extends Node3D
## Rope-bound, rounded timbers share cached meshes and raft-wide instance draws.
## Original scene boxes remain hidden solver/physics proxies, preserving saves.
@export_enum("Foundation", "Wall", "Roof") var kind := "Foundation"
@export var wall_height := 2.5
const WOOD_SHADER := preload("res://shaders/wood_planks.gdshader")
const ROPE_SHADER := preload("res://shaders/rope_fiber.gdshader")
const ATLAS := preload("res://textures/construction/timber_photographic_atlas.png")
static var _meshes: Dictionary = {}
static var _hemp: ShaderMaterial

static func _rope_material() -> ShaderMaterial:
	if _hemp == null:
		_hemp = ShaderMaterial.new()
		_hemp.shader = ROPE_SHADER
	return _hemp

static func _wood(strip: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WOOD_SHADER
	material.set_shader_parameter("photographic_wood", true)
	material.set_shader_parameter("wood_texture", ATLAS)
	material.set_shader_parameter("atlas_strip", strip)
	material.set_shader_parameter("authored_timber_uv", true)
	material.set_shader_parameter("solid_timber", true)
	material.set_shader_parameter("tint_variation", 0.12)
	material.set_shader_parameter("wood_darkening", 0.86 if strip == 1.0 else 1.0)
	return material

# Retained for callers that need a rectangular metal/structural detail.
static func box(size: Vector3, color: Color) -> BoxMesh:
	var key := "box:" + str(size) + str(color)
	if _meshes.has(key): return _meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := _wood(2.0)
	mat.set_shader_parameter("authored_timber_uv", false)
	mat.set_shader_parameter("horizontal_boards", size.x > size.y)
	mat.set_shader_parameter("half_x", size.x / 2)
	mat.set_shader_parameter("half_y", size.y / 2)
	mat.set_shader_parameter("half_z", size.z / 2)
	mesh.material = mat
	_meshes[key] = mesh
	return mesh

static func rounded_timber(size: Vector3, strip: float = 0.0) -> ArrayMesh:
	var key := "round:" + str(size) + str(strip)
	if _meshes.has(key): return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_wood(strip))
	_add_log(surface, size, Vector3.ZERO, 0)
	surface.generate_tangents()
	var mesh := surface.commit()
	_meshes[key] = mesh
	return mesh

static func panel(size: Vector3, vertical: bool, strip: float = 0.0, count: int = 5) -> ArrayMesh:
	var key := "panel:" + str(size) + str(vertical) + str(strip) + str(count)
	if _meshes.has(key): return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_wood(strip))
	for index in count:
		var timber_size := Vector3(size.x / count - 0.002, size.y, size.z) if vertical else Vector3(size.x, size.y, size.z / count - 0.002)
		var center := Vector3(-size.x / 2 + (index + 0.5) * size.x / count, 0, 0) if vertical else Vector3(0, 0, -size.z / 2 + (index + 0.5) * size.z / count)
		_add_log(surface, timber_size, center, index)
	surface.generate_tangents()
	var mesh := surface.commit()
	_meshes[key] = mesh
	return mesh

static func _axis_point(axis: int, along: float, cross_a: float, cross_b: float) -> Vector3:
	if axis == 0: return Vector3(along, cross_a, cross_b)
	if axis == 1: return Vector3(cross_a, along, cross_b)
	return Vector3(cross_a, cross_b, along)

