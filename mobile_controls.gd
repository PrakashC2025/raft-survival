extends Control
class_name MobileControls

## ============================================================
## MOBILE TOUCH CONTROLS — full button set
##   - Left half of screen   : dynamic joystick = walk (starts where you touch)
##   - Right half of screen  : drag = look around
##   - Buttons feed the SAME Input actions as the keyboard:
##       JUMP(jump) RUN(sprint,hold) USE(interact) DIVE(move_down)
##       ROPE(rope_throw, HOLD to charge, release to throw) RECALL(rope_cancel)
##       BUILD(build/exit/cancel) EDIT(pick up aimed piece) REMOVE(remove_build)
##       PLACE(place_build / confirm edit) ROT(rotate_build) NEXT(cycle_build)
##   Buttons swap per mode: normal / build / edit.
## Shows on touch/mobile devices automatically; `force_show` previews on PC.
## ============================================================

@export var force_show: bool = false
## Fraction of the screen width used as the movement zone (left side).
@export var move_zone_width: float = 0.45
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

# --- buttons ---
var _btn_jump: Button
var _btn_run: Button
var _btn_use: Button
var _btn_dive: Button
var _btn_rope: Button
var _btn_recall: Button
var _btn_edit: Button
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


# ============================================================
# TOUCH ROUTING — via _input (mouse_filter is IGNORE so the mouse is never
# blocked). Touches that land on a button are left to the button's own GUI
# handling; everything else becomes joystick (left half) or look (right).
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
		if event.pressed and _over_button(event.position):
			return  # the Button handles it
		if event.pressed:
			if _move_id == -1 and event.position.x < size.x * move_zone_width:
				_start_move(event.index, event.position)
			elif _look_id == -1:
				_start_look(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _move_id:
			_update_move(event.position)
		elif event.index == _look_id:
			_update_look(event.relative)
	# Mouse events are deliberately ignored here — desktop keeps mouse + keys.


func _over_button(pos: Vector2) -> bool:
	for b in _all_buttons:
		if b != null and b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


func _start_move(index: int, pos: Vector2) -> void:
	_move_id = index
	# Touching near the docked joystick uses the dock as its base (a fixed
	# stick feels better); anywhere else on the left half spawns a joystick at
	# the touch point.
	var r := _joy_radius()
	if pos.distance_to(_dock) <= r * 1.5:
		_base = _dock
	else:
		_base = pos
	_knob = _base
	_stick = Vector2.ZERO
	queue_redraw()


func _update_move(pos: Vector2) -> void:
	var radius := _joy_radius()
	var delta := pos - _base
	var len := delta.length()
	if len > radius:
		delta = delta / len * radius
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
# BUTTONS
# ============================================================
func _build_buttons() -> void:
	_btn_jump = _make_button("JUMP", Color(0.18, 0.55, 0.9, 0.62))
	_btn_rope = _make_button("ROPE", Color(0.85, 0.6, 0.15, 0.68))
	_btn_recall = _make_button("BACK", Color(0.75, 0.3, 0.25, 0.7))
	_btn_run = _make_button("RUN", Color(0.3, 0.62, 0.35, 0.55))
	_btn_use = _make_button("USE", Color(0.85, 0.6, 0.2, 0.6))
	_btn_dive = _make_button("DIVE", Color(0.2, 0.55, 0.8, 0.55))
	_btn_edit = _make_button("EDIT", Color(0.5, 0.4, 0.75, 0.6))
	_btn_build = _make_button("BUILD", Color(0.45, 0.35, 0.8, 0.65))
	_btn_place = _make_button("PLACE", Color(0.15, 0.72, 0.45, 0.75))
	_btn_rotate = _make_button("ROT", Color(0.2, 0.55, 0.8, 0.6))
	_btn_next = _make_button("NEXT", Color(0.25, 0.6, 0.75, 0.6))
	_btn_remove = _make_button("REMOVE", Color(0.8, 0.25, 0.2, 0.75))

	_all_buttons = [_btn_jump, _btn_rope, _btn_recall, _btn_run, _btn_use, _btn_dive,
			_btn_edit, _btn_build, _btn_place, _btn_rotate, _btn_next, _btn_remove]

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

	# Tap-style: USE is momentary (like pressing E), EDIT picks the aimed piece.
	_btn_use.button_down.connect(_press_action.bind("interact"))
	_btn_use.button_up.connect(_release_action.bind("interact"))
	_btn_edit.pressed.connect(_on_edit_pressed)

	for b in _all_buttons:
		add_child(b)
	_sync_mode()


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


func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.8))
	var normal := _style(color)
	var hover := _style(color.lightened(0.15))
	var pressed := _style(color.darkened(0.25))
	pressed.border_color = Color(1, 1, 1, 0.6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal.duplicate())
	return b


