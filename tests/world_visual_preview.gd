extends SceneTree
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	call_deferred("_run")
func capture(label: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/updated-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset",true)
	root.get_node("GameSettings").set("quality",2)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	root.get_node("Stats").enabled = false
	var player := get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	player.get_node("CanvasLayer").visible = false
	current_scene.get_node("Sky3D").set("current_time",10.0)
	for i in range(220): await physics_frame
	player.set("cam_mode",0)
	player.call("_apply_camera_mode")
	await capture("gun-hand-first-person")
	player.set("cam_mode",1)
	player.call("_apply_camera_mode")
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.make_current()
	camera.position = player.global_position+Vector3(0.85,0.35,-1.4)
	camera.look_at(player.global_position+Vector3(0,0.1,0))
	await capture("gun-hand-third-person")
	var island := current_scene.get_node("Island") as Node3D
	player.get_node("Body").visible = false
	player.position = island.global_position+Vector3(3,3,-3)
	camera.position = island.global_position+Vector3(12,7,15)
	camera.look_at(island.global_position+Vector3(0,2,0))
	await capture("island-trees")
	var banana := island.get_node("CoastalGrove/Banana0") as Node3D
	camera.position = banana.global_position+Vector3(2,2.1,3)
	camera.look_at(banana.global_position+Vector3(0,1.2,0))
	await capture("banana-texture")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for i in range(20): await process_frame
	print("WORLD VISUAL PREVIEW: captured first/third person grip, island and banana textures")
	quit()
