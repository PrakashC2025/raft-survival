extends Control
class_name MobileControls

const Icons := preload("res://scripts/ui_icons.gd")
const UI_SURFACE := preload("res://scripts/ui_surface.gd")

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
## Look sensitivity per normalized touch-pixel (mouse is 0.00225).
@export var look_sensitivity: float = 0.003
## Movement dead zone (0..1 of joystick travel).
@export var joystick_deadzone: float = 0.18

var _player: Node = null
var _shown := false

# --- touch tracking ---
var _move_id := -1
var _look_id := -1
var _button_touches: Dictionary = {}
var _owned_actions: Dictionary = {}
var _base := Vector2.ZERO   # joystick base (screen)
var _knob := Vector2.ZERO   # joystick knob (screen)
var _stick := Vector2.ZERO  # joystick vector, y+ = forward
var _dock := Vector2.ZERO   # resting joystick position (bottom-left)

# --- buttons (invisible; icon art drawn by _draw) ---
var _btn_jump: Button
var _btn_run: Button
var _btn_use: Button
var _btn_aim: Button
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
var _btn_help: Button
var _all_buttons: Array[Button] = []

# --- in-game help panel (the "?" button) ---
var _help_open := false
var _help_ui: Control = null
var _help_dim: Button = null
var _help_panel: ColorRect = null
var _help_text: RichTextLabel = null
var _help_close: Button = null

# cached mode state
var _mode := "init"  # "normal" | "build" | "edit"
var _rope_busy := false
var _swimming := false
var _can_edit := false
var _can_interact := false  # center crosshair points at an interactable
var _was_blocked := false
var _use_caption := ""
var _moving := false
var _rope_equipped := false
var _bow_equipped := false
var _can_build := false
var _can_climb := false     # swimming next to the raft — CLIMB button available

# reference to the survival HUD overlay (bag/hotbar), lazy
var _hud: Control = null


func _ready() -> void:
	add_to_group("mobile_controls")
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# Deferred: the overlay's _ready runs while the CanvasLayer is still being
	# built during scene load, so adding a sibling panel now would fail.
	call_deferred("_build_help_panel")
	var vp := get_viewport()
	vp.size_changed.connect(_apply_viewport_size)
	_apply_viewport_size()


func _apply_viewport_size() -> void:
	reset_input()
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	_layout()
	_layout_help()


func _process(_delta: float) -> void:
	_update_visibility()
	if _input_blocked():
		if not _was_blocked:
			reset_input()
		_was_blocked = true
		return
	if _was_blocked:
		_was_blocked = false
		_mode = "init"
		queue_redraw()
	if not _shown:
		return
	# While the help panel is open, release every held action so nothing walks
	# behind the overlay, and skip movement/joystick syncing.
	if _help_open:
		_release_all_actions()
		return
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
		reset_input()
		if _help_open:
			_set_help(false)