func _style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(1, 1, 1, 0.3)
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


# ============================================================
# MODE SYNC — which buttons are visible, and how BUILD is labelled.
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

	if mode == _mode and rope_busy == _rope_busy and swimming == _swimming and can_edit == _can_edit:
		return
	_mode = mode
	_rope_busy = rope_busy
	_swimming = swimming
	_can_edit = can_edit

	var normal: bool = mode == "normal"
	_btn_jump.visible = normal
	_btn_run.visible = normal
	_btn_use.visible = normal
	_btn_dive.visible = normal and swimming
	_btn_rope.visible = normal
	_btn_recall.visible = normal and rope_busy
	_btn_edit.visible = normal and can_edit
	_btn_place.visible = mode != "normal"
	_btn_rotate.visible = mode != "normal"
	_btn_next.visible = mode == "build"
	_btn_remove.visible = mode == "edit"

	var label := "BUILD"
	var col := Color(0.45, 0.35, 0.8, 0.65)
	match mode:
		"edit":
			label = "CANCEL"
			col = Color(0.7, 0.45, 0.2, 0.7)
		"build":
			label = "EXIT"
			col = Color(0.8, 0.3, 0.3, 0.7)
	if _btn_build.text != label:
		_btn_build.text = label
	_btn_build.add_theme_stylebox_override("normal", _style(col))


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
	var tiny := clampf(vp.y * 0.07, 46.0, 64.0)
	var right := vp.x - m
	var bottom := vp.y - m

	# Resting joystick position: bottom-left corner, inside the move zone.
	var jr := _joy_radius()
	_dock = Vector2(m + jr, vp.y - m - jr)
	queue_redraw()

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

	# Left-of-column small stack (bottom up): RUN/USE (normal), DIVE, EDIT,
	# and the ROT/NEXT/REMOVE equivalents in build/edit modes.
	var s_x := right - big - m - small
	_btn_run.position = Vector2(s_x, bottom - small)
	_btn_run.size = Vector2(small, small)
	_btn_use.position = Vector2(s_x, bottom - small - m - small)
	_btn_use.size = Vector2(small, small)
	_btn_dive.position = Vector2(s_x, bottom - small - m - small - m - small)
	_btn_dive.size = Vector2(small, small)
	_btn_edit.position = Vector2(s_x, bottom - small - m - small - m - small - m - small)
	_btn_edit.size = Vector2(small, small)
	_btn_next.position = _btn_run.position
	_btn_next.size = _btn_run.size
	_btn_rotate.position = _btn_use.position
	_btn_rotate.size = _btn_use.size
	_btn_remove.position = _btn_dive.position
	_btn_remove.size = Vector2(small, small)

	# Top-right BUILD / EXIT / CANCEL toggle.
	_btn_build.position = Vector2(right - small, m)
	_btn_build.size = Vector2(small, small)

	_fit_fonts()


func _fit_fonts() -> void:
	for b in _all_buttons:
		if b != null and b.size.x > 0.0:
			b.add_theme_font_size_override("font_size", int(maxf(13.0, b.size.x * 0.15)))


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


# ============================================================
# DEBUG DRAW — joystick base ring + knob
# ============================================================
func _draw() -> void:
	if not visible:
		return
	var radius := _joy_radius()
	if _move_id != -1:
		# Active joystick at its base.
		draw_circle(_base, radius, Color(1, 1, 1, 0.12))
		draw_arc(_base, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		var knob_r := clampf(radius * 0.38, 24.0, 48.0)
		draw_circle(_knob, knob_r, Color(1, 1, 1, 0.4))
		draw_arc(_knob, knob_r, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	else:
		# Idle dock — a faint resting joystick so players can SEE where to put
		# their thumb instead of hunting for an invisible control.
		draw_circle(_dock, radius, Color(1, 1, 1, 0.06))
		draw_arc(_dock, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.2), 3.0)
		draw_circle(_dock, clampf(radius * 0.3, 20.0, 38.0), Color(1, 1, 1, 0.16))


# Exposed for tests: where the resting joystick dock sits.
func _dock_center() -> Vector2:
	return _dock
