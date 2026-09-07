extends Control
class_name SurvivalHUD

const Icons := preload("res://scripts/ui_icons.gd")

## ============================================================
## MOBILE SURVIVAL HUD — graphical overlay shown on touch devices (and the
## desktop F10 preview). All art is drawn from primitives (no external icons).
##
## NORMAL MODE (Build Mode OFF):
##   - bottom-center: HOTBAR of inventory slots 0..5 (items the player owns)
##     + a BAG button at its right end. Tap a slot to make that item the
##     active one (highlighted). Tapping the BAG opens the 30-slot panel.
##   - bag panel: 30 slots (5 x 6). Rows 0-4 = bag-only slots 6..29, the
##     bottom row = the hotbar (slots 0..5, one authoritative array). Items
##     can be dragged between ANY two slots: move / merge / swap, and a drag
##     ghost follows the finger. Item pickups stack and overflow reports
##     "BAG FULL" instead of silently deleting anything.
## BUILD MODE (ON):
##   - the bottom hotbar temporarily becomes the BUILD-PIECE row (Foundation,
##     Wall, Roof, Stairs, Door, Window). Tapping a piece selects it for the
##     existing preview/placement system. Exiting Build Mode restores the
##     inventory hotbar exactly as it was (nothing is moved or changed).
##
## The HUD never swallows the mouse (desktop), only claims touches on its own
## controls; it coordinates with MobileControls via claims_touch()/is_blocking().
## ============================================================

const PIECE_ORDER := ["Foundation", "Wall", "Roof", "Stairs", "Door", "Window"]
const RESOURCE_PILL_ITEMS := ["Wood", "Rope", "Plastic", "Metal"]
const STATS := [["health", "Health"], ["hunger", "Hunger"], ["thirst", "Thirst"]]

const HOTBAR_COUNT := 6
const BAG_COLS := 5
const BAG_ROWS := 6   # 5x5 bag + 1 hotbar row = 30

var _bag_open := false

# --- geometry (recomputed every frame while visible) ---
var _vp := Vector2.ZERO
var _hotbar_rects: Array = []      # bottom bar (normal-mode items or build pieces)
var _bag_rect := Rect2()           # the BAG button (normal mode)
var _slot := 0.0                   # current slot size
var _panel_rect := Rect2()
var _close_rect := Rect2()
var _save_rect := Rect2()          # SAVE chip in the bag panel header
var _save_flash_until := 0.0       # brief "SAVED ✓" state after a quick-save
var _bag_slot_rects: Array = []    # 30 rects, index = inventory slot index
var _status_centers: Array = []
var _clock_center := Vector2.ZERO   # day/night clock at the far top-right
var _clock_r := 0.0
var _sky: Node = null
var _pill_rects: Array = []
var _chip_rect := Rect2()
var _chip_text := ""
var _toast := ""
var _toast_until := 0.0
var _toast_rect := Rect2()

# --- drag & touch ---
var _press_slot := -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _drag_from := -1
var _drag_pos := Vector2.ZERO
var _press_bag := false
var _pressed_visual := -1

var _stats_node: Node = null
var _last_key := ""

# --- pause (button under the day/night clock) ---
var _pause_center := Vector2.ZERO
var _pause_btn_rect := Rect2()
var _paused := false
var _pause_panel_rect := Rect2()
var _pause_resume_rect := Rect2()
var _pause_quit_rect := Rect2()


func _ready() -> void:
	add_to_group("survival_hud")
	_stats_node = get_tree().root.get_node_or_null("/root/Stats")
	# Keep this HUD ticking (pause overlay, clock) while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	Inventory.changed.connect(_inventory_changed)
	Inventory.bag_full.connect(_on_bag_full)
	var vp := get_viewport()
	vp.size_changed.connect(_on_size_changed)
	visible = _should_show()
	_on_size_changed()


func _inventory_changed() -> void:
	_last_key = ""
	if visible:
		queue_redraw()


func _on_bag_full(amount: int) -> void:
	_show_toast("BAG FULL" if amount >= 1 else "")


func _show_toast(text: String) -> void:
	_toast = text
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.2
	queue_redraw()


## Public toast (used by the player for quick-save feedback etc.).
func show_toast(text: String) -> void:
	_show_toast(text)


func _should_show() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	var mc: Node = get_parent().get_node_or_null("MobileControls")
	return mc != null and bool(mc.get("force_show")) == true


func _on_size_changed() -> void:
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	queue_redraw()


func _process(_delta: float) -> void:
	var want := _should_show()
	if visible != want:
		visible = want
		if not want:
			_bag_open = false
			_cancel_drag()
		queue_redraw()
	if not visible:
		return
	_compute_layout()
	if _flash_active():
		queue_redraw()  # re-draw the "SAVED ✓" chip while it is lit
	var key := _build_cache_key()
	if key != _last_key:
		_last_key = key
		queue_redraw()


