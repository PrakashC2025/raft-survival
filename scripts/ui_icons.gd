class_name UiIcons
## Original vector icon library for the mobile UI. Every glyph is drawn from
## primitives (no external art): action buttons, build pieces, and survival
## resources. All drawing targets a CanvasItem (`c` = self).

static func _line(c: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	c.draw_line(a, b, col, w, true)


static func _circle(c: CanvasItem, center: Vector2, radius: float, col: Color, filled: bool = true, w: float = 0.0) -> void:
	if filled:
		c.draw_circle(center, radius, col)
	else:
		c.draw_arc(center, radius, 0.0, TAU, 40, col, maxf(w, 1.0), true)


# A single chevron pointing along `dir`.
static func chevron(c: CanvasItem, center: Vector2, dir: Vector2, length: float, w: float, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * length * 0.5
	var back := center - dir * length * 0.5
	_line(c, tip, back + perp * length * 0.42, w, col)
	_line(c, tip, back - perp * length * 0.42, w, col)


# Two chevrons (double arrow).
static func chevrons(c: CanvasItem, center: Vector2, dir: Vector2, length: float, w: float, col: Color) -> void:
	var off := dir * length * 0.26
	chevron(c, center - off, dir, length * 0.8, w, col)
	chevron(c, center + off, dir, length * 0.8, w, col)


static func arrow_up(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center + Vector2(0, r * 0.05), Vector2.UP, r * 0.55, w, col)
	_line(c, center + Vector2(0, r * 0.62), center + Vector2(0, -r * 0.15), w, col)


static func arrow_down(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center + Vector2(0, -r * 0.05), Vector2.DOWN, r * 0.55, w, col)
	_line(c, center + Vector2(0, -r * 0.62), center + Vector2(0, r * 0.15), w, col)


static func arrow_left(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center, Vector2.LEFT, r * 0.6, w, col)


static func check(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, 0.0), center + Vector2(-r * 0.1, r * 0.42), w, col)
	_line(c, center + Vector2(-r * 0.1, r * 0.42), center + Vector2(r * 0.55, -r * 0.45), w, col)


static func cross(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.45, -r * 0.45), center + Vector2(r * 0.45, r * 0.45), w, col)
	_line(c, center + Vector2(r * 0.45, -r * 0.45), center + Vector2(-r * 0.45, r * 0.45), w, col)