static func _add_log(surface: SurfaceTool, size: Vector3, center: Vector3, index: int) -> void:
	var axis := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	var length := size[axis]
	var radius_a := (size.y if axis == 0 else size.x) / 2
	var radius_b := (size.y if axis == 2 else size.z) / 2
	# Smooth elliptical timbers have broad tops, rounded shoulders and subtly
	# tapered ends. Adjacent members nearly touch; joints stay only 2 mm wide.
	for edge in range(16):
		var angle := TAU * edge / 16
		var next_angle := TAU * (edge + 1) / 16
		var normal_a := _axis_point(axis, 0, cos(angle) / radius_a, sin(angle) / radius_b).normalized()
		var normal_b := _axis_point(axis, 0, cos(next_angle) / radius_a, sin(next_angle) / radius_b).normalized()
		for segment in range(3):
			var t0: float = [0.0, 0.025, 0.975, 1.0][segment]
			var t1: float = [0.0, 0.025, 0.975, 1.0][segment + 1]
			var taper0 := 0.97 if segment == 0 else 1.0
			var taper1 := 0.97 if segment == 2 else 1.0
			var a := center + _axis_point(axis, (t0 - 0.5) * length, cos(angle) * radius_a * taper0, sin(angle) * radius_b * taper0)
			var b := center + _axis_point(axis, (t1 - 0.5) * length, cos(angle) * radius_a * taper1, sin(angle) * radius_b * taper1)
			var c := center + _axis_point(axis, (t1 - 0.5) * length, cos(next_angle) * radius_a * taper1, sin(next_angle) * radius_b * taper1)
			var d := center + _axis_point(axis, (t0 - 0.5) * length, cos(next_angle) * radius_a * taper0, sin(next_angle) * radius_b * taper0)
			var offset := float(index) * 0.173
			var uva := Vector2(t0 * length + offset, float(edge) / 16 + offset)
			var uvb := Vector2(t1 * length + offset, float(edge) / 16 + offset)
			var uvc := Vector2(t1 * length + offset, float(edge + 1) / 16 + offset)
			var uvd := Vector2(t0 * length + offset, float(edge + 1) / 16 + offset)
			# Select clockwise winding by outward radial normals for all axes.
			_face(surface, [a,b,c], [normal_a,normal_a,normal_b], [uva,uvb,uvc])
			_face(surface, [a,c,d], [normal_a,normal_b,normal_b], [uva,uvc,uvd])
		for end in [-1.0, 1.0]:
			var middle := center + _axis_point(axis, end * length / 2, 0, 0)
			var a := middle + _axis_point(axis, 0, cos(angle) * radius_a * 0.97, sin(angle) * radius_b * 0.97)
			var b := middle + _axis_point(axis, 0, cos(next_angle) * radius_a * 0.97, sin(next_angle) * radius_b * 0.97)
			var normal := _axis_point(axis, end, 0, 0)
			_face(surface, [middle,a,b], [normal,normal,normal], [Vector2(0.5,0.5), Vector2(cos(angle),sin(angle))*0.5+Vector2(0.5,0.5), Vector2(cos(next_angle),sin(next_angle))*0.5+Vector2(0.5,0.5)])

static func _face(surface: SurfaceTool, vertices: Array, normals: Array, uvs: Array) -> void:
	var winding: Vector3 = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
	var order := [0,2,1] if winding.dot(normals[0]+normals[1]+normals[2]) > 0 else [0,1,2]
	for index in order:
		surface.set_normal(normals[index])
		surface.set_uv(uvs[index])
		surface.add_vertex(vertices[index])

static func rope_loop(half_size: Vector2, axis: int) -> ArrayMesh:
	var key := "binding:" + str(half_size) + str(axis)
	if _meshes.has(key): return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_rope_material())
	# Constant-thickness hemp follows a rounded rectangular loop around the
	# entire joined surface, rather than four loose decorative corner rings.
	var points: Array[Vector3] = []
	var corner_radius := minf(0.035, minf(half_size.x,half_size.y)*0.5)
	for corner in range(4):
		var angle := PI / 2 * corner
		var center := Vector2(1 if corner in [0,3] else -1, 1 if corner < 2 else -1) * (half_size-Vector2.ONE*corner_radius)
		for segment in range(5):
			var theta := angle + PI / 2 * segment / 4
			var point := center + Vector2(cos(theta),sin(theta))*corner_radius
			points.append(_axis_point(axis,0,point.x,point.y))
	points.append(points[0])
	_add_braided_rope(surface, points, _axis_point(axis,1,0,0))
	surface.generate_tangents()
	var mesh := surface.commit()
	_meshes[key] = mesh
	return mesh