# ============================================================
# PUBLIC — coordination with MobileControls
# ============================================================
func is_blocking() -> bool:
	return visible and _bag_open


## Should MobileControls treat this screen point as HUD territory (never
## start camera look from it)?
func claims_touch(pos: Vector2) -> bool:
	if not visible:
		return false
	if _bag_open:
		return true
	if _bag_rect.has_point(pos):
		return true
	for r in _hotbar_rects:
		if r.has_point(pos):
			return true
	return false


func _in_build_mode() -> bool:
	var p := _get_player()
	return p != null and p.get("build_mode") == true


func _editing() -> bool:
	var p := _get_player()
	return p != null and p.get("_editing") != null


# ============================================================
# LAYOUT / GEOMETRY
# ============================================================
func _compute_layout() -> void:
	_vp = size
	if _vp.x <= 0.0 or _vp.y <= 0.0:
		return
	var m: float = maxf(12.0, _vp.y * 0.022)
	var top_safe: float = maxf(m, _vp.y * 0.035)
	var font := ThemeDB.fallback_font
	var cr: float = clampf(_vp.y * 0.05, 23.0, 34.0)
	var gap: float = cr * 0.16

	# top-right corner: day/night CLOCK occupies the far corner column; the
	# status circles sit to its LEFT so the clock's caption never overlaps them.
	_clock_center = Vector2(_vp.x - m - cr, top_safe + cr)
	_clock_r = cr
	var cap_fs: int = int(clampf(cr * 0.58, 14.0, 20.0))
	var cap_w: float = font.get_string_size("DAY 99", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var cap_w2: float = font.get_string_size("88:88", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var clock_left: float = _clock_center.x - maxf(cap_w, cap_w2) * 0.5 - gap * 0.5
	_status_centers.clear()
	var sx := clock_left - cr
	for i in range(STATS.size()):
		_status_centers.append(Vector2(sx, top_safe + cr))
		sx -= cr * 2.0 + gap

	# pause button centered under the clock caption (same far-right column)
	_pause_btn_rect = Rect2()
	if _clock_r > 0.0:
		var pb_r: float = _clock_r * 0.66
		var pb_y: float = _clock_center.y + _clock_r + cap_fs * 1.75 + pb_r
		_pause_center = Vector2(_clock_center.x, pb_y)
		_pause_btn_rect = Rect2(_pause_center.x - pb_r, _pause_center.y - pb_r, pb_r * 2.0, pb_r * 2.0)

	# resource pills top-left
	_pill_rects.clear()
	var px := m
	var py := top_safe
	var ph: float = clampf(cr * 0.92, 22.0, 32.0)
	for item in RESOURCE_PILL_ITEMS:
		var count: int = int(Inventory.total(item))
		if count <= 0:
			continue
		var label := str(count)
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ph * 0.56)).x
		var w: float = ph + tw + ph * 0.7
		_pill_rects.append(Rect2(px, py, w, ph))
		px += w + gap

	# bottom bar: normal = inventory slots + bag button; build = piece slots
	_slot = clampf(_vp.y * 0.105, 54.0, 86.0)
	var sg: float = _slot * 0.14
	var building: bool = _in_build_mode()
	var n: int = HOTBAR_COUNT
	var extra: int = 0 if building else 1  # bag button after the slots
	var total: float = float(n + extra) * _slot + float(n - 1 + extra) * sg
	var x0: float = (_vp.x - total) * 0.5
	var y0: float = _vp.y - m - _slot
	_hotbar_rects.clear()
	for i in range(n):
		_hotbar_rects.append(Rect2(x0 + float(i) * (_slot + sg), y0, _slot, _slot))
	_bag_rect = Rect2(x0 + float(n) * (_slot + sg), y0, _slot, _slot)

	# build/edit chip top-center
	_chip_text = _build_chip_text()
	if _chip_text != "":
		var fs: int = int(clampf(cr * 0.62, 14.0, 20.0))
		var cw: float = font.get_string_size(_chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + cr * 1.4
		var ch: float = cr * 1.15
		_chip_rect = Rect2((_vp.x - cw) * 0.5, top_safe, cw, ch)
	else:
		_chip_rect = Rect2()

	# bag panel grid (5 cols x 5 bag rows + 1 hotbar row = 30 slots)
	_bag_slot_rects.clear()
	if _bag_open:
		var cell: float = clampf(minf(_vp.x * 0.082, _vp.y * 0.072), 44.0, 78.0)
		var cg: float = cell * 0.16
		var pad: float = cell * 0.5
		var head_h: float = cell * 0.78
		var pw: float = float(BAG_COLS) * cell + float(BAG_COLS - 1) * cg + pad * 2.0
		var phh: float = float(BAG_ROWS) * cell + float(BAG_ROWS - 1) * cg + pad * 2.0 + head_h
		_panel_rect = Rect2((_vp.x - pw) * 0.5, (_vp.y - phh) * 0.5, pw, phh)
		var ccr: float = cell * 0.4
		_close_rect = Rect2(_panel_rect.end.x - ccr - pad * 0.6, _panel_rect.position.y + pad * 0.35, ccr, ccr)
		# SAVE chip in the header, left of the close button
		var sfs: int = int(clampf(cell * 0.3, 12.0, 18.0))
		var stxt: String = "SAVED ✓" if _flash_active() else "QUICK SAVE"
		var sw: float = font.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		var scw: float = sw + cell * 0.5
		_save_rect = Rect2(_close_rect.position.x - scw - pad * 0.6, _panel_rect.position.y + pad * 0.35, scw, ccr)
		var grid_origin := Vector2(_panel_rect.position.x + pad, _panel_rect.position.y + pad + head_h)
		for idx in range(Inventory.SLOT_COUNT):
			var r := _row_of(idx)
			var c := _col_of(idx)
			var rr := Rect2(grid_origin.x + float(c) * (cell + cg),
				grid_origin.y + float(r) * (cell + cg), cell, cell)
			_bag_slot_rects.append(rr)
	else:
		_save_rect = Rect2()

	# toast pill (above the bottom bar)
	_toast_rect = Rect2()
	var now := Time.get_ticks_msec() / 1000.0
	if _toast != "" and now < _toast_until:
		var tfs: int = int(clampf(_slot * 0.3, 15.0, 24.0))
		var tw2: float = font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var tw_: float = tw2 + _slot * 0.7
		var th: float = _slot * 0.5
		_toast_rect = Rect2((_vp.x - tw_) * 0.5, y0 - th - m, tw_, th)
	else:
		_toast = ""

	# pause overlay (drawn above everything while paused)
	if _paused:
		var ppad: float = clampf(_vp.y * 0.035, 16.0, 26.0)
		var ppw: float = minf(_vp.x * 0.72, 430.0)
		var ptrow: float = clampf(_vp.y * 0.055, 30.0, 46.0)
		var pbh2: float = clampf(_vp.y * 0.078, 46.0, 68.0)
		var psep2: float = clampf(_vp.y * 0.02, 10.0, 16.0)
		var pph2: float = ppad * 2.0 + ptrow + psep2 + pbh2 * 2.0 + psep2
		_pause_panel_rect = Rect2((_vp.x - ppw) * 0.5, (_vp.y - pph2) * 0.5, ppw, pph2)
		var pqx: float = _pause_panel_rect.position.x + ppad
		var pqw: float = ppw - ppad * 2.0
		_pause_resume_rect = Rect2(pqx, _pause_panel_rect.position.y + ppad + ptrow + psep2, pqw, pbh2)
		_pause_quit_rect = Rect2(pqx, _pause_resume_rect.end.y + psep2, pqw, pbh2)
	else:
		_pause_panel_rect = Rect2()
		_pause_resume_rect = Rect2()
		_pause_quit_rect = Rect2()


func _row_of(idx: int) -> int:
	if idx < HOTBAR_COUNT:
		return BAG_ROWS - 1
	return int(float(idx - HOTBAR_COUNT) / float(BAG_COLS))


func _col_of(idx: int) -> int:
	if idx < HOTBAR_COUNT:
		return idx
	return (idx - HOTBAR_COUNT) % BAG_COLS


func _idx_at(pos: Vector2) -> int:
	for i in range(_bag_slot_rects.size()):
		if (_bag_slot_rects[i] as Rect2).has_point(pos):
			return i
	return -1


func _build_cache_key() -> String:
	var p := _get_player()
	var key := str(_vp)
	key += "|bag" + str(_bag_open)
	if p == null:
		return key
	key += "|bm" + str(p.get("build_mode") == true)
	key += "|ed" + str(_editing())
	key += "|sel" + str(int(p.get("selected_piece_index")))
	key += "|act" + str(int(p.get("active_slot_index")))
	key += "|av" + str(p.get("active_item"))
	key += "|valid" + str(p.get("build_valid") == true)
	# inventory digest (totals are cheap; pickups/removals change them)
	for item in Inventory.items:
		key += "|" + item + str(int(Inventory.items.get(item, 0)))
	for s in STATS:
		key += "|" + s[0] + str(int(roundf(float(_get_stat(s[0])))))
	key += "|clk" + str(int(floorf(_time_now() * 60.0)))
	key += "|drag" + str(_dragging) + str(_drag_from) + str(_pressed_visual)
	key += "|toast" + _toast + str(Time.get_ticks_msec() / 1000.0 < _toast_until)
	key += "|save" + str(_flash_active())
	key += "|p" + str(_paused)
	return key


func _build_chip_text() -> String:
	var p := _get_player()
	if p == null:
		return ""
	if p.get("_editing") != null:
		return "EDITING  " + str(p.get("_editing").name).to_upper()
	if p.get("build_mode") != true:
		return ""
	var idx: int = clampi(int(p.get("selected_piece_index")), 0, PIECE_ORDER.size() - 1)
	var piece_name2: String = PIECE_ORDER[idx]
	var ok: bool = p.get("build_valid") == true
	var state := "READY" if ok else "NO SPOT"
	var cost := ""
	if Inventory.RECIPES.has(piece_name2):
		var parts: Array = []
		var recipe: Dictionary = Inventory.RECIPES[piece_name2]
		for item in recipe:
			parts.append("%s %d" % [str(item).substr(0, 3).to_upper(), int(recipe[item])])
		cost = "   " + "  ".join(parts)
	var afford := "OK" if Inventory.can_afford(piece_name2) else "NEED MORE"
	return "%s  %s%s   [%s]" % [piece_name2.to_upper(), state, cost, afford]


func _get_stat(which: String) -> float:
	if _stats_node == null or not is_instance_valid(_stats_node):
		return 100.0
	return float(_stats_node.get(which))


func _flash_active() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _save_flash_until


func _do_quick_save() -> void:
	var p := _get_player()
	if p == null or not p.has_method("quick_save"):
		return
	p.call("quick_save")
	_save_flash_until = Time.get_ticks_msec() / 1000.0 + 1.6
	queue_redraw()


func _cancel_drag() -> void:
	_press_slot = -1
	_dragging = false
	_drag_from = -1
	_pressed_visual = -1
	_press_bag = false


# ============================================================
# INPUT — touches on hotbar / bag / panel
# ============================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _paused:
		# While paused only the overlay buttons react; nothing else moves.
		if event is InputEventScreenTouch:
			_handle_pause_input(event as InputEventScreenTouch)
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pause_btn_rect.size.x > 0.0 and _pause_btn_rect.has_point(touch.position):
			_set_paused(true)
			get_viewport().set_input_as_handled()
			return
	if _bag_open:
		_handle_bag_input(event)
	else:
		_handle_bar_input(event)


func _handle_bar_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _bag_rect.has_point(touch.position) and not _in_build_mode():
				_press_bag = true
				_bag_open = true
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			for i in range(_hotbar_rects.size()):
				if (_hotbar_rects[i] as Rect2).has_point(touch.position):
					_pressed_visual = i
					_tap_bar_slot(i)
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
		else:
			_pressed_visual = -1
			queue_redraw()


## Normal mode: hotbar slot = inventory selection. Build mode: piece select.
func _tap_bar_slot(i: int) -> void:
	var p := _get_player()
	if p == null:
		return
	if _in_build_mode():
		if p.has_method("select_piece_for_build"):
			p.call("select_piece_for_build", i)
	elif p.has_method("select_hotbar_slot"):
		p.call("select_hotbar_slot", i)


func _handle_bag_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _save_rect.has_point(touch.position):
				_do_quick_save()
				get_viewport().set_input_as_handled()
				return
			_press_pos = touch.position
			var idx := _idx_at(touch.position)
			if idx >= 0 and not Inventory.slot_empty(idx):
				_press_slot = idx
				_pressed_visual = idx
			else:
				_press_slot = -1
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# released
		var release_pos := touch.position
		if _press_slot >= 0:
			if _dragging:
				var dest := _idx_at(release_pos)
				if dest >= 0 and dest != _drag_from:
					Inventory.drop_into(_drag_from, dest)
					# selection lives on the hotbar row: keep it coherent
					_refresh_selection_after_move()
				_cancel_drag()
			else:
				# plain tap (no drag): hotbar-row tap selects the item
				if _press_slot < HOTBAR_COUNT:
					var p := _get_player()
					if p != null and p.has_method("select_hotbar_slot"):
						p.call("select_hotbar_slot", _press_slot)
				_cancel_drag()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# tap on background: close unless it started on the panel chrome
		if _close_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		elif not _panel_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _press_slot >= 0:
			if not _dragging and _press_pos.distance_to(drag.position) > 14.0:
				_dragging = true
				_drag_from = _press_slot
			if _dragging:
				_drag_pos = drag.position
			queue_redraw()
			get_viewport().set_input_as_handled()


func _handle_pause_input(t: InputEventScreenTouch) -> void:
	if t.pressed:
		if _pause_resume_rect.has_point(t.position):
			_set_paused(false)
		elif _pause_quit_rect.has_point(t.position):
			_quit_to_menu()
		get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	if _paused == p:
		return
	_paused = p
	if p:
		_cancel_drag()
		_bag_open = false
	get_tree().paused = p
	queue_redraw()


func _quit_to_menu() -> void:
	var p := _get_player()
	if p != null and p.has_method("_flush_save"):
		p.call("_flush_save")
	_set_paused(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh_selection_after_move() -> void:
	var p := _get_player()
	if p != null and p.has_method("_refresh_active_item"):
		p.call("_refresh_active_item")


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


# ============================================================
# DRAW
# ============================================================
func _draw() -> void:
	if not visible or _vp.x <= 0.0:
		return
	_draw_status()
	_draw_clock()
	_draw_pause_btn()
	_draw_pills()
	_draw_chip()
	if _bag_open:
		_draw_bag_panel()
	else:
		_draw_bottom_bar()
	if _toast != "" and _toast_rect.size.x > 0.0:
		_draw_toast()
	# drag ghost rides above everything
	if _dragging and _drag_from >= 0:
		_draw_drag_ghost()
	# pause overlay is the top-most layer
	if _paused:
		_draw_pause_overlay()


func _draw_pause_btn() -> void:
	if _pause_btn_rect.size.x <= 0.0:
		return
	var c := _pause_center
	var r: float = _pause_btn_rect.size.x * 0.5
	draw_circle(c, r, Color(0.05, 0.07, 0.1, 0.9))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.32), maxf(r * 0.06, 1.0), true)
	var bw: float = maxf(r * 0.16, 1.6)
	var bh: float = r * 0.72
	draw_rect(Rect2(c.x - r * 0.3, c.y - bh * 0.5, bw, bh), Color(1, 1, 1, 0.95))
	draw_rect(Rect2(c.x + r * 0.3 - bw, c.y - bh * 0.5, bw, bh), Color(1, 1, 1, 0.95))


