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
const WALL_SURFACE_SNAP_RANGE: float = 4.0  # wall ghost snaps to a surface within this 2D distance
const WALL_STACK_AIM_TOLERANCE: float = 0.6  # aiming this close to a wall's top stacks a 2nd floor wall
const BUILD_ROTATION_STEP := PI / 2.0    # R / Y rotate 90°
const BUILD_ROTATION_FINE_STEP := PI / 12.0  # hold Shift for 15° fine steps (center walls)

# Grid & Foundation dimensions — single source of truth
const CELL_SIZE: float = 2.0  # kept for backward compat; prefer FOUNDATION_WIDTH/DEPTH
const FOUNDATION_WIDTH: float = 2.0
const FOUNDATION_DEPTH: float = 2.0
const FOUNDATION_THICKNESS: float = 0.30
const FOUNDATION_HALF_WIDTH: float = FOUNDATION_WIDTH * 0.5
const FOUNDATION_HALF_DEPTH: float = FOUNDATION_DEPTH * 0.5
const FOUNDATION_HALF_HEIGHT: float = FOUNDATION_THICKNESS * 0.5

var _roof_last_support: Node3D = null  # last support wall for roof hysteresis

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
# Build overlay: toggleable on-screen footprint samples + support ratio (F3)
var build_overlay: bool = false
var _f3_held: bool = false
@export_range(0.0, 1.0) var minimum_support_ratio: float = 0.50
@export var placement_surface_tolerance: float = 0.30
var _diag: Dictionary = {}

# Edit system state machine
var _editing: Node3D = null              # currently selected building (null = IDLE)
var _edit_original_transform: Transform3D = Transform3D()
var _edit_original_cell: Vector2i = Vector2i(999999, 999999)
var _edit_valid: bool = false
var _edit_candidate_transform: Transform3D = Transform3D()
var _edit_candidate_cell: Vector2i = Vector2i(999999, 999999)
# Double-click detection
var _last_click_time: float = 0.0
var _last_clicked_piece: Node3D = null
const DOUBLE_CLICK_TIME: float = 0.30

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
# E PICKUP (debris / toggle only — build placement uses P)
# ============================================================
func _handle_pickup() -> void:
	if not Input.is_action_just_pressed("interact"):
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
	# --- PRIORITY 1: Edit Mode ---
	if _editing != null:
		if Input.is_action_just_pressed("place_build"):
			_confirm_edit()
			return
		if Input.is_action_just_pressed("remove_build"):
			_remove_editing()
			return
		if Input.is_action_just_pressed("build"):
			_cancel_edit()
			return
		if Input.is_action_just_pressed("rotate_build"):
			_rotate_build()
		if Input.is_action_just_pressed("rotate_build_x"):
			_rotate_build_x()
		_update_edit_follow()
		crosshair.set_state(crosshair.State.BUILD)
		return
	# --- E double-click: pickup piece for editing (works in AND out of build mode) ---
	if Input.is_action_just_pressed("interact"):
		_handle_double_click_edit()
	# --- PRIORITY 2: Build Mode ---
	if Input.is_action_just_pressed("build"):
		_toggle_build()
	if Input.is_action_just_pressed("cycle_build") and build_mode:
		_cycle_build_piece()
	if build_mode and ghost:
		if Input.is_action_just_pressed("place_build"):
			_try_build()
		if Input.is_action_just_pressed("rotate_build"):
			_rotate_build()
		if Input.is_action_just_pressed("rotate_build_x"):
			_rotate_build_x()
		if Input.is_key_pressed(KEY_F3) and not _f3_held:
			build_overlay = not build_overlay
			if not build_overlay:
				_clear_overlay_markers()
		_f3_held = Input.is_key_pressed(KEY_F3)
		crosshair.set_state(crosshair.State.BUILD)
		_update_build_preview()
		return
	# --- PRIORITY 3: Normal gameplay ---
	_handle_pickup()
	if aim_valid and aim_collider != null and aim_collider.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
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
		_clear_overlay_markers()

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
	# Disable ALL collision shapes (some pieces have several, e.g. stairs steps)
	for col in ghost.find_children("*", "CollisionShape3D", true, false):
		(col as CollisionShape3D).disabled = true
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
	# Reset hysteresis when switching pieces
	_roof_last_support = null
	if build_mode:
		_spawn_ghost()

func _rotate_build() -> void:
	# Hold Shift for 15° fine steps (e.g. angling a center wall), otherwise 90°.
	var step: float = BUILD_ROTATION_FINE_STEP if Input.is_key_pressed(KEY_SHIFT) else BUILD_ROTATION_STEP
	build_rotation += step
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

# A cell is blocked when it holds a REAL placed piece. The raft itself is
# registered at (0,0) as a structural anchor but must NOT block placement —
# the player builds the first Foundation ON the raft (aiming at the raft deck
# should never snap the preview into the water).
func _grid_is_blocked(cell: Vector2i) -> bool:
	if not _grid_occupancy.has(cell):
		return false
	var occ: Node3D = _grid_occupancy[cell] as Node3D
	if occ == null or not is_instance_valid(occ):
		return false
	return occ != _get_raft_node()

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
	# A piece sitting ON the raft (or in a cardinal neighbor cell) is supported
	# directly — the raft is located from the scene node, NOT _grid_occupancy,
	# which is overwritten when the first Foundation is placed on the raft's
	# cell (without this, that Foundation fails its own structural check and
	# every later build returns NO STRUCTURAL SUPPORT).
	var raft_sn: Node3D = _get_raft_node()
	if raft_sn != null:
		var raft_cell_sn: Vector2i = _world_to_grid(raft_sn.global_position)
		var piece_cell_sn: Vector2i = _get_piece_cell(piece)
		if piece_cell_sn == raft_cell_sn:
			return true
		if absi(piece_cell_sn.x - raft_cell_sn.x) + absi(piece_cell_sn.y - raft_cell_sn.y) == 1:
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

# Determine which cardinal edge of a foundation the crosshair targets.
# Returns the foundation edge socket name (e.g. "Socket_North").
func _select_wall_edge(foundation: Node3D, aim_world: Vector3) -> String:
	var flat_xf: Transform3D = _get_flat_support_transform(foundation)
	var local_aim: Vector3 = flat_xf.affine_inverse() * aim_world
	var half_w: float = FOUNDATION_HALF_WIDTH
	# Perpendicular distance from aim to each edge line in local space.
	var dist_n: float = absf(local_aim.z - half_w)
	var dist_s: float = absf(local_aim.z + half_w)
	var dist_e: float = absf(local_aim.x - half_w)
	var dist_w: float = absf(local_aim.x + half_w)
	var edges: Array = [
		{"name": "Socket_North", "dist": dist_n, "out": Vector3(0, 0, 1)},
		{"name": "Socket_South", "dist": dist_s, "out": Vector3(0, 0, -1)},
		{"name": "Socket_East",  "dist": dist_e, "out": Vector3(1, 0, 0)},
		{"name": "Socket_West",  "dist": dist_w, "out": Vector3(-1, 0, 0)},
	]
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var best_name: String = edges[0]["name"]
	var best_dist: float = edges[0]["dist"]
	# Corner tolerance — when two edges are close, use camera direction to break tie.
	const CORNER_TOL: float = 0.25
	var candidates: Array = []
	for e in edges:
		if e["dist"] <= best_dist + CORNER_TOL:
			candidates.append(e)
	if candidates.size() == 1:
		return candidates[0]["name"]
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var cam_flat: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var best_score: float = -INF
	for e in candidates:
		var score: float = cam_flat.dot(e["out"])
		if score > best_score:
			best_score = score
			best_name = e["name"]
	return best_name

# Edge-snapping wall placement: wall snaps to the foundation edge the crosshair targets.
# The wall's width runs along the edge; the wall also SLIDES along the edge to follow
# the crosshair, so corners and any point along the edge work. Edge rotation is
# computed from the socket position.
func _compute_wall_transform(foundation: Node3D, aim_world: Vector3) -> Transform3D:
	var edge_name: String = _select_wall_edge(foundation, aim_world)
	var sockets_node: Node3D = foundation.get_node_or_null("BuildSockets")
	if sockets_node == null:
		return Transform3D()
	var edge_socket: Node3D = sockets_node.get_node_or_null(edge_name)
	if edge_socket == null:
		return Transform3D()
	# Flat transform of the foundation (no wave tilt).
	var flat_xf: Transform3D = _get_flat_support_transform(foundation)
	# Edge socket local position — e.g. (0, 0.15, 1) for North, (1, 0.15, 0) for East.
	var socket_local: Vector3 = edge_socket.position
	# Edge-specific rotation: wall width must run ALONG the edge.
	#   North/South edges (socket offset along Z): wall along X → no rotation.
	#   East/West  edges (socket offset along X): wall along Z → rotate 90°.
	# The slide axis is the direction the wall runs along.
	var edge_angle: float = 0.0
	var edge_axis: Vector3 = Vector3(1, 0, 0)
	if absf(socket_local.x) > absf(socket_local.z):
		edge_angle = PI * 0.5
		edge_axis = Vector3(0, 0, 1)
	# Combined rotation = edge rotation + player build_rotation.
	var total_rot: float = edge_angle + build_rotation
	# Slide the wall along the edge to follow the crosshair. `along` is the aim
	# projected onto the edge axis, relative to the edge socket (edge midpoint).
	var local_aim: Vector3 = flat_xf.affine_inverse() * aim_world
	var along: float = local_aim.dot(edge_axis) - socket_local.dot(edge_axis)
	# Clamp to the foundation extent — small inset so the wall's own footprint
	# samples stay on the surface when the wall is slid all the way to a corner.
	var max_slide: float = FOUNDATION_HALF_WIDTH - 0.1
	along = clampf(along, -max_slide, max_slide)
	# World position of the edge socket, slid along the edge axis.
	var target_local: Vector3 = socket_local + edge_axis * along
	var target_flat_pos: Vector3 = flat_xf * target_local
	# Wall Socket_Base local position (bottom center of the wall).
	var wall_base_local: Vector3 = Vector3(0, -1.25, 0)
	var rotated_offset: Vector3 = wall_base_local.rotated(Vector3.UP, total_rot)
	# Wall center = slid edge socket world pos − rotated base offset.
	var piece_center: Vector3 = target_flat_pos - rotated_offset
	# Wall basis = foundation basis rotated by combined angle.
	var piece_basis: Basis = flat_xf.basis.rotated(Vector3.UP, total_rot)
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
	# Get support socket direction in its parent piece's local space.
	# Use full 3D direction (do NOT zero Y) so vertical sockets like
	# Wall.Socket_Top (0, 1.25, 0) and Roof.Socket_Base (0, -0.075, 0)
	# are correctly identified as opposite-facing.
	var support_local_dir: Vector3 = support_socket.position
	if support_local_dir.length() > 0.001:
		support_local_dir = support_local_dir.normalized()
	else:
		support_local_dir = Vector3.FORWARD
	# STAIRS STACKING: the reciprocal for a stair is always its Socket_Base — the
	# diagonal sockets defeat the generic opposite-facing scoring, so pick it
	# directly when the support is a stair.
	if effective_support_name == "Stairs":
		for s in new_piece_sockets:
			if s != null and s.name == "Socket_Base" and s.is_compatible("Stairs"):
				return s
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
		# Direction-opposite bonus: reciprocal must face opposite direction.
		# Use full 3D direction so vertical sockets are handled correctly.
		var new_local_dir: Vector3 = s.position
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

