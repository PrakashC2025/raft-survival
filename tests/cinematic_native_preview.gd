extends SceneTree
var _frame_gaps: Array[float] = []
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("FAIL: Native video handoff timed out"); quit(1))
	call_deferred("_run")
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/cinematic-"+label+".png")
	print("CAPTURE "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true)
	var settings := root.get_node("GameSettings")
	settings.target_fps = 30
	settings.quality = 1
	settings.call("_apply")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	await process_frame
	var menu := current_scene
	var index := 0
	for i in range(menu.get("_buttons").size()):
		if menu.get("_buttons")[i]["id"] == "new": index = i
	menu.call("_activate",index)
	while menu.get("_story_pending"): await process_frame
	var intro := menu.get("_intro") as Control
	if intro == null:
		push_error("FAIL: Native New Game did not create a video intro")
		quit(1)
		return
	var captions: Array = intro.get("captioned_cues")
	var completed := [false]
	intro.finished.connect(func(): completed[0] = bool(intro.get("playback_finished")))
	var targets := [1.4,10.5,20.5,28.2]
	var labels := ["opening","impact","flood","raft"]
	var next_capture := 0
	var last_frame := Time.get_ticks_usec()
	while is_instance_valid(intro) and not intro.get("complete"):
		await process_frame
		var now := Time.get_ticks_usec()
		_frame_gaps.append(float(now-last_frame)/1000000.0)
		last_frame = now
		if next_capture < targets.size() and intro.elapsed >= targets[next_capture]:
			await capture(labels[next_capture])
			next_capture += 1
			last_frame = Time.get_ticks_usec() # Exclude PNG export time from playback sampling.
	if not completed[0] or captions != [0,1,2,3,4,5,6,7] or next_capture != 4:
		push_error("FAIL: Full film did not finish with all subtitle cues: "+str(captions))
		quit(1)
		return
	_frame_gaps.sort()
	print("VIDEO FRAME TIMING: p95=%.3fs maximum=%.3fs (desktop observation)" % [_frame_gaps[int(_frame_gaps.size()*0.95)],_frame_gaps[-1]])
	while is_instance_valid(menu): await process_frame
	await capture("handoff")
	while root.get_node_or_null("WakeHandoff") != null: await process_frame
	for i in range(20): await process_frame
	var player := get_first_node_in_group("player")
	if player == null or not player.is_physics_processing() or not player.get_node("CanvasLayer").visible or not player.is_processing_unhandled_input():
		push_error("FAIL: Native video did not release gameplay")
		quit(1)
		return
	await capture("playable")
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null: ambient.call("stop_environment")
	print("NATIVE VIDEO HANDOFF: full film, all eight narrated subtitle cues, dawn fade and playable controls passed")
	quit()
