extends Node3D
class_name RopeSystem

const ROPE_VISUAL := preload("res://scripts/rope_launcher_visual.gd")
const CONTACT_AUDIO := preload("res://scripts/contact_audio.gd")

## Ocean-survival hook + rope system.
## Q = charge & throw hook toward the crosshair. Right-click (rope_cancel) = recall.
## Fully automatic after the throw:
##   - hook lands ON the water (never sails over it) and keeps checking for debris;
##   - the metal head must touch a piece to catch it;
##   - with a catch  -> hook pauses ~0.4 s, then reels itself back to the hand;
##   - nothing caught -> hook waits ~0.8 s for drift-ins, then RETURNS BY ITSELF fast;
##   - recall anytime: pulls the hook and its catch back; build/edit releases it.

# ============================================================
# STATE MACHINE
# ============================================================
enum State { IDLE, THROWING, EXTENDED, HOOKED, REELING, RETURNING }

var _state: int = State.IDLE

# ============================================================
# EXPORTS
# ============================================================
@export var max_hook_distance: float = 60.0
@export var quick_cast_distance: float = 20.0
@export var charge_speed: float = 50.0
@export var throw_speed: float = 42.0
@export var hook_gravity: float = 9.81
@export var reel_speed: float = 6.0
@export var return_speed: float = 45.0
@export var debris_hook_radius: float = 0.20
@export var collection_radius: float = 1.5
## How long the hook rests when nothing is hooked before auto-returning.
@export var empty_wait_time: float = 0.8
## How long the head settles at its contact before auto-reeling it in.
@export var hook_pause_time: float = 0.25

# ============================================================
# NODES
# ============================================================
var player: Node3D = null
var camera: Camera3D = null

var _hook: Node3D = null
var _hook_origin: Node3D = null
var _rope_mesh: MeshInstance3D = null
var _rope_material: ShaderMaterial = null
var _rope_geometry: ImmediateMesh = null
var _aim_ray: RayCast3D = null
var _charge_bar: ColorRect = null
var _charge_label: Label = null

# ============================================================
# STATE — all world-space, immutable after throw
# ============================================================
var _throw_direction: Vector3 = Vector3.FORWARD
var _throw_start: Vector3 = Vector3.ZERO
var _throw_dist: float = 0.0
var _throw_end := Vector3.ZERO
var _flight_duration := 0.5
var _launch_velocity := Vector3.ZERO
var _launch_kick := 0.0
var _hook_world_pos: Vector3 = Vector3.ZERO
var _hook_travelled: float = 0.0
var _state_timer: float = 0.0

## Every piece captured by the current throw (one hook can scoop several).
var _hooked_debris: Array[RigidBody3D] = []
var _collected: bool = false
var _is_charging: bool = false
var _charge_distance: float = 0.0
var _catch_offset := Vector3.ZERO
var _seen_catches: Dictionary = {}
var _return_requested := false
var _contact_audio: Array[AudioStreamPlayer3D]=[]
var _contact_audio_index:=0


# ============================================================
# INIT
# ============================================================
func _ready() -> void:
	_ensure_actions()
	_create_hook_origin()
	_create_hook()
	_create_rope_mesh()
	_create_charge_bar()
	_create_aim_ray()
	for index in 3:
		var audio:=AudioStreamPlayer3D.new();audio.name="RopeContactAudio%d"%index
		audio.top_level=true;audio.unit_size=3.0;audio.max_distance=45.0;audio.volume_db=-12
		add_child(audio);_contact_audio.append(audio)

func _play_rope_sound(stream: AudioStream, at: Vector3, level_db: float=-12.0) -> void:
	if stream==null or _contact_audio.is_empty():return
	var audio:=_contact_audio[_contact_audio_index]
	_contact_audio_index=(_contact_audio_index+1)%_contact_audio.size()
	audio.global_position=at;audio.stream=stream;audio.volume_db=level_db;audio.play()


func _ensure_actions() -> void:
	if not InputMap.has_action("rope_throw"):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_Q
		InputMap.add_action("rope_throw")
		InputMap.action_add_event("rope_throw", ev)
	if not InputMap.has_action("rope_pull"):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.add_action("rope_pull")
		InputMap.action_add_event("rope_pull", ev)
	if not InputMap.has_action("rope_cancel"):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.add_action("rope_cancel")
		InputMap.action_add_event("rope_cancel", ev)


