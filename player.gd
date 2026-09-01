extends CharacterBody3D

# ============================================================
# CONSTANTS
# ============================================================
const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.0
const SWIM_SPEED := 2.0
const SWIM_SPRINT_SPEED := 3.5
const JUMP_VELOCITY := 10.0
const WATER_JUMP_VELOCITY := 12.0
const DIVE_VELOCITY := -6.0
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.003

# Swimming
const SWIM_UP_CONTINUOUS := 5.0
const SWIM_DOWN_SPEED := 3.0
const SWIM_ACCELERATION := 12.0
const SWIM_DECELERATION := 6.0
const FLOAT_FORCE := 8.0
const FLOAT_DAMPING := 0.95
const WATER_ENTER_OFFSET := 0.3
const WATER_EXIT_OFFSET := 1.5
const MAX_SWIM_DEPTH := 30.0

# Aim
const AIM_DISTANCE := 60.0
const PICKUP_RANGE := 5.0
const NEARBY_PICKUP_RANGE := 2.0

# Build
const BUILD_RECIPE_NAMES := ["Foundation", "Wall", "Roof", "Stairs", "Door", "Window"]
const BUILD_SCENES := [
	"res://foundation.tscn",
	"res://wall.tscn",
	"res://roof.tscn",
	"res://stairs.tscn",
	"res://door.tscn",
	"res://window.tscn",
]
const SOCKET_SNAP_RADIUS: float = 2.5

# Grid & Foundation dimensions — single source of truth
const CELL_SIZE: float = 2.0  # kept for backward compat; prefer FOUNDATION_WIDTH/DEPTH
const FOUNDATION_WIDTH: float = 2.0
const FOUNDATION_DEPTH: float = 2.0
const FOUNDATION_THICKNESS: float = 0.30
const FOUNDATION_HALF_WIDTH: float = FOUNDATION_WIDTH * 0.5
const FOUNDATION_HALF_DEPTH: float = FOUNDATION_DEPTH * 0.5
const FOUNDATION_HALF_HEIGHT: float = FOUNDATION_THICKNESS * 0.5

# ============================================================
# NODE REFERENCES
# ============================================================
@onready var cam_pivot: Node3D = $CamPivot
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var crosshair: Control = $CanvasLayer/Crosshair
@onready var rope_system: RopeSystem = $RopeSystem

var ocean: Ocean = null

@export var build_pieces: Array[PackedScene] = []
var selected_piece_index: int = 0
var build_mode: bool = false
var ghost: Node3D = null
var build_rotation: float = 0.0
var build_rotation_x: float = 0.0
var build_valid: bool = false
var _ghost_valid_mat: StandardMaterial3D = null
var _ghost_invalid_mat: StandardMaterial3D = null

# Diagnostics
@export var debug_building: bool = false
var _diag: Dictionary = {}

# Edit system
var _editing: Node3D = null
var _edit_original_pos: Vector3 = Vector3.ZERO
var _edit_original_rot: Vector3 = Vector3.ZERO
var _edit_valid: bool = false
var _edit_last_pos: Vector3 = Vector3.ZERO
var _last_click_time: float = 0.0

# Aim
var aim_point: Vector3 = Vector3.ZERO
var aim_normal: Vector3 = Vector3.FORWARD
var aim_collider: Node3D = null
var aim_distance: float = 0.0
var aim_valid: bool = false

# State
var is_swimming: bool = false
var was_swimming: bool = false

# HUD
var _hud_label: Label = null

# Grid occupancy — maps raft-relative Vector2i → Node3D
var _grid_occupancy: Dictionary = {}
var _raft_node: Node3D = null  # cached reference to root raft
var _last_debug_key: String = ""  # prevents output flooding

# ============================================================
# OCEAN
# ============================================================
func _get_ocean() -> Ocean:
	if ocean == null or not is_instance_valid(ocean):
		ocean = get_tree().get_first_node_in_group("ocean")
		if ocean == null:
			ocean = get_node_or_null("%Ocean")
	return ocean

# ============================================================
# INIT
# ============================================================
func _ready() -> void:
	add_to_group("player")
	rope_system.player = self
	rope_system.camera = camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh != null:
		mesh.visible = false
	if build_pieces.is_empty():
		for scene_path in BUILD_SCENES:
			var scene = load(scene_path) as PackedScene
			if scene:
				build_pieces.append(scene)
	Inventory.infinite = true
	Inventory.add("Wood", 999)
	Inventory.add("Rope", 999)
	Inventory.add("Plastic", 999)
	_create_hud()
	if debug_building:
		for i in BUILD_SCENES.size():
			var scene: PackedScene = load(BUILD_SCENES[i]) as PackedScene
			if scene:
				_validate_build_scene(scene, BUILD_RECIPE_NAMES[i])

# ============================================================
# MOUSE LOOK
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		cam_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, -1.4, 1.4)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ============================================================
# CENTRAL AIM SYSTEM
# ============================================================
func _update_aim() -> void:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := camera.global_position
	var ray_dir := -camera.global_transform.basis.z
	var ray_end := ray_origin + ray_dir * AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 3
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		aim_valid = true
		aim_point = result.position
		aim_normal = result.normal
		aim_collider = result.collider as Node3D
		aim_distance = ray_origin.distance_to(result.position)
	else:
		aim_valid = false
		aim_point = ray_end
		aim_normal = -ray_dir
		aim_collider = null
		aim_distance = AIM_DISTANCE

# ============================================================
# PHYSICS PROCESS
# ============================================================
func _physics_process(delta: float) -> void:
	_update_aim()
	var oc := _get_ocean()
	var water_y: float = 0.0
	var has_ocean: bool = false
	if oc != null:
		water_y = oc.get_height(global_position)
		has_ocean = true
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var direction := _get_movement_direction(input_dir)
	var sprinting := Input.is_action_pressed("sprint")
	if is_swimming:
		_update_swimming(delta, direction, water_y, sprinting)
	else:
		_update_land(delta, direction, sprinting)
	move_and_slide()
	_update_swimming_state(water_y, has_ocean)

func _update_swimming_state(water_y: float, has_ocean: bool) -> void:
	was_swimming = is_swimming
	if has_ocean:
		if is_swimming:
			is_swimming = global_position.y < water_y + WATER_EXIT_OFFSET and not is_on_floor()
		else:
			is_swimming = global_position.y < water_y + WATER_ENTER_OFFSET
	else:
		is_swimming = false
	if is_swimming != was_swimming:
		if not is_swimming:
			velocity.y = min(velocity.y, 0.0)

func _get_movement_direction(input_dir: Vector2) -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return (right * input_dir.x + forward * input_dir.y).normalized()

func _update_land(delta: float, direction: Vector3, sprinting: bool) -> void:
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y -= GRAVITY * delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	if is_on_floor() and Input.is_action_just_pressed("move_down"):
		velocity.y = DIVE_VELOCITY

func _update_swimming(delta: float, direction: Vector3, water_y: float, sprinting: bool) -> void:
	var spd := SWIM_SPRINT_SPEED if sprinting else SWIM_SPEED
	velocity.x = direction.x * spd
	velocity.z = direction.z * spd
	if Input.is_action_just_pressed("jump"):
		velocity.y = WATER_JUMP_VELOCITY
	elif Input.is_action_pressed("jump"):
		velocity.y = move_toward(velocity.y, SWIM_UP_CONTINUOUS, SWIM_ACCELERATION * delta)
	elif Input.is_action_pressed("move_down"):
		velocity.y = move_toward(velocity.y, -SWIM_DOWN_SPEED, SWIM_ACCELERATION * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, SWIM_DECELERATION * delta)
	var depth := water_y - global_position.y
	if depth > -1.0 and depth < 2.0:
		var surface_target := water_y + 0.2
		var error := surface_target - global_position.y
		if abs(error) > 0.3 and not Input.is_action_pressed("jump") and not Input.is_action_pressed("move_down"):
			velocity.y += error * FLOAT_FORCE * delta
		velocity.y *= FLOAT_DAMPING
	if depth > MAX_SWIM_DEPTH:
		velocity.y = move_toward(velocity.y, 0.0, SWIM_DECELERATION * delta)

# ============================================================
# E PICKUP
# ============================================================
func _handle_pickup() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	if build_mode and _editing == null:
		_try_build()
		return
	if aim_valid and aim_collider != null:
		if aim_collider.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
			_collect_debris(aim_collider)
			return
		if "toggle" in aim_collider:
			aim_collider.toggle()
			return
	if aim_collider == null or not aim_collider.is_in_group("debris"):
		for d in get_tree().get_nodes_in_group("debris"):
			if d is Node3D and is_instance_valid(d):
				if global_position.distance_to(d.global_position) <= NEARBY_PICKUP_RANGE:
					_collect_debris(d)
					return

func _collect_debris(debris: Node3D) -> void:
	if debris.get("collected") == true:
		return
	var item_name: String = str(debris.get("item_name"))
	if item_name != "" and item_name != "null":
		debris.set("collected", true)
		Inventory.add(item_name)
		debris.queue_free()

# ============================================================
# BUILD SYSTEM — PROCESS & INPUT
# ============================================================
func _process(_delta: float) -> void:
	_update_hud()
	if Input.is_action_just_pressed("build"):
		_toggle_build()
	if Input.is_action_just_pressed("cycle_build") and build_mode:
		_cycle_build_piece()
	if Input.is_action_just_pressed("rotate_build") and (build_mode or _editing != null):
		_rotate_build()
	if Input.is_action_just_pressed("rotate_build_x") and (build_mode or _editing != null):
		_rotate_build_x()
	if _editing != null:
		if Input.is_action_just_pressed("interact"):
			_confirm_edit()
		if Input.is_action_just_pressed("remove_build"):
			_remove_editing()
		_update_edit_follow()
	elif Input.is_action_just_pressed("interact"):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_click_time < 0.4 and aim_valid and aim_collider != null:
			var target := _find_editable_target(aim_collider)
			if target != null:
				_start_edit(target)
				_last_click_time = 0.0
				return
		_last_click_time = now
	_handle_pickup()
	if _editing != null:
		crosshair.set_state(crosshair.State.BUILD)
	elif build_mode and ghost:
		crosshair.set_state(crosshair.State.BUILD)
		_update_build_preview()
	elif aim_valid and aim_collider != null and aim_collider.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
		crosshair.set_state(crosshair.State.ITEM)
	elif aim_valid and aim_collider != null and "toggle" in aim_collider:
		crosshair.set_state(crosshair.State.ITEM)
	else:
		crosshair.set_state(crosshair.State.NONE)

