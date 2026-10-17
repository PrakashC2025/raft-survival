extends Control
class_name SurvivalHUD

const Icons := preload("res://scripts/ui_icons.gd")
const UI_SURFACE := preload("res://scripts/ui_surface.gd")
var _refresh_seconds := 0.0

## ============================================================
## MOBILE SURVIVAL HUD — graphical overlay shown on touch devices (and the
## desktop F10 preview). Item art shares an original textured atlas.
##
## NORMAL MODE (Build Mode OFF):
##   - bottom-center: HOTBAR of inventory slots 0..5 (items the player owns)
##     + a BAG button at its right end. Tap a slot to make that item the
##     active one (highlighted). Tapping the BAG opens the 30-slot panel.
##   - right side: separate MAP, CRAFT and permanent ROPE shortcuts.
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
const CRAFT_ORDER := ["Torch","Diving Tank","Spear","Axe","Shovel","Pickaxe","Paddle","Anchor","Fishing Rod","Sail Kit","Motor Kit","Rowboat Kit","Life Vest","Bow","Arrow","Bandage","Solar Torch","Binoculars","Walkie Talkie","Battery","Repair Kit","Screw","Wire","Motor","Medkit","Can","Tumbler","Barrel","PlanterPot","PlanterBox","TreePot"]
const RESOURCE_PILL_ITEMS := []
const STATS := [["health", "HEALTH"], ["thirst", "WATER"], ["hunger", "HUNGER"]]
const FOOD_RULES := preload("res://scripts/food_rules.gd")
const ITEM_GUIDE := preload("res://scripts/item_guide.gd")
var _display_stats := [100.0,100.0,100.0]
const ITEM_LABELS := {"Torch":"Hand Fire Torch","Bonfire":"Bonfire","Diving Tank":"Handmade Air Tank","PlanterPot":"Plant Pot","PlanterBox":"Plant Bed","TreePot":"Tree Pot","RainCollector":"Rain Collector","SandFilter":"Sand Filter","HalfWall":"Half Wall","CargoCrate":"Cargo Crate","WallTorch":"Wall Torch","WaterPurifier":"Water Purifier","WindGenerator":"Wind Generator","ElectricLamp":"Salvaged LED","ElectricPurifier":"Electric Purifier","RescueRadio":"Rescue Radio"}
const MAP_RANGE_METERS := 430.0
var _map_range := MAP_RANGE_METERS

const HOTBAR_COUNT := 6
const BAG_COLS := 6
const BAG_ROWS := 5   # 24 bag slots + one row of six hotbar slots

var _bag_open := false
var _map_open := false
var _craft_open := false
var _craft_menu: Control
var _selected_island: Node3D = null

# --- map / crafting modal geometry ---
var _map_button_rect := Rect2()
var _craft_button_rect := Rect2()
var _map_panel_rect := Rect2()
var _map_close_rect := Rect2()
var _map_course_rect := Rect2()
var _map_cancel_course_rect := Rect2()
var _map_area_rect := Rect2()
var _map_center := Vector2.ZERO
var _map_plot_radius := 0.0
var _map_markers: Array[Dictionary] = []
var _craft_selected := "Torch"
var _inspect_slot := -1
var _bag_use_rect := Rect2()
var _bag_equip_rect := Rect2()
var _bag_detail_rect := Rect2()
var _mission_rect := Rect2()
var _held_card_rect := Rect2()
var _focus_label := ""
var _trip_card_rect := Rect2()
var _trip_skip_rect := Rect2()
var _trip_transition: CanvasLayer

# --- geometry (recomputed every frame while visible) ---
var _vp := Vector2.ZERO
var _hotbar_rects: Array = []      # bottom bar (normal-mode items or build pieces)
var _rope_slot_rect := Rect2()    # permanent equipment; never an inventory stack
var _bag_rect := Rect2()           # the BAG button (normal mode)
var _hud_craft_rect := Rect2()     # direct quick-access CRAFT button on HUD
var _hud_map_rect := Rect2()       # direct quick-access MAP chart button on HUD
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
var _toast_lines := PackedStringArray()
var _toast_font_size := 15
var _pickup_queue: Array[Dictionary] = []
var _pickup_active: Dictionary = {}
var _pickup_remaining := 0.0

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
var _map_log_rect := Rect2()

# --- pause (button under the day/night clock) ---
var _pause_center := Vector2.ZERO
var _pause_btn_rect := Rect2()
var _paused := false
var _pause_panel_rect := Rect2()
var _pause_resume_rect := Rect2()
var _pause_quit_rect := Rect2()
var _pause_settings_rect := Rect2()
var _inventory_touch_id := -1
var _death_open := false
var _death_panel_rect := Rect2()
var _death_respawn_rect := Rect2()
var _death_menu_rect := Rect2()


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
	Inventory.pickup_received.connect(show_pickup)
	var vp := get_viewport()
	vp.size_changed.connect(_on_size_changed)
	visible = _should_show()
	_on_size_changed()


func show_pickup(item: String, amount: int) -> void:
	if amount<=0:return
	_pickup_queue.append({"item":item,"amount":amount})
	if _pickup_active.is_empty():_advance_pickup()

func _advance_pickup() -> void:
	_pickup_active = _pickup_queue.pop_front() if not _pickup_queue.is_empty() else {}
	_pickup_remaining = 1.6 if not _pickup_active.is_empty() else 0.0
	queue_redraw()

func _inventory_changed() -> void:
	_last_key = ""
	if visible:
		queue_redraw()


## True while a HUD modal should keep one-shot world actions from firing.
func gameplay_input_blocked() -> bool:
	var actor:=_get_player()
	if actor!=null and actor.has_node("SurvivalServices") and actor.get_node("SurvivalServices").is_modal():return true
	return _trip_skipping() or GameSettings.is_open or _map_open or _craft_open or _bag_open or _paused or _death_open

func _trip_skipping() -> bool:
	return is_instance_valid(_trip_transition) and bool(_trip_transition.get("active"))

func _begin_trip_skip() -> void:
	if _trip_skipping():return
	var actor:=_get_player() as CharacterBody3D
	var vessel:=_get_raft()
	if actor==null or vessel==null or not vessel.has_method("can_skip_course"):return
	if not preload("res://scripts/course_skip.gd").aboard(vessel,actor):_show_toast("BOARD YOUR BOAT OR RAFT TO SKIP THE TRIP");return
	if not bool(vessel.call("can_skip_course")):_show_toast("ALREADY NEAR YOUR DESTINATION · KEEP SAILING");return
	if actor.build_mode or is_instance_valid(actor._editing) or actor.get_node("SurvivalServices").busy():_show_toast("FINISH YOUR CURRENT ACTION TO SKIP");return
	if _map_open:_close_map()
	_trip_transition=preload("res://scripts/trip_transition.gd").new()
	_trip_transition.player=actor;_trip_transition.vehicle=vessel
	add_child(_trip_transition);queue_redraw()


func _on_bag_full(amount: int) -> void:
	_show_toast("BAG FULL" if amount >= 1 else "")


func _show_toast(text: String, seconds: float=2.2) -> void:
	_toast = text
	_toast_until = Time.get_ticks_msec() / 1000.0 + seconds
	queue_redraw()


## Public toast (used by the player for quick-save feedback etc.).
func show_toast(text: String, seconds: float=2.2) -> void:
	_show_toast(text,seconds)


func show_death() -> void:
	if is_instance_valid(_craft_menu):_close_crafting()
	GameSettings.release_gameplay_input()
	_death_open = true
	_map_open = false
	_craft_open = false
	_bag_open = false
	_paused = false
	_cancel_drag()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_compute_layout()
	queue_redraw()


func _close_death() -> void:
	_death_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	if not _should_show():
		visible = false
	queue_redraw()


func _respawn_from_death() -> void:
	var player := _get_player()
	_close_death()
	if player != null and player.has_method("respawn_from_death"):
		player.call("respawn_from_death")


func toggle_map() -> void:
	if is_instance_valid(_craft_menu):_close_crafting()
	if _death_open:
		return
	if _map_open:
		_close_map()
		return
	if _paused:
		return
	_map_open = true
	GameSettings.release_gameplay_input()
	_craft_open = false
	_bag_open = false
	_selected_island = null
	_cancel_drag()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_compute_layout()
	queue_redraw()


func toggle_crafting() -> void:
	if _death_open:
		return
	if _craft_open:
		_close_crafting()
		return
	if _paused:
		return
	_craft_open = true
	GameSettings.release_gameplay_input()
	_map_open = false
	_bag_open = false
	_cancel_drag()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_craft_menu=preload("res://scripts/craft_menu.gd").new()
	add_child(_craft_menu)
	var products:=CRAFT_ORDER.duplicate()
	products.insert(products.find("Rowboat Kit"),"BoatWorkshop")
	for item in Inventory.ITEM_RECIPES:
		if not products.has(item):products.append(item)
	var actor:=_get_player()
	if actor!=null:
		for item in actor.BUILD_RECIPE_NAMES:
			if Inventory.RECIPES.has(item) and not products.has(item):products.append(item)
	var labels:=ITEM_LABELS.duplicate();labels.FishingNet="Fishing Net";labels.ElectricLamp="Salvaged LED"
	labels.SeedDryingTray="Seed Drying Tray"
	labels.BoatWorkshop="Boat Workshop"
	_craft_menu.setup(products,labels)
	_craft_menu.closed.connect(_close_crafting)
	_craft_menu.build_requested.connect(func(item: String, quantity: int):
		_craft_selected=item
		_confirm_craft_selection(quantity))
	_compute_layout()
	queue_redraw()


func _close_map() -> void:
	_map_open = false
	get_tree().paused = _paused
	if not _paused and not _death_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _should_show():
		visible = false
	queue_redraw()


func _close_crafting() -> void:
	_craft_open = false
	if is_instance_valid(_craft_menu):_craft_menu.hide();_craft_menu.queue_free()
	_craft_menu=null
	get_tree().paused = _paused
	if not _paused and not _death_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _should_show():
		visible = false
	queue_redraw()


func _touch_ui_active() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	var mc: Node = get_parent().get_node_or_null("MobileControls")
	return mc != null and bool(mc.get("force_show")) == true


func _should_show() -> bool:
	return _touch_ui_active() or _map_open or _craft_open or _bag_open or _paused or _death_open \
		or _trip_card_rect.has_area() or (not _toast.is_empty() and Time.get_ticks_msec()/1000.0<_toast_until)

func _feedback_only() -> bool:
	return not _touch_ui_active() and not (_map_open or _craft_open or _bag_open or _paused or _death_open)


func _on_size_changed() -> void:
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	queue_redraw()
	_cancel_drag()
	_compute_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if not _death_open and not GameSettings.is_open:
			_map_open = false
			_craft_open = false
			_set_paused(true)


func handle_back() -> void:
	if _trip_skipping():_trip_transition.call("cancel");return
	if _death_open:
		return
	var actor:=_get_player()
	var service:=actor.get_node_or_null("SurvivalServices") if actor!=null else null
	if service!=null and service.is_modal():service.close_menu();return
	if not GameSettings.is_open:
		var controls := get_parent().get_node_or_null("MobileControls")
		if controls != null and bool(controls.get("_help_open")):
			controls.call("_set_help", false)
		elif _map_open:
			_close_map()
		elif _craft_open:
			_close_crafting()
		elif _bag_open:
			_bag_open = false
			_cancel_drag()
		else:
			_set_paused(not _paused)


