extends Control
## One mobile-sized film with its original soundtrack and timed captions.
signal finished
signal cancelled

const FILM: VideoStream = preload("res://video/new_game_intro.ogv")
const ARRIVAL: Texture2D = preload("res://video/intro_arrival.jpg")
const FILM_SIZE := Vector2(720, 408)
const DURATION := 31.033333
# Captions follow scene cuts and decoder position, never accumulated wall time.
const CUES := [
	[0.5, 3.65, "A stone from space was falling toward Earth."],
	[4.0, 5.9, "Life below went on."],
	[6.1, 8.9, "Then it struck the ocean."],
	[9.05, 15.7, "A wave higher than the buildings raced toward the shore."],
	[16.0, 19.1, "The flood swallowed our cities."],
	[19.3, 23.8, "Ninety-five percent of the land vanished.\nOnly a few islands remained."],
	[24.0, 26.5, "I woke alone on tied logs."],
	[26.7, 31.0, "With my rope gun, I must salvage, build, and survive."],
]

var elapsed := 0.0
var complete := false
var progress := 0.0
var playback_finished := false
var captioned_cues: Array[int] = []
var handoff_texture: Texture2D
var _video: VideoStreamPlayer
var _arrival: TextureRect
var _caption: Label
var _caption_panel: PanelContainer
var _status: Label
var _loading_bar: ProgressBar
var _skip: Button
var _cancel: Button
var _status_seconds := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	theme = preload("res://scripts/ui_surface.gd").theme()
	handoff_texture = ARRIVAL
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video = VideoStreamPlayer.new()
	_video.name = "IntroFilm"
	_video.stream = FILM
	_video.expand = true
	_video.loop = false
	_video.buffering_msec = 750
	_video.bus = &"Master"
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	_video.finished.connect(_on_video_finished)
	_arrival = TextureRect.new()
	_arrival.texture = ARRIVAL
	_arrival.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrival.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_arrival.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrival)
	_arrival.hide()
	_caption_panel = PanelContainer.new()
	_caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0.015, 0.025, 0.03, 0.82)
	caption_style.set_corner_radius_all(8)
	caption_style.set_content_margin_all(12)
	_caption_panel.add_theme_stylebox_override("panel", caption_style)
	add_child(_caption_panel)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9))
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_caption_panel.add_child(_caption)
	_skip = Button.new()
	_skip.text = "SKIP STORY"
	add_child(_skip)
	_skip.pressed.connect(finish)
	_cancel = Button.new()
	_cancel.text = "BACK TO MENU"
	add_child(_cancel)
	_cancel.pressed.connect(cancel_story)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("font_size", 18)
	add_child(_status)
	_status.hide()
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loading_bar)
	_loading_bar.hide()
	resized.connect(_layout)
	_layout()
	_update_caption(0.0)
	_video.play()


func total_duration() -> float:
	return DURATION


func cue_at(position_seconds: float) -> int:
	for i in range(CUES.size()):
		if position_seconds >= CUES[i][0] and position_seconds < CUES[i][1]:
			return i
	return -1


func _update_caption(position_seconds: float) -> void:
	var cue := cue_at(position_seconds)
	_caption_panel.visible = cue >= 0 and not complete
	_caption.text = str(CUES[cue][2]) if cue >= 0 else ""
	if cue >= 0 and not captioned_cues.has(cue):
		captioned_cues.append(cue)


func _layout() -> void:
	var film_size := FILM_SIZE * minf(size.x / FILM_SIZE.x, size.y / FILM_SIZE.y)
	_video.position = (size - film_size) * 0.5
	_video.size = film_size
	_arrival.position = _video.position
	_arrival.size = film_size
	var margin := clampf(size.x * 0.025, 12, 32)
	var button_width := minf(178, (size.x - margin * 3) * 0.5)
	_cancel.position = Vector2(margin, margin)
	_cancel.size = Vector2(button_width, 48)
	_skip.position = Vector2(size.x - button_width - margin, margin)
	_skip.size = Vector2(button_width, 48)
	var caption_width := minf(size.x - margin * 2, 1000)
	_caption_panel.position = Vector2((size.x - caption_width) * 0.5, size.y - 120)
	_caption_panel.size = Vector2(caption_width, 90)
	_caption.add_theme_font_size_override("font_size", int(clampf(size.x / 48, 16, 26)))
	_status.position = Vector2(margin, size.y - 90)
	_status.size = Vector2(size.x - margin * 2, 36)
	_loading_bar.position = Vector2(size.x * 0.3, size.y - 42)
	_loading_bar.size = Vector2(size.x * 0.4, 6)


func _process(delta: float) -> void:
	if not complete:
		elapsed = _video.stream_position
		_update_caption(elapsed)
	else:
		_status_seconds += minf(delta, 0.1)
		_status.text = "Preparing your raft" + ".".repeat(1 + int(_status_seconds * 2) % 3)
		_loading_bar.value = clampf(progress, 0, 1) * 100


func _on_video_finished() -> void:
	playback_finished = true
	elapsed = DURATION
	finish()


func finish() -> void:
	if complete: return
	complete = true
	# Hold the current frame on Skip without a synchronous GPU readback.
	# Natural completion uses a tiny still of the film's final raft shot.
	if not playback_finished and _video.get_video_texture() != null:
		handoff_texture = _video.get_video_texture()
	_arrival.texture = handoff_texture
	_arrival.show()
	_video.stop()
	_video.hide()
	_caption_panel.hide()
	_skip.hide()
	_status.show()
	_loading_bar.show()
	finished.emit()


func cancel_story() -> void:
	_video.stop()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _skip.visible and _skip.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			finish()
		elif _cancel.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			cancel_story()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_story()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(_video): _video.paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(_video): _video.paused = false
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and not GameSettings.is_open:
		if is_instance_valid(_video): cancel_story()


func _exit_tree() -> void:
	if is_instance_valid(_video): _video.stop()
