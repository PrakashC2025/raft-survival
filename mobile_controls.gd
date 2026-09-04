extends Control
class_name MobileControls

const Icons := preload("res://ui_icons.gd")

## ============================================================
## MOBILE TOUCH CONTROLS — joystick = move, touch-screen = look
##   - The bottom-left joystick DOCK is the ONLY movement control: touch it
##     (within its grab zone) and drag to walk. It stays fixed at the dock.
##   - Touching ANYWHERE ELSE on the screen and dragging rotates the camera
##     (look). A second finger can look while the first holds the joystick.
##   - Action buttons are INVISIBLE Button nodes whose circular icon art is
##     painted by this overlay's _draw() (original vector glyphs, reference
##     style). They feed the SAME Input actions as the keyboard:
##       JUMP(jump) RUN(sprint,hold) USE(interact) DIVE(move_down)
##       ROPE(rope_throw, HOLD to charge, release to throw) RECALL(rope_cancel)
##       BUILD(build/exit/cancel) EDIT(pick up aimed piece) REMOVE(remove_build)
##       PLACE(place_build / confirm edit) ROT(rotate_build) NEXT(cycle_build)
##   Buttons swap per mode: normal / build / edit.
##   - The survival HUD (bag/hotbar) may claim touches: anything its
##     claims_touch() reports is never turned into camera look, and while its
##     bag panel is open all gameplay input is suspended.
## Shows on touch/mobile devices automatically; `force_show` previews on PC.
## ============================================================

@export var force_show: bool = false
## Grab zone around the joystick dock, as a multiple of the stick radius.
## Touches inside it start movement; touches outside it start camera look.
@export var dock_zone_scale: float = 1.6
## Look sensitivity per touch-pixel (mouse is 0.003; fingers are coarser).
@export var look_sensitivity: float = 0.007
## Movement dead zone (0..1 of joystick travel).
@export var joystick_deadzone: float = 0.18

var _player: Node = null
var _shown := false

# --- touch tracking ---
var _move_id := -1
var _look_id := -1
var _base := Vector2.ZERO   # joystick base (screen)
var _knob := Vector2.ZERO   # joystick knob (screen)
var _stick := Vector2.ZERO  # joystick vector, y+ = forward
var _dock := Vector2.ZERO   # resting joystick position (bottom-left)

# --- buttons (invisible; icon art drawn by _draw) ---
var _btn_jump: Button
var _btn_run: Button
var _btn_use: Button
var _btn_dive: Button
var _btn_rope: Button
var _btn_recall: Button
var _btn_edit: Button
var _btn_climb: Button
var _btn_build: Button
var _btn_place: Button
var _btn_rotate: Button
var _btn_next: Button
var _btn_remove: Button
var _all_buttons: Array[Button] = []

# cached mode state
var _mode := "init"  # "normal" | "build" | "edit"
var _rope_busy := false
var _swimming := false
var _can_edit := false
var _can_interact := false  # center crosshair points at an interactable
var _can_climb := false     # swimming next to the raft — CLIMB button available

# reference to the survival HUD overlay (bag/hotbar), lazy
var _hud: Control = null


func _ready() -> void:
	# IMPORTANT: this full-screen Control must never swallow mouse events or it
	# blocks desktop mouse-look (e.g. after Esc shows the cursor). Buttons keep
	# their own mouse_filter = STOP; the overlay itself is IGNORE and receives
	# touches via _input() instead of the GUI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No Control parent (this hangs off a CanvasLayer), so anchors are useless.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	_build_buttons()
	# Apply the correct initial visibility (scene default is `visible = true`,
	# which used to leave the touch UI on screen on desktop machines).
	_shown = _should_show()
	visible = _shown
	var vp := get_viewport()
	vp.size_changed.connect(_apply_viewport_size)
	_apply_viewport_size()


func _apply_viewport_size() -> void:
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	_layout()