# Running person silhouette.
static func run(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	# head
	_circle(c, center + Vector2(0, -r * 0.55), r * 0.2, col)
	# torso leaning forward
	_line(c, center + Vector2(-r * 0.2, -r * 0.32), center + Vector2(r * 0.25, r * 0.05), w * 1.5, col)
	# front leg (up) and back leg (extended back)
	_line(c, center + Vector2(r * 0.25, r * 0.05), center + Vector2(r * 0.05, r * 0.75), w * 1.4, col)
	_line(c, center + Vector2(-r * 0.2, -r * 0.32), center + Vector2(-r * 0.5, r * 0.35), w * 1.3, col)
	_line(c, center + Vector2(-r * 0.5, r * 0.35), center + Vector2(-r * 0.62, r * 0.72), w * 1.2, col)
	# swing arm
	_line(c, center + Vector2(r * 0.25, r * 0.05), center + Vector2(r * 0.55, -r * 0.4), w * 1.2, col)


# Simple open hand (interact).
static func hand(c: CanvasItem, center: Vector2, r: float, _w: float, col: Color) -> void:
	# palm
	var palm := center + Vector2(0, r * 0.25)
	_circle(c, palm, r * 0.34, col)
	# four fingers
	for i in range(4):
		var fx := center.x + (float(i) - 1.5) * r * 0.18
		var fy := center.y - r * 0.05
		_circle(c, Vector2(fx, fy), r * 0.11, col)
	# thumb
	_circle(c, center + Vector2(-r * 0.45, r * 0.05), r * 0.13, col)


# Fishing-hook shape (rope throw).
static func hook(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	var top := center + Vector2(0, -r * 0.62)
	var hook_c := center + Vector2(0, r * 0.18)
	var rad := r * 0.34
	_line(c, top, hook_c + Vector2(0, -rad), w * 1.2, col)
	c.draw_arc(hook_c, rad, -PI * 0.5, PI * 1.15, 24, col, w * 1.2, true)
	# barb
	var tip := hook_c + Vector2(sin(PI * 1.15) * rad, cos(PI * 1.15) * rad)
	_line(c, tip, tip + Vector2(-0.22, -0.14) * r, w * 1.0, col)
	# eye
	_circle(c, top, w * 0.62, col, false, w * 0.8)


# Hammer (enter build mode).
static func hammer(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(r * 0.35, r * 0.5), center + Vector2(-r * 0.35, -r * 0.42), w * 1.6, col)
	# head sits across the top of the handle
	var hs := r * 0.3
	var hx := center.x - r * 0.3 - hs * 0.9
	var hy := center.y - r * 0.42 - hs * 0.28
	c.draw_rect(Rect2(hx, hy, hs * 1.8, hs * 0.56), col)
	# second (peen) block to make the head read as two-lobed
	c.draw_rect(Rect2(hx - hs * 0.34, hy + hs * 0.1, hs * 0.34, hs * 0.36), col)


# Pencil (pick up piece for editing).
static func pencil(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, r * 0.5), center + Vector2(r * 0.42, -r * 0.42), w * 1.2, col)
	var tip := center + Vector2(r * 0.42, -r * 0.42)
	_line(c, tip, tip + Vector2(r * 0.14, -r * 0.02), w * 1.2, col)
	_line(c, center + Vector2(r * 0.42, -r * 0.42), center + Vector2(r * 0.5, -r * 0.28), w * 1.2, col)


# Trash bin (remove piece).
static func trash(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, -r * 0.45), center + Vector2(r * 0.5, -r * 0.45), w, col)
	_line(c, center + Vector2(-r * 0.3, -r * 0.45), center + Vector2(-r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(r * 0.3, -r * 0.45), center + Vector2(r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(-r * 0.22, r * 0.55), center + Vector2(r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(-r * 0.06, -r * 0.32), center + Vector2(-r * 0.02, r * 0.4), w, col)
	_line(c, center + Vector2(r * 0.12, -r * 0.32), center + Vector2(r * 0.08, r * 0.4), w, col)


# Circular rotation arrow.
static func rotate(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	var arc_r := r * 0.52
	# big arc leaving a gap at the bottom-right
	var a0 := -0.6
	var a1 := 4.9
	c.draw_arc(center, arc_r, a0, a1, 32, col, w, true)
	# arrowhead on the tip of the arc, pointing along travel direction
	var end := center + Vector2(cos(a1), sin(a1)) * arc_r
	var tang := Vector2(-sin(a1), cos(a1))
	var tip := end + tang * r * 0.16
	var back := end - tang * r * 0.1
	var perp := Vector2(-tang.y, tang.x)
	var pts := PackedVector2Array([tip, back + perp * r * 0.14, back - perp * r * 0.14])
	c.draw_colored_polygon(pts, col)


# ============================================================
# BUILD PIECES (hotbar glyphs)
# ============================================================
static func piece(c: CanvasItem, kind: String, center: Vector2, r: float, col: Color) -> void:
	match kind:
		"Foundation":
			c.draw_rect(Rect2(center.x - r * 0.62, center.y - r * 0.3, r * 1.24, r * 0.6), col)
		"Wall":
			c.draw_rect(Rect2(center.x - r * 0.42, center.y - r * 0.62, r * 0.84, r * 1.24), col)
		"Roof":
			var pts := PackedVector2Array([
				center + Vector2(0, -r * 0.62),
				center + Vector2(r * 0.64, r * 0.34),
				center + Vector2(-r * 0.64, r * 0.34),
			])
			c.draw_colored_polygon(pts, col)
			c.draw_rect(Rect2(center.x - r * 0.64, center.y + r * 0.34, r * 1.28, r * 0.16), col)
		"Stairs":
			for i in range(4):
				var y := center.y + r * 0.62 - float(i) * r * 0.34
				var x0 := center.x - r * 0.66 + float(i) * r * 0.32
				c.draw_rect(Rect2(x0, y - r * 0.3, r * (0.66 - float(i) * 0.16) + r * 0.32, r * 0.3), col)
		"Door":
			c.draw_rect(Rect2(center.x - r * 0.44, center.y - r * 0.62, r * 0.88, r * 1.24), col)
			c.draw_rect(Rect2(center.x - r * 0.16, center.y - r * 0.62, r * 0.32, r * 1.24), Color(0.05, 0.07, 0.1, 0.9))
		"Window":
			c.draw_rect(Rect2(center.x - r * 0.48, center.y - r * 0.62, r * 0.96, r * 1.24), col)
			c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.5, r * 0.16, r * 1.0), Color(0.05, 0.07, 0.1, 0.9))
			c.draw_rect(Rect2(center.x - r * 0.44, center.y - r * 0.1, r * 0.88, r * 0.16), Color(0.05, 0.07, 0.1, 0.9))
		_:
			_circle(c, center, r * 0.5, col)


# ============================================================
# SURVIVAL RESOURCES (bag grid + top pills)
# ============================================================
static func item_color(item: String) -> Color:
	match item:
		"Wood":
			return Color(0.66, 0.45, 0.22)
		"Rope":
			return Color(0.78, 0.66, 0.38)
		"Plastic":
			return Color(0.35, 0.72, 0.9)
		"Metal":
			return Color(0.62, 0.65, 0.7)
		"Barrel":
			return Color(0.75, 0.28, 0.2)
		"Stone":
			return Color(0.55, 0.55, 0.58)
		"Coconut":
			return Color(0.43, 0.27, 0.14)
		"Banana":
			return Color(0.96, 0.78, 0.22)
		"Fish":
			return Color(0.45, 0.72, 0.82)
		"Spear":
			return Color(0.72, 0.74, 0.76)
		"Fishing Rod":
			return Color(0.64, 0.46, 0.25)
		"Sail Kit":
			return Color(0.84, 0.76, 0.58)
		"Motor Kit":
			return Color(0.42, 0.48, 0.5)
		"Life Vest":
			return Color(0.97, 0.42, 0.16)
	return Color(0.8, 0.8, 0.8)


static func item_icon(c: CanvasItem, item: String, center: Vector2, r: float) -> void:
	var col := item_color(item)
	match item:
		"Wood":
			# three stacked logs (end-on rings)
			for i in range(3):
				var off := Vector2(float(i - 1) * r * 0.55, r * 0.25)
				_circle(c, center + off, r * 0.3, col)
				_circle(c, center + off, r * 0.12, Color(0.9, 0.75, 0.45), true)
		"Rope":
			# coiled rope
			_circle(c, center, r * 0.5, col, false, r * 0.2)
			_circle(c, center, r * 0.18, col, false, r * 0.16)
			_circle(c, center, r * 0.05, col)
		"Plastic":
			# bottle
			c.draw_rect(Rect2(center.x - r * 0.2, center.y - r * 0.42, r * 0.4, r * 0.84), col)
			c.draw_rect(Rect2(center.x - r * 0.12, center.y - r * 0.62, r * 0.24, r * 0.24), col)
			c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.14, r * 0.6, r * 0.22), Color(0.9, 0.97, 1.0))
		"Metal":
			# ingot
			var pts := PackedVector2Array([
				center + Vector2(-r * 0.6, -r * 0.1),
				center + Vector2(-r * 0.4, -r * 0.5),
				center + Vector2(r * 0.4, -r * 0.5),
				center + Vector2(r * 0.6, -r * 0.1),
				center + Vector2(r * 0.35, r * 0.5),
				center + Vector2(-r * 0.35, r * 0.5),
			])
			c.draw_colored_polygon(pts, col)
		"Barrel":
			c.draw_rect(Rect2(center.x - r * 0.42, center.y - r * 0.62, r * 0.84, r * 1.24), col)
			c.draw_arc(center + Vector2(-r * 0.42, 0), r * 0.42, -PI * 0.5, PI * 0.5, 12, col, r * 0.18, true)
			c.draw_arc(center + Vector2(r * 0.42, 0), r * 0.42, PI * 0.5, PI * 1.5, 12, col, r * 0.18, true)
			_line(c, center + Vector2(-r * 0.42, -r * 0.2), center + Vector2(r * 0.42, -r * 0.2), r * 0.12, Color(0.9, 0.8, 0.6))
			_line(c, center + Vector2(-r * 0.42, r * 0.2), center + Vector2(r * 0.42, r * 0.2), r * 0.12, Color(0.9, 0.8, 0.6))
		"Stone":
			var pts2 := PackedVector2Array([
				center + Vector2(-r * 0.55, r * 0.2),
				center + Vector2(-r * 0.3, -r * 0.45),
				center + Vector2(r * 0.25, -r * 0.5),
				center + Vector2(r * 0.55, -r * 0.1),
				center + Vector2(r * 0.2, r * 0.5),
				center + Vector2(-r * 0.4, r * 0.45),
			])
			c.draw_colored_polygon(pts2, col)
		"Coconut":
			_circle(c, center, r * 0.48, col)
			_circle(c, center + Vector2(-r * 0.12, -r * 0.12), r * 0.08, Color(0.83, 0.68, 0.45))
		"Banana":
			c.draw_arc(center + Vector2(0, -r * 0.05), r * 0.48, -0.85, 2.4, 22, col, r * 0.24, true)
			_line(c, center + Vector2(-r * 0.39, -r * 0.32), center + Vector2(-r * 0.5, -r * 0.48), 1.8, Color(0.35, 0.25, 0.12))
		"Fish":
			var fish_body := PackedVector2Array([
				center + Vector2(-r * 0.55, 0), center + Vector2(-r * 0.2, -r * 0.36),
				center + Vector2(r * 0.34, -r * 0.28), center + Vector2(r * 0.54, 0),
				center + Vector2(r * 0.34, r * 0.28), center + Vector2(-r * 0.2, r * 0.36),
			])
			c.draw_colored_polygon(fish_body, col)
			var tail := PackedVector2Array([center + Vector2(r * 0.42, 0), center + Vector2(r * 0.72, -r * 0.28), center + Vector2(r * 0.72, r * 0.28)])
			c.draw_colored_polygon(tail, col.lightened(0.12))
			_circle(c, center + Vector2(-r * 0.28, -r * 0.08), r * 0.055, Color(0.05, 0.08, 0.1))
		"Spear":
			_line(c, center + Vector2(-r * 0.55, r * 0.55), center + Vector2(r * 0.45, -r * 0.45), maxf(r * 0.12, 1.5), col)
			var spear_tip := PackedVector2Array([center + Vector2(r * 0.72, -r * 0.72), center + Vector2(r * 0.1, -r * 0.48), center + Vector2(r * 0.48, -r * 0.1)])
			c.draw_colored_polygon(spear_tip, Color(0.82, 0.86, 0.88))
		"Fishing Rod":
			_line(c, center + Vector2(-r * 0.5, r * 0.5), center + Vector2(r * 0.36, -r * 0.55), maxf(r * 0.1, 1.5), col)
			c.draw_arc(center + Vector2(r * 0.4, -r * 0.48), r * 0.2, -0.8, 1.7, 10, Color(0.82, 0.88, 0.9), maxf(r * 0.06, 1.0), true)
		"Sail Kit":
			_line(c, center + Vector2(-r * 0.45, r * 0.55), center + Vector2(-r * 0.45, -r * 0.6), maxf(r * 0.08, 1.2), col)
			var sail_icon := PackedVector2Array([center + Vector2(-r * 0.35, -r * 0.48), center + Vector2(r * 0.58, r * 0.18), center + Vector2(-r * 0.35, r * 0.18)])
			c.draw_colored_polygon(sail_icon, col)
		"Motor Kit":
			c.draw_rect(Rect2(center.x - r * 0.35, center.y - r * 0.35, r * 0.62, r * 0.62), col)
			_line(c, center + Vector2(-r * 0.05, r * 0.28), center + Vector2(r * 0.24, r * 0.58), maxf(r * 0.09, 1.4), col)
		"Life Vest":
			c.draw_rect(Rect2(center.x - r * 0.48, center.y - r * 0.44, r * 0.36, r * 0.88), col)
			c.draw_rect(Rect2(center.x + r * 0.12, center.y - r * 0.44, r * 0.36, r * 0.88), col)
			c.draw_rect(Rect2(center.x - r * 0.12, center.y - r * 0.08, r * 0.24, r * 0.16), Color(0.98, 0.86, 0.62))
		_:
			_circle(c, center, r * 0.5, col)