func _process(delta: float) -> void:
	# Action feedback belongs to gameplay; it must not cover inventory recipes.
	var actor:=_get_player()
	var action:=actor.get_node_or_null("SurvivalAction") if actor!=null else null
	if action!=null and is_instance_valid(action.get("_panel")):
		action.get("_panel").visible=not gameplay_input_blocked() and not get_tree().paused and not str(action.kind).is_empty() and not action._construction_idle
	if _pickup_remaining>0.0 and not get_tree().paused:
		_pickup_remaining-=delta
		if _pickup_remaining<=0.0:_advance_pickup()
		queue_redraw()
	for index in STATS.size():
		var target:=clampf(_get_stat(STATS[index][0]),0,100)
		if absf(float(_display_stats[index])-target)>.05:
			_display_stats[index]=lerpf(float(_display_stats[index]),target,1.0-exp(-delta*9.0));queue_redraw()
	var want := _should_show()
	if visible != want:
		visible = want
		if not want:
			_bag_open = false
			_cancel_drag()
		queue_redraw()
	if not visible:
		return
	_refresh_seconds += delta
	if _refresh_seconds < 0.1:
		return
	_refresh_seconds = 0.0
	_focus_label=_aimed_item_label()
	_compute_layout()
	if _flash_active():
		queue_redraw()  # re-draw the "SAVED ✓" chip while it is lit
	var key := _build_cache_key()
	if _get_stat("health")<=25 or _get_stat("thirst")<=25 or _get_stat("hunger")<=25:queue_redraw()
	if key != _last_key:
		_last_key = key
		queue_redraw()


# ============================================================
# PUBLIC — coordination with MobileControls
# ============================================================
func is_blocking() -> bool:
	return gameplay_input_blocked()


