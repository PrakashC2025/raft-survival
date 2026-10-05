extends AnimatableBody3D
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")

@export var float_height: float = 0.6
@export var follow_speed: float = 4.0

var ocean: Ocean = null
var _markers: Array = []
var _extra_sample_points: Array[Node3D] = []
var upgrade_tier := 0
var _course_active := false
var _course_target := Vector3.ZERO
var _arrival_radius := 14.0


func _ready() -> void:
	add_to_group("build_surface")
	add_to_group("raft")
	_markers = [
		get_node_or_null("F1"),
		get_node_or_null("F2"),
		get_node_or_null("F3"),
		get_node_or_null("F4"),
	]
	rotation = Vector3.ZERO
	var starter := preload("res://scripts/starter_raft_visual.gd").create()
	add_child(starter)
	var old_deck := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_deck != null: old_deck.hide()


func _get_ocean() -> Ocean:
	if ocean == null or not is_instance_valid(ocean):
		ocean = get_tree().get_first_node_in_group("ocean") as Ocean
	return ocean


func set_upgrade_tier(tier: int) -> void:
	upgrade_tier = clampi(maxi(upgrade_tier, tier), 0, 2)
	_refresh_upgrade_visuals()


func get_navigation_speed() -> float:
	match upgrade_tier:
		1:
			return 2.7  # canvas sail
		2:
			return 4.8  # small outboard motor
	return 0.0


func set_course(target: Vector3) -> bool:
	if get_navigation_speed() <= 0.0:
		return false
	_course_target = Vector3(target.x, global_position.y, target.z)
	_course_active = Vector2(_course_target.x - global_position.x,
			_course_target.z - global_position.z).length() > _arrival_radius + 1.0
	return true


func clear_course() -> void:
	_course_active = false


func has_active_course() -> bool:
	return _course_active


func get_course_distance() -> float:
	if not _course_active:
		return 0.0
	return Vector2(_course_target.x - global_position.x,
			_course_target.z - global_position.z).length()


# Called by player.gd after a piece is placed, passing one of the piece's
# own corner/center markers so the raft's buoyancy averaging expands to
# cover the growing structure.
func register_sample_point(marker: Node3D) -> void:
	if marker != null and not _extra_sample_points.has(marker):
		_extra_sample_points.append(marker)


# Called when a piece is removed (Fix support for X / remove_build).
func unregister_sample_point(marker: Node3D) -> void:
	_extra_sample_points.erase(marker)


func _physics_process(delta: float) -> void:
	var before_move := global_position
	_advance_course(delta)
	var horizontal_delta := Vector3(global_position.x - before_move.x, 0.0,
			global_position.z - before_move.z)
	if horizontal_delta.length_squared() > 0.000001:
		_carry_passenger(before_move, horizontal_delta)

	var oc := _get_ocean()
	if oc == null:
		return
	var avg_height: float = 0.0
	var count: int = 0
	for marker in _markers:
		if marker != null and is_instance_valid(marker):
			avg_height += float(oc.get_height(marker.global_position))
			count += 1
	# Prune invalid refs lazily while summing (freed pieces, etc.).
	for i in range(_extra_sample_points.size() - 1, -1, -1):
		var marker := _extra_sample_points[i]
		if not is_instance_valid(marker):
			_extra_sample_points.remove_at(i)
			continue
		avg_height += float(oc.get_height(marker.global_position))
		count += 1
	if count > 0:
		avg_height /= float(count)
	var target_y: float = avg_height + float_height
	global_position.y = lerpf(global_position.y, target_y,
			1.0 - exp(-follow_speed * delta))


func _advance_course(delta: float) -> void:
	if not _course_active:
		return
	var to_target := Vector2(_course_target.x - global_position.x,
			_course_target.z - global_position.z)
	var distance := to_target.length()
	if distance <= _arrival_radius:
		_course_active = false
		return
	var travel := minf(distance - _arrival_radius, get_navigation_speed() * delta)
	var direction := to_target / maxf(distance, 0.001)
	global_position.x += direction.x * travel
	global_position.z += direction.y * travel
	if distance - travel <= _arrival_radius:
		_course_active = false


