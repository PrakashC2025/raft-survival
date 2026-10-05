extends CanvasLayer
## Carries the last cinematic frame across scene entry, then releases gameplay.
const ART := preload("res://textures/ui/flooded_world_story.png")
var _image: TextureRect
var _black: ColorRect
var _seconds := 0.0
var _frames := 0
var _player: Node
var _stats_enabled := true
var _physics_enabled := true
var _process_enabled := true
var _hud_visible := true
func _ready() -> void:
	layer = 100
	name = "WakeHandoff"
	var crop := AtlasTexture.new()
	crop.atlas = ART
	crop.region = Rect2(Vector2(ART.get_width(),ART.get_height())*0.5,Vector2(ART.get_width(),ART.get_height())*0.5)
	_image = TextureRect.new()
	_image.texture = crop
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black = ColorRect.new()
	_black.color = Color(0,0,0,0)
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var waves := AudioStreamPlayer.new()
	waves.stream = preload("res://audio/ocean_ambience.mp3")
	waves.volume_db = -26
	add_child(waves)
	waves.play()
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
		_player.set_physics_process(false)
		_player.set_process(false)
		var hud := _player.get_node_or_null("CanvasLayer") as CanvasLayer
		if hud != null:
			_hud_visible = hud.visible
			hud.hide()
	_frames += 1
	if _frames < 3: return
	_seconds += minf(delta,0.1)
	if _seconds < 0.4:
		_black.color.a = smoothstep(0,0.4,_seconds)
	else:
		_image.hide()
		_black.color.a = 1-smoothstep(0.4,2.0,_seconds)
	if _seconds >= 2.0:
		_release_player()
		queue_free()
func _release_player() -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(_physics_enabled)
		_player.set_process(_process_enabled)
		var hud := _player.get_node_or_null("CanvasLayer") as CanvasLayer
		if hud != null: hud.visible = _hud_visible
		Stats.enabled = _stats_enabled
func _exit_tree() -> void:
	_release_player()
