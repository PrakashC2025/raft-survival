extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func capture(label: String) -> void:
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/environment-" + label + ".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	var settings := root.get_node("GameSettings")
	settings.set("quality", 2)
	settings.set("third_person", false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for frame in range(600):
		await physics_frame
		if current_scene.get_node_or_null("Island/IslandGrass/GrassField") != null:
			break
	var player := get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	performance.set("_last_quality", -1)
	performance.call("_apply_profile")
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	player.call("_update_hud")
	await capture("raft")
	player.get_node("CanvasLayer").visible = false
	var camera := Camera3D.new()
	camera.fov = 65.0
	current_scene.add_child(camera)
	camera.make_current()
	var island := current_scene.get_node("Island") as Node3D
	camera.global_position = island.global_position + Vector3(22, 7, 23)
	camera.look_at(island.global_position + Vector3(0, 2.5, 0))
	await capture("island")
	var field := island.get_node("IslandGrass/GrassField") as MultiMeshInstance3D
	var sample := field.multimesh.get_instance_custom_data(0)
	if sample.b <= 0.0 or sample.a <= 0.0:
		push_error("Grass color/dryness data is missing from the rendering instance")
		quit(1)
		return
	var ground := field.global_transform * field.multimesh.get_instance_transform(0).origin
	camera.global_position = ground + Vector3(0.9, 0.8, 1.3)
	camera.look_at(ground + Vector3(-2.0, 0.15, -3.0))
	await capture("grass")
	var ocean := get_first_node_in_group("ocean")
	ocean.call("_force_time", 17.8)
	camera.global_position = Vector3(0, 3, 0)
	camera.look_at(Vector3(40, 0, -20))
	await capture("sunset")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	await create_timer(0.1).timeout
	quit()
