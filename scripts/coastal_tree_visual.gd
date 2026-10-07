@static_unload
extends RefCounted
## Original curved 3D foliage sharing one compact photographic atlas. Meshes
## and materials are cached across islands and growing planter instances.
const ATLAS: Texture2D = preload("res://textures/ui/coastal_tree_atlas.png")
static var _meshes: Dictionary = {}
static var _leaf_material: ShaderMaterial
static var _bark_material: StandardMaterial3D
static func create(kind: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "TexturedBanana" if kind == 0 else "CoastalAlmond" if kind == 1 else "CoastalShadeTree"
	if _leaf_material == null:
		_leaf_material = ShaderMaterial.new()
		_leaf_material.shader = preload("res://shaders/palm_leaf.gdshader")
		_leaf_material.set_shader_parameter("use_albedo_texture",true)
		_leaf_material.set_shader_parameter("albedo_texture",ATLAS)
		_leaf_material.set_shader_parameter("leaf_radius",2.0)
		_leaf_material.set_shader_parameter("wind_strength",0.045)
		_bark_material = StandardMaterial3D.new()
		_bark_material.albedo_texture = ATLAS
		_bark_material.roughness = 0.94
	if not _meshes.has(kind): _meshes[kind] = _build(kind)
	var meshes: Array = _meshes[kind]
	for surface in range(2):
		var mesh := MeshInstance3D.new()
		mesh.name = "TexturedLeaves" if surface == 1 else "TexturedStem"
		mesh.mesh = meshes[surface]
		if surface == 1:
			mesh.material_override = _leaf_material
		else:
			mesh.material_override = _bark_material
		mesh.visibility_range_end = 120 if surface == 1 else 240
		mesh.visibility_range_end_margin = 12
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if surface == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.extra_cull_margin = 0.15
		root.add_child(mesh)
	return root
static func _build(kind: int) -> Array:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_height := 2.25 if kind == 0 else 3.3 if kind == 1 else 3.8
	_branch(bark,Vector3.ZERO,Vector3(0.08,stem_height,0),0.13 if kind == 0 else 0.16,kind)
	if kind == 0:
		for leaf in range(8):
			var angle := float(leaf)*2.4
			var length := 1.6+sin(float(leaf)*2.1)*0.3
			_ribbon(leaves,Vector3(0.08,stem_height-float(leaf%3)*0.10,0),angle,length,0.65,0)
	else:
		for branch in range(9):
			var angle := float(branch)*2.4
			var tier := float(branch%3)
			var start := Vector3(0.06,stem_height-1.3+tier*0.42,0)
			var end := start+Vector3(cos(angle),0.35,sin(angle))*(1.0+tier*0.22)
			_branch(bark,start,end,0.045,kind)
			for spray in range(6):
				var center := start.lerp(end,0.30+float(spray)*0.135)
				_ribbon(leaves,center,angle+sin(float(spray)*1.7)*0.8,0.58,0.40,1)
	bark.generate_normals()
	leaves.generate_normals()
	bark.index()
	leaves.index()
	return [bark.commit(),leaves.commit()]
static func _branch(builder: SurfaceTool, start: Vector3, end: Vector3, radius: float, kind: int) -> void:
	var direction := (end-start).normalized()
	var axis := Vector3.UP.cross(direction)
	var basis := Basis.IDENTITY if axis.length_squared() < 0.00001 else Basis(axis.normalized(),acos(clampf(Vector3.UP.dot(direction),-1,1)))
	var cylinder := CylinderMesh.new()
	cylinder.height = start.distance_to(end)
	cylinder.bottom_radius = radius
	cylinder.top_radius = radius*0.62
	cylinder.radial_segments = 10
	cylinder.rings = 1
	var arrays := cylinder.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in range(uv.size()):
		uv[index] = Vector2((uv[index].x*0.96+0.02)*0.5+(0.5 if kind > 0 else 0.0),(uv[index].y*0.96+0.02)*0.5+0.5)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	builder.append_from(mesh,0,Transform3D(basis,(start+end)*0.5))
static func _ribbon(builder: SurfaceTool, base: Vector3, angle: float, length: float, width: float, tile: int) -> void:
	var outward := Vector3(cos(angle),0,sin(angle))
	var side := Vector3(-sin(angle),0,cos(angle))
	for segment in range(6):
		var a := float(segment)/6.0
		var b := float(segment+1)/6.0
		var ca := base+outward*length*a+Vector3.UP*(sin(a*PI)*0.45-a*a*0.36)
		var cb := base+outward*length*b+Vector3.UP*(sin(b*PI)*0.45-b*b*0.36)
		for half in range(2):
			var sign_value := -1.0 if half == 0 else 1.0
			var pa := ca+side*width*0.5*sign_value-Vector3.UP*0.07
			var pb := cb+side*width*0.5*sign_value-Vector3.UP*0.07
			var points: Array[Vector3] = [ca,cb,pa,pa,cb,pb]
			var across := 0.0 if half == 0 else 1.0
			var coords: Array[Vector2] = [Vector2(0.5,1-a),Vector2(0.5,1-b),Vector2(across,1-a),Vector2(across,1-a),Vector2(0.5,1-b),Vector2(across,1-b)]
			for index in range(6):
				builder.set_uv(coords[index]*Vector2(0.48,0.48)+Vector2(0.01+tile*0.5,0.01))
				builder.add_vertex(points[index])