func _create_hook_origin() -> void:
	_hook_origin = Node3D.new()
	_hook_origin.name = "HookOrigin"
	add_child(_hook_origin)


func _create_hook() -> void:
	_hook = ROPE_VISUAL.create_hook()
	_hook.visible = false
	_hook.top_level = true
	add_child(_hook)

func _create_rope_mesh() -> void:
	_rope_mesh = MeshInstance3D.new()
	_rope_mesh.name = "RopeMesh"
	_rope_geometry = ImmediateMesh.new()
	_rope_mesh.mesh = _rope_geometry
	_rope_material = ShaderMaterial.new()
	_rope_material.shader = preload("res://shaders/rope_fiber.gdshader")
	_rope_mesh.material_override = _rope_material
	_rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_mesh.visible = false
	_rope_mesh.top_level = true
	add_child(_rope_mesh)

func _create_charge_bar() -> void:
	_charge_bar = ColorRect.new()
	_charge_bar.color = Color(0.9, 0.8, 0.2, 0.75)
	_charge_bar.visible = false
	_charge_bar.size = Vector2(0, 6)
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_label = Label.new()
	_charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_label.add_theme_font_size_override("font_size", 17)
	_charge_label.position = Vector2(-55, -27)
	_charge_label.size = Vector2(310, 24)
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_bar.add_child(_charge_label)
	add_child(_charge_bar)


func _create_aim_ray() -> void:
	_aim_ray = RayCast3D.new()
	_aim_ray.target_position = Vector3(0, 0, -max_hook_distance)
	_aim_ray.collision_mask = 3
	add_child(_aim_ray)


# ============================================================
# HELPERS
# ============================================================
## Aim point: real raycast hit (raft/debris), otherwise the point where the
## crosshair ray crosses the OCEAN SURFACE. Without this the hook used to fly
## straight at eye height and never reach the water where debris float.
func _get_aim_point() -> Vector3:
	if camera == null:
		return _hook_origin.global_position + Vector3(0, 0, -10)
	if player != null:
		_aim_ray.add_exception(player)
	_aim_ray.global_position = camera.global_position
	_aim_ray.global_rotation = camera.global_rotation
	_aim_ray.target_position = Vector3(0, 0, -max_hook_distance)
	_aim_ray.force_raycast_update()
	if _aim_ray.is_colliding():
		return _aim_ray.get_collision_point()

	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var water_y := _get_ocean_y(origin) + 0.15
	if dir.y < -0.001:
		var t := (water_y - origin.y) / dir.y
		if t > 1.0 and t <= max_hook_distance:
			return origin + dir * t
	return origin + dir * max_hook_distance


func _hand_pos() -> Vector3:
	return _hook_origin.global_position


func _get_ocean_y(pos: Vector3) -> float:
	if player == null:
		return 0.0
	var oc = player.get("ocean")
	if oc != null:
		return float(oc.get_height(pos))
	return 0.0


func _is_build_active() -> bool:
	if player == null:
		return false
	var bm = player.get("build_mode")
	return bm != null and bool(bm)


func _is_editing_active() -> bool:
	if player == null:
		return false
	return player.get("_editing") != null


func can_cast_from_raft() -> bool:
	if not is_instance_valid(player) or player.get("is_swimming") == true or is_instance_valid(player.get("boat_vehicle")):
		return false
	var raft := get_tree().get_first_node_in_group("raft") as Node3D
	if raft == null:
		return false
	# Check actual support, including constructed upper decks. Proximity to the
	# raft also includes swimmers beside it and island ground, so is insufficient.
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.1,
		player.global_position + Vector3.DOWN * 1.15, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var support := hit.get("collider") as Node
	return support != null and (support == raft or raft.is_ancestor_of(support))