func _toggle_build() -> void:
	if _editing != null:
		_cancel_edit()
		return
	if build_pieces.is_empty():
		return
	build_mode = !build_mode
	if build_mode:
		build_rotation = 0.0
		build_rotation_x = 0.0
		_spawn_ghost()
	elif ghost:
		ghost.queue_free()
		ghost = null
		if _debug_markers_root != null and is_instance_valid(_debug_markers_root):
			_debug_markers_root.queue_free()
			_debug_markers_root = null
			_debug_target_marker = null
			_debug_actual_marker = null

func _cancel_edit() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	_editing.global_position = _edit_original_pos
	_editing.rotation = _edit_original_rot
	var col := _editing.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = false
	_apply_building_color(_editing)
	_editing = null

var _build_preview_root: Node3D = null

func _get_build_preview_root() -> Node3D:
	if _build_preview_root != null and is_instance_valid(_build_preview_root):
		return _build_preview_root
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_build_preview_root = Node3D.new()
	_build_preview_root.name = "BuildPreviewRoot"
	root.add_child(_build_preview_root)
	return _build_preview_root

func _spawn_ghost() -> void:
	if ghost:
		ghost.queue_free()
	ghost = build_pieces[selected_piece_index].instantiate()
	ghost.scale = Vector3.ONE
	ghost.visible = false
	_get_build_preview_root().add_child(ghost)
	ghost.global_position = aim_point
	var col := ghost.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true
	if _ghost_valid_mat == null:
		_ghost_valid_mat = StandardMaterial3D.new()
		_ghost_valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_valid_mat.albedo_color = Color(0.2, 0.9, 0.2, 0.5)
		_ghost_valid_mat.no_depth_test = true
	if _ghost_invalid_mat == null:
		_ghost_invalid_mat = StandardMaterial3D.new()
		_ghost_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_invalid_mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		_ghost_invalid_mat.no_depth_test = true

func _cycle_build_piece() -> void:
	if build_pieces.is_empty():
		return
	selected_piece_index = (selected_piece_index + 1) % build_pieces.size()
	if build_mode:
		_spawn_ghost()

func _rotate_build() -> void:
	build_rotation += PI / 2.0
	if build_rotation >= TAU:
		build_rotation -= TAU

func _rotate_build_x() -> void:
	build_rotation_x += PI / 2.0
	if build_rotation_x >= TAU:
		build_rotation_x -= TAU

# ============================================================
# BUILD SYSTEM — GRID & OCCUPANCY
# ============================================================
func _get_raft_node() -> Node3D:
	if _raft_node != null and is_instance_valid(_raft_node):
		return _raft_node
	_raft_node = get_tree().get_first_node_in_group("build_surface") as Node3D
	if _raft_node != null:
		_grid_register(Vector2i.ZERO, _raft_node)
	return _raft_node

# Canonical structural deck height: top surface of the Foundation floor.
# Every Foundation uses this same height — no cumulative calculation.
func _get_structural_deck_y() -> float:
	var raft: Node3D = _get_raft_node()
	if raft == null:
		return 0.0
	var flat_xf: Transform3D = _get_flat_support_transform(raft)
	return flat_xf.origin.y + FOUNDATION_HALF_HEIGHT

# Convert world position to grid cell relative to the raft.
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var raft := _get_raft_node()
	if raft == null:
		return Vector2i.ZERO
	# Use flat transform (no wave tilt) for consistent grid mapping
	var flat_xform: Transform3D = _get_flat_support_transform(raft)
	var local: Vector3 = flat_xform.affine_inverse() * world_pos
	var cx: int = int(roundf(local.x / FOUNDATION_WIDTH))
	var cz: int = int(roundf(local.z / FOUNDATION_DEPTH))
	return Vector2i(cx, cz)

# Get the world-space center of a grid cell relative to the raft.
func _grid_to_world(cell: Vector2i) -> Vector3:
	var raft := _get_raft_node()
	if raft == null:
		return Vector3.ZERO
	var local: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
	# Use flat transform (no wave tilt) so grid positions are always level
	return _get_flat_support_transform(raft) * local

# Register a piece in the occupancy grid.
func _grid_register(cell: Vector2i, piece: Node3D) -> void:
	_grid_occupancy[cell] = piece

# Unregister a piece from the grid.
func _grid_unregister(cell: Vector2i) -> void:
	_grid_occupancy.erase(cell)

# Check if a cell is occupied.
func _grid_is_occupied(cell: Vector2i) -> bool:
	return _grid_occupancy.has(cell)

# Get the cell that a support piece occupies.
func _get_piece_cell(piece: Node3D) -> Vector2i:
	return _world_to_grid(piece.global_position)

# Find the support piece's cell, then determine which adjacent cell
# the player's aim is targeting.
func _aim_to_candidate_cell(support: Node3D) -> Vector2i:
	var support_cell: Vector2i = _get_piece_cell(support)
	# Convert aim point to support-local space
	var raft := _get_raft_node()
	if raft == null:
		return support_cell
	# Use flat transform (no wave tilt) for consistent aim-to-cell mapping
	var flat_xform: Transform3D = _get_flat_support_transform(raft)
	var local_aim: Vector3 = flat_xform.affine_inverse() * aim_point
	# Determine direction from support center to aim point
	var dx: float = local_aim.x - support_cell.x * FOUNDATION_WIDTH
	var dz: float = local_aim.z - support_cell.y * FOUNDATION_DEPTH
	# Map to grid offset
	var ox: int = 0
	var oz: int = 0
	# Determine which edge/corner the aim is closest to
	var abs_dx: float = absf(dx)
	var abs_dz: float = absf(dz)
	if abs_dx < 0.01 and abs_dz < 0.01:
		# Aim at center — use hit normal instead
		var normal_local: Vector3 = flat_xform.basis.inverse() * aim_normal
		normal_local.y = 0.0
		if normal_local.length() > 0.001:
			normal_local = normal_local.normalized()
			ox = int(roundf(normal_local.x))
			oz = int(roundf(normal_local.z))
		else:
			return support_cell
	elif abs_dx > abs_dz:
		# Primarily X direction
		ox = 1 if dx > 0 else -1
		# Check if also at Z edge for corner
		if abs_dz > FOUNDATION_HALF_WIDTH * 0.7:
			oz = 1 if dz > 0 else -1
	else:
		# Primarily Z direction
		oz = 1 if dz > 0 else -1
		if abs_dx > FOUNDATION_HALF_WIDTH * 0.7:
			ox = 1 if dx > 0 else -1
	return support_cell + Vector2i(ox, oz)

# ============================================================
# BUILD SYSTEM — STRUCTURAL SUPPORT
# ============================================================
func _is_structurally_supported(piece: Node3D) -> bool:
	# Raft is always supported
	if piece.name.begins_with("Raft"):
		return true
	# BFS from piece to find a path back to the raft — avoids infinite recursion
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	var start_cell: Vector2i = _get_piece_cell(piece)
	visited[start_cell] = true
	queue.append(start_cell)
	while not queue.is_empty():
		var current_cell: Vector2i = queue.pop_front()
		# Cardinal neighbors (full edge connection)
		var cardinal: Array[Vector2i] = [
			current_cell + Vector2i(0, -1), current_cell + Vector2i(0, 1),
			current_cell + Vector2i(-1, 0), current_cell + Vector2i(1, 0),
		]
		for n in cardinal:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var neighbor: Node3D = _grid_occupancy[n] as Node3D
				if neighbor != null and is_instance_valid(neighbor):
					if neighbor.name.begins_with("Raft"):
						return true
					visited[n] = true
					queue.append(n)
		# Diagonal neighbors — only count when connecting to raft root
		var diagonal: Array[Vector2i] = [
			current_cell + Vector2i(-1, -1), current_cell + Vector2i(1, -1),
			current_cell + Vector2i(-1, 1), current_cell + Vector2i(1, 1),
		]
		for n in diagonal:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var neighbor: Node3D = _grid_occupancy[n] as Node3D
				if neighbor != null and is_instance_valid(neighbor):
					if neighbor.name.begins_with("Raft"):
						return true
	return false

func _get_support_path(piece: Node3D) -> Array[String]:
	var path: Array[String] = []
	var current: Node3D = piece
	var visited: Dictionary = {}
	while current != null:
		if visited.has(current):
			break
		visited[current] = true
		path.append(current.name)
		if current.name.begins_with("Raft"):
			break
		var sockets_node := current.get_node_or_null("BuildSockets")
		if sockets_node == null:
			break
		var parent_piece: Node3D = null
		for socket in sockets_node.get_children():
			if socket is BuildSocket and socket.occupying_piece != null \
				and is_instance_valid(socket.occupying_piece):
				parent_piece = socket.occupying_piece
				break
		current = parent_piece
	return path

# ============================================================
# BUILD SYSTEM — SOCKET HELPERS
# ============================================================
func _get_all_sockets(root: Node) -> Array[BuildSocket]:
	var result: Array[BuildSocket] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BuildSocket:
			result.append(n)
		for c in n.get_children():
			stack.append(c)
	return result

func _find_support_piece(collider: Node3D) -> Node3D:
	if collider == null:
		return null
	if collider.name.begins_with("Foundation") or collider.name.begins_with("Wall") \
		or collider.name.begins_with("Roof") or collider.name.begins_with("Stairs") \
		or collider.name.begins_with("Door") or collider.name.begins_with("Window") \
		or collider.name.begins_with("Raft"):
		if collider.get_node_or_null("BuildSockets") != null:
			return collider
	var current: Node = collider
	for _i in range(5):
		if current == null:
			break
		if current is Node3D and current.get_node_or_null("BuildSockets") != null:
			return current as Node3D
		current = current.get_parent()
	return null

func _find_piece_name(node: Node3D) -> String:
	if node == null:
		return ""
	for n in BUILD_RECIPE_NAMES:
		if node.name.begins_with(n):
			return n
	if node.name.begins_with("Raft"):
		return "Raft"
	return ""

func _piece_name_from_node(node: Node3D) -> String:
	return _find_piece_name(node)

