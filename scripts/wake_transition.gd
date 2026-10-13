extends CanvasLayer
## Holds the film frame through scene setup, then reveals ready dawn gameplay.
const ARRIVAL: Texture2D = preload("res://video/intro_arrival.jpg")
var arrival_texture: Texture2D
var resuming := false
var _image: TextureRect
var _background: ColorRect
var _black: ColorRect
var _status: Label
var _seconds := 0.0
var _warm_seconds := 0.0
var _ready_wait_seconds := 0.0
var _settled_frames := 0
var _reveal_seconds := 0.0
var _revealing := false
var _player: Node
var _setups: Array[Node] = []
var _stats_enabled := true
var _physics_enabled := true
var _process_enabled := true
var _input_enabled := true
var _unhandled_enabled := true
var _hud_visible := true
var _ui_input_states: Array[Dictionary] = []
var _holding := false
var _waves: AudioStreamPlayer

func _ready() -> void:
	layer = 100
	name = "WakeHandoff"
	_background = ColorRect.new()
	_background.color = Color.BLACK
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image = TextureRect.new()
	_image.texture = null if resuming else (arrival_texture if arrival_texture != null else ARRIVAL)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_left = -230
	_status.offset_right = 230
	_status.offset_top = -90
	_status.offset_bottom = -40
	add_child(_status)
	_status.hide()
	_waves = AudioStreamPlayer.new()
	_waves.stream = preload("res://audio/ocean_ambience.mp3")
	_waves.volume_db = -32
	add_child(_waves)
	_waves.play()

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player == null: return
		_stats_enabled = Stats.enabled
		Stats.enabled = false
		_physics_enabled = _player.is_physics_processing()
		_process_enabled = _player.is_processing()
		_input_enabled = _player.is_processing_input()
		_unhandled_enabled = _player.is_processing_unhandled_input()
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.set_process_input(false)
		_player.set_process_unhandled_input(false)
		GameSettings.release_gameplay_input()
		var hud := _player.get_node_or_null("CanvasLayer") as CanvasLayer
		if hud != null:
			_hud_visible = hud.visible
			hud.hide()
			# Global _input callbacks can still run in a hidden CanvasLayer.
			for control in hud.find_children("*", "Control", true, false):
				var direct := control.is_processing_input()
				var unhandled := control.is_processing_unhandled_input()
				if direct or unhandled:
					_ui_input_states.append({"node": control, "direct": direct, "unhandled": unhandled})
					control.set_process_input(false)
					control.set_process_unhandled_input(false)
		_holding = true
		var scene := get_tree().current_scene
		if scene != null:
			_setups.assign(scene.find_children("IslandSetup", "", true, false))
	_seconds += minf(delta, 0.1)
	if not _revealing:
		_black.color.a = smoothstep(0, 0.4, _seconds)
		_warm_seconds += minf(delta, 0.1)
		_settled_frames = _settled_frames + 1 if delta < 0.05 else 0
		_status.visible = _seconds >= 0.8
		_status.text = ("Restoring your raft" if resuming else "Waking on the ocean") + ".".repeat(1 + int(_seconds * 2) % 3)
		if not _world_ready(): return
		_ready_wait_seconds += minf(delta, 0.1)
		# A slower phone must still finish the transition if it never reaches 20 FPS.
		if _warm_seconds < 0.6 or (_settled_frames < 12 and _ready_wait_seconds < 2.0): return
		_revealing = true
		_background.hide()
		_image.hide()
		_status.hide()
		# Begin the reveal from opaque black even after a very slow setup frame.
		_black.color.a = 1.0
		return
	_reveal_seconds += minf(delta, 0.05)
	_black.color.a = 1.0 - smoothstep(0, 1.6, _reveal_seconds)
	_waves.volume_db = lerpf(-32, -60, clampf(_reveal_seconds / 1.6, 0, 1))
	if _reveal_seconds >= 1.6:
		_release_player()
		queue_free()

func _world_ready() -> bool:
	if is_instance_valid(_player) and _player.get("restoration_complete") == false:
		return false
	if is_instance_valid(_player):
		var action:=_player.get_node_or_null("SurvivalAction")
		if action!=null and not action.hands_prepared:return false
		var services:=_player.get_node_or_null("SurvivalServices")
		if services!=null and not services.ui.cooking_prepared:return false
	for setup in _setups:
		if is_instance_valid(setup) and setup.get("setup_complete") != true:
			return false
	return true

func _release_player() -> void:
	if not _holding: return
	_holding = false
	if is_instance_valid(_player):
		GameSettings.release_gameplay_input()
		_player.set_physics_process(_physics_enabled)
		_player.set_process(_process_enabled)
		_player.set_process_input(_input_enabled)
		_player.set_process_unhandled_input(_unhandled_enabled)
		var hud := _player.get_node_or_null("CanvasLayer") as CanvasLayer
		if hud != null: hud.visible = _hud_visible
		for state in _ui_input_states:
			if is_instance_valid(state.node):
				state.node.set_process_input(state.direct)
				state.node.set_process_unhandled_input(state.unhandled)
		_ui_input_states.clear()
		Stats.enabled = _stats_enabled

func _exit_tree() -> void:
	_release_player()
	if is_instance_valid(_waves): _waves.stop()
