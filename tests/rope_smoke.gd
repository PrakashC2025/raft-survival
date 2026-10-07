extends SceneTree

var checks := 0
var failures := 0

class TestDebris extends RigidBody3D:
	var is_hooked := false
	var collected := false
	var item_name := "Wood"
	var freeboard := 0.15

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
	root.size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	root.get_node("Inventory").call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	root.get_node("GameSettings").set("third_person", false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	# The empty-water flight fixture must not catch randomly prewarmed salvage.
	# Deferred prewarming yields across frames even after _process is disabled.
	var stream := current_scene.get_node("DebrisSpawner")
	stream.set("prewarm_count",0)
	stream.set_process(false)
	for frame in range(20):
		await process_frame
	var player := get_first_node_in_group("player")
	if player == null:
		check(false, "Survival scene creates the player")
		quit(1)
		return
	player.set_process(false)
	player.set_physics_process(false)
	var rope := player.get_node("RopeSystem")
	rope.set_physics_process(false)
	var camera := player.get("camera") as Camera3D
	camera.global_position = Vector3(0, 3, 0)
	camera.global_rotation = Vector3.ZERO
	rope.get("_aim_ray").collision_mask = 0
	for debris in get_nodes_in_group("debris"):
		debris.remove_from_group("debris")
	var launcher := player.get("_rope_launcher") as Node3D
	check(launcher != null and launcher.has_node("LaunchMuzzle"), "Rope equips a launcher with a real muzzle")
	check(launcher.find_children("*", "MeshInstance3D", true, false).size() <= 8, "Held launcher is batched into few mobile draw calls")
	rope.call("_update_hook_origin")
	check((rope.call("_hand_pos") as Vector3).distance_to((launcher.get_node("LaunchMuzzle") as Node3D).global_position) < 0.001, "Line starts at the visible launcher muzzle")
	check((rope.get("_hook") as Node3D).get_child_count() == 2, "Flying hook uses metal grappling geometry")
	check(float(rope.get("max_hook_distance")) == 60.0, "Launcher maximum range is 60 metres")
	# Quick press/release through the real phone control.
	var controls: Control = player.get_node("CanvasLayer/MobileControls")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	controls.call("_apply_viewport_size")
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	var button: Button = controls.get("_btn_rope")
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = button.get_global_rect().get_center()
	root.push_input(down, true)
	rope.call("_handle_idle", 1.0 / 60.0)
	check(rope.get("_is_charging") and float(rope.get("_charge_distance")) == 20.0, "Mobile press starts a 20 metre quick cast")
	await process_frame
	var up := down.duplicate() as InputEventScreenTouch
	up.pressed = false
	root.push_input(up, true)
	rope.call("_handle_idle", 1.0 / 60.0)
	check(int(rope.get("_state")) == 1 and float(rope.get("_throw_dist")) >= 19.9, "Mobile release launches the hook")
	rope.call("_force_cancel")
	await process_frame
	Input.action_press("rope_throw")
	rope.call("_handle_idle", 1.0 / 60.0)
	await process_frame
	rope.call("_handle_idle", 0.85)
	check(float(rope.get("_charge_distance")) == 60.0, "Holding for under a second reaches maximum cast power")
	Input.action_release("rope_throw")
	rope.call("_throw_hook")
	check(float(rope.get("_throw_dist")) > 58.0 and float(rope.get("_throw_dist")) <= 60.0, "Charged cast reaches distant water within the range limit")
	var start: Vector3 = rope.get("_throw_start")
	var end: Vector3 = rope.get("_throw_end")
	var middle: Vector3 = rope.call("_flight_position", float(rope.get("_throw_dist")) * 0.5)
	check(middle.y > start.lerp(end, 0.5).y + 1.0, "Hook travels in an arc above the water")
	var before: Vector3=rope.call("_flight_position",float(rope.get("_throw_dist"))*0.4)
	var after: Vector3=rope.call("_flight_position",float(rope.get("_throw_dist"))*0.6)
	var dt: float=float(rope.get("_flight_duration"))*0.1
	check(absf((before.y-2.0*middle.y+after.y)/(dt*dt)+float(rope.get("hook_gravity")))<0.002,"Hook flight has constant downward gravity")
	for frame in range(200):
		if int(rope.get("_state")) != 1:
			break
		rope.call("_handle_throwing", 1.0 / 60.0)
	check(int(rope.get("_state")) == 2, "Long cast reaches water and waits for debris")
	check(absf((rope.get("_hook_world_pos") as Vector3).y - float(rope.call("_get_ocean_y", end)) - 0.15) < 0.02, "Hook lands on the real ocean surface")
	# Actual swept collision rather than a source-text assertion.
	rope.call("_force_cancel");rope.call("_throw_hook")
	var obstacle:=StaticBody3D.new()
	var shape_node:=CollisionShape3D.new()
	var box:=BoxShape3D.new();box.size=Vector3.ONE*0.8;shape_node.shape=box
	obstacle.add_child(shape_node);current_scene.add_child(obstacle)
	obstacle.global_position=rope.call("_flight_position",float(rope.get("_throw_dist"))*0.4)
	await physics_frame
	await physics_frame
	for frame in range(200):
		if int(rope.get("_state"))!=1:break
		rope.call("_handle_throwing",1.0/60.0)
	check(int(rope.get("_state"))==5,"A real solid obstacle makes the hook recall instead of tunnelling through")
	obstacle.queue_free();await physics_frame
	rope.call("_force_cancel");rope.call("_throw_hook")
	for frame in range(200):
		if int(rope.get("_state"))!=1:break
		rope.call("_handle_throwing",1.0/60.0)
	rope.call("_update_rope_visual")
	check((rope.get("_rope_mesh") as MeshInstance3D).mesh.get_surface_count() == 1, "Long line renders with one mesh surface")
	var catch := TestDebris.new()
	root.add_child(catch)
	catch.add_to_group("debris")
	catch.global_position = rope.get("_hook_world_pos")
	rope.call("_check_debris")
	check(catch.is_hooked and catch.freeze, "Distant hook captures floating materials")
	rope.call("_start_return")
	check(not catch.is_hooked and not catch.freeze, "Recall releases captured materials safely")
	for frame in range(300):
		if int(rope.get("_state")) == 0:
			break
		rope.call("_handle_returning", 1.0 / 60.0)
	check(int(rope.get("_state")) == 0, "Long-distance recall returns without overshooting")
	player.set("cam_mode", 1)
	player.call("_apply_camera_mode")
	rope.call("_update_hook_origin")
	var third := player.get("_third_person_launcher") as Node3D
	check(third.visible and (rope.call("_hand_pos") as Vector3).distance_to((third.get_node("LaunchMuzzle") as Node3D).global_position) < 0.001, "Third-person casts start on the player's launcher")
	player.call("select_hotbar_slot", 5)
	check(player.get("_rope_launcher") == null and (player.get("_hand_item") as Node3D).get_node_or_null("HumanHand") != null, "Hotbar selection updates held visuals immediately")
	player.call("select_hotbar_slot", 0)
	check(player.get("_rope_launcher") != null, "Selecting Rope restores the launcher")
	rope.set("_is_charging", true)
	player.set("build_mode", true)
	rope.call("_physics_process", 0.01)
	check(not rope.get("_is_charging"), "Entering build mode cancels a held cast")
	player.set("build_mode", false)
	var inventory := root.get_node("Inventory")
	player.call("equip_rope_gun")
	inventory.call("remove", "Rope", int(inventory.call("total", "Rope")))
	check(int(inventory.call("total", "Rope")) == 0 and player.get("_rope_launcher") != null, "Spending every rope material cannot remove the permanent gun")
	player.call("select_hotbar_slot", 5)
	controls.call("_sync_mode")
	check(button.visible, "CAST remains available with another item selected and no rope materials")
	await process_frame
	root.push_input(down, true)
	rope.call("_handle_idle", 0.01)
	check(player.get("rope_gun_selected") and player.get("_rope_launcher") != null and rope.get("_is_charging"), "CAST re-equips the permanent gun and charges with zero rope")
	root.push_input(up, true)
	controls.call("reset_input")
	rope.call("_force_cancel")
	inventory.call("place_at", 0, "Wood", 1)
	inventory.call("drop_into", 0, 10)
	check(player.get("_rope_launcher") != null and player.get("rope_gun_selected"), "Dragging inventory stacks cannot drag away the gun")
	inventory.call("add", "Stone", 60000)
	var full := true
	for slot_index in range(30):
		full = full and not bool(inventory.call("slot_empty", slot_index))
	var full_slots: Array = inventory.get("slots").duplicate(true)
	player.call("select_hotbar_slot", 5)
	check(full and player.call("equip_rope_gun") and inventory.get("slots") == full_slots, "Permanent gun equips with a full bag without displacing any inventory")
	player.call("quick_save")
	inventory.call("load_game", "quick")
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await process_frame
	player = get_first_node_in_group("player")
	check(player.get("rope_gun_selected") and player.get("_rope_launcher") != null and int(inventory.call("total", "Rope")) == 0, "Continue restores the gun when all rope materials have been spent")
	# Let the new scene's deferred restoration finish before testing another load.
	await physics_frame
	await physics_frame
	# Legacy saves do not carry the new optional equipped-state field.
	inventory.get("loaded_meta").erase("rope_gun_selected")
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await process_frame
	player = get_first_node_in_group("player")
	controls = player.get_node("CanvasLayer/MobileControls")
	controls.call("_sync_mode")
	check((controls.get("_btn_rope") as Button).visible and player.call("equip_rope_gun"), "Legacy saves also receive an always-available gun without changing their slots")
	print("ROPE SMOKE: %d checks, %d failures" % [checks, failures])
	var ambience := current_scene.get_node_or_null("OceanAmbience") as AudioStreamPlayer
	if ambience != null:
		ambience.call("stop_environment")
	# Let the dummy audio backend flush playback before engine shutdown.
	await create_timer(0.1).timeout
	current_scene.queue_free()
	for unused in 25:await process_frame
	quit(0 if failures == 0 else 1)