func _get_socket_world_direction(socket: BuildSocket) -> Vector3:
	var parent_piece: Node3D = socket.get_parent_piece()
	if parent_piece == null:
		return Vector3.FORWARD
	# Use flat transform (no wave tilt) for consistent direction scoring
	var parent_basis: Basis = _get_flat_support_transform(parent_piece).basis
	var local_pos: Vector3 = socket.position
	if absf(local_pos.y) < 0.01:
		local_pos.y = 0.0
	if local_pos.length() < 0.001:
		return Vector3.UP
	return (parent_basis * local_pos.normalized()).normalized()

func _is_corner_socket(socket: BuildSocket) -> bool:
	var sname: String = socket.name
	return sname.contains("NorthEast") or sname.contains("NorthWest") \
		or sname.contains("SouthEast") or sname.contains("SouthWest")

# ============================================================
# BUILD SYSTEM — TRANSFORM SOLVERS
# Get the support's flat transform (position + Y-rotation only, no wave tilt).
# This ensures placed buildings are always level, not tilted with waves.
func _get_flat_support_transform(support: Node3D) -> Transform3D:
	var pos: Vector3 = support.global_position
	var yaw: float = support.global_rotation.y
	return Transform3D(Basis(Vector3.UP, yaw), pos)

# Edge/face placement: new piece socket coincides with target socket.
# Always flat — ignores wave tilt.
func _solve_socket_transform(
	target_socket: BuildSocket,
	new_piece_socket_local_pos: Vector3,
	support: Node3D,
) -> Transform3D:
	# Use flat support transform (no wave tilt)
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var socket_local: Vector3 = target_socket.position
	var target_flat_pos: Vector3 = flat_xform * socket_local
	var rotated_offset: Vector3 = new_piece_socket_local_pos.rotated(Vector3.UP, build_rotation)
	var piece_center: Vector3 = target_flat_pos - rotated_offset
	var piece_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(piece_basis, piece_center)

# Corner placement: foundation corner touches support corner.
# Always flat — ignores wave tilt.
func _solve_corner_transform(
	corner_socket: BuildSocket,
	_piece_name: String,
	support: Node3D,
) -> Transform3D:
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var support_pos: Vector3 = flat_xform.origin
	var local_dir: Vector3 = corner_socket.position
	local_dir.y = 0.0
	var sign_x: float = signf(local_dir.x)
	var sign_z: float = signf(local_dir.z)
	if absf(sign_x) < 0.5:
		sign_x = 0.0
	if absf(sign_z) < 0.5:
		sign_z = 0.0
	var half_ext: float = FOUNDATION_HALF_WIDTH
	var cell_half: float = FOUNDATION_HALF_WIDTH
	var corner_offset_local: Vector3 = Vector3(
		sign_x * (cell_half + half_ext),
		0.0,
		sign_z * (cell_half + half_ext)
	)
	var rotated_offset: Vector3 = corner_offset_local.rotated(Vector3.UP, build_rotation)
	var piece_center: Vector3 = support_pos + flat_xform.basis * rotated_offset
	var piece_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(piece_basis, piece_center)

# ============================================================
# BUILD SYSTEM — CANDIDATE SELECTION
# ============================================================
# Find the best socket on the support for the given piece type and aim.
func _find_best_socket(
	support_piece: Node3D,
	piece_name: String,
	aim_world_pos: Vector3,
	target_aim_normal: Vector3,
) -> BuildSocket:
	var best_socket: BuildSocket = null
	var best_score: float = -1.0e10
	var aim_dir: Vector3 = target_aim_normal.normalized()
	var sockets_node := support_piece.get_node_or_null("BuildSockets")
	if sockets_node == null:
		return null
	# Use flat transform for consistent distance scoring (no wave tilt)
	var flat_xf: Transform3D = _get_flat_support_transform(support_piece)
	for socket in sockets_node.get_children():
		if socket == null or not is_instance_valid(socket):
			continue
		if socket.is_occupied:
			continue
		if not socket.is_compatible(piece_name):
			continue
		var socket_flat_pos: Vector3 = flat_xf * socket.position
		var dist: float = aim_world_pos.distance_to(socket_flat_pos)
		if dist > SOCKET_SNAP_RADIUS:
			continue
		var socket_dir: Vector3 = _get_socket_world_direction(socket)
		var alignment: float = socket_dir.dot(aim_dir)
		var score: float = alignment * 10.0 - dist
		if score > best_score:
			best_score = score
			best_socket = socket
	if best_socket == null and debug_building:
		var count: int = 0
		var occ_count: int = 0
		var detail: String = ""
		if sockets_node != null:
			count = sockets_node.get_child_count()
			for s in sockets_node.get_children():
				if s is BuildSocket:
					if s.is_occupied:
						occ_count += 1
						detail += "  [OCC] %s\n" % s.name
					elif not s.is_compatible(piece_name):
						detail += "  [INCOMPAT] %s\n" % s.name
					else:
						var sflat: Vector3 = flat_xf * s.position
						var sd: float = aim_world_pos.distance_to(sflat)
						detail += "  [DIST %.2fm] %s\n" % [sd, s.name]
		push_warning("[BUILD] No socket found! Total: %d, Occ: %d, Piece: %s\n%s" % [count, occ_count, piece_name, detail])
	return best_socket

# Find the best reciprocal socket on the new piece.
# The reciprocal must face OPPOSITE to the support socket.
func _find_reciprocal_socket(
	support_socket: BuildSocket,
	new_piece_temp: Node3D,
	effective_support_name: String,
) -> BuildSocket:
	var new_piece_sockets: Array[BuildSocket] = _get_all_sockets(new_piece_temp)
	var best: BuildSocket = null
	var best_score: float = -1.0e10
	# Get support socket direction in its parent piece's local space
	var support_local_dir: Vector3 = support_socket.position
	support_local_dir.y = 0.0
	if support_local_dir.length() > 0.001:
		support_local_dir = support_local_dir.normalized()
	else:
		support_local_dir = Vector3.FORWARD
	for s in new_piece_sockets:
		if s == null or not is_instance_valid(s):
			continue
		if not s.is_compatible(effective_support_name):
			continue
		var score: float = 0.0
		# Type compatibility score
		if support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_EDGE \
			and s.socket_type == BuildSocket.SocketType.FOUNDATION_EDGE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_BASE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_BASE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_SIDE \
			and s.socket_type == BuildSocket.SocketType.WALL_SIDE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_TOP \
			and (s.socket_type == BuildSocket.SocketType.DOOR_SLOT \
				or s.socket_type == BuildSocket.SocketType.WINDOW_SLOT):
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_TOP:
			score = 10.0
		else:
			score = 1.0
		# Direction-opposite bonus: reciprocal must face opposite direction
		var new_local_dir: Vector3 = s.position
		new_local_dir.y = 0.0
		if new_local_dir.length() > 0.001:
			new_local_dir = new_local_dir.normalized()
		else:
			new_local_dir = Vector3.FORWARD
		var dot: float = support_local_dir.dot(new_local_dir)
		# dot < 0 means opposite facing = correct reciprocal
		# dot ≈ 0 means perpendicular = acceptable for some types
		# dot > 0 means same direction = WRONG
		if dot < -0.5:
			score += 50.0  # Strong bonus for opposite-facing
		elif dot > 0.5:
			score -= 100.0  # Strong penalty for same-direction
		if score > best_score:
			best_score = score
			best = s
	return best

# ============================================================
# BUILD SYSTEM — VALIDATION HELPERS
# ============================================================
var _shape_cache: Dictionary = {}
var _ghost_target_socket: BuildSocket = null
var _ghost_transform: Transform3D
var _ghost_cell: Vector2i = Vector2i(999999, 999999)
var _ghost_support: Node3D = null

func _get_validation_shape(piece_scene: PackedScene) -> Shape3D:
	if _shape_cache.has(piece_scene):
		return _shape_cache[piece_scene]
	var temp: Node3D = piece_scene.instantiate()
	var col := temp.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: Shape3D
	if col != null and col.shape != null:
		shape = col.shape.duplicate()
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(1, 1, 1)
		shape = bs
	temp.queue_free()
	_shape_cache[piece_scene] = shape
	return shape

func _check_overlap(shape: Shape3D, xform: Transform3D, support: Node3D) -> Array[Dictionary]:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = 1
	var excluded: Array[RID] = [get_rid()]
	# Exclude the support and ALL ancestors in build_surface group
	# (raft, foundations, etc.) so pieces sitting on top don't false-overlap
	var excl_node: Node3D = support
	while excl_node != null and is_instance_valid(excl_node):
		if excl_node is PhysicsBody3D:
			excluded.append(excl_node.get_rid())
		excl_node = excl_node.get_parent() as Node3D
	if _editing != null and is_instance_valid(_editing):
		excluded.append(_editing.get_rid())
	if ghost != null and is_instance_valid(ghost):
		excluded.append(ghost.get_rid())
	query.exclude = excluded
	var results: Array[Dictionary] = []
	var hits := space_state.intersect_shape(query, 8)
	for h in hits:
		var hit_dict: Dictionary = {}
		for key in h.keys():
			hit_dict[key] = h[key]
		results.append(hit_dict)
	return results

# Measure edge gap between two pieces along the connection direction.
# Returns the signed gap: negative = penetration, positive = gap, zero = flush.
# Uses flat support transform to match the flat solver.
func _measure_edge_gap(
	support: Node3D,
	support_socket: BuildSocket,
	new_xform: Transform3D,
	_new_piece_temp: Node3D,
	new_socket: BuildSocket,
) -> float:
	# Use flat support transform for consistent comparison
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var support_edge: Vector3 = flat_xform * support_socket.position
	var new_socket_world: Vector3 = (new_xform * new_socket.transform).origin
	var gap: float = support_edge.distance_to(new_socket_world)
	# Check if the new piece is on the correct side
	var conn_local: Vector3 = support_socket.position
	conn_local.y = 0.0
	var conn_dir: Vector3 = (flat_xform.basis * conn_local.normalized()).normalized() if conn_local.length() > 0.001 else Vector3.FORWARD
	var to_new: Vector3 = (new_xform.origin - flat_xform.origin).normalized()
	var side_check: float = to_new.dot(conn_dir)
	if side_check < 0.0:
		return -gap
	return gap