## Should MobileControls treat this screen point as HUD territory (never
## start camera look from it)?
func claims_touch(pos: Vector2) -> bool:
	_compute_layout()
	if not visible or (_feedback_only() and not _trip_skip_rect.has_point(pos)):
		return false
	if _bag_open or _map_open or _craft_open or _paused or _death_open:
		return true
	if _pause_btn_rect.has_point(pos) or _bag_rect.has_point(pos) or _map_button_rect.has_point(pos) or _craft_button_rect.has_point(pos):
		return true
	if _hud_craft_rect.has_point(pos) or _hud_map_rect.has_point(pos):
		return true
	if _rope_slot_rect.has_point(pos): return true
	if _trip_skip_rect.has_point(pos):return true
	if not _trip_card_rect.has_area() and _mission_recipe()!="" and _mission_rect.has_point(pos):return true
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
	var cr: float = clampf(_vp.y * 0.038, 21.0, 29.0)
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
		sx -= cr * 2.0 + maxf(gap,cr*0.60)

	# pause button centered under the clock caption (same far-right column)
	_pause_btn_rect = Rect2()
	if _clock_r > 0.0:
		var pb_r: float = maxf(24.0, _clock_r * 0.66)
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

	# Map and crafting live inside the bag, keeping gameplay clear.
	_map_button_rect = Rect2()
	_craft_button_rect = Rect2()

	# Keep the bottom dock to six inventory slots plus BAG; build uses piece slots.
	_slot = clampf(_vp.y * 0.083, 48.0, 74.0)
	var sg: float = _slot * 0.14
	var building: bool = _in_build_mode()
	var n: int = HOTBAR_COUNT
	var extra: int = 0 if building else 1
	var total: float = float(n + extra) * _slot + float(n - 1 + extra) * sg
	var x0: float = (_vp.x - total) * 0.5
	var y0: float = _vp.y - m - _slot
	_held_card_rect=Rect2(x0,y0-70,total,60) if not building else Rect2()
	_mission_rect=Rect2(Vector2(m,top_safe),Vector2(minf(320,_vp.x*.30),96)) if not building and not _editing() else Rect2()
	_trip_card_rect=Rect2();_trip_skip_rect=Rect2()
	var vessel:=_get_raft()
	var traveller:=_get_player() as CharacterBody3D
	if not building and not _editing() and not gameplay_input_blocked() and vessel!=null and vessel.has_method("has_active_course") and vessel.call("has_active_course") and preload("res://scripts/course_skip.gd").aboard(vessel,traveller):
		_trip_card_rect=Rect2(_mission_rect.position,Vector2(_mission_rect.size.x,114))
		if vessel.has_method("can_skip_course") and vessel.call("can_skip_course"):
			_trip_skip_rect=Rect2(_trip_card_rect.position+Vector2(12,54),Vector2(_trip_card_rect.size.x-24,48))
	_hotbar_rects.clear()
	for i in range(n):
		_hotbar_rects.append(Rect2(x0 + float(i) * (_slot + sg), y0, _slot, _slot))
	_bag_rect = Rect2() if building else Rect2(x0 + float(n) * (_slot + sg), y0, _slot, _slot)
	if not building:
		# A separate utility column leaves the left joystick and right action
		# buttons clear. Keep MAP below the clock/status area at every scale.
		var shortcut_scale := clampf(_vp.y / 720.0, 0.80, 1.35)
		var shortcut_side := 60.0 * shortcut_scale
		var shortcut_gap := 12.0 * shortcut_scale
		var shortcut_x := _vp.x - 76.0 * shortcut_scale
		var shortcut_y := 228.0 * shortcut_scale
		_hud_map_rect = Rect2(shortcut_x, shortcut_y, shortcut_side, shortcut_side)
		_hud_craft_rect = Rect2(shortcut_x, _hud_map_rect.end.y + shortcut_gap, shortcut_side, shortcut_side)
		_rope_slot_rect = Rect2(shortcut_x, _hud_craft_rect.end.y + shortcut_gap, shortcut_side, shortcut_side)
	else:
		_hud_craft_rect = Rect2()
		_hud_map_rect = Rect2()
		_rope_slot_rect = Rect2()

	# build/edit chip top-center
	_chip_text = _build_chip_text()
	if _chip_text != "":
		var fs: int = int(clampf(cr * 0.62, 14.0, 20.0))
		var cw: float = font.get_string_size(_chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + cr * 1.4
		var ch: float = cr * 1.15
		_chip_rect = Rect2(m, top_safe, cw, ch)
	else:
		_chip_rect = Rect2()

	# All 30 slots keep their saved indices. A separate reading pane makes a
	# picture, purpose and explicit actions visible without tiny footer buttons.
	_bag_slot_rects.clear()
	if _bag_open:
		var bag_scale:=minf((_vp.x-24)/1010.0,(_vp.y-24)/660.0)
		var cell: float = 76*bag_scale
		var cg: float = 8*bag_scale
		var pad: float = 22*bag_scale
		var grid_width: float = float(BAG_COLS)*cell+float(BAG_COLS-1)*cg
		var pw: float = 1010*bag_scale
		var phh: float = 660*bag_scale
		_panel_rect = Rect2((_vp.x - pw) * 0.5, (_vp.y - phh) * 0.5, pw, phh)
		var ccr: float = 48*bag_scale
		_close_rect = Rect2(_panel_rect.end.x-pad-ccr,_panel_rect.position.y+pad*.5,ccr,ccr)
		# SAVE chip in the header, left of the close button
		var sfs: int = int(clampf(cell * 0.3, 12.0, 18.0))
		var stxt: String = "SAVED ✓" if _flash_active() else "QUICK SAVE"
		var sw: float = font.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		var scw: float = sw + cell * 0.5
		_save_rect = Rect2(_close_rect.position.x - scw - pad * 0.6, _panel_rect.position.y + pad * 0.35, scw, ccr)
		var tab_y: float = _panel_rect.position.y+72*bag_scale
		var tab_w: float = (pw-pad*2-cg)*.5
		_map_button_rect = Rect2(_panel_rect.position.x+pad,tab_y,tab_w,48*bag_scale)
		_craft_button_rect = Rect2(_map_button_rect.end.x+cg,tab_y,tab_w,48*bag_scale)
		var grid_origin := _panel_rect.position+Vector2(22,148)*bag_scale
		for idx in range(Inventory.SLOT_COUNT):
			var r := _row_of(idx)
			var c := _col_of(idx)
			var rr := Rect2(grid_origin.x + float(c) * (cell + cg),
				grid_origin.y + float(r) * (cell + cg), cell, cell)
			if idx<HOTBAR_COUNT:rr.position.y+=18*bag_scale
			_bag_slot_rects.append(rr)
		_bag_detail_rect=Rect2(grid_origin+Vector2(grid_width+pad,0),Vector2(pw-grid_width-pad*3,phh-170*bag_scale))
		_bag_equip_rect=Rect2(_bag_detail_rect.position.x+14*bag_scale,_bag_detail_rect.end.y-78*bag_scale,_bag_detail_rect.size.x-28*bag_scale,64*bag_scale)
		_bag_use_rect=Rect2(_bag_equip_rect.position-Vector2(0,76*bag_scale),_bag_equip_rect.size)
	else:
		_save_rect = Rect2()
		_bag_detail_rect=Rect2();_bag_use_rect=Rect2();_bag_equip_rect=Rect2()

	# Full-screen chart modal, projected from the raft's current world position.
	_map_markers.clear()
	if _map_open:
		var map_pad: float = clampf(_vp.y * 0.025, 12.0, 24.0)
		var map_w: float = minf(_vp.x * 0.94, 900.0)
		var map_h: float = minf(_vp.y * 0.86, 820.0)
		_map_panel_rect = Rect2((_vp.x - map_w) * 0.5, (_vp.y - map_h) * 0.5, map_w, map_h)
		var close_r: float = clampf(map_h * 0.045, 20.0, 30.0)
		_map_close_rect = Rect2(_map_panel_rect.end.x - map_pad - close_r * 2.0,
				_map_panel_rect.position.y + map_pad * 0.65, close_r * 2.0, close_r * 2.0)
		_map_log_rect=Rect2(_map_close_rect.position-Vector2(126,0),Vector2(112,_map_close_rect.size.y))
		var head_h: float = clampf(map_h * 0.12, 68.0, 96.0)
		var foot_h: float = clampf(map_h * 0.13, 78.0, 106.0)
		_map_area_rect = Rect2(_map_panel_rect.position.x + map_pad,
				_map_panel_rect.position.y + map_pad + head_h,
				map_w - map_pad * 2.0, map_h - map_pad * 2.0 - head_h - foot_h)
		_map_center = _map_area_rect.get_center()
		_map_plot_radius = maxf(24.0, minf(_map_area_rect.size.x, _map_area_rect.size.y) * 0.43)
		var course_w: float = minf(map_w - map_pad * 2.0, 420.0)
		var course_h: float = clampf(map_h * 0.085, 48.0, 64.0)
		_map_course_rect = Rect2(_map_panel_rect.get_center().x - course_w * 0.5,
				_map_panel_rect.end.y - map_pad - course_h, course_w, course_h)
		_map_cancel_course_rect=Rect2()
		var current_vessel:=_get_raft()
		if current_vessel!=null and current_vessel.call("has_active_course"):
			_map_course_rect.size.x=course_w*.65-6
			_map_cancel_course_rect=Rect2(_map_course_rect.end+Vector2(12,-course_h),Vector2(course_w*.35-6,course_h))
		var raft := _get_raft()
		var origin := raft.global_position if raft != null else Vector3.ZERO
		_map_range=MAP_RANGE_METERS
		var destinations:=get_tree().get_nodes_in_group("island")+get_tree().get_nodes_in_group("dive_site")
		destinations.append_array(get_tree().get_nodes_in_group("player_boat"))
		destinations.append_array(get_tree().get_nodes_in_group("drift_cache"))
		if raft!=null and raft.is_in_group("player_boat"):
			var home:=get_tree().get_first_node_in_group("raft") as Node3D
			if home!=null:home.set_meta("map_label","Home Raft");home.set_meta("arrival_radius",maxf(5.0,float(home.get("_deck_radius"))+4));destinations.append(home)
		for destination in destinations:
			var relative: Vector3=destination.global_position-origin
			_map_range=maxf(_map_range,Vector2(relative.x,relative.z).length()*1.22)
		for island in destinations:
			if not (island is Node3D) or not is_instance_valid(island):
				continue
			var island_node := island as Node3D
			var offset := island_node.global_position - origin
			var relative := Vector2(offset.x, offset.z)
			var map_pos := _map_center + relative / _map_range * _map_plot_radius
			var label: String = str(island_node.get_meta("map_label", island_node.name))
			_map_markers.append({
				"node": island_node,
				"label": label,
				"pos": map_pos,
				"distance": relative.length(),
			})
		if _selected_island != null and not is_instance_valid(_selected_island):
			_selected_island = null
	else:
		_map_panel_rect = Rect2()
		_map_close_rect = Rect2()
		_map_log_rect = Rect2()
		_map_course_rect = Rect2()
		_map_cancel_course_rect=Rect2()
		_map_area_rect = Rect2()
		_map_center = Vector2.ZERO
		_map_plot_radius = 0.0

	# toast pill (above the bottom bar)
	_toast_rect = Rect2()
	var now := Time.get_ticks_msec() / 1000.0
	if _toast != "" and now < _toast_until:
		_toast_font_size = int(clampf(_slot * 0.3, 15.0, 20.0))
		var max_width := minf(_vp.x*.27,340.0)
		_toast_lines = PackedStringArray()
		var line := ""
		for word in _toast.split(" ",false):
			var next := word if line.is_empty() else line+" "+word
			if not line.is_empty() and font.get_string_size(next,HORIZONTAL_ALIGNMENT_LEFT,-1,_toast_font_size).x>max_width-32:
				_toast_lines.append(line);line=word
			else:line=next
		_toast_lines.append(line)
		var tw2 := 0.0
		for text_line in _toast_lines:tw2=maxf(tw2,font.get_string_size(text_line,HORIZONTAL_ALIGNMENT_LEFT,-1,_toast_font_size).x)
		var tw_: float = minf(max_width,tw2+32)
		var th: float = _toast_lines.size()*(_toast_font_size+6)+20
		_toast_rect = Rect2(m, minf(_vp.y*.24,172.0), tw_, th)
	else:
		_toast = ""

	# pause overlay (drawn above everything while paused)
	if _paused:
		var ppad: float = clampf(_vp.y * 0.035, 16.0, 26.0)
		var ppw: float = minf(_vp.x * 0.72, 430.0)
		var ptrow: float = clampf(_vp.y * 0.055, 30.0, 46.0)
		var pbh2: float = clampf(_vp.y * 0.078, 46.0, 68.0)
		var psep2: float = clampf(_vp.y * 0.02, 10.0, 16.0)
		var pph2: float = ppad * 2.0 + ptrow + psep2 + pbh2 * 3.0 + psep2 * 2.0
		_pause_panel_rect = Rect2((_vp.x - ppw) * 0.5, (_vp.y - pph2) * 0.5, ppw, pph2)
		var pqx: float = _pause_panel_rect.position.x + ppad
		var pqw: float = ppw - ppad * 2.0
		_pause_resume_rect = Rect2(pqx, _pause_panel_rect.position.y + ppad + ptrow + psep2, pqw, pbh2)
		_pause_settings_rect = Rect2(pqx, _pause_resume_rect.end.y + psep2, pqw, pbh2)
		_pause_quit_rect = Rect2(pqx, _pause_settings_rect.end.y + psep2, pqw, pbh2)
	else:
		_pause_panel_rect = Rect2()
		_pause_resume_rect = Rect2()
		_pause_quit_rect = Rect2()
		_pause_settings_rect = Rect2()

	if _death_open:
		var death_pad: float = clampf(_vp.y * 0.035, 16.0, 28.0)
		var death_w: float = minf(_vp.x * 0.82, 460.0)
		var death_h: float = clampf(_vp.y * 0.36, 250.0, 330.0)
		_death_panel_rect = Rect2((_vp.x - death_w) * 0.5, (_vp.y - death_h) * 0.5, death_w, death_h)
		var button_h: float = clampf(death_h * 0.2, 52.0, 68.0)
		var button_w: float = death_w - death_pad * 2.0
		var button_x: float = _death_panel_rect.position.x + death_pad
		var button_y: float = _death_panel_rect.position.y + death_h * 0.5
		_death_respawn_rect = Rect2(button_x, button_y, button_w, button_h)
		_death_menu_rect = Rect2(button_x, button_y + button_h + death_pad * 0.5, button_w, button_h)
	else:
		_death_panel_rect = Rect2()
		_death_respawn_rect = Rect2()
		_death_menu_rect = Rect2()


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
	key += "|inspect" + str(_inspect_slot)
	key += "|focus"+_focus_label
	key += "|map" + str(_map_open) + "|craft" + str(_craft_open) + "|death" + str(_death_open)
	key += "|map_selected" + (str(_selected_island.name) if _selected_island != null and is_instance_valid(_selected_island) else "")
	if p == null:
		return key
	var progress := p.get_node_or_null("SurvivalProgression")
	if progress != null:
		key += str(progress.level) + str(progress.call("objective")) + str(int(progress.oxygen)) + str(int(progress.stamina))+str(int(progress.air_tank_seconds))+str(int(progress.wetness))
	key += "|bm" + str(p.get("build_mode") == true)
	key += "|ed" + str(_editing())
	key += "|sel" + str(int(p.get("selected_piece_index")))
	key += "|act" + str(int(p.get("active_slot_index")))
	key += "|av" + str(p.get("active_item"))
	var vessel:=_get_raft()
	if vessel!=null and vessel.has_method("has_active_course"):
		key+="|trip"+str(vessel.call("has_active_course"))+str(int(vessel.call("get_course_distance")))+str(_trip_skipping())
	if _map_open:key+="|heading"+str(snappedf(p.global_rotation.y,.01))+"|position"+str(p.global_position.snapped(Vector3.ONE))
	var salvage:=p.get_node_or_null("OceanSalvage")
	if salvage!=null:key+="|cargo"+salvage.objective()+salvage.journal_caption()
	if progress!=null and (progress.oxygen<=25 or (progress.diving_tank and progress.air_tank_seconds<=30)):key+="|airblink"+str(floori(float(Time.get_ticks_msec())/400.0))
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
	var idx: int = clampi(int(p.get("selected_piece_index")), 0, p.BUILD_RECIPE_NAMES.size() - 1)
	var piece_name2: String = p.BUILD_RECIPE_NAMES[idx]
	var ok: bool = p.get("build_valid") == true
	var state := "READY" if ok else "NO SPOT"
	var cost := ""
	var multiplier := 1
	var room_plan: Dictionary = p.get("_smart_roof_plan")
	if piece_name2 == "Roof" and not room_plan.is_empty():
		multiplier = room_plan.transforms.size()
		state = "READY %d TILES" % multiplier if ok else "NO SPOT"
	if Inventory.RECIPES.has(piece_name2):
		var parts: Array = []
		var recipe: Dictionary = Inventory.recipe_cost(piece_name2)
		for item in recipe:
			parts.append("%s %d/%d" % [str(item).to_upper(), Inventory.total(item),int(recipe[item])*multiplier])
		cost = "   " + "  ".join(parts)
	var afford := "OK" if Inventory.can_afford(piece_name2) else "NEED MORE"
	if multiplier > 1:
		var total_cost := {}
		for item in Inventory.RECIPES[piece_name2]: total_cost[item] = int(Inventory.RECIPES[piece_name2][item])*multiplier
		afford = "OK" if Inventory.infinite or Inventory.has_cost(total_cost) else "NEED MORE"
	var piece_label: String = {"HalfWall":"HALF WALL","CargoCrate":"CARGO CRATE","SandFilter":"SAND FILTER"}.get(piece_name2,piece_name2.to_upper())
	return "%s  %s%s   [%s]" % [piece_label, state, cost, afford]


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
	if not bool(p.call("quick_save")): return
	_save_flash_until = Time.get_ticks_msec() / 1000.0 + 1.6
	queue_redraw()


func _cancel_drag() -> void:
	_inventory_touch_id = -1
	_press_slot = -1
	_dragging = false
	_drag_from = -1
	_pressed_visual = -1
	_press_bag = false


# ============================================================
# INPUT — touches on hotbar / bag / panel
# ============================================================
func _input(event: InputEvent) -> void:
	if _trip_skipping():
		if event is InputEventKey and event.pressed and event.is_action_pressed("ui_cancel"):_trip_transition.call("cancel")
		_consume_input();return
	if GameSettings.is_open:
		return
	var actor:=_get_player()
	var service:=actor.get_node_or_null("SurvivalServices") if actor!=null else null
	if service!=null and service.is_modal():
		if event is InputEventKey and event.pressed and event.is_action_pressed("ui_cancel"):
			service.close_menu();_consume_input()
		return
	var controls := get_parent().get_node_or_null("MobileControls")
	if controls != null and bool(controls.get("_help_open")):
		return
	# ScrollContainer owns the finger and its emulated mouse stream. The
	# gameplay input stays released/paused until this menu is dismissed.
	if _craft_open and is_instance_valid(_craft_menu) and not event is InputEventKey:
		return
	if _craft_open and is_instance_valid(_craft_menu) and event is InputEventKey and _craft_menu._search.has_focus() and not event.is_action_pressed("ui_cancel"):
		return
	# Android replays a finger event as a mouse event. This custom HUD already
	# handles the finger; processing both can immediately close the opened bag
	# or confirm a recipe twice. Real desktop mouse events remain supported.
	if event is InputEventMouse and event.device == -1:
		if visible and (gameplay_input_blocked() or claims_touch(event.position)):
			_consume_input()
		return
	_compute_layout()
	if _death_open:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			_consume_input()
			if event.is_action_pressed("ui_accept") or (event as InputEventKey).keycode == KEY_ENTER:
				_respawn_from_death()
			elif event.is_action_pressed("ui_cancel") or (event as InputEventKey).keycode == KEY_ESCAPE:
				_quit_to_menu()
		elif event is InputEventScreenTouch or event is InputEventMouseButton:
			_handle_death_pointer(event)
		return
	# Keyboard shortcuts also work when the desktop HUD is normally hidden.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		if event.is_action_pressed("ui_cancel") or (event as InputEventKey).keycode == KEY_ESCAPE:
			if _map_open:
				_close_map()
			elif _craft_open:
				_close_crafting()
			elif _bag_open:
				_bag_open = false
				_cancel_drag()
				queue_redraw()
			elif _paused:
				_set_paused(false)
			else:
				_set_paused(true)
			_consume_input()
			return
		if event.is_action_pressed("toggle_map"):
			toggle_map()
			_consume_input()
			return
		if event.is_action_pressed("toggle_crafting"):
			toggle_crafting()
			_consume_input()
			return
	if visible and _feedback_only():
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed):
			if _trip_skip_rect.has_point(event.position):_begin_trip_skip();_consume_input()
		return
	if not visible:
		return
	if _map_open or _craft_open:
		_handle_modal_pointer(event)
		return
	if _paused:
		# While paused only the overlay buttons react; nothing else moves.
		if event is InputEventScreenTouch:
			_handle_pause_input(event as InputEventScreenTouch)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			_handle_pause_mouse((event as InputEventMouseButton).position)
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _pause_btn_rect.has_point(touch.position):
				_set_paused(true)
				_consume_input()
				return
			if _map_button_rect.has_point(touch.position):
				toggle_map()
				_consume_input()
				return
			if _craft_button_rect.has_point(touch.position):
				toggle_crafting()
				_consume_input()
				return
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			if _map_button_rect.has_point(mouse.position):
				toggle_map()
				_consume_input()
				return
			if _craft_button_rect.has_point(mouse.position):
				toggle_crafting()
				_consume_input()
				return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var pointer_touch:=InputEventScreenTouch.new()
		pointer_touch.index=-2;pointer_touch.position=event.position;pointer_touch.pressed=event.pressed
		event=pointer_touch
	elif event is InputEventMouseMotion and _inventory_touch_id==-2:
		var pointer_drag:=InputEventScreenDrag.new()
		pointer_drag.index=-2;pointer_drag.position=event.position;pointer_drag.relative=event.relative
		event=pointer_drag
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if _bag_open:
		_handle_bag_input(event)
	else:
		_handle_bar_input(event)


