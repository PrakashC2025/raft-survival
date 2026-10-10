extends AnimatableBody3D
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")

@export var float_height: float = 0.045
@export var follow_speed: float = 9.0

var ocean: Ocean = null
var _markers: Array = []
var _extra_sample_points: Array[Node3D] = []
var _deck_samples := PackedVector3Array()
var _deck_sample_timer := 0.0
var _deck_sample_dirty := true
var _deck_center := Vector3.ZERO
var _deck_radius := 1.0
var _sample_wave_time := -INF
var _sample_wave_settings := Vector3.ZERO
var _sample_origin := Vector3.ZERO
var _sample_basis := Basis.IDENTITY
var _sample_crest := 0.0
var _motion_frame := -1
var _motion_wave_time := -INF
var _motion_level := false
var _pending_motion_delta := 0.0
var upgrade_tier := 0
var _course_active := false
var _course_target := Vector3.ZERO
var _arrival_radius := 14.0
var anchored := false
var _paddle_velocity := Vector3.ZERO
var _anchor_rig: Node3D
var _anchor_tween: Tween


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
	set_anchored(bool(Inventory.loaded_meta.get("raft_anchored",false)),false)


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


func set_course(target: Vector3,arrival: float=14.0) -> bool:
	if anchored or get_navigation_speed() <= 0.0:
		return false
	_arrival_radius=clampf(arrival,14,80)
	_paddle_velocity=Vector3.ZERO
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
	_pending_motion_delta+=delta
	var oc := _get_ocean()
	var frame := Engine.get_process_frames()
	var wave_time := oc._time if oc != null else 0.0
	var actor := get_tree().get_first_node_in_group("player")
	var level_deck := actor != null and (bool(actor.get("build_mode")) or is_instance_valid(actor.get("_editing")))
	# Moving this parent invalidates every foundation collider/child transform.
	# Catch-up ticks share one visible wave frame: move the compound raft once,
	# carrying elapsed navigation/smoothing time forward to the next update.
	if frame == _motion_frame and wave_time == _motion_wave_time and level_deck == _motion_level and not _deck_sample_dirty:
		return
	_motion_frame=frame
	_motion_wave_time=wave_time
	_motion_level=level_deck
	delta=_pending_motion_delta
	_pending_motion_delta=0.0
	var before_move := global_position
	var next_position := navigation_position(delta)
	var horizontal_delta := next_position-before_move
	if horizontal_delta.length_squared() > 0.000001:
		_carry_passenger(before_move, horizontal_delta)

	if oc == null:
		global_position=next_position
		return
	_deck_sample_timer+=delta
	if _deck_sample_dirty or _deck_sample_timer>=0.5:
		_refresh_deck_samples()
	var next_rotation := _swell_rotation(oc,delta,next_position)
	var next_basis := (get_parent() as Node3D).global_basis*Basis.from_euler(next_rotation)
	# Batch the same tilted-corner probes; the downhill edge keeps its full
	# clearance without hundreds of separate Node calls each physics tick.
	var crest := _deck_crest(oc,next_position,next_basis)
	var time := float(oc.get("_time"))
	var bob := sin(time*0.84)*0.003+sin(time*1.19+1.3)*0.002
	var target_y := crest+clampf(float_height,0.035,0.07)+bob
	var smooth_y := lerpf(global_position.y,target_y,1.0-exp(-follow_speed*delta))
	# Safe freeboard takes precedence over smoothing on a rising crest. Lower
	# gently after the swell; a large foundation must never follow its average.
	# Rounded logs extend 14 cm below the deck plane. A 4.5 cm freeboard
	# keeps their lower part submerged instead of lifting them clear of water.
	next_position.y=clampf(smooth_y,crest+0.035,crest+0.085)
	# AnimatableBody sync_to_physics queues a transform and restores the current
	# one until the physics tick. Separate setters overwrite the queued tilt.
	global_transform=Transform3D(next_basis,next_position)