# ============================================================
# PHYSICS — main update
# ============================================================
func _physics_process(delta: float) -> void:
	_launch_kick = move_toward(_launch_kick, 0.0, delta * 6.0)
	if player == null or camera == null:
		return

	# Block during build/edit
	var cargo:=player.get_node_or_null("HuntingCargo")
	var salvage:=player.get_node_or_null("OceanSalvage")
	var cargo_owns_hands: bool=(cargo!=null and (is_instance_valid(cargo.held) or cargo.busy())) or (salvage!=null and salvage.busy())
	if _is_build_active() or _is_editing_active() or not can_cast_from_raft() or cargo_owns_hands:
		if _state != State.IDLE or _is_charging:
			_force_cancel()
		return

	# Update hook origin (follows the player's hand)
	_update_hook_origin()
	# Keep a restrained two-hand reeling pose while the loaded spool is running.
	if _state == State.REELING and player.has_node("SurvivalAction"):
		var action:=player.get_node("SurvivalAction")
		if str(action.get("kind")) != "reel":player.call("play_action","reel",0.8)

	# State machine
	match _state:
		State.IDLE:
			_handle_idle(delta)
		State.THROWING:
			_handle_throwing(delta)
		State.EXTENDED:
			_handle_extended(delta)
		State.HOOKED:
			_handle_hooked(delta)
		State.REELING:
			_handle_reeling(delta)
		State.RETURNING:
			_handle_returning(delta)

	# Update visuals
	_update_hook_visual()
	_update_rope_visual()
	_update_charge_bar_ui()


# ============================================================
# HOOK ORIGIN — anchored at the hand, BELOW and to the RIGHT of the
# camera so the rope visibly comes from the player's hand, not the head.
# ============================================================
func _update_hook_origin() -> void:
	if player == null or camera == null:
		return
	if player.has_method("get_rope_launch_origin"):
		_hook_origin.global_position = player.call("get_rope_launch_origin")
	else:
		_hook_origin.global_position = camera.global_transform * Vector3(0.18, -0.22, -0.95)


func get_launcher_kick() -> float:
	return _launch_kick

# ============================================================
# STATE: IDLE
# ============================================================
func _handle_idle(delta: float) -> void:
	if not can_cast_from_raft():
		_cancel_charge()
		return
	if _take_return_request():
		_cancel_charge()
		return
	if Input.is_action_just_pressed("rope_throw"):
		if player != null and player.has_method("equip_rope_gun") and not bool(player.call("equip_rope_gun")):
			return
		_update_hook_origin()
		_is_charging = true
		_charge_distance = minf(quick_cast_distance, max_hook_distance)
	elif _is_charging and Input.is_action_pressed("rope_throw"):
		_charge_distance = minf(_charge_distance + charge_speed * delta, max_hook_distance)
	elif _is_charging and Input.is_action_just_released("rope_throw"):
		_throw_hook()


func _cancel_charge() -> void:
	_is_charging = false
	_charge_bar.visible = false


# ============================================================
# STATE: THROWING — hook flies along the locked direction, sampled in
# small sub-steps so debris between physics frames can never be skipped.
# ============================================================
func _handle_throwing(delta: float) -> void:
	if _take_return_request():
		_request_return()
		return
	var remaining := throw_speed * delta
	while remaining > 0.001 and _state == State.THROWING:
		var step := minf(remaining, 0.5)
		remaining -= step
		var previous := _hook_world_pos
		_hook_travelled += step
		_hook_world_pos = _flight_position(_hook_travelled)
		# Sweep every short ballistic segment, preventing walls/terrain tunnelling.
		var excluded: Array[RID] = []
		if player is CollisionObject3D:
			excluded.append((player as CollisionObject3D).get_rid())
		var ray := PhysicsRayQueryParameters3D.create(previous, _hook_world_pos, 1, excluded)
		var solid := get_world_3d().direct_space_state.intersect_ray(ray)
		if not solid.is_empty():
			_hook_world_pos = solid.position + solid.normal * 0.035
			_start_return()
			return
		_check_debris(previous)
		if not _hooked_debris.is_empty():
			_enter_hooked()
			return
		var water_y := _get_ocean_y(_hook_world_pos) + 0.15
		# Descending crossing uses the moving surface, rather than the launch-time wave.
		if (_hook_world_pos.y <= water_y and _hook_world_pos.y < previous.y) or _hook_travelled >= _throw_dist:
			_hook_world_pos.y = water_y
			_finish_flight()
			return