func _consume_input() -> void:
	var input_viewport := get_viewport()
	if input_viewport != null:
		input_viewport.set_input_as_handled()


func _handle_death_pointer(event: InputEvent) -> void:
	var pointer := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pointer = touch.position
		pressed = touch.pressed
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		pointer = mouse.position
		pressed = mouse.pressed
	if pressed:
		_consume_input()
		if _death_respawn_rect.has_point(pointer):
			_respawn_from_death()
		elif _death_menu_rect.has_point(pointer):
			_quit_to_menu()


func _handle_modal_pointer(event: InputEvent) -> void:
	var pointer := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pointer = touch.position
		pressed = touch.pressed
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		pointer = mouse.position
		pressed = mouse.pressed
	else:
		return
	if not pressed:
		return
	if _map_open:
		if _map_close_rect.has_point(pointer):
			_close_map()
		elif _map_log_rect.has_point(pointer):
			_close_map()
			_get_player().get_node("OceanSalvage").open_journal()
		elif _map_cancel_course_rect.has_point(pointer):
			var vessel:=_get_raft()
			if vessel!=null:vessel.call("clear_course")
			_show_toast("COURSE CANCELLED");_compute_layout();queue_redraw()
		elif _map_course_rect.has_point(pointer):
			_start_selected_course()
		else:
			var nearest:=maxf(24.0,_map_plot_radius*.16)
			for marker in _map_markers:
				var marker_pos: Vector2 = marker.get("pos", Vector2.ZERO)
				var distance:=pointer.distance_to(marker_pos)
				if distance<=nearest:
					nearest=distance
					_selected_island = marker.get("node") as Node3D
					queue_redraw()
	_consume_input()


func _start_selected_course() -> void:
	var raft := _get_raft()
	if raft != null and raft.has_method("has_active_course") and bool(raft.call("has_active_course")):
		_begin_trip_skip();return
	if _selected_island == null or not is_instance_valid(_selected_island):
		_show_toast("SELECT A DESTINATION FIRST")
		return
	var player := _get_player()
	if player == null or not player.has_method("request_course_to"):
		_show_toast("NO RAFT AVAILABLE")
		return
	var nav_speed: float = float(raft.call("get_navigation_speed")) if raft != null and raft.has_method("get_navigation_speed") else 0.0
	if nav_speed <= 0.0:
		_show_toast("BUILD A ROWBOAT KIT OR INSTALL A SAIL")
		toggle_crafting()
		return
	if bool(player.call("request_course_to", _selected_island)):
		_close_map()


func _craft_item(item_name: String, quantity: int=1) -> void:
	if not Inventory.recipe_unlocked(item_name):
		_show_toast("COMPLETE YOUR MISSION TO UNLOCK " + item_name.to_upper())
		return
	if item_name in preload("res://scripts/equipment_repairs.gd").PORTABLE:
		if not Inventory.can_afford_item(item_name,quantity) or not Inventory.can_store_craft_result(item_name,quantity):_show_toast("NEED PARTS OR BAG SPACE FOR "+item_name.to_upper());return
		_close_crafting();_bag_open=false;GameSettings.release_gameplay_input()
		var actor:=_get_player()
		if actor!=null:actor.get_node("EquipmentRepairs").start("assemble_electronics",null,item_name,quantity)
		queue_redraw();return
	if Inventory.craft_item(item_name,quantity):
		_close_crafting()
		var player := _get_player()
		if player!=null:player.call("play_action","craft",0.7)
		_show_toast(str(ITEM_LABELS.get(item_name,item_name)).to_upper()+" ×%d BUILT · ADDED TO BAG"%quantity,4.0)
	else:
		_show_toast("NEED MATERIALS FOR " + item_name.to_upper())
	queue_redraw()

func _confirm_craft_selection(quantity: int=1) -> void:
	if Inventory.RECIPES.has(_craft_selected):
		if not Inventory.can_afford(_craft_selected):
			_show_toast("NEED MATERIALS OR MISSION UNLOCK")
			return
		_close_crafting()
		var actor:=_get_player()
		if actor!=null:actor.call("select_piece_for_build",actor.BUILD_RECIPE_NAMES.find(_craft_selected))
		_show_toast("AIM AT A CLEAR DECK · PLACE CONFIRMS AND SPENDS MATERIALS")
	else:_craft_item(_craft_selected,quantity)

func _use_bag_selection(eat: bool) -> void:
	if _inspect_slot<0 or Inventory.slot_empty(_inspect_slot):return
	var actor:=_get_player()
	if actor==null:return
	var item:=Inventory.slot_item(_inspect_slot)
	if eat and not _bag_can_use(item):return
	var equip_slot:=_bag_hold_slot()
	if equip_slot!=_inspect_slot and Inventory.slot_item(equip_slot)!=item:
		Inventory.swap_slots(_inspect_slot,equip_slot)
	actor.call("select_hotbar_slot",equip_slot)
	_bag_open=false;GameSettings.release_gameplay_input();_cancel_drag()
	if eat:actor.call("_handle_selected_item_use")
	queue_redraw()


func _bag_can_use(item: String) -> bool:
	return FOOD_RULES.edible(item) or item in ["Medkit","Can","Tumbler","Bandage","Solar Torch","Binoculars","Walkie Talkie","WindGenerator","ElectricLamp","Diving Tank","Life Vest"] or not preload("res://scripts/garden_items.gd").box_crop(item).is_empty() or not preload("res://scripts/garden_items.gd").seed_crop(item,true).is_empty()

func _bag_hold_slot() -> int:
	if _inspect_slot<HOTBAR_COUNT:return maxi(0,_inspect_slot)
	var item:=Inventory.slot_item(_inspect_slot)
	for index in HOTBAR_COUNT:
		if Inventory.slot_item(index)==item:return index
	for index in HOTBAR_COUNT:
		if Inventory.slot_empty(index):return index
	var actor:=_get_player()
	return clampi(int(actor.active_slot_index),0,HOTBAR_COUNT-1) if actor!=null else 0

func _activate_bag_primary() -> void:
	if _inspect_slot<0 or Inventory.slot_empty(_inspect_slot):return
	var item:=Inventory.slot_item(_inspect_slot)
	if _bag_can_use(item):_use_bag_selection(true)
	else:
		toggle_crafting()
		if is_instance_valid(_craft_menu):
			_craft_menu._search.text=item
			_craft_menu.call("_refresh_cards")

func _mission_recipe() -> String:
	var actor:=_get_player()
	var progress:=actor.get_node_or_null("SurvivalProgression") if actor!=null else null
	if progress==null:return ""
	var needs: Dictionary=progress.CHAPTERS[progress.level-1][2]
	for entry in needs:
		var event:=str(entry)
		if int(progress.events.get(event,0))>=int(needs[event]):continue
		if event.begins_with("craft:") or event.begins_with("build:"):
			return event.get_slice(":",1)
		return ""
	return ""

func _open_mission_recipe() -> void:
	var item:=_mission_recipe()
	if item.is_empty():return
	toggle_crafting()
	if is_instance_valid(_craft_menu):_craft_menu.call("select_item",item)

func _handle_pause_mouse(pointer: Vector2) -> void:
	# Scene changes detach this HUD immediately: claim the event first.
	_consume_input()
	if _pause_resume_rect.has_point(pointer):
		_set_paused(false)
	elif _pause_settings_rect.has_point(pointer):
		GameSettings.open()
	elif _pause_quit_rect.has_point(pointer):
		_quit_to_menu()


func _handle_bar_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _trip_skip_rect.has_point(touch.position):_begin_trip_skip();_consume_input();return
			if not _trip_card_rect.has_area() and _mission_rect.has_point(touch.position) and not _mission_recipe().is_empty():
				_open_mission_recipe();_consume_input();return
			if _rope_slot_rect.has_point(touch.position) and not _in_build_mode():
				var player := _get_player()
				if player != null: player.call("equip_rope_gun")
				queue_redraw()
				_consume_input()
				return
			if _bag_rect.has_point(touch.position) and not _in_build_mode():
				_cancel_drag()
				_press_bag = true
				_bag_open = true
				if _inspect_slot<0 or Inventory.slot_empty(_inspect_slot):
					var actor:=_get_player()
					_inspect_slot=int(actor.active_slot_index) if actor!=null else -1
				GameSettings.release_gameplay_input()
				_compute_layout()
				queue_redraw()
				_consume_input()
				return
			if _hud_craft_rect.has_point(touch.position) and not _in_build_mode():
				toggle_crafting()
				_consume_input()
				return
			if _hud_map_rect.has_point(touch.position) and not _in_build_mode():
				toggle_map()
				_consume_input()
				return
			for i in range(_hotbar_rects.size()):
				if (_hotbar_rects[i] as Rect2).has_point(touch.position):
					_pressed_visual = i
					_tap_bar_slot(i)
					queue_redraw()
					_consume_input()
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
			if _inventory_touch_id != -1:
				_consume_input()
				return
			if _bag_use_rect.has_point(touch.position):_activate_bag_primary();_consume_input();return
			if _bag_equip_rect.has_point(touch.position):_use_bag_selection(false);_consume_input();return
			if _close_rect.has_point(touch.position) or not _panel_rect.has_point(touch.position):
				_bag_open = false
				_cancel_drag()
				queue_redraw()
				_consume_input()
				return
			if _save_rect.has_point(touch.position):
				_do_quick_save()
				_consume_input()
				return
			_press_pos = touch.position
			_inventory_touch_id = touch.index
			var idx := _idx_at(touch.position)
			if idx >= 0 and not Inventory.slot_empty(idx):
				_press_slot = idx
				_pressed_visual = idx
			else:
				_press_slot = -1
			queue_redraw()
			_consume_input()
			return
		# released
		if touch.index != _inventory_touch_id:
			return
		if touch.canceled:
			_cancel_drag()
			queue_redraw()
			return
		_inventory_touch_id = -1
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
				_inspect_slot=_press_slot
				# plain tap (no drag): hotbar-row tap selects the item
				if _press_slot < HOTBAR_COUNT:
					var p := _get_player()
					if p != null and p.has_method("select_hotbar_slot"):
						p.call("select_hotbar_slot", _press_slot)
				_cancel_drag()
			queue_redraw()
			_consume_input()
			return
		# tap on background: close unless it started on the panel chrome
		if _close_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		elif not _panel_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		_consume_input()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _inventory_touch_id:
			return
		if _press_slot >= 0:
			if not _dragging and _press_pos.distance_to(drag.position) > 14.0:
				_dragging = true
				_drag_from = _press_slot
			if _dragging:
				_drag_pos = drag.position
			queue_redraw()
			_consume_input()