func _draw_pause_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.0, 0.0, 0.0, 0.55))
	var rect := _pause_panel_rect
	if rect.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	_draw_rounded(rect, 24.0, Color(0.055, 0.075, 0.1, 0.98))
	_draw_rounded(rect, 24.0, Color(1, 1, 1, 0.25), false, 2.0)
	var tfs: int = int(clampf(rect.size.y * 0.08, 22.0, 36.0))
	var ttext := "PAUSED"
	var tw: float = font.get_string_size(ttext, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	_draw_text(ttext, Vector2(rect.position.x + (rect.size.x - tw) * 0.5,
			rect.position.y + rect.size.y * 0.1 + tfs * 0.36), tfs, Color(1, 1, 1, 0.97))
	_draw_pause_button(_pause_resume_rect, "RESUME", true)
	_draw_pause_button(_pause_quit_rect, "QUIT TO MENU", false)


func _draw_pause_button(btn: Rect2, label: String, primary: bool) -> void:
	if btn.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var bg: Color = Color(0.13, 0.26, 0.3, 0.98) if primary else Color(0.28, 0.16, 0.13, 0.98)
	var border: Color = Color(0.5, 0.95, 1.0, 0.75) if primary else Color(1.0, 0.72, 0.66, 0.6)
	_draw_rounded(btn, btn.size.y * 0.5, bg)
	_draw_rounded(btn, btn.size.y * 0.5, border, false, 2.0)
	var fs: int = int(clampf(btn.size.y * 0.42, 18.0, 28.0))
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(label, Vector2(btn.position.x + (btn.size.x - tw) * 0.5,
			btn.position.y + btn.size.y * 0.5 + fs * 0.36), fs, Color(1, 1, 1, 0.97))


func _draw_toast() -> void:
	_draw_rounded(_toast_rect, _toast_rect.size.y * 0.5, Color(0.55, 0.12, 0.1, 0.88))
	_draw_rounded(_toast_rect, _toast_rect.size.y * 0.5, Color(1, 1, 1, 0.35), false, 1.5)
	var fs: int = int(clampf(_toast_rect.size.y * 0.55, 15.0, 24.0))
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(_toast, Vector2(_toast_rect.position.x + (_toast_rect.size.x - tw) * 0.5,
			_toast_rect.position.y + _toast_rect.size.y * 0.52 + fs * 0.34), fs, Color(1, 1, 1, 0.98))


## Bottom bar: NORMAL = inventory slots 0..5 + bag; BUILD = piece slots.
func _draw_bottom_bar() -> void:
	var building: bool = _in_build_mode()
	var p := _get_player()
	var sel_piece: int = int(p.get("selected_piece_index")) if p != null else -1
	var act_slot: int = int(p.get("active_slot_index")) if p != null else 0
	for i in range(_hotbar_rects.size()):
		var rect: Rect2 = _hotbar_rects[i]
		if building:
			var piece_sel: bool = i == sel_piece
			_draw_slot(rect, _pressed_visual == i, piece_sel)
			Icons.piece(self, PIECE_ORDER[i], rect.get_center(), _slot * 0.3,
				Color(0.88, 0.72, 0.42, 0.95) if piece_sel else Color(0.75, 0.6, 0.34, 0.85))
		else:
			var item_sel: bool = i == act_slot and not Inventory.slot_empty(i)
			_draw_slot(rect, _pressed_visual == i, item_sel)
			_draw_item_slot(rect, i, item_sel)
	if not building and _bag_rect.size.x > 0.0:
		_draw_slot(_bag_rect, _press_bag, false)
		Icons.backpack(self, _bag_rect.get_center(), _slot * 0.3, Color(0.9, 0.75, 0.45, 0.95))


func _draw_item_slot(rect: Rect2, idx: int, selected: bool) -> void:
	if Inventory.slot_empty(idx):
		return
	var item: String = Inventory.slot_item(idx)
	var count: int = Inventory.slot_count(idx)
	var glyph: Color = Color(1, 1, 1, 0.98) if selected else Color(0.95, 0.95, 0.95, 0.9)
	Icons.item_icon(self, item, rect.get_center(), _slot * 0.26)
	if count > 1:
		var fs: int = int(clampf(_slot * 0.28, 13.0, 22.0))
		var label := str(count)
		var font := ThemeDB.fallback_font
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(rect.end.x - tw - rect.size.x * 0.06,
				rect.position.y + rect.size.y * 0.8 + fs * 0.26), fs, glyph)
	else:
		# even count "1" is shown small, like the reference slot numbers
		var fs: int = int(clampf(_slot * 0.2, 10.0, 16.0))
		var label := str(count)
		var font := ThemeDB.fallback_font
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(rect.end.x - tw - rect.size.x * 0.06,
				rect.position.y + rect.size.y * 0.78 + fs * 0.24), fs, Color(1, 1, 1, 0.6))