# ============================================================
# BUILD SYSTEM — GRID CELL FOUNDATION PLACEMENT
# ============================================================
# Determine which side of the support the player is aiming toward.
# Returns a Vector2i direction: (±1, 0) or (0, ±1) for edges,
# (±1, ±1) for corners, (0, 0) for center.
func _determine_aim_side(support: Node3D, aim_pos: Vector3) -> Vector2i:
	var flat_xf: Transform3D = _get_flat_support_transform(support)
	var inv_xf: Transform3D = flat_xf.affine_inverse()
	var local_aim: Vector3 = inv_xf * aim_pos
	var half_cell: float = FOUNDATION_HALF_WIDTH
	var dx: float = local_aim.x
	var dz: float = local_aim.z
	var side_x: int = 0
	var side_z: int = 0
	# Determine primary direction from local aim offset
	if dx > half_cell * 0.25:
		side_x = 1
	elif dx < -half_cell * 0.25:
		side_x = -1
	if dz > half_cell * 0.25:
		side_z = 1
	elif dz < -half_cell * 0.25:
		side_z = -1
	# If aim is near center, use camera forward projected onto build plane
	if side_x == 0 and side_z == 0:
		var cam_forward: Vector3 = -camera.global_transform.basis.z
		var local_forward: Vector3 = inv_xf.basis * cam_forward
		local_forward.y = 0.0
		if local_forward.length() > 0.01:
			local_forward = local_forward.normalized()
			side_x = int(roundf(local_forward.x))
			side_z = int(roundf(local_forward.z))
	return Vector2i(side_x, side_z)

# Check if a grid cell is structurally supported (has a supported neighbor
# connected via cardinal edge to the raft).
func _is_cell_structurally_supported(cell: Vector2i) -> bool:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	# Start BFS from all occupied cardinal neighbors
	var cardinal: Array[Vector2i] = [
		cell + Vector2i(0, -1), cell + Vector2i(0, 1),
		cell + Vector2i(-1, 0), cell + Vector2i(1, 0),
	]
	for n in cardinal:
		if visited.has(n):
			continue
		if _grid_occupancy.has(n):
			var piece: Node3D = _grid_occupancy[n] as Node3D
			if piece != null and is_instance_valid(piece):
				if piece.name.begins_with("Raft"):
					return true
				visited[n] = true
				queue.append(n)
	# Diagonal neighbors — only count raft
	var diagonal: Array[Vector2i] = [
		cell + Vector2i(-1, -1), cell + Vector2i(1, -1),
		cell + Vector2i(-1, 1), cell + Vector2i(1, 1),
	]
	for n in diagonal:
		if _grid_occupancy.has(n):
			var piece: Node3D = _grid_occupancy[n] as Node3D
			if piece != null and is_instance_valid(piece):
				if piece.name.begins_with("Raft"):
					return true
	# BFS through connected foundations to find raft
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var c_card: Array[Vector2i] = [
			current + Vector2i(0, -1), current + Vector2i(0, 1),
			current + Vector2i(-1, 0), current + Vector2i(1, 0),
		]
		for n in c_card:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var piece: Node3D = _grid_occupancy[n] as Node3D
				if piece != null and is_instance_valid(piece):
					if piece.name.begins_with("Raft"):
						return true
					visited[n] = true
					queue.append(n)
	return false

# Count how many occupied neighbors a cell has (for scoring).
func _count_supporting_neighbors(cell: Vector2i) -> int:
	var count: int = 0
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
	]
	for o in offsets:
		if _grid_occupancy.has(cell + o):
			count += 1
	return count

# Compute the world-space Transform3D for a Foundation at a grid cell.
# This is the SINGLE AUTHORITATIVE cell-to-position formula.
# Every Foundation must be placed using only this function.
func _compute_foundation_transform(cell: Vector2i) -> Transform3D:
	var raft: Node3D = _get_raft_node()
	var flat_xf: Transform3D = _get_flat_support_transform(raft) if raft else Transform3D()
	# Canonical grid formula: local_pos = cell * FOUNDATION_WIDTH/DEPTH
	var local_pos: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
	var world_pos: Vector3 = flat_xf * local_pos
	var world_basis: Basis = flat_xf.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(world_basis, world_pos)

# Find the socket on the support that faces a given candidate cell direction.
# Used by _try_build to know which socket to mark occupied.
func _find_connecting_socket(support: Node3D, candidate_cell: Vector2i) -> BuildSocket:
	var support_cell: Vector2i = _get_piece_cell(support)
	var diff: Vector2i = candidate_cell - support_cell
	var support_sockets: Array[BuildSocket] = _get_all_sockets(support)
	var best: BuildSocket = null
	var best_dot: float = -1.0
	for s in support_sockets:
		if s.socket_type != BuildSocket.SocketType.FOUNDATION_EDGE:
			continue
		var sdir: Vector3 = s.position
		sdir.y = 0.0
		if sdir.length() < 0.001:
			continue
		sdir = sdir.normalized()
		var target_dir: Vector3 = Vector3(float(diff.x), 0.0, float(diff.y)).normalized()
		var dot: float = sdir.dot(target_dir)
		if dot > best_dot:
			best_dot = dot
			best = s
	return best

# Find and verify the socket connection between support and candidate cell.
# Returns the socket position error (0 = perfect alignment).
func _verify_foundation_connection(
	support: Node3D,
	candidate_cell: Vector2i,
	solved: Transform3D,
	temp_piece: Node3D,
) -> float:
	var support_cell: Vector2i = _get_piece_cell(support)
	var diff: Vector2i = candidate_cell - support_cell
	var flat_sf: Transform3D = _get_flat_support_transform(support)
	# Find support socket facing the candidate direction
	var support_sockets: Array[BuildSocket] = _get_all_sockets(support)
	var best_support_socket: BuildSocket = null
	var best_dot: float = -1.0
	for s in support_sockets:
		if s.socket_type != BuildSocket.SocketType.FOUNDATION_EDGE:
			continue
		var sdir: Vector3 = s.position
		sdir.y = 0.0
		if sdir.length() < 0.001:
			continue
		sdir = sdir.normalized()
		var target_dir: Vector3 = Vector3(float(diff.x), 0.0, float(diff.y)).normalized()
		var dot: float = sdir.dot(target_dir)
		if dot > best_dot:
			best_dot = dot
			best_support_socket = s
	if best_support_socket == null:
		return 10.0
	_diag["target_socket_name"] = best_support_socket.name
	_diag["target_socket_pos"] = best_support_socket.global_position
	# Find reciprocal socket on new piece
	var effective_support_name: String = "Foundation"
	if support.name.begins_with("Raft"):
		effective_support_name = "Foundation"
	var reciprocal: BuildSocket = _find_reciprocal_socket(best_support_socket, temp_piece, effective_support_name)
	if reciprocal == null:
		return 10.0
	_diag["new_socket_name"] = reciprocal.name
	# Verify: ghost reciprocal socket position vs support socket position
	var ghost_sockets: Array[BuildSocket] = _get_all_sockets(temp_piece)
	for gs in ghost_sockets:
		if gs.name == reciprocal.name:
			var actual_pos: Vector3 = (solved * gs.transform).origin
			var flat_target: Vector3 = flat_sf * best_support_socket.position
			var err: float = actual_pos.distance_to(flat_target)
			_diag["actual_socket_pos"] = actual_pos
			_diag["socket_position_error"] = err
			return err
	return 10.0