func _flight_position(distance_along: float) -> Vector3:
	var progress := clampf(distance_along / maxf(_throw_dist, 0.001), 0.0, 1.0)
	var elapsed := progress * _flight_duration
	return _throw_start + _launch_velocity * elapsed - Vector3.UP * (0.5 * hook_gravity * elapsed * elapsed)

func _finish_flight() -> void:
	_snap_hook_to_water()
	_check_debris()
	if _hooked_debris.is_empty():
		_play_rope_sound(CONTACT_AUDIO.pick_action("water"),_hook_world_pos,-16.0)
		_state = State.EXTENDED
	else:
		_enter_hooked()
	_state_timer = 0.0


# ============================================================
# STATE: EXTENDED — hook rests on the water, still hunting: any debris that
# drifts into range is hooked; otherwise it auto-returns after a short wait.
# ============================================================
func _handle_extended(delta: float) -> void:
	if _take_return_request():
		_request_return()
		return
	# Keep the hook riding the wave surface so its reach stays constant
	# (only when it actually landed on/near the water).
	var wy := _get_ocean_y(_hook_world_pos) + 0.2
	if _hook_world_pos.y - wy < 3.0:
		_hook_world_pos.y = lerpf(_hook_world_pos.y, wy, clampf(delta * 4.0, 0.0, 1.0))
	_state_timer += delta
	_check_debris()
	if not _hooked_debris.is_empty():
		_enter_hooked()
		return
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		# Manual reel before the auto-wait expires.
		_state = State.REELING
		_state_timer = 0.0
		return
	if _state_timer >= empty_wait_time:
		# Nothing caught — come back on our own, fast.
		_start_return()


# ============================================================
# STATE: HOOKED — preserve the contact, then tension and reel the line.
# ============================================================
func _handle_hooked(delta: float) -> void:
	_state_timer += delta
	_place_captured_chain(delta)
	if _take_return_request():
		_request_return()
		return
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		_play_rope_sound(CONTACT_AUDIO.pick_action("reel"),_hand_pos(),-15.0)
		_state = State.REELING
		_state_timer = 0.0
		return
	# Settle at the actual contact, then tension the line; no forward scooping.
	if _state_timer >= hook_pause_time:
		_play_rope_sound(CONTACT_AUDIO.pick_action("reel"),_hand_pos(),-15.0)
		_state = State.REELING
		_state_timer = 0.0


# ============================================================
# STATE: REELING — hook + captured pieces move toward the hand.
# Empty rope reels at the fast return speed; a loaded rope drags slowly.
# ============================================================
func _handle_reeling(delta: float) -> void:
	if _take_return_request():
		_request_return()
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	# Tow on the water, then lift the attached head/catch at the raft edge.
	var target := hand
	var horizontal := Vector2(to_hand.x,to_hand.z).length()
	if not _hooked_debris.is_empty() and horizontal > 2.5:
		target.y = _get_ocean_y(_hook_world_pos) + 0.15
	var speed := reel_speed if not _hooked_debris.is_empty() else return_speed
	_hook_world_pos = _hook_world_pos.move_toward(target, speed * delta)
	_hook_travelled = _throw_start.distance_to(_hook_world_pos)

	_place_captured_chain(delta)

	# Collect each trailed piece as it reaches the raft edge (the hook leads,
	# the catch trails behind it in the water — pieces come in one by one).
	var i := 0
	while i < _hooked_debris.size():
		var d: RigidBody3D = _hooked_debris[i]
		if is_instance_valid(d) and hand.distance_to(d.global_position) <= collection_radius:
			_collect_one(d)
			_hooked_debris.remove_at(i)
		elif not is_instance_valid(d):
			_hooked_debris.remove_at(i)
		else:
			i += 1

	if _hooked_debris.is_empty():
		_start_return()
		return

	# A large item's contact can reach the muzzle before its centre does.
	if dist <= 0.25:
		for d in _hooked_debris:
			if is_instance_valid(d):
				d.global_position = d.global_position.move_toward(hand, reel_speed * delta)