func _draw_status() -> void:
	var cr: float = clampf(_vp.y * 0.05, 23.0, 34.0)
	var col: Color = Color(1, 1, 1, 0.9)
	var font := ThemeDB.fallback_font
	for i in range(STATS.size()):
		if i >= _status_centers.size():
			break
		var center: Vector2 = _status_centers[i]
		var c: Color = _status_bg(STATS[i][0])
		draw_circle(center, cr, c)
		draw_arc(center, cr, 0.0, TAU, 40, Color(1, 1, 1, 0.28), clampf(cr * 0.05, 1.5, 2.5), true)
		var glyph_r: float = cr * 0.52
		Icons.status_icon(self, STATS[i][0], center, glyph_r, Color(1, 1, 1, 0.95))
		var val: int = int(roundf(_get_stat(STATS[i][0])))
		var label := str(val)
		var fs: int = int(clampf(cr * 0.62, 13.0, 19.0))
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(center.x - tw * 0.5, center.y + cr + fs * 0.15), fs, col)


## Current in-game hour (float, Sky3D.current_time). Day number + hh:mm derive
## from it; falls back to 12.0 (noon) while the sky node is unavailable.
func _time_now() -> float:
	if _sky == null or not is_instance_valid(_sky):
		var sc: Node = get_tree().current_scene
		if sc != null:
			_sky = sc.get_node_or_null("Sky3D")
	if _sky != null and is_instance_valid(_sky) and _sky.get("current_time") != null:
		return float(_sky.get("current_time"))
	return 12.0