func _resolve_placement(piece_name: String, _hit_point: Vector3) -> Dictionary:
	_diag = {}
	_diag["piece"] = piece_name

	# Step 1: Aim — with build plane fallback for empty gaps
	var effective_aim_point: Vector3 = aim_point
	var effective_aim_normal: Vector3 = aim_normal
	var effective_collider: Node3D = aim_collider
	# For Foundation: ALWAYS use structural build plane for grid cell targeting.
	# The physics ray may hit a neighboring Foundation surface, placing the aim
	# point inside the occupied cell. The build plane intersection gives the
	# correct empty gap cell under the crosshair.
	if piece_name == "Foundation":
		var deck_y_bp: float = _get_structural_deck_y()
		var ray_o: Vector3 = camera.global_position
		var ray_d: Vector3 = -camera.global_transform.basis.z
		if absf(ray_d.y) > 0.001:
			var t_bp: float = (deck_y_bp - ray_o.y) / ray_d.y
			if t_bp > 0.0 and t_bp < AIM_DISTANCE:
				effective_aim_point = ray_o + ray_d * t_bp
				effective_aim_normal = Vector3.UP
	# Fallback: when ray doesn't hit anything (all piece types)
	if not aim_valid or aim_collider == null:
		var raft: Node3D = _get_raft_node()
		if raft != null and build_mode:
			var deck_y: float = _get_structural_deck_y()
			var ray_origin: Vector3 = camera.global_position
			var ray_dir: Vector3 = -camera.global_transform.basis.z
			if absf(ray_dir.y) > 0.001:
				var t: float = (deck_y - ray_origin.y) / ray_dir.y
				if t > 0.0 and t < AIM_DISTANCE:
					effective_aim_point = ray_origin + ray_dir * t
					effective_aim_normal = Vector3.UP
					effective_collider = raft
					aim_valid = true
					aim_point = effective_aim_point
					aim_normal = effective_aim_normal
					aim_collider = raft
					aim_distance = t
	if not aim_valid or effective_collider == null:
		_diag["has_aim"] = false
		_diag["invalid_reason"] = "NO AIM"
		_diag["error_category"] = "AIM_ERROR"
		return {"valid": false}
	_diag["has_aim"] = true
	_diag["aim_pos"] = effective_aim_point
	_diag["aim_norm"] = effective_aim_normal
	if effective_collider != null:
		_diag["aim_collider_name"] = effective_collider.name
	else:
		_diag["aim_collider_name"] = "NONE"

	# Step 2: Support
	var support: Node3D = _find_support_piece(effective_collider)
	if support == null:
		_diag["invalid_reason"] = "INVALID SUPPORT"
		_diag["error_category"] = "SUPPORT_ERROR"
		return {"valid": false}
	_diag["support_name"] = support.name

	# Step 3: Structural support
	var supported: bool = _is_structurally_supported(support)
	_diag["support_valid"] = supported
	_diag["support_path"] = _get_support_path(support)
	if not supported:
		_diag["invalid_reason"] = "NO STRUCTURAL SUPPORT"
		_diag["error_category"] = "SUPPORT_ERROR"
		return {"valid": false}

	# ============================================================
	# FOUNDATION: Grid-cell-driven placement
	# ============================================================
	if piece_name == "Foundation":
		var found_idx: int = BUILD_RECIPE_NAMES.find("Foundation")
		var found_scene: PackedScene = build_pieces[found_idx]

		# Step 4a: Get support grid cell
		var support_cell: Vector2i = _get_piece_cell(support)
		_diag["support_cell"] = support_cell

		# Step 4b: Determine which side the player is aiming toward
		var aim_side: Vector2i = _determine_aim_side(support, effective_aim_point)
		_diag["aim_side"] = aim_side
		var debug_key: String = "%s_%s_%s_%s" % [support.name, str(support_cell), str(aim_side), piece_name]
		if debug_building and debug_key != _last_debug_key:
			_last_debug_key = debug_key
			print("[FOUNDATION] Support=%s cell=%s aim_side=%s" % [support.name, str(support_cell), str(aim_side)])

		# Step 4c: Generate candidate cells
		# Priority 1: The cell that the aim point directly maps to (gap filling)
		# Priority 2: Support's neighbor cells (edge expansion)
		var candidates: Array[Vector2i] = []
		# Direct aim cell — this is the cell the player is pointing at
		var aim_cell: Vector2i = _world_to_grid(effective_aim_point)
		if not candidates.has(aim_cell):
			candidates.append(aim_cell)
		# Aim side neighbor of the direct aim cell (in case aim hits edge)
		if aim_side != Vector2i.ZERO:
			var aim_side_cell: Vector2i = aim_cell + aim_side
			if not candidates.has(aim_side_cell):
				candidates.append(aim_side_cell)
		# Support's neighbor cells (edge expansion) — always generate,
		# dedup handles overlap with aim_cell.
		if aim_side != Vector2i.ZERO:
			var support_aim: Vector2i = support_cell + aim_side
			if not candidates.has(support_aim):
				candidates.append(support_aim)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = support_cell + offset
			if not candidates.has(c):
				candidates.append(c)
		for offset in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var c: Vector2i = support_cell + offset
			if not candidates.has(c):
				candidates.append(c)
		# Also check neighbors of ALL occupied cells (for gap filling between foundations)
		for occ_cell in _grid_occupancy:
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c: Vector2i = Vector2i(occ_cell) + offset
				if not candidates.has(c):
					candidates.append(c)

		# Step 4d: Score and pick best candidate
		var best_cell: Vector2i = Vector2i(999999, 999999)
		var best_score: float = -1.0e10
		if debug_building and debug_key != _last_debug_key:
			print("=== FOUNDATION CANDIDATES (support=%s cell=%s) ===" % [str(_diag.get("support_name", "?")), str(support_cell)])
		for c in candidates:
			if _grid_is_occupied(c):
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: OCCUPIED" % str(c))
				continue
			if not _is_cell_structurally_supported(c):
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: NO SUPPORT" % str(c))
				continue
			var world_pos: Vector3 = _grid_to_world(c)
			var dist: float = effective_aim_point.distance_to(world_pos)
			if dist > 6.0:
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: TOO FAR (%.1fm)" % [str(c), dist])
				continue
			var score: float = -dist
			# Priority: exact aim cell gets highest score to prevent preview jumping
			if c == aim_cell:
				score += 100.0
			# Bonus for aimed direction
			if c == support_cell + aim_side:
				score += 5.0
			# Bonus for more supporting neighbors
			var neighbor_count: int = _count_supporting_neighbors(c)
			score += float(neighbor_count) * 2.0
			# Penalty for diagonal-only support
			var is_diagonal: bool = (c.x != support_cell.x and c.y != support_cell.y)
			if is_diagonal and neighbor_count == 0:
				score -= 3.0
			if debug_building and debug_key != _last_debug_key:
				print("  [%s] dist=%.1f neighbors=%d score=%.1f" % [str(c), dist, neighbor_count, score])
			if score > best_score:
				best_score = score
				best_cell = c

		if debug_building and debug_key != _last_debug_key:
			print("  Selected: %s" % str(best_cell))

		if best_cell == Vector2i(999999, 999999):
			_diag["invalid_reason"] = "NO VALID NEIGHBOR CELL"
			_diag["error_category"] = "GRID_ERROR"
			return {"valid": false}

		_diag["target_cell"] = best_cell

		# Step 4e: Compute transform from grid cell
		var found_solved: Transform3D = _compute_foundation_transform(best_cell)
		_diag["solved_pos"] = found_solved.origin

		# Step 4f: Apply to ghost
		if ghost != null:
			ghost.global_transform = found_solved
			ghost.visible = true

		# Step 4f1: Size validation — collision and mesh must match canonical tile
		if ghost != null:
			var col_check: CollisionShape3D = ghost.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col_check != null and col_check.shape != null and col_check.shape is BoxShape3D:
				var box: BoxShape3D = col_check.shape as BoxShape3D
				_diag["collision_size"] = box.size
				var sz_err_x: float = absf(box.size.x - FOUNDATION_WIDTH)
				var sz_err_z: float = absf(box.size.z - FOUNDATION_DEPTH)
				var sz_err_y: float = absf(box.size.y - FOUNDATION_THICKNESS)
				if sz_err_x > 0.01 or sz_err_z > 0.01 or sz_err_y > 0.01:
					_diag["final"] = "INVALID"
					_diag["invalid_reason"] = "FOUNDATION SIZE MISMATCH: coll=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f)" % [box.size.x, box.size.y, box.size.z, FOUNDATION_WIDTH, FOUNDATION_THICKNESS, FOUNDATION_DEPTH]
					_diag["error_category"] = "SIZE_ERROR"
					return {"valid": false}
			# Also verify mesh AABB matches canonical tile
			var stack_check: Array[Node] = ghost.get_children()
			while not stack_check.is_empty():
				var cn: Node = stack_check.pop_back()
				if cn is MeshInstance3D:
					var aabb: AABB = (cn as MeshInstance3D).get_aabb()
					_diag["mesh_size"] = aabb.size
					var msz_x: float = absf(aabb.size.x - FOUNDATION_WIDTH)
					var msz_z: float = absf(aabb.size.z - FOUNDATION_DEPTH)
					var msz_y: float = absf(aabb.size.y - FOUNDATION_THICKNESS)
					if msz_x > 0.01 or msz_z > 0.01 or msz_y > 0.01:
						_diag["final"] = "INVALID"
						_diag["invalid_reason"] = "FOUNDATION MESH SIZE MISMATCH: mesh=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z, FOUNDATION_WIDTH, FOUNDATION_THICKNESS, FOUNDATION_DEPTH]
						_diag["error_category"] = "SIZE_ERROR"
						return {"valid": false}
					break  # only check first MeshInstance3D
				for cc in cn.get_children():
					stack_check.append(cc)

		# Step 4f2: Height validation — canonical deck height is the single source of truth
		var structural_deck_y: float = _get_structural_deck_y()
		var foundation_top_y: float = found_solved.origin.y + FOUNDATION_HALF_HEIGHT
		var height_error: float = absf(foundation_top_y - structural_deck_y)
		_diag["foundation_top_y"] = foundation_top_y
		_diag["raft_deck_y"] = structural_deck_y
		_diag["height_error"] = height_error
		if height_error > 0.01:
			_diag["invalid_reason"] = "HEIGHT MISMATCH: %.3fm" % height_error
			_diag["error_category"] = "HEIGHT_ERROR"
			return {"valid": false}

		# Step 4g: Verify socket connection
		var found_piece_temp: Node3D = found_scene.instantiate()
		var socket_err: float = _verify_foundation_connection(support, best_cell, found_solved, found_piece_temp)
		found_piece_temp.queue_free()
		_diag["socket_position_valid"] = socket_err <= 0.1

		# Step 4h: Overlap check
		var found_shape: Shape3D = _get_validation_shape(found_scene)
		var found_overlap := _check_overlap(found_shape, found_solved, support)
		_diag["overlap_valid"] = found_overlap.size() == 0
		_diag["overlap_count"] = found_overlap.size()
		if found_overlap.size() > 0:
			var hit_obj: PhysicsBody3D = found_overlap[0].get("collider") as PhysicsBody3D
			if hit_obj != null and is_instance_valid(hit_obj):
				_diag["overlap_object"] = hit_obj.name
			else:
				_diag["overlap_object"] = "?"
			_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
			_diag["error_category"] = "COLLISION_ERROR"
			return {"valid": false}

		# All checks passed
		_diag["final"] = "VALID"
		# Hard validation: ghost cell must match candidate cell
		var ghost_grid_cell: Vector2i = _world_to_grid(ghost.global_position)
		_diag["ghost_grid_cell"] = ghost_grid_cell
		_diag["cell_match"] = ghost_grid_cell == best_cell
		if ghost_grid_cell != best_cell:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "GHOST CELL MISMATCH: ghost=%s candidate=%s" % [str(ghost_grid_cell), str(best_cell)]
			_diag["error_category"] = "GRID_ERROR"
			return {"valid": false}
		# Hard validation: ghost must be horizontal (not vertical)
		var ghost_x_rot: float = ghost.global_rotation.x
		var ghost_z_rot: float = ghost.global_rotation.z
		_diag["ghost_rot_x"] = rad_to_deg(ghost_x_rot)
		_diag["ghost_rot_z"] = rad_to_deg(ghost_z_rot)
		if absf(ghost_x_rot) > 0.1 or absf(ghost_z_rot) > 0.1:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "FOUNDATION ROTATION INVALID: X=%.1f Z=%.1f" % [rad_to_deg(ghost_x_rot), rad_to_deg(ghost_z_rot)]
			_diag["error_category"] = "ROTATION_ERROR"
			return {"valid": false}
		# Hard validation: Foundation footprint must not overlap any occupied cell.
		# Use the RAFT transform (not support) for consistent grid mapping.
		# Shrink corners slightly to avoid false positives at exact cell boundaries.
		# A 2m Foundation at a 2m cell fills exactly that cell; edge contact with
		# neighbors is valid (touching ≠ overlap).
		var raft_ft: Node3D = _get_raft_node()
		var flat_xf: Transform3D = _get_flat_support_transform(raft_ft) if raft_ft else Transform3D()
		var inv_xf: Transform3D = flat_xf.affine_inverse()
		var half_ext: float = FOUNDATION_HALF_WIDTH
		var grid_eps: float = 0.0001
		var footprint_corners: Array[Vector2i] = []
		var corner_offsets: Array[Vector2] = [
			Vector2(-half_ext + grid_eps, -half_ext + grid_eps),
			Vector2(half_ext - grid_eps, -half_ext + grid_eps),
			Vector2(half_ext - grid_eps, half_ext - grid_eps),
			Vector2(-half_ext + grid_eps, half_ext - grid_eps),
		]
		for co in corner_offsets:
			var world_c: Vector3 = found_solved * Vector3(co.x, 0.0, co.y)
			var local_c: Vector3 = inv_xf * world_c
			var fc: Vector2i = Vector2i(int(roundf(local_c.x / FOUNDATION_WIDTH)), int(roundf(local_c.z / FOUNDATION_DEPTH)))
			if not footprint_corners.has(fc):
				footprint_corners.append(fc)
		_diag["footprint_cells"] = footprint_corners
		var footprint_valid: bool = true
		var overlap_cell: Vector2i = Vector2i.ZERO
		for fc in footprint_corners:
			if fc != best_cell:
				# Footprint extends outside target cell — check if it overlaps an occupied cell
				if _grid_occupancy.has(fc):
					footprint_valid = false
					overlap_cell = fc
					break
		_diag["footprint_valid"] = footprint_valid
		if not footprint_valid:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "FOOTPRINT OVERLAP: cell %s occupied" % str(overlap_cell)
			_diag["error_category"] = "FOOTPRINT_ERROR"
			return {"valid": false}
		if debug_building and ghost != null:
			var mesh_aabb: AABB = AABB()
			var collision_aabb: AABB = AABB()
			# Recursively find MeshInstance3D (may be under MeshPivot)
			var stack: Array[Node] = ghost.get_children()
			while not stack.is_empty():
				var cn: Node = stack.pop_back()
				if cn is MeshInstance3D:
					mesh_aabb = (cn as MeshInstance3D).get_aabb()
				if cn is CollisionShape3D:
					var col: CollisionShape3D = cn as CollisionShape3D
					if col.shape is BoxShape3D:
						var box: BoxShape3D = col.shape as BoxShape3D
						collision_aabb = AABB(-box.size * 0.5, box.size)
				for cc in cn.get_children():
					stack.append(cc)
			_diag["mesh_aabb_min"] = ghost.global_transform * mesh_aabb.position
			_diag["mesh_aabb_max"] = ghost.global_transform * (mesh_aabb.position + mesh_aabb.size)
			_diag["collision_size"] = collision_aabb.size
			_diag["ghost_global_pos"] = ghost.global_position
			_diag["ghost_grid_cell"] = ghost_grid_cell
		if debug_building and debug_key != _last_debug_key:
			print("=== FOUNDATION GRID BUILD ===")
			print("  Support: %s cell %s" % [str(_diag.get("support_name", "?")), str(_diag.get("support_cell", Vector2i.ZERO))])
			print("  Aim side: %s" % str(_diag.get("aim_side", Vector2i.ZERO)))
			print("  Target cell: %s" % str(_diag.get("target_cell", Vector2i.ZERO)))
			print("  Solved pos: %s" % str(_diag.get("solved_pos", Vector3.ZERO)))
			print("  Socket err: %s" % str(_diag.get("socket_position_error", -1.0)))
			print("  Overlap: %s" % str(_diag.get("overlap_valid", true)))
			print("  Footprint: %s cells=%s" % [str(_diag.get("footprint_valid", true)), str(_diag.get("footprint_cells", []))])
			print("  Ghost cell: %s match=%s" % [str(_diag.get("ghost_grid_cell", Vector2i.ZERO)), str(_diag.get("cell_match", false))])
			print("  Height: raft=%.3f found=%.3f err=%.3fm" % [_diag.get("raft_deck_y", 0.0), _diag.get("foundation_top_y", 0.0), _diag.get("height_error", 0.0)])
			print("============================")
		# Return with the connecting socket for _try_build
		var connect_socket: BuildSocket = _find_connecting_socket(support, best_cell)
		return {"valid": true, "socket": connect_socket, "transform": found_solved, "cell": best_cell, "support": support}

	# ============================================================
	# NON-FOUNDATION: Socket-based placement (Wall, Window, etc.)
	# ============================================================
	# Step 4: Find target socket on the support
	var socket: BuildSocket = _find_best_socket(support, piece_name, effective_aim_point, effective_aim_normal)
	if socket == null:
		_diag["invalid_reason"] = "NO SOCKET"
		_diag["error_category"] = "SOCKET_ERROR"
		return {"valid": false}
	_diag["target_socket_name"] = socket.name
	_diag["target_socket_pos"] = socket.global_position
	if socket.is_occupied:
		_diag["invalid_reason"] = "SOCKET OCCUPIED"
		_diag["error_category"] = "SOCKET_ERROR"
		return {"valid": false}

	# Step 5: Find reciprocal socket on new piece
	var new_piece_idx: int = BUILD_RECIPE_NAMES.find(piece_name)
	if new_piece_idx == -1:
		_diag["invalid_reason"] = "INVALID BUILD SCENE"
		return {"valid": false}
	var new_piece_scene: PackedScene = build_pieces[new_piece_idx]
	var new_piece_temp: Node3D = new_piece_scene.instantiate()
	var support_piece_name: String = _find_piece_name(support)
	var effective_support_name: String = support_piece_name
	if support_piece_name == "Raft":
		effective_support_name = "Foundation"
	var new_piece_socket: BuildSocket = _find_reciprocal_socket(socket, new_piece_temp, effective_support_name)
	if new_piece_socket == null:
		var all_sockets: Array[BuildSocket] = _get_all_sockets(new_piece_temp)
		if not all_sockets.is_empty():
			new_piece_socket = all_sockets[0]
	if new_piece_socket == null:
		_diag["invalid_reason"] = "MISSING SOCKET"
		new_piece_temp.queue_free()
		return {"valid": false}
	_diag["new_socket_name"] = new_piece_socket.name

	# Step 6: Solve transform
	var solved: Transform3D
	solved = _solve_socket_transform(socket, new_piece_socket.position, support)
	_diag["solved_pos"] = solved.origin

	# Step 7: Apply to ghost and verify socket alignment
	if ghost != null:
		ghost.global_transform = solved
		ghost.visible = true

	var flat_target_pos: Vector3 = _get_flat_support_transform(support) * socket.position
	if ghost != null:
		var ghost_sockets: Array[BuildSocket] = _get_all_sockets(ghost)
		for gs in ghost_sockets:
			if gs.name == new_piece_socket.name:
				var actual_pos: Vector3 = gs.global_position
				var socket_err: float = actual_pos.distance_to(flat_target_pos)
				_diag["actual_socket_pos"] = actual_pos
				_diag["socket_position_error"] = socket_err
				_diag["socket_position_valid"] = socket_err <= 0.05
				if socket_err > 0.05:
					_diag["invalid_reason"] = "SOCKET MISMATCH: " + str(snappedf(socket_err, 0.001)) + "m"
					_diag["error_category"] = "TRANSFORM_ERROR"
					new_piece_temp.queue_free()
					return {"valid": false}
				break

	# Step 8: Gap / penetration measurement
	var gap: float = _measure_edge_gap(support, socket, solved, new_piece_temp, new_piece_socket)
	_diag["edge_gap"] = gap
	_diag["gap_valid"] = absf(gap) < 0.05
	if absf(gap) >= 0.05:
		if gap < 0.0:
			_diag["invalid_reason"] = "PENETRATION: " + str(snappedf(gap, 0.001)) + "m"
		else:
			_diag["invalid_reason"] = "GAP: " + str(snappedf(gap, 0.001)) + "m"
		_diag["error_category"] = "GEOMETRY_ERROR"
		new_piece_temp.queue_free()
		return {"valid": false}

	# Step 9: Overlap check
	var shape: Shape3D = _get_validation_shape(build_pieces[new_piece_idx])
	var overlap_hits := _check_overlap(shape, solved, support)
	_diag["overlap_valid"] = overlap_hits.size() == 0
	_diag["overlap_count"] = overlap_hits.size()
	if overlap_hits.size() > 0:
		var hit_obj: PhysicsBody3D = overlap_hits[0].get("collider") as PhysicsBody3D
		if hit_obj != null and is_instance_valid(hit_obj):
			_diag["overlap_object"] = hit_obj.name
		else:
			_diag["overlap_object"] = "?"
		_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
		_diag["error_category"] = "COLLISION_ERROR"
		new_piece_temp.queue_free()
		return {"valid": false}

	new_piece_temp.queue_free()

	# All checks passed
	_diag["final"] = "VALID"
	if debug_building and ghost != null:
		var mesh_aabb: AABB = AABB()
		var collision_aabb: AABB = AABB()
		var mesh_off: Vector3 = Vector3.ZERO
		for c in ghost.get_children():
			if c is MeshInstance3D:
				mesh_aabb = c.get_aabb()
				mesh_off = c.position
			if c is CollisionShape3D:
				var col: CollisionShape3D = c as CollisionShape3D
				if col.shape is BoxShape3D:
					var box: BoxShape3D = col.shape as BoxShape3D
					collision_aabb = AABB(-box.size * 0.5, box.size)
					mesh_off = c.position
		_diag["mesh_offset"] = mesh_off
		_diag["mesh_aabb_min"] = ghost.global_transform * mesh_aabb.position
		_diag["mesh_aabb_max"] = ghost.global_transform * (mesh_aabb.position + mesh_aabb.size)
		_diag["collision_size"] = collision_aabb.size
		_diag["ghost_global_pos"] = ghost.global_position
	if debug_building and _diag.get("final", "") == "VALID":
		print("=== BUILD VERIFY ===")
		print("  Solved pos: %s" % str(_diag.get("solved_pos", Vector3.ZERO)))
		print("  Ghost pos:  %s" % str(_diag.get("ghost_global_pos", Vector3.ZERO)))
		print("  Socket err: %s" % str(_diag.get("socket_position_error", -1.0)))
		print("  Mesh AABB:  %s -> %s" % [str(_diag.get("mesh_aabb_min", Vector3.ZERO)), str(_diag.get("mesh_aabb_max", Vector3.ZERO))])
		print("  Mesh off:   %s" % str(_diag.get("mesh_offset", Vector3.ZERO)))
		print("  Coll size:  %s" % str(_diag.get("collision_size", Vector3.ZERO)))
		print("  Support:    %s" % str(_diag.get("support_name", "?")))
		print("  Target:     %s at %s" % [str(_diag.get("target_socket_name", "?")), str(_diag.get("target_socket_pos", Vector3.ZERO))])
		print("  Actual:     %s at %s" % [str(_diag.get("new_socket_name", "?")), str(_diag.get("actual_socket_pos", Vector3.ZERO))])
		print("====================")
	return {"valid": true, "socket": socket, "transform": solved}


