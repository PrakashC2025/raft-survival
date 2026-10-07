extends StaticBody3D
## Craftable cargo decoration: wooden crate, hemp coil and draped net.
## It is a physical prop; player inventory remains the existing authoritative bag.
const TIMBER := preload("res://scripts/construction_visual.gd")
static var _crate_mesh: ArrayMesh
static var _rope_material: ShaderMaterial
static var _coil_mesh: TorusMesh
static var _net_mesh: CylinderMesh

func _ready() -> void:
	if _rope_material == null:
		_rope_material = ShaderMaterial.new()
		_rope_material.shader = preload("res://shaders/rope_fiber.gdshader")
		_rope_material.set_shader_parameter("photographic_hemp",true)
		_rope_material.set_shader_parameter("hemp_atlas",TIMBER.ATLAS)
	if _crate_mesh == null:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var member := TIMBER.rounded_timber(Vector3(0.94,0.11,0.07),1)
		surface.set_material(member.surface_get_material(0))
		for y in [-0.25,-0.13,-0.01,0.11,0.23]:
			for z in [-0.33,0.33]: surface.append_from(member,0,Transform3D(Basis.IDENTITY,Vector3(-0.2,y,z)))
		var side := TIMBER.rounded_timber(Vector3(0.07,0.11,0.64),1)
		for y in [-0.25,-0.13,-0.01,0.11,0.23]:
			for x in [-0.67,0.27]: surface.append_from(side,0,Transform3D(Basis.IDENTITY,Vector3(x,y,0)))
		var lid := TIMBER.rounded_timber(Vector3(0.94,0.06,0.15),1)
		for z in [-0.24,-0.08,0.08,0.24]: surface.append_from(lid,0,Transform3D(Basis.IDENTITY,Vector3(-0.2,0.31,z)))
		for x in [-0.58,0.18]:
			var post := TIMBER.rounded_timber(Vector3(0.08,0.65,0.08),1)
			for z in [-0.34,0.34]: surface.append_from(post,0,Transform3D(Basis.IDENTITY,Vector3(x,0,z)))
		_crate_mesh = surface.commit()
	var crate := MeshInstance3D.new()
	crate.name = "WeatheredCargoCrate"
	crate.mesh = _crate_mesh
	add_child(crate)
	if _coil_mesh == null:
		_coil_mesh = TorusMesh.new()
		_coil_mesh.inner_radius = 0.15
		_coil_mesh.outer_radius = 0.19
		_coil_mesh.rings = 32
		_coil_mesh.ring_segments = 8
		_coil_mesh.material = _rope_material
	var coils: Array[Transform3D] = []
	for turn in range(5):
		var scale_size := 1.0-float(turn)*0.12
		coils.append(Transform3D(Basis.from_scale(Vector3(scale_size,1,scale_size)),Vector3(0.55,-0.29+turn*0.018,0.1)))
	_add_batch(_coil_mesh,coils,"HempRopeCoil")
	if _net_mesh == null:
		_net_mesh = CylinderMesh.new()
		_net_mesh.top_radius = 0.006
		_net_mesh.bottom_radius = 0.006
		_net_mesh.height = 1.0
		_net_mesh.radial_segments = 5
		_net_mesh.material = _rope_material
	var strands: Array[Transform3D] = []
	for row in range(6):
		for column in range(6):
			var a := _net_point(row,column)
			if row < 5: _strand(strands,a,_net_point(row+1,column))
			if column < 5: _strand(strands,a,_net_point(row,column+1))
	_add_batch(_net_mesh,strands,"CargoNet")
	for x in [-0.55,0.12]:
		var strap := MeshInstance3D.new()
		strap.mesh = TIMBER.rope_loop(Vector2(0.34,0.35),0)
		strap.position.x = x
		add_child(strap)

func _net_point(row: int, column: int) -> Vector3:
	var u := float(column)/5.0
	var v := float(row)/5.0
	return Vector3(-0.5+u*0.6,0.27-v*0.57,0.38+sin(u*PI)*sin(v*PI)*0.07)

func _strand(transforms: Array[Transform3D], a: Vector3, b: Vector3) -> void:
	var direction := b-a
	var basis := Basis(Quaternion(Vector3.UP,direction.normalized()))*Basis.from_scale(Vector3(1,direction.length(),1))
	transforms.append(Transform3D(basis,(a+b)/2))

func _add_batch(mesh: Mesh, transforms: Array[Transform3D], label: String) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in transforms.size(): multi.set_instance_transform(index,transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	node.visibility_range_end = 45
	add_child(node)
