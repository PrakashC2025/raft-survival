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
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.get("active_item") in ["Bow","Spear"]:
		queue_redraw()

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
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.get("active_item") in ["Bow","Spear"]:
		var center := Vector2(r, r)
		var equipment := player.get_node_or_null("SurvivalEquipment")
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(center + direction * (r + 3.0), center + direction * (r + 9.0), col, 1.5, true)
		draw_circle(center, 1.5, col)
		if equipment != null:
			var fraction: float = float(equipment.call("get_draw_fraction"))
			if fraction > 0.0:
				draw_arc(center, r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 32, Color(0.93, 0.77, 0.43), 2.0, true)
		var font := ThemeDB.fallback_font
		# Detailed controls appear on selection/HELP; aiming keeps only ammunition near the edge.
		var caption := "ARROWS  %d" % Inventory.total("Arrow")
		if player.active_item=="Spear":caption="SPEARS  %d"%Inventory.total("Spear")
		var view:=get_viewport_rect().size
		draw_string(font,Vector2(16,view.y*.60)-position,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,13,col)
