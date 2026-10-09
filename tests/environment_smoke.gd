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
	# Earlier suites may save Battery Saver in the shared isolated test profile.
	root.get_node("GameSettings").call("update_setting","quality",0)
	root.get_node("Stats").set("enabled", false)
	var starting_buses := AudioServer.bus_count
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	# Each field has a 0.5 ms share; diagnostics observed 1,720 render frames
	# through all rays/filling on a busy desktop. Wait on actual readiness.
	for frame in range(2400):
		await process_frame
		if current_scene.get_node_or_null("Island/IslandGrass/GrassField") != null:
			break
	for frame in range(360):
		if current_scene.get_node_or_null("Island/CropSeedCache_Tomato") != null:
			break
		await physics_frame
	check(current_scene.get_node_or_null("Island/CropSeedCache_Carrot") != null and current_scene.get_node_or_null("Island/CropSeedCache_Tomato") != null, "Home seed caches wait for terrain preparation rather than mountain collision")
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
	# Load after autoloads exist; resolving Planter while compiling this entry
	# script also compiles PlantInstance before Inventory is registered.
	var test_pot := (load("res://scenes/planter_pot.tscn") as PackedScene).instantiate()
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
	if leaf_mesh != null:
		var leaf_material := leaf_mesh.get_surface_override_material(0) as ShaderMaterial
		check(leaf_material != null and leaf_material.get_shader_parameter("use_albedo_texture") == true \
			and leaf_material.get_shader_parameter("albedo_texture") is Texture2D,
			"Imported palm keeps its real frond texture with wind animation")
	var imported_palms := 0
	var colliders_ok := true
	for island_name in ["Island", "ReefIsle", "DriftwoodCay", "FarCove"]:
		var destination := current_scene.get_node(island_name)
		for palm in destination.get_children():
			if not str(palm.name).begins_with("Palm"):
				continue
			var model := palm.get_node_or_null("CoconutPalmModel")
			if model == null:
				continue
			imported_palms += 1
			colliders_ok = colliders_ok and model.find_child("Tree_0_Trunk_Body", true, false) is StaticBody3D \
				and model.find_child("leafs_Body", true, false) == null
	check(imported_palms == 31, "All home and destination palms use the supplied coconut GLB")
	check(colliders_ok, "Imported trunks collide while textured fronds stay visual-only")
	var first_trunk := island.get_node("PalmTree").find_child("Tree_0_Trunk_Body", true, false) as StaticBody3D
	var second_trunk := island.get_node("PalmTree2").find_child("Tree_0_Trunk_Body", true, false) as StaticBody3D
	check((first_trunk.get_child(0) as CollisionShape3D).shape == (second_trunk.get_child(0) as CollisionShape3D).shape,
		"Repeated palms reuse one cooked collision shape with independent body transforms")
	var field := island.get_node_or_null("IslandGrass/GrassField") as MultiMeshInstance3D
	check(field != null and field.multimesh.mesh.get_faces().size() == 72, "Realistic grass GLB stays within its 24-triangle tuft budget")
	if field == null:
		for node in current_scene.find_children("IslandGrass","",true,false):
			print("GRASS DIAGNOSTIC: ",node.get_path()," ",node._prepare_phase," ",node._prepare_progress)
		quit(1)
		return
	var grass_material := field.material_override as ShaderMaterial
	check(island.get_node("IslandGrass").get("_using_imported_model") == true \
		and grass_material.get_shader_parameter("use_albedo_texture") == true \
		and grass_material.get_shader_parameter("albedo_texture") is Texture2D,
		"Grass field uses the supplied textured GLB rather than the procedural fallback")
	var grass_bounds := field.multimesh.mesh.get_aabb()
	check(absf(grass_bounds.position.y) < 0.001 and absf(grass_bounds.size.y - 0.38) < 0.001,
		"Imported grass roots stay grounded at a natural 0.38 m tuft height")
	check(field.multimesh.use_custom_data and field.visibility_range_end == 100.0, "Grass variation stays batched and has a distance limit")
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	root.get_node("GameSettings").call("update_setting", "quality", 1)
	var material := (ocean as MeshInstance3D).get_active_material(0) as ShaderMaterial
	check(float(material.get_shader_parameter("surface_detail")) < 0.6, "Battery Saver skips the second water-detail layer")
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "Battery Saver avoids extra anti-aliasing samples")
	check(field.multimesh.visible_instance_count <= 800 and field.visibility_range_end == 55.0,
		"Battery Saver bounds grass density and draw distance")
	root.get_node("GameSettings").call("update_setting", "quality", 2)
	check(float(material.get_shader_parameter("surface_detail")) > 0.6, "Balanced restores richer water detail")
	check(root.msaa_3d == Viewport.MSAA_2X, "Balanced smooths fine foliage edges")
	check(field.multimesh.visible_instance_count <= 1600 and field.visibility_range_end == 100.0,
		"Balanced restores grass without regenerating the field")
	var old_field_id := field.get_instance_id()
	performance.set("_foliage_reduced", true)
	performance.call("refresh_foliage")
	check(field.multimesh.visible_instance_count <= 1040 and field.get_instance_id() == old_field_id,
		"Sustained slowdown reduces foliage without allocations or ground queries")
	performance.set("_foliage_reduced", false)
	performance.call("refresh_foliage")
	var tree_pot := (load("res://scenes/tree_pot.tscn") as PackedScene).instantiate()
	tree_pot.position = Vector3(410, -20, 400)
	current_scene.add_child(tree_pot)
	tree_pot.restore_plant_state({"id": "Coconut", "stage": 3, "health": 4, "timer": 0.0})
	var planted := tree_pot.find_child("CoconutPalm", true, false)
	check(planted != null and planted.find_child("Tree_0_Trunk", true, false) is MeshInstance3D,
		"Legacy mature coconut state now displays the supplied realistic palm")
	var plant_state: Dictionary = tree_pot.save_plant_state()
	check(plant_state.get("health") == 4 and plant_state.get("fruits", []).size() == 4,
		"Realistic planter tree preserves saved chopping health and fruit slots")
	tree_pot.queue_free()
	root.get_node("GameSettings").call("update_setting", "quality", 0)
	performance.call("_set_render_scale", 1.0)
	for sample in range(5):
		performance.call("_update_quality", 0.01)
	check(performance.get("_cumulus_reduced") == true,
		"Mobile Auto recovery never silently enables expensive volumetric clouds")
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
