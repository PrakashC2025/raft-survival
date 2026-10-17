extends StaticBody3D
## One sealed, buoyant cargo case. The expedition service owns its rewards.
var service: Node
var cargo_kind := 0
var available := true
var visual: Node3D
var _caption: Label3D
var _sea: Node3D
var _current := Vector3(0, 0, .32)
var _drift_tick := 0.0

func _ready() -> void:
	add_to_group("drift_cache")
	collision_layer = 2
	collision_mask = 0
	set_meta("map_label", service.cargo_name(cargo_kind))
	set_meta("arrival_radius", 4.0)
	set_meta("biome", "cargo")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, .8, 1.05)
	shape.shape = box
	shape.position.y = .24
	add_child(shape)
	visual = Node3D.new()
	visual.name = "SealedCargo"
	add_child(visual)
	var wood := preload("res://scripts/object_materials.gd").make(0, Color(.26, .17, .09), .9)
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(.10, .15, .16)
	strap.roughness = .8
	var signal_color: Color = [Color(.86,.49,.16),Color(.22,.53,.62),Color(.38,.57,.22),Color(.75,.26,.22)][cargo_kind]
	var paint := StandardMaterial3D.new()
	paint.albedo_color = signal_color
	paint.roughness = .82
	for i in 6:
		_part(Vector3(1.20,.105,.95), Vector3(0,-.12+float(i)*.108,0), wood)
	for x in [-.43, .43]:
		_part(Vector3(.065,.70,1.01),Vector3(x,.18,0),strap)
	_part(Vector3(1.22,.08,.98),Vector3(0,.55,0),paint)
	_part(Vector3(.03,1.3,.03),Vector3(.5,1.17,0),strap)
	_part(Vector3(.42,.25,.025),Vector3(.30,1.67,0),paint)
	_part(Vector3(.23,.055,.03),Vector3(.29,1.67,-.02),strap)
	_part(Vector3(.055,.18,.03),Vector3(.29,1.67,-.025),strap)
	_caption = Label3D.new()
	_caption.name = "CargoManifest"
	_caption.text = service.cargo_name(cargo_kind).to_upper()+" · RECOVER 3 s\n"+service.manifest(cargo_kind)
	_caption.font_size = 25
	_caption.pixel_size = .003
	_caption.position.y = 2.0
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.visibility_range_end = 11
	add_child(_caption)
	_sea = get_tree().get_first_node_in_group("ocean") as Node3D
	var stream := get_tree().current_scene.get_node_or_null("DebrisSpawner")
	if stream != null:
		var direction: Vector3 = stream.current_direction
		direction.y = 0
		if direction.length_squared() > .01:
			_current = direction.normalized()*clampf(float(stream.current_speed),.1,.45)
	if is_instance_valid(_sea):global_position.y = float(_sea.call("get_height",global_position))+.10

func _part(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	visual.add_child(mesh)

func interaction_caption() -> String:
	return "RECOVER CARGO" if available else "RECOVERED"

func interact_survival(actor: Node3D) -> void:
	if available and is_instance_valid(service) and actor == service.player:service.start_recovery(self)

func _physics_process(delta: float) -> void:
	if not available or not is_instance_valid(_sea):return
	# Sample the identical ocean surface as boats. Exponential response is frame-rate independent.
	var height := float(_sea.call("get_height",global_position))
	global_position.y = lerpf(global_position.y,height+.10,1.0-exp(-delta*5.0))
	var across := float(_sea.call("get_height",global_position+global_basis.x*.65))
	var ahead := float(_sea.call("get_height",global_position-global_basis.z*.55))
	visual.rotation.z = lerp_angle(visual.rotation.z,clampf(atan2(across-height,.65),-.12,.12),1.0-exp(-delta*3.0))
	visual.rotation.x = lerp_angle(visual.rotation.x,clampf(atan2(ahead-height,.55),-.12,.12),1.0-exp(-delta*3.0))
	_drift_tick += delta
	if _drift_tick < .25:return
	var step := minf(_drift_tick,.5)
	_drift_tick = 0.0
	# Stay in the water when the current meets a beach, hull or foundation.
	var next := global_position+_current*step
	if service.water_clear(next):
		global_position.x = next.x
		global_position.z = next.z

func save_state() -> Dictionary:
	return {"kind":cargo_kind,"p":[global_position.x,global_position.y,global_position.z],"yaw":rotation.y}