## Day/night clock: split circle (sun above / moon + stars below) with the
## saved day and clock time printed underneath, at the far top-right corner.
func _draw_clock() -> void:
	var c: Vector2 = _clock_center
	var r: float = _clock_r
	if r <= 4.0 or _clock_center == Vector2.ZERO:
		return
	var t := _time_now()
	var day: int = int(floorf(t / 24.0)) + 1
	var hh: int = int(t) % 24
	var mm: int = int((t - floorf(t)) * 60.0) % 60
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(r * 0.58, 14.0, 20.0))
	var lw: float = maxf(font.get_string_size("DAY 99", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		font.get_string_size("88:88", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var cx: float = maxf(c.x, lw * 0.5 + 2.0)  # keep the caption fully on-screen

	# base dial (night navy) + thin ring + faint sunpath track
	draw_circle(c, r, Color(0.04, 0.06, 0.09, 0.97))
	draw_arc(c, r, 0.0, TAU, 44, Color(1, 1, 1, 0.32), maxf(r * 0.05, 1.2), true)
	draw_arc(c, r * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0, true)

	# SUN POSITION on a 24 h dial: midnight at the bottom, sunrise on the left,
	# noon at the top, sunset on the right (theta_s points at the sun). The
	# amber "day" half is the semicircle FACING the sun, so it rotates through
	# the day — the dial reads as a sunrise -> noon -> sunset wheel.
	var theta_s: float = PI * 0.5 + ((12.0 - t) / 24.0) * TAU
	var is_day: bool = t >= 6.0 and t < 18.0
	# day half fades at dawn/dusk and goes faint at night
	var day_a: float = 0.22
	if is_day:
		day_a = 1.0
	elif t >= 5.0 and t < 19.0:
		day_a = 0.55
	var half := PackedVector2Array()
	half.append(c)
	var steps: int = 22
	for i in range(steps + 1):
		var a: float = theta_s - PI * 0.5 + PI * float(i) / float(steps)
		half.append(c + Vector2(cos(a), -sin(a)) * r * 0.97)
	draw_colored_polygon(half, Color(1.0, 0.68, 0.25, day_a))

	# orbital marker: the sun by day, a crescent moon on the opposite side by
	# night (moonrise/set mirror the sun around the dial)
	var mrk_a: float = theta_s if is_day else theta_s + PI
	var mrk: Vector2 = c + Vector2(cos(mrk_a), -sin(mrk_a)) * r * 0.62
	if is_day:
		draw_circle(mrk, r * 0.26, Color(1.0, 0.8, 0.35, 0.45))  # glow
		draw_circle(mrk, r * 0.17, Color(1.0, 0.95, 0.68, 1.0))
	else:
		var m2r: float = r * 0.17
		draw_circle(mrk, m2r, Color(0.9, 0.94, 1.0, 1.0))
		draw_circle(mrk + Vector2(m2r * 0.55, 0.0), m2r, Color(0.04, 0.06, 0.09, 1.0))

	# caption: DAY + clock time under the dial, centered on it
	var y0: float = c.y + r + fs * 0.1
	var day_txt := "DAY %d" % day
	var day_w: float = font.get_string_size(day_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(day_txt, Vector2(cx - day_w * 0.5, y0 + fs * 0.3), fs, Color(1, 0.92, 0.7, 0.98))
	var time_txt := "%02d:%02d" % [hh, mm]
	var time_w: float = font.get_string_size(time_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(time_txt, Vector2(cx - time_w * 0.5, y0 + fs * 0.3 + fs * 1.05), fs,
		Color(0.65, 0.9, 1.0, 0.95))


func _status_bg(kind: String) -> Color:
	match kind:
		"health":
			return Color(0.72, 0.16, 0.16, 0.62)
		"hunger":
			return Color(0.8, 0.52, 0.12, 0.62)
		"thirst":
			return Color(0.18, 0.48, 0.85, 0.62)
	return Color(0.3, 0.3, 0.34, 0.62)


func _draw_pills() -> void:
	var ph: float = clampf(clampf(_vp.y * 0.05, 23.0, 34.0) * 0.92, 22.0, 32.0)
	for i in range(_pill_rects.size()):
		if i >= RESOURCE_PILL_ITEMS.size():
			break
		var rect: Rect2 = _pill_rects[i]
		var item: String = RESOURCE_PILL_ITEMS[i]
		draw_rect(rect, Color(0.05, 0.07, 0.1, 0.62), true)
		draw_rect(rect, Color(1, 1, 1, 0.16), false, 1.0)
		var center := Vector2(rect.position.x + ph * 0.5, rect.position.y + ph * 0.5)
		Icons.item_icon(self, item, center, ph * 0.34)
		var count: int = int(Inventory.total(item))
		var fs: int = int(ph * 0.5)
		var label := str(count)
		_draw_text(label, Vector2(rect.position.x + ph * 0.92, rect.position.y + ph * 0.5 + fs * 0.32), fs, Color(1, 1, 1, 0.95))


func _draw_chip() -> void:
	if _chip_text == "" or _chip_rect.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(clampf(_vp.y * 0.05, 23.0, 34.0) * 0.62, 14.0, 20.0))
	draw_rect(_chip_rect, Color(0.04, 0.06, 0.09, 0.72), true)
	draw_rect(_chip_rect, Color(1, 1, 1, 0.2), false, 1.0)
	var tw: float = font.get_string_size(_chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(_chip_text, Vector2(_chip_rect.position.x + (_chip_rect.size.x - tw) * 0.5,
			_chip_rect.position.y + _chip_rect.size.y * 0.5 + fs * 0.36), fs, Color(1, 1, 1, 0.95))


func _draw_bag_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.0, 0.0, 0.0, 0.5))
	var font := ThemeDB.fallback_font
	var rect := _panel_rect
	_draw_rounded(rect, 22.0, Color(0.055, 0.075, 0.1, 0.98))
	_draw_rounded(rect, 22.0, Color(1, 1, 1, 0.2), false, 2.0)
	# header
	var fs: int = int(clampf(rect.size.y * 0.028, 17.0, 25.0))
	_draw_text("BACKPACK", Vector2(rect.position.x + rect.size.x * 0.045,
			rect.position.y + rect.size.y * 0.062 + fs * 0.2), fs, Color(1, 1, 1, 0.95))
	var sub: String = "DRAG TO MOVE / SWAP  -  TAP HOTBAR ROW TO USE"
	var sfs: int = int(fs * 0.5)
	_draw_text(sub, Vector2(rect.position.x + rect.size.x * 0.045,
			rect.position.y + rect.size.y * 0.112 + sfs * 0.2), sfs, Color(1, 1, 1, 0.55))
	# quick-save chip + close button
	var ccr: float = _close_rect.size.x * 0.5
	if _save_rect.size.x > 0.0:
		var flash: bool = _flash_active()
		var sc := _save_rect.get_center()
		_draw_rounded(_save_rect, ccr * 0.55,
			Color(0.1, 0.45, 0.22, 0.95) if flash else Color(0.1, 0.16, 0.22, 0.9))
		_draw_rounded(_save_rect, ccr * 0.55, Color(1, 1, 1, 0.3), false, 1.5)
		var stxt: String = "SAVED ✓" if flash else "QUICK SAVE"
		var chip_fs: int = int(clampf(_save_rect.size.y * 0.34, 12.0, 18.0))
		var stw: float = font.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_fs).x
		_draw_text(stxt, Vector2(sc.x - stw * 0.5, sc.y + chip_fs * 0.34), chip_fs,
			Color(0.75, 1.0, 0.8, 1.0) if flash else Color(1, 1, 1, 0.92))
	var cc := _close_rect.get_center()
	draw_circle(cc, ccr, Color(1, 1, 1, 0.1))
	Icons.cross(self, cc, ccr * 0.9, clampf(ccr * 0.24, 2.0, 4.0), Color(1, 1, 1, 0.85))
	# grid
	var p := _get_player()
	var act_slot: int = int(p.get("active_slot_index")) if p != null else 0
	for idx in range(_bag_slot_rects.size()):
		var b: Rect2 = _bag_slot_rects[idx]
		var is_hotbar: bool = idx < HOTBAR_COUNT
		var selected: bool = is_hotbar and idx == act_slot and not Inventory.slot_empty(idx)
		_draw_slot(b, _pressed_visual == idx, selected)
		# hotbar row gets a subtle divider tint so it reads as the equip row
		if is_hotbar:
			_draw_rounded(b.grow(-2.0), b.size.x * 0.16, Color(1, 1, 1, 0.03), true, 1.0)
		if not Inventory.slot_empty(idx):
			Icons.item_icon(self, Inventory.slot_item(idx), b.get_center(), b.size.x * 0.24)
			var count: int = Inventory.slot_count(idx)
			if count > 0:
				var cfs: int = int(clampf(b.size.x * 0.28, 11.0, 20.0))
				var label := str(count)
				var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
				_draw_text(label, Vector2(b.end.x - tw2 - b.size.x * 0.08,
						b.position.y + b.size.y * 0.78 + cfs * 0.26), cfs, Color(1, 1, 1, 0.95))


func _draw_drag_ghost() -> void:
	if _drag_from < 0 or _drag_from >= Inventory.SLOT_COUNT or Inventory.slot_empty(_drag_from):
		return
	var sz := _slot * 0.92
	var r := Rect2(_drag_pos.x - sz * 0.5, _drag_pos.y - sz * 0.5, sz, sz)
	_draw_slot(r, false, false)
	Icons.item_icon(self, Inventory.slot_item(_drag_from), r.get_center(), sz * 0.28)
	var font := ThemeDB.fallback_font
	var count: int = Inventory.slot_count(_drag_from)
	if count > 1:
		var cfs: int = int(clampf(sz * 0.26, 11.0, 20.0))
		var label := str(count)
		var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		_draw_text(label, Vector2(r.end.x - tw2 - r.size.x * 0.1, r.position.y + r.size.y * 0.8 + cfs * 0.24), cfs, Color(1, 1, 1, 0.98))


func _draw_slot(rect: Rect2, pressed: bool, selected: bool) -> void:
	var bg := Color(0.05, 0.07, 0.1, 0.66)
	if selected:
		bg = Color(0.1, 0.18, 0.24, 0.88)
	elif pressed:
		bg = Color(0.16, 0.2, 0.26, 0.82)
	var radius: float = rect.size.x * 0.2
	_draw_rounded(rect, radius, bg)
	var border: Color = Color(1, 1, 1, 0.25)
	if selected:
		border = Color(0.42, 0.92, 1.0, 0.95)
	elif pressed:
		border = Color(1, 1, 1, 0.6)
	_draw_rounded(rect.grow(-1.5), radius * 0.9, border, false, 2.0)
	if selected:
		_draw_rounded(rect.grow(2.0), radius, Color(0.42, 0.92, 1.0, 0.12), false, 3.0)


# ============================================================
# HELPERS
# ============================================================
func _draw_rounded(rect: Rect2, _radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	if filled:
		draw_style_box(_rounded_style(color), rect)
	else:
		draw_style_box(_rounded_style_outline(color, width), rect)


func _rounded_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(18)
	s.set_border_width_all(0)
	return s


func _rounded_style_outline(color: Color, width: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(18)
	s.border_color = color
	s.set_border_width_all(int(maxf(width, 1.0)))
	return s


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