# ============================================================
# BUILD SYSTEM — FOOTPRINT VALIDATION
# ============================================================
# Check if a node is a valid build surface (Foundation, Raft, or
# a building piece that itself sits on a valid surface).
func _is_build_surface(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var n: Node3D = node
	for _i in range(5):
		if n == null:
			break
		if n.is_in_group("build_surface"):
			return true
		var nm: String = n.name
		if nm.begins_with("Foundation") or nm.begins_with("Raft"):
			return true
		n = n.get_parent() as Node3D
	return false

# RIDs to exclude from wall-footprint support rays: the player, the preview
# ghost, and the piece being edited must never block detection of the buildable
# surface underneath the wall.
func _support_ray_excludes() -> Array[RID]:
	var ex: Array[RID] = [get_rid()]
	if ghost != null and is_instance_valid(ghost):
		ex.append(ghost.get_rid())
	if _editing != null and is_instance_valid(_editing):
		ex.append(_editing.get_rid())
	return ex

# Validate that a wall's bottom footprint is supported by build surfaces.
# Uses center-point priority: if the center ray hits a valid surface, the wall
# is valid. This prevents edge-floating-point misses from causing false INVALID.
func _validate_wall_footprint(wall_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var bottom_center: Vector3 = wall_xform.origin + wall_xform.basis * Vector3(0, -1.25, 0)
	var w_basis: Basis = wall_xform.basis
	var supported_count: int = 0
	var total_count: int = 0
	var foundation_height_sum: float = 0.0
	var foundation_hit_count: int = 0
	# --- Center-point check (highest priority) ---
	var center_supported: bool = false
	var center_ray_o: Vector3 = bottom_center + Vector3.UP * 1.0
	var center_ray_e: Vector3 = bottom_center + Vector3.DOWN * 3.0
	var center_q := PhysicsRayQueryParameters3D.create(center_ray_o, center_ray_e)
	center_q.collision_mask = 1
	center_q.exclude = _support_ray_excludes()
	var center_hit := space_state.intersect_ray(center_q)
	if center_hit:
		var ch_body: Node3D = center_hit.collider as Node3D
		if _is_build_surface(ch_body):
			var ch_diff: float = absf(bottom_center.y - center_hit.position.y)
			if ch_diff <= placement_surface_tolerance:
				center_supported = true
				foundation_height_sum += center_hit.position.y
				foundation_hit_count += 1
	# --- 3x3 grid sampling, counted per width-column ---
	# A wall is centered ON the deck edge: half its thickness hangs off into the
	# water, so only the inner half must rest on the surface. Counting each
	# width-column as supported when ANY of its depth samples hit prevents the
	# over-water half from wrongly invalidating edge placements (raft edges,
	# foundation edges, and walls slid to corners).
	var sample_count: int = 3
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
		var column_supported: bool = false
		for iz in range(sample_count):
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			# 40% inset from width edges to avoid floating-point boundary misses
			var local_off: Vector3 = w_basis * Vector3(tx * 0.6, 0.0, tz * 0.06)
			var sample_pos: Vector3 = bottom_center + local_off
			_sample_positions.append(sample_pos)
			var ray_o: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_e: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var q := PhysicsRayQueryParameters3D.create(ray_o, ray_e)
			q.collision_mask = 1
			q.exclude = _support_ray_excludes()
			var hit := space_state.intersect_ray(q)
			if hit:
				var hb: Node3D = hit.collider as Node3D
				if _is_build_surface(hb):
					var hd: float = absf(bottom_center.y - hit.position.y)
					if hd <= placement_surface_tolerance:
						column_supported = true
						foundation_height_sum += hit.position.y
						foundation_hit_count += 1
			_sample_supported.append(column_supported)
		if column_supported:
			supported_count += 1
		total_count += 1
	# Center support overrides grid result (prevents edge false-negatives)
	if center_supported and supported_count == 0:
		supported_count = 1
	if total_count == 0:
		total_count = 1
	var support_ratio: float = float(supported_count) / float(total_count)
	var valid: bool = center_supported or support_ratio >= minimum_support_ratio
	var foundation_height: float = foundation_height_sum / float(foundation_hit_count) if foundation_hit_count > 0 else 0.0
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["foundation_height"] = foundation_height
	_diag["bottom_height"] = bottom_center.y
	_diag["center_supported"] = center_supported
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = FOUNDATION_WIDTH * 0.5
	return {"valid": valid, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count, "foundation_height": foundation_height}

# Validate that a foundation's bottom footprint is supported.
func _validate_foundation_footprint(found_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var half_w: float = FOUNDATION_HALF_WIDTH
	var sample_count: int = 3
	var supported_count: int = 0
	var total_count: int = 0
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		for iz in range(sample_count):
			var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var local_off: Vector3 = Vector3(tx * half_w * 0.8, -FOUNDATION_HALF_HEIGHT, tz * half_w * 0.8)
			var sample_pos: Vector3 = found_xform * local_off
			var ray_origin: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_end: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1
			if ghost != null and is_instance_valid(ghost):
				query.exclude = [ghost.get_rid()]
			var result := space_state.intersect_ray(query)
			total_count += 1
			var sample_ok: bool = false
			if result:
				var hit_body: Node3D = result.collider as Node3D
				if _is_build_surface(hit_body):
					sample_ok = true
					supported_count += 1
			_sample_positions.append(sample_pos)
			_sample_supported.append(sample_ok)
	var support_ratio: float = float(supported_count) / float(total_count) if total_count > 0 else 0.0
	var valid: bool = support_ratio >= minimum_support_ratio
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = FOUNDATION_WIDTH * 0.5
	return {"valid": valid, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count}

# Validate that a roof's bottom corners are supported by build surfaces
# (wall tops, other roofs, foundations). Samples a 3x3 grid on the roof's
# bottom plane and records per-sample results for the build overlay.
func _validate_roof_footprint(roof_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var sample_count: int = 3
	var supported_count: int = 0
	var total_count: int = 0
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		for iz in range(sample_count):
			var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			# Bottom plane of the roof (0.15 thick): sample at half thickness below
			# center, inset 40% like the other footprint validators.
			var local_off: Vector3 = Vector3(tx * 0.6, -0.075, tz * 0.6)
			var sample_pos: Vector3 = roof_xform * local_off
			var ray_origin: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_end: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1
			if ghost != null and is_instance_valid(ghost):
				query.exclude = [ghost.get_rid()]
			var result := space_state.intersect_ray(query)
			total_count += 1
			var sample_ok: bool = false
			if result:
				var hit_body: Node3D = result.collider as Node3D
				if _is_build_surface(hit_body):
					sample_ok = true
					supported_count += 1
			_sample_positions.append(sample_pos)
			_sample_supported.append(sample_ok)
	# Support ratio from the actual per-cell measurements (matches the overlay
	# grid labels) rather than a raw hit count — the roof overhangs its wall
	# support, so outer cells honestly show partial/0% support.
	var percents: Array = _overlay_sample_percents(_sample_positions, _sample_supported)
	var pct_sum: float = 0.0
	for p in percents:
		pct_sum += p
	var support_ratio: float = pct_sum / (percents.size() * 100.0) if percents.size() > 0 else 0.0
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = 1.0
	return {"valid": support_ratio >= minimum_support_ratio, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count}

func _check_overlap(shape: Shape3D, xform: Transform3D, support: Node3D, extra_skip: Array[Node3D] = []) -> Array[Dictionary]:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = 1
	# Exclude the player and ghost via RID
	var excluded: Array[RID] = [get_rid()]
	if ghost != null and is_instance_valid(ghost):
		excluded.append(ghost.get_rid())
	if _editing != null and is_instance_valid(_editing):
		excluded.append(_editing.get_rid())
	query.exclude = excluded
	# Build set of support + all ancestors to filter out manually
	var skip_bodies: Array = []
	var excl_node: Node3D = support
	while excl_node != null and is_instance_valid(excl_node):
		skip_bodies.append(excl_node)
		excl_node = excl_node.get_parent() as Node3D
	# Also skip extra bodies (e.g. foundation under a wall)
	for extra in extra_skip:
		if extra != null and is_instance_valid(extra) and not skip_bodies.has(extra):
			skip_bodies.append(extra)
	# Also skip the editing piece and all its children
	if _editing != null and is_instance_valid(_editing):
		skip_bodies.append(_editing)
		for c in _editing.get_children():
			if c is Node3D:
				skip_bodies.append(c)
	var results: Array[Dictionary] = []
	var hits := space_state.intersect_shape(query, 8)
	for h in hits:
		var hit_body: Node3D = h.get("collider") as Node3D
		# Skip the support, its ancestors (raft, etc.), and the player
		if hit_body != null and skip_bodies.has(hit_body):
			continue
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
	# The raft anchors the grid: the cell it occupies and every cardinal
	# neighbor is directly supported by it (this lets the FIRST Foundation
	# be placed on or against the raft itself). The raft is located from the
	# scene node — NOT _grid_occupancy, which gets overwritten when the first
	# Foundation is placed on the raft's cell.
	var raft_node: Node3D = _get_raft_node()
	if raft_node != null:
		var raft_cell: Vector2i = _world_to_grid(raft_node.global_position)
		if cell == raft_cell:
			return true
		if absi(cell.x - raft_cell.x) + absi(cell.y - raft_cell.y) == 1:
			return true
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

	# Shared variables declared before branches to avoid CONFUSABLE_LOCAL_DECLARATION
	var solved: Transform3D = Transform3D()
	var new_piece_idx: int = BUILD_RECIPE_NAMES.find(piece_name)
	var shape: Shape3D = _get_validation_shape(build_pieces[new_piece_idx]) if new_piece_idx >= 0 else null
	var overlap_hits: Array[Dictionary] = []

	# Step 1: Aim — with build plane fallback for empty gaps
	var effective_aim_point: Vector3 = aim_point
	var effective_aim_normal: Vector3 = aim_normal
	var effective_collider: Node3D = aim_collider
	# For Foundation: use structural build plane for targeting.
	# For Wall: use ACTUAL ray hit — the player's crosshair determines which edge.
	if piece_name == "Foundation":
		var deck_y_bp: float = _get_structural_deck_y()
		var ray_o: Vector3 = camera.global_position
		var ray_d: Vector3 = -camera.global_transform.basis.z
		if absf(ray_d.y) > 0.001:
			var t_bp: float = (deck_y_bp - ray_o.y) / ray_d.y
			if t_bp > 0.0 and t_bp < AIM_DISTANCE:
				effective_aim_point = ray_o + ray_d * t_bp
				effective_aim_normal = Vector3.UP
	# Fallback: when ray misses OR hits a non-building object.
	# The crosshair determines the target — NOT nearest Foundation.
	# 1. Intersect the structural build plane to get exact aim position.
	# 2. Convert to grid cell.
	# 3. Look up the Foundation at that cell (or adjacent).
	var _hit_is_build: bool = aim_valid and aim_collider != null \
		and _find_support_piece(aim_collider) != null
	if not _hit_is_build:
		var raft: Node3D = _get_raft_node()
		if raft != null and build_mode:
			var deck_y: float = _get_structural_deck_y()
			var ray_origin: Vector3 = camera.global_position
			var ray_dir: Vector3 = -camera.global_transform.basis.z
			# Calculate build plane intersection (works even for horizontal camera)
			var _bp_t: float = -1.0
			if absf(ray_dir.y) > 0.001:
				_bp_t = (deck_y - ray_origin.y) / ray_dir.y
			else:
				# Horizontal camera: project 10m forward onto build plane
				_bp_t = 10.0
			if _bp_t > 0.0 and _bp_t < AIM_DISTANCE:
				effective_aim_point = ray_origin + ray_dir * _bp_t
				effective_aim_normal = Vector3.UP
				# Direct grid cell lookup — check aim cell + all neighbors
				var _aim_cell_fb: Vector2i = _world_to_grid(effective_aim_point)
				var _fb_foundation: Node3D = null
				var _fb_offsets: Array[Vector2i] = [
					Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0),
					Vector2i(0,1), Vector2i(0,-1),
					Vector2i(1,1), Vector2i(1,-1),
					Vector2i(-1,1), Vector2i(-1,-1),
				]
				for _off in _fb_offsets:
					var _cc: Vector2i = _aim_cell_fb + _off
					if _grid_occupancy.has(_cc):
						var _occ: Node3D = _grid_occupancy[_cc] as Node3D
						if _occ != null and is_instance_valid(_occ):
							var _fb_pn: String = _find_piece_name(_occ)
							if _fb_pn == "Foundation" or _fb_pn == "Raft":
								_fb_foundation = _occ
								break
				if _fb_foundation != null:
					effective_collider = _fb_foundation
					aim_valid = true
					aim_point = effective_aim_point
					aim_normal = effective_aim_normal
					aim_collider = _fb_foundation
					aim_distance = _bp_t
					# else: no Foundation under crosshair — stay invalid (RED)
	if (not aim_valid or effective_collider == null) and piece_name != "Wall" \
		and piece_name != "Roof" and piece_name != "Door" and piece_name != "Window":
		# Walls, Roofs, Doors and Windows handle the aim-less case themselves
		# (deck-plane projection + auto-snap), so they must not bail out here.
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
	# Wall and Roof resolve their own support in their specific sections below.
	# For them, skip the generic support check and let them handle it.
	var support: Node3D = _find_support_piece(effective_collider)
	if support == null and piece_name != "Wall" and piece_name != "Roof" \
		and piece_name != "Door" and piece_name != "Window":
		_diag["invalid_reason"] = "INVALID SUPPORT"
		_diag["error_category"] = "SUPPORT_ERROR"
		return {"valid": false}
	if support != null:
		_diag["support_name"] = support.name
	else:
		_diag["support_name"] = "PENDING"

	# Step 3: Structural support (skip for Wall/Roof/Door/Window — they check
	# their own support in their placement sections below)
	if support != null and piece_name != "Wall" and piece_name != "Roof" \
		and piece_name != "Door" and piece_name != "Window":
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
			if _grid_is_blocked(c):
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
			var mesh_off: Vector3 = Vector3.ZERO
			# Recursively find MeshInstance3D (may be under MeshPivot)
			var stack: Array[Node] = ghost.get_children()
			while not stack.is_empty():
				var cn: Node = stack.pop_back()
				if cn is MeshInstance3D:
					mesh_aabb = (cn as MeshInstance3D).get_aabb()
					mesh_off = cn.position
				if cn is CollisionShape3D:
					var dbg_col: CollisionShape3D = cn as CollisionShape3D
					if dbg_col.shape is BoxShape3D:
						var box: BoxShape3D = dbg_col.shape as BoxShape3D
						collision_aabb = AABB(-box.size * 0.5, box.size)
						mesh_off = cn.position
				for cc in cn.get_children():
					stack.append(cc)
			_diag["mesh_offset"] = mesh_off
			_diag["mesh_aabb_min"] = ghost.global_transform * mesh_aabb.position
			_diag["mesh_aabb_max"] = ghost.global_transform * (mesh_aabb.position + mesh_aabb.size)
			_diag["collision_size"] = collision_aabb.size
			_diag["ghost_global_pos"] = ghost.global_position
			_diag["ghost_grid_cell"] = ghost_grid_cell
		if debug_building and debug_key != _last_debug_key:
			print("=== FOUNDATION GRID BUILD ===")
			print("  Support: %s cell %s" % [str(_diag.get("support_name", "?")), str(_diag.get("support_cell", Vector2i.ZERO))])
			print("  Target cell: %s" % str(_diag.get("target_cell", Vector2i.ZERO)))
			print("  Solved pos: %s" % str(_diag.get("solved_pos", Vector3.ZERO)))
			print("  Socket err: %s" % str(_diag.get("socket_position_error", -1.0)))
			print("  Overlap: %s" % str(_diag.get("overlap_valid", true)))
			print("  Footprint: %s cells=%s" % [str(_diag.get("footprint_valid", true)), str(_diag.get("footprint_cells", []))])
			print("  Ghost cell: %s match=%s" % [str(_diag.get("ghost_grid_cell", Vector2i.ZERO)), str(_diag.get("cell_match", false))])
			print("  Height: raft=%.3f found=%.3f err=%.3fm" % [_diag.get("raft_deck_y", 0.0), _diag.get("foundation_top_y", 0.0), _diag.get("height_error", 0.0)])
			print("============================")
		# Footprint sampling for the build overlay (visual only — foundation
		# validity itself is decided by the grid/occupancy checks above).
		_validate_foundation_footprint(found_solved)
		# Return with the connecting socket for _try_build
		var connect_socket: BuildSocket = _find_connecting_socket(support, best_cell)
		return {"valid": true, "socket": connect_socket, "transform": found_solved, "cell": best_cell, "support": support}

	# ============================================================
	# WALL: The ghost follows the crosshair EVERYWHERE.
	#   - Aiming at a Foundation/Raft surface -> edge snapping, wall slides along the edge.
	#   - Aiming at a Wall/Door/Window       -> socket placement (wall-to-wall).
	#   - Aiming at open water / no surface  -> RED ghost at the crosshair (deck height).
	# ============================================================
	# Door and Window are wall-sized pieces with wall sockets — they share the
	# Wall solver so they join walls flush (collision touch = join, overlap =
	# red) instead of embedding into a wall's Socket_Middle.
	if piece_name == "Wall" or piece_name == "Door" or piece_name == "Window":
		# ==== Aim: when the ray misses or hits a non-build object, project the
		# crosshair onto the structural deck plane so the ghost follows the aim
		# point instead of jumping to the raft. ====
		var wall_aim: Vector3 = aim_point
		var wall_aim_normal: Vector3 = aim_normal
		var _hit_is_build_wall: bool = aim_valid and aim_collider != null \
			and _find_support_piece(aim_collider) != null
		if not _hit_is_build_wall:
			var _deck_y_wall: float = _get_structural_deck_y()
			var _ro_wall: Vector3 = camera.global_position
			var _rd_wall: Vector3 = -camera.global_transform.basis.z
			var _bp_t_wall: float = -1.0
			if absf(_rd_wall.y) > 0.001:
				_bp_t_wall = (_deck_y_wall - _ro_wall.y) / _rd_wall.y
			else:
				_bp_t_wall = 10.0
			# Clamp: aiming up at the sky (t < 0) or far off the deck plane should
			# NOT send the ghost to the horizon — keep the aim near the structure
			# so the vertical drop can find the surface under the crosshair.
			if _bp_t_wall <= 0.0 or _bp_t_wall >= AIM_DISTANCE:
				_bp_t_wall = 10.0
			wall_aim = _ro_wall + _rd_wall * _bp_t_wall
			wall_aim_normal = Vector3.UP

		var wall_foundation: Node3D = null
		# P1: raycast hit — what the crosshair actually points at
		if support != null:
			var _sn: String = _find_piece_name(support)
			if _sn == "Foundation" or _sn == "Raft" or _sn == "Wall" \
				or _sn == "Door" or _sn == "Window":
				wall_foundation = support
		# P2a: vertical drop at the (projected) aim — whatever build surface sits
		# directly under the crosshair becomes the support. This covers grazing
		# angles where the main aim ray passes just over the far edge of the deck.
		if wall_foundation == null:
			var _drop_deck_y: float = _get_structural_deck_y()
			var _drop_q := PhysicsRayQueryParameters3D.create(
				Vector3(wall_aim.x, _drop_deck_y + 4.0, wall_aim.z),
				Vector3(wall_aim.x, _drop_deck_y - 4.0, wall_aim.z))
			_drop_q.collision_mask = 1
			var _drop_hit := get_world_3d().direct_space_state.intersect_ray(_drop_q)
			if _drop_hit:
				var _drop_piece: Node3D = _find_support_piece(_drop_hit.get("collider") as Node3D)
				if _drop_piece != null:
					var _dpn: String = _find_piece_name(_drop_piece)
					if _dpn == "Foundation" or _dpn == "Raft" or _dpn == "Wall" \
						or _dpn == "Door" or _dpn == "Window":
						wall_foundation = _drop_piece
		# P2: nearest surface to the (projected) aim — only when the crosshair is
		#     close enough to snap (otherwise the ghost stays at the aim point).
		if wall_foundation == null:
			var _raft: Node3D = _get_raft_node()
			if _raft != null:
				var _best_d: float = Vector2(wall_aim.x - _raft.global_position.x, wall_aim.z - _raft.global_position.z).length()
				wall_foundation = _raft
				var bp: Node3D = _raft.get_node_or_null("BuiltPieces")
				if bp != null:
					for child in bp.get_children():
						if child is Node3D:
							var _cn: String = _find_piece_name(child)
							if _cn == "Foundation" or _cn == "Raft" or _cn == "Wall" \
								or _cn == "Door" or _cn == "Window":
								var _fd: float = Vector2(wall_aim.x - child.global_position.x, wall_aim.z - child.global_position.z).length()
								if _fd < _best_d:
									_best_d = _fd
									wall_foundation = child
				if _best_d > WALL_SURFACE_SNAP_RANGE:
					wall_foundation = null
		# No surface found near the aim: DO NOT reject yet — the wall's actual
		# bottom FOOTPRINT may still rest on a foundation directly under the
		# crosshair (e.g. the aim ray grazing over the deck edge). The shared
		# footprint validation below samples the wall's real bottom; genuinely
		# unsupported spots (open water, floating above) still come out INVALID
		# there with NO SUPPORT SURFACE / INSUFFICIENT SUPPORT.
		# Wall-to-wall: use socket-based placement when support is another wall/door/window
		var _wsn: String = _find_piece_name(wall_foundation)
		if _wsn == "Wall" or _wsn == "Door" or _wsn == "Window":
			# SECOND-FLOOR STACKING: aiming at the upper part of a wall's face
			# (top ~40%) places the new wall directly ON TOP (Socket_Top ->
			# Socket_Base) instead of attaching to its side. The old trigger
			# required aiming within 0.6m of the top edge, which is unreachable
			# from standing eye height — so every stack attempt silently fell
			# back to a SIDE attach that nested the new wall into the old one.
			var _w2w_socket: BuildSocket = null
			if _wsn == "Wall" or _wsn == "Door" or _wsn == "Window":
				var _wall_sockets: Node3D = wall_foundation.get_node_or_null("BuildSockets")
				if _wall_sockets != null:
					var _wall_top: BuildSocket = _wall_sockets.get_node_or_null("Socket_Top") as BuildSocket
					if _wall_top != null and _wall_top.is_compatible(piece_name):
						var _wall_top_y: float = (_get_flat_support_transform(wall_foundation) * _wall_top.position).y
						# Aim must be in the upper part of this wall's face: above the
						# wall's mid-height AND within the stack tolerance of the top.
						# Wall bottom from its own Socket_Base (the top socket's
						# counterpart) — robust for stacked walls on any floor.
						var _wall_base_s: BuildSocket = _wall_sockets.get_node_or_null("Socket_Base") as BuildSocket
						var _wall_base_y: float = _wall_top_y
						if _wall_base_s != null:
							_wall_base_y = (_get_flat_support_transform(wall_foundation) * _wall_base_s.position).y
						var _mid_y: float = (_wall_base_y + _wall_top_y) * 0.5
						if wall_aim.y >= _mid_y and wall_aim.y >= _wall_top_y - 1.0 \
							and not _wall_top.is_occupied:
							_w2w_socket = _wall_top
						elif wall_aim.y >= _mid_y and wall_aim.y >= _wall_top_y - 1.0 \
							and _wall_top.is_occupied:
							# Top already stacked — show RED instead of silently
							# side-attaching into the wall below.
							_diag["invalid_reason"] = "STACK OCCUPIED"
							_diag["error_category"] = "COLLISION_ERROR"
							return {"valid": false, "socket": null, "transform": Transform3D(), "support": wall_foundation}
			if _w2w_socket == null:
				_w2w_socket = _find_best_socket(wall_foundation, piece_name, wall_aim, wall_aim_normal)
			if _w2w_socket != null:
				var _wall_idx: int = BUILD_RECIPE_NAMES.find(piece_name)
				var _w2w_temp: Node3D = build_pieces[_wall_idx].instantiate()
				var new_socket: BuildSocket = _find_reciprocal_socket(_w2w_socket, _w2w_temp, _wsn)
				if new_socket != null:
					solved = _solve_socket_transform(_w2w_socket, new_socket.position, wall_foundation)
					_diag["solved_pos"] = solved.origin
					_diag["wall_foundation"] = wall_foundation.name
					_diag["wall_edge"] = _w2w_socket.name
					var wall_shape: Shape3D = _get_validation_shape(build_pieces[_wall_idx])
					# Also skip the foundation under this wall for overlap check
					var _extra_skip_wf: Array[Node3D] = []
					var _raft_wf: Node3D = _get_raft_node()
					if _raft_wf != null:
						var _bp_wf: Node3D = _raft_wf.get_node_or_null("BuiltPieces")
						if _bp_wf != null:
							var _best_wf_d: float = INF
							for _wf_child in _bp_wf.get_children():
								if _wf_child is Node3D and _find_piece_name(_wf_child) == "Foundation":
									var _wf_dist: float = Vector2(wall_foundation.global_position.x - _wf_child.global_position.x, wall_foundation.global_position.z - _wf_child.global_position.z).length()
									if _wf_dist < _best_wf_d:
										_best_wf_d = _wf_dist
										_extra_skip_wf.append(_wf_child)
					var wall_overlap := _check_overlap(wall_shape, solved, wall_foundation, _extra_skip_wf)
					_w2w_temp.queue_free()
					if wall_overlap.size() > 0:
						_diag["invalid_reason"] = "OVERLAPPING WALL"
						_diag["error_category"] = "COLLISION_ERROR"
						return {"valid": false, "socket": _w2w_socket, "transform": solved, "support": wall_foundation}
					_diag["final"] = "VALID"
					return {"valid": true, "socket": _w2w_socket, "transform": solved, "support": wall_foundation}
				else:
					_w2w_temp.queue_free()
			# Socket-based failed — find nearest Foundation for edge-snapping
			var _wf_fb_target: Node3D = null
			if wall_foundation != null:
				var _raft_wfb: Node3D = _get_raft_node()
				if _raft_wfb != null:
					var _best_wfb_d: float = INF
					var _bp_wfb: Node3D = _raft_wfb.get_node_or_null("BuiltPieces")
					if _bp_wfb != null:
						for _wfb_child in _bp_wfb.get_children():
							if _wfb_child is Node3D and (_find_piece_name(_wfb_child) == "Foundation" or _find_piece_name(_wfb_child) == "Raft"):
								var _wfb_d: float = Vector2(wall_foundation.global_position.x - _wfb_child.global_position.x, wall_foundation.global_position.z - _wfb_child.global_position.z).length()
								if _wfb_d < _best_wfb_d:
									_best_wfb_d = _wfb_d
									_wf_fb_target = _wfb_child
			if _wf_fb_target != null:
				wall_foundation = _wf_fb_target
			# Foundation/Raft: edge-snapping placement
		var _f_sn: String = _find_piece_name(wall_foundation)
		if _f_sn == "Foundation" or _f_sn == "Raft":
			# CENTER placement: aiming in the middle zone of a deck piece places
			# the wall upright in the deck CENTER (Foundation.Socket_Top / raft
			# center) instead of snapping to the nearest edge.
			var _flat_wf: Transform3D = _get_flat_support_transform(wall_foundation)
			var _local_aim_wf: Vector3 = _flat_wf.affine_inverse() * wall_aim
			var _center_zone: float = FOUNDATION_HALF_WIDTH * 0.5
			if absf(_local_aim_wf.x) <= _center_zone and absf(_local_aim_wf.z) <= _center_zone:
				var _deck_c: float = _get_structural_deck_y()
				solved = Transform3D(
					Basis(Vector3.UP, build_rotation),
					Vector3(_flat_wf.origin.x, _deck_c + 1.25, _flat_wf.origin.z))
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = "CENTER"
			else:
				var edge_name: String = _select_wall_edge(wall_foundation, wall_aim)
				solved = _compute_wall_transform(wall_foundation, wall_aim)
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = edge_name
		else:
			# Support is not Foundation/Raft (or none found) — project to deck
			# height at the aim point; the footprint check decides validity.
			var deck_y_f: float = _get_structural_deck_y()
			var _f_pos: Vector3 = Vector3(wall_aim.x, deck_y_f + 1.25, wall_aim.z)
			solved = Transform3D(Basis(Vector3.UP, build_rotation), _f_pos)
			_diag["solved_pos"] = solved.origin
			if wall_foundation != null:
				_diag["wall_foundation"] = wall_foundation.name
			else:
				_diag["wall_foundation"] = "NONE"
		# FOOTPRINT VALIDATION: sample 3x3 grid on wall bottom to check support
		var fp_result := _validate_wall_footprint(solved)
		_diag["footprint_total"] = fp_result["total_count"]
		_diag["footprint_supported"] = fp_result["supported_count"]
		_diag["footprint_ratio"] = fp_result["support_ratio"]
		if not fp_result["valid"]:
			if fp_result["supported_count"] <= 0:
				_diag["invalid_reason"] = "NO SUPPORT SURFACE"
				_diag["error_category"] = "SUPPORT_ERROR"
			else:
				_diag["invalid_reason"] = "INSUFFICIENT SUPPORT: %d/%d (%.0f%%)" % [fp_result["supported_count"], fp_result["total_count"], fp_result["support_ratio"] * 100.0]
				_diag["error_category"] = "FOOTPRINT_ERROR"
			return {"valid": false, "socket": null, "transform": solved, "support": wall_foundation}
		# OVERLAP CHECK: reject if a wall already exists at this position
		var _wall_overlap: bool = false
		var _raft_w: Node3D = _get_raft_node()
		if _raft_w != null:
			var _bp_w: Node3D = _raft_w.get_node_or_null("BuiltPieces")
			if _bp_w != null:
				for _w in _bp_w.get_children():
					if _w is Node3D and is_instance_valid(_w) and _w != wall_foundation:
						var _wn: String = _find_piece_name(_w)
						if _wn == "Wall" or _wn == "Door" or _wn == "Window":
							var _wd: float = Vector3(solved.origin.x - _w.global_position.x, 0.0, solved.origin.z - _w.global_position.z).length()
							if _wd < 0.5:
								_wall_overlap = true
								break
		if _wall_overlap:
			_diag["invalid_reason"] = "OVERLAPPING WALL"
			_diag["error_category"] = "COLLISION_ERROR"
			return {"valid": false, "socket": null, "transform": solved, "support": wall_foundation}
		_diag["final"] = "VALID"
		if wall_foundation != null:
			_diag["support_name"] = wall_foundation.name
		else:
			_diag["support_name"] = "NONE"
		return {"valid": true, "socket": null, "transform": solved, "support": wall_foundation}

	# ============================================================
	# ROOF: TOP_ATTACHMENT — snap to Wall/structural top
	# ============================================================
	if piece_name == "Roof":
		# ROOF AIM FALLBACK: when the aim ray misses (e.g. aiming just over the
		# wall top into the sky, or at a gap), project the crosshair onto the
		# structural deck plane so the wall-top auto-snap below can still find
		# the nearest free Wall top. The roof is a 2x2 slab — the player should
		# never need a pixel-perfect ray hit to place it.
		if not aim_valid or effective_collider == null:
			var _deck_y_r: float = _get_structural_deck_y()
			var _ro_r: Vector3 = camera.global_position
			var _rd_r: Vector3 = -camera.global_transform.basis.z
			var _t_r: float = -1.0
			if absf(_rd_r.y) > 0.001:
				_t_r = (_deck_y_r - _ro_r.y) / _rd_r.y
			else:
				_t_r = 10.0
			if _t_r <= 0.0 or _t_r >= AIM_DISTANCE:
				_t_r = 10.0
			effective_aim_point = _ro_r + _rd_r * _t_r
			effective_aim_normal = Vector3.UP
			effective_collider = null

		# Find the wall or structural support the player is aiming at.
		# The ray hit collider determines the support. Walk up hierarchy.
		var roof_support: Node3D = null
		var roof_target_socket: BuildSocket = null

		# ROOF-TO-ROOF: ray hit an existing Roof — attach the new roof to it
		# (side-by-side expansion via the side sockets, or stacking on top via
		# Socket_Top). This must run FIRST so aiming at a roof never falls
		# through to the "search all walls" fallback and snaps to the wrong
		# wall's top.
		if support != null and _find_piece_name(support) == "Roof":
			# Edge-aware socket choice: the roof is 2x2, so the aim point in the
			# roof's flat space decides the intent. Aim near the CENTER -> stack
			# on top (Socket_Top). Aim near an EDGE -> expand sideways through
			# that edge's side socket. This matches how walls behave (upper face
			# = stack, side = attach) and avoids requiring the player to hit the
			# roof's 0.15m-thin side face.
			var rr_socket: BuildSocket = null
			var rr_flat: Transform3D = _get_flat_support_transform(support)
			var rr_local: Vector3 = rr_flat.affine_inverse() * aim_point
			var rr_sockets_node: Node3D = support.get_node_or_null("BuildSockets")
			var rr_center_zone: float = 0.45  # fraction of half-width
			if rr_sockets_node != null:
				if absf(rr_local.x) <= rr_center_zone and absf(rr_local.z) <= rr_center_zone:
					var rr_top: BuildSocket = rr_sockets_node.get_node_or_null("Socket_Top") as BuildSocket
					if rr_top != null and not rr_top.is_occupied and rr_top.is_compatible("Roof"):
						rr_socket = rr_top
				else:
					var rr_side_name: String = ""
					if absf(rr_local.x) >= absf(rr_local.z):
						rr_side_name = "Socket_East" if rr_local.x >= 0.0 else "Socket_West"
					else:
						rr_side_name = "Socket_North" if rr_local.z >= 0.0 else "Socket_South"
					var rr_side: BuildSocket = rr_sockets_node.get_node_or_null(rr_side_name) as BuildSocket
					if rr_side != null and not rr_side.is_occupied and rr_side.is_compatible("Roof"):
						rr_socket = rr_side
			if rr_socket == null:
				# Aimed roof has no free socket for another roof — show RED
				# instead of silently jumping to a different wall.
				_diag["invalid_reason"] = "ROOF SLOT OCCUPIED"
				_diag["error_category"] = "COLLISION_ERROR"
				return {"valid": false, "socket": null, "transform": Transform3D(), "support": support}
			var rr_idx: int = BUILD_RECIPE_NAMES.find("Roof")
			var rr_temp: Node3D = build_pieces[rr_idx].instantiate()
			var rr_new_socket: BuildSocket = _find_reciprocal_socket(rr_socket, rr_temp, "Roof")
			if rr_new_socket == null:
				rr_temp.queue_free()
				_diag["invalid_reason"] = "MISSING ROOF SOCKET"
				_diag["error_category"] = "TRANSFORM_ERROR"
				return {"valid": false, "socket": rr_socket, "transform": Transform3D(), "support": support}
			solved = _solve_socket_transform(rr_socket, rr_new_socket.position, support)
			_diag["solved_pos"] = solved.origin
			_diag["wall_foundation"] = support.name
			_diag["target_socket_name"] = rr_socket.name
			var rr_shape: Shape3D = _get_validation_shape(build_pieces[rr_idx])
			var rr_overlap := _check_overlap(rr_shape, solved, support)
			rr_temp.queue_free()
			# Allow contact with walls/foundations (build surface), but flag
			# overlap with OTHER roofs or non-build bodies.
			var rr_filtered: Array[Dictionary] = []
			for hit in rr_overlap:
				var hit_body: Node3D = hit.get("collider") as Node3D
				if hit_body == null or not is_instance_valid(hit_body):
					continue
				if _find_piece_name(hit_body) == "Roof":
					rr_filtered.append(hit)
					continue
				var _is_build_rr: bool = false
				var _wn_rr: Node = hit_body
				while _wn_rr != null:
					if _wn_rr.is_in_group("build_surface"):
						_is_build_rr = true
						break
					_wn_rr = _wn_rr.get_parent()
				if not _is_build_rr:
					rr_filtered.append(hit)
			if rr_filtered.size() > 0:
				var hit_obj_rr: Node3D = rr_filtered[0].get("collider") as Node3D
				var rr_obj_name: String = "?"
				if hit_obj_rr != null and is_instance_valid(hit_obj_rr):
					rr_obj_name = hit_obj_rr.name
				_diag["invalid_reason"] = "OVERLAP: " + rr_obj_name
				_diag["error_category"] = "COLLISION_ERROR"
				_validate_roof_footprint(solved)
				return {"valid": false, "socket": rr_socket, "transform": solved, "support": support}
			_validate_roof_footprint(solved)
			_diag["final"] = "VALID"
			return {"valid": true, "socket": rr_socket, "transform": solved, "support": support}

		# Method 1: Ray hit a Wall directly — use ITS Socket_Top. If the top is
		# already occupied (e.g. a 2nd-floor wall), still target this wall so the
		# placement goes RED instead of silently snapping the roof to a DIFFERENT
		# wall the player wasn't aiming at.
		if support != null and _find_piece_name(support) == "Wall":
			var sockets_node := support.get_node_or_null("BuildSockets")
			if sockets_node != null:
				for s in sockets_node.get_children():
					if s is BuildSocket and s.name == "Socket_Top" and s.is_compatible("Roof"):
						roof_target_socket = s
						roof_support = support
						break

		# Method 2: Ray hit something on top of a wall (e.g. another roof)
		# Walk up to find a Wall ancestor with Socket_Top
		if roof_support == null and support != null:
			var walk: Node3D = support
			for _i in range(5):
				if walk == null:
					break
				if _find_piece_name(walk) == "Wall":
					var sn := walk.get_node_or_null("BuildSockets")
					if sn != null:
						for s in sn.get_children():
							if s is BuildSocket and s.name == "Socket_Top" \
								and not s.is_occupied and s.is_compatible("Roof"):
								roof_target_socket = s
								roof_support = walk
								break
				if roof_support != null:
					break
				walk = walk.get_parent() as Node3D

		# Method 3: Ray didn't hit a Wall directly — search ALL built
		# pieces, but FIRST honor the wall the crosshair is actually over
		# (its horizontal footprint contains the aim point). Roofs must go on
		# the wall the player is aiming at — never silently jump to another.
		# Walls are NOT in _grid_occupancy (only Foundations are), so
		# we must search the BuiltPieces container where they live.
		if roof_support == null:
			var raft_node: Node3D = _get_raft_node()
			if raft_node != null:
				var bp: Node3D = raft_node.get_node_or_null("BuiltPieces")
				if bp != null:
					var aim_over_wall: Node3D = null
					var aim_over_socket: BuildSocket = null
					for child in bp.get_children():
						if not (child is Node3D):
							continue
						if _find_piece_name(child) != "Wall":
							continue
						var sn: Node3D = child.get_node_or_null("BuildSockets")
						if sn == null:
							continue
						var wall_flat: Transform3D = _get_flat_support_transform(child)
						var wall_local_aim: Vector3 = wall_flat.affine_inverse() * effective_aim_point
						# Aim inside the wall's 2.0 x 0.2 footprint -> this is the aimed wall
						if absf(wall_local_aim.x) <= 1.0 and absf(wall_local_aim.z) <= 0.15:
							for s in sn.get_children():
								if s is BuildSocket and s.name == "Socket_Top" and s.is_compatible("Roof"):
									aim_over_socket = s
									aim_over_wall = child
									break
						if aim_over_wall != null:
							break
					if aim_over_wall != null:
						roof_target_socket = aim_over_socket
						roof_support = aim_over_wall
					else:
						var best_horiz_d: float = 4.0  # generous horizontal search
						for child in bp.get_children():
							if not (child is Node3D):
								continue
							if _find_piece_name(child) != "Wall":
								continue
							var sn: Node3D = child.get_node_or_null("BuildSockets")
							if sn == null:
								continue
							for s in sn.get_children():
								if s is BuildSocket and s.name == "Socket_Top" \
									and not s.is_occupied and s.is_compatible("Roof"):
									var flat_sp: Vector3 = _get_flat_support_transform(child) * s.position
									# Use horizontal distance (ignore Y) since the aim
									# point may be on the Foundation surface far below
									# the Wall top.
									var dx: float = effective_aim_point.x - flat_sp.x
									var dz: float = effective_aim_point.z - flat_sp.z
									var horiz_d: float = sqrt(dx * dx + dz * dz)
									if horiz_d < best_horiz_d:
										best_horiz_d = horiz_d
										roof_target_socket = s
										roof_support = child

		if roof_support == null or roof_target_socket == null:
			_diag["invalid_reason"] = "NO VALID ROOF TARGET"
			_diag["error_category"] = "SUPPORT_ERROR"
			return {"valid": false}
		# A roof needs the TOP of the piece it lands on. If the targeted top is
		# taken by a stacked wall OR a roof, CLIMB to the topmost piece in that
		# column and target ITS top (the roof belongs on the highest surface the
		# player can see — roofs stack on roofs, walls stack on walls).
		var roof_climb: int = 0
		while roof_target_socket.is_occupied and roof_climb < 8:
			var above: Node3D = roof_target_socket.occupying_piece as Node3D
			roof_climb += 1
			if above == null or not is_instance_valid(above):
				break
			var above_pn: String = _find_piece_name(above)
			if above_pn != "Wall" and above_pn != "Roof":
				break
			var sn_above: Node3D = above.get_node_or_null("BuildSockets")
			if sn_above == null:
				break
			var top_above: BuildSocket = sn_above.get_node_or_null("Socket_Top") as BuildSocket
			if top_above == null or not top_above.is_compatible("Roof"):
				break
			roof_target_socket = top_above
			roof_support = above

		# Update roof hysteresis
		_roof_last_support = roof_support
		_diag["wall_foundation"] = roof_support.name
		_diag["target_socket_name"] = roof_target_socket.name
		_diag["target_socket_pos"] = roof_target_socket.global_position

		# Find the reciprocal socket on the Roof: Socket_Base
		if new_piece_idx == -1:
			_diag["invalid_reason"] = "INVALID BUILD SCENE"
			return {"valid": false}
		var roof_scene: PackedScene = build_pieces[new_piece_idx]
		var roof_temp: Node3D = roof_scene.instantiate()
		var roof_base_socket: BuildSocket = null
		for s in _get_all_sockets(roof_temp):
			if s.name == "Socket_Base" and s.is_compatible(_find_piece_name(roof_support)):
				roof_base_socket = s
				break
		if roof_base_socket == null:
			# Fallback: any compatible socket
			for s in _get_all_sockets(roof_temp):
				if s.is_compatible(_find_piece_name(roof_support)):
					roof_base_socket = s
					break
		if roof_base_socket == null:
			_diag["invalid_reason"] = "MISSING ROOF SOCKET"
			roof_temp.queue_free()
			return {"valid": false}

		_diag["new_socket_name"] = roof_base_socket.name

		# Solve: RoofRoot * RoofSocketLocal = TargetSocket
		# RoofRoot = TargetSocket * inverse(RoofSocketLocal)
		solved = _solve_socket_transform(roof_target_socket, roof_base_socket.position, roof_support)
		_diag["solved_pos"] = solved.origin

		# Apply to ghost and verify socket alignment
		if ghost != null:
			ghost.global_transform = solved
			ghost.visible = true

		var roof_flat_target: Vector3 = _get_flat_support_transform(roof_support) * roof_target_socket.position
		# Verify socket alignment from the SOLVED transform — the live ghost's
		# sockets read stale for AnimatableBody3D in the frame the transform is
		# set (Jolt sync), which produced false SOCKET MISMATCH errors.
		var actual_pos: Vector3 = solved * roof_base_socket.position
		var socket_err: float = actual_pos.distance_to(roof_flat_target)
		_diag["actual_socket_pos"] = actual_pos
		_diag["socket_position_error"] = socket_err
		_diag["socket_position_valid"] = socket_err <= 0.1
		if socket_err > 0.1:
			_diag["invalid_reason"] = "SOCKET MISMATCH: " + str(snappedf(socket_err, 0.001)) + "m"
			_diag["error_category"] = "TRANSFORM_ERROR"
			# Footprint sampling for the build overlay (samples the intended spot)
			_validate_roof_footprint(solved)
			roof_temp.queue_free()
			return {"valid": false}

		# Overlap check — exclude the support wall and foundations
		var roof_overlap := _check_overlap(shape, solved, roof_support)
		var roof_filtered: Array[Dictionary] = []
		for hit in roof_overlap:
			var hit_body: Node3D = hit.get("collider") as Node3D
			if hit_body == null or not is_instance_valid(hit_body):
				continue
			# Exclude ANY build-system body via group check
			var _is_build_roof: bool = false
			var _wn_r: Node = hit_body
			while _wn_r != null:
				if _wn_r.is_in_group("build_surface"):
					_is_build_roof = true
					break
				_wn_r = _wn_r.get_parent()
			if _is_build_roof:
				continue
			roof_filtered.append(hit)
		_diag["overlap_valid"] = roof_filtered.size() == 0
		if roof_filtered.size() > 0:
			var hit_obj: PhysicsBody3D = roof_filtered[0].get("collider") as PhysicsBody3D
			if hit_obj != null and is_instance_valid(hit_obj):
				_diag["overlap_object"] = hit_obj.name
			else:
				_diag["overlap_object"] = "?"
			_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
			_diag["error_category"] = "COLLISION_ERROR"
			_validate_roof_footprint(solved)
			roof_temp.queue_free()
			return {"valid": false}

		roof_temp.queue_free()
		# Footprint sampling for the build overlay (visual only — the roof's
		# validity is determined by the socket/overlap checks above).
		_validate_roof_footprint(solved)
		_diag["final"] = "VALID"
		return {"valid": true, "socket": roof_target_socket, "transform": solved, "support": roof_support}

	# ============================================================
	# OTHER NON-FOUNDATION: Socket-based placement (Window, Door, etc.)
	# ============================================================
	# Step 4: Find target socket on the support
	var socket: BuildSocket = null
	# STAIRS STACKING: stairs attach to the TOP of the stair below, so a
	# staircase can climb up to a second floor (or higher).
	if piece_name == "Stairs" and support != null and _find_piece_name(support) == "Stairs":
		var _s_sk: Node3D = support.get_node_or_null("BuildSockets")
		if _s_sk != null:
			var _s_top: BuildSocket = _s_sk.get_node_or_null("Socket_Top") as BuildSocket
			if _s_top != null and not _s_top.is_occupied and _s_top.is_compatible("Stairs"):
				socket = _s_top
	if socket == null:
		socket = _find_best_socket(support, piece_name, effective_aim_point, effective_aim_normal)
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
				# Compute from the solved transform instead of reading the live ghost:
				# a freshly-spawned AnimatableBody3D ghost doesn't reflect its new
				# transform in global reads until the physics sync, which would
				# falsely fail the alignment check on the first preview frame.
				var actual_pos: Vector3 = (solved * gs.transform).origin
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
	overlap_hits = _check_overlap(shape, solved, support)
	# Filter out build-system bodies (same as Wall/Roof overlap checks)
	var generic_filtered: Array[Dictionary] = []
	for hit in overlap_hits:
		var hit_body: Node3D = hit.get("collider") as Node3D
		if hit_body == null or not is_instance_valid(hit_body):
			continue
		var _is_gen_build: bool = false
		var _wn_g: Node = hit_body
		while _wn_g != null:
			if _wn_g.is_in_group("build_surface"):
				_is_gen_build = true
				break
			_wn_g = _wn_g.get_parent()
		if _is_gen_build:
			continue
		if hit_body.global_position.y < solved.origin.y - 1.0:
			continue
		generic_filtered.append(hit)
	_diag["overlap_valid"] = generic_filtered.size() == 0
	_diag["overlap_count"] = generic_filtered.size()
	if generic_filtered.size() > 0:
		var hit_obj: PhysicsBody3D = generic_filtered[0].get("collider") as PhysicsBody3D
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
				var dbg_col2: CollisionShape3D = c as CollisionShape3D
				if dbg_col2.shape is BoxShape3D:
					var box: BoxShape3D = dbg_col2.shape as BoxShape3D
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
	var is_valid: bool = bool(resolved.get("valid", false))
	# Apply material FIRST — before ghost becomes visible — so it never
	# flashes with the wrong color.
	_apply_ghost_material(is_valid)
	if is_valid:
		var xform: Transform3D = resolved["transform"]
		_ghost_target_socket = resolved["socket"]
		_ghost_cell = resolved.get("cell", Vector2i(999999, 999999))
		_ghost_support = resolved.get("support", null)
		# Only update ghost transform if it actually changed (prevents jitter)
		var pos_delta: float = (xform.origin - _ghost_transform.origin).length()
		var rot_delta: float = xform.basis.get_euler().distance_to(_ghost_transform.basis.get_euler())
		if pos_delta > 0.001 or rot_delta > 0.001 or not build_valid:
			ghost.global_transform = xform
			_ghost_transform = xform
		ghost.visible = true
		build_valid = true
	else:
		# Still show ghost at aim position in RED so player sees where they're aiming
		_ghost_target_socket = null
		_ghost_cell = Vector2i(999999, 999999)
		_ghost_support = null
		build_valid = false
		# Use the transform from resolved result if available
		var fallback_xform: Transform3D = ghost.global_transform
		if resolved.has("transform"):
			fallback_xform = resolved["transform"]
		elif piece_name == "Foundation":
			var raft_fb: Node3D = _get_raft_node()
			if raft_fb != null:
				var aim_cell_fb: Vector2i = _world_to_grid(aim_point)
				fallback_xform = _compute_foundation_transform(aim_cell_fb)
		elif piece_name == "Wall" or piece_name == "Door" or piece_name == "Window":
			# Find nearest Foundation/Raft/Wall and snap wall to its edge
			var _wf_fb: Node3D = null
			var _raft_fb: Node3D = _get_raft_node()
			if _raft_fb != null:
				var _best_fb_d: float = Vector2(aim_point.x - _raft_fb.global_position.x, aim_point.z - _raft_fb.global_position.z).length()
				_wf_fb = _raft_fb
				var bp_fb: Node3D = _raft_fb.get_node_or_null("BuiltPieces")
				if bp_fb != null:
					for child in bp_fb.get_children():
						if child is Node3D:
							var _cn_fb: String = _find_piece_name(child)
							if _cn_fb == "Foundation" or _cn_fb == "Wall" \
								or _cn_fb == "Door" or _cn_fb == "Window":
								var _fd_fb: float = Vector2(aim_point.x - child.global_position.x, aim_point.z - child.global_position.z).length()
								if _fd_fb < _best_fb_d:
									_best_fb_d = _fd_fb
									_wf_fb = child
			if _wf_fb != null:
				var _wf_sn: String = _find_piece_name(_wf_fb)
				if _wf_sn == "Foundation" or _wf_sn == "Raft":
					fallback_xform = _compute_wall_transform(_wf_fb, aim_point)
				else:
					# Wall/Door/Window support — snap to nearest edge at deck height
					var deck_y_wfb: float = _get_structural_deck_y()
					var _wfb_pos: Vector3 = Vector3(aim_point.x, deck_y_wfb + 1.25, aim_point.z)
					fallback_xform = Transform3D(Basis(Vector3.UP, build_rotation), _wfb_pos)
		elif piece_name == "Roof":
			# Show roof ghost near the closest Wall top even when invalid
			# Search BuiltPieces (Walls are NOT in _grid_occupancy)
			var roof_fb_wall: Node3D = null
			var roof_fb_dist: float = 4.0  # horizontal search radius
			var raft_fb: Node3D = _get_raft_node()
			if raft_fb != null:
				var bp_fb: Node3D = raft_fb.get_node_or_null("BuiltPieces")
				if bp_fb != null:
					for child in bp_fb.get_children():
						if not (child is Node3D):
							continue
						if _find_piece_name(child) != "Wall":
							continue
						var sn := child.get_node_or_null("BuildSockets")
						if sn == null:
							continue
						for s in sn.get_children():
							if s is BuildSocket and s.name == "Socket_Top" \
								and not s.is_occupied and s.is_compatible("Roof"):
								var flat_sp: Vector3 = _get_flat_support_transform(child) * s.position
								var dx: float = aim_point.x - flat_sp.x
								var dz: float = aim_point.z - flat_sp.z
								var horiz_d: float = sqrt(dx * dx + dz * dz)
								if horiz_d < roof_fb_dist:
									roof_fb_dist = horiz_d
									roof_fb_wall = child
			if roof_fb_wall != null:
				# Compute roof transform at the nearest wall top
				var fb_sn := roof_fb_wall.get_node_or_null("BuildSockets")
				if fb_sn != null:
					for s in fb_sn.get_children():
						if s is BuildSocket and s.name == "Socket_Top" \
							and not s.is_occupied and s.is_compatible("Roof"):
							var roof_scene_fb: PackedScene = build_pieces[selected_piece_index]
							var roof_temp_fb: Node3D = roof_scene_fb.instantiate()
							var roof_base_fb: BuildSocket = null
							for rs in _get_all_sockets(roof_temp_fb):
								if rs.name == "Socket_Base":
									roof_base_fb = rs
									break
							if roof_base_fb != null:
								fallback_xform = _solve_socket_transform(s, roof_base_fb.position, roof_fb_wall)
							roof_temp_fb.queue_free()
							break
		ghost.global_transform = fallback_xform
		ghost.visible = true
	# Material already applied at the top of this function
	if debug_building:
		_update_debug_markers()
	if build_overlay:
		_update_overlay_markers()

func _ensure_ghost_materials() -> void:
	if _ghost_valid_mat == null:
		_ghost_valid_mat = StandardMaterial3D.new()
		_ghost_valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_valid_mat.albedo_color = Color(0.1, 1.0, 0.1, 0.85)
		_ghost_valid_mat.no_depth_test = true
		_ghost_valid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _ghost_invalid_mat == null:
		_ghost_invalid_mat = StandardMaterial3D.new()
		_ghost_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_invalid_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.85)
		_ghost_invalid_mat.no_depth_test = true
		_ghost_invalid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

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
# BUILD OVERLAY — footprint samples + support ratio (F3)
# ============================================================
var _overlay_markers_root: Node3D = null
var _overlay_cells: Array[MeshInstance3D] = []
var _overlay_labels: Array[Label3D] = []
var _overlay_mat_green: StandardMaterial3D = null
var _overlay_mat_orange: StandardMaterial3D = null
var _overlay_mat_red: StandardMaterial3D = null

func _ensure_overlay_markers(count: int) -> void:
	if _overlay_markers_root == null or not is_instance_valid(_overlay_markers_root):
		_overlay_markers_root = Node3D.new()
		_overlay_markers_root.name = "BuildOverlayMarkers"
		get_tree().current_scene.add_child(_overlay_markers_root)
		_overlay_cells.clear()
		_overlay_labels.clear()
	if _overlay_mat_green == null:
		_overlay_mat_green = StandardMaterial3D.new()
		_overlay_mat_green.albedo_color = Color(0.1, 1.0, 0.1, 0.65)
		_overlay_mat_green.no_depth_test = true
		_overlay_mat_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _overlay_mat_orange == null:
		_overlay_mat_orange = StandardMaterial3D.new()
		_overlay_mat_orange.albedo_color = Color(1.0, 0.65, 0.1, 0.65)
		_overlay_mat_orange.no_depth_test = true
		_overlay_mat_orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _overlay_mat_red == null:
		_overlay_mat_red = StandardMaterial3D.new()
		_overlay_mat_red.albedo_color = Color(1.0, 0.1, 0.1, 0.65)
		_overlay_mat_red.no_depth_test = true
		_overlay_mat_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	while _overlay_cells.size() < count:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.04, 1.0)
		m.mesh = box
		# Cell box sits ON the sample point (bottom face at the sample height)
		m.position = Vector3(0, 0.02, 0)
		_overlay_markers_root.add_child(m)
		_overlay_cells.append(m)
		var lab := Label3D.new()
		lab.font_size = 48
		lab.outline_size = 10
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.pixel_size = 0.004
		lab.position = Vector3(0, 0.18, 0)
		lab.modulate = Color(1, 1, 1)
		_overlay_markers_root.add_child(lab)
		_overlay_labels.append(lab)

func _clear_overlay_markers() -> void:
	if _overlay_markers_root != null and is_instance_valid(_overlay_markers_root):
		_overlay_markers_root.queue_free()
	_overlay_markers_root = null
	_overlay_cells.clear()
	_overlay_labels.clear()

# Support percentage for one sample point: measure the gap between the sample
# height and the build surface directly below it (0% when nothing is found).
func _overlay_sample_percent(pos: Vector3, fallback: float) -> float:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = pos + Vector3.UP * 1.0
	var ray_end: Vector3 = pos + Vector3.DOWN * 3.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.exclude = _support_ray_excludes()
	var hit := space_state.intersect_ray(query)
	if hit:
		var hb: Node3D = hit.collider as Node3D
		if _is_build_surface(hb):
			var gap: float = pos.y - hit.position.y
			# Sample sits right on the surface -> 100%; gap up to 0.3m scales down.
			var pct: float = clampf(1.0 - (gap - 0.02) / 0.3, 0.0, 1.0)
			if pct >= 0.99:
				return 100.0
			return pct * 100.0
	return 0.0 if fallback < 0.5 else 100.0

# Per-cell support percentage for every recorded sample position. Used by both
# the overlay grid labels and the HUD ratio so they always agree.
func _overlay_sample_percents(positions: Array, supported: Array) -> Array:
	var out: Array = []
	for i in positions.size():
		var is_sup: bool = bool(supported[i]) if i < supported.size() else false
		out.append(_overlay_sample_percent(positions[i], 100.0 if is_sup else 0.0))
	return out

func _update_overlay_markers() -> void:
	if _overlay_markers_root != null and is_instance_valid(_overlay_markers_root):
		for m in _overlay_cells:
			m.visible = false
		for l in _overlay_labels:
			l.visible = false
	if not build_mode or not build_overlay:
		return
	var positions: Array = _diag.get("sample_positions", [])
	var supported: Array = _diag.get("sample_supported", [])
	if positions.is_empty():
		return
	# INVALID resolves leave the ghost at its fallback spot (e.g. deck height)
	# while the recorded samples came from a different solve — recenter the
	# grid on the ghost's VISIBLE position so the overlay always shows where
	# the player actually sees the preview. Valid resolves already sample the
	# correct solve position, so no offset (the ghost may report a stale
	# transform for AnimatableBody3D in the same frame).
	var offset: Vector3 = Vector3.ZERO
	if not build_valid and ghost != null and is_instance_valid(ghost) and positions.size() > 0:
		var sample_origin: Vector3 = positions[0]
		var first_in_ghost_local: Vector3 = ghost.global_transform.affine_inverse() * sample_origin
		if first_in_ghost_local.length() < 3.0:
			offset = ghost.global_position - sample_origin
	var _overlay_percents: Array = _overlay_sample_percents(positions, supported)
	_ensure_overlay_markers(positions.size())
	var cell_size: float = float(_diag.get("footprint_cell_size", FOUNDATION_WIDTH * 0.5))
	for i in positions.size():
		var m: MeshInstance3D = _overlay_cells[i]
		var lab: Label3D = _overlay_labels[i]
		m.global_position = positions[i] + offset
		# Reorient the cell box so it lies flat on the surface (axis-aligned
		# on X/Z, no pitch/roll — grid stays level even over waves)
		m.global_basis = Basis(Vector3.UP, 0.0)
		(m.mesh as BoxMesh).size = Vector3(cell_size, 0.04, cell_size)
		var percents: Array = _overlay_percents
		var pct: float = 0.0
		if i < percents.size():
			pct = percents[i]
		# Cell COLOR follows the placement verdict (green = will build, red =
		# won't), so the overlay never contradicts the build system. The % label
		# still shows the actual surface coverage under that cell.
		if build_valid:
			m.set_surface_override_material(0, _overlay_mat_green)
		else:
			m.set_surface_override_material(0, _overlay_mat_red)
		m.visible = true
		lab.global_position = positions[i] + Vector3.UP * 0.22
		lab.text = "%d%%" % int(roundf(pct))
		lab.visible = true

func _overlay_hud_text() -> String:
	if not build_mode or not build_overlay:
		return ""
	var d: String = ""
	var positions: Array = _diag.get("sample_positions", [])
	var supported: Array = _diag.get("sample_supported", [])
	var tot: int = positions.size()
	var force_red: bool = not build_valid and str(_diag.get("invalid_reason", "")) not in ["", "NO SUPPORT SURFACE", "INSUFFICIENT SUPPORT"]
	d += "\n--- BUILD OVERLAY ---"
	if tot > 0:
		if force_red:
			var sup: int = int(_diag.get("footprint_supported", 0))
			d += "\nSamples: %d/%d supported (%.0f%%)  [placement %s]" % [sup, tot, float(_diag.get("footprint_ratio", 0.0)) * 100.0, str(_diag.get("invalid_reason", "?"))]
		else:
			var percents: Array = _overlay_sample_percents(positions, supported)
			var sum: float = 0.0
			for p in percents:
				sum += p
			var avg: float = sum / percents.size() if percents.size() > 0 else 0.0
			d += "\nCoverage: %.0f%%  (%d cells, 100%% = fully on surface)" % [avg, tot]
	else:
		d += "\nNo footprint samples for this piece"
	if _diag.has("center_supported"):
		d += "\nCenter ray: " + _yn(_diag.get("center_supported", false))
	if _diag.has("bottom_height") and _diag.has("foundation_height"):
		d += "\nBottom: %.3f  Surface: %.3f" % [_diag.get("bottom_height", 0.0), _diag.get("foundation_height", 0.0)]
	if _diag.has("wall_edge") and str(_diag.get("wall_edge", "")) != "":
		d += "\nEdge/Socket: " + str(_diag.get("wall_edge", "?"))
	if _diag.has("wall_foundation"):
		d += "\nSurface piece: " + str(_diag.get("wall_foundation", "?"))
	return d

# ============================================================
# BUILD SYSTEM — TRY BUILD (CONFIRM)
# ============================================================
func _try_build() -> void:
	if not build_valid:
		return
	var piece_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
	# Walls use direct transform, no socket required
	# Walls, Doors and Windows use the direct ghost transform (no socket
	# required) — they are wall-sized pieces placed by the shared Wall solver.
	if piece_name != "Wall" and piece_name != "Door" and piece_name != "Window" \
		and _ghost_target_socket == null:
		return
	if not Inventory.can_afford(piece_name):
		return
	if not Inventory.craft(piece_name):
		return
	var scene: PackedScene = build_pieces[selected_piece_index]
	var piece: Node3D = scene.instantiate()
	# Give every placed piece a unique name — Godot auto-renames duplicate
	# children to "@AnimatableBody3D@n" (class name based), which breaks the
	# name-based piece detection (_find_piece_name etc.) for every piece after
	# the first of its type.
	piece.name = "%s_%d" % [piece_name, piece.get_instance_id()]
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
	# Disable ALL collision shapes BEFORE adding to tree to prevent pushing the
	# player (some pieces have several, e.g. stairs steps)
	var piece_cols: Array[Node] = piece.find_children("*", "CollisionShape3D", true, false)
	for _pc in piece_cols:
		(_pc as CollisionShape3D).disabled = true
	# Set the piece's transform BEFORE add_child so the physics body enters the
	# space already placed. Setting global_transform right after add would be
	# overwritten by the physics sync for script-animated bodies (e.g. the
	# Door's _physics_process), snapping the piece back to the raft origin.
	# Use the EXACT candidate cell from preview — never recompute from
	# world position, which can drift between preview and E press frames.
	var cell: Vector2i = _ghost_cell
	if cell == Vector2i(999999, 999999):
		# Fallback: recompute from ghost world transform
		var flat_xf: Transform3D = _get_flat_support_transform(raft)
		var inv_xf: Transform3D = flat_xf.affine_inverse()
		var local_pos: Vector3 = inv_xf * _ghost_transform.origin
		cell = Vector2i(int(roundf(local_pos.x / FOUNDATION_WIDTH)), int(roundf(local_pos.z / FOUNDATION_DEPTH)))
	# Place piece — use ghost transform for non-foundations (walls etc.)
	if piece_name == "Foundation":
		# Grid-based: exact formula from cell coordinates
		var raft_local_pos: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
		var raft_local_basis: Basis = Basis(Vector3.UP, build_rotation)
		piece.transform = Transform3D(raft_local_basis, raft_local_pos)
	else:
		# Wall/other: use the ghost's preview transform, converted to raft-local
		piece.transform = raft.global_transform.affine_inverse() * _ghost_transform
	container.add_child(piece)
	# Re-enable collision after physics frame settles (prevents pushing player)
	for _pc in piece_cols:
		(_pc as CollisionShape3D).set_deferred("disabled", false)
	piece.add_to_group("build_surface")
	# Link sockets if available (walls use direct transform, no socket)
	if _ghost_target_socket != null:
		_ghost_target_socket.occupy(piece)
		_link_reciprocal_socket(piece, _ghost_target_socket)
	# Register in grid (only foundations — walls/other are edge attachments)
	if piece_name == "Foundation":
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
		print("  Preview socket: %s" % str(_ghost_target_socket.name) if _ghost_target_socket != null else "NULL")
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
		best.occupy(parent_piece_of_socket if parent_piece_of_socket != null else new_piece)# ============================================================
# BUILD SYSTEM — EDIT SYSTEM
# ============================================================
const RECIPE_REFUND := {
	"Foundation": {"Wood": 5},
	"Wall": {"Wood": 8, "Rope": 1},
	"Roof": {"Wood": 8, "Rope": 1},
	"Stairs": {"Wood": 6, "Rope": 1},
	"Door": {"Wood": 4, "Rope": 1},
	"Window": {"Wood": 3, "Plastic": 1},
}



# Walk up the node hierarchy to find a node with BuildSockets (a building piece).
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

# Handle double-click detection for edit mode pickup.
func _handle_double_click_edit() -> void:
	if not aim_valid or aim_collider == null:
		return
	var target := _find_editable_target(aim_collider)
	var now := Time.get_ticks_msec() / 1000.0
	if target != null and _last_clicked_piece == target and (now - _last_click_time) <= DOUBLE_CLICK_TIME:
		# Same piece clicked twice within time — PICK UP
		_start_edit(target)
		_last_clicked_piece = null
		_last_click_time = 0.0
	else:
		# First click or different piece — store and wait
		_last_clicked_piece = target
		_last_click_time = now

# Start editing a building piece.
func _start_edit(target: Node3D) -> void:
	_editing = target
	_edit_original_transform = target.global_transform
	_edit_original_cell = _world_to_grid(target.global_position)
	_edit_valid = false
	_edit_candidate_transform = target.global_transform
	_edit_candidate_cell = _edit_original_cell
	# Disable collision so the piece doesn't block itself
	var col := target.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true
	# Unregister from grid — its cell is now free for candidate evaluation
	_grid_unregister(_edit_original_cell)
	# Free sockets this piece occupies
	for s in _get_all_sockets(target):
		if s.is_occupied:
			s.free_socket()
	# Free support sockets that reference this piece (siblings in BuiltPieces)
	var raft: Node3D = _get_raft_node()
	if raft != null:
		var bp: Node3D = raft.get_node_or_null("BuiltPieces")
		if bp != null:
			for sibling in bp.get_children():
				if sibling == target or not (sibling is Node3D):
					continue
				if sibling.get_node_or_null("BuildSockets") == null:
					continue
				for s in _get_all_sockets(sibling):
					if s.is_occupied and s.occupying_piece == target:
						s.free_socket()
	# Apply transparent preview material
	_set_edit_color(_ghost_valid_mat)
	if ghost:
		ghost.visible = false

# Called every frame while editing — update the preview position.
func _update_edit_follow() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	_ensure_ghost_materials()
	var piece_name := _piece_name_from_node(_editing)
	var raft: Node3D = _get_raft_node()
	if raft == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	# Compute aim point on the structural deck plane
	var deck_y: float = _get_structural_deck_y()
	var ray_o: Vector3 = camera.global_position
	var ray_d: Vector3 = -camera.global_transform.basis.z
	var edit_aim: Vector3 = Vector3.ZERO
	var got_aim: bool = false
	if absf(ray_d.y) > 0.001:
		var t: float = (deck_y - ray_o.y) / ray_d.y
		if t > 0.0 and t < AIM_DISTANCE:
			edit_aim = ray_o + ray_d * t
			got_aim = true
	if not got_aim:
		# Fallback: use current piece position as aim
		edit_aim = _editing.global_position
	# Shared variables for both branches
	var new_xform: Transform3D = Transform3D()
	var col: CollisionShape3D = null
	# --- Foundation: grid-based placement with neighbor search ---
	if piece_name == "Foundation":
		var aim_cell: Vector2i = _world_to_grid(edit_aim)
		# Try aim cell first, then neighbors — find best empty supported cell
		var best_cell: Vector2i = Vector2i(999999, 999999)
		var best_score: float = -1.0e10
		var cells_to_try: Array[Vector2i] = [aim_cell]
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			cells_to_try.append(aim_cell + offset)
		for offset in [Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
			cells_to_try.append(aim_cell + offset)
		for c in cells_to_try:
			if _grid_is_occupied(c):
				continue
			var wp: Vector3 = _grid_to_world(c)
			var dist: float = edit_aim.distance_to(wp)
			if dist > 6.0:
				continue
			var score: float = -dist
			if c == aim_cell:
				score += 100.0
			var nc: int = _count_supporting_neighbors(c)
			score += float(nc) * 2.0
			if score > best_score:
				best_score = score
				best_cell = c
		if best_cell.x == 999999:
			# No valid cell found — stay at current position, show invalid
			_edit_valid = false
			_set_edit_color(_ghost_invalid_mat)
			return
		new_xform = _compute_foundation_transform(best_cell)
		# Overlap check — exclude editing piece itself
		col = _editing.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col != null and col.shape != null:
			var hits := _check_overlap(col.shape, new_xform, _editing)
			if hits.size() > 0:
				_edit_valid = false
				_set_edit_color(_ghost_invalid_mat)
				return
		_editing.global_transform = new_xform
		_edit_candidate_transform = new_xform
		_edit_candidate_cell = best_cell
		_edit_valid = true
		_set_edit_color(_ghost_valid_mat)
		return
	# --- Non-foundation: socket-based placement ---
	var support: Node3D = null
	if aim_valid and aim_collider != null:
		support = _find_support_piece(aim_collider)
	if support == null:
		support = raft
	if support == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var socket: BuildSocket = _find_best_socket(support, piece_name, edit_aim, Vector3.UP)
	if socket == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var reciprocal: BuildSocket = null
	var best_dist: float = 999.0
	for s in _get_all_sockets(_editing):
		if not s.is_compatible(_find_piece_name(support)):
			continue
		var d: float = (s.global_position - socket.global_position).length()
		if d < best_dist:
			best_dist = d
			reciprocal = s
			if best_dist < 0.01:
				break
	if reciprocal == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var target_pos: Vector3 = flat_xform * socket.position
	var offset: Vector3 = reciprocal.position.rotated(Vector3.UP, build_rotation)
	var new_pos: Vector3 = target_pos - flat_xform.basis * offset
	var new_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	new_xform = Transform3D(new_basis, new_pos)
	# Overlap check — exclude editing piece
	col = _editing.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape != null:
		var hits := _check_overlap(col.shape, new_xform, _editing)
		if hits.size() > 0:
			_edit_valid = false
			_set_edit_color(_ghost_invalid_mat)
			return
	_editing.global_transform = new_xform
	_edit_candidate_transform = new_xform
	_edit_valid = true
	_set_edit_color(_ghost_valid_mat)

# Confirm edit: place the building at the preview position.
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
	# Register at new grid cell
	var new_cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_register(new_cell, _editing)
	# Re-link sockets for non-foundation pieces
	var piece_name := _piece_name_from_node(_editing)
	if piece_name != "Foundation":
		var support: Node3D = null
		if aim_valid and aim_collider != null:
			support = _find_support_piece(aim_collider)
		if support == null:
			support = _get_raft_node()
		if support != null:
			var socket: BuildSocket = _find_best_socket(support, piece_name, aim_point, aim_normal)
			if socket != null:
				socket.occupy(_editing)
				_link_reciprocal_socket(_editing, socket)
	_editing = null
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

# Cancel edit: restore the building to its original position.
func _cancel_edit() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	# Restore original transform
	_editing.global_transform = _edit_original_transform
	var col := _editing.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = false
	_apply_building_color(_editing)
	# Re-register at original grid cell
	_grid_register(_edit_original_cell, _editing)
	# Re-link sockets at original position
	var piece_name := _piece_name_from_node(_editing)
	if piece_name != "Foundation":
		var raft := _get_raft_node()
		if raft != null:
			var support: Node3D = null
			var bp: Node3D = raft.get_node_or_null("BuiltPieces")
			if bp != null:
				for sibling in bp.get_children():
					if sibling == _editing or not (sibling is Node3D):
						continue
					if sibling.get_node_or_null("BuildSockets") == null:
						continue
					var d: float = (sibling.global_position - _edit_original_transform.origin).length()
					if d < 5.0:
						support = sibling
						break
				if support == null:
					support = raft
			if support != null:
				var socket: BuildSocket = _find_best_socket(support, piece_name, _edit_original_transform.origin, Vector3.UP)
				if socket != null:
					socket.occupy(_editing)
					_link_reciprocal_socket(_editing, socket)
	# Clear edit state
	_editing = null
	_edit_valid = false
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

# Remove the edited building and refund resources.
func _remove_editing() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	var building_name := _editing.name
	# Unregister from grid
	var cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_unregister(cell)
	# Free support sockets that reference this piece
	var raft: Node3D = _get_raft_node()
	if raft != null:
		var bp: Node3D = raft.get_node_or_null("BuiltPieces")
		if bp != null:
			for sibling in bp.get_children():
				if sibling == _editing or not (sibling is Node3D):
					continue
				if sibling.get_node_or_null("BuildSockets") == null:
					continue
				for s in _get_all_sockets(sibling):
					if s.is_occupied and s.occupying_piece == _editing:
						s.free_socket()
	# Refund resources
	for recipe_name in RECIPE_REFUND:
		if building_name.begins_with(recipe_name):
			var refund: Dictionary = RECIPE_REFUND[recipe_name]
			for item in refund:
				Inventory.add(item, refund[item])
			break
	_editing.queue_free()
	_editing = null
	_edit_valid = false
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

func _set_edit_color(mat: StandardMaterial3D) -> void:
	if _editing == null:
		return
	var stack: Array[Node] = _editing.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

func _apply_building_color(obj: Node3D) -> void:
	if obj.name.begins_with("Door") or obj.name.begins_with("Window"):
		var reset_stack: Array[Node] = obj.get_children()
		while not reset_stack.is_empty():
			var n: Node = reset_stack.pop_back()
			if n is MeshInstance3D:
				(n as MeshInstance3D).set_surface_override_material(0, null)
			for c in n.get_children():
				reset_stack.append(c)
		return
	var building_name := obj.name
	var color := Color(0.72, 0.53, 0.30)
	if building_name.begins_with("Wall"):
		color = Color(0.62, 0.43, 0.22)
	elif building_name.begins_with("Stairs"):
		color = Color(0.55, 0.38, 0.20)
	var stack: Array[Node] = obj.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

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
		var piece_name: String = _piece_name_from_node(_editing)
		var status := "[VALID]" if _edit_valid else "[INVALID]"
		text += "\n--- EDIT MODE ---"
		text += "\nPiece: " + piece_name
		text += "\nStatus: " + status
		if not _edit_valid and _editing != null:
			text += "\nReason: Aim at empty supported cell"
		text += "\nP=Place  R/Y=Rotate  X=Remove  B=Cancel"
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
		text += "\nR/Y=Rotate(90°)  Shift+R=15°  Tab=Switch  P=Place  B=Exit"
		text += "\nF3=Overlay " + ("ON" if build_overlay else "OFF")
		if build_overlay:
			text += _overlay_hud_text()
		elif debug_building and _diag.size() > 0:
			text += _format_debug_hud()
		else:
			# Always show footprint info and reason when available
			if _diag.has("footprint_ratio"):
				var _fp_r: float = _diag["footprint_ratio"]
				var _fp_s: int = int(_diag.get("footprint_supported", 0))
				var _fp_t: int = int(_diag.get("footprint_total", 0))
				text += "\nSupport: %d/%d (%.0f%%)" % [_fp_s, _fp_t, _fp_r * 100.0]
			if _diag.has("wall_foundation"):
				text += "\nSurface: " + str(_diag["wall_foundation"])
			if not build_valid and _diag.size() > 0:
				var reason: String = str(_diag.get("invalid_reason", ""))
				if reason == "":
					reason = str(_diag.get("final", "UNKNOWN"))
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
