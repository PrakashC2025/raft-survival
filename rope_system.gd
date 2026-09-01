extends Node3D
class_name RopeSystem

## Ocean-survival hook + rope system.
## Q = throw hook toward crosshair aim. Q/F = reel. Right-click = cancel.
## Hook position LOCKED after throw — camera rotation does NOT move it.

# ============================================================
# STATE MACHINE
# ============================================================
enum State { IDLE, THROWING, EXTENDED, HOOKED, REELING, RETURNING }

var _state: int = State.IDLE

# ============================================================
# EXPORTS
# ============================================================
@export var max_hook_distance: float = 22.0
@export var throw_speed: float = 22.0
@export var reel_speed: float = 12.0
@export var return_speed: float = 20.0
@export var debris_hook_radius: float = 1.5
@export var collection_radius: float = 1.5

# ============================================================
# NODES
# ============================================================
var player: Node3D = null
var camera: Camera3D = null

var _hook: MeshInstance3D = null
var _hook_origin: Node3D = null
var _rope_mesh: MeshInstance3D = null
var _rope_material: StandardMaterial3D = null
var _aim_ray: RayCast3D = null
var _charge_bar: ColorRect = null

# ============================================================
# STATE — all world-space, immutable after throw
# ============================================================
var _throw_direction: Vector3 = Vector3.FORWARD
var _throw_start: Vector3 = Vector3.ZERO
var _throw_dist: float = 0.0
var _hook_world_pos: Vector3 = Vector3.ZERO
var _hook_travelled: float = 0.0
var _hooked_debris: RigidBody3D = null
var _collected: bool = false
var _is_charging: bool = false
var _charge_distance: float = 0.0
var _charge_speed: float = 30.0

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
	_hook = MeshInstance3D.new()
	_hook.name = "Hook"
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	_hook.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.8, 0.2) * 0.3
	_hook.material_override = mat
	_hook.visible = false
	add_child(_hook)


func _create_rope_mesh() -> void:
	_rope_mesh = MeshInstance3D.new()
	_rope_mesh.name = "RopeMesh"
	_rope_material = StandardMaterial3D.new()
	_rope_material.albedo_color = Color(0.7, 0.6, 0.3)
	_rope_material.no_depth_test = false
	_rope_mesh.material_override = _rope_material
	_rope_mesh.visible = false
	add_child(_rope_mesh)


func _create_charge_bar() -> void:
	_charge_bar = ColorRect.new()
	_charge_bar.color = Color(0.9, 0.8, 0.2, 0.75)
	_charge_bar.visible = false
	_charge_bar.size = Vector2(0, 5)
	add_child(_charge_bar)


func _create_aim_ray() -> void:
	_aim_ray = RayCast3D.new()
	_aim_ray.target_position = Vector3(0, 0, -max_hook_distance)
	_aim_ray.collision_mask = 3
	add_child(_aim_ray)


# ============================================================
# HELPERS
# ============================================================
func _get_aim_point() -> Vector3:
	if camera == null:
		return _hook_origin.global_position + Vector3(0, 0, -10)
	if player != null:
		_aim_ray.add_exception(player)
	_aim_ray.global_position = camera.global_position
	_aim_ray.global_rotation = camera.global_rotation
	_aim_ray.force_raycast_update()
	if _aim_ray.is_colliding():
		return _aim_ray.get_collision_point()
	return camera.global_position + (-camera.global_transform.basis.z * max_hook_distance)


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
	return bool(player.get("build_mode"))


func _is_editing_active() -> bool:
	if player == null:
		return false
	return player.get("_editing") != null


# ============================================================
# PHYSICS — main update
# ============================================================
func _physics_process(delta: float) -> void:
	if player == null or camera == null:
		return

	# Block during build/edit
	if _is_build_active() or _is_editing_active():
		if _state != State.IDLE:
			_force_cancel()
		return

	# Update hook origin (follows player hand)
	_update_hook_origin()

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
# HOOK ORIGIN — follows player hand (right side, chest height)
# ============================================================
func _update_hook_origin() -> void:
	if player == null:
		return
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	_hook_origin.global_position = player.global_position + right * 0.4 + forward * 0.3 + Vector3(0, 0.8, 0)


