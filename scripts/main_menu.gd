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

const GAME_SCENE := "res://scenes/main.tscn"
## Device tiering: phones get longer prewarm/stall windows (statics via
## preload so the menu logic works even before the autoload tree exists).
const MobilePerf := preload("res://scripts/mobile_perf.gd")

# button ids in display order
var _buttons: Array = []          # of {id, label, sub}
var _btn_rects: Array = []        # parallel Rect2
var _hover := -1
var _press := -1
var _busy := false
var _t := 0.0
var _vp := Vector2.ZERO
var _title_w := 0.0

# --- threaded world loading (never blocks the menu) ---
var _loading := false          # loading overlay is up
var _load_prog := 0.0          # smoothed 0..1 for the rope bar
var _load_real := 0.0          # engine-reported progress (or time-fallback)
var _tip := ""
# --- prewarm chain: ONE heavy bake at a time ---
# Requesting the scene AND all 5 big bakes at once made the resource loader
# thrash and stall at ~92% forever (user report 2026-09-15). Sequential
# requests + a watchdog keep it always moving.
# Mobile builds prewarm the LIGHT apple bake (plant_instance._mobile_bake
# resolves the same way) so the desktop tree never touches phone RAM;
# desktop prewarms only the full bake. _request_next_prewarm skips paths
# that don't exist in the export (the Android preset excludes the desktop
# apple tree).
static func _prewarm_paths() -> Array:
	if OS.has_feature("mobile"):
		return [
			"res://grass/baked/apple_tree_mobile.res",
			"res://grass/baked/palm_island.res",
			"res://grass/baked/coconut_mature.res",
			"res://grass/baked/coconut_young.res",
			"res://grass/baked/coconut_sprout.res",
		]
	return [
		"res://grass/baked/apple_tree.res",
		"res://grass/baked/palm_island.res",
		"res://grass/baked/coconut_mature.res",
		"res://grass/baked/coconut_young.res",
		"res://grass/baked/coconut_sprout.res",
	]
var _prewarm_idx := 0
var _prewarm_path := ""        # the bake currently loading ("" = none)
var _prewarm_wait := 0.0       # seconds waited with the scene already ready
var _stall_t := 0.0            # seconds without any real progress
var _last_prog := 0.0
const LOADING_TIPS := [
	"Hold E to chop trees for wood",
	"Seeds grow in pots on your raft",
	"The beacon light marks the island",
	"Ripe fruit twinkles — pick it with E",
	"Swim close to the raft and press E to climb",
	"Build walls before the storm hits",
]

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
	if _loading:
		_poll_load(delta)
	# hover tracking (mouse)
	if not OS.has_feature("mobile") and not OS.has_feature("android") \
			and not OS.has_feature("ios") and get_viewport() != null:
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
	_start_threaded_load()


# ============================================================
# THREADED WORLD LOADING — the menu stays alive and animates while the
# island builds. The old code changed scene synchronously: on phones the
# 1–2 s island generation froze everything with no feedback, which felt
# like the game had hung when tapping Continue.
# ============================================================
func _start_threaded_load() -> void:
	_loading = true
	_load_prog = 0.0
	_load_real = 0.0
	_prewarm_idx = 0
	_prewarm_path = ""
	_prewarm_wait = 0.0
	_stall_t = 0.0
	_last_prog = 0.0
	_tip = LOADING_TIPS[randi() % LOADING_TIPS.size()]
	ResourceLoader.load_threaded_request(GAME_SCENE, "", true)
	_request_next_prewarm()


## Start the NEXT prewarm request only when the previous one finished.
func _request_next_prewarm() -> void:
	_prewarm_path = ""
	var paths := _prewarm_paths()
	while _prewarm_idx < paths.size():
		var p: String = paths[_prewarm_idx]
		_prewarm_idx += 1
		if ResourceLoader.exists(p):
			_prewarm_path = p
			ResourceLoader.load_threaded_request(p, "", true)
			return


func _poll_load(delta: float) -> void:
	# Advance the one-at-a-time prewarm chain.
	if _prewarm_path != "":
		var pst := ResourceLoader.load_threaded_get_status(_prewarm_path)
		if pst != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_prewarm_path = ""
			_request_next_prewarm()
	# Progress is filled into the array passed to the status call (Godot 4 API).
	var prog_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, prog_arr)
	# Engine progress (0..1 array) when it reports; else creep with time so
	# the bar never sits at zero on fast compiles.
	if prog_arr.size() > 0:
		_load_real = maxf(_load_real, float(prog_arr[0]))
	else:
		_load_real = minf(_load_real + delta * 0.25, 0.9)
	# Smooth toward the real progress; snap when done.
	var target := maxf(_load_real, 0.08)
	_load_prog = lerpf(_load_prog, target, minf(delta * 6.0, 1.0))
	# --- STALL WATCHDOG: never let the bar freeze at ~92% again ---
	# If the engine reports no new progress for 15 s (a wedged loader thread,
	# a blocked import, anything), fall back to the synchronous scene load so
	# the game ALWAYS gets through.
	if _load_real > _last_prog + 0.005:
		_last_prog = _load_real
		_stall_t = 0.0
	else:
		_stall_t += delta
	var scene_ready := status == ResourceLoader.THREAD_LOAD_LOADED
	if scene_ready and _prewarm_path != "":
		# Scene is parsed; give the prewarm chain a tier-based window (mobile
		# parses the 16 MB apple bake — fixed 8 s kept cutting it off and
		# paying the parse cost again during gameplay), then enter the game.
		_prewarm_wait += delta
		if _prewarm_wait > MobilePerf.prewarm_window():
			_prewarm_path = ""
	if (scene_ready and _prewarm_path == "") or _stall_t > MobilePerf.stall_window():
		_load_prog = 1.0
		var scene: PackedScene = null
		if scene_ready:
			scene = ResourceLoader.load_threaded_get(GAME_SCENE)
		if scene != null:
			get_tree().change_scene_to_packed(scene)
		else:
			get_tree().change_scene_to_file(GAME_SCENE)
		_loading = false
	elif status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		# Never trap the player on a broken save/load: fall back to the
		# synchronous path (worst case it freezes for a second like before).
		_loading = false
		get_tree().change_scene_to_file(GAME_SCENE)
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
	if _loading:
		_draw_loading(s)
		return
	_draw_title(s)
	_draw_buttons(s)
	_draw_footer(s)