static func _add_braided_rope(surface: SurfaceTool, path: Array[Vector3], across: Vector3) -> void:
	# Three real helical strands, with metre-based UVs. Cached and instanced.
	var distance := 0.0
	for edge in range(path.size()-1):
		var length := path[edge].distance_to(path[edge+1])
		var segments := maxi(1,ceili(length/0.075))
		var tangent := (path[edge+1]-path[edge]).normalized()
		var other := tangent.cross(across).normalized()
		for segment in segments:
			var a := float(segment)/segments
			var b := float(segment+1)/segments
			var da := distance+length*a
			var db := distance+length*b
			for strand in 3:
				var phase := TAU*float(strand)/3.0
				var ca := path[edge].lerp(path[edge+1],a)+(across*cos(da*TAU/0.24+phase)+other*sin(da*TAU/0.24+phase))*0.014
				var cb := path[edge].lerp(path[edge+1],b)+(across*cos(db*TAU/0.24+phase)+other*sin(db*TAU/0.24+phase))*0.014
				for side in 4:
					var n0 := across*cos(TAU*side/4.0)+other*sin(TAU*side/4.0)
					var n1 := across*cos(TAU*(side+1)/4.0)+other*sin(TAU*(side+1)/4.0)
					var p0 := ca+n0*0.013
					var p1 := cb+n0*0.013
					var p2 := cb+n1*0.013
					var p3 := ca+n1*0.013
					var uv0 := Vector2(da,float(side)/4.0)
					var uv1 := Vector2(db,float(side)/4.0)
					var uv2 := Vector2(db,float(side+1)/4.0)
					var uv3 := Vector2(da,float(side+1)/4.0)
					_face(surface,[p0,p1,p2],[n0,n0,n1],[uv0,uv1,uv2])
					_face(surface,[p0,p2,p3],[n0,n1,n1],[uv0,uv2,uv3])
		distance += length

static func rope_knot() -> ArrayMesh:
	if _meshes.has("hemp_knot"): return _meshes["hemp_knot"]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_rope_material())
	var path: Array[Vector3] = []
	for index in range(33):
		var t := float(index)/32.0*TAU
		path.append(Vector3(sin(t)*0.085, sin(t*2.0)*0.022, sin(t*2.0)*0.045))
	_add_braided_rope(surface,path,Vector3.UP)
	_add_braided_rope(surface,[Vector3(-0.04,0,-0.02),Vector3(-0.11,0.006,-0.10),Vector3(-0.17,-0.01,-0.12)],Vector3.UP)
	surface.generate_tangents()
	var mesh := surface.commit()
	_meshes["hemp_knot"] = mesh
	return mesh

func batch(mesh: Mesh, transforms: Array[Transform3D], label: String, distance: float = 90.0) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in transforms.size(): multi.set_instance_transform(index,transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.visibility_range_end = distance
	instance.visibility_range_end_margin = 5.0
	add_child(instance)

func _ready() -> void:
	var proxy := get_parent().get_node_or_null("MeshInstance3D") as MeshInstance3D
	if proxy != null:
		proxy.visible = false
		proxy.set_meta("structural_proxy",true)
	for old_seam in get_parent().find_children("Seam*","MeshInstance3D",false,false):
		old_seam.visible = false
		old_seam.set_meta("structural_proxy",true)
	var timbers := MeshInstance3D.new()
	timbers.name = "JoinedRoundedTimbers"
	timbers.mesh = panel(Vector3(2,wall_height,0.20),true,1.0) if kind == "Wall" else panel(Vector3(2,0.30 if kind == "Foundation" else 0.15,2),false)
	add_child(timbers)
	var rails: Array[Transform3D] = []
	var bindings: Array[Transform3D] = []
	var knots: Array[Transform3D] = []
	if kind == "Wall":
		for y in [-wall_height*0.30,wall_height*0.30]:
			rails.append(Transform3D(Basis.IDENTITY,Vector3(0,y,-0.14)))
			bindings.append(Transform3D(Basis.IDENTITY,Vector3(0,y,0)))
			bindings.append(Transform3D(Basis.IDENTITY,Vector3(0,y+0.055,0)))
			for x in [-0.85,0.85]: knots.append(Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(x,y+0.025,0.23)))
		batch(rounded_timber(Vector3(2,0.12,0.12),2),rails,"BackCrossTimbers")
		batch(rope_loop(Vector2(1.01,0.21),1),bindings,"HempBindings",45.0)
	else:
		for x in [-0.74,0.74]:
			rails.append(Transform3D(Basis.IDENTITY,Vector3(x,-0.10 if kind == "Foundation" else -0.04,0)))
			bindings.append(Transform3D(Basis.IDENTITY,Vector3(x,0,0)))
			bindings.append(Transform3D(Basis.IDENTITY,Vector3(x+0.055,0,0)))
			for z in [-0.82,0.82]: knots.append(Transform3D(Basis.IDENTITY,Vector3(x+0.025,0.18 if kind == "Foundation" else 0.11,z)))
		batch(rounded_timber(Vector3(0.12,0.12,2),2),rails,"UnderDeckBearers")
		batch(rope_loop(Vector2(0.16 if kind == "Foundation" else 0.09,1.01),0),bindings,"HempBindings",45.0)
	batch(rope_knot(),knots,"BindingKnots",28.0)