func _process(_delta: float) -> void:
	_update_visibility()
	# While the bag panel is open the whole screen belongs to the HUD: drop the
	# joystick and any held action so nothing drifts behind the panel.
	if _hud_node() != null and _hud_node().is_blocking():
		if _move_id != -1 or Input.is_action_pressed("jump") or Input.is_action_pressed("sprint") \
				or Input.is_action_pressed("rope_throw") or Input.is_action_pressed("interact"):
			_move_id = -1
			_stick = Vector2.ZERO
			queue_redraw()
			_release_all_actions()
		return
	_update_movement_actions()
	_sync_mode()


# ============================================================
# VISIBILITY
# ============================================================
func _should_show() -> bool:
	# Mobile UI only on real mobile builds (Android/iOS/web-mobile) or when
	# force_show is enabled in the inspector for desktop preview. Never on a
	# plain PC — desktop keeps the keyboard + mouse and must not be covered by
	# touch controls (some desktops report a touchscreen and previously the UI
	# popped up there and got in the way).
	if force_show:
		return true
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	return false


func _update_visibility() -> void:
	var want := _should_show()
	if want == _shown:
		return
	_shown = want
	visible = want
	if not want:
		_release_all_actions()
		_move_id = -1
		_look_id = -1


func _hud_node() -> Control:
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("survival_hud") as Control
	return _hud