func _handle_pause_input(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_handle_pause_mouse(t.position)


func _set_paused(p: bool) -> void:
	if _paused == p:
		return
	_paused = p
	if p:
		GameSettings.release_gameplay_input()
		_cancel_drag()
		_bag_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = p
	visible = _should_show()
	_compute_layout()
	queue_redraw()


func _quit_to_menu() -> void:
	var p := _get_player()
	if p != null and p.has_method("_flush_save"):
		p.call("_flush_save")
	_set_paused(false)
	_map_open = false
	_craft_open = false
	_death_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh_selection_after_move() -> void:
	var p := _get_player()
	if p != null and p.has_method("_refresh_active_item"):
		p.call("_refresh_active_item")


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _get_raft() -> Node3D:
	var actor:=_get_player()
	if actor!=null and actor.has_method("navigation_vehicle"):return actor.call("navigation_vehicle") as Node3D
	return get_tree().get_first_node_in_group("raft") as Node3D


# ============================================================
# DRAW
# ============================================================
func _draw() -> void:
	if not visible or _vp.x <= 0.0:
		return
	if _craft_open and is_instance_valid(_craft_menu):return
	if _feedback_only():
		if not _toast.is_empty() and _toast_rect.has_area():_draw_toast()
		_draw_trip_card()
		return
	_draw_status()
	_draw_clock()
	_draw_pause_btn()
	_draw_pills()
	_draw_chip()
	_draw_mission()
	_draw_trip_card()
	if _bag_open:
		_draw_bag_panel()
	else:
		_draw_bottom_bar()
	if _bag_open and not _map_open and not _craft_open:
		_draw_map_button()
		_draw_craft_button()
	if _toast != "" and _toast_rect.size.x > 0.0 and not gameplay_input_blocked():
		_draw_toast()
	if not _pickup_active.is_empty() and not gameplay_input_blocked():_draw_pickup()
	if _dragging and _drag_from >= 0:
		_draw_drag_ghost()
	if _paused:
		_draw_pause_overlay()
	if _map_open:
		_draw_map_overlay()
	if _death_open:
		_draw_death_overlay()


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


func _draw_map_button() -> void:
	var rect := _map_button_rect
	_draw_ocean_tab(rect, Color(0.10, 0.25, 0.27))
	Icons.sea_chart(self, Vector2(rect.position.x + rect.size.y * 0.76, rect.get_center().y), rect.size.y * 0.36)
	_draw_tab_caption(rect, "MAP", "ISLAND CHART")


func _draw_craft_button() -> void:
	var rect := _craft_button_rect
	_draw_ocean_tab(rect, Color(0.20, 0.19, 0.12))
	Icons.salvage_tools(self, Vector2(rect.position.x + rect.size.y * 0.76, rect.get_center().y), rect.size.y * 0.34)
	_draw_tab_caption(rect, "CRAFT", "SURVIVAL GEAR")


func _draw_ocean_tab(rect: Rect2, base: Color) -> void:
	var radius := rect.size.y * 0.14
	_draw_rounded(Rect2(rect.position + Vector2(0, 2), rect.size), radius, Color(0, 0, 0, 0.65))
	_draw_rounded(rect, radius, base.darkened(0.35))
	_draw_rounded(rect.grow(-2.0), radius, base)
	# Weathered wood grain and a restrained wave etching inside a brass rim.
	for grain_index in range(4):
		var y := rect.position.y + rect.size.y * (0.19 + float(grain_index) * 0.20)
		draw_line(Vector2(rect.position.x + 7.0, y), Vector2(rect.end.x - 7.0, y + 1.0), Color(0.85, 0.84, 0.63, 0.06), 1.0, true)
	var wave := PackedVector2Array()
	for wave_index in range(25):
		var t := float(wave_index) / 24.0
		wave.append(Vector2(lerpf(rect.position.x + 8.0, rect.end.x - 8.0, t), rect.end.y - 5.0 + sin(t * TAU * 3.0) * 1.0))
	draw_polyline(wave, Color(0.51, 0.76, 0.69, 0.24), 1.0, true)
	_draw_rounded(rect.grow(-1.0), radius, Color(0.71, 0.63, 0.42, 0.88), false, 1.0)
	for rivet_x in [rect.position.x + 5.0, rect.end.x - 5.0]:
		draw_circle(Vector2(rivet_x, rect.get_center().y), 1.6, Color(0.78, 0.70, 0.49))


func _draw_tab_caption(rect: Rect2, title: String, subtitle: String) -> void:
	var fs := int(clampf(rect.size.y * 0.34, 12.0, 16.0))
	var x := rect.position.x + rect.size.y * 1.45
	_draw_text(title, Vector2(x, rect.position.y + rect.size.y * 0.49), fs, Color(0.98, 0.91, 0.72))
	_draw_text(subtitle, Vector2(x, rect.position.y + rect.size.y * 0.76), int(clampf(rect.size.y * 0.19, 7.0, 9.0)), Color(0.70, 0.80, 0.74))


func map_player_arrow() -> PackedVector2Array:
	var actor:=_get_player()
	var raft:=_get_raft()
	var centre:=_map_center
	var heading:=0.0
	if actor!=null:
		var forward:Vector3=-actor.global_basis.z
		heading=atan2(forward.x,-forward.z)
		if raft!=null:centre+=Vector2(actor.global_position.x-raft.global_position.x,actor.global_position.z-raft.global_position.z)/maxf(_map_range,1)*_map_plot_radius
	var points:=PackedVector2Array()
	for point in [Vector2(0,-12),Vector2(8,9),Vector2(0,4),Vector2(-8,9)]:points.append(centre+point.rotated(heading))
	return points

func _draw_map_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.01, 0.035, 0.055, 0.86))
	var panel := _map_panel_rect
	_draw_rounded(panel, 24.0, Color(0.045, 0.1, 0.13, 0.99))
	_draw_rounded(panel, 24.0, Color(0.56, 0.82, 0.79, 0.48), false, 2.0)
	var title_fs: int = int(clampf(panel.size.y * 0.055, 22.0, 34.0))
	var sub_fs: int = int(clampf(title_fs * 0.43, 12.0, 16.0))
	_draw_text("THE FLOODED WORLD", Vector2(panel.position.x + panel.size.x * 0.07,
			panel.position.y + panel.size.y * 0.075 + title_fs * 0.36), title_fs, Color(0.9, 0.95, 0.85, 0.98))
	var salvage:=_get_player().get_node_or_null("OceanSalvage") if _get_player()!=null else null
	var chart_caption:=str(salvage.journal_caption()) if salvage!=null else "95% SUBMERGED · RARE ISLANDS & YOUR FLOATING CAMP"
	_draw_text(chart_caption, Vector2(panel.position.x + panel.size.x * 0.07,
			panel.position.y + panel.size.y * 0.12 + sub_fs * 0.6), sub_fs,
			Color(0.65, 0.81, 0.81, 0.9))
	_draw_pause_button(_map_log_rect,"LOG",false)
	var close_center := _map_close_rect.get_center()
	draw_circle(close_center, _map_close_rect.size.x * 0.5, Color(1, 1, 1, 0.08))
	Icons.cross(self, close_center, _map_close_rect.size.x * 0.36, 2.5, Color(1, 1, 1, 0.9))

	_draw_rounded(_map_area_rect, 18.0, Color(0.025, 0.14, 0.19, 0.96))
	_draw_rounded(_map_area_rect, 18.0, Color(0.35, 0.72, 0.72, 0.25), false, 1.0)
	for ring in range(1, 5):
		var radius := _map_plot_radius * float(ring) / 4.0
		draw_arc(_map_center, radius, 0.0, TAU, 56, Color(0.55, 0.82, 0.78, 0.20), 1.0, true)
		if ring < 4:
			var range_label := str(int(roundf(_map_range * float(ring) / 4.0))) + " m"
			_draw_text(range_label, _map_center + Vector2(-_map_plot_radius * float(ring) / 4.0 - 3.0, -4.0),
					int(clampf(sub_fs * 0.82, 10.0, 13.0)), Color(0.65, 0.84, 0.83, 0.55))
	draw_line(_map_center - Vector2(_map_plot_radius, 0), _map_center + Vector2(_map_plot_radius, 0),
			Color(0.55, 0.82, 0.78, 0.13), 1.0, true)
	draw_line(_map_center - Vector2(0, _map_plot_radius), _map_center + Vector2(0, _map_plot_radius),
			Color(0.55, 0.82, 0.78, 0.13), 1.0, true)
	_draw_text("N", _map_center + Vector2(-4.0, -_map_plot_radius - 6.0),
			int(clampf(sub_fs, 11.0, 16.0)), Color(0.85, 0.94, 0.88, 0.85))

	var selected_pos := Vector2.ZERO
	var label_boxes:Array[Rect2]=[]
	for marker in _map_markers:
		var island := marker.get("node") as Node3D
		if island == null or not is_instance_valid(island):
			continue
		var marker_pos: Vector2 = marker.get("pos", _map_center)
		if island == _selected_island:
			selected_pos = marker_pos
	var raft := _get_raft()
	if _selected_island != null and is_instance_valid(_selected_island) and raft != null:
		var course_from := _map_center
		var course_to := selected_pos
		var route := PackedVector2Array([course_from, course_to])
		draw_polyline(route, Color(1.0, 0.85, 0.45, 0.72), 2.5, true)
		for dot in range(1, 6):
			var point := course_from.lerp(course_to, float(dot) / 6.0)
			draw_circle(point, 2.2, Color(1.0, 0.91, 0.62, 0.9))

	for marker in _map_markers:
		var island := marker.get("node") as Node3D
		if island == null or not is_instance_valid(island):
			continue
		var pos: Vector2 = marker.get("pos", _map_center)
		var label: String = str(marker.get("label", island.name))
		var dist: float = float(marker.get("distance", 0.0))
		var chosen := island == _selected_island
		var r: float = 10.0 if chosen else 8.0
		var sea_ring := Color(1.0, 0.81, 0.43, 0.9) if chosen else Color(0.72, 0.86, 0.64, 0.75)
		draw_circle(pos, r + 4.0, Color(sea_ring.r, sea_ring.g, sea_ring.b, 0.15))
		draw_arc(pos, r + 2.0, 0.0, TAU, 28, sea_ring, 1.8, true)
		var island_shape := PackedVector2Array([
			pos + Vector2(-r, 1.0), pos + Vector2(-r * 0.45, -r * 0.75),
			pos + Vector2(r * 0.65, -r * 0.55), pos + Vector2(r, r * 0.12),
			pos + Vector2(r * 0.35, r * 0.8), pos + Vector2(-r * 0.55, r * 0.65),
		])
		var biome := str(island.get_meta("biome","tropical"))
		var tint:Color={"volcano":Color(.86,.40,.20),"winter":Color(.81,.92,1),"spring":Color(.61,.84,.40),"underwater":Color(.22,.68,.88),"cargo":Color(.95,.65,.24)}.get(biome,Color(.52,.68,.46,.95))
		if island.is_in_group("drift_cache"):
			var crate_rect:=Rect2(pos-Vector2.ONE*r,Vector2.ONE*r*2)
			draw_rect(crate_rect,tint)
			draw_line(pos-Vector2(r,r),pos+Vector2(r,r),Color(.2,.23,.19),2,true)
			draw_line(pos+Vector2(-r,r),pos+Vector2(r,-r),Color(.2,.23,.19),2,true)
		else:draw_colored_polygon(island_shape,tint.lightened(.18) if chosen else tint)
		var label_fs: int = int(clampf(sub_fs * 0.95, 11.0, 15.0))
		var label_text := "%s  %dm" % [label, int(roundf(dist))]
		var label_w: float = ThemeDB.fallback_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x
		var label_x := clampf(pos.x - label_w * 0.5, _map_area_rect.position.x + 5.0,
				_map_area_rect.end.x - label_w - 5.0)
		var label_y := pos.y + r + label_fs * 1.3
		if label_y > _map_area_rect.end.y - label_fs:
			label_y = pos.y - r - label_fs * 0.55
		var box:=Rect2(label_x,label_y-label_fs,label_w,label_fs+4)
		for attempt in 12:
			var overlaps:=false
			for previous in label_boxes:overlaps=overlaps or previous.grow(3).intersects(box)
			if not overlaps:break
			label_y=pos.y+(1 if attempt%2==0 else -1)*(label_fs+5)*(floori(float(attempt)/2)+2)
			label_y=clampf(label_y,_map_area_rect.position.y+label_fs+5,_map_area_rect.end.y-6)
			box.position.y=label_y-label_fs
		label_boxes.append(box)
		if absf(label_y-pos.y)>38:draw_line(pos+Vector2(0,r),Vector2(clampf(pos.x,label_x,label_x+label_w),label_y-label_fs),Color(.4,.63,.65,.5),1,true)
		_draw_text(label_text, Vector2(label_x, label_y), label_fs, Color(0.93, 0.96, 0.86, 0.95))

	# Current raft marker stays at chart center as the world origin.
	draw_circle(_map_center, 12.0, Color(0.26, 0.86, 0.95, 0.2))
	draw_arc(_map_center, 10.0, 0.0, TAU, 28, Color(0.45, 0.92, 1.0, 0.96), 2.0, true)
	var player_arrow := map_player_arrow()
	draw_colored_polygon(player_arrow, Color(0.45, 0.92, 1.0, 0.96))

	var detail_fs: int = int(clampf(sub_fs * 1.05, 12.0, 16.0))
	var detail := "Your arrow shows where you face. Select a destination."
	if _selected_island != null and is_instance_valid(_selected_island):
		var selected_name: String = str(_selected_island.get_meta("map_label", _selected_island.name))
		var distance_m: float = _get_raft().global_position.distance_to(_selected_island.global_position) if _get_raft() != null else 0.0
		var speed: float = float(raft.call("get_navigation_speed")) if raft != null and raft.has_method("get_navigation_speed") else 0.0
		var eta: String = "" if speed <= 0.0 else "   •   ETA %d:%02d" % [int(distance_m / speed / 60.0), int(int(distance_m / speed) % 60)]
		detail = "%s  •  %dm%s" % [selected_name, int(roundf(distance_m)), eta]
	_draw_text(detail, Vector2(_map_area_rect.position.x + 8.0,
			_map_course_rect.position.y - detail_fs * 0.45), detail_fs, Color(0.88, 0.92, 0.82, 0.94))
	var button_label := "SELECT A DESTINATION"
	var button_enabled := false
	if raft != null and raft.has_method("has_active_course") and bool(raft.call("has_active_course")):
		button_enabled=raft.has_method("can_skip_course") and bool(raft.call("can_skip_course"))
		button_label="SKIP TRIP" if button_enabled else "APPROACHING"
	elif _selected_island != null and is_instance_valid(_selected_island):
		var nav_speed: float = float(raft.call("get_navigation_speed")) if raft != null and raft.has_method("get_navigation_speed") else 0.0
		button_label = "SET COURSE TO " + str(_selected_island.get_meta("map_label", _selected_island.name)).to_upper() if nav_speed > 0.0 else "BUILD ROWBOAT OR SAIL KIT"
		button_enabled = true
	var btn_bg := Color(0.13, 0.35, 0.27, 0.97) if button_enabled else Color(0.12, 0.16, 0.18, 0.95)
	_draw_rounded(_map_course_rect, _map_course_rect.size.y * 0.42, btn_bg)
	_draw_rounded(_map_course_rect, _map_course_rect.size.y * 0.42,
			Color(0.75, 0.91, 0.62, 0.7) if button_enabled else Color(1, 1, 1, 0.16), false, 1.5)
	var btn_fs: int = int(clampf(_map_course_rect.size.y * 0.28, 13.0, 19.0))
	var btn_w: float = ThemeDB.fallback_font.get_string_size(button_label, HORIZONTAL_ALIGNMENT_LEFT, -1, btn_fs).x
	var shown_label := button_label
	if btn_w > _map_course_rect.size.x * 0.92:
		shown_label = "SKIP TRAVEL" if button_label.begins_with("SKIP") else ("BUILD ROWBOAT" if button_label.begins_with("BUILD") else "SET COURSE")
		btn_w = ThemeDB.fallback_font.get_string_size(shown_label, HORIZONTAL_ALIGNMENT_LEFT, -1, btn_fs).x
	_draw_text(shown_label, Vector2(_map_course_rect.get_center().x - btn_w * 0.5,
			_map_course_rect.get_center().y + btn_fs * 0.34), btn_fs,
			Color(0.95, 0.99, 0.88, 0.98) if button_enabled else Color(0.74, 0.81, 0.79, 0.8))
	if _map_cancel_course_rect.has_area():_draw_pause_button(_map_cancel_course_rect,"CANCEL",false)

