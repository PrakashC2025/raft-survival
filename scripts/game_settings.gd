extends Node
## Persistent phone settings, shared by the menu and the paused game.
signal changed

const SETTINGS_PATH := "user://settings.cfg"
const OCEAN_UI := preload("res://scripts/ocean_ui.gd")
const DEFAULT_DAY_MINUTES := 20.0
const MIN_DAY_MINUTES := 12.0
const MAX_DAY_MINUTES := 30.0
var quality := 0 # Auto, Low / Battery Saver, Medium / Balanced, High, Ultra
var target_fps := 60
var look_speed := 1.0
var invert_look := false
var volume := 0.8
var third_person := false
var day_minutes := DEFAULT_DAY_MINUTES
var head_bob := false
var smooth_look := true
var is_open := false
var _previous_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _layer: CanvasLayer
var _overlay: Control
var _panel: PanelContainer


func mobile_effects_profile() -> bool:
	# The command-line flag lets desktop verification exercise the phone policy.
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or "--mobile-effects" in OS.get_cmdline_user_args()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	# Start new phone installations within a steady frame budget. Existing
	# settings retain the owner's chosen graphics and 30/60 FPS preference.
	if mobile_effects_profile(): target_fps = 30
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		quality = clampi(int(config.get_value("game", "quality", 0)), 0, 4)
		target_fps = 30 if int(config.get_value("game", "fps", target_fps)) == 30 else 60
		look_speed = clampf(float(config.get_value("game", "look_speed", 1.0)), 0.3, 2.0)
		invert_look = bool(config.get_value("game", "invert_look", false))
		volume = clampf(float(config.get_value("game", "volume", 0.8)), 0.0, 1.0)
		third_person = bool(config.get_value("game", "third_person", false))
		day_minutes = valid_day_minutes(float(config.get_value("game", "day_minutes", DEFAULT_DAY_MINUTES)))
		head_bob = bool(config.get_value("game", "head_bob", false))
		smooth_look = bool(config.get_value("game", "smooth_look", true))
	_apply()


func update_setting(key: String, value: Variant) -> void:
	match key:
		"quality": quality = clampi(int(value), 0, 4)
		"fps": target_fps = 30 if int(value) == 30 else 60
		"look_speed": look_speed = clampf(float(value), 0.3, 2.0)
		"invert_look": invert_look = bool(value)
		"volume": volume = clampf(float(value), 0.0, 1.0)
		"third_person": third_person = bool(value)
		"day_minutes": day_minutes = clampf(float(value), MIN_DAY_MINUTES, MAX_DAY_MINUTES)
		"head_bob": head_bob = bool(value)
		"smooth_look": smooth_look = bool(value)
	_apply()
	var config := ConfigFile.new()
	for property in ["quality", "look_speed", "invert_look", "volume", "third_person", "day_minutes", "head_bob", "smooth_look"]:
		config.set_value("game", property, get(property))
	config.set_value("game", "fps", target_fps)
	if config.save(SETTINGS_PATH) != OK:
		push_warning("Could not save game settings.")
	changed.emit()


func valid_day_minutes(value: float) -> float:
	# Existing choices inside the owner's slower range survive. Older fast/invalid
	# cycles use the new default without changing any saved calendar or time.
	return value if is_finite(value) and value >= MIN_DAY_MINUTES and value <= MAX_DAY_MINUTES else DEFAULT_DAY_MINUTES


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
		player.call("reset_look_input")
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
		# The wake overlay owns input until scene preparation and its fade finish.
		if get_tree().root.get_node_or_null("WakeHandoff") != null:
			return
		if is_open:
			close()
		else:
			var hud := get_tree().get_first_node_in_group("survival_hud")
			if hud != null:
				hud.call("handle_back")



