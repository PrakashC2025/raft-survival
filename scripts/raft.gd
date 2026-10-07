extends AnimatableBody3D
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")

@export var float_height: float = 0.20
@export var follow_speed: float = 3.0

var ocean: Ocean = null
var _markers: Array = []
var _extra_sample_points: Array[Node3D] = []
var _deck_samples := PackedVector3Array()
var _deck_sample_timer := 0.0
var _deck_sample_dirty := true
var _deck_center := Vector3.ZERO
var _deck_radius := 1.0
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
# own corner/center markers so the raft's buoyancy sampling expands to
# cover the growing structure.
func register_sample_point(marker: Node3D) -> void:
	_deck_sample_dirty=true
	if marker != null and not _extra_sample_points.has(marker):
		_extra_sample_points.append(marker)


# Called when a piece is removed (Fix support for X / remove_build).
func unregister_sample_point(marker: Node3D) -> void:
	_deck_sample_dirty=true
	_extra_sample_points.erase(marker)


func _physics_process(delta: float) -> void:
	var before_move := global_position
	var next_position := _course_position(delta)
	var horizontal_delta := next_position-before_move
	if horizontal_delta.length_squared() > 0.000001:
		_carry_passenger(before_move, horizontal_delta)

	var oc := _get_ocean()
	if oc == null:
		global_position=next_position
		return
	_deck_sample_timer+=delta
	if _deck_sample_dirty or _deck_sample_timer>=0.5:
		_refresh_deck_samples()
	var next_rotation := _swell_rotation(oc,delta,next_position)
	var next_basis := (get_parent() as Node3D).global_basis*Basis.from_euler(next_rotation)
	var crest := -INF
	for at in _deck_samples:
		var offset := next_basis*at
		# Every tilted corner gets the same minimum clearance, including large
		# decks. Subtract its height so the downhill edge cannot enter a wave.
		crest=maxf(crest,oc.get_height(next_position+offset)-offset.y)
	var time := float(oc.get("_time"))
	var bob := sin(time*0.84)*0.012+sin(time*1.19+1.3)*0.008
	var target_y := crest+maxf(float_height,0.20)+bob
	var smooth_y := lerpf(global_position.y,target_y,1.0-exp(-follow_speed*delta))
	# Safe freeboard takes precedence over smoothing on a rising crest. Lower
	# gently after the swell; a large foundation must never follow its average.
	next_position.y=maxf(smooth_y,crest+0.12)
	# AnimatableBody sync_to_physics queues a transform and restores the current
	# one until the physics tick. Separate setters overwrite the queued tilt.
	global_transform=Transform3D(next_basis,next_position)

func _swell_rotation(oc: Ocean,delta: float,next_position: Vector3) -> Vector3:
	var player := get_tree().get_first_node_in_group("player")
	# Existing socket solvers use a level structural plane. Keep that exact
	# plane during construction/editing rather than saving a counter-tilt.
	if player!=null and (bool(player.get("build_mode")) or is_instance_valid(player.get("_editing"))):
		return Vector3(0,rotation.y,0)
	var yaw_basis := Basis(Vector3.UP,rotation.y)
	var center := next_position+yaw_basis*_deck_center
	var span := clampf(_deck_radius*0.5,1.0,4.0)
	var dx := yaw_basis.x*span
	var dz := yaw_basis.z*span
	var pitch := atan((oc.get_height(center-dz)-oc.get_height(center+dz))/(2.0*span))*0.45
	var roll := atan((oc.get_height(center+dx)-oc.get_height(center-dx))/(2.0*span))*0.45
	# Heavier expanded rafts rock less; their outer edges move at most 10 cm.
	var limit := minf(0.028,0.10/maxf(_deck_radius,1.0))
	var follow := 1.0-exp(-1.6*delta)
	return Vector3(lerp_angle(rotation.x,clampf(pitch,-limit,limit),follow),rotation.y,
		lerp_angle(rotation.z,clampf(roll,-limit,limit),follow))

func _refresh_deck_samples() -> void:
	_deck_sample_dirty=false;_deck_sample_timer=0.0
	var origins: Array[Vector3]=[Vector3.ZERO]
	var built := get_node_or_null("BuiltPieces")
	if built!=null:
		for child in built.get_children():
			if child is Node3D and str(child.name).begins_with("Foundation") and absf(child.position.y)<0.2:
				origins.append(child.position)
	var unique := {}
	for center in origins:
		for x in [-1.0,0.0,1.0]:
			for z in [-1.0,0.0,1.0]:
				unique[Vector3(center.x+x,0,center.z+z)]=true
	_deck_samples=PackedVector3Array(unique.keys())
	var low := Vector3.ZERO
	var high := Vector3.ZERO
	_deck_radius=1.0
	for at in _deck_samples:
		low=low.min(at);high=high.max(at)
		_deck_radius=maxf(_deck_radius,maxf(absf(at.x),absf(at.z)))
	_deck_center=(low+high)*0.5


func _course_position(delta: float) -> Vector3:
	if not _course_active:
		return global_position
	var to_target := Vector2(_course_target.x - global_position.x,
			_course_target.z - global_position.z)
	var distance := to_target.length()
	if distance <= _arrival_radius:
		_course_active = false
		return global_position
	var travel := minf(distance - _arrival_radius, get_navigation_speed() * delta)
	var direction := to_target / maxf(distance, 0.001)
	if distance - travel <= _arrival_radius:
		_course_active = false
	return global_position+Vector3(direction.x*travel,0,direction.y*travel)


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
