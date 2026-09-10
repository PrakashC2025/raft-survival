extends Control
## Island direction hint (HUD): a small diamond + distance readout that points
## toward the island. Sits above the island while it is on screen, clamps to
## the screen edge when it isn't, and fades out once the player arrives.
## Pure `_draw()` visuals, mouse-transparent, matching the rest of this
## project's HUD (see crosshair.gd / survival_hud.gd).

const DEFAULT_TINT := Color(1.0, 0.75, 0.4, 1.0) ## warm beacon orange

@export var beacon_group := "island_beacon"
@export var player_group := "player"
@export var edge_margin := 64.0
@export var fade_distance := 18.0 ## stop showing the hint within this range of the beacon

var _beacon: Node3D
var _player: Node3D
var _screen_pos := Vector2.ZERO
var _clamped := false
var _alpha := 0.0
var _dist_m := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	if _beacon == null or not is_instance_valid(_beacon):
		_beacon = get_tree().get_first_node_in_group(beacon_group)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group)
	if _beacon == null or _player == null:
		if _alpha > 0.0:
			_alpha = 0.0
			queue_redraw()
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var target: Vector3 = _beacon.global_position
	var to_target: Vector3 = target - cam.global_position
	var dist: float = to_target.length()
	# Fade out once you've arrived
	_alpha = clampf((dist - fade_distance) / 12.0, 0.0, 1.0)
	_dist_m = int(_player.global_position.distance_to(target) + 0.5)

	var vp := get_viewport_rect().size
	var on_screen: bool = to_target.dot(-cam.global_transform.basis.z) > 0.0
	if on_screen:
		_screen_pos = cam.unproject_position(target)
		_clamped = false
	else:
		# Behind or off the frustum: clamp a direction hint to the screen border
		var cam_x: Vector3 = cam.global_transform.basis.x
		var cam_y: Vector3 = cam.global_transform.basis.y
		var dir := Vector2(to_target.dot(cam_x), -to_target.dot(cam_y))
		if dir.length_squared() < 0.001:
			dir = Vector2(0.0, -1.0)
		var c := vp * 0.5
		var half := c - Vector2(edge_margin, edge_margin)
		var t: float = minf(half.x / absf(dir.x), half.y / absf(dir.y))
		_screen_pos = c + dir.normalized() * t
		_clamped = true

	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.01:
		return
	var col := DEFAULT_TINT
	col.a = _alpha * 0.95
	var edge_col := Color(col.r, col.g, col.b, _alpha * 0.25)

	var r := 13.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)

	if _clamped:
		# Edge hint: hollow diamond + distance
		var d := r * (1.0 + 0.12 * pulse)
		var pts := PackedVector2Array([
			_screen_pos + Vector2(0, -d), _screen_pos + Vector2(d, 0),
			_screen_pos + Vector2(0, d), _screen_pos + Vector2(-d, 0),
		])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, col.a * 0.25))
		draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0, true)
	else:
		# On-screen: small filled diamond floating above the island
		draw_arc(_screen_pos, r + 6.0 + 4.0 * pulse, 0.0, TAU, 32, edge_col, 2.0, true)
		var d := r * 0.75
		var pts := PackedVector2Array([
			_screen_pos + Vector2(0, -d), _screen_pos + Vector2(d, 0),
			_screen_pos + Vector2(0, d), _screen_pos + Vector2(-d, 0),
		])
		draw_colored_polygon(pts, col)

	var font := ThemeDB.fallback_font
	var text := "%d m" % _dist_m
	var fs := 15
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tpos := _screen_pos + Vector2(-tw * 0.5, r + 6.0 + fs)
	draw_string(font, tpos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7 * _alpha))
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
