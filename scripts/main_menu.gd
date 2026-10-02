extends Control
## ============================================================
## MAIN MENU — survival-styled ocean start screen.
## Fully drawn from primitives (no external art): a dusk sky with a low sun
## over animated waves, a wooden title plaque, and wood-plank action buttons.
##   - No saves            -> NEW GAME only
##   - Autosave present    -> CONTINUE (resumes it)
##   - Quick-save present  -> QUICK SAVE (second resume option)
## Each resume button shows the saved in-game day/time.
##
## MOBILE / TOUCH NOTES (this is the part that used to break on the APK):
##   * Buttons fire on PRESS-DOWN, not on release. A phone sends
##     touch -> drag -> drag -> release and the release position is rarely
##     exactly the press position, so press/release matching silently dropped
##     taps. Press-down activation is also what the in-game HUD uses.
##   * Touch is tracked per finger (`index`) so a second thumb resting on the
##     screen can no longer cancel the first one.
##   * Screen touches arrive in VIEWPORT coordinates while the button rects are
##     in this Control's LOCAL space — positions are converted explicitly, so
##     the menu keeps working if it is ever offset, scaled or resized.
##   * Hit rects are rebuilt on demand (resize / before every hit test) instead
##     of only inside _draw(), so the very first tap can never land on an
##     empty rect list.
##   * `main.tscn` is heavy (multi-megabyte island GLBs + sky shaders). It is
##     pre-loaded on a background thread from _ready(), so the tap swaps scenes
##     instantly instead of freezing the phone for seconds with no feedback.
##     While it loads the tapped button reads "LOADING…" with a progress bar.
##   * If the game scene cannot be opened the menu shows the reason on screen
##     and unlocks again — a dead, silent menu is what made this look broken.
## ============================================================

const GAME_SCENE := "res://scenes/main.tscn"
## Seconds a tap may wait on the background load before we force a normal,
## blocking load instead. Never reached on a healthy build — pure safety net.
const ENTER_TIMEOUT := 20.0

# button ids in display order
var _buttons: Array = []          # of {id, label, sub}
var _btn_rects: Array = []        # parallel Rect2
var _hover := -1
var _press := -1
var _busy := false
var _t := 0.0
var _vp := Vector2.ZERO
var _title_w := 0.0

# --- touch bookkeeping -------------------------------------------------
var _touch_ids: Array = []        # fingers currently on the screen
# --- background load of the game scene ---------------------------------
var _load_requested := false
var _load_progress := 0.0
var _packed_game: PackedScene = null
var _waiting_to_enter := false    # tapped, waiting for the load to finish
var _wait_seconds := 0.0          # how long the current wait has been going
var _pending_idx := -1            # button that is running (draws LOADING)
var _selected_id := ""            # "new" / "continue" / "quick", applied on go
var _error := ""                  # non-empty -> drawn as a red banner

func _ready() -> void:
	if _is_mobile():
		Engine.max_fps = 60
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
	# Build the hit rects right away: the first tap must never arrive before
	# the first _draw() has run.
	_vp = size
	_layout_buttons()
	# Start warming the game scene on a worker thread.
	_request_game_load()
	queue_redraw()


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") \
		or OS.has_feature("ios") or OS.has_feature("web_android")


func _notification(what: int) -> void:
	# Rotation / split-screen / foldables resize the viewport at runtime.
	if what == NOTIFICATION_RESIZED:
		_vp = size
		_layout_buttons()
		queue_redraw()


## Human label for a save slot: "DAY n · hh:mm" from the saved game time.
func _save_sub(slot: String) -> String:
	var info: Dictionary = Inventory.save_info(slot)
	if info.has("game_time"):
		var gt: float = float(info["game_time"])
		var day: int = maxi(1, int(info.get("game_day", 1)))
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
	_poll_game_load()
	# The tap came in before the background load finished -> go now.
	if _waiting_to_enter:
		_wait_seconds += delta
		if _packed_game != null:
			_waiting_to_enter = false
			_swap_scene(_packed_game)
			return
		if _wait_seconds > ENTER_TIMEOUT:
			# Background load is not answering: fall back to a blocking load so
			# the button can never strand the player on the menu.
			_waiting_to_enter = false
			_wait_seconds = 0.0
			_swap_scene(null)
			return
	if not visible:
		return
	_vp = size
	# hover tracking (mouse only — phones have no hover)
	if not _is_mobile():
		_hover = _hit(get_local_mouse_position())
	queue_redraw()  # animated waves need a redraw every frame


