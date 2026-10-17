extends RefCounted
## Cached matte panels, brushed-metal rims, glassmorphic plates and tactile controls.
static var _styles: Dictionary = {}
const CACHE_LIMIT := 192

# Modern nautical survival color palette
const BRASS := Color(0.82, 0.70, 0.48, 0.90)
const INK := Color(0.040, 0.055, 0.070, 0.94)
const SLATE_DEEP := Color(0.035, 0.050, 0.068, 0.90)
const SLATE_CARD := Color(0.050, 0.075, 0.098, 0.95)
const CYAN := Color(0.35, 0.82, 0.92, 0.95)
const EMERALD := Color(0.35, 0.90, 0.55, 0.95)
const RUBY := Color(0.95, 0.32, 0.25, 0.95)
const AMBER := Color(0.96, 0.68, 0.22, 0.95)
const AZURE := Color(0.24, 0.75, 0.96, 0.95)

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
	if filled and radius >= 5.0 and rect.size.x > 36.0 and rect.size.y > 22.0:
		var inset := minf(radius, rect.size.x * 0.18)
		canvas.draw_line(rect.position + Vector2(inset, 1.5),
			Vector2(rect.end.x - inset, rect.position.y + 1.5), Color(1.0, 1.0, 1.0, 0.16), 1.0, true)
		canvas.draw_line(Vector2(rect.position.x + inset, rect.end.y - 1.5),
			rect.end - Vector2(inset, 1.5), Color(0.0, 0.0, 0.0, 0.35), 1.0, true)

static func dial(canvas: CanvasItem, center: Vector2, radius: float, accent: Color, pressed: bool = false) -> void:
	# Outer soft drop shadow
	canvas.draw_circle(center + Vector2(0, 2.5), radius + 1.5, Color(0, 0, 0, 0.38))
	# Base disc with frosted slate tone
	canvas.draw_circle(center, radius, Color(0.07, 0.095, 0.115, 0.90))
	# Inner disc depth
	var inner_col := INK.lightened(0.12) if pressed else INK
	canvas.draw_circle(center, maxf(radius - 2.5, 1.0), inner_col)
	# Accent rim ring
	canvas.draw_arc(center, radius - 0.75, 0.0, TAU, 44, accent, 1.6, true)
	# Subtle glass gloss arc along top rim
	canvas.draw_arc(center, radius - 3.2, PI * 1.15, PI * 1.85, 24, Color(1.0, 1.0, 1.0, 0.22), 1.2, true)

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var color := Color(0.08, 0.11, 0.13, 0.94)
			if state == "hover": color = color.lightened(0.12)
			if state == "pressed": color = Color(0.18, 0.24, 0.26, 0.96)
			var box := style(8, color).duplicate() as StyleBoxFlat
			box.set_content_margin_all(12)
			box.set_border_width_all(1)
			box.border_color = BRASS if state != "disabled" else Color(0.25, 0.28, 0.30)
			result.set_stylebox(state, type_name, box)
		result.set_color("font_color", type_name, Color(0.94, 0.93, 0.88))
		result.set_stylebox("focus", type_name, style(8, CYAN, false, 2))
	result.set_color("font_color", "Label", Color(0.92, 0.93, 0.89))
	return result
