extends Control
## ============================================================
## MAIN MENU — survival-styled ocean start screen.
## Fully drawn from primitives (no external art): a dusk sky with a low sun
## over animated waves, a wooden title plaque, and wood-plank action buttons.
##   - No saves            -> NEW GAME only
##   - Autosave present    -> CONTINUE (resumes it)
##   - Quick-save present  -> QUICK SAVE (second resume option)
## Each resume button shows the saved in-game day/time.
## ============================================================

const GAME_SCENE := "res://main.tscn"

# button ids in display order
var _buttons: Array = []          # of {id, label, sub}
var _btn_rects: Array = []        # parallel Rect2
var _hover := -1
var _press := -1
var _busy := false
var _t := 0.0
var _vp := Vector2.ZERO
var _title_w := 0.0

func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_buttons.clear()
	if Inventory.has_save("main"):
		_buttons.append({"id": "continue", "label": "CONTINUE",
			"sub": _save_sub("main")})
	if Inventory.has_save("quick"):
		_buttons.append({"id": "quick", "label": "QUICK SAVE",
			"sub": _save_sub("quick")})
	_buttons.append({"id": "new", "label": "NEW GAME", "sub": ""})
	queue_redraw()


## Human label for a save slot: "DAY n · hh:mm" from the saved game time.
func _save_sub(slot: String) -> String:
	var info: Dictionary = Inventory.save_info(slot)
	if info.has("game_time"):
		var gt: float = float(info["game_time"])
		var day: int = int(floorf(gt / 24.0)) + 1
		var h: int = int(gt) % 24
		var m: int = int((gt - floorf(gt)) * 60.0) % 60
		return "DAY %d  ·  %02d:%02d" % [day, h, m]
	if info.has("saved_at"):
		var stamp: String = Time.get_datetime_string_from_unix_time(int(info["saved_at"]), true)
		if stamp.length() >= 16:
			return "SAVED  " + stamp.substr(0, 16)
	return ""


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	_vp = size
	# hover tracking (mouse)
	if not OS.has_feature("mobile") and not OS.has_feature("android") \
			and not OS.has_feature("ios"):
		var mp := get_global_mouse_position()
		_hover = _btn_at(mp)
	queue_redraw()  # animated waves need a redraw every frame


# ============================================================
# INPUT — custom buttons (works with mouse and touch)
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = _btn_at(mb.position)
			else:
				if _btn_at(mb.position) == _press:
					_activate(_press, mb.position)
				_press = -1
			queue_redraw()
			accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press = _btn_at(t.position)
		elif _press >= 0:
			if _btn_at(t.position) == _press:
				_activate(_press, t.position)
			_press = -1
		queue_redraw()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _btn_at(pos: Vector2) -> int:
	for i in range(_btn_rects.size()):
		if (_btn_rects[i] as Rect2).has_point(pos):
			return i
	return -1


func _activate(btn_idx: int, _pos: Vector2) -> void:
	if btn_idx < 0 or btn_idx >= _buttons.size() or _busy:
		return
	_busy = true
	var id: String = _buttons[btn_idx]["id"]
	if id == "continue":
		Inventory.load_game("main")
	elif id == "quick":
		Inventory.load_game("quick")
	else:
		Inventory.new_game_reset()
	get_tree().change_scene_to_file(GAME_SCENE)


# ============================================================
# LAYOUT
# ============================================================
func _layout_buttons() -> void:
	_btn_rects.clear()
	var s := _vp
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var bw: float = minf(s.x * 0.78, 440.0)
	var bhs: Array = []
	for b in _buttons:
		bhs.append(104.0 if str(b["sub"]) != "" else 92.0)
	var gap: float = 20.0
	var total_h: float = 0.0
	for h in bhs:
		total_h += float(h)
	total_h += gap * float(maxi(0, bhs.size() - 1))
	var y: float = (s.y * 0.5) - total_h * 0.5 + s.y * 0.03
	for i in range(_buttons.size()):
		var w2: float = bw
		if str(_buttons[i]["sub"]) != "":
			w2 = bw  # same width; subs are short
		_btn_rects.append(Rect2((s.x - w2) * 0.5, y, w2, bhs[i]))
		y += bhs[i] + gap


# ============================================================
# DRAW — sky / sun / ocean / title / buttons
# ============================================================
func _draw() -> void:
	if _vp.x <= 0.0:
		_vp = size
	if _vp.x <= 0.0:
		return
	_layout_buttons()
	var s := _vp
	var horizon: float = s.y * 0.55
	_draw_sky(s, horizon)
	_draw_sun(s, horizon)
	_draw_ocean(s, horizon)
	_draw_title(s)
	_draw_buttons(s)
	_draw_footer(s)


func _lerp_color(a: Color, b: Color, k: float) -> Color:
	var kk := clampf(k, 0.0, 1.0)
	return Color(a.r + (b.r - a.r) * kk, a.g + (b.g - a.g) * kk,
		a.b + (b.b - a.b) * kk, a.a + (b.a - a.a) * kk)