func _deck_crest(oc: Ocean, origin: Vector3, deck_basis: Basis) -> float:
	var settings := Vector3(oc.wave_height,oc.wave_speed,oc.global_position.y)
	var motion := origin-_sample_origin
	var dx := deck_basis.x-_sample_basis.x
	var dz := deck_basis.z-_sample_basis.z
	var horizontal := absf(motion.x)+absf(motion.z) \
			+_deck_radius*(absf(dx.x)+absf(dx.z)+absf(dz.x)+absf(dz.z))
	var vertical := _deck_radius*(absf(dx.y)+absf(dz.y))
	# Ocean advances once per rendered frame. Physics may run several catch-up
	# steps against that identical wave field: reuse its crest with a conservative
	# bound for small raft movement/tilt, rather than resampling the whole deck.
	if _sample_wave_time == oc._time and _sample_wave_settings == settings \
			and horizontal <= 0.12 and vertical <= 0.025:
		return _sample_crest+oc.get_wave_slope_bound()*horizontal+vertical
	_sample_crest=oc.get_deck_crest(origin,deck_basis,_deck_samples)
	_sample_wave_time=oc._time
	_sample_wave_settings=settings
	_sample_origin=origin
	_sample_basis=deck_basis
	return _sample_crest

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
	_sample_wave_time=-INF
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
	if anchored or not _course_active:
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

func paddle_stroke(direction: Vector3) -> bool:
	if anchored or not direction.is_finite():return false
	direction.y=0
	if direction.length_squared()<.01:return false
	clear_course()
	_paddle_velocity=(_paddle_velocity+direction.normalized()*1.35).limit_length(2.3)
	return true

func navigation_position(delta: float) -> Vector3:
	if anchored:return global_position
	var next := _course_position(delta)
	if not _course_active and _paddle_velocity.length_squared()>.0001:
		var drag := exp(-.9*delta)
		next+=_paddle_velocity*(1.0-drag)/.9
		_paddle_velocity*=drag
	# New large landmasses must stop a rowed hull at the shoreline.
	for island in get_tree().get_nodes_in_group("biome_island"):
		var local: Vector3=island.to_local(next)
		if Vector2(local.x,local.z).length()>50:continue
		if island.call("height_at",Vector2(local.x,local.z))> -1.6:
			_paddle_velocity=Vector3.ZERO;clear_course();return global_position
	return next

func set_anchored(enabled: bool,animate: bool=true) -> void:
	anchored=enabled
	if enabled:clear_course();_paddle_velocity=Vector3.ZERO
	if _anchor_rig==null and enabled:
		_anchor_rig=Node3D.new();_anchor_rig.name="AnchorRig";_anchor_rig.position=Vector3(.85,0,.7);add_child(_anchor_rig)
		var anchor:=preload("res://scripts/survival_tool_visual.gd").create("Anchor");anchor.name="IronAnchor";_anchor_rig.add_child(anchor)
		var rope_mat:=OBJECT_MATERIALS.make(OBJECT_MATERIALS.Kind.CLOTH,Color(.35,.25,.13),.98)
		var new_rope:=preload("res://scripts/machine_visual.gd").cylinder(_anchor_rig,Vector3(0,-2,0),.012,4,rope_mat);new_rope.name="AnchorRope"
	if _anchor_rig==null:return
	if _anchor_tween!=null and _anchor_tween.is_valid():_anchor_tween.kill()
	var iron:=_anchor_rig.get_node("IronAnchor") as Node3D
	var rope:=_anchor_rig.get_node("AnchorRope") as Node3D
	rope.show()
	_anchor_rig.show()
	if animate:
		_anchor_tween=create_tween().set_parallel(true)
		_anchor_tween.tween_property(iron,"position:y",-4.0 if enabled else .02,.8)
		_anchor_tween.tween_property(rope,"scale:y",1.0 if enabled else .01,.8)
		_anchor_tween.tween_property(rope,"position:y",-2.0 if enabled else .0,.8)
		if not enabled:_anchor_tween.chain().tween_callback(_anchor_rig.hide)
	else:
		iron.position.y=-4.0 if enabled else .02;rope.visible=enabled;_anchor_rig.visible=enabled


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
