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
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
	if _player != null:
		_beacon = _find_target_beacon()
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
	var vp := get_viewport_rect().size
	if not to_target.is_finite() or vp.x < 32.0 or vp.y < 32.0:
		_alpha = 0.0
		queue_redraw()
		return
	var dist: float = to_target.length()
	# Fade out once you've arrived
	_alpha = clampf((dist - fade_distance) / 12.0, 0.0, 1.0)
	_dist_m = int(_player.global_position.distance_to(target) + 0.5)

	var margin := clampf(edge_margin, 18.0, minf(vp.x, vp.y) * 0.5 - 1.0)
	var safe_rect := Rect2(Vector2.ONE * margin, vp - Vector2.ONE * margin * 2.0)
	var in_front: bool = to_target.dot(-cam.global_transform.basis.z) > 0.01
	var projected := cam.unproject_position(target) if in_front else Vector2.ZERO
	var on_screen := in_front and projected.is_finite() and safe_rect.has_point(projected)
	if on_screen:
		_screen_pos = projected
		_clamped = false
	else:
		# Behind or off the frustum: clamp a direction hint to the screen border
		var cam_x: Vector3 = cam.global_transform.basis.x
		var cam_y: Vector3 = cam.global_transform.basis.y
		var dir := projected - vp * 0.5 if in_front and projected.is_finite() else Vector2(to_target.dot(cam_x), -to_target.dot(cam_y))
		if dir.length_squared() < 0.001:
			dir = Vector2(0.0, -1.0)
		dir = dir.normalized()
		var c := vp * 0.5
		var half := c - Vector2.ONE * margin
		var t: float = minf(half.x / maxf(absf(dir.x), 0.000001), half.y / maxf(absf(dir.y), 0.000001))
		_screen_pos = c + dir * t
		_clamped = true

	queue_redraw()

func _find_target_beacon() -> Node3D:
	var beacons := get_tree().get_nodes_in_group(beacon_group)
	var nearest_outside: Node3D = null
	var nearest_any: Node3D = null
	var outside_distance := INF
	var any_distance := INF
	for candidate in beacons:
		if not (candidate is Node3D) or not is_instance_valid(candidate):
			continue
		var beacon := candidate as Node3D
		var distance := _player.global_position.distance_to(beacon.global_position)
		if distance < any_distance:
			any_distance = distance
			nearest_any = beacon
		if distance >= fade_distance and distance < outside_distance:
			outside_distance = distance
			nearest_outside = beacon
	return nearest_outside if nearest_outside != null else nearest_any


func _draw() -> void:
	if _alpha <= 0.01 or not _screen_pos.is_finite():
		return
	# Draw the small diamond around a local origin. Projected world coordinates
	# must never enter polygon vertices, where float precision can collapse them.
	draw_set_transform(_screen_pos)
	var col := DEFAULT_TINT
	col.a = _alpha * 0.95
	var edge_col := Color(col.r, col.g, col.b, _alpha * 0.25)

	var r := 13.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)

	if _clamped:
		# Edge hint: hollow diamond + distance
		var d := r * (1.0 + 0.12 * pulse)
		var pts := PackedVector2Array([
			Vector2(0, -d), Vector2(d, 0),
			Vector2(0, d), Vector2(-d, 0),
		])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, col.a * 0.25))
		draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0, true)
	else:
		# On-screen: small filled diamond floating above the island
		draw_arc(Vector2.ZERO, r + 6.0 + 4.0 * pulse, 0.0, TAU, 32, edge_col, 2.0, true)
		var d := r * 0.75
		var pts := PackedVector2Array([
			Vector2(0, -d), Vector2(d, 0),
			Vector2(0, d), Vector2(-d, 0),
		])
		draw_colored_polygon(pts, col)

	var font := ThemeDB.fallback_font
	var text := "%d m" % _dist_m
	var fs := 15
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tpos := Vector2(-tw * 0.5, r + 6.0 + fs)
	draw_string(font, tpos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7 * _alpha))
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
