extends RefCounted
## Cached matte panels, brushed-metal rims and tactile controls.
static var _styles: Dictionary = {}
const CACHE_LIMIT := 192
const BRASS := Color(0.72, 0.61, 0.42, 0.80)
const INK := Color(0.045, 0.060, 0.063, 0.94)

static func style(radius: float, color: Color, filled: bool = true, width: float = 1.0) -> StyleBoxFlat:
	var rounded := maxi(0, int(radius))
	var border := 0 if filled else maxi(1, int(width))
	var key := "%d:%s:%s:%d" % [rounded, color.to_html(true), filled, border]
	var cached: StyleBoxFlat = _styles.get(key)
	if cached != null:
		return cached
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(rounded)
	box.bg_color = color if filled else Color.TRANSPARENT
	box.border_color = color
	box.set_border_width_all(border)
	box.anti_aliasing = true
	if _styles.size() >= CACHE_LIMIT:
		_styles.clear()
	_styles[key] = box
	return box

static func panel(canvas: CanvasItem, rect: Rect2, radius: float, color: Color,
		filled: bool = true, width: float = 1.0) -> void:
	canvas.draw_style_box(style(radius, color, filled, width), rect)
	# Restrained light on the bevel gives dark plates depth without a blur pass.
	if filled and radius >= 6.0 and rect.size.x > 45.0 and rect.size.y > 28.0:
		var inset := minf(radius, rect.size.x * 0.2)
		canvas.draw_line(rect.position + Vector2(inset, 2),
			Vector2(rect.end.x - inset, rect.position.y + 2), Color(0.95, 0.91, 0.80, 0.12), 1.0, true)
		canvas.draw_line(Vector2(rect.position.x + inset, rect.end.y - 2),
			rect.end - Vector2(inset, 2), Color(0, 0, 0, 0.25), 1.0, true)

static func dial(canvas: CanvasItem, center: Vector2, radius: float, accent: Color, pressed: bool = false) -> void:
	canvas.draw_circle(center + Vector2(0, 2), radius + 1, Color(0, 0, 0, 0.25))
	canvas.draw_circle(center, radius, Color(0.13, 0.15, 0.14, 0.84))
	canvas.draw_circle(center, maxf(radius - 2.5, 1), INK.lightened(0.10) if pressed else INK)
	canvas.draw_arc(center, radius - 0.5, 0, TAU, 36, accent, 1.5, true)
	canvas.draw_arc(center, radius - 3.5, PI * 1.12, PI * 1.88, 20, Color(1, 0.96, 0.85, 0.18), 1, true)

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var color := Color(0.095, 0.12, 0.12)
			if state == "hover": color = color.lightened(0.1)
			if state == "pressed": color = Color(0.20, 0.23, 0.19)
			var box := style(8, color).duplicate() as StyleBoxFlat
			box.set_content_margin_all(12)
			box.set_border_width_all(1)
			box.border_color = BRASS if state != "disabled" else Color(0.25, 0.27, 0.25)
			result.set_stylebox(state, type_name, box)
		result.set_color("font_color", type_name, Color(0.92, 0.91, 0.85))
		result.set_stylebox("focus", type_name, style(8, BRASS, false, 2))
	result.set_color("font_color", "Label", Color(0.90, 0.91, 0.87))
	return result
