extends SceneTree

var checks := 0
var failures := 0
var player: Node
var raft: Node3D
var inventory: Node
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func aim_at(cell: Vector2i, support: Node3D) -> void:
	var target: Transform3D = player.call("_compute_foundation_transform", cell)
	camera.global_position = target.origin + Vector3(0, 3, 3)
	camera.look_at(target.origin + Vector3(0, 0.15, 0))
	player.set("aim_valid", true)
	player.set("aim_collider", support)
	player.set("aim_point", target.origin + Vector3(0, 0.15, 0))
	player.set("aim_normal", Vector3.UP)
	player.call("_update_build_preview")

func press_p() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.keycode = KEY_P
	event.pressed = true
	Input.parse_input_event(event)
	player.call("_poll_gameplay_actions")
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	Input.use_accumulated_input = false
	root.size = Vector2i(1280, 720)
	inventory = root.get_node("Inventory")
	inventory.call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for frame in range(4):
		await process_frame
	player = get_first_node_in_group("player")
	raft = get_first_node_in_group("raft") as Node3D
	# Freeze motion so comparisons verify the exact preview cell and transform.
	player.set_process(false)
	player.set_physics_process(false)
	raft.set_physics_process(false)
	camera = player.get("camera") as Camera3D
	inventory.call("remove", "Wood", inventory.call("total", "Wood"))
	inventory.call("add", "Wood", 15)
	player.call("_toggle_build")
	var container := raft.get_node("BuiltPieces")
	var before_count := container.get_child_count()
	# Reproduce legacy/custom support with valid grid support and no edge socket.
	var socket_types: Array[int] = []
	for socket in raft.get_node("BuildSockets").get_children():
		socket_types.append(socket.get("socket_type"))
		socket.set("socket_type", 2)
	aim_at(Vector2i(1, 0), raft)
	check(player.get("build_valid") and player.get("_ghost_target_socket") == null, "Grid preview is valid without optional edge socket metadata")
	var preview: Transform3D = player.get("_ghost_transform")
	press_p()
	check(container.get_child_count() == before_count + 1, "P places a green foundation without socket metadata")
	check(inventory.call("total", "Wood") == 10, "P spends exactly five wood")
	var first: Node3D = container.get_child(before_count)
	check(first.global_position.distance_to(preview.origin) < 0.001, "Placed foundation matches the preview position")
	check(player.get("_grid_occupancy").get(Vector2i(1, 0)) == first, "Placed foundation occupies its preview grid cell")
	for index in range(socket_types.size()):
		raft.get_node("BuildSockets").get_child(index).set("socket_type", socket_types[index])
	await process_frame
	await physics_frame
	await process_frame
	aim_at(Vector2i(0, 1), raft)
	check(player.get("build_valid") and player.get("_ghost_target_socket") != null, "Ordinary raft edge has a green connected preview")
	preview = player.get("_ghost_transform")
	var controls: Control = player.get_node("CanvasLayer/MobileControls")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	controls.call("_apply_viewport_size")
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	var place: Button = controls.get("_btn_place")
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = place.get_global_rect().get_center()
	root.push_input(down, true)
	player.call("_poll_gameplay_actions")
	var up := down.duplicate() as InputEventScreenTouch
	up.pressed = false
	root.push_input(up, true)
	check(container.get_child_count() == before_count + 2, "Mobile PLACE builds a foundation through viewport touch routing")
	check(inventory.call("total", "Wood") == 5, "Mobile PLACE spends exactly five wood")
	if container.get_child_count() != before_count + 2:
		quit(1)
		return
	check((container.get_child(before_count + 1) as Node3D).global_position.distance_to(preview.origin) < 0.001, "Mobile foundation matches its preview position")
	await process_frame
	await physics_frame
	await process_frame
	aim_at(Vector2i(2, 0), first)
	check(player.get("build_valid"), "Expansion can connect to an existing foundation")
	press_p()
	check(container.get_child_count() == before_count + 3 and inventory.call("total", "Wood") == 0, "P extends the raft with a third foundation and normal costs")
	await process_frame
	await physics_frame
	await process_frame
	aim_at(Vector2i(3, 0), container.get_child(before_count + 2))
	press_p()
	check(container.get_child_count() == before_count + 3, "Insufficient materials cannot create a free foundation")
	var hud := player.get_node("CanvasLayer/SurvivalHUD")
	check(hud.get("_toast") == "NEED 5 Wood", "Insufficient materials show the exact shortage")
	inventory.call("add", "Wood", 5)
	player.set("build_valid", false)
	player.set("_diag", {"invalid_reason": "OVERLAP"})
	player.call("_try_build")
	check(container.get_child_count() == before_count + 3 and inventory.call("total", "Wood") == 5, "Invalid placement preserves both buildings and materials")
	check(str(hud.get("_toast")).contains("OVERLAP"), "Invalid placement explains why it was rejected")
	player.call("quick_save")
	check(not (inventory.call("load_game", "quick") as Dictionary).is_empty(), "Placed foundations can be saved and loaded")
	var saved: Array = inventory.get("loaded_meta").get("built", [])
	check(saved.size() == before_count + 3, "Save contains all three placed foundations")
	print("FOUNDATION SMOKE: %d checks, %d failures" % [checks, failures])
	var ambience := current_scene.get_node_or_null("OceanAmbience") as AudioStreamPlayer
	if ambience != null:
		ambience.stop()
	await process_frame
	quit(0 if failures == 0 else 1)
