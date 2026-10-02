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
	for frame in range(5):
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
	for frame in range(200):
		if int(rope.get("_state")) != 1:
			break
		rope.call("_handle_throwing", 1.0 / 60.0)
	check(int(rope.get("_state")) == 2, "Long cast reaches water and waits for debris")
	check(absf((rope.get("_hook_world_pos") as Vector3).y - float(rope.call("_get_ocean_y", end)) - 0.15) < 0.02, "Hook lands on the real ocean surface")
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
	check(player.get("_rope_launcher") == null and (player.get("_fist_node") as MeshInstance3D).mesh != null, "Hotbar selection updates held visuals immediately")
	player.call("select_hotbar_slot", 0)
	check(player.get("_rope_launcher") != null, "Selecting Rope restores the launcher")
	rope.set("_is_charging", true)
	player.set("build_mode", true)
	rope.call("_physics_process", 0.01)
	check(not rope.get("_is_charging"), "Entering build mode cancels a held cast")
	print("ROPE SMOKE: %d checks, %d failures" % [checks, failures])
	var ambience := current_scene.get_node_or_null("OceanAmbience") as AudioStreamPlayer
	if ambience != null:
		ambience.stop()
	# Let the dummy audio backend flush playback before engine shutdown.
	await create_timer(0.1).timeout
	quit(0 if failures == 0 else 1)
