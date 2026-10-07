extends SceneTree
var checks := 0
var failures := 0
var player: Node3D
var raft: Node3D
var inv: Node
var built: Node3D
const STORAGE := preload("res://scripts/save_storage.gd")
const ROOF := preload("res://scripts/smart_roof.gd")

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("FAIL: overhaul timed out"); quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func frames(count: int = 3) -> void:
	for unused in count: await physics_frame

func put(path: String, text: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()

func fixture(kind: String, position: Vector3, yaw: float = 0.0) -> Node3D:
	var index: int = player.BUILD_RECIPE_NAMES.find(kind)
	var piece: Node3D = player.build_pieces[index].instantiate()
	piece.name = "%s_Test_%d" % [kind,piece.get_instance_id()]
	piece.transform = Transform3D(Basis(Vector3.UP,yaw),position)
	built.add_child(piece)
	piece.add_to_group("build_surface")
	return piece

func aim_at(local: Vector3, support: Node3D) -> void:
	var point: Vector3 = raft.to_global(local)
	player.global_position = point + Vector3(0,1,3)
	var camera: Camera3D = player.camera
	camera.global_position = point + Vector3(0,3,3)
	camera.look_at(point)
	player.set("aim_valid",true)
	player.set("aim_collider",support)
	player.set("aim_point",point)
	player.set("aim_normal",Vector3.UP)
	player.call("_update_build_preview")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	inv = root.get_node("Inventory")
	inv.call("new_game_reset",true)
	var legacy := {"version":1,"slots":[["Wood",37]],"health":81,"built":[]}
	put("user://raft_save.json",JSON.stringify(legacy))
	inv.call("load_game")
	check(inv.call("total","Wood") == 37 and inv.loaded_meta.health == 81,"Legacy plaintext inventory and world meta load")
	check(inv.call("save_game",{"health":81}),"Legacy save migrates through a verified atomic write")
	check(FileAccess.get_file_as_string("user://raft_save.json").contains(STORAGE.FORMAT) and not FileAccess.get_file_as_string("user://raft_save.json").contains("health"),"AES envelope contains no plaintext world fields")
	var first := FileAccess.get_file_as_bytes("user://raft_save.json")
	check(inv.call("save_game",{"health":81}) and FileAccess.get_file_as_bytes("user://raft_save.json") != first,"Fresh IV makes repeated encrypted saves distinct")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://raft_save.json"))
	envelope.mac = Marshalls.raw_to_base64(PackedByteArray([1,2,3]))
	put("user://raft_save.json",JSON.stringify(envelope))
	check(inv.call("save_info").get("health") == 81,"Authentication failure recovers previous valid backup")
	check(inv.call("save_game",{"health":82}),"Recovery commits a valid primary without rotating corruption over backup")
	var primary := FileAccess.get_file_as_bytes("user://raft_save.json")
	var key := FileAccess.get_file_as_bytes(STORAGE.KEY_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORAGE.KEY_PATH))
	var old_slots: Array = inv.slots.duplicate(true)
	var old_meta: Dictionary = inv.loaded_meta.duplicate(true)
	check(inv.call("load_game").is_empty() and inv.slots == old_slots and inv.loaded_meta == old_meta,"Lost save key preserves live inventory and world state")
	check(not inv.call("save_game") and FileAccess.get_file_as_bytes("user://raft_save.json") == primary,"Lost key cannot overwrite encrypted save")
	var key_file := FileAccess.open(STORAGE.KEY_PATH,FileAccess.WRITE)
	key_file.store_buffer(key)
	key_file.close()
	check(inv.call("save_info").get("health") == 82,"Restoring the original key recovers the encrypted primary")
	check(not STORAGE.write("user://missing-folder/save.json",legacy),"File creation failure reports a failed save")
	inv.call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player = get_first_node_in_group("player") as Node3D
	raft = get_first_node_in_group("raft") as Node3D
	built = raft.get_node("BuiltPieces")
	player.set_physics_process(false)
	player.set_process(false)
	raft.set_physics_process(false)
	root.get_node("Stats").enabled = false
	for unused in range(700):
		await physics_frame
		var ready := true
		for node in current_scene.find_children("IslandSetup", "", true, false):
			ready = ready and node.get("setup_complete")
		if ready and unused > 50: break
	var valid := [1,0,0,0,1,0,0,0,1,2,0,2]
	check(player.call("_valid_saved_transform",valid),"Normal legacy transforms remain valid")
	var bad := valid.duplicate(); bad[9] = NAN
	check(not player.call("_valid_saved_transform",bad),"NaN building positions are rejected")
	bad[9] = INF
	check(not player.call("_valid_saved_transform",bad),"Infinite building positions are rejected")
	check(not player.call("_valid_saved_transform",[0,0,0,0,0,0,0,0,0,0,0,0]),"Singular building bases are rejected")
	check(player._survivor_animator.has_animation("Survival/Swim"),"Existing rig gains a blended swimming clip")
	check(is_equal_approx(player.camera.fov,75) and is_equal_approx(player.camera.near,0.1),"Camera uses the survival viewing angle and near clip")
	player.call("select_piece_for_build",0)
	var before_wood: int = inv.call("total","Wood")
	for z in range(8):
		for x in range(8):
			if x == 0 and z == 0: continue
			var cell := Vector2i(x,z)
			var neighbor := Vector2i(x-1,z) if x > 0 else Vector2i(x,z-1)
			var support: Node3D = raft if neighbor == Vector2i.ZERO else player._grid_occupancy[neighbor]
			aim_at(Vector3(x*2.0,0.15,z*2.0),support)
			if not player.build_valid: print("STRESS PREVIEW ",cell," ",player._diag)
			player.call("_try_build")
			await frames(1)
	check(built.get_child_count() == 63,"63 foundations placed through real grid validation and costs")
	check(inv.call("total","Wood") == before_wood-315,"Stress construction spends exactly 315 wood")
	raft.get_node("ConstructionBatch").call("refresh")
	check(raft.get_node("ConstructionBatch").get_child_count() <= 5,"63 foundations share at most five timber/rope/hardware draws")
	var f1: Node3D = player._grid_occupancy[Vector2i(1,1)]
	var f2: Node3D = player._grid_occupancy[Vector2i(2,1)]
	for position in [Vector3(2,1.4,1),Vector3(4,1.4,1),Vector3(2,1.4,3),Vector3(4,1.4,3)]: fixture("Wall",position)
	fixture("Wall",Vector3(1,1.4,2),PI/2)
	var window := fixture("Window",Vector3(5,1.4,2),PI/2)
	await frames()
	check(window.find_child("Glass",true,false) == null and window.find_child("JoinedWoodenShutter",true,false) != null,"Window uses a joined wooden shutter and contains no glass")
	var door := fixture("Door",Vector3(30,1.4,30))
	check(door.get_node("LeafPivot/Leaf").mesh is ArrayMesh,"Door leaf uses real rounded timber geometry")
	door.call("toggle")
	await frames(50)
	check(door.is_open and absf(door.get_node("LeafPivot").rotation.y)>1.3,"Rounded timber door still swings on its original hinge")
	door.queue_free()
	await frames()
	var plan := ROOF.plan(raft,raft.to_global(Vector3(2,0.15,2)))
	check(plan.get("room",false) and plan.transforms.size() == 2,"Six wall/window segments enclose a two-tile room")
	var yaw_before: Transform3D = raft.transform
	raft.rotation.y = 0.73
	var yaw_plan := ROOF.plan(raft,raft.to_global(Vector3(2,0.15,2)))
	check(yaw_plan.transforms.size() == 2 and (raft.to_local(yaw_plan.transforms[0].origin)-Vector3(2,2.725,2)).length() < 0.001,"Room snapping remains exact on a rotated raft")
	raft.transform = yaw_before
	player.call("select_piece_for_build",2)
	aim_at(Vector3(2,0.15,2),f1)
	check(player.build_valid and player._smart_roof_plan.transforms.size() == 2,"One green ceiling preview covers the entire room")
	var saved_wood: int = inv.call("total","Wood")
	inv.call("remove","Wood",saved_wood-3)
	var pieces_before := built.get_child_count()
	player.call("_try_build")
	check(built.get_child_count() == pieces_before and inv.call("total","Wood") == 3,"Insufficient room materials create no partial roof and spend nothing")
	inv.call("add","Wood",saved_wood-3)
	var ropes_before: int = inv.call("total","Rope")
	player.call("_try_build")
	await frames()
	check(built.get_child_count() == pieces_before+2 and inv.call("total","Wood") == saved_wood-16 and inv.call("total","Rope") == ropes_before-2,"Room roof places two tiles with exact transactional cost")
	check(ROOF.plan(raft,raft.to_global(Vector3(2,0.15,2))).get("occupied",false),"Existing roofs cannot be charged or duplicated")
	window.call("toggle")
	await create_timer(0.55).timeout
	check(window.is_open and absf(window.get_node("Hinge").rotation.y) > 1.4,"Window sash and its collider swing open")
	player.call("select_piece_for_build",16)
	var half_support: Node3D = player._grid_occupancy[Vector2i(6,6)]
	aim_at(Vector3(12,0.15,12.99),half_support)
	check(player.build_valid,"Half wall uses the existing automatic edge alignment")
	var half_count := built.get_child_count()
	var half_cost: int = inv.call("total","Wood")
	player.call("_try_build")
	await frames()
	var half := built.find_child("HalfWall_*",false,false) as Node3D
	check(half != null and built.get_child_count() == half_count+1 and inv.call("total","Wood") == half_cost-4,"Half wall places through normal cost and touch-compatible building path")
	check(half.get_node("CollisionShape3D").shape.size.y == 1.25,"Half wall keeps its true 1.25 metre collider")
	player.call("select_piece_for_build",17)
	var cargo_support: Node3D = player._grid_occupancy[Vector2i(6,5)]
	aim_at(Vector3(12,0.15,10),cargo_support)
	check(player.build_valid,"Cargo crate snaps to a supported raft tile")
	var cargo_wood: int = inv.call("total","Wood")
	player.call("_try_build")
	await frames()
	var cargo := built.find_child("CargoCrate_*",false,false)
	check(cargo != null and inv.call("total","Wood") == cargo_wood-6,"Craftable cargo crate spends its real material cost")
	if cargo != null:
		check(cargo.find_child("HempRopeCoil",true,false) != null and cargo.find_child("CargoNet",true,false) != null,"Crate includes batched rope coil and draped cargo net")
	var snapshot: Array = player.call("_serialize_built_pieces")
	check(snapshot.any(func(record): return record.t == "HalfWall"),"Half walls save their distinct scene identity")
	check(snapshot.any(func(record): return record.t == "Window" and record.survival.open),"Open window state is persisted")
	check(snapshot.any(func(record): return record.t == "CargoCrate"),"Cargo prop persists through the ordinary build save path")
	player._editing = half
	player.call("_set_edit_color",StandardMaterial3D.new())
	player.call("_apply_building_color",half)
	check(half.get_node("MeshInstance3D").get_surface_override_material(0) == null,"Leaving edit highlight restores the true timber material")
	player._editing = null
	var invalid_record := {"t":"Wall","x":[0,0,0,0,0,0,0,0,0,0,0,0]}
	for piece in built.get_children(): piece.queue_free()
	await frames(6)
	inv.loaded_meta["built"] = snapshot+[invalid_record]
	player._grid_occupancy = {Vector2i.ZERO:raft}
	player.call("_restore_built_pieces")
	await frames(4)
	check(built.get_child_count() == snapshot.size(),"70-plus mixed structures restore while invalid records are skipped")
	var restored_window := built.find_child("Window_*",false,false)
	check(restored_window != null and restored_window.is_open,"Restored window retains its open hinge")
	var clock := current_scene.get_node("Sky3D/TimeOfDay")
	clock.current_time = 12
	var generator := fixture("WindGenerator",Vector3(2,0.8,2))
	var lamp := fixture("ElectricLamp",Vector3(2,0.8,3))
	generator.set_process(false); lamp.set_process(false); generator.charge = 10
	lamp.call("advance",1)
	check(not lamp.get("_light").visible and generator.charge == 10,"Automatic lamp saves battery during daylight")
	clock.current_time = 22
	lamp.call("advance",1)
	check(lamp.get("_light").visible and is_equal_approx(generator.charge,9.92),"Automatic lamp lights at night and charges normal power cost")
	check(clock.minutes_per_day == 24.0,"Default day/night cycle takes 24 real minutes")
	# Warm caches, then repeated >50-object batches must return to the same node
	# and resource counts. Shared static caches are bounded and intentionally live.
	for piece in built.get_children(): piece.queue_free()
	await frames(20)
	raft.get_node("ConstructionBatch").call("refresh")
	await frames(5)
	# Stop unrelated world spawners/AI before measuring construction retention.
	for node in current_scene.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		if node is Timer: node.stop()
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var baseline_resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	for cycle in range(3):
		for index in range(64): fixture("Wall",Vector3(index*2.0,1.4,30))
		raft.get_node("ConstructionBatch").call("refresh")
		check(raft.get_node("ConstructionBatch").get_child_count() <= 4,"64-wall batch keeps shared draws bounded, cycle %d" % cycle)
		for piece in built.get_children(): piece.queue_free()
		await frames(20)
		raft.get_node("ConstructionBatch").call("refresh")
		await frames(5)
		print("STRESS RETENTION cycle %d nodes %d -> %d resources %d -> %d" % [cycle,baseline_nodes,Performance.get_monitor(Performance.OBJECT_NODE_COUNT),baseline_resources,Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
		check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) <= baseline_nodes+2,"Removed 64-wall batch releases nodes, cycle %d" % cycle)
		check(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)) <= baseline_resources+4,"Removed 64-wall batch releases per-instance resources, cycle %d" % cycle)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	await frames(20)
	print("VISUAL BUILD OVERHAUL SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