func _draw_trip_card() -> void:
	if not _trip_card_rect.has_area() or gameplay_input_blocked():return
	var vessel:=_get_raft()
	if vessel==null:return
	var rect:=_trip_card_rect
	_draw_rounded(rect,10,Color(.03,.12,.15,.94))
	var destination:=str(vessel.get_meta("course_label","Destination"))
	_draw_paragraph("SAILING · "+destination,Rect2(rect.position+Vector2(12,7),Vector2(rect.size.x-24,20)),14,Color(.77,.95,.94),1)
	_draw_text("%d m to destination"%roundi(float(vessel.call("get_course_distance"))),rect.position+Vector2(12,43),13,Color(.72,.85,.88))
	if _trip_skip_rect.has_area():_draw_pause_button(_trip_skip_rect,"SKIP TRIP",true)
	else:_draw_text("Approaching · Keep sailing",rect.position+Vector2(12,83),13,Color(.66,.89,.74))


func _draw_mission() -> void:
	if gameplay_input_blocked() or _trip_card_rect.has_area() or _vp.x < 500:
		return
	var player := _get_player()
	if player == null:
		return
	var progress := player.get_node_or_null("SurvivalProgression")
	if bool(player.get("build_mode")) or is_instance_valid(player.get("_editing")):return
	if progress == null:
		return
	var show_air:bool=progress.oxygen<99 or progress.stamina<80 or progress.diving_tank
	var show_wet:bool=progress.wetness>=5
	var rect := _mission_rect
	if not rect.has_area():return
	if show_air:rect.size.y+=24
	if show_wet:rect.size.y+=22
	var width:=rect.size.x
	_draw_rounded(rect, 9, Color(0.03,0.10,0.115,0.80))
	_draw_text("%s" % progress.CHAPTERS[progress.level-1][0], rect.position+Vector2(12,20),14,Color(0.86,0.77,0.57))
	var font := ThemeDB.fallback_font
	var objective := str(progress.call("objective"))
	var fs := 13
	while font.get_string_size(objective,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > width-24 and fs > 9:
		fs -= 1
	_draw_text(objective,rect.position+Vector2(12,43),fs,Color(0.82,0.90,0.85))
	var needs: Dictionary=progress.CHAPTERS[progress.level-1][2]
	var done:=0
	var total:=0
	for event in needs:
		total+=int(needs[event]);done+=mini(int(needs[event]),int(progress.events.get(event,0)))
	var track:=Rect2(rect.position+Vector2(12,53),Vector2(width-24,4))
	_draw_rounded(track,2,Color(1,1,1,.12))
	if total>0 and done>0:_draw_rounded(Rect2(track.position,Vector2(track.size.x*float(done)/float(total),4)),2,UI_SURFACE.EMERALD)
	var follow:="TAP TO SEE RECIPE" if not _mission_recipe().is_empty() else "KEEP EXPLORING" if total==0 else "USE YOUR CAMP TO CONTINUE"
	var salvage:=player.get_node_or_null("OceanSalvage")
	if total==0 and salvage!=null:follow=salvage.journal_caption()
	_draw_text("%d/%d  ·  %s"%[done,total,follow] if total>0 else follow,rect.position+Vector2(12,80),11,Color(.65,.83,.84))
	if show_air:
		var air := " · AIR %d:%02d" % [floori(progress.air_tank_seconds/60.0),int(progress.air_tank_seconds)%60] if progress.diving_tank else ""
		var warning:bool=progress.oxygen<=25 or (progress.diving_tank and progress.air_tank_seconds<=30)
		var tint:=Color(1,.46,.27,.45 if floori(float(Time.get_ticks_msec())/400.0)%2 else 1.0) if warning else Color(.78,.89,.92)
		_draw_text("OXYGEN %d%% · STAMINA %d%%%s" % [int(progress.oxygen),int(progress.stamina),air],rect.position+Vector2(12,106),12,tint)
	if show_wet:
		_draw_text("WET %d%% · Shelter to dry off"%roundi(progress.wetness),rect.position+Vector2(12,130 if show_air else 106),12,Color(.60,.81,.91))

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
	_draw_pause_button(_pause_settings_rect, "SETTINGS", true)
	_draw_pause_button(_pause_quit_rect, "QUIT TO MENU", false)


func _draw_death_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.035, 0.012, 0.015, 0.82))
	var rect := _death_panel_rect
	if rect.size.x <= 0.0:
		return
	_draw_rounded(rect, 24.0, Color(0.09, 0.055, 0.055, 0.99))
	_draw_rounded(rect, 24.0, Color(0.96, 0.4, 0.3, 0.52), false, 2.0)
	var title := "LOST AT SEA"
	var title_fs: int = int(clampf(rect.size.y * 0.12, 28.0, 42.0))
	var title_w: float = ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs).x
	_draw_text(title, Vector2(rect.get_center().x - title_w * 0.5,
			rect.position.y + rect.size.y * 0.24 + title_fs * 0.36), title_fs, Color(1.0, 0.72, 0.62, 0.98))
	var subtitle := "Items kept. Your boat and cargo are safe."
	var sub_fs: int = int(clampf(rect.size.y * 0.052, 14.0, 18.0))
	var sub_w: float = ThemeDB.fallback_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	_draw_text(subtitle, Vector2(rect.get_center().x - sub_w * 0.5,
			rect.position.y + rect.size.y * 0.39 + sub_fs * 0.36), sub_fs, Color(0.83, 0.78, 0.74, 0.9))
	_draw_pause_button(_death_respawn_rect, "RESPAWN ON RAFT", true)
	_draw_pause_button(_death_menu_rect, "QUIT TO MENU", false)


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


func _draw_pickup() -> void:
	var scale_factor:=clampf(_vp.y/720.0,0.72,1.35)
	var rect:=Rect2(Vector2(maxf(12,_vp.y*.022),minf(_vp.y*.36,260.0)),Vector2(270,62)*scale_factor)
	var fade:=clampf(minf(_pickup_remaining/0.2,(1.6-_pickup_remaining)/0.12),0.0,1.0)
	_draw_rounded(rect,12.0*scale_factor,Color(0.025,0.065,0.075,0.92*fade))
	_draw_rounded(rect,12.0*scale_factor,Color(0.45,0.8,0.63,fade),false,1.5)
	var item:=str(_pickup_active.item)
	Icons.item_icon(self,item,rect.position+Vector2(30,30)*scale_factor,22.0*scale_factor)
	_draw_text(item.to_upper(),rect.position+Vector2(62,25)*scale_factor,int(15*scale_factor),Color(1,1,1,fade))
	_draw_text("COLLECTED  +%d"%int(_pickup_active.amount),rect.position+Vector2(62,47)*scale_factor,int(13*scale_factor),Color(0.6,0.95,0.72,fade))

func _draw_toast() -> void:
	_draw_rounded(_toast_rect,12,Color(.025,.11,.16,.96))
	_draw_rounded(_toast_rect,12,Color(.38,.78,.78,.65),false,1.0)
	for index in _toast_lines.size():
		_draw_text(_toast_lines[index],_toast_rect.position+Vector2(16,10+_toast_font_size+index*(_toast_font_size+6)),_toast_font_size,Color(.94,.98,1))