func _build_panel() -> void:
	_layer=CanvasLayer.new();_layer.layer=100;add_child(_layer)
	_overlay=Control.new();_overlay.theme=OCEAN_UI.theme();_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sea:=ColorRect.new();sea.name="SettingsOcean";sea.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/menu_sea.gdshader");sea.material=material
	_overlay.add_child(sea);sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(.015,.05,.08,.60);shade.mouse_filter=Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel=PanelContainer.new();_panel.name="OceanSettings";_overlay.add_child(_panel)
	var style:=OCEAN_UI.box(Color(.025,.09,.14,.97),Color(.34,.65,.72,.5),20)
	style.set_content_margin_all(22);_panel.add_theme_stylebox_override("panel",style)
	var shell:=VBoxContainer.new();shell.add_theme_constant_override("separation",16);_panel.add_child(shell)
	var heading:=HBoxContainer.new();shell.add_child(heading)
	var titles:=VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(titles)
	var brand:=Label.new();brand.text="OCEAN SURVIVAL / YOUR EXPERIENCE";brand.add_theme_font_size_override("font_size",12)
	brand.add_theme_color_override("font_color",OCEAN_UI.AQUA);titles.add_child(brand)
	var title:=Label.new();title.text="Settings";title.add_theme_font_size_override("font_size",34);titles.add_child(title)
	var tabs:=TabContainer.new();tabs.name="SettingsTabs";tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;tabs.custom_minimum_size.y=64
	tabs.tab_alignment=TabBar.ALIGNMENT_LEFT;shell.add_child(tabs)
	var display:=_settings_page(tabs,"Display","A clearer view of your ocean")
	var quality_options:=OptionButton.new();quality_options.name="GraphicsChoice"
	for label in ["Auto","Low / Battery Saver","Medium / Balanced","High","Ultra"]:quality_options.add_item(label)
	quality_options.selected=quality
	quality_options.item_selected.connect(func(index: int):update_setting("quality",index))
	_add_row(display,"Graphics",quality_options)
	var frame_options:=OptionButton.new();frame_options.name="FrameRateChoice"
	frame_options.add_item("30 FPS");frame_options.add_item("60 FPS")
	frame_options.selected=0 if target_fps==30 else 1
	frame_options.item_selected.connect(func(index: int):update_setting("fps",30 if index==0 else 60))
	_add_row(display,"Frame rate",frame_options)
	_settings_note(display,"Battery Saver uses less power. Balanced adds detail.\nChoose the frame rate that feels smooth on your device.")
	var controls:=_settings_page(tabs,"Controls","Find your natural movement")
	var sensitivity:=HSlider.new();sensitivity.name="LookSpeedSlider";sensitivity.min_value=.3;sensitivity.max_value=2;sensitivity.step=.05;sensitivity.value=look_speed
	sensitivity.value_changed.connect(func(value: float):update_setting("look_speed",value))
	_add_row(controls,"Look speed",_slider_value(sensitivity,false))
	var smooth:=CheckButton.new();smooth.name="SmoothLookToggle";smooth.text="On" if smooth_look else "Off";smooth.button_pressed=smooth_look
	smooth.toggled.connect(func(value: bool):smooth.text="On" if value else "Off";update_setting("smooth_look",value));_add_row(controls,"Smooth camera look",smooth)
	var invert:=CheckButton.new();invert.name="InvertLookToggle";invert.text="On" if invert_look else "Off";invert.button_pressed=invert_look
	invert.toggled.connect(func(value: bool):invert.text="On" if value else "Off";update_setting("invert_look",value));_add_row(controls,"Invert vertical look",invert)
	var camera_options:=OptionButton.new();camera_options.name="CameraChoice";camera_options.add_item("First person");camera_options.add_item("Third person")
	camera_options.selected=1 if third_person else 0
	camera_options.item_selected.connect(func(index: int):update_setting("third_person",index==1));_add_row(controls,"Camera",camera_options)
	var bob:=CheckButton.new();bob.name="HeadBobToggle";bob.text="On" if head_bob else "Off";bob.button_pressed=head_bob
	bob.toggled.connect(func(value: bool):bob.text="On" if value else "Off";update_setting("head_bob",value));_add_row(controls,"Walking head bob",bob)
	var sound:=_settings_page(tabs,"Sound","Hear the sea around you")
	var audio:=HSlider.new();audio.name="SoundVolumeSlider";audio.min_value=0;audio.max_value=1;audio.step=.05;audio.value=volume
	audio.value_changed.connect(func(value: float):update_setting("volume",value));_add_row(sound,"Volume",_slider_value(audio,true))
	_settings_note(sound,"Waves, footsteps and survival sounds follow this volume.\nSlide to zero to mute.")
	var world:=_settings_page(tabs,"World","Give every sunrise its own pace")
	var day_length:=SpinBox.new();day_length.name="DayLengthChoice";day_length.min_value=MIN_DAY_MINUTES;day_length.max_value=MAX_DAY_MINUTES
	day_length.step=1;day_length.suffix="min";day_length.value=day_minutes
	day_length.value_changed.connect(func(value: float):update_setting("day_minutes",value));_add_row(world,"Day + night cycle",day_length)
	_settings_note(world,"One full day and night, measured in real minutes.")
	var footer:=HBoxContainer.new();shell.add_child(footer)
	var saved:=Label.new();saved.text="Saved automatically";saved.size_flags_horizontal=Control.SIZE_EXPAND_FILL;saved.clip_text=true
	saved.add_theme_font_size_override("font_size",13);saved.add_theme_color_override("font_color",OCEAN_UI.MUTED);footer.add_child(saved)
	var done:=Button.new();done.name="SettingsDone";done.text="DONE";done.custom_minimum_size=Vector2(128,50)
	done.add_theme_stylebox_override("normal",OCEAN_UI.box(Color("176879"),OCEAN_UI.AQUA.darkened(.2)))
	done.button_down.connect(release_gameplay_input);done.pressed.connect(close);footer.add_child(done)
	_overlay.resized.connect(_layout_panel);_layout_panel()

