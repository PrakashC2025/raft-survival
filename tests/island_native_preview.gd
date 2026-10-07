extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.size = Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true)
	root.get_node("GameSettings").call("update_setting","quality",3)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var player := get_first_node_in_group("player") as Node3D
	player.set_process(false)
	player.set_physics_process(false)
	player.get_node("CanvasLayer").visible = false
	root.get_node("Stats").enabled = false
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile",true)
	performance.call("refresh_foliage")
	var camera := Camera3D.new()
	camera.fov = 58
	camera.far = 2000
	current_scene.add_child(camera)
	camera.current = true
	for frame in range(1200):
		await process_frame
		var ready := true
		for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
			ready = ready and current_scene.get_node(name+"/IslandLandscape").landscape_ready \
				and current_scene.get_node_or_null(name+"/IslandGrass/GrassField") != null
		if ready: break
	current_scene.get_node("Sky3D/TimeOfDay").current_time = 16.7
	if "--balanced-only" in OS.get_cmdline_user_args():
		root.get_node("GameSettings").call("update_setting","quality",2)
		var home := current_scene.get_node("Island") as Node3D
		camera.global_position = home.global_position + Vector3(-3,4.5,29)
		camera.look_at(home.global_position + Vector3(0,3.1,-1))
		for frame in range(40): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/island-realism-mobile-balanced.png")
		current_scene.get_node("OceanAmbience").call("stop_environment")
		current_scene.queue_free()
		for frame in range(25): await process_frame
		quit()
		return
	for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
		var island := current_scene.get_node(name) as Node3D
		camera.global_position = island.global_position + Vector3(-3,4.5,29 if name == "Island" else 23)
		camera.look_at(island.global_position + Vector3(0,3.1,-1))
		for frame in range(35): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/island-realism-"+name+".png")
		print("ISLAND PREVIEW ",name," ready=",island.get_node("IslandLandscape").landscape_ready," draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var island := current_scene.get_node("Island") as Node3D
	camera.global_position = island.global_position + Vector3(-3,4.5,29)
	camera.look_at(island.global_position + Vector3(0,3.1,-1))
	var timings: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(180):
		await process_frame
		var now := Time.get_ticks_usec()
		if frame > 30: timings.append(float(now - previous) / 1000.0)
		previous = now
	timings.sort()
	print("ISLAND GPU METRICS adapter=",RenderingServer.get_video_adapter_name()," renderer=",RenderingServer.get_current_rendering_method()," median_ms=",timings[floori(float(timings.size()) / 2.0)]," p95_ms=",timings[floori(timings.size() * 0.95)])
	root.get_node("GameSettings").call("update_setting","quality",2)
	for frame in range(35): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/island-realism-mobile-balanced.png")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for frame in range(25): await process_frame
	quit()
