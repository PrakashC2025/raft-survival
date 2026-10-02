extends Node
## Persistent phone settings, shared by the menu and the paused game.
signal changed

const SETTINGS_PATH := "user://settings.cfg"
var quality := 0 # Auto, Battery Saver, Balanced, High
var target_fps := 60
var look_speed := 1.0
var invert_look := false
var volume := 0.8
var third_person := false
var is_open := false
var _previous_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _layer: CanvasLayer
var _overlay: Control
var _panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		quality = clampi(int(config.get_value("game", "quality", 0)), 0, 3)
		target_fps = 30 if int(config.get_value("game", "fps", 60)) == 30 else 60
		look_speed = clampf(float(config.get_value("game", "look_speed", 1.0)), 0.3, 2.0)
		invert_look = bool(config.get_value("game", "invert_look", false))
		volume = clampf(float(config.get_value("game", "volume", 0.8)), 0.0, 1.0)
		third_person = bool(config.get_value("game", "third_person", false))
	_apply()


func update_setting(key: String, value: Variant) -> void:
	match key:
		"quality": quality = clampi(int(value), 0, 3)
		"fps": target_fps = 30 if int(value) == 30 else 60
		"look_speed": look_speed = clampf(float(value), 0.3, 2.0)
		"invert_look": invert_look = bool(value)
		"volume": volume = clampf(float(value), 0.0, 1.0)
		"third_person": third_person = bool(value)
	_apply()
	var config := ConfigFile.new()
	for property in ["quality", "look_speed", "invert_look", "volume", "third_person"]:
		config.set_value("game", property, get(property))
	config.set_value("game", "fps", target_fps)
	if config.save(SETTINGS_PATH) != OK:
		push_warning("Could not save game settings.")
	changed.emit()


func _apply() -> void:
	Engine.max_fps = target_fps
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.set("cam_mode", 1 if third_person else 0)
		player.call("_apply_camera_mode")


func release_gameplay_input() -> void:
	for controls in get_tree().get_nodes_in_group("mobile_controls"):
		controls.call("reset_input")
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var rope := player.get_node_or_null("RopeSystem")
		if rope != null:
			rope.call("_cancel_charge")


func open() -> void:
	if is_open:
		return
	is_open = true
	_previous_paused = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode
	release_gameplay_input()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_panel()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_layer.queue_free()
	get_tree().paused = _previous_paused
	Input.mouse_mode = _previous_mouse_mode


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_open:
			close()
		else:
			var hud := get_tree().get_first_node_in_group("survival_hud")
			if hud != null:
				hud.call("handle_back")


func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_overlay = Control.new()
	_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 0.88)
	_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_overlay.add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.10, 0.13)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	var quality_options := OptionButton.new()
	for label in ["Auto (adapts to your phone)", "Battery Saver", "Balanced", "High"]:
		quality_options.add_item(label)
	quality_options.selected = quality
	quality_options.item_selected.connect(func(index: int): update_setting("quality", index))
	_add_row(content, "Graphics", quality_options)
	var frame_options := OptionButton.new()
	frame_options.add_item("30 FPS")
	frame_options.add_item("60 FPS")
	frame_options.selected = 0 if target_fps == 30 else 1
	frame_options.item_selected.connect(func(index: int): update_setting("fps", 30 if index == 0 else 60))
	_add_row(content, "Frame rate", frame_options)
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.3
	sensitivity.max_value = 2.0
	sensitivity.step = 0.05
	sensitivity.value = look_speed
	sensitivity.value_changed.connect(func(value: float): update_setting("look_speed", value))
	_add_row(content, "Look speed", sensitivity)
	var audio := HSlider.new()
	audio.min_value = 0.0
	audio.max_value = 1.0
	audio.step = 0.05
	audio.value = volume
	audio.value_changed.connect(func(value: float): update_setting("volume", value))
	_add_row(content, "Sound volume", audio)
	var invert := CheckButton.new()
	invert.text = "Invert vertical look"
	invert.button_pressed = invert_look
	invert.toggled.connect(func(value: bool): update_setting("invert_look", value))
	_add_row(content, "", invert)
	var camera_options := OptionButton.new()
	camera_options.add_item("First person")
	camera_options.add_item("Third person")
	camera_options.selected = 1 if third_person else 0
	camera_options.item_selected.connect(func(index: int): update_setting("third_person", index == 1))
	_add_row(content, "Camera", camera_options)
	var tip := Label.new()
	tip.text = "For a slower phone, choose Battery Saver and 30 FPS.\nChanges are saved automatically."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tip)
	var done := Button.new()
	done.text = "DONE"
	done.custom_minimum_size.y = 52
	done.pressed.connect(close)
	content.add_child(done)
	_overlay.resized.connect(_layout_panel)
	_layout_panel()


func _add_row(content: VBoxContainer, label_text: String, widget: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size.x = 155
		row.add_child(label)
	widget.custom_minimum_size = Vector2(180, 48)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)


func _layout_panel() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var panel_size := Vector2(minf(_overlay.size.x - 32.0, 640.0), minf(_overlay.size.y - 32.0, 630.0))
	_panel.size = panel_size
	_panel.position = (_overlay.size - panel_size) * 0.5
