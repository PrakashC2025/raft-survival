extends Control

# A small, always-centered hollow-circle reticle drawn in screen space.
# Lives under a CanvasLayer so it is independent of 3D movement/camera.
# Its center sits at (screen center X, screen center Y + aim_vertical_offset),
# and player.gd orients the interaction RayCast through this exact screen point.

enum State { NONE, ITEM, BUILD }

@export var crosshair_size: float = 24.0
@export var line_width: float = 3.0
# Negative = above exact screen center (creates visible space above the player).
@export var aim_vertical_offset: float = 0.0
@export var color_idle: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var color_item: Color = Color(0.4, 1.0, 0.4, 0.95)
@export var color_build: Color = Color(0.4, 0.8, 1.0, 0.95)

var state: int = State.NONE

func _ready() -> void:
	# Never intercept the mouse — camera look must pass through.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(crosshair_size, crosshair_size)
	anchors_preset = Control.PRESET_TOP_LEFT
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_position_reticle)
	_position_reticle()

func _process(_delta: float) -> void:
	_position_reticle()

func set_state(value: int) -> void:
	state = value
	queue_redraw()

func _position_reticle() -> void:
	var vp := get_viewport_rect().size
	var half := custom_minimum_size * 0.5
	# Center horizontally; offset vertically by the configured amount.
	position = Vector2(vp.x * 0.5 - half.x, vp.y * 0.5 + aim_vertical_offset - half.y)

func _draw() -> void:
	var col: Color = color_idle
	if state == State.ITEM:
		col = color_item
	elif state == State.BUILD:
		col = color_build

	var r: float = crosshair_size * 0.5
	var radius: float = max(r - line_width * 0.5, 0.5)
	draw_arc(Vector2(r, r), radius, 0.0, TAU, 32, col, line_width, true)