# ============================================================
# STATE: RETURNING — hook flies back to the hand (always fast; anything
# hooked was already released by _start_return / collected).
# ============================================================
func _handle_returning(delta: float) -> void:
	_return_requested = false
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	if dist <= 0.5:
		_hook.visible = false
		_rope_mesh.visible = false
		_state = State.IDLE
		_state_timer = 0.0
		return

	var dir := to_hand.normalized()
	_hook_world_pos += dir * minf(return_speed * delta, dist)


# ============================================================
# THROW — capture direction ONCE
# ============================================================
func _throw_hook() -> void:
	_is_charging = false
	_charge_bar.visible = false
	if not can_cast_from_raft():
		return
	_update_hook_origin()

	var aim_point := _get_aim_point()
	var hand := _hand_pos()
	var to_aim := aim_point - hand
	var aim_dist := to_aim.length()

	# LOCK direction — never recalculated
	if aim_dist > 0.001:
		_throw_direction = (to_aim / aim_dist).normalized()
	else:
		_throw_direction = -camera.global_transform.basis.z

	_throw_dist = clampf(_charge_distance, minf(quick_cast_distance, max_hook_distance), max_hook_distance)
	# If the aim point is nearer than the charge (e.g. raft edge in the way),
	# don't overshoot past it.
	if aim_dist > 1.0 and aim_dist < _throw_dist:
		_throw_dist = aim_dist
	_throw_start = hand
	_throw_end = hand + _throw_direction * _throw_dist
	# Resolve a real water landing instead of teleporting the hook down at range.
	_throw_end.y = _get_ocean_y(_throw_end) + 0.15
	_throw_dist = minf(hand.distance_to(_throw_end), max_hook_distance)
	_throw_direction = (_throw_end - hand).normalized()
	_throw_end = hand + _throw_direction * _throw_dist
	_flight_duration = maxf(0.18, _throw_dist / maxf(throw_speed, 1.0))
	_launch_velocity = (_throw_end - _throw_start) / _flight_duration + Vector3.UP * (0.5 * hook_gravity * _flight_duration)
	_launch_kick = 1.0
	if player.has_method("play_action"):player.call("play_action","hook",0.35)
	_hook_world_pos = hand
	_hook_travelled = 0.0
	_hooked_debris.clear()
	_seen_catches.clear()
	_collected = false
	_state_timer = 0.0

	_hook.visible = true
	_hook.global_position = hand
	_rope_mesh.visible = true
	_play_rope_sound(CONTACT_AUDIO.pick_action("swing"),hand,-15.0)
	_state = State.THROWING


# ============================================================
# DEBRIS DETECTION — sweep the head against fitted salvage bounds.
# Keep the nearest real contact; a grappling head carries one piece.
# ============================================================
func _check_debris(previous: Vector3 = Vector3.INF) -> void:
	if not _hooked_debris.is_empty(): return
	var start := _hook_world_pos if previous == Vector3.INF else previous
	var nearest: RigidBody3D
	var nearest_contact := Vector3.ZERO
	var nearest_distance := INF
	for d in get_tree().get_nodes_in_group("debris"):
		if not (d is RigidBody3D) or not is_instance_valid(d):
			continue
		if d.get("collected") == true:
			continue
		if d.get("is_hooked") == true:
			continue
		if _seen_catches.has(d.get_instance_id()) or d.is_queued_for_deletion():
			continue
		var contact := _debris_contact(d, start, _hook_world_pos)
		if contact != Vector3.INF and start.distance_squared_to(contact) < nearest_distance:
			nearest = d
			nearest_contact = contact
			nearest_distance = start.distance_squared_to(contact)
	if nearest != null:
		_hook_world_pos = nearest_contact
		_hook_debris(nearest)