func _settings_page(tabs: TabContainer, label: String, description: String) -> VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.name=label;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;tabs.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",12);scroll.add_child(content)
	_settings_note(content,description)
	return content

func _settings_note(content: VBoxContainer, text: String) -> void:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",14);label.add_theme_color_override("font_color",OCEAN_UI.MUTED)
	content.add_child(label)

func _slider_value(slider: HSlider, percent: bool) -> HBoxContainer:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12)
	slider.custom_minimum_size=Vector2(80,48);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
	var value:=Label.new();value.custom_minimum_size.x=52;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color",OCEAN_UI.AQUA);row.add_child(value)
	var refresh:=func(number: float):value.text=("%d%%"%roundi(number*100)) if percent else ("%.2f×"%number)
	slider.value_changed.connect(refresh);refresh.call(slider.value)
	return row

func _add_row(content: VBoxContainer, label_text: String, widget: Control) -> void:
	var card:=PanelContainer.new();card.add_theme_stylebox_override("panel",OCEAN_UI.box(Color("103041"),Color(.18,.34,.4,.45),12));content.add_child(card)
	var row:=BoxContainer.new();row.add_theme_constant_override("separation",18);card.add_child(row)
	var label:=Label.new();label.text=label_text;label.custom_minimum_size.x=160;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",16);row.add_child(label)
	widget.custom_minimum_size=Vector2(130,48);widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(widget)
	widget.set_meta("settings_widget",true)

func _layout_panel() -> void:
	if not is_instance_valid(_overlay):return
	var ui_scale:=OCEAN_UI.scale_for(get_viewport())
	var available:=_overlay.size/ui_scale
	var panel_size:=Vector2(minf(available.x-24,820),minf(available.y-24,690))
	var compact:=panel_size.x<550
	for widget in _panel.find_children("*","Control",true,false):
		if not widget.has_meta("settings_widget"):continue
		var row:=widget.get_parent() as BoxContainer
		row.vertical=compact
		(row.get_child(0) as Control).custom_minimum_size.x=0 if compact else 160
	_panel.scale=Vector2.ONE*ui_scale
	_panel.size=panel_size;_panel.position=(_overlay.size-panel_size*ui_scale)*.5