# ============================================================
# BUILD SYSTEM — GHOST PREVIEW
# ============================================================
func _update_build_preview() -> void:
	if ghost == null:
		return
	var piece_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
	_ensure_ghost_materials()
	var resolved := _resolve_placement(piece_name, aim_point)
	if not bool(resolved.get("valid", false)):
		ghost.visible = false
		build_valid = false
		_ghost_target_socket = null
		_ghost_cell = Vector2i(999999, 999999)
		_ghost_support = null
		return
	ghost.visible = true
	var xform: Transform3D = resolved["transform"]
	_ghost_target_socket = resolved["socket"]
	_ghost_transform = xform
	_ghost_cell = resolved.get("cell", Vector2i(999999, 999999))
	_ghost_support = resolved.get("support", null)
	ghost.global_transform = xform
	build_valid = true
	_apply_ghost_material(build_valid)
	if debug_building:
		_update_debug_markers()

func _ensure_ghost_materials() -> void:
	if _ghost_valid_mat == null:
		_ghost_valid_mat = StandardMaterial3D.new()
		_ghost_valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_valid_mat.albedo_color = Color(0.2, 0.9, 0.2, 0.5)
		_ghost_valid_mat.no_depth_test = true
	if _ghost_invalid_mat == null:
		_ghost_invalid_mat = StandardMaterial3D.new()
		_ghost_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_invalid_mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		_ghost_invalid_mat.no_depth_test = true