static func status_icon(c: CanvasItem, kind: String, center: Vector2, r: float, col: Color) -> void:
	match kind:
		"health":
			c.draw_rect(Rect2(center.x - r * 0.12, center.y - r * 0.55, r * 0.24, r * 1.1), col)
			c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.12, r * 1.1, r * 0.24), col)
		"hunger":
			# bowl
			c.draw_arc(center + Vector2(0, r * 0.1), r * 0.5, PI, TAU, 20, col, r * 0.2, true)
			_line(c, center + Vector2(-r * 0.6, r * 0.1), center + Vector2(r * 0.6, r * 0.1), r * 0.2, col)
		"thirst":
			# droplet
			var pts := PackedVector2Array([
				center + Vector2(0, -r * 0.6),
				center + Vector2(r * 0.42, r * 0.05),
				center + Vector2(0, r * 0.55),
				center + Vector2(-r * 0.42, r * 0.05),
			])
			c.draw_colored_polygon(pts, col)


static func backpack(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.38, r * 1.1, r * 0.85), col)
	# flap
	c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.52, r * 1.1, r * 0.2), col)
	# straps
	c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.3, r * 0.16, r * 0.62), Color(0.9, 0.85, 0.7))
	c.draw_rect(Rect2(center.x + r * 0.14, center.y - r * 0.3, r * 0.16, r * 0.62), Color(0.9, 0.85, 0.7))
	# pocket
	c.draw_rect(Rect2(center.x - r * 0.2, center.y - r * 0.1, r * 0.4, r * 0.36), Color(0.85, 0.7, 0.45))