## Bottom bar: NORMAL = inventory slots 0..5 + BAG; BUILD = piece slots.
func _draw_bottom_bar() -> void:
	var building: bool = _in_build_mode()
	var p := _get_player()
	var sel_piece: int = int(p.get("selected_piece_index")) if p != null else -1
	var act_slot: int = int(p.get("active_slot_index")) if p != null else 0

	# Floating frosted-glass dock panel behind the bottom bar
	if _hotbar_rects.size() > 0:
		var dock_min_x: float = (_hotbar_rects[0] as Rect2).position.x
		var dock_max_x: float = _bag_rect.end.x if not building else (_hotbar_rects[-1] as Rect2).end.x
		var dock_h := _slot + 14.0
		var dock_rect := Rect2(dock_min_x - 8.0, (_hotbar_rects[0] as Rect2).position.y - 7.0, (dock_max_x - dock_min_x) + 16.0, dock_h)
		_draw_rounded(dock_rect, 14.0, UI_SURFACE.SLATE_DEEP)
		_draw_rounded(dock_rect, 14.0, Color(0.35, 0.50, 0.60, 0.28), false, 1.2)

	if not building:
		var gun_selected: bool = p != null and p.get("rope_gun_selected") == true
		_draw_hud_shortcut(_rope_slot_rect,"ROPE",Color(.78,.90,.92),gun_selected)
	for i in range(_hotbar_rects.size()):
		var rect: Rect2 = _hotbar_rects[i]
		if building:
			var piece_sel: bool = i == sel_piece
			_draw_slot(rect, _pressed_visual == i, piece_sel)
			Icons.piece(self, PIECE_ORDER[i], rect.get_center(), _slot * 0.3,
				Color(0.88, 0.72, 0.42, 0.95) if piece_sel else Color(0.75, 0.6, 0.34, 0.85))
		else:
			var item_sel: bool = i == act_slot and not Inventory.slot_empty(i) and not (p != null and p.get("rope_gun_selected"))
			_draw_slot(rect, _pressed_visual == i, item_sel)
			_draw_item_slot(rect, i, item_sel)
	if not building:
		if _bag_rect.size.x > 0.0:
			_draw_slot(_bag_rect, _press_bag, false)
			Icons.backpack(self, _bag_rect.get_center() - Vector2(0, _slot * 0.08), _slot * 0.38, Color.WHITE)
			var font := ThemeDB.fallback_font
			var fs := int(clampf(_slot * 0.17, 9.0, 13.0))
			var label := "BAG"
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, _bag_rect.get_center() + Vector2(-tw * 0.5, _slot * 0.38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.88, 0.75))
		_draw_hud_shortcut(_hud_craft_rect,"CRAFT",Color(.95,.85,.55))
		_draw_hud_shortcut(_hud_map_rect,"MAP",Color(.65,.90,.98))
		_draw_held_card()

func _draw_held_card() -> void:
	if gameplay_input_blocked() or _editing() or not _held_card_rect.has_area():return
	var actor:=_get_player()
	if actor==null:return
	var item:=str(actor.active_item)
	if item.is_empty() and _focus_label.is_empty():return
	var rect:=_held_card_rect
	_draw_rounded(rect,10,UI_SURFACE.SLATE_DEEP)
	var title:="Empty hands" if item.is_empty() else ITEM_GUIDE.label("Rope Gun" if actor.rope_gun_selected else item)
	_draw_text(title,rect.position+Vector2(12,20),16,Color(.97,.91,.74))
	_draw_paragraph(ITEM_GUIDE.quick_action(item),Rect2(rect.position+Vector2(12,26),rect.size-Vector2(24,28)),12,Color(.8,.91,.94),2)
	if not _focus_label.is_empty():
		var focus_rect:=Rect2(rect.position-Vector2(0,35),Vector2(rect.size.x,28))
		_draw_rounded(focus_rect,8,Color(.05,.18,.18,.94))
		_draw_paragraph("AIMING AT · "+_focus_label,focus_rect.grow(-6),12,Color(.72,.98,.87),1)

func _aimed_item_label() -> String:
	var actor:=_get_player()
	if actor==null or not actor.aim_valid or not is_instance_valid(actor.aim_collider) or actor.aim_distance>actor.PICKUP_RANGE:return ""
	var target: Node=actor.aim_collider
	for unused in 6:
		if target==null:break
		if "item_name" in target:return ITEM_GUIDE.label(str(target.get("item_name")))
		if "machine_type" in target:return ITEM_GUIDE.label(str(target.get("machine_type")))
		if target.is_in_group("animal_carcass"):return str(target.get("species")).capitalize()+" · Whole animal"
		if target.is_in_group("storage_box"):return "Loot Bag" if bool(target.get("loot_bag")) else "Storage Box"
		if target.is_in_group("drift_cache"):return str(target.get_meta("map_label","Drift Cargo"))
		if target.is_in_group("boat_workshop"):return "Boat Workshop"
		if target.is_in_group("interactable_boat"):return "Rowboat"
		if target.is_in_group("campfire"):return "Cooking Fire"
		if target is PlantInstance:return str(target._def.get("name",target.plant_id)).capitalize()
		if target is Planter:return ["Plant Pot","Plant Bed","Tree Pot"][target.planter_category]
		target=target.get_parent()
	return ""

func _draw_hud_shortcut(rect: Rect2,label: String,tint: Color,selected: bool=false) -> void:
	if not rect.has_area():return
	_draw_slot(rect,false,selected)
	var side := rect.size.x
	var icon_at := rect.get_center() - Vector2(0,side * .08)
	match label:
		"ROPE":Icons.item_icon(self,"Rope Gun",icon_at,side * .36)
		"CRAFT":Icons.salvage_tools(self,icon_at,side * .34)
		"MAP":Icons.sea_chart(self,icon_at,side * .34)
	var font := ThemeDB.fallback_font
	var fs := int(clampf(side * .17,10.0,14.0))
	var tw := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	draw_string(font,rect.get_center() + Vector2(-tw * .5,side * .38),label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,tint)


func _draw_item_slot(rect: Rect2, idx: int, selected: bool) -> void:
	# Subtle slot number in top-left
	var font := ThemeDB.fallback_font
	var num_fs := int(clampf(_slot * 0.18, 9.0, 12.0))
	draw_string(font, rect.position + Vector2(5.0, num_fs + 2.0), str(idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, num_fs, Color(1, 1, 1, 0.30))

	if Inventory.slot_empty(idx):
		return
	var item: String = Inventory.slot_item(idx)
	var count: int = Inventory.slot_count(idx)
	var glyph: Color = Color(1, 1, 1, 0.98) if selected else Color(0.95, 0.95, 0.95, 0.9)
	Icons.item_icon(self, Icons.ITEM_ART.slot_icon(item, idx), rect.get_center() - Vector2(0, _slot * 0.10), _slot * 0.31)
	if count > 1:
		var fs: int = int(clampf(_slot * 0.22, 11.0, 18.0))
		var label := str(count)
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Clean rounded badge behind stack count
		var badge_rect := Rect2(rect.end.x - tw - 7.0, rect.position.y+2, tw + 6.0, fs + 3.0)
		_draw_rounded(badge_rect, 3.0, Color(0.02, 0.03, 0.04, 0.85))
		_draw_text(label, Vector2(badge_rect.position.x + 3.0, badge_rect.position.y + fs * 0.92), fs, glyph)
	else:
		var fs: int = int(clampf(_slot * 0.2, 10.0, 16.0))
		var label := str(count)
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(rect.end.x - tw - rect.size.x * 0.06,rect.position.y+fs+2), fs, Color(1, 1, 1, 0.6))
	_draw_paragraph(ITEM_GUIDE.label(item),Rect2(rect.position+Vector2(3,rect.size.y*.66),Vector2(rect.size.x-6,rect.size.y*.34)),int(clampf(_slot*.16,8,11)),Color(.91,.94,.92),2)


func _draw_status() -> void:
	var cr: float = _clock_r
	var phase: float = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.005))
	for i in STATS.size():
		if i >= _status_centers.size(): break
		var center: Vector2 = _status_centers[i]
		var value: float = clampf(_get_stat(STATS[i][0]), 0.0, 100.0)
		var low := value <= 25.0
		var tint: Color = _status_bg(STATS[i][0])
		if low:
			tint = Color(0.95, 0.25, 0.18, 0.75 + 0.25 * phase)
			# Pulsing warning halo when stat is critically low
			draw_circle(center, cr * 1.25, Color(1.0, 0.20, 0.15, 0.18 * phase))

		# Frosted glass circular monitor
		UI_SURFACE.dial(self, center, cr, tint if low else UI_SURFACE.BRASS)
		# Arc track background
		draw_arc(center, cr - 3.0, 0.0, TAU, 36, Color(0.10, 0.14, 0.18, 0.60), 3.5, true)
		# Glowing filled progress arc
		var arc_angle := -PI * 0.5 + TAU * (float(_display_stats[i]) / 100.0)
		draw_arc(center, cr - 3.0, -PI * 0.5, arc_angle, 44, tint, 3.5, true)
		Icons.status_icon(self, STATS[i][0], center - Vector2(0, 1.0), cr * 0.46, Color(1, 1, 1, 0.95))

		var label := "%d%%" % roundi(value)
		var font := ThemeDB.fallback_font
		var text_pos := Vector2(center.x - cr * 1.3, center.y + cr + 16.0)
		var text_col: Color = Color(1.0, 0.35, 0.25, 0.95) if low else Color.WHITE
		# Drop shadow for readability
		draw_string(font, text_pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_CENTER, cr * 2.6, 17, Color(0, 0, 0, 0.8))
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, cr * 2.6, 17, text_col)

		var sub_label: String = ("CRITICAL " if low else "") + STATS[i][1]
		var sub_pos := Vector2(center.x - cr * 1.3, center.y + cr + 31.0)
		var sub_col: Color = tint if low else Color(0.78, 0.84, 0.82)
		draw_string(font, sub_pos + Vector2(1, 1), sub_label, HORIZONTAL_ALIGNMENT_CENTER, cr * 2.6, 11, Color(0, 0, 0, 0.7))
		draw_string(font, sub_pos, sub_label, HORIZONTAL_ALIGNMENT_CENTER, cr * 2.6, 11, sub_col)


## Current in-game hour (float, Sky3D.current_time). Falls back to noon while
## the sky node is unavailable.
func _time_now() -> float:
	if _sky == null or not is_instance_valid(_sky):
		var sc: Node = get_tree().current_scene
		if sc != null:
			_sky = sc.get_node_or_null("Sky3D")
	if _sky != null and is_instance_valid(_sky) and _sky.get("current_time") != null:
		return float(_sky.get("current_time"))
	return 12.0


func _day_now() -> int:
	var player := _get_player()
	if player != null and player.has_method("get_survival_day"):
		return maxi(1, int(player.call("get_survival_day")))
	var sky := _sky if _sky != null and is_instance_valid(_sky) else null
	if sky == null:
		var scene := get_tree().current_scene
		if scene != null:
			sky = scene.get_node_or_null("Sky3D")
			_sky = sky
	if sky != null:
		var time_of_day := sky.get_node_or_null("TimeOfDay")
		if time_of_day != null and time_of_day.get("day") != null:
			return maxi(1, int(time_of_day.get("day")))
	return 1