func _apply_ghost_material(valid: bool) -> void:
	if ghost == null:
		return
	var mat: StandardMaterial3D = _ghost_valid_mat if valid else _ghost_invalid_mat
	# Recursively find all MeshInstance3D (may be under MeshPivot)
	var stack: Array[Node] = ghost.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

# Debug markers: show target socket (blue) and actual ghost socket (yellow)
var _debug_markers_root: Node3D = null
var _debug_target_marker: MeshInstance3D = null
var _debug_actual_marker: MeshInstance3D = null

func _update_debug_markers() -> void:
	if _debug_markers_root == null:
		_debug_markers_root = Node3D.new()
		_debug_markers_root.name = "BuildDebugMarkers"
		get_tree().current_scene.add_child(_debug_markers_root)
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.05
		var blue_mat: StandardMaterial3D = StandardMaterial3D.new()
		blue_mat.albedo_color = Color(0.2, 0.4, 1.0)
		blue_mat.no_depth_test = true
		_debug_target_marker = MeshInstance3D.new()
		_debug_target_marker.mesh = sphere
		_debug_target_marker.set_surface_override_material(0, blue_mat)
		_debug_markers_root.add_child(_debug_target_marker)
		var yellow_mat: StandardMaterial3D = StandardMaterial3D.new()
		yellow_mat.albedo_color = Color(1.0, 1.0, 0.0)
		yellow_mat.no_depth_test = true
		_debug_actual_marker = MeshInstance3D.new()
		_debug_actual_marker.mesh = sphere
		_debug_actual_marker.set_surface_override_material(0, yellow_mat)
		_debug_markers_root.add_child(_debug_actual_marker)
	if _ghost_target_socket != null and _debug_target_marker != null:
		var flat_sf: Transform3D = _get_flat_support_transform(_ghost_target_socket.get_parent_piece())
		var tpos: Vector3 = flat_sf * _ghost_target_socket.position
		_debug_target_marker.global_position = tpos
		_debug_target_marker.visible = true
	else:
		if _debug_target_marker != null:
			_debug_target_marker.visible = false
	if ghost != null and ghost.visible and _debug_actual_marker != null:
		var new_socket_name: String = str(_diag.get("new_socket_name", ""))
		var sockets: Array[BuildSocket] = _get_all_sockets(ghost)
		for gs in sockets:
			if gs.name == new_socket_name:
				_debug_actual_marker.global_position = gs.global_position
				_debug_actual_marker.visible = true
				return
			_debug_actual_marker.visible = false
	else:
		if _debug_actual_marker != null:
			_debug_actual_marker.visible = false

# ============================================================
# BUILD SYSTEM — TRY BUILD (CONFIRM)
# ============================================================
func _try_build() -> void:
	if not build_valid or _ghost_target_socket == null:
		return
	var piece_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
	if not Inventory.can_afford(piece_name):
		return
	if not Inventory.craft(piece_name):
		return
	var scene: PackedScene = build_pieces[selected_piece_index]
	var piece: Node3D = scene.instantiate()
	# ALWAYS parent under the actual raft — NOT the socket's parent_raft.
	# When building from a Foundation, get_parent_raft() returns the Foundation
	# (it is in build_surface group). Parenting there causes the piece local
	# transform to be relative to the Foundation, not the raft, shifting the
	# final world position by the Foundation's offset.
	var raft: Node3D = _get_raft_node()
	if raft == null:
		piece.queue_free()
		return
	var container: Node = raft.get_node_or_null("BuiltPieces")
	if container == null:
		container = Node3D.new()
		container.name = "BuiltPieces"
		raft.add_child(container)
	# Disable collision BEFORE adding to tree to prevent pushing the player
	var piece_col: CollisionShape3D = piece.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if piece_col != null:
		piece_col.disabled = true
	container.add_child(piece)
	# Use the EXACT candidate cell from preview — never recompute from
	# world position, which can drift between preview and E press frames.
	var cell: Vector2i = _ghost_cell
	if cell == Vector2i(999999, 999999):
		# Fallback: recompute from ghost world transform
		var flat_xf: Transform3D = _get_flat_support_transform(raft)
		var inv_xf: Transform3D = flat_xf.affine_inverse()
		var local_pos: Vector3 = inv_xf * _ghost_transform.origin
		cell = Vector2i(int(roundf(local_pos.x / FOUNDATION_WIDTH)), int(roundf(local_pos.z / FOUNDATION_DEPTH)))
	# Place piece at raft-local position so it follows raft tilt/movement
	# EXACT grid formula — same as _compute_foundation_transform
	var raft_local_pos: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
	var raft_local_basis: Basis = Basis(Vector3.UP, build_rotation)
	piece.transform = Transform3D(raft_local_basis, raft_local_pos)
	# Re-enable collision after physics frame settles (prevents pushing player)
	if piece_col != null:
		piece_col.set_deferred("disabled", false)
	piece.add_to_group("build_surface")
	_ghost_target_socket.occupy(piece)
	_link_reciprocal_socket(piece, _ghost_target_socket)
	# Register in grid using the exact preview cell
	_grid_register(cell, piece)
	# Register buoyancy sample
	var sample: Node = piece.get_node_or_null("SampleMarker")
	if sample == null:
		sample = piece.get_node_or_null("F1")
	if sample != null and raft.has_method("register_sample_point"):
		raft.register_sample_point(sample)
	if debug_building:
		print("[BUILD] === PRE-BUILD SNAPSHOT ===")
		print("  Preview cell: %s" % str(_ghost_cell))
		print("  Preview world: %s" % str(_ghost_transform.origin))
		print("  Preview socket: %s" % str(_ghost_target_socket.name if _ghost_target_socket else "NULL"))
		print("[BUILD] === POST-BUILD SNAPSHOT ===")
		print("  Built cell: %s" % str(cell))
		print("  Piece world: %s" % str(piece.global_position))
		print("  Piece local: %s" % str(piece.position))
		print("  Cell match: %s" % str(_ghost_cell == cell))
		var pos_err: float = piece.global_position.distance_to(_ghost_transform.origin)
		print("  Position error: %.4fm" % pos_err)
		print("[BUILD] Placed %s at cell %s" % [piece_name, str(cell)])
		print("[BUILD] Grid occupancy: %d pieces" % _grid_occupancy.size())
		for key in _grid_occupancy:
			var p: Node3D = _grid_occupancy[key] as Node3D
			var pname: String
			if p != null and is_instance_valid(p):
				pname = p.name
			else:
				pname = "NULL"
			print("  %s -> %s" % [str(key), pname])

func _link_reciprocal_socket(new_piece: Node3D, parent_socket: BuildSocket) -> void:
	var best: BuildSocket = null
	var best_dist: float = 0.35
	var pp: Node3D = parent_socket.get_parent_piece()
	var fp: Transform3D = _get_flat_support_transform(pp) if pp != null else Transform3D()
	var pfp: Vector3 = fp * parent_socket.position
	for s in _get_all_sockets(new_piece):
		var d: float = s.global_position.distance_to(pfp)
		if d < best_dist:
			best_dist = d
			best = s
	if best != null:
		var parent_piece_of_socket := parent_socket.get_parent_piece()
		best.occupy(parent_piece_of_socket if parent_piece_of_socket != null else new_piece)

# ============================================================
# BUILD SYSTEM — EDIT SYSTEM
# ============================================================
const RECIPE_REFUND := {
	"Foundation": {"Wood": 5},
	"Wall": {"Wood": 8, "Rope": 1},
	"Stairs": {"Wood": 6, "Rope": 1},
	"Door": {"Wood": 4, "Rope": 1},
	"Window": {"Wood": 3, "Plastic": 1},
}

func _find_editable_target(collider: Node3D) -> Node3D:
	var current: Node = collider
	for _i in range(5):
		if current == null:
			break
		if current is Node3D and current.get_node_or_null("BuildSockets") != null:
			if current.name == "Raft" or current.is_in_group("raft"):
				return null
			if current == ghost:
				return null
			return current as Node3D
		current = current.get_parent()
	return null

func _start_edit(target: Node3D) -> void:
	_editing = target
	_edit_original_pos = target.global_position
	_edit_original_rot = target.rotation
	var col := target.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true
	for child in target.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
			mat.no_depth_test = true
			child.set_surface_override_material(0, mat)
	if ghost:
		ghost.visible = false