# ============================================================
# INPUT — custom buttons (works with mouse and touch)
# ============================================================
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var idx := _hit(mb.position)
	if mb.pressed:
		_press = idx
		# Fire immediately: on a phone the release event can be dropped,
		# reordered or land a few pixels away.
		if idx >= 0:
			_activate(idx)
	else:
		_press = -1
	queue_redraw()
	accept_event()


func _input(event: InputEvent) -> void:
	var handled := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var idx := _hit(_to_local(t.position))
		if t.pressed:
			if not _touch_ids.has(t.index):
				_touch_ids.append(t.index)
			_press = idx
			if idx >= 0:
				_activate(idx)
		else:
			_touch_ids.erase(t.index)
			if _touch_ids.is_empty():
				_press = -1
		handled = true
	elif event is InputEventScreenDrag:
		# Keep the pressed highlight under the finger while it slides.
		var d := event as InputEventScreenDrag
		if _touch_ids.has(d.index):
			_press = _hit(_to_local(d.position))
			handled = true
	elif event is InputEventKey:
		# Keyboard / gamepad / TV-remote fallback: Enter or Space takes the
		# first entry (Continue when a save exists, otherwise New Game).
		var k := event as InputEventKey
		if k.pressed and not k.echo and not _busy and not _buttons.is_empty() \
				and (k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER
					or k.physical_keycode == KEY_SPACE):
			_activate(0)
			handled = true
	if handled:
		queue_redraw()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Screen-space (viewport) position -> this Control's local space, so the hit
