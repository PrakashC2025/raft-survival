extends RefCounted
## Nine rounded timbers, lashings, cross-braces with clear deck space.
const SURFACES := preload("res://scripts/object_materials.gd")
const WOOD := preload("res://textures/construction/timber_photographic_atlas.png")
static var _timber: ShaderMaterial
static var _log: CylinderMesh
static func create() -> Node3D:
	var root := Node3D.new()
	root.name = "StarterRaftVisual"
	if _timber == null:
		_timber = ShaderMaterial.new()
		_timber.shader = preload("res://shaders/raft_timber.gdshader")
		_timber.set_shader_parameter("wood_texture",WOOD)
		_log = CylinderMesh.new()
		_log.top_radius = 0.13
		_log.bottom_radius = 0.14
		_log.height = 2.12
		_log.radial_segments = 12
	var logs := MultiMeshInstance3D.new()
	logs.name = "RoundedTimbers"
	logs.material_override = _timber
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _log
	batch.instance_count = 9
	for i in range(9):
		var basis := Basis(Vector3.FORWARD,PI/2)*Basis.from_scale(Vector3(1.0,0.97+float(i%3)*0.025,1.0))
		batch.set_instance_transform(i,Transform3D(basis,Vector3(float(i%3-1)*0.025,0,float(i-4)*0.23)))
	logs.multimesh = batch
	root.add_child(logs)
	var braces := MultiMeshInstance3D.new()
	braces.name = "CrossBraces"
	braces.material_override = _timber
	var brace_batch := MultiMesh.new()
	brace_batch.transform_format = MultiMesh.TRANSFORM_3D
	brace_batch.mesh = _log
	brace_batch.instance_count = 2
	for i in range(2):
		brace_batch.set_instance_transform(i,Transform3D(Basis(Vector3.RIGHT,PI/2)*Basis.from_scale(Vector3(0.5,1,0.5)),Vector3(-0.72+i*1.44,-0.18,0)))
	braces.multimesh = brace_batch
	root.add_child(braces)
	var rope := ShaderMaterial.new()
	rope.shader = preload("res://shaders/rope_fiber.gdshader")
	rope.set_shader_parameter("photographic_hemp",true)
	rope.set_shader_parameter("hemp_atlas",WOOD)
	for i in range(2):
		var strap := MeshInstance3D.new()
		strap.name = "RopeLashing"+str(i)
		var ring := TorusMesh.new()
		ring.inner_radius = 1.01
		ring.outer_radius = 1.04
		ring.rings = 32
		ring.ring_segments = 6
		strap.mesh = ring
		strap.material_override = rope
		strap.transform = Transform3D(Basis(Vector3.FORWARD,PI/2)*Basis.from_scale(Vector3(0.17,1,1.04)),Vector3(-0.75+i*1.5,-0.035,0))
		root.add_child(strap)
	return root
