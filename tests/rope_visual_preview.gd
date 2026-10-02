extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func capture(name: String) -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/" + name + ".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	var settings := root.get_node("GameSettings")
	settings.set("third_person", false)
	settings.set("quality", 2)
	settings.set("target_fps", 60)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for frame in range(10):
		await process_frame
	var player := get_first_node_in_group("player")
	player.set("cam_mode", 0)
	player.call("_apply_camera_mode")
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	performance.set("_last_quality", -1)
	performance.call("_apply_profile")
	await capture("rope-launcher-first-person")
	var rope := player.get_node("RopeSystem")
	rope.set_physics_process(false)
	rope.set("_charge_distance", 60.0)
	rope.call("_throw_hook")
	rope.call("_handle_throwing", 0.25)
	rope.call("_update_rope_visual")
	rope.call("_update_hook_visual")
	await capture("rope-launcher-casting")
	rope.call("_force_cancel")
	player.set("cam_mode", 1)
	player.call("_apply_camera_mode")
	await capture("rope-launcher-third-person")
	quit()