func _debris_contact(debris: RigidBody3D, start: Vector3, end: Vector3) -> Vector3:
	var shape := debris.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is BoxShape3D and not shape.disabled:
		var inverse := shape.global_transform.affine_inverse()
		var a := inverse * start
		var b := inverse * end
		var scale_min := maxf(minf(shape.global_basis.x.length(), minf(shape.global_basis.y.length(),shape.global_basis.z.length())), 0.001)
		var half := (shape.shape as BoxShape3D).size * 0.5 + Vector3.ONE * (debris_hook_radius / scale_min)
		var low := 0.0
		var high := 1.0
		for axis in 3:
			var change := b[axis] - a[axis]
			if absf(change) < 0.00001:
				if absf(a[axis]) > half[axis]: return Vector3.INF
			else:
				var first := (-half[axis]-a[axis])/change
				var last := (half[axis]-a[axis])/change
				low = maxf(low,minf(first,last))
				high = minf(high,maxf(first,last))
				if low > high: return Vector3.INF
		return start.lerp(end,low)
	# Small test/custom pickups without a box still require real head contact.
	var closest := Geometry3D.get_closest_point_to_segment(debris.global_position,start,end)
	return closest if closest.distance_to(debris.global_position) <= debris_hook_radius else Vector3.INF


func _hook_debris(debris: RigidBody3D) -> void:
	debris.set("is_hooked", true)
	debris.freeze = true
	debris.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_hooked_debris.append(debris)
	_catch_offset = debris.global_position - _hook_world_pos
	_seen_catches[debris.get_instance_id()] = true
	_play_rope_sound(CONTACT_AUDIO.pick("metal"),_hook_world_pos,-13.0)


func _enter_hooked() -> void:
	_state = State.HOOKED
	_state_timer = 0.0


## Preserve the head's contact offset and bound all catch movement.
func _place_captured_chain(delta: float = 0.0) -> void:
	var n: int = _hooked_debris.size()
	for i in n:
		var d: RigidBody3D = _hooked_debris[i]
		if not is_instance_valid(d):
			continue
		var fb: float = 0.15
		var fbv = d.get("freeboard")
		if fbv != null:
			fb = float(fbv)
		var pos := _hook_world_pos + _catch_offset
		var water_y := _get_ocean_y(pos) + fb
		pos.y = maxf(pos.y,water_y) if _state == State.REELING else water_y
		d.global_position = d.global_position.move_toward(pos,reel_speed * delta)
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO


func _release_debris() -> void:
	for d in _hooked_debris:
		if is_instance_valid(d):
			d.freeze = false
			d.set("is_hooked", false)
	_hooked_debris.clear()


func _collect_one(d: RigidBody3D) -> void:
	var item_name: String = str(d.get("item_name"))
	if item_name.is_empty() or item_name == "null":
		d.set("is_hooked", false)
		d.freeze = false
		return
	var amount:=maxi(1,int(d.get("amount"))) if "amount" in d else 1
	var overflow:=Inventory.add(item_name,amount)
	if overflow<amount:
		Inventory.notify_pickup(Inventory.canonical_item(item_name),amount-overflow)
		_collected=true
	if overflow > 0:
		# Capacity can change while the rope reels in. Release the catch back to
		# the ocean instead of deleting it when the last slot has filled up.
		d.set("is_hooked", false)
		d.freeze = false
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO
		if overflow<amount:
			if d.has_method("set_pickup_amount"):d.call("set_pickup_amount",overflow)
			elif "amount" in d:d.set("amount",overflow)
		return
	d.set("collected", true)
	if d.has_method("get_pickup_id"):Inventory.mark_island_pickup_collected(str(d.call("get_pickup_id")))
	d.queue_free()
	_collected = true
	if player != null and player.has_method("play_action"):
		player.call("play_action","grab",0.65,d.global_position,item_name)


func _snap_hook_to_water() -> void:
	var water_y := _get_ocean_y(_hook_world_pos)
	if _hook_world_pos.y > water_y + 1.0:
		_hook_world_pos.y = water_y + 0.2


func _start_return() -> void:
	_release_debris()
	_play_rope_sound(CONTACT_AUDIO.pick_action("reel"),_hand_pos(),-15.0)
	_state = State.RETURNING
	_state_timer = 0.0

func _request_return() -> void:
	_cancel_charge()
	if _state in [State.IDLE,State.RETURNING]: return
	if not _hooked_debris.is_empty():
		_state = State.REELING
		_state_timer = 0.0
	else:
		_start_return()

func request_return() -> void:
	# A short mobile tap may begin/end between physics updates. Keep it queued.
	_return_requested = true

