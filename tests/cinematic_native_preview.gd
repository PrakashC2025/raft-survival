extends SceneTree
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("FAIL: Native story handoff timed out"); quit(1))
	call_deferred("_run")
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/cinematic-"+label+".png")
	print("CAPTURE "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset",true)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	await process_frame
	var menu := current_scene
	var index := 0
	for i in range(menu.get("_buttons").size()):
		if menu.get("_buttons")[i]["id"] == "new": index = i
	menu.call("_activate",index)
	for i in range(45): await process_frame
	var intro := menu.get("_intro") as Control
	if intro == null:
		push_error("FAIL: Native New Game did not create a cinematic")
		quit(1)
		return
	await capture("opening")
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.pressed = true
	tap.position = intro.get("_skip").get_global_rect().get_center()
	Input.parse_input_event(tap)
	await process_frame
	if is_instance_valid(intro) and not intro.get("complete"):
		push_error("FAIL: Native Skip touch was intercepted")
		quit(1)
		return
	while is_instance_valid(menu): await process_frame
	await process_frame
	await capture("handoff")
	while root.get_node_or_null("WakeHandoff") != null: await process_frame
	for i in range(20): await process_frame
	var player := get_first_node_in_group("player")
	if player == null or not player.is_physics_processing() or not player.get_node("CanvasLayer").visible:
		push_error("FAIL: Native story did not release gameplay")
		quit(1)
		return
	await capture("playable")
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null: ambient.call("stop_environment")
	print("NATIVE CINEMATIC HANDOFF: New Game, touch Skip, dawn fade and playable controls passed")
	quit()