## Day/night clock: split circle (sun above / moon + stars below) with the
## saved day and clock time printed underneath, at the far top-right corner.
func _draw_clock() -> void:
	var c: Vector2 = _clock_center
	var r: float = _clock_r
	if r <= 4.0 or _clock_center == Vector2.ZERO:
		return
	var t := _time_now()
	var day: int = _day_now()
	var hh: int = int(t) % 24
	var mm: int = int((t - floorf(t)) * 60.0) % 60
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(r * 0.58, 14.0, 20.0))
	var lw: float = maxf(font.get_string_size("DAY 99", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		font.get_string_size("88:88", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var cx: float = maxf(c.x, lw * 0.5 + 2.0)  # keep the caption fully on-screen

	# Base dial (night navy) + thin brass ring + faint sunpath track
	draw_circle(c + Vector2(0, 2.5), r + 1.5, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Color(0.04, 0.06, 0.09, 0.97))
	draw_arc(c, r, 0.0, TAU, 44, UI_SURFACE.BRASS, maxf(r * 0.05, 1.2), true)
	draw_arc(c, r * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0, true)

	# SUN POSITION on a 24 h dial
	var theta_s: float = PI * 0.5 + ((12.0 - t) / 24.0) * TAU
	var is_day: bool = t >= 6.0 and t < 18.0
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

	# Orbital marker: the sun by day, a crescent moon by night
	var mrk_a: float = theta_s if is_day else theta_s + PI
	var mrk: Vector2 = c + Vector2(cos(mrk_a), -sin(mrk_a)) * r * 0.62
	if is_day:
		draw_circle(mrk, r * 0.26, Color(1.0, 0.8, 0.35, 0.45))
		draw_circle(mrk, r * 0.17, Color(1.0, 0.95, 0.68, 1.0))
	else:
		var m2r: float = r * 0.17
		draw_circle(mrk, m2r, Color(0.9, 0.94, 1.0, 1.0))
		draw_circle(mrk + Vector2(m2r * 0.55, 0.0), m2r, Color(0.04, 0.06, 0.09, 1.0))

	# Caption: DAY + clock time under the dial, centered on it
	var y0: float = c.y + r + fs * 0.1
	var day_txt := "DAY %d" % day
	var day_w: float = font.get_string_size(day_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var day_pos := Vector2(cx - day_w * 0.5, y0 + fs * 0.3)
	draw_string(font, day_pos + Vector2(1, 1), day_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75))
	_draw_text(day_txt, day_pos, fs, Color(1, 0.92, 0.7, 0.98))

	var time_txt := "%02d:%02d" % [hh, mm]
	var time_w: float = font.get_string_size(time_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var time_pos := Vector2(cx - time_w * 0.5, y0 + fs * 0.3 + fs * 1.05)
	draw_string(font, time_pos + Vector2(1, 1), time_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75))
	_draw_text(time_txt, time_pos, fs, Color(0.45, 0.90, 1.0, 0.95))


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
	_draw_rounded(rect, 12.0, Color(0.035, 0.075, 0.095, 0.98))
	_draw_rounded(rect.grow(-3.0), 10.0, Color(0.52, 0.47, 0.34, 0.55), false, 1.0)
	# Restrained canvas seams along the outside of the storage panel.
	for seam_x in [rect.position.x + 10.0, rect.end.x - 10.0]:
		for stitch_y in range(int(rect.position.y + 18.0), int(rect.end.y - 18.0), 9):
			draw_line(Vector2(seam_x, stitch_y), Vector2(seam_x, stitch_y + 3.0), Color(0.63, 0.57, 0.40, 0.24), 1.0)
	# header
	var fs: int = int(clampf(rect.size.y * 0.028, 17.0, 25.0))
	_draw_text("BACKPACK", Vector2(rect.position.x + rect.size.x * 0.045,
			rect.position.y + rect.size.y * 0.062 + fs * 0.2), fs, Color(1, 1, 1, 0.95))
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
	var bag_scale:=rect.size.y/660.0
	_draw_text("ITEM DETAILS",_bag_detail_rect.position-Vector2(0,8*bag_scale),int(12*bag_scale),Color(.65,.83,.84))
	for idx in range(_bag_slot_rects.size()):
		var b: Rect2 = _bag_slot_rects[idx]
		var is_hotbar: bool = idx < HOTBAR_COUNT
		var selected: bool = not Inventory.slot_empty(idx) and (idx == _inspect_slot if _inspect_slot >= 0 else (is_hotbar and idx == act_slot and not (p != null and p.get("rope_gun_selected"))))
		_draw_slot(b, _pressed_visual == idx, selected)
		# hotbar row gets a subtle divider tint so it reads as the equip row
		if is_hotbar:
			_draw_rounded(b.grow(-2.0), b.size.x * 0.16, Color(1, 1, 1, 0.03), true, 1.0)
		if not Inventory.slot_empty(idx):
			var display_item: String = Icons.ITEM_ART.slot_icon(Inventory.slot_item(idx), idx)
			Icons.item_icon(self, display_item, b.get_center() - Vector2(0, b.size.y * 0.12), b.size.x * 0.32)
			var count: int = Inventory.slot_count(idx)
			if count > 0:
				var cfs: int = int(clampf(b.size.x * 0.22, 11.0, 18.0))
				var label := str(count)
				var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
				var badge := Rect2(b.end.x - tw2 - 8.0, b.position.y + 3.0, tw2 + 5.0, cfs + 3.0)
				_draw_rounded(badge, 3.0, Color(0.018, 0.023, 0.019, 0.88))
				_draw_text(label, badge.position + Vector2(2.0, cfs), cfs, Color(1, 1, 1, 0.95))
			_draw_paragraph(ITEM_GUIDE.label(Inventory.slot_item(idx)),Rect2(b.position+Vector2(4,b.size.y*.66),Vector2(b.size.x-8,b.size.y*.34)),maxi(9,int(11*bag_scale)),Color(.9,.93,.89),2)
	_draw_text("BACKPACK ITEMS",_bag_slot_rects[HOTBAR_COUNT].position-Vector2(0,8*bag_scale),int(12*bag_scale),Color(.65,.83,.84))
	_draw_text("SHORTCUTS  1–6",_bag_slot_rects[0].position-Vector2(0,8*bag_scale),int(12*bag_scale),Color(.65,.83,.84))
	var used:=0
	for index in Inventory.SLOT_COUNT:
		if not Inventory.slot_empty(index):used+=1
	_draw_text("%d / 30 SLOTS  ·  Tap to identify"%used,rect.position+Vector2(22,600)*bag_scale,maxi(11,int(14*bag_scale)),Color(.78,.9,.89))
	_draw_text("Drag between slots to move or swap",rect.position+Vector2(22,626)*bag_scale,maxi(10,int(12*bag_scale)),Color(.6,.75,.79))
	_draw_bag_details()

func _bag_primary_caption(item: String) -> String:
	if not _bag_can_use(item):return "FIND RECIPES"
	if not preload("res://scripts/garden_items.gd").box_crop(item).is_empty():return "OPEN BOX"
	if not preload("res://scripts/garden_items.gd").seed_crop(item,true).is_empty():return "HOLD TO DRY SEEDS"
	if item in preload("res://scripts/garden_items.gd").CROPS:return "EAT / SAVE SEEDS"
	if FOOD_RULES.edible(item):return "DRINK NOW" if FOOD_RULES.is_drink(item) else "EAT NOW"
	if item in ["Diving Tank","Life Vest"]:return "EQUIP NOW"
	if item in ["Bandage","Medkit"]:return "HEAL NOW"
	return "PLACE" if item=="WindGenerator" else "USE NOW"

func _draw_bag_details() -> void:
	var rect:=_bag_detail_rect
	var scale_factor:=_panel_rect.size.y/660.0
	_draw_rounded(rect,10,Color(.065,.135,.16,.95))
	var origin:=rect.position+Vector2(18,18)*scale_factor
	if _inspect_slot<0 or Inventory.slot_empty(_inspect_slot):
		_draw_paragraph("Tap an item to see what it does",Rect2(origin,rect.size-Vector2(36,36)*scale_factor),int(23*scale_factor),Color(.9,.94,.91),3)
		return
	var item:=Inventory.slot_item(_inspect_slot)
	Icons.item_icon(self,Icons.ITEM_ART.slot_icon(item,_inspect_slot),origin+Vector2(48,48)*scale_factor,46*scale_factor)
	var text_at:=origin+Vector2(112,4)*scale_factor
	_draw_paragraph(ITEM_GUIDE.label(item),Rect2(text_at,Vector2(rect.size.x-148*scale_factor,64*scale_factor)),maxi(17,int(24*scale_factor)),Color(.99,.94,.8),2)
	_draw_text("%s · Owned %d"%[ITEM_GUIDE.category(item),Inventory.total(item)],text_at+Vector2(0,92)*scale_factor,maxi(11,int(14*scale_factor)),Color(.61,.85,.88))
	var nutrition:=ITEM_GUIDE.nutrition(item)
	var copy_at:=origin+Vector2(0,130)*scale_factor
	if not nutrition.is_empty():
		var effects:=FOOD_RULES.effects(item)
		_draw_paragraph(nutrition,Rect2(copy_at,Vector2(rect.size.x-36*scale_factor,48*scale_factor)),maxi(12,int(16*scale_factor)),Color(1,.66,.45) if int(effects[2])<0 else Color(.57,.94,.74),2)
		copy_at.y+=54*scale_factor
	_draw_paragraph(ITEM_GUIDE.purpose(item),Rect2(copy_at,Vector2(rect.size.x-36*scale_factor,_bag_use_rect.position.y-copy_at.y-56*scale_factor)),maxi(12,int(17*scale_factor)),Color(.83,.91,.9),6)
	var hold_slot:=_bag_hold_slot()
	var swapped:=Inventory.slot_item(hold_slot)
	var destination:="Shortcut %d · ready to select"%(hold_slot+1)
	if _inspect_slot>=HOTBAR_COUNT and not swapped.is_empty() and swapped!=item:destination="Swaps with %s · both kept"%ITEM_GUIDE.label(swapped)
	_draw_paragraph(destination,Rect2(Vector2(origin.x,_bag_use_rect.position.y-44*scale_factor),Vector2(rect.size.x-36*scale_factor,40*scale_factor)),maxi(11,int(13*scale_factor)),Color(.66,.82,.85),2)
	_draw_pause_button(_bag_use_rect,_bag_primary_caption(item),true)
	_draw_pause_button(_bag_equip_rect,"HOLD ITEM · SLOT %d"%(hold_slot+1),true)

func _draw_paragraph(value: String, rect: Rect2, font_size: int, color: Color, max_lines: int=3) -> void:
	var font:=ThemeDB.fallback_font
	var lines:=PackedStringArray()
	var line:=""
	for word in value.split(" ",false):
		var next:=word if line.is_empty() else line+" "+word
		if not line.is_empty() and font.get_string_size(next,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x:
			lines.append(line);line=word
		else:line=next
	if not line.is_empty():lines.append(line)
	var visible_lines:=mini(max_lines,maxi(0,floori(rect.size.y/float(font_size+2))))
	for index in mini(lines.size(),visible_lines):
		var text_line:=lines[index]
		if index==visible_lines-1 and lines.size()>visible_lines:text_line+="…"
		while font.get_string_size(text_line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x and text_line.length()>1:
			text_line=text_line.left(text_line.length()-2)+"…"
		_draw_text(text_line,rect.position+Vector2(0,font_size+index*(font_size+2)),font_size,color)


func _draw_drag_ghost() -> void:
	if _drag_from < 0 or _drag_from >= Inventory.SLOT_COUNT or Inventory.slot_empty(_drag_from):
		return
	var sz := _slot * 0.92
	var r := Rect2(_drag_pos.x - sz * 0.5, _drag_pos.y - sz * 0.5, sz, sz)
	_draw_slot(r, false, false)
	Icons.item_icon(self, Icons.ITEM_ART.slot_icon(Inventory.slot_item(_drag_from), _drag_from), r.get_center(), sz * 0.43)
	var font := ThemeDB.fallback_font
	var count: int = Inventory.slot_count(_drag_from)
	if count > 1:
		var cfs: int = int(clampf(sz * 0.26, 11.0, 20.0))
		var label := str(count)
		var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		_draw_text(label, Vector2(r.end.x - tw2 - r.size.x * 0.1, r.position.y + r.size.y * 0.8 + cfs * 0.24), cfs, Color(1, 1, 1, 0.98))


func _draw_slot(rect: Rect2, pressed: bool, selected: bool) -> void:
	var radius: float = clampf(rect.size.x * 0.14, 6.0, 11.0)
	var bg := UI_SURFACE.SLATE_CARD
	if selected:
		bg = Color(0.12, 0.17, 0.22, 0.95)
	elif pressed:
		bg = Color(0.16, 0.22, 0.28, 0.90)

	# Soft bottom drop shadow
	_draw_rounded(Rect2(rect.position + Vector2(0, 1.5), rect.size), radius, Color(0, 0, 0, 0.45))
	# Base card surface
	_draw_rounded(rect, radius, bg)

	var border: Color = Color(0.32, 0.44, 0.52, 0.40)
	if selected:
		border = UI_SURFACE.BRASS
		# Outer selection glow
		_draw_rounded(rect.grow(2.0), radius + 1.5, Color(UI_SURFACE.BRASS.r, UI_SURFACE.BRASS.g, UI_SURFACE.BRASS.b, 0.25), false, 2.0)
	elif pressed:
		border = Color(1, 1, 1, 0.75)

	_draw_rounded(rect, radius, border, false, 1.6 if selected else 1.0)



# ============================================================
# HELPERS
# ============================================================
func _draw_rounded(rect: Rect2, radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	UI_SURFACE.panel(self, rect, radius, color, filled, width)


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