func _update_edit_follow() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	_ensure_ghost_materials()
	var piece_name := _piece_name_from_node(_editing)
	var resolved := _resolve_placement(piece_name, aim_point)
	if not bool(resolved.get("valid", false)):
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var xform: Transform3D = resolved["transform"]
	_editing.global_transform = xform
	_edit_last_pos = xform.origin
	_edit_valid = true
	_set_edit_color(_ghost_valid_mat)

func _confirm_edit() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	if not _edit_valid:
		return
	var col := _editing.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = false
	_apply_building_color(_editing)
	# Update grid
	var cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_register(cell, _editing)
	_editing = null

func _remove_editing() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	var building_name := _editing.name
	# Unregister from grid
	var cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_unregister(cell)
	for recipe_name in RECIPE_REFUND:
		if building_name.begins_with(recipe_name):
			var refund: Dictionary = RECIPE_REFUND[recipe_name]
			for item in refund:
				Inventory.add(item, refund[item])
			break
	_editing.queue_free()
	_editing = null

func _set_edit_color(mat: StandardMaterial3D) -> void:
	if _editing == null:
		return
	for child in _editing.get_children():
		if child is MeshInstance3D:
			child.set_surface_override_material(0, mat)

func _apply_building_color(obj: Node3D) -> void:
	if obj.name.begins_with("Door"):
		for child in obj.get_children():
			if child is MeshInstance3D:
				child.set_surface_override_material(0, null)
		return
	var building_name := obj.name
	if building_name.begins_with("Window"):
		for child in obj.get_children():
			if child is MeshInstance3D:
				child.set_surface_override_material(0, null)
		return
	var color := Color(0.72, 0.53, 0.30)
	if building_name.begins_with("Wall"):
		color = Color(0.62, 0.43, 0.22)
	elif building_name.begins_with("Stairs"):
		color = Color(0.55, 0.38, 0.20)
	for child in obj.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			child.set_surface_override_material(0, mat)

# ============================================================
# BUILD SYSTEM — SCENE VALIDATION
# ============================================================
func _validate_build_scene(scene: PackedScene, scene_name: String) -> void:
	var inst: Node3D = scene.instantiate()
	var errors: Array[String] = []
	if not (inst is Node3D):
		errors.append("Root is not Node3D")
	var has_mesh: bool = false
	for child in inst.get_children():
		if child is MeshInstance3D:
			has_mesh = true
			break
	if not has_mesh:
		errors.append("No MeshInstance3D found")
	var col := inst.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		errors.append("No CollisionShape3D found")
	elif col.shape == null:
		errors.append("CollisionShape3D has no shape")
	var sockets_node := inst.get_node_or_null("BuildSockets")
	if sockets_node == null:
		errors.append("No BuildSockets node")
	else:
		var socket_names: Dictionary = {}
		for c in sockets_node.get_children():
			if c is BuildSocket:
				if socket_names.has(c.name):
					errors.append("Duplicate socket: " + c.name)
				socket_names[c.name] = true
	if errors.size() > 0:
		print("[BUILD ERROR] " + scene_name + ":")
		for e in errors:
			print("  - " + e)
	else:
		print("[BUILD OK] " + scene_name + " validated")
	inst.queue_free()

# ============================================================
# HUD
# ============================================================
func _create_hud() -> void:
	_hud_label = Label.new()
	_hud_label.name = "InventoryHUD"
	_hud_label.add_theme_font_size_override("font_size", 18)
	_hud_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_hud_label.position = Vector2(15, 15)
	_hud_label.size = Vector2(400, 400)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_hud_label)

func _update_hud() -> void:
	if _hud_label == null:
		return
	var text := ""
	for item_name in Inventory.items:
		var count: int = Inventory.items[item_name]
		if count > 0 or item_name in ["Wood", "Rope", "Plastic", "Metal"]:
			text += item_name + ": " + str(count) + "\n"
	if _editing != null:
		text += "\n--- EDIT MODE ---"
		text += "\nDouble-click: Pick up"
		text += "\nE=Place here (green only)"
		text += "\nR/Y=Rotate  X=Tilt  Del=Remove (+refund)"
		text += "\nB=Cancel"
	elif build_mode:
		var recipe_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
		var status := "[INVALID]" if not build_valid else "[VALID]"
		text += "\n--- BUILD MODE ---"
		text += "\nPiece: " + recipe_name
		text += "\nStatus: " + status
		if Inventory.can_afford(recipe_name):
			text += "\nCost: OK"
		else:
			text += "\nCost: NEED MORE"
		text += "\nR/Y=Rotate  Tab=Switch  E=Place  B=Exit"
		if debug_building and _diag.size() > 0:
			text += _format_debug_hud()
		elif not build_valid and _diag.size() > 0:
			var reason: String = str(_diag.get("invalid_reason", ""))
			if reason != "":
				text += "\nReason: " + reason
	_hud_label.text = text

func _format_debug_hud() -> String:
	var d: String = ""
	d += "\n--- BUILD DEBUG ---"
	d += "\nPiece: " + str(_diag.get("piece", "?"))
	d += "\nAim: " + _yn(_diag.get("has_aim", false))
	if bool(_diag.get("has_aim", false)):
		d += "\n  Pos: " + str(_diag.get("aim_pos", Vector3.ZERO))
		d += "\n  Normal: " + str(_diag.get("aim_norm", Vector3.FORWARD))
		d += "\n  Collider: " + str(_diag.get("aim_collider_name", "?"))
	d += "\nSupport: " + str(_diag.get("support_name", "NONE"))
	if _diag.has("support_cell"):
		d += "\n  Cell: " + str(_diag.get("support_cell", Vector2i.ZERO))
	d += "\n  Path: " + _fmt_path(_diag.get("support_path", []))
	d += "\n  Valid: " + _yn(_diag.get("support_valid", false))
	if _diag.has("aim_side"):
		d += "\nAim Side: " + str(_diag.get("aim_side", Vector2i.ZERO))
	if _diag.has("target_cell"):
		d += "\nTarget Cell: " + str(_diag.get("target_cell", Vector2i.ZERO))
	d += "\nTarget Socket: " + str(_diag.get("target_socket_name", "NONE"))
	if _diag.has("target_socket_pos"):
		d += "\n  Pos: " + str(_diag.get("target_socket_pos", Vector3.ZERO))
	d += "\nNew Socket: " + str(_diag.get("new_socket_name", "NONE"))
	d += "\nSolved Pos: " + str(_diag.get("solved_pos", Vector3.ZERO))
	d += "\nSocket Error: " + str(_diag.get("socket_position_error", -1.0)) + "m"
	d += "\nEdge Gap: " + str(_diag.get("edge_gap", 0.0)) + "m"
	d += "\nOverlap: " + _yn(not bool(_diag.get("overlap_valid", true)))
	if int(_diag.get("overlap_count", 0)) > 0:
		d += "\n  Blocked by: " + str(_diag.get("overlap_object", "?"))
	d += "\nCorner: " + _yn(_diag.get("is_corner", false))
	var final_val: String = str(_diag.get("final", "INVALID"))
	var reason: String = str(_diag.get("invalid_reason", ""))
	d += "\nFinal: " + final_val
	if reason != "":
		d += "\nReason: " + reason
	var cat: String = str(_diag.get("error_category", ""))
	if cat != "":
		d += "\nCategory: " + cat
	# Tile dimension diagnostics
	d += "\n--- TILE DIMENSIONS ---"
	d += "\nTile: %.2f x %.2f x %.2f" % [FOUNDATION_WIDTH, FOUNDATION_DEPTH, FOUNDATION_THICKNESS]
	if _diag.has("collision_size"):
		var csz: Vector3 = _diag["collision_size"]
		d += "\nColl: %.2f x %.2f x %.2f" % [csz.x, csz.z, csz.y]
		var cx: float = absf(csz.x - FOUNDATION_WIDTH)
		var cz: float = absf(csz.z - FOUNDATION_DEPTH)
		var cy: float = absf(csz.y - FOUNDATION_THICKNESS)
		if cx > 0.01 or cz > 0.01 or cy > 0.01:
			d += "\n  ** SIZE MISMATCH **"
	if _diag.has("mesh_size"):
		var msz: Vector3 = _diag["mesh_size"]
		d += "\nMesh: %.2f x %.2f x %.2f" % [msz.x, msz.z, msz.y]
	# Geometry diagnostics
	if _diag.has("ghost_global_pos"):
		d += "\nGhost Pos: " + str(_diag.get("ghost_global_pos", Vector3.ZERO))
	if _diag.has("ghost_grid_cell"):
		d += "\nGhost Cell: " + str(_diag.get("ghost_grid_cell", Vector2i.ZERO))
	if _diag.has("cell_match"):
		d += "\nCell Match: " + _yn(_diag.get("cell_match", false))
	if _diag.has("footprint_valid"):
		d += "\nFootprint: " + _yn(_diag.get("footprint_valid", false))
	if _diag.has("footprint_cells"):
		d += "\n  Cells: " + str(_diag.get("footprint_cells", []))
	if _diag.has("ghost_rot_x"):
		d += "\nGhost Rot X: " + str(_diag.get("ghost_rot_x", 0.0)) + " deg"
		d += "\nGhost Rot Z: " + str(_diag.get("ghost_rot_z", 0.0)) + " deg"
	if _diag.has("mesh_aabb_min"):
		d += "\nMesh AABB: " + str(_diag.get("mesh_aabb_min", Vector3.ZERO)) + " -> " + str(_diag.get("mesh_aabb_max", Vector3.ZERO))
	if _diag.has("actual_socket_pos"):
		d += "\nActual Socket: " + str(_diag.get("actual_socket_pos", Vector3.ZERO))
	if _diag.has("foundation_top_y"):
		d += "\nFoundation Top: %.3f" % _diag.get("foundation_top_y", 0.0)
		d += "\nDeck Height: %.3f" % _diag.get("raft_deck_y", 0.0)
		d += "\nHeight Error: %.3fm" % _diag.get("height_error", 0.0)
	return d

static func _yn(val: Variant) -> String:
	return "YES" if val else "NO"

static func _fmt_path(path_arr: Variant) -> String:
	if path_arr is Array:
		var arr: Array = path_arr as Array
		if arr.is_empty():
			return "NONE"
		return " -> ".join(arr)
	return "NONE"