# ============================================================
# STATE: IDLE
# ============================================================
func _handle_idle(delta: float) -> void:
	if Input.is_action_just_pressed("rope_throw"):
		_is_charging = true
		_charge_distance = 5.0
	elif _is_charging and Input.is_action_pressed("rope_throw"):
		_charge_distance = min(_charge_distance + _charge_speed * delta, max_hook_distance)
	elif _is_charging and Input.is_action_just_released("rope_throw"):
		_throw_hook()


# ============================================================
# STATE: THROWING — hook flies along locked direction
# ============================================================
func _handle_throwing(delta: float) -> void:
	var step := throw_speed * delta
	var new_dist := _hook_travelled + step

	if new_dist >= _throw_dist:
		# Reached max — snap to end
		_hook_world_pos = _throw_start + _throw_direction * _throw_dist
		_hook_travelled = _throw_dist
		_snap_hook_to_water()
		_check_debris()
		if _hooked_debris != null:
			_state = State.HOOKED
		else:
			_state = State.EXTENDED
	else:
		_hook_travelled = new_dist
		_hook_world_pos = _throw_start + _throw_direction * new_dist
		# Check for debris during flight
		_check_debris()
		if _hooked_debris != null:
			_state = State.HOOKED


# ============================================================
# STATE: EXTENDED — hook is at target, waiting
# ============================================================
func _handle_extended(_delta: float) -> void:
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		_state = State.REELING
	elif Input.is_action_just_pressed("rope_cancel"):
		_start_return()


# ============================================================
# STATE: HOOKED — debris attached, waiting for reel
# ============================================================
func _handle_hooked(_delta: float) -> void:
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		_state = State.REELING
	elif Input.is_action_just_pressed("rope_cancel"):
		_release_debris()
		_start_return()


# ============================================================
# STATE: REELING — hook + debris move toward player
# ============================================================
func _handle_reeling(delta: float) -> void:
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	if dist <= collection_radius:
		_collect_debris()
		_start_return()
		return

	var dir := to_hand.normalized()
	_hook_world_pos += dir * reel_speed * delta
	_hook_travelled = _throw_start.distance_to(_hook_world_pos)

	# Move hooked debris with hook
	if _hooked_debris != null and is_instance_valid(_hooked_debris):
		_hooked_debris.global_position = _hook_world_pos + Vector3(0, 0.3, 0)
		_hooked_debris.linear_velocity = Vector3.ZERO


# ============================================================
# STATE: RETURNING — hook flies back to player
# ============================================================
func _handle_returning(delta: float) -> void:
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	if dist <= 0.5:
		_hook.visible = false
		_rope_mesh.visible = false
		_state = State.IDLE
		return

	var dir := to_hand.normalized()
	_hook_world_pos += dir * return_speed * delta


# ============================================================
# THROW — capture direction ONCE
# ============================================================
func _throw_hook() -> void:
	_is_charging = false
	_charge_bar.visible = false

	var aim_point := _get_aim_point()
	var hand := _hand_pos()
	var to_aim := aim_point - hand
	var aim_dist := to_aim.length()

	# LOCK direction — never recalculated
	if aim_dist > 0.001:
		_throw_direction = (to_aim / aim_dist).normalized()
	else:
		_throw_direction = -camera.global_transform.basis.z

	_throw_dist = minf(_charge_distance, max_hook_distance)
	_throw_start = hand
	_hook_world_pos = hand
	_hook_travelled = 0.0
	_hooked_debris = null
	_collected = false

	_hook.visible = true
	_hook.global_position = hand
	_rope_mesh.visible = true
	_state = State.THROWING