func _take_return_request() -> bool:
	var requested := _return_requested or Input.is_action_pressed("rope_cancel")
	_return_requested = false
	return requested


# Convenience for the mobile UI (MobileControls shows Return while
# the rope is out).
func is_active() -> bool:
	return _state != State.IDLE


func _force_cancel() -> void:
	for audio in _contact_audio:audio.stop()
	_return_requested = false
	_release_debris()
	_hook.visible = false
	_rope_mesh.visible = false
	_hooked_debris.clear()
	_seen_catches.clear()
	_collected = false
	_is_charging = false
	_charge_bar.visible = false
	_state = State.IDLE
	_state_timer = 0.0


# ============================================================
# VISUALS — hook + rope
# ============================================================
func _update_hook_visual() -> void:
	if _state == State.IDLE:
		_hook.visible = false
		return
	_hook.visible = true
	_hook.global_position = _hook_world_pos
	var elapsed := clampf(_hook_travelled / maxf(_throw_dist,0.001),0.0,1.0) * _flight_duration
	# Ballistic tangent going out, tail-first on the taut returning line.
	var toward := _launch_velocity - Vector3.UP * hook_gravity * elapsed if _state == State.THROWING else _hook_world_pos - _hand_pos()
	if toward.length_squared() > 0.001:
		var direction := toward.normalized()
		var right := _hook.global_basis.x - direction * _hook.global_basis.x.dot(direction)
		if right.length_squared() < 0.0001:
			right = direction.cross(Vector3.RIGHT if absf(direction.y)>0.95 else Vector3.UP)
		right = right.normalized()
		_hook.global_basis = Basis(right,right.cross(direction).normalized(),-direction)


func _update_rope_visual() -> void:
	if _state == State.IDLE:
		_rope_mesh.visible = false
		return
	var from := _hand_pos()
	var to := _hook_world_pos
	var length := from.distance_to(to)
	if length < 0.1:
		_rope_mesh.visible = false
		return
	_rope_mesh.visible = true
	# Twelve short tube segments make the line sag naturally. A single reused
	# mesh/material keeps this independent of cast distance on phones.
	var segments := 12
	var sides := 6
	var direction := (to - from).normalized()
	var right := direction.cross(Vector3.RIGHT if absf(direction.y) > 0.95 else Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	var sag := minf(0.7, length * 0.02) if _state in [State.THROWING, State.EXTENDED] else minf(0.12, length * 0.004)
	_rope_geometry.clear_surfaces()
	_rope_geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(segments):
		var t0 := float(segment) / segments
		var t1 := float(segment + 1) / segments
		var p0 := from.lerp(to, t0) - Vector3.UP * sin(t0 * PI) * sag
		var p1 := from.lerp(to, t1) - Vector3.UP * sin(t1 * PI) * sag
		for side in range(sides):
			var a := TAU * float(side) / sides
			var b := TAU * float(side + 1) / sides
			var na := right * cos(a) + up * sin(a)
			var nb := right * cos(b) + up * sin(b)
			var vertices := [p0 + na * 0.011, p1 + nb * 0.011, p1 + na * 0.011, p0 + na * 0.011, p0 + nb * 0.011, p1 + nb * 0.011]
			for index in range(6):
				var at_end: bool = index in [1, 2, 5]
				var at_next_side: bool = index in [1, 4, 5]
				_rope_geometry.surface_set_normal(nb if at_next_side else na)
				_rope_geometry.surface_set_uv(Vector2(float(side + (1 if at_next_side else 0)) / sides, (t1 if at_end else t0) * length))
				_rope_geometry.surface_add_vertex(vertices[index])
	_rope_geometry.surface_end()

func _update_charge_bar_ui() -> void:
	if _charge_bar == null:
		return
	if _is_charging:
		_charge_bar.visible = true
		var vp := get_viewport().get_visible_rect().size
		var bar_w := (_charge_distance / max_hook_distance) * 200.0
		_charge_bar.size = Vector2(bar_w, 6)
		_charge_bar.position = Vector2(vp.x * 0.5 - 100.0, vp.y * 0.5 + 40.0)
		_charge_label.text = "CAST %.0f m  ·  RELEASE TO FIRE" % _charge_distance
	else:
		_charge_bar.visible = false