func _hud_node() -> Control:
	if _hud == null or not _hud.is_inside_tree():
		var candidate: Node = get_tree().get_first_node_in_group("survival_hud")
		if candidate is Control:
			_hud = candidate
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
	# Gameplay buttons are routed by finger ID, independently of the single
	# emulated mouse pointer used by ordinary menu widgets.
	if event is InputEventMouse and event.device == -1:
		if not _input_blocked():
			get_viewport().set_input_as_handled()
		return
	# While the help panel is open the screen belongs to it: no joystick, no
	# camera look (the panel's own buttons still work via the GUI).
	if _input_blocked():
		reset_input()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _hud_node() != null and _hud_node().claims_touch(event.position):
				return  # bag / hotbar / open panel
			var button := _button_at(event.position)
			if button != null:
				if _button_touches.values().has(button):
					get_viewport().set_input_as_handled()
					return
				_button_touches[event.index] = button
				button.set_pressed_no_signal(true)
				button.button_down.emit()
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if _move_id == -1 and _in_dock_zone(event.position):
				_start_move(event.index)
				_update_move(event.position)
			elif _look_id == -1:
				_start_look(event.index, event.position)
		else:
			if _button_touches.has(event.index):
				_release_touch_button(event.index, not event.canceled)
				get_viewport().set_input_as_handled()
				return
			_end_touch(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _button_touches.has(event.index):
			var held: Button = _button_touches[event.index]
			if not held.is_visible_in_tree() or not held.get_global_rect().grow(18.0).has_point(event.position):
				_release_touch_button(event.index, false)
			get_viewport().set_input_as_handled()
			return
		if _move_id != -1 and event.index == _move_id and _hud_node() != null and _hud_node().is_blocking():
			_move_id = -1
			_stick = Vector2.ZERO
			queue_redraw()
			_release_all_actions()
		elif event.index == _move_id:
			_update_move(event.position)
		elif event.index == _look_id:
			_update_look(event.relative)
		get_viewport().set_input_as_handled()
	# Mouse events are deliberately ignored here — desktop keeps mouse + keys.


func _over_button(pos: Vector2) -> bool:
	return _button_at(pos) != null


func _button_at(pos: Vector2) -> Button:
	var actor:=_get_player()
	var tools:=actor.get_node_or_null("PortableElectronics") if actor!=null else null
	if tools!=null:
		var tool_button:=tools.call("touch_button_at",pos) as Button
		if tool_button!=null:return tool_button
	for b in _all_buttons:
		if b != null and b.visible and b.get_global_rect().has_point(pos):
			return b
	return null


func _release_touch_button(index: int, activate: bool) -> void:
	var button: Button = _button_touches[index]
	_button_touches.erase(index)
	button.set_pressed_no_signal(false)
	button.button_up.emit()
	if not activate and button == _btn_use and _bow_equipped:
		var p := _get_player()
		if p != null and p.get_node_or_null("SurvivalEquipment") != null:
			p.get_node("SurvivalEquipment").call("cancel_draw")
	if activate and button.is_visible_in_tree() and not button.disabled:
		button.pressed.emit()
	queue_redraw()


func _input_blocked() -> bool:
	return _help_open or get_tree().paused or GameSettings.is_open \
			or (_hud_node() != null and _hud_node().is_blocking())


func reset_input() -> void:
	for index in _button_touches.keys():
		_release_touch_button(int(index), false)
	_move_id = -1
	_look_id = -1
	_stick = Vector2.ZERO
	_knob = _dock
	_release_all_actions()
	var p := _get_player()
	if p != null:
		p.call("reset_look_input")
		var equipment := p.get_node_or_null("SurvivalEquipment")
		if equipment != null:
			equipment.call("set_aiming", false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_input()


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
		var adjusted := rel * (720.0/maxf(size.y,1.0))
		if GameSettings.invert_look:
			adjusted.y = -adjusted.y
		p.add_look_input(adjusted, look_sensitivity * GameSettings.look_speed)


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
			_release_action(a)
		return
	var v := _stick
	_set_move_action("move_forward", clampf(v.y, 0.0, 1.0))
	_set_move_action("move_back", clampf(-v.y, 0.0, 1.0))
	_set_move_action("move_left", clampf(-v.x, 0.0, 1.0))
	_set_move_action("move_right", clampf(v.x, 0.0, 1.0))


func _set_move_action(action: StringName, strength: float) -> void:
	if strength <= joystick_deadzone:
		_release_action(action)
	elif not Input.is_action_pressed(action) or not is_equal_approx(Input.get_action_strength(action), strength):
		Input.action_press(action, strength)
		_owned_actions[action] = true


func _release_all_actions() -> void:
	for action in _owned_actions.keys():
		_release_action(action)


# ============================================================
# BUTTONS (invisible, icon art drawn in _draw)
# ============================================================
func _build_buttons() -> void:
	_btn_jump = _make_button("jump")
	_btn_rope = _make_button("hook")
	_btn_recall = _make_button("back")
	_btn_run = _make_button("run")
	_btn_use = _make_button("hand")
	_btn_aim = _make_button("aim")
	_btn_dive = _make_button("down")
	_btn_edit = _make_button("pencil")
	_btn_climb = _make_button("climb")
	_btn_build = _make_button("hammer")
	_btn_place = _make_button("check")
	_btn_rotate = _make_button("rot")
	_btn_next = _make_button("next")
	_btn_remove = _make_button("trash")
	_btn_help = _make_button("help")

	_all_buttons = [_btn_jump, _btn_rope, _btn_recall, _btn_run, _btn_use, _btn_aim, _btn_dive,
			_btn_climb, _btn_edit, _btn_build, _btn_place, _btn_rotate, _btn_next,
			_btn_remove, _btn_help]

	# Hold-style buttons: press the action on touch-down, release on touch-up.
	_btn_jump.button_down.connect(_press_action.bind("jump"))
	_btn_jump.button_up.connect(_release_action.bind("jump"))
	_btn_rope.button_down.connect(_on_cast_down)
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
	_btn_recall.button_down.connect(_request_rope_return)
	_btn_recall.button_up.connect(_release_action.bind("rope_cancel"))

	# Tap-style: USE is momentary (like pressing E), EDIT picks the aimed piece,
	# CLIMB boards the raft directly (same as E while swimming next to it).
	_btn_use.button_down.connect(_on_use_down)
	_btn_use.button_up.connect(_release_action.bind("interact"))
	_btn_aim.pressed.connect(_on_aim_pressed)
	_btn_edit.pressed.connect(_on_edit_pressed)
	_btn_climb.pressed.connect(_on_climb_pressed)
	_btn_help.pressed.connect(_toggle_help)

	for b in _all_buttons:
		add_child(b)
		b.pressed.connect(_queue_redraw)
		b.button_down.connect(_queue_redraw)
		b.button_up.connect(_queue_redraw)
	_sync_mode()


func _queue_redraw() -> void:
	queue_redraw()

func _on_cast_down() -> void:
	var p := _get_player()
	if visible and not _input_blocked() and p != null and p.get("rope_gun_selected") == true:
		_press_action("rope_throw")

func _on_use_down() -> void:
	_press_action("interact")
	var p := _get_player()
	if p != null and p.get("active_item") == "Bow" and visible and not _input_blocked():
		# Start the dedicated mobile draw at touch-down, even between physics
		# ticks. begin_draw ignores the subsequent keyboard/action poll.
		p.get_node("SurvivalEquipment").call("begin_draw")


func _press_action(action: StringName) -> void:
	if visible and not _input_blocked():
		Input.action_press(action)
		_owned_actions[action] = true


func _release_action(action: StringName) -> void:
	if _owned_actions.has(action):
		Input.action_release(action)
		_owned_actions.erase(action)

func _request_rope_return() -> void:
	if not visible or _input_blocked(): return
	_press_action(&"rope_cancel")
	var actor := _get_player()
	if actor != null and actor.get_node_or_null("RopeSystem") != null:
		actor.get_node("RopeSystem").call("request_return")


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
func _on_aim_pressed() -> void:
	var p := _get_player()
	if p != null and not _input_blocked():
		var equipment := p.get_node_or_null("SurvivalEquipment")
		if equipment != null:
			equipment.call("toggle_aim")
	queue_redraw()

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
		var c: Node = p.get("aim_collider") if is_instance_valid(p.get("aim_collider")) else null
		if c != null and p.has_method("_find_editable_target"):
			can_edit = p.call("_find_editable_target", c) != null
	var can_interact := false
	if mode == "normal" and p != null and p.has_method("can_interact_now"):
		can_interact = bool(p.call("can_interact_now"))
	var can_climb := false
	if mode == "normal" and swimming and p != null and p.has_method("can_climb_out"):
		can_climb = bool(p.call("can_climb_out"))

	var use_caption := str(p.call("interaction_caption")) if p != null and p.has_method("interaction_caption") else "USE"
	var moving := _move_id != -1
	var rope_equipped: bool = p != null and p.get("rope_gun_selected") == true
	var bow_equipped: bool = p != null and p.get("active_item") == "Bow"
	var can_build: bool = mode != "normal"
	if p != null:
		var raft := get_tree().get_first_node_in_group("raft") as Node3D
		can_build = can_build or (raft != null and (p as Node3D).global_position.distance_to(raft.global_position) <= 9.0)
		can_build = can_build or (can_edit and float(p.get("aim_distance")) <= 5.0)
	if mode == _mode and rope_busy == _rope_busy and swimming == _swimming \
			and can_edit == _can_edit and can_interact == _can_interact and can_climb == _can_climb \
			and moving == _moving and rope_equipped == _rope_equipped and bow_equipped == _bow_equipped and can_build == _can_build and use_caption == _use_caption:
		return
	_use_caption = use_caption
	_moving = moving
	_rope_equipped = rope_equipped
	_bow_equipped = bow_equipped
	_can_build = can_build
	_mode = mode
	_rope_busy = rope_busy
	_swimming = swimming
	_can_edit = can_edit
	_can_interact = can_interact
	_can_climb = can_climb

	var normal: bool = mode == "normal"
	_btn_jump.visible = normal
	_btn_run.visible = normal and moving
	# The HAND button only appears when the center crosshair is actually over
	# an interactable (debris / door / usable piece) — same logic as the E key.
	_btn_use.visible = normal and can_interact and not can_climb and use_caption not in ["GROWING","READY",""]
	_btn_aim.visible = normal and bow_equipped
	_btn_dive.visible = normal and swimming
	# CLIMB appears ONLY while swimming right next to the raft/foundation
	# (same test as the E key) — never on land, never in open water.
	_btn_climb.visible = normal and can_climb
	_btn_rope.visible = normal and rope_equipped and not rope_busy
	_btn_recall.visible = normal and rope_busy
	_btn_edit.visible = normal and can_edit
	_btn_place.visible = mode != "normal"
	_btn_rotate.visible = mode != "normal"
	_btn_next.visible = mode == "build"
	_btn_remove.visible = mode == "edit"
	# Help is available in every mode.
	_btn_build.visible = can_build
	_btn_help.visible = true
	for index in _button_touches.keys():
		var held: Button = _button_touches[index]
		if not held.visible:
			_release_touch_button(int(index), false)

	# If a hold-style button vanished while held (e.g. the target moved away
	# from the crosshair mid-press), release its action so it never sticks.
	if not _btn_use.visible:
		_release_action("interact")
	if not _btn_rope.visible:
		_release_action("rope_throw")
	if not _btn_run.visible:
		_release_action("sprint")

	queue_redraw()


# ============================================================
# LAYOUT — right-edge cluster; everything scales with the viewport.
# ============================================================
func _layout() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0: return
	var scale_factor := clampf(vp.y / 720.0, 0.72, 1.35)
	var margin := 24.0 * scale_factor
	var gap := 16.0 * scale_factor
	var primary := 112.0 * scale_factor
	var secondary := 88.0 * scale_factor
	var utility := 76.0 * scale_factor
	var right := vp.x - margin
	var bottom := vp.y - margin
	var action_top := bottom - primary - secondary - gap * 3.0
	var action_x := right - primary
	var inner_x := action_x - gap - primary
	var jr := _joy_radius()
	_dock = Vector2(margin + jr, bottom - jr)
	# Main thumb actions sit above the quick slots, with a consistent jump
	# position. Secondary actions have independent, non-overlapping targets.
	_btn_jump.position = Vector2(right-secondary,bottom-secondary)
	_btn_jump.size = Vector2.ONE*secondary
	_btn_rope.position = Vector2(action_x,action_top)
	_btn_rope.size = Vector2.ONE*primary
	_btn_place.position = _btn_rope.position
	_btn_place.size = _btn_rope.size
	_btn_use.position = Vector2(margin+utility+gap,minf(vp.y*0.42,action_top))
	_btn_use.size = Vector2.ONE*(primary+12.0*scale_factor)
	_btn_climb.position = _btn_use.position
	_btn_climb.size = _btn_use.size
	_btn_recall.position = _btn_rope.position
	_btn_recall.size = _btn_rope.size
	_btn_aim.position = Vector2(inner_x,action_top-gap-secondary)
	_btn_aim.size = Vector2.ONE*secondary
	_btn_edit.position = Vector2(inner_x-gap-utility,action_top)
	_btn_edit.size = Vector2.ONE*utility
	_btn_dive.position = Vector2(right-secondary-gap-utility,bottom-utility)
	_btn_dive.size = Vector2.ONE*utility
	_btn_run.position = Vector2(margin,_dock.y-jr-gap-utility)
	_btn_run.size = Vector2.ONE*utility
	_btn_rotate.position = Vector2(inner_x,action_top)
	_btn_rotate.size = Vector2.ONE*secondary
	_btn_next.position = Vector2(inner_x,action_top+secondary+gap)
	_btn_next.size = Vector2.ONE*secondary
	_btn_remove.position = Vector2(right-secondary,bottom-secondary)
	_btn_remove.size = Vector2.ONE*secondary
	var utility_y := minf(vp.y*0.42,_btn_run.position.y-gap-utility)
	_btn_build.position = Vector2(margin,utility_y)
	_btn_build.size = Vector2.ONE*utility
	_btn_help.position = Vector2(margin,utility_y-utility-gap)
	_btn_help.size = Vector2.ONE*utility
	queue_redraw()


# ============================================================
# ICON ART — every visible action button is painted here as a dark glassy
# circle with an original white vector glyph (reference-style).
# ============================================================
func _button_icon_kind(b: Button) -> String:
	var kind: String = str(b.get_meta("icon_kind", "?"))
	if b == _btn_run and _swimming:
		return "swim"
	if b == _btn_use and _bow_equipped:
		return "shoot"
	if b == _btn_use:
		if _use_caption in ["OPEN","CLOSE"]:return "door"
		if _use_caption in ["EAT","DRINK","COLLECT WATER","FILTER WATER","WATER"]:return "meal" if _use_caption=="EAT" else "water"
		if _use_caption in ["PLANT","HARVEST","CLEAR","COLLECT"]:return "hand"
		if _use_caption in ["COOK","COOKING","COOK / COLLECT"]:return "cook"
		if _use_caption.begins_with("LIGHT"):return "light"
	if b == _btn_build:
		# The build toggle morphs with its mode: hammer = enter, X = exit/cancel.
		kind = "x" if (_mode == "build" or _mode == "edit") else "hammer"
	return kind


func _draw() -> void:
	if not visible or _input_blocked():
		return
	var radius := _joy_radius()
	_draw_dpad(_base if _move_id != -1 else _dock, radius, _knob if _move_id != -1 else _dock)

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
	var ring: Color = UI_SURFACE.BRASS
	if b == _btn_rope and _rope_equipped:
		ring = Color(0.53, 0.85, 0.76, 0.95)
	if _button_icon_kind(b) == "hammer" and _mode == "normal":
		ring = Color(0.55, 0.9, 0.5, 0.5)
	elif _button_icon_kind(b) == "x":
		ring = Color(0.95, 0.4, 0.35, 0.5)
	elif _button_icon_kind(b) == "check":
		ring = Color(0.4, 0.95, 0.6, 0.5)
	elif _button_icon_kind(b) == "climb":
		ring = Color(0.4, 0.85, 0.95, 0.6)
	UI_SURFACE.dial(self, center, r * 0.92, ring, pressed)
	var col := Color(1, 1, 1, 0.92) if not pressed else Color(1, 1, 1, 1.0)
	_draw_icon_glyph(b, center - Vector2(0, r * 0.09), r * 0.48, col)
	var label := _button_caption(b)
	var font := ThemeDB.fallback_font
	var fs := int(clampf(r * 0.32, 12.0, 18.0))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, center + Vector2(-width * 0.5, r * 0.64), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _button_caption(b: Button) -> String:
	if b == _btn_run and _swimming:
		return "FAST SWIM"
	if b == _btn_aim:
		var p := _get_player()
		var equipment := p.get_node_or_null("SurvivalEquipment") if p != null else null
		return "UN-AIM" if equipment != null and equipment.get("aiming") else "AIM"
	if b == _btn_use:
		var player := _get_player()
		if player != null and player.has_method("interaction_caption"):
			return str(player.call("interaction_caption"))
	var captions := {"jump": "JUMP", "run": "RUN", "hand": "USE", "down": "DIVE", "hook": "CAST", "back": "RETURN", "climb": "CLIMB", "hammer": "BUILD", "x": "CANCEL", "check": "PLACE", "rot": "ROTATE", "next": "NEXT", "pencil": "EDIT", "trash": "REMOVE", "help": "HELP"}
	return str(captions.get(_button_icon_kind(b), "USE"))


func _draw_icon_glyph(b: Button, center: Vector2, r: float, col: Color) -> void:
	var w := clampf(r * 0.26, 3.0, 7.0)
	var kind := _button_icon_kind(b)
	match kind:
		"aim":
			draw_arc(center, r * 0.65, 0.0, TAU, 24, col, maxf(w * 0.4, 1.0), true)
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + direction * r * 0.45, center + direction * r, col, maxf(w * 0.4, 1.0), true)
		"shoot":
			Icons.item_icon(self, "Bow", center, r * 1.35)
		"jump":
			Icons.jump(self, center, r, w*0.65, col)
		"door":
			Icons.door(self,center,r,w,col)
		"meal","cook":
			Icons.meal(self,center,r,w,col)
		"water":
			Icons.status_icon(self,"thirst",center,r,col)
		"light":
			Icons.item_icon(self,"Torch",center,r)
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
		"swim":
			Icons.swim(self, center, r, w * 0.7, col)
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
			Icons.item_icon(self, "Rope Gun", center, r * 1.65)
		"hammer":
			Icons.hammer(self, center, r, w, col)
		"pencil":
			Icons.pencil(self, center, r, w, col)
		"trash":
			Icons.trash(self, center, r, w, col)
		"rot":
			Icons.rotate(self, center, r, w, col)
		"help":
			var font := ThemeDB.fallback_font
			var fs := int(r * 1.35)
			var sz := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, center + Vector2(-sz.x * 0.5, sz.y * 0.5), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		_:
			Icons.check(self, center, r, w, col)


# ============================================================
# DEBUG DRAW — D-pad joystick: transparent base ring, four directional
# arrows pointing toward the central thumbstick (reference style).
# ============================================================
func _draw_dpad(center: Vector2, radius: float, knob_pos: Vector2) -> void:
	# Transparent base plate.
	UI_SURFACE.dial(self, center, radius, Color(0.66, 0.63, 0.48, 0.45))
	draw_arc(center, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 1.5)
	# Four directional arrows pointing toward the central thumbstick.
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for dir in dirs:
		_draw_inward_arrow(center, dir, radius)
	# Central thumbstick (moves with the touch).
	var knob_r := clampf(radius * 0.34, 22.0, 44.0)
	UI_SURFACE.dial(self, knob_pos, knob_r, UI_SURFACE.BRASS, _move_id != -1)


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


# ============================================================
# HELP PANEL — the "?" button opens an in-game controls guide
# ============================================================
const HELP_CONTENT := "[center][b]GAME CONTROLS[/b][/center]\n\n" \
	+ "[b]BIRD HUNTING[/b]\nCraft a Bow and Arrows in BAG → CRAFT. Move the Bow to a hotbar slot and select it; Arrows can stay in the bag. Tap AIM to zoom, drag the view to line up a bird, then hold SHOOT to draw and release to fire. Lead moving birds and aim slightly above distant ones. Tap UN-AIM to return to normal view. Collect the bird where it lands and cook Raw Bird on a bonfire.\n\n" \
	+ "[b]MOVE[/b]\nJoystick (bottom-left) = walk. Big button = jump / swim up. Hold RUN to sprint; in water it becomes FAST SWIM (3.5 m/s). Release to swim normally. Fast swimming uses stamina.\n\n" \
	+ "[b]DIVING[/b]\nCraft the Handmade Air Tank on the first CRAFT page, select it and tap EQUIP. It supplies 3 minutes of underwater air. Look up/down while moving forward to swim; hold DIVE to descend and JUMP to rise. Surface before breath runs out. With empty hands on dry ground or your raft, tap REFILL AIR and stay still for 6 seconds. Aim a spear at fish, crabs, turtles or rays and tap HUNT; the hit happens during the thrust. Aim at the seabed to collect sand, or use a shovel. Diving sites appear on MAP, where your cyan arrow shows your location and facing direction. Sharks only make rare attacks from level 6.\n\n" \
	+ "[b]USE / HAND[/b] (tap or hold)\nCollect debris and open doors. Farming: hold a potato, tomato, carrot, coconut or banana; aim at a suitable empty pot or dry island soil and tap PLANT. Aim away and tap EAT to eat it. Tap a ripe fruit to pick it. Hold on a potato to dig it, hold on a tree trunk to chop it, hold on a stump to remove it.\n\n" \
	+ "[b]BUILD[/b]\nHammer button (left) = enter/exit build mode. NEXT = choose piece (Wall, Roof, ... PlanterPot, PlanterBox, TreePot). Big PLACE button = put the green piece down. ROT = turn it.\n\n" \
	+ "[b]EDIT / REPAIR[/b]\nWhile aiming at your own piece, tap the pencil to lift it, then PLACE to set it down or the trash button to remove it (materials refunded).\n\n" \
	+ "[b]FARMING QUICK START[/b]\n1) BAG → CRAFT → select Plant Pot, Plant Bed or Tree Pot. Review HAVE / NEED, choose a spot, then PLACE. Gather Soil on higher island land if needed. 2) Exit build mode. Tap a crop in the bag, then HOLD TO PLANT, or select it in the hotbar. 3) Aim at the empty pot or dry island sand/soil and tap PLANT. Coconut and banana need a Tree Pot on the raft. 4) Water soil and wait for maturity. 5) Hold HARVEST on root crops; tap ripe tree fruit to pick it. The harvested produce can be eaten with USE / EAT or planted again.\n\n" \
	+ "[b]ROPE GUN[/b]\nSelect the gun in the first quick slot. Hold CAST to charge and release to launch. RETURN appears while the hook is out and brings back its catch. Empty casts also return automatically. Selecting another quick slot hides CAST. Your gun cannot be dropped, spent or lost; Rope stacks in the bag are crafting materials.\n\n" \
	+ "[b]BAG[/b]\nTap the BAG button to open your 30-slot inventory; drag items to move/swap/merge them. Tap a hotbar slot to select that item.\n\n" \
	+ "[b]KEYBOARD (PC)[/b]\nWASD move · Space jump · Ctrl dive · E use · C craft · M map · B build · Tab next piece · P place · R/Y rotate · Delete remove · Q rope · F3 build overlay · F5 quick-save"


func _toggle_help() -> void:
	_set_help(not _help_open)


func _set_help(open: bool) -> void:
	if open == _help_open:
		return
	_help_open = open
	if open:
		_layout_help()
		GameSettings.release_gameplay_input()
	get_tree().paused = open
	if _help_ui != null:
		_help_ui.visible = open


func _build_help_panel() -> void:
	if _help_ui != null:
		return
	_help_ui = Control.new()
	_help_ui.name = "HelpPanel"
	_help_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_help_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_ui.visible = false
	# Sibling of this overlay on the same CanvasLayer, added LAST so the panel
	# draws above the survival HUD (clock/pills/bag).
	var canvas := get_parent()
	if canvas != null:
		canvas.add_child(_help_ui)

	_help_dim = Button.new()
	_help_dim.text = ""
	_help_dim.focus_mode = Control.FOCUS_NONE
	_help_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_help_dim.add_theme_stylebox_override(state, empty)
	_help_dim.pressed.connect(_set_help.bind(false))
	_help_ui.add_child(_help_dim)

	_help_panel = ColorRect.new()
	_help_panel.color = Color(0.09, 0.11, 0.15, 0.97)
	_help_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_ui.add_child(_help_panel)

	_help_close = Button.new()
	_help_close.text = "✕"
	_help_close.focus_mode = Control.FOCUS_NONE
	_help_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_close.pressed.connect(_set_help.bind(false))
	_help_ui.add_child(_help_close)

	_help_text = RichTextLabel.new()
	_help_text.bbcode_enabled = true
	_help_text.text = HELP_CONTENT
	_help_text.scroll_active = true
	_help_text.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_ui.add_child(_help_text)


func _layout_help() -> void:
	if _help_ui == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_help_ui.position = Vector2.ZERO
	_help_ui.size = vp
	_help_dim.position = Vector2.ZERO
	_help_dim.size = vp
	var panel_w := minf(vp.x * 0.9, 720.0)
	var panel_h := minf(vp.y * 0.86, 780.0)
	_help_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)
	_help_panel.size = Vector2(panel_w, panel_h)
	var pad_x := panel_w * 0.045
	var pad_y := panel_h * 0.028
	var fs := clampi(int(panel_h * 0.024), 14, 20)
	_help_text.add_theme_font_size_override("normal_font_size", fs)
	var close_s := fs * 2.6
	var top_off := pad_y + close_s * 1.4
	_help_text.position = _help_panel.position + Vector2(pad_x, top_off)
	_help_text.size = Vector2(panel_w - pad_x * 2.0, panel_h - top_off - pad_y)
	_help_close.position = _help_panel.position + Vector2(panel_w - pad_x - close_s, pad_y)
	_help_close.size = Vector2(close_s, close_s)
	_help_close.add_theme_font_size_override("font_size", int(fs * 1.3))