# ============================================================
# DEBRIS DETECTION — distance check
# ============================================================
func _check_debris() -> void:
	if _hooked_debris != null:
		return
	for d in get_tree().get_nodes_in_group("debris"):
		if d is RigidBody3D and is_instance_valid(d):
			if d.get("collected") == true:
				continue
			if d.global_position.distance_to(_hook_world_pos) <= debris_hook_radius:
				_hook_debris(d)
				return


func _hook_debris(debris: RigidBody3D) -> void:
	_hooked_debris = debris
	debris.set("is_hooked", true)
	debris.freeze = true
	debris.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func _release_debris() -> void:
	if _hooked_debris != null and is_instance_valid(_hooked_debris):
		_hooked_debris.freeze = false
		_hooked_debris.set("is_hooked", false)
	_hooked_debris = null


func _collect_debris() -> void:
	if _hooked_debris == null or not is_instance_valid(_hooked_debris):
		_hooked_debris = null
		return
	if _collected:
		return
	_collected = true
	var item_name: String = str(_hooked_debris.get("item_name"))
	if item_name != "" and item_name != "null":
		_hooked_debris.set("collected", true)
		Inventory.add(item_name)
	_hooked_debris.queue_free()
	_hooked_debris = null


func _snap_hook_to_water() -> void:
	var water_y := _get_ocean_y(_hook_world_pos)
	if _hook_world_pos.y > water_y + 1.0:
		_hook_world_pos.y = water_y + 0.2


func _start_return() -> void:
	_release_debris()
	_state = State.RETURNING


func _force_cancel() -> void:
	_release_debris()
	_hook.visible = false
	_rope_mesh.visible = false
	_hooked_debris = null
	_collected = false
	_is_charging = false
	_charge_bar.visible = false
	_state = State.IDLE


# ============================================================
# VISUALS — hook + rope
# ============================================================
func _update_hook_visual() -> void:
	if _state == State.IDLE:
		_hook.visible = false
		return
	_hook.visible = true
	_hook.global_position = _hook_world_pos


func _update_rope_visual() -> void:
	if _state == State.IDLE:
		_rope_mesh.visible = false
		return

	var from := _hand_pos()
	var to := _hook_world_pos
	var rope_len := from.distance_to(to)

	if rope_len < 0.1:
		_rope_mesh.visible = false
		return

	_rope_mesh.visible = true

	# Build a tube mesh along the rope path using CylinderMesh
	var mid := (from + to) * 0.5
	var dir := to - from
	var height := rope_len

	_rope_mesh.global_position = mid
	_rope_mesh.global_rotation = Vector3.ZERO

	# CylinderMesh extends along local Y axis — orient Y along the rope
	var rope_dir := dir.normalized()
	var arbitrary := Vector3.UP
	if abs(rope_dir.dot(Vector3.UP)) > 0.9:
		arbitrary = Vector3.FORWARD
	var right := arbitrary.cross(rope_dir).normalized()
	var perp := rope_dir.cross(right).normalized()
	# Y axis = rope direction, X = right, Z = perpendicular
	_rope_mesh.global_transform.basis = Basis(right, rope_dir, perp)

	# Update the cylinder mesh
	var existing_mesh := _rope_mesh.mesh
	var cyl: CylinderMesh = null
	if existing_mesh is CylinderMesh:
		cyl = existing_mesh as CylinderMesh
	else:
		cyl = CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.025
		_rope_mesh.mesh = cyl
	cyl.height = height


func _update_charge_bar_ui() -> void:
	if _charge_bar == null:
		return
	if _is_charging:
		_charge_bar.visible = true
		var vp := get_viewport().get_visible_rect().size
		var bar_w := (_charge_distance / max_hook_distance) * 200.0
		_charge_bar.size = Vector2(bar_w, 5)
		_charge_bar.position = Vector2(vp.x * 0.5 - bar_w * 0.5, vp.y * 0.5 + 35.0)
	else:
		_charge_bar.visible = false