func _carry_passenger(raft_before_move: Vector3, movement: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.get("is_swimming") == true:
		return
	var relative := player.global_position - raft_before_move
	var horizontal_distance := Vector2(relative.x, relative.z).length()
	if horizontal_distance > 15.0 or relative.y < -0.3 or relative.y > 7.0:
		return
	player.global_position += movement


func _refresh_upgrade_visuals() -> void:
	var decoration := get_node_or_null("StarterRaftVisual/DecorativeRig") as Node3D
	if decoration != null: decoration.visible = upgrade_tier == 0
	if upgrade_tier >= 1 and get_node_or_null("SailUpgradeVisual") == null:
		_build_sail_visual()
	if upgrade_tier >= 2 and get_node_or_null("MotorUpgradeVisual") == null:
		_build_motor_visual()


func _build_sail_visual() -> void:
	var rig := Node3D.new()
	rig.name = "SailUpgradeVisual"
	rig.position = Vector3(0.0, 0.16, -0.15)
	add_child(rig)
	var wood := _mat(Color(0.36, 0.20, 0.1), 0.82)
	var canvas := OBJECT_MATERIALS.make(OBJECT_MATERIALS.Kind.CLOTH, Color(0.74, 0.68, 0.52), 0.9)
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.045
	mast_mesh.bottom_radius = 0.075
	mast_mesh.height = 3.8
	mast_mesh.radial_segments = 8
	_add_mesh(rig, "Mast", mast_mesh, wood, Vector3(0.0, 1.9, 0.0))
	var sail_mesh := QuadMesh.new()
	sail_mesh.size = Vector2(2.15, 2.35)
	var sail := MeshInstance3D.new()
	sail.name = "Canvas"
	sail.mesh = sail_mesh
	sail.material_override = canvas
	sail.position = Vector3(0.0, 2.35, -0.035)
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(sail)
	var boom := CylinderMesh.new()
	boom.top_radius = 0.035
	boom.bottom_radius = 0.035
	boom.height = 2.2
	boom.radial_segments = 7
	_add_mesh(rig, "Boom", boom, wood, Vector3(0.0, 1.18, -0.05), Vector3(0.0, 0.0, PI * 0.5))


func _build_motor_visual() -> void:
	var rig := Node3D.new()
	rig.name = "MotorUpgradeVisual"
	rig.position = Vector3(0.0, 0.05, 1.02)
	add_child(rig)
	var metal := _mat(Color(0.18, 0.23, 0.27), 0.35, 0.72)
	var accent := _mat(Color(0.78, 0.23, 0.12), 0.5)
	var case_mesh := BoxMesh.new()
	case_mesh.size = Vector3(0.48, 0.52, 0.43)
	_add_mesh(rig, "EngineCase", case_mesh, metal, Vector3(0.0, 0.12, 0.0))
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.19
	cap_mesh.bottom_radius = 0.19
	cap_mesh.height = 0.12
	cap_mesh.radial_segments = 10
	_add_mesh(rig, "FuelCap", cap_mesh, accent, Vector3(0.0, 0.43, -0.02))
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.055
	shaft.bottom_radius = 0.055
	shaft.height = 0.7
	shaft.radial_segments = 8
	_add_mesh(rig, "Shaft", shaft, metal, Vector3(0.0, -0.37, 0.18))
	var prop := BoxMesh.new()
	prop.size = Vector3(0.52, 0.06, 0.11)
	_add_mesh(rig, "PropellerA", prop, metal, Vector3(0.0, -0.74, 0.18))
	var prop_cross := BoxMesh.new()
	prop_cross.size = Vector3(0.11, 0.06, 0.52)
	_add_mesh(rig, "PropellerB", prop_cross, metal, Vector3(0.0, -0.74, 0.18))


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material,
		at: Vector3, euler: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation = euler
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _mat(color: Color, roughness: float, metallic: float = 0.0) -> Material:
	var kind := OBJECT_MATERIALS.Kind.METAL if metallic > 0.5 else OBJECT_MATERIALS.Kind.WOOD
	return OBJECT_MATERIALS.make(kind, color, roughness, metallic)
