extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("FAIL: world visuals timed out"); quit(1))
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)
	else: print("PASS: "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset",true)
	var layout := load("res://scripts/island_layout.gd")
	check(layout.version({}) == 1 and layout.version({"health":70}) == 0,"New voyages use distant islands and legacy saves retain coordinates")
	check(layout.version({"health":70,"island_layout":1}) == 1,"Distant world selection survives Continue")
	var legacy := Node3D.new()
	legacy.name = "Island"
	legacy.position = Vector3(85,0,-165)
	layout.apply(legacy,{"health":70})
	check(legacy.position == Vector3(85,0,-165),"Applying a legacy layout never relocates its home island")
	legacy.free()
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var player := get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	root.get_node("Stats").enabled = false
	for frame in range(700):
		await physics_frame
		var ready := true
		for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
			ready = ready and current_scene.get_node(name+"/CoastalGrove").get_child_count() == 8
		if ready: break
	for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
		var island := current_scene.get_node(name) as Node3D
		check(Vector2(island.position.x,island.position.z).length() >= 620,"Open ocean distance for "+name)
		var grove := island.get_node("CoastalGrove")
		check(grove.get_child_count() == 8,"Bounded eight-tree grove on "+name)
		var banana := grove.get_node("Banana0")
		check(banana.find_child("BananaPlantModel",true,false) != null and banana.get("_fruits").size() > 0,"Supplied banana model has real harvesting slots on "+name)
		check(not banana.is_processing(),"Distant island plants sleep outside interaction range")
	var tree_visual := load("res://scripts/coastal_tree_visual.gd")
	var a: Node3D = tree_visual.create(0)
	var b: Node3D = tree_visual.create(0)
	check(a.get_child(1).mesh == b.get_child(1).mesh and a.get_child(1).material_override == b.get_child(1).material_override,"Repeated foliage shares cached meshes and materials")
	check(a.get_child(1).mesh.get_faces().size() < 2000 and a.get_child(1).visibility_range_end == 120,"Banana triangles and foliage distance stay bounded")
	a.free()
	b.free()
	var grove := current_scene.get_node("Island/CoastalGrove")
	var banana := grove.get_node("Banana0")
	banana.call("restore_state",{"id":"Banana","stage":3,"health":2,"timer":0.0})
	var state: Dictionary = grove.call("save_state")
	check(state.Banana0.health == 2 and state.Banana0.fruits.size() > 0,"Grove state preserves chopping damage and fruit progression")
	player.set("cam_mode",1)
	player.call("_apply_camera_mode")
	var gun: Node3D = player.get("_third_person_launcher")
	var grip := gun.get_node("AnimatedHandGrip")
	var rig: Skeleton3D = grip.get("skeleton")
	check(rig != null and int(grip.get("wrist")) >= 0,"Third-person launcher resolves the animated right wrist")
	for i in range(5): await process_frame
	# Headless does not schedule every rendered skeleton modifier. Sample the
	# follower explicitly before comparing the same current wrist pose.
	grip.call("_process",0.0)
	var bone := int(grip.get("wrist"))
	var wrist: Transform3D = rig.global_transform*rig.get_bone_global_pose(bone)
	check(gun.global_position.distance_to(wrist.origin) < 0.20,"Launcher stays within the real hand rather than the torso")
	var original := gun.global_position
	player.position.x += 4
	grip.call("_process",0)
	check(absf(gun.global_position.x-original.x-4) < 0.02,"Grip follows player movement without detaching")
	check(player.get("_rope_launcher").get_node_or_null("WrappedFingers") != null,"First-person fingers wrap the pistol grip")
	player.call("_write_save","quick")
	inv.call("load_game","quick")
	check(inv.loaded_meta.island_layout == 1 and inv.loaded_meta.island_groves.Island.Banana0.health == 2,"World layout and tree state round-trip through a real save")
	banana.queue_free()
	await process_frame
	check(grove.call("save_state").Banana0.get("removed",false),"Removed island trees retain a save tombstone rather than respawning on Continue")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for i in range(20): await process_frame
	print("WORLD VISUAL SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