## Game-styled loading overlay: the same ocean now carries a bobbing raft,
## a rope progress bar on a wooden plaque, a survival tip, and the day
## counter ticks as the island builds. Player sees motion, not a freeze.
func _draw_loading(s: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	var cy: float = s.y * 0.42
	# --- bobbing raft on the existing waves ---
	var bob := sin(_t * 2.2) * 5.0
	var tilt := sin(_t * 1.7) * 0.05
	var rw: float = minf(s.x * 0.34, 260.0)
	var rh: float = rw * 0.22
	var rc := Vector2(cx, cy + bob)
	draw_set_transform(rc, tilt, Vector2.ONE)
	# hull planks
	var hull := Rect2(-rw * 0.5, -rh * 0.5, rw, rh)
	_draw_rounded(hull, 8.0, Color(0.32, 0.22, 0.12, 0.98))
	_draw_rounded(hull, 8.0, Color(0.5, 0.36, 0.2, 0.9), false, 2.0)
	for i in range(3):
		var py: float = hull.position.y + rh * (0.25 + 0.25 * float(i))
		draw_line(Vector2(hull.position.x + 6, py), Vector2(hull.end.x - 6, py), Color(0, 0, 0, 0.2), 2.0)
	# mast + sail
	draw_line(Vector2(0, -rh * 0.5), Vector2(0, -rh * 2.1), Color(0.25, 0.17, 0.1), 4.0)
	var sway := sin(_t * 2.6) * 4.0
	var sail := PackedVector2Array([
		Vector2(2, -rh * 2.0), Vector2(rw * 0.34 + sway, -rh * 1.2), Vector2(2, -rh * 0.55),
	])
	draw_colored_polygon(sail, Color(0.88, 0.84, 0.74, 0.96))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# wake lines under the raft
	draw_line(Vector2(rc.x - rw * 0.62, rc.y + rh * 0.5), Vector2(rc.x - rw * 0.3, rc.y + rh * 0.55), Color(0.8, 0.95, 1.0, 0.30), 2.0)
	draw_line(Vector2(rc.x + rw * 0.3, rc.y + rh * 0.55), Vector2(rc.x + rw * 0.62, rc.y + rh * 0.5), Color(0.8, 0.95, 1.0, 0.30), 2.0)
	# --- "LOADING THE ISLAND" text ---
	var fs: int = int(clampf(s.y * 0.032, 16.0, 26.0))
	var msg := "LOADING THE ISLAND…"
	var tw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(msg, Vector2(cx - tw * 0.5, cy + rh * 2.2), fs, Color(1.0, 0.9, 0.66, 0.98))
	# --- rope progress bar on a small wooden plaque ---
	var bw: float = minf(s.x * 0.6, 380.0)
	var bh: float = 14.0
	var bp := Vector2(cx - bw * 0.5, cy + rh * 2.2 + fs * 1.6)
	var plaque := Rect2(bp.x - 12, bp.y - 12, bw + 24, bh + 24)
	_draw_rounded(plaque, 10.0, Color(0.14, 0.09, 0.05, 0.92))
	_draw_rounded(plaque, 10.0, Color(0.38, 0.26, 0.13, 0.9), false, 2.0)
	draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.05, 0.04, 0.03, 0.9))
	var fill_w: float = bw * clampf(_load_prog, 0.0, 1.0)
	if fill_w > 2.0:
		draw_rect(Rect2(bp, Vector2(fill_w, bh)), Color(0.72, 0.52, 0.26, 1.0))
		# rope-twist texture: light dashes along the fill
		var dash_x := bp.x
		while dash_x < bp.x + fill_w - 4.0:
			draw_rect(Rect2(dash_x, bp.y + 2, 3.0, bh - 4.0), Color(0.85, 0.66, 0.38, 0.5))
			dash_x += 9.0
	# percent text
	var pct := "%d%%" % int(roundf(_load_prog * 100.0))
	var pfs: int = int(fs * 0.8)
	_draw_text(pct, Vector2(cx - font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x * 0.5, bp.y + bh + pfs * 1.3), pfs, Color(1, 1, 1, 0.75))
	# --- rotating survival tip ---
	if _tip != "":
		var tfs: int = int(clampf(s.y * 0.024, 13.0, 18.0))
		var ttw: float = font.get_string_size(_tip, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		_draw_text(_tip, Vector2(cx - ttw * 0.5, bp.y + bh + pfs * 3.1), tfs, Color(0.6, 0.85, 0.95, 0.9))


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
