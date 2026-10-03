extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	var starting_buses := AudioServer.bus_count
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for frame in range(600):
		await physics_frame
		if current_scene.get_node_or_null("Island/IslandGrass/GrassField") != null:
			break
	var ambience := current_scene.get_node("OceanAmbience")
	var player := get_first_node_in_group("player") as Node3D
	var mountain := current_scene.get_node_or_null("Island/IslandMountain") as Node3D
	var mountain_mesh: MeshInstance3D = null
	if mountain != null:
		mountain_mesh = mountain.find_child("CraggyRockMesh", true, false) as MeshInstance3D
	check(mountain_mesh != null and mountain_mesh.mesh != null \
		and mountain.get_node_or_null("MountainCollision") is StaticBody3D,
		"Home island has one generated craggy peak and matching collider")
	var birds := current_scene.get_node_or_null("Island/IslandBirds")
	check(birds != null and birds.get_child_count() == 4, "Home island has a small, non-colliding gull flock")
	var footprints := current_scene.get_node_or_null("SandFootprints") as Node3D
	var decal_pool: Array = []
	if footprints != null:
		decal_pool = footprints.get("_decals")
	check(footprints != null and decal_pool.size() == 28,
		"Sand prints use a bounded reusable decal pool")
	if footprints != null:
		footprints.call("stamp", Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
		decal_pool = footprints.get("_decals")
		check(decal_pool.size() == 28 and (decal_pool[0] as MeshInstance3D).visible,
			"Footstep stamp activates an impression without adding physics")
	var test_pot := (load("res://scenes/planter_pot.tscn") as PackedScene).instantiate() as Planter
	test_pot.position = Vector3(400.0, -20.0, 400.0)
	current_scene.add_child(test_pot)
	check(test_pot.add_sand() and test_pot.has_sand() \
		and test_pot.get_node_or_null("AppliedBeachSand") is MeshInstance3D,
		"A sand scoop visibly top-dresses a planter")
	test_pot.queue_free()
	player.set_physics_process(false)
	var camera := root.get_camera_3d()
	var ocean := get_first_node_in_group("ocean") as Node3D
	var island := current_scene.get_node("Island") as Node3D
	check(AudioServer.bus_count == starting_buses + 1, "Environment owns one bus, not one bus per sound")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(ambience.get("_bus_name"))) == &"Master", "Settings volume/mute still controls ambience")
	check(ambience.call("shoreline_factor", island.global_position) > 0.99, "Island approach enables leaf and shore ambience")
	check(ambience.call("shoreline_factor", Vector3(450, 3, 450)) < 0.01, "Open water does not play close-up leaf rustle")
	for label in ["SeaWind", "FoliageRustle"]:
		var layer := ambience.get_node(label) as AudioStreamPlayer
		var audio := layer.stream as AudioStreamWAV
		check(audio != null and audio.stereo and audio.get_length() >= 12.0, label + " has a real stereo sample bed")
		check(audio.loop_mode == AudioStreamWAV.LOOP_FORWARD and audio.loop_end > 0, label + " loops continuously")
	var rain := player.get_node("RainSystem")
	check(rain.get("rain_sound") != null, "Rain now has an audible default")
	var rain_audio := rain.get_node("RainAudio") as AudioStreamPlayer
	check(rain_audio.bus == ambience.get("_bus_name"), "Rain shares underwater environment filtering")
	var original_camera := camera.global_transform
	camera.global_position = island.global_position + Vector3(0, 4, 0)
	for frame in range(40):
		ambience.call("_process", 0.1)
	check((ambience.get_node("FoliageRustle") as AudioStreamPlayer).volume_db > -26.0, "Near-island foliage fades into the mix")
	camera.global_position = Vector3(450, -1.5, 450)
	for frame in range(40):
		ambience.call("_process", 0.1)
	check(float(ambience.get("_under_mix")) > 0.99, "Submerged camera transitions to underwater ambience")
	check((ambience.get("_low_pass") as AudioEffectLowPassFilter).cutoff_hz < 1000.0, "Underwater high frequencies are muffled")
	camera.global_position.y = 5.0
	for frame in range(40):
		ambience.call("_process", 0.1)
	check((ambience.get("_low_pass") as AudioEffectLowPassFilter).cutoff_hz > 17000.0, "Surfacing restores clear sound")
	camera.global_transform = original_camera
	var leaf_mesh := island.get_node("PalmTree").find_child("leafs", true, false) as MeshInstance3D
	check(leaf_mesh != null and leaf_mesh.get_surface_override_material(0) is ShaderMaterial, "Island palm fronds receive animated natural materials")
	var field := island.get_node_or_null("IslandGrass/GrassField") as MultiMeshInstance3D
	check(field != null and field.multimesh.mesh.get_faces().size() == 72, "Grass grows as three tapered curved blades per instance")
	if field == null:
		quit(1)
		return
	check(field.multimesh.use_custom_data and field.visibility_range_end == 100.0, "Grass variation stays batched and has a distance limit")
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	root.get_node("GameSettings").call("update_setting", "quality", 1)
	var material := ((ocean as MeshInstance3D).mesh as PlaneMesh).material as ShaderMaterial
	check(float(material.get_shader_parameter("surface_detail")) < 0.6, "Battery Saver skips the second water-detail layer")
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "Battery Saver avoids extra anti-aliasing samples")
	root.get_node("GameSettings").call("update_setting", "quality", 2)
	check(float(material.get_shader_parameter("surface_detail")) > 0.6, "Balanced restores richer water detail")
	check(root.msaa_3d == Viewport.MSAA_2X, "Balanced smooths fine foliage edges")
	ambience.call("stop_environment")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	# Do not terminate while the menu's background scene preloader is parsing.
	for frame in range(900):
		if current_scene.get("_packed_game") != null:
			break
		await process_frame
	check(current_scene.get("_packed_game") != null, "Menu can preload gameplay again after environment teardown")
	await create_timer(0.1).timeout
	check(AudioServer.bus_count == starting_buses, "Leaving gameplay removes the scene-owned audio bus")
	print("ENVIRONMENT SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
