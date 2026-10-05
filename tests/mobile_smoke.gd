extends SceneTree

var failures := 0
var checks := 0
var settings: Node
var inventory: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func touch(target: Node, index: int, pos: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	target.call("_input", event)

func drag(target: Node, index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	target.call("_input", event)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		push_error("Tests require an isolated MobileTests custom_user_dir.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	settings = root.get_node("GameSettings")
	inventory = root.get_node("Inventory")
	root.get_node("Stats").set("enabled", false)
	inventory.call("new_game_reset", true)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var entries: Array = menu.get("_buttons")
	menu.call("_activate", entries.size() - 1)
	check(settings.get("is_open") and paused, "Main menu Settings opens and pauses")
	await process_frame
	check((settings.get("_panel") as Control).size.x > 300.0, "Settings panel has usable dimensions")
	settings.call("update_setting", "quality", 1)
	settings.call("update_setting", "fps", 30)
	settings.call("update_setting", "look_speed", 0.7)
	settings.call("update_setting", "volume", 0.4)
	settings.call("update_setting", "invert_look", true)
	settings.call("update_setting", "third_person", true)
	var config := ConfigFile.new()
	check(config.load("user://settings.cfg") == OK and int(config.get_value("game", "fps")) == 30, "Settings persist to disk")
	check(Engine.max_fps == 30, "30 FPS selection is applied")
	settings.call("close")
	check(not paused, "Closing menu settings restores game state")
	for frame in range(5400):
		if menu.get("_packed_game") != null or menu.get("_error") != "":
			break
		await process_frame
	check(menu.get("_packed_game") != null, "Packaged survival scene loads with every dependency")
	if menu.get("_packed_game") == null:
		quit(1)
		return
	menu.call("_activate", 0)
	await scene_changed
	await process_frame
	var player := get_first_node_in_group("player")
	check(player != null, "New Game enters playable world")
	if player == null:
		quit(1)
		return
	check(player.get("cam_mode") == 1, "Saved camera preference applies to New Game")
	var controls: Control = player.get_node("CanvasLayer/MobileControls")
	var hud: Control = player.get_node("CanvasLayer/SurvivalHUD")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	hud.visible = true
	hud.call("_compute_layout")
	controls.call("_apply_viewport_size")
	controls.call("_sync_mode")
	check(not (hud.get("_map_button_rect") as Rect2).has_area() and not (hud.get("_craft_button_rect") as Rect2).has_area(), "Map and crafting stay inside the bag")
	check(controls.get("_move_id") == -1 and not (controls.get("_btn_run") as Button).visible, "Idle movement controls stay hidden")
	var dock: Vector2 = controls.call("_dock_center")
	touch(controls, 0, dock + Vector2(0, -70), true)
	controls.call("_update_movement_actions")
	check(Input.is_action_pressed("move_forward"), "Joystick responds on touch-down")
	touch(controls, 1, controls.size * Vector2(0.55, 0.45), true)
	var old_yaw: float = player.rotation.y
	drag(controls, 1, controls.size * Vector2(0.55, 0.45), Vector2(20, 10))
	check(not is_equal_approx(player.rotation.y, old_yaw), "Second finger can look while moving")
	var jump: Button = controls.get("_btn_jump")
	var rope: Button = controls.get("_btn_rope")
	touch(controls, 2, jump.get_global_rect().get_center(), true)
	touch(controls, 3, rope.get_global_rect().get_center(), true)
	check(Input.is_action_pressed("move_forward") and Input.is_action_pressed("jump") and Input.is_action_pressed("rope_throw"), "Move, look, jump and hook accept independent fingers")
	touch(controls, 2, jump.get_global_rect().get_center(), false)
	check(not Input.is_action_pressed("jump") and Input.is_action_pressed("rope_throw"), "Releasing jump does not release the hook")
	drag(controls, 3, Vector2.ZERO, Vector2.ZERO)
	check(not Input.is_action_pressed("rope_throw"), "Dragging out of a held action releases it")
	controls.call("reset_input")
	check(not Input.is_action_pressed("move_forward") and controls.get("_look_id") == -1, "Canceled input clears movement and camera ownership")
	Input.action_press("move_forward")
	controls.call("_update_movement_actions")
	check(Input.is_action_pressed("move_forward"), "Mobile preview preserves keyboard movement")
	Input.action_release("move_forward")
	check(player.call("_get_movement_direction", Vector2(0.0, 0.4)).length() < 0.5, "Joystick strength produces analog walking speed")
	var action_pairs := [["_btn_jump", "jump"], ["_btn_run", "sprint"], ["_btn_use", "interact"], ["_btn_dive", "move_down"], ["_btn_rope", "rope_throw"], ["_btn_recall", "rope_cancel"], ["_btn_build", "build"], ["_btn_place", "place_build"], ["_btn_rotate", "rotate_build"], ["_btn_next", "cycle_build"], ["_btn_remove", "remove_build"]]
	for pair in action_pairs:
		for button in controls.get("_all_buttons"):
			button.visible = false
		var button: Button = controls.get(pair[0])
		button.visible = true
		touch(controls, 4, button.get_global_rect().get_center(), true)
		check(Input.is_action_pressed(pair[1]), pair[1] + " touch button presses")
		touch(controls, 4, button.get_global_rect().get_center(), false, true)
		check(not Input.is_action_pressed(pair[1]), pair[1] + " canceled touch releases")
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	hud.call("_compute_layout")
	check(hud.call("claims_touch", (hud.get("_pause_btn_rect") as Rect2).get_center()), "Pause button is excluded from camera look")
	touch(hud, 5, (hud.get("_bag_rect") as Rect2).get_center(), true)
	hud.call("_compute_layout")
	check(hud.get("_bag_open"), "Bag opens by touch")
	check((hud.get("_map_button_rect") as Rect2).has_area() and (hud.get("_craft_button_rect") as Rect2).has_area(), "Bag provides map and crafting tabs")
	var panel: Rect2 = hud.get("_panel_rect")
	for rect in hud.get("_bag_slot_rects"):
		check(panel.encloses(rect), "Inventory slot stays within bag panel")
	var dragged_item: String = inventory.call("slot_item", 0)
	var slots: Array = hud.get("_bag_slot_rects")
	touch(hud, 6, slots[0].get_center(), true)
	touch(hud, 7, slots[6].get_center(), true)
	drag(hud, 6, slots[6].get_center(), Vector2(50, 0))
	touch(hud, 7, slots[6].get_center(), false)
	check(hud.get("_inventory_touch_id") == 6, "Second finger cannot cancel an inventory drag")
	touch(hud, 6, slots[6].get_center(), false)
	check(inventory.call("slot_item", 6) == dragged_item, "Inventory drag moves the item")
	touch(hud, 8, (hud.get("_close_rect") as Rect2).get_center(), true)
	check(not hud.get("_bag_open"), "Bag close works on touch-down")
	var help: Button = controls.get("_btn_help")
	touch(controls, 9, help.get_global_rect().get_center(), true)
	touch(controls, 9, help.get_global_rect().get_center(), false)
	check(controls.get("_help_open") and paused, "Help opens and pauses survival")
	controls.call("_set_help", false)
	check(not paused, "Closing help resumes survival")
	# Exercise full viewport event routing, rather than calling a control directly.
	for pair in [[10, dock + Vector2(0, -70)], [11, jump.get_global_rect().get_center()]]:
		var routed := InputEventScreenTouch.new()
		routed.index = pair[0]
		routed.position = pair[1]
		routed.pressed = true
		root.push_input(routed, true)
	controls.call("_update_movement_actions")
	check(Input.is_action_pressed("move_forward") and Input.is_action_pressed("jump"), "Viewport routes simultaneous joystick and button touches")
	controls.call("reset_input")
	var raft: Node3D = get_first_node_in_group("raft")
	player.global_position = raft.global_position + Vector3(1.4, 0.0, 0.0)
	player.set("is_swimming", true)
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	var climb: Button = controls.get("_btn_climb")
	check(climb.visible, "Climb appears beside the raft while swimming")
	touch(controls, 12, climb.get_global_rect().get_center(), true)
	touch(controls, 12, climb.get_global_rect().get_center(), false)
	check(not player.get("is_swimming"), "Climb touch boards the raft")
	var piece: Node3D = load("res://scenes/foundation.tscn").instantiate()
	piece.name = "FoundationTest"
	raft.get_node("BuiltPieces").add_child(piece)
	piece.position = Vector3(2.0, 0.0, 0.0)
	player.set("aim_valid", true)
	player.set("aim_collider", piece)
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	var edit: Button = controls.get("_btn_edit")
	touch(controls, 13, edit.get_global_rect().get_center(), true)
	touch(controls, 13, edit.get_global_rect().get_center(), false)
	check(player.get("_editing") == piece, "Edit touch picks up an aimed building")
	player.call("_cancel_edit")
	player.set("aim_valid", false)
	player.set("aim_collider", null)
	controls.set("_mode", "init")
	controls.call("_sync_mode")
	hud.call("toggle_map")
	check(hud.get("_map_open") and paused, "Map opens and pauses")
	hud.call("_close_map")
	hud.call("toggle_crafting")
	check(hud.get("_craft_open") and paused, "Crafting opens and pauses")
	hud.call("_close_crafting")
	hud.call("_set_paused", true)
	hud.call("_handle_pause_mouse", (hud.get("_pause_settings_rect") as Rect2).get_center())
	check(settings.get("is_open"), "Pause Settings button works")
	settings.call("close")
	check(paused, "Closing in-game settings preserves pause")
	settings.call("open")
	settings.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not settings.get("is_open") and paused, "Android Back closes settings without resuming behind pause")
	hud.call("_set_paused", false)
	var performance: Node = get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	settings.call("update_setting", "quality", 0)
	settings.call("update_setting", "fps", 30)
	performance.call("_update_quality", 1.0 / 30.0)
	check(performance.get("_slow_windows") == 0, "Quality governor treats 30 FPS as healthy at a 30 FPS target")
	settings.call("update_setting", "fps", 60)
	performance.call("_update_quality", 0.03)
	performance.call("_update_quality", 0.03)
	check(float(performance.get("_render_scale")) < 0.82, "Auto graphics reduces resolution under sustained slow frames")
	player.call("quick_save")
	check(inventory.call("has_save", "quick"), "Touch-accessible quick save writes progress")
	hud.call("_set_paused", true)
	var quit_event := InputEventMouseButton.new()
	quit_event.button_index = MOUSE_BUTTON_LEFT
	quit_event.pressed = true
	quit_event.position = (hud.get("_pause_quit_rect") as Rect2).get_center()
	root.push_input(quit_event, true)
	await scene_changed
	await process_frame
	menu = current_scene
	check(menu.scene_file_path == "res://scenes/main_menu.tscn" and not paused, "Pause Quit pointer safely detaches the HUD and enters the menu")
	check(inventory.call("has_save", "main"), "Quit to menu saves survival progress")
	for frame in range(5400):
		if menu.get("_packed_game") != null:
			break
		await process_frame
	menu.call("_activate", 0)
	await scene_changed
	await process_frame
	check(get_first_node_in_group("player") != null, "Continue enters the saved world")
	print("MOBILE SMOKE: %d checks, %d failures" % [checks, failures])
	var ambience := current_scene.get_node_or_null("OceanAmbience") as AudioStreamPlayer
	if ambience != null:
		ambience.call("stop_environment")
	# Wait for actual preparation completion rather than a fixed delay.
	for frame in range(600):
		var complete := true
		for setup in current_scene.find_children("IslandSetup", "Node3D", true, false):
			complete = complete and setup.get("setup_complete") == true
		if complete:
			break
		await physics_frame
	await process_frame
	quit(0 if failures == 0 else 1)
