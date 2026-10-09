extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("FAIL: island visuals timed out"); quit(1))
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.get_node("Inventory").call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var player := get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	root.get_node("Stats").enabled = false
	for frame in range(1200):
		await process_frame
		var ready := true
		for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
			ready = ready and current_scene.get_node(name+"/IslandLandscape").landscape_ready
		if ready: break
	var reference_material: Material
	for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
		var island := current_scene.get_node(name) as Node3D
		var landscape := island.get_node("IslandLandscape")
		check(landscape.landscape_ready, name + " finishes bounded landscape/shore preparation")
		var setup := island.get_node_or_null("IslandSetup")
		if setup == null: setup = current_scene.get_node("IslandSetup")
		check(setup.get("_terrain_mats").size() > 0, name + " receives its sand material even after imported trees are installed")
		var anchor := island.get_node("IslandBeacon")
		check(anchor.get_child_count() == 0 and anchor.is_in_group("island_beacon"), name + " keeps navigation without glowing pillar, orb or light")
		var dry_palms := true
		var grounded_palms := true
		var exclude: Array[RID] = []
		for palm in island.get_children():
			if not str(palm.name).begins_with("Palm"): continue
			for body in palm.find_children("*","StaticBody3D",true,false): exclude.append(body.get_rid())
		for palm in island.get_children():
			if not str(palm.name).begins_with("Palm"): continue
			dry_palms = dry_palms and palm.global_position.y >= 0.42
			var from_position: Vector3 = palm.global_position + Vector3.UP * 0.12
			var palm_hit: Dictionary = current_scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from_position,from_position + Vector3.DOWN * 0.3,1,exclude))
			grounded_palms = grounded_palms and not palm_hit.is_empty()
		check(dry_palms and grounded_palms, name + " palms root on actual dry land")
		var mountain := island.get_node("IslandMountain")
		var collision := mountain.get_node("MountainCollision")
		check(collision.get_child_count() == 3, name + " has three matching solid rock headlands")
		var visual := mountain.get_node("CraggyRockMesh") as MeshInstance3D
		var material := visual.material_override as ShaderMaterial
		if reference_material == null: reference_material = material
		check(material == reference_material and material.get_shader_parameter("rock_albedo") is Texture2D
			and material.get_shader_parameter("rock_normal") is Texture2D, name + " reuses one photographic PBR rock material")
		for index in range(3):
			var rock := mountain.get_node("CraggyRockMesh" if index == 0 else "RockHeadland%d" % index) as MeshInstance3D
			var shape := collision.get_child(index) as CollisionShape3D
			check(shape.transform.is_equal_approx(rock.transform)
				and shape.shape is ConcavePolygonShape3D, name + " rock " + str(index) + " collision matches its baked visible mesh")
		var from := island.to_global(Vector3(0,22,5))
		var hit: Dictionary = current_scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,from + Vector3.DOWN * 45,1))
		check(not hit.is_empty(), name + " approach beach still has usable solid ground")
		var foliage := 0
		for part in landscape.get_node("WildPlants").get_children():
			if part is MultiMeshInstance3D and part.is_in_group("island_landscape_foliage"):
				foliage += 1
				check(part.multimesh.instance_count <= 64, name + " vegetation batch stays bounded")
		check(foliage == 8, name + " owner kit uses eight shared batches / ten material draws")
	var ocean := get_first_node_in_group("ocean")
	var water := (ocean as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var zones: PackedVector4Array = water.get_shader_parameter("island_shores")
	check(zones.size() == 6 and zones[0].z > 0 and zones[3].z > 0,"Original four shore masks retain their slots beside two new biomes")
	for index in range(4):
		var texture: Texture2D = water.get_shader_parameter("shore_height_" + str(index))
		check(texture != null and texture.get_width() == 32 and texture.get_height() == 32,"Shore " + str(index) + " uses a compact 32-square height texture")
	var home := current_scene.get_node("Island")
	check(home.get_node_or_null("CropSeedCache_Carrot") != null and home.get_node_or_null("CropSeedCache_Tomato") != null,"Essential crop pickups still prepare on the home island")
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile",true)
	root.get_node("GameSettings").call("update_setting","quality",1)
	var reduced := true
	for part in get_nodes_in_group("island_landscape_foliage"):
		reduced = reduced and part.multimesh.visible_instance_count == part.multimesh.instance_count and part.visibility_range_end == 55.0
	check(reduced,"Battery Saver limits interactive plants to 55 metres without invisible trunks")
	check(float(water.get_shader_parameter("surface_detail")) < 0.6,"Battery Saver retains its cheaper ocean detail")
	root.get_node("GameSettings").call("update_setting","quality",2)
	check(zones == water.get_shader_parameter("island_shores"),"Quality changes retain the prepared shore masks")
	var camera := root.get_camera_3d()
	var original_camera := camera.global_position
	var sample := Vector3(50,0,50)
	var height_before := float(ocean.call("get_height",sample))
	camera.global_position += Vector3(850,0,650)
	ocean.call("_process",0.0)
	check(Vector2(ocean.global_position.x,ocean.global_position.z).distance_to(Vector2(camera.global_position.x,camera.global_position.z)) < 0.01,"Dense ocean follows the active view at distant islands")
	check(is_equal_approx(height_before,float(ocean.call("get_height",sample))),"Ocean recentering preserves world-space buoyancy heights")
	camera.global_position = original_camera
	ocean.call("_process",0.0)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for frame in range(25): await process_frame
	print("ISLAND VISUAL SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