# ============================================================
# TOUCH ROUTING — via _input (mouse_filter is IGNORE so the mouse is never
# blocked). Touches claimed by the HUD (bag/hotbar/panel) or landing on an
# action button are left to those controls; the bottom-left joystick dock is
# the ONLY movement control; every other touch starts camera look.
# ============================================================
func _input(event: InputEvent) -> void:
	# F10 toggles the mobile UI on/off — handy for previewing it on a PC
	# (Android/iOS builds show it automatically).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		force_show = not force_show
		return
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_button(event.position):
				return  # the Button handles it
			if _hud_node() != null and _hud_node().claims_touch(event.position):
				return  # bag / hotbar / open panel
			if _move_id == -1 and _in_dock_zone(event.position):
				_start_move(event.index)
			elif _look_id == -1:
				_start_look(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		if _move_id != -1 and event.index == _move_id and _hud_node() != null and _hud_node().is_blocking():
			_move_id = -1
			_stick = Vector2.ZERO
			queue_redraw()
			_release_all_actions()
		elif event.index == _move_id:
			_update_move(event.position)
		elif event.index == _look_id:
			_update_look(event.relative)
	# Mouse events are deliberately ignored here — desktop keeps mouse + keys.


func _over_button(pos: Vector2) -> bool:
	for b in _all_buttons:
		if b != null and b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


## True when the touch is inside the joystick dock's grab zone (the ONLY
## place movement can start — everywhere else on the screen looks around).
func _in_dock_zone(pos: Vector2) -> bool:
	return pos.distance_to(_dock) <= _joy_radius() * dock_zone_scale


func _start_move(index: int) -> void:
	_move_id = index
	# Movement always anchors to the fixed dock (no dynamic spawning) so the
	# rest of the screen stays free for camera look.
	_base = _dock
	_knob = _dock
	_stick = Vector2.ZERO
	queue_redraw()


func _update_move(pos: Vector2) -> void:
	var radius := _joy_radius()
	var delta := pos - _base
	var dist := delta.length()
	if dist > radius:
		delta = delta / dist * radius
		_knob = _base + delta
	else:
		_knob = pos
	_stick = Vector2(delta.x / radius, -delta.y / radius)
	if _stick.length() > 1.0:
		_stick = _stick.normalized()
	queue_redraw()


func _end_touch(index: int) -> void:
	if index == _move_id:
		_move_id = -1
		_stick = Vector2.ZERO
		queue_redraw()
	if index == _look_id:
		_look_id = -1


func _start_look(index: int, _pos: Vector2) -> void:
	_look_id = index


func _update_look(rel: Vector2) -> void:
	var p := _get_player()
	if p != null and p.has_method("add_look_input"):
		p.add_look_input(rel, look_sensitivity)


func _joy_radius() -> float:
	return clampf(size.y * 0.16, 70.0, 150.0)


# ============================================================
# MOVE ACTIONS — synthesized every frame from the joystick vector
# ============================================================
func _update_movement_actions() -> void:
	if not visible:
		return
	if _move_id == -1:
		for a in ["move_forward", "move_back", "move_left", "move_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		return
	var v := _stick
	_set_move_action("move_forward", clampf(v.y, 0.0, 1.0))
	_set_move_action("move_back", clampf(-v.y, 0.0, 1.0))
	_set_move_action("move_left", clampf(-v.x, 0.0, 1.0))
	_set_move_action("move_right", clampf(v.x, 0.0, 1.0))


func _set_move_action(action: StringName, strength: float) -> void:
	if strength <= joystick_deadzone:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	elif not Input.is_action_pressed(action) or not is_equal_approx(Input.get_action_strength(action), strength):
		Input.action_press(action, strength)


func _release_all_actions() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact",
			"move_down", "rope_throw", "rope_cancel", "build", "place_build", "cycle_build",
			"rotate_build", "remove_build"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


# ============================================================
# BUTTONS (invisible, icon art drawn in _draw)
# ============================================================
func _build_buttons() -> void:
	_btn_jump = _make_button("jump")
	_btn_rope = _make_button("hook")
	_btn_recall = _make_button("back")
	_btn_run = _make_button("run")
	_btn_use = _make_button("hand")
	_btn_dive = _make_button("down")
	_btn_edit = _make_button("pencil")
	_btn_climb = _make_button("climb")
	_btn_build = _make_button("hammer")
	_btn_place = _make_button("check")
	_btn_rotate = _make_button("rot")
	_btn_next = _make_button("next")
	_btn_remove = _make_button("trash")

	_all_buttons = [_btn_jump, _btn_rope, _btn_recall, _btn_run, _btn_use, _btn_dive,
			_btn_climb, _btn_edit, _btn_build, _btn_place, _btn_rotate, _btn_next, _btn_remove]

	# Hold-style buttons: press the action on touch-down, release on touch-up.
	_btn_jump.button_down.connect(_press_action.bind("jump"))
	_btn_jump.button_up.connect(_release_action.bind("jump"))
	_btn_rope.button_down.connect(_press_action.bind("rope_throw"))
	_btn_rope.button_up.connect(_release_action.bind("rope_throw"))
	_btn_run.button_down.connect(_press_action.bind("sprint"))
	_btn_run.button_up.connect(_release_action.bind("sprint"))
	_btn_dive.button_down.connect(_press_action.bind("move_down"))
	_btn_dive.button_up.connect(_release_action.bind("move_down"))
	_btn_build.button_down.connect(_press_action.bind("build"))
	_btn_build.button_up.connect(_release_action.bind("build"))
	_btn_place.button_down.connect(_press_action.bind("place_build"))
	_btn_place.button_up.connect(_release_action.bind("place_build"))
	_btn_rotate.button_down.connect(_press_action.bind("rotate_build"))
	_btn_rotate.button_up.connect(_release_action.bind("rotate_build"))
	_btn_next.button_down.connect(_press_action.bind("cycle_build"))
	_btn_next.button_up.connect(_release_action.bind("cycle_build"))
	_btn_remove.button_down.connect(_press_action.bind("remove_build"))
	_btn_remove.button_up.connect(_release_action.bind("remove_build"))
	_btn_recall.button_down.connect(_press_action.bind("rope_cancel"))
	_btn_recall.button_up.connect(_release_action.bind("rope_cancel"))

	# Tap-style: USE is momentary (like pressing E), EDIT picks the aimed piece,
	# CLIMB boards the raft directly (same as E while swimming next to it).
	_btn_use.button_down.connect(_press_action.bind("interact"))
	_btn_use.button_up.connect(_release_action.bind("interact"))
	_btn_edit.pressed.connect(_on_edit_pressed)
	_btn_climb.pressed.connect(_on_climb_pressed)

	for b in _all_buttons:
		add_child(b)
		b.pressed.connect(_queue_redraw)
		b.button_down.connect(_queue_redraw)
		b.button_up.connect(_queue_redraw)
	_sync_mode()


func _queue_redraw() -> void:
	queue_redraw()


func _press_action(action: StringName) -> void:
	if visible:
		Input.action_press(action)


func _release_action(action: StringName) -> void:
	Input.action_release(action)


## One tap = the desktop "E, E" double-pickup of the piece under the crosshair.
func _on_edit_pressed() -> void:
	var p := _get_player()
	if p == null or not visible:
		return
	if p.has_method("_handle_double_click_edit"):
		p.call("_handle_double_click_edit")
		p.call("_handle_double_click_edit")


## Tap = pull the player out of the water onto the nearest deck edge. The
## button only appears while swimming next to the raft/foundation, so the
## press always succeeds (climb_out no-ops if the ledge moved away).
func _on_climb_pressed() -> void:
	var p := _get_player()
	if p == null or not visible:
		return
	if p.has_method("climb_out"):
		p.call("climb_out")


func _make_button(kind: String) -> Button:
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("icon_kind", kind)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	return b


# ============================================================
# MODE SYNC — which buttons are visible, and what BUILD does per mode.
# ============================================================
func _sync_mode() -> void:
	var p := _get_player()
	var editing: bool = p != null and p.get("_editing") != null
	var building: bool = p != null and p.get("build_mode") == true
	var swimming: bool = p != null and p.get("is_swimming") == true
	var rope: Node = null
	if p != null:
		rope = p.get_node_or_null("RopeSystem")
	var rope_busy: bool = rope != null and rope.has_method("is_active") and bool(rope.call("is_active"))

	var mode := "edit" if editing else ("build" if building else "normal")
	var can_edit := false
	if mode == "normal" and p != null and p.get("aim_valid") == true:
		var c: Node = p.get("aim_collider")
		if c != null and p.has_method("_find_editable_target"):
			can_edit = p.call("_find_editable_target", c) != null
	var can_interact := false
	if mode == "normal" and p != null and p.has_method("can_interact_now"):
		can_interact = bool(p.call("can_interact_now"))
	var can_climb := false
	if mode == "normal" and swimming and p != null and p.has_method("can_climb_out"):
		can_climb = bool(p.call("can_climb_out"))

	if mode == _mode and rope_busy == _rope_busy and swimming == _swimming \
			and can_edit == _can_edit and can_interact == _can_interact and can_climb == _can_climb:
		return
	_mode = mode
	_rope_busy = rope_busy
	_swimming = swimming
	_can_edit = can_edit
	_can_interact = can_interact
	_can_climb = can_climb

	var normal: bool = mode == "normal"
	_btn_jump.visible = normal
	_btn_run.visible = normal
	# The HAND button only appears when the center crosshair is actually over
	# an interactable (debris / door / usable piece) — same logic as the E key.
	_btn_use.visible = normal and can_interact
	_btn_dive.visible = normal and swimming
	# CLIMB appears ONLY while swimming right next to the raft/foundation
	# (same test as the E key) — never on land, never in open water.
	_btn_climb.visible = normal and can_climb
	_btn_rope.visible = normal
	_btn_recall.visible = normal and rope_busy
	_btn_edit.visible = normal and can_edit
	_btn_place.visible = mode != "normal"
	_btn_rotate.visible = mode != "normal"
	_btn_next.visible = mode == "build"
	_btn_remove.visible = mode == "edit"

	# If a hold-style button vanished while held (e.g. the target moved away
	# from the crosshair mid-press), release its action so it never sticks.
	if not _btn_use.visible and Input.is_action_pressed("interact"):
		Input.action_release("interact")
	if not _btn_rope.visible and Input.is_action_pressed("rope_throw"):
		Input.action_release("rope_throw")
	if not _btn_run.visible and Input.is_action_pressed("sprint"):
		Input.action_release("sprint")

	queue_redraw()


# ============================================================
# LAYOUT — right-edge cluster; everything scales with the viewport.
# ============================================================
func _layout() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var m := clampf(vp.y * 0.018, 8.0, 18.0)
	var big := clampf(vp.y * 0.15, 92.0, 132.0)
	var small := clampf(vp.y * 0.085, 54.0, 80.0)
	var right := vp.x - m
	var bottom := vp.y - m

	# Resting joystick position: bottom-left corner, inside the move zone.
	var jr := _joy_radius()
	_dock = Vector2(m + jr, vp.y - m - jr)

	# Right-edge column (bottom up): JUMP/PLACE (big), ROPE, RECALL.
	var col_x := right - big
	_btn_jump.position = Vector2(col_x, bottom - big)
	_btn_jump.size = Vector2(big, big)
	_btn_place.position = _btn_jump.position
	_btn_place.size = _btn_jump.size
	_btn_rope.position = Vector2(col_x, bottom - big - m - big)
	_btn_rope.size = Vector2(big, big)
	_btn_recall.position = Vector2(right - small, bottom - big - m - big - m - small)
	_btn_recall.size = Vector2(small, small)

	# Left-of-column small stack (bottom up): RUN/USE (normal), DIVE, CLIMB,
	# EDIT, and the ROT/NEXT/REMOVE equivalents in build/edit modes.
	var s_x := right - big - m - small
	_btn_run.position = Vector2(s_x, bottom - small)
	_btn_run.size = Vector2(small, small)
	_btn_use.position = Vector2(s_x, bottom - small - m - small)
	_btn_use.size = Vector2(small, small)
	_btn_dive.position = Vector2(s_x, bottom - small - m - small - m - small)
	_btn_dive.size = Vector2(small, small)
	_btn_climb.position = Vector2(s_x, bottom - small - m - small - m - small - m - small)
	_btn_climb.size = Vector2(small, small)
	_btn_edit.position = Vector2(s_x, bottom - small - m - small - m - small - m - small - m - small)
	_btn_edit.size = Vector2(small, small)
	_btn_next.position = _btn_run.position
	_btn_next.size = _btn_run.size
	_btn_rotate.position = _btn_use.position
	_btn_rotate.size = _btn_use.size
	_btn_remove.position = _btn_dive.position
	_btn_remove.size = Vector2(small, small)

	# LEFT-CENTER BUILD toggle (enter/exit build mode): sits above the
	# movement joystick's grab zone, out of the camera-look area and never on
	# top of the center crosshair. Turns into an X (cancel) while building.
	var b_size := small
	var b_x: float = m
	var b_y: float = clampf(vp.y * 0.36, m, _dock.y - jr * 1.9 - b_size)
	_btn_build.position = Vector2(b_x, b_y)
	_btn_build.size = Vector2(b_size, b_size)

	queue_redraw()


# ============================================================
# ICON ART — every visible action button is painted here as a dark glassy
# circle with an original white vector glyph (reference-style).
# ============================================================
func _button_icon_kind(b: Button) -> String:
	var kind: String = str(b.get_meta("icon_kind", "?"))
	if b == _btn_build:
		# The build toggle morphs with its mode: hammer = enter, X = exit/cancel.
		kind = "x" if (_mode == "build" or _mode == "edit") else "hammer"
	return kind


func _draw() -> void:
	if not visible:
		return
	var radius := _joy_radius()
	if _move_id != -1:
		_draw_dpad(_base, radius, _knob)
	else:
		# Idle dock — a faint resting D-pad so players can SEE where to put
		# their thumb instead of hunting for an invisible control.
		_draw_dpad(_dock, radius, _dock)
	# Action buttons on top of the D-pad? No — buttons live bottom-right; draw
	# them after so nothing overlaps incorrectly.
	for b in _all_buttons:
		if b == null or not b.visible:
			continue
		_draw_action_button(b)


func _draw_action_button(b: Button) -> void:
	var rect := b.get_global_rect()
	var center := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var pressed := b.is_pressed() or b.has_focus()
	var bg := Color(0.06, 0.08, 0.11, 0.55) if not pressed else Color(0.16, 0.2, 0.28, 0.75)
	draw_circle(center, r * 0.92, bg)
	var ring: Color = Color(1, 1, 1, 0.32)
	if _button_icon_kind(b) == "hammer" and _mode == "normal":
		ring = Color(0.55, 0.9, 0.5, 0.5)
	elif _button_icon_kind(b) == "x":
		ring = Color(0.95, 0.4, 0.35, 0.5)
	elif _button_icon_kind(b) == "check":
		ring = Color(0.4, 0.95, 0.6, 0.5)
	elif _button_icon_kind(b) == "climb":
		ring = Color(0.4, 0.85, 0.95, 0.6)
	draw_arc(center, r * 0.92, 0.0, TAU, 40, ring, clampf(r * 0.06, 1.5, 3.0), true)
	var col := Color(1, 1, 1, 0.92) if not pressed else Color(1, 1, 1, 1.0)
	_draw_icon_glyph(b, center, r * 0.48, col)


func _draw_icon_glyph(b: Button, center: Vector2, r: float, col: Color) -> void:
	var w := clampf(r * 0.26, 3.0, 7.0)
	var kind := _button_icon_kind(b)
	match kind:
		"jump":
			Icons.arrow_up(self, center, r, w, col)
		"down":
			Icons.arrow_down(self, center, r, w, col)
		"back":
			Icons.arrow_left(self, center, r, w, col)
		"next":
			Icons.chevrons(self, center, Vector2.RIGHT, r, w, col)
		"check":
			Icons.check(self, center, r, w, col)
		"x":
			Icons.cross(self, center, r, w, col)
		"run":
			Icons.run(self, center, r * 1.15, w * 0.9, col)
		"hand":
			Icons.hand(self, center, r, w * 0.7, col)
		"climb":
			# Arrow up out of a wave — "pull yourself onto the raft".
			Icons.arrow_up(self, center + Vector2(0, -r * 0.1), r * 0.6, w, col)
			var wy := center.y + r * 0.45
			var wpts := PackedVector2Array()
			for wi in range(5):
				var wt := float(wi) / 4.0
				wpts.append(Vector2(center.x - r * 0.6 + wt * r * 1.2, wy + sin(wt * PI) * r * 0.18))
			draw_polyline(wpts, col, maxf(w * 0.7, 1.5), true)
		"hook":
			Icons.hook(self, center, r, w * 0.9, col)
		"hammer":
			Icons.hammer(self, center, r, w, col)
		"pencil":
			Icons.pencil(self, center, r, w, col)
		"trash":
			Icons.trash(self, center, r, w, col)
		"rot":
			Icons.rotate(self, center, r, w, col)
		_:
			Icons.check(self, center, r, w, col)


# ============================================================
# DEBUG DRAW — D-pad joystick: transparent base ring, four directional
# arrows pointing toward the central thumbstick (reference style).
# ============================================================
func _draw_dpad(center: Vector2, radius: float, knob_pos: Vector2) -> void:
	# Transparent base plate.
	draw_circle(center, radius, Color(1, 1, 1, 0.08))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.28), 2.5)
	draw_arc(center, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 1.5)
	# Four directional arrows pointing toward the central thumbstick.
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for dir in dirs:
		_draw_inward_arrow(center, dir, radius)
	# Central thumbstick (moves with the touch).
	var knob_r := clampf(radius * 0.34, 22.0, 44.0)
	draw_circle(knob_pos, knob_r, Color(1, 1, 1, 0.34))
	draw_arc(knob_pos, knob_r, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 2.0)


## One directional chevron whose tip points IN toward the center (like the
## reference D-pad, where the arrows converge on the thumbstick).
func _draw_inward_arrow(center: Vector2, dir: Vector2, radius: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * radius * 0.30
	var back := center + dir * radius * 0.82
	var half_w := radius * 0.16
	var pts := PackedVector2Array([
		tip,
		back + perp * half_w,
		back - perp * half_w,
	])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.34))


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


# Exposed for tests: where the resting joystick dock sits.
func _dock_center() -> Vector2:
	return _dock