func _draw_sky(s: Vector2, horizon: float) -> void:
	# banded vertical gradient: deep night navy -> teal -> warm horizon glow
	var top_c := Color(0.008, 0.03, 0.06)
	var mid_c := Color(0.03, 0.12, 0.16)
	var glow_c := Color(0.32, 0.16, 0.1)
	var bands := 30
	var band_h: float = horizon / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col: Color
		if k < 0.55:
			col = _lerp_color(top_c, mid_c, k / 0.55)
		else:
			col = _lerp_color(mid_c, glow_c, (k - 0.55) / 0.45)
		draw_rect(Rect2(0.0, float(i) * band_h, s.x, band_h + 1.0), col)


func _draw_sun(s: Vector2, horizon: float) -> void:
	# low warm sun with a soft glow, sitting just on the horizon right-of-center
	var cx: float = s.x * 0.72
	var cy: float = horizon - s.y * 0.03
	var sr: float = minf(s.y * 0.085, 84.0)
	# glow rings
	for g in range(6, 0, -1):
		var gr: float = sr * (1.0 + float(g) * 0.34)
		var ga: float = 0.05 + float(6 - g) * 0.008
		draw_circle(Vector2(cx, cy), gr, Color(1.0, 0.62, 0.28, ga))
	draw_circle(Vector2(cx, cy), sr, Color(1.0, 0.8, 0.42, 0.95))
	draw_circle(Vector2(cx, cy), sr * 0.82, Color(1.0, 0.94, 0.72, 1.0))
	# horizontal haze band around the sun line
	draw_rect(Rect2(0.0, cy - sr * 0.7, s.x, sr * 1.6), Color(1.0, 0.55, 0.3, 0.05))


func _draw_ocean(s: Vector2, horizon: float) -> void:
	var depth: float = s.y - horizon
	var bands := 26
	var band_h: float = depth / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col := _lerp_color(Color(0.03, 0.14, 0.17), Color(0.005, 0.02, 0.035), k)
		draw_rect(Rect2(0.0, horizon + float(i) * band_h, s.x, band_h + 1.0), col)
	# animated wave crest lines (cheap: a few sine polylines)
	var rows := 10
	for r in range(rows):
		var ky: float = float(r) / float(rows)
		var base_y: float = horizon + 6.0 + ky * depth * 0.92
		var amp: float = 2.5 + ky * depth * 0.09
		var speed: float = 1.6 + ky * 0.9
		var alpha: float = 0.34 * (1.0 - ky * 0.72)
		var pts := PackedVector2Array()
		var segs := 26
		for i in range(segs + 1):
			var x: float = s.x * float(i) / float(segs)
			var ph: float = sin(x * 0.018 + _t * speed + float(r) * 1.7)
			var ph2: float = sin(x * 0.007 - _t * speed * 0.6 + float(r))
			pts.append(Vector2(x, base_y + ph * amp + ph2 * amp * 0.6))
		draw_polyline(pts, Color(0.75, 0.95, 1.0, alpha), 1.4, true)
	# sun glint path (soft vertical shimmer under the sun)
	var gx: float = s.x * 0.72
	for k in range(16):
		var gy: float = horizon + 8.0 + float(k) * (depth * 0.8) / 16.0
		var gw: float = 3.0 + float(k) * 1.5
		var ga: float = 0.14 * (1.0 - float(k) / 18.0)
		draw_rect(Rect2(gx - gw * 0.5, gy, gw, 3.0), Color(1.0, 0.9, 0.6, ga))


func _draw_title(s: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(s.y * 0.105, 40.0, 74.0))
	var title := "RAFT SURVIVAL"
	var tw: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_title_w = tw
	var cx: float = s.x * 0.5
	var ty: float = s.y * 0.16 + fs
	# wooden plaque behind the title
	var pad: float = fs * 0.8
	var plaque := Rect2(cx - tw * 0.5 - pad, ty - fs * 1.15, tw + pad * 2.0, fs * 1.9)
	_draw_rounded(plaque, 14.0, Color(0.14, 0.09, 0.05, 0.92))
	_draw_rounded(plaque, 14.0, Color(0.38, 0.26, 0.13, 0.9), false, 2.0)
	# wood grain: a few faint darker streaks
	for i in range(6):
		var gy2: float = plaque.position.y + 6.0 + float(i) * (plaque.size.y - 12.0) / 5.0
		draw_line(Vector2(plaque.position.x + 8.0, gy2), Vector2(plaque.end.x - 8.0, gy2 + 1.5),
			Color(0.0, 0.0, 0.0, 0.18), 2.0)
	# rivets at the plaque corners
	var rr2: float = 3.4
	for pt in [plaque.position + Vector2(10, 10), Vector2(plaque.end.x - 10, plaque.position.y + 10),
			Vector2(plaque.position.x + 10, plaque.end.y - 10), Vector2(plaque.end.x - 10, plaque.end.y - 10)]:
		draw_circle(pt, rr2, Color(0.55, 0.5, 0.32, 0.9))
	# title text with a soft shadow
	_draw_text(title, Vector2(cx - tw * 0.5 + 3.0, ty + fs * 0.32 + 3.0), fs, Color(0.0, 0.0, 0.0, 0.55))
	_draw_text(title, Vector2(cx - tw * 0.5, ty + fs * 0.32), fs, Color(1.0, 0.87, 0.58, 1.0))
	# subtitle
	var sub := "OCEAN SURVIVAL"
	var sfs: int = int(fs * 0.32)
	var sw2: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	_draw_text(sub, Vector2(cx - sw2 * 0.5, ty + fs * 1.35), sfs, Color(0.55, 0.88, 0.95, 0.95))


