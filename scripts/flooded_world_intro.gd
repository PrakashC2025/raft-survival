extends Control
## One atlas and prerecorded narration; shots never cut speech short.
signal finished
signal cancelled
const ART: Texture2D = preload("res://textures/ui/flooded_world_story.png")
const VOICES := [preload("res://audio/intro_space.wav"),preload("res://audio/intro_city.wav"),preload("res://audio/intro_flood.wav"),preload("res://audio/intro_raft.wav")]
const CAPTIONS := ["A world before the flood.","The impact came from the sky.","Ninety-five percent of the land vanished beneath the ocean.","You wake alone. Salvage. Build. Survive."]
const FRAME_SECONDS := 5.0
var elapsed := 0.0
var complete := false
var progress := 0.0
var _skip: Button
var _cancel: Button
var _voice: AudioStreamPlayer
var _effects: AudioStreamPlayer
var _ocean: AudioStreamPlayer
var _shot := -1
var _durations: Array[float] = []
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	theme = preload("res://scripts/ui_surface.gd").theme()
	for clip in VOICES: _durations.append(maxf(FRAME_SECONDS,clip.get_length()+0.85))
	_skip = Button.new()
	_skip.text = "SKIP STORY"
	add_child(_skip)
	_skip.pressed.connect(finish)
	_cancel = Button.new()
	_cancel.text = "BACK TO MENU"
	add_child(_cancel)
	_cancel.pressed.connect(func(): cancelled.emit())
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -1
	add_child(_voice)
	_effects = AudioStreamPlayer.new()
	_effects.volume_db = -9
	add_child(_effects)
	_ocean = AudioStreamPlayer.new()
	_ocean.stream = preload("res://audio/ocean_ambience.mp3")
	_ocean.volume_db = -42
	add_child(_ocean)
	_ocean.play()
	_layout_buttons()
	_start_shot(0)
func shot_start(index: int) -> float:
	var result := 0.0
	for i in range(mini(index,_durations.size())): result += _durations[i]
	return result
func total_duration() -> float:
	return shot_start(4)
func shot_at(at: float) -> int:
	for i in range(4):
		if at < shot_start(i+1): return i
	return 3
func _layout_buttons() -> void:
	_skip.position = Vector2(maxf(22,size.x-194),22)
	_skip.size = Vector2(172,48)
	_cancel.position = Vector2(22,22)
	_cancel.size = Vector2(178,48)
func _start_shot(index: int) -> void:
	_shot = index
	_voice.stream = VOICES[index]
	_voice.play()
	_ocean.volume_db = -42 if index < 2 else -25
	if index == 1 or index == 2:
		_effects.stream = preload("res://audio/intro_impact.wav") if index == 2 else preload("res://audio/intro_approach.wav")
		_effects.play()
func _process(delta: float) -> void:
	if not complete:
		elapsed += minf(delta,0.2)
		var index := shot_at(elapsed)
		if index != _shot: _start_shot(index)
		if elapsed >= total_duration(): finish()
	_layout_buttons()
	queue_redraw()
func finish() -> void:
	if complete: return
	complete = true
	elapsed = total_duration()-0.001
	_voice.stop()
	_effects.stop()
	_skip.disabled = true
	_skip.text = "PREPARING RAFT"
	finished.emit()
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _skip.get_global_rect().has_point(event.position) and not complete:
			finish()
			get_viewport().set_input_as_handled()
		elif _cancel.get_global_rect().has_point(event.position):
			cancelled.emit()
			get_viewport().set_input_as_handled()
func _draw() -> void:
	if _durations.is_empty(): return
	var index := shot_at(elapsed)
	var fraction := clampf((elapsed-shot_start(index))/_durations[index],0,1)
	var half := Vector2(ART.get_width(),ART.get_height())*0.5
	var source := Rect2(Vector2(index%2,int(index/2.0))*half,half)
	var dest_size := half*maxf(size.x/half.x,size.y/half.y)*lerpf(1,1.06,fraction)
	draw_texture_rect_region(ART,Rect2((size-dest_size)*0.5,dest_size),source)
	var fade := maxf(1-smoothstep(0,0.1,fraction),smoothstep(0.9,1,fraction))
	if complete: fade = 0
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,fade))
	draw_rect(Rect2(0,size.y-125,size.x,125),Color(0.01,0.03,0.04,0.86))
	var fs := int(clampf(size.x/44,16,28))
	draw_string(ThemeDB.fallback_font,Vector2(34,size.y-76),CAPTIONS[index],HORIZONTAL_ALIGNMENT_LEFT,size.x-68,fs,Color(0.94,0.91,0.82))
	if complete:
		draw_string(ThemeDB.fallback_font,Vector2(34,size.y-38),"Preparing your raft · %d%%" % roundi(progress*100),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.6,0.84,0.86))
