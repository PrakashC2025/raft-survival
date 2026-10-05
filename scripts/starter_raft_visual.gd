extends RefCounted
## Nine rounded timbers, lashings, cross-braces and a purely decorative cloth.
const SURFACES := preload("res://scripts/object_materials.gd")
const WOOD := preload("res://textures/ui/weathered_raft_wood.png")
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
	var rope := SURFACES.make(SURFACES.Kind.CLOTH,Color(0.36,0.27,0.16))
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
	var rig := Node3D.new()
	rig.name = "DecorativeRig"
	rig.set_meta("cosmetic_only",true)
	# Keep the cosmetic cloth at the aft edge, clear of the starting view and
	# the centre of the third-person camera's line of sight.
	rig.position = Vector3(-0.88,0.13,0.68)
	root.add_child(rig)
	var mast := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.042
	pole.height = 1.75
	pole.radial_segments = 8
	mast.mesh = pole
	mast.material_override = _timber
	mast.position.y = 0.85
	rig.add_child(mast)
	for i in range(3):
		var tie := MeshInstance3D.new()
		var collar := TorusMesh.new()
		collar.inner_radius = 0.035
		collar.outer_radius = 0.049
		collar.rings = 16
		collar.ring_segments = 6
		tie.mesh = collar
		tie.material_override = rope
		tie.position.y = 0.25+i*0.027
		rig.add_child(tie)
	var cloth := MeshInstance3D.new()
	cloth.name = "SalvagedCloth"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(5):
		for x in range(7):
			if y == 0 and x in [2,6]: continue
			for point in [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y),Vector2(x+1,y+1),Vector2(x,y+1)]:
				var uv: Vector2 = Vector2(point)/Vector2(7,5)
				surface.set_uv(uv)
				surface.add_vertex(Vector3(-0.04-uv.x*0.68,0.6+uv.y*0.78+(sin(uv.x*17)*0.025 if y == 0 else 0),0))
	surface.generate_normals()
	cloth.mesh = surface.commit()
	var canvas := ShaderMaterial.new()
	canvas.shader = preload("res://shaders/starter_sail.gdshader")
	cloth.material_override = canvas
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(cloth)
	return root