## test is correct even if the menu is ever moved, scaled or rotated.
func _to_local(pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * pos


func _hit(pos: Vector2) -> int:
	_ensure_layout()
	for i in range(_btn_rects.size()):
		if (_btn_rects[i] as Rect2).has_point(pos):
			return i
	return -1


## The rects are normally built during _draw(); make sure they exist before
## any hit test so a tap on the very first frame still lands.
func _ensure_layout() -> void:
	if size != _vp or _btn_rects.size() != _buttons.size():
		_vp = size
		_layout_buttons()


# ============================================================
# RUN / RESUME — start the game without ever dead-ending the menu
# ============================================================
func _activate(btn_idx: int) -> void:
	if btn_idx < 0 or btn_idx >= _buttons.size() or _busy:
		return
	_busy = true
	_pending_idx = btn_idx
	_error = ""
	# Remember the choice; the save slot is only touched once we know the game
	# scene can really be opened (never wipe a save for a transition that fails).
	_selected_id = str(_buttons[btn_idx]["id"])
	_enter_game()
	queue_redraw()


func _apply_selection() -> void:
	if _selected_id == "continue":
		Inventory.load_game("main")
	elif _selected_id == "quick":
		Inventory.load_game("quick")
	elif _selected_id == "new":
		Inventory.new_game_reset()
	_selected_id = ""


func _enter_game() -> void:
	if _packed_game != null:
		_swap_scene(_packed_game)
		return
	if _load_requested and _error == "":
		# Warm-up still running: keep the button in its LOADING state and swap
		# from _process() the instant the scene lands in memory.
		_waiting_to_enter = true
		_wait_seconds = 0.0
		queue_redraw()
		return
	# Nothing usable in the background -> fall back to a normal blocking load.
	_swap_scene(null)


func _swap_scene(packed: PackedScene) -> void:
	var can_pack := packed != null and packed.can_instantiate()
	if not can_pack and not ResourceLoader.exists(GAME_SCENE):
		_fail("COULD NOT START GAME  ·  no scene")
		return
	_apply_selection()
	var err: int = get_tree().change_scene_to_packed(packed) if can_pack \
		else get_tree().change_scene_to_file(GAME_SCENE)
	if err != OK:
		_fail("COULD NOT START GAME  ·  err %d" % err)


## Never leave the player with a menu that ignores every tap: say why it
## failed and unlock the buttons so they can try again.
func _fail(msg: String) -> void:
	push_error("[MainMenu] " + msg + " (" + GAME_SCENE + ")")
	_error = msg
	_busy = false
	_waiting_to_enter = false
	_pending_idx = -1
	_selected_id = ""
	# Allow the next tap to start the load over instead of waiting forever on a
	# background request that is never going to answer.
	_load_requested = false
	queue_redraw()


## Kick off a background (threaded) load of main.tscn so the tap is instant.
func _request_game_load() -> void:
	if _load_requested:
		return
	_load_requested = true
	if not ResourceLoader.exists(GAME_SCENE):
		_fail("MISSING  " + GAME_SCENE)
		return
	# Warm the heavy game scene on a worker thread while the player reads the
	# menu, so tapping a button swaps instantly instead of stalling the phone.
	if ResourceLoader.load_threaded_request(GAME_SCENE) != OK:
		_fail("COULD NOT START LOADING  " + GAME_SCENE)


func _poll_game_load() -> void:
	if not _load_requested or _packed_game != null:
		return
	var prog: Array = [0.0]
	var st := ResourceLoader.load_threaded_get_status(GAME_SCENE, prog)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if prog.size() > 0:
			_load_progress = clampf(float(prog[prog.size() - 1]), 0.0, 1.0)
		return
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var res: Resource = ResourceLoader.load_threaded_get(GAME_SCENE)
		if res is PackedScene:
			_packed_game = res
			_load_progress = 1.0
			queue_redraw()
			return
		_fail(GAME_SCENE + "  IS NOT A SCENE")
		return
	_fail("GAME SCENE FAILED TO LOAD  ·  code %d" % int(st))


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
	_draw_error(s)
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
		var show_label := label
		var show_sub := sub
		var running: bool = _busy and i == _pending_idx
		if running:
			# Immediate feedback: the tap registered, the world is loading.
			show_label = "LOADING…"
			show_sub = "%d%%" % int(roundf(_load_progress * 100.0))
		var lw2: float = font.get_string_size(show_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lx: float = rr.position.x + (rr.size.x - lw2) * 0.5 + rr.size.y * 0.2
		var ly: float = rr.position.y + rr.size.y * 0.44
		_draw_text(show_label, Vector2(lx, ly + fs * 0.3), fs, Color(1.0, 0.98, 0.92, 1.0))
		if show_sub != "":
			var sfs: int = int(clampf(rr.size.y * 0.2, 13.0, 18.0))
			var sw3: float = font.get_string_size(show_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			_draw_text(show_sub, Vector2(rr.position.x + (rr.size.x - sw3) * 0.5, ly + fs * 0.55 + sfs * 0.85),
				sfs, Color(0.6, 0.85, 0.95, 0.85))
		if running:
			# thin progress bar along the bottom of the plank
			var bar := Rect2(rr.position.x + 14.0, rr.end.y - 12.0, rr.size.x - 28.0, 5.0)
			_draw_rounded(bar, 2.5, Color(0.0, 0.0, 0.0, 0.45))
			var fill_w: float = bar.size.x * clampf(_load_progress, 0.0, 1.0)
			if fill_w > 2.0:
				_draw_rounded(Rect2(bar.position, Vector2(fill_w, bar.size.y)), 2.5,
					Color(1.0, 0.78, 0.35, 0.95))


## Red banner shown when the game scene could not be opened — a visible reason
## beats a menu that silently ignores every tap.
func _draw_error(s: Vector2) -> void:
	if _error == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 16
	var msg := _error
	var tw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w: float = s.x * 0.9
	if tw > max_w:
		var keep := int(msg.length() * (max_w / tw)) - 1
		msg = msg.substr(0, maxi(keep, 8)) + "…"
		tw = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2((s.x - tw) * 0.5 - 16.0, s.y * 0.86, tw + 32.0, fs * 2.4)
	_draw_rounded(box, 10.0, Color(0.28, 0.06, 0.05, 0.92))
	_draw_rounded(box, 10.0, Color(0.95, 0.4, 0.35, 0.9), false, 2.0)
	_draw_text(msg, Vector2((s.x - tw) * 0.5, box.position.y + fs * 1.6), fs,
		Color(1.0, 0.85, 0.8, 1.0))


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