func _draw_buttons(_s: Vector2) -> void:
	for i in range(_btn_rects.size()):
		var r2 := _btn_rects[i] as Rect2
		var b: Dictionary = _buttons[i]
		var label: String = b["label"]
		var sub: String = b["sub"]
		var is_resume: bool = b["id"] != "new"
		var hovered: bool = i == _hover
		var pressed: bool = i == _press
		var off: float = 3.0 if pressed else 0.0
		var rr := Rect2(r2.position.x, r2.position.y + off, r2.size.x, r2.size.y)
		# drop shadow
		_draw_rounded(Rect2(rr.position + Vector2(0, 5), rr.size), rr.size.y * 0.22,
			Color(0.0, 0.0, 0.0, 0.4))
		# plank body + border
		var base := Color(0.24, 0.17, 0.1, 0.97)
		if is_resume:
			base = Color(0.2, 0.23, 0.16, 0.97) if b["id"] == "quick" else base
		if hovered:
			base = base.lightened(0.12)
		if pressed:
			base = base.darkened(0.14)
		_draw_rounded(rr, rr.size.y * 0.2, base)
		var border_c := Color(0.1, 0.06, 0.03, 1.0)
		if hovered:
			border_c = Color(0.95, 0.72, 0.32, 0.95)
		elif is_resume:
			border_c = Color(0.62, 0.5, 0.28, 0.9)
		_draw_rounded(rr, rr.size.y * 0.2, border_c, false, 2.0)
		# top edge catch-light (plank highlight)
		draw_line(Vector2(rr.position.x + 8.0, rr.position.y + 2.0),
			Vector2(rr.end.x - 8.0, rr.position.y + 2.0), Color(1.0, 1.0, 1.0, 0.14), 2.0)
		# side icon
		var icon_c := Vector2(rr.position.x + rr.size.y * 0.5, rr.position.y + rr.size.y * 0.5)
		_draw_button_icon(icon_c, rr.size.y * 0.42, b["id"],
			Color(1.0, 0.9, 0.65, 0.95) if hovered else Color(0.85, 0.72, 0.45, 0.9))
		# label + sub (centered, pushed right of the icon)
		var font := ThemeDB.fallback_font
		var fs: int = int(clampf(rr.size.y * 0.3, 20.0, 30.0))
		var lw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lx: float = rr.position.x + (rr.size.x - lw2) * 0.5 + rr.size.y * 0.2
		var ly: float = rr.position.y + rr.size.y * 0.44
		_draw_text(label, Vector2(lx, ly + fs * 0.3), fs, Color(1.0, 0.98, 0.92, 1.0))
		if sub != "":
			var sfs: int = int(clampf(rr.size.y * 0.2, 13.0, 18.0))
			var sw3: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			_draw_text(sub, Vector2(rr.position.x + (rr.size.x - sw3) * 0.5, ly + fs * 0.55 + sfs * 0.85),
				sfs, Color(0.6, 0.85, 0.95, 0.85))


func _draw_button_icon(c: Vector2, r: float, id: String, col: Color) -> void:
	match id:
		"continue":
			# play triangle
			var tri := PackedVector2Array([
				c + Vector2(-r * 0.42, -r * 0.55), c + Vector2(-r * 0.42, r * 0.55),
				c + Vector2(r * 0.6, 0.0),
			])
			draw_colored_polygon(tri, col)
		"quick":
			# clock: circle + hands
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c, c + Vector2(0.0, -r * 0.4), col, maxf(r * 0.12, 1.5))
			draw_line(c, c + Vector2(r * 0.26, r * 0.2), col, maxf(r * 0.12, 1.5))
		_:
			# plus = new game
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c + Vector2(-r * 0.3, 0.0), c + Vector2(r * 0.3, 0.0), col, maxf(r * 0.14, 2.0))
			draw_line(c + Vector2(0.0, -r * 0.3), c + Vector2(0.0, r * 0.3), col, maxf(r * 0.14, 2.0))


func _draw_footer(s: Vector2) -> void:
	var fs := 14
	var foot := "BUILD. SURVIVE. SAIL ON."
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(foot, Vector2((s.x - tw) * 0.5, s.y - fs * 1.4), fs, Color(1, 1, 1, 0.28))


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_rounded(rect: Rect2, radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	var sbox := StyleBoxFlat.new()
	sbox.set_corner_radius_all(int(radius))
	if filled:
		sbox.bg_color = color
		sbox.set_border_width_all(0)
	else:
		sbox.bg_color = Color(0, 0, 0, 0)
		sbox.set_border_width_all(int(maxf(width, 1.0)))
		sbox.border_color = color
	draw_style_box(sbox, rect)
