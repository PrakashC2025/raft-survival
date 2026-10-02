extends RefCounted
## Shared lightweight materials. Only visual surfaces change; trunk collision,
## fruit sockets and saved transforms keep their existing geometry.

static var _leaves: ShaderMaterial
static var _bark: ShaderMaterial
static var _grass_tuft: ArrayMesh
static var _fronds: ArrayMesh

static func palm_fronds() -> ArrayMesh:
	if _fronds != null:
		return _fronds
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(8):
		var angle := float(frond) * TAU / 8.0
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		var length := 0.48 + sin(float(frond) * 2.1) * 0.045
		for segment in range(10):
			var t := float(segment + 1) / 11.0
			var center := outward * length * t + Vector3.UP * (sin(t * PI) * 0.09 - t * t * 0.065)
			var leaflet_length := 0.018 + sin(t * PI) * 0.12
			for sign_value in [-1.0, 1.0]:
				var across: Vector3 = side * float(sign_value)
				var front := center + outward * 0.035 + across * leaflet_length * 0.45 + Vector3.UP * 0.006
				var tip := center - outward * 0.022 + across * leaflet_length - Vector3.UP * 0.008
				var back := center - outward * 0.032 + across * leaflet_length * 0.43
				_leaf_triangle(builder, center, front, tip)
				_leaf_triangle(builder, center, tip, back)
		for segment in range(8):
			var a := float(segment) / 8.0
			var b := float(segment + 1) / 8.0
			var pa := outward * length * a + Vector3.UP * (sin(a * PI) * 0.09 - a * a * 0.065)
			var pb := outward * length * b + Vector3.UP * (sin(b * PI) * 0.09 - b * b * 0.065)
			_leaf_triangle(builder, pa - side * 0.008, pb - side * 0.003, pa + side * 0.008)
			_leaf_triangle(builder, pa + side * 0.008, pb - side * 0.003, pb + side * 0.003)
	builder.generate_normals()
	_fronds = builder.commit()
	return _fronds

static func _leaf_triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var vertices: Array[Vector3] = [a, b, c]
	if (b - a).cross(c - a).dot(Vector3.UP) > 0.0:
		vertices[1] = c
		vertices[2] = b
	for point in vertices:
		builder.set_uv(Vector2(point.x, point.z))
		builder.add_vertex(point)

static func grass_tuft() -> ArrayMesh:
	if _grass_tuft != null:
		return _grass_tuft
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(3):
		var angle := float(blade) * 2.4
		var side := Vector3(cos(angle), 0.0, sin(angle))
		var lean := Vector3(-sin(angle), 0.0, cos(angle))
		var height: float = [0.30, 0.38, 0.27][blade]
		for segment in range(4):
			var a := float(segment) / 4.0
			var b := float(segment + 1) / 4.0
			var pa := Vector3.UP * height * a + lean * 0.09 * a * a
			var pb := Vector3.UP * height * b + lean * 0.09 * b * b
			var wa := 0.023 * (1.0 - a * a)
			var wb := 0.023 * (1.0 - b * b)
			var vertices: Array[Vector3] = [pa - side * wa, pb - side * wb, pa + side * wa,
				pa + side * wa, pb - side * wb, pb + side * wb]
			var heights: Array[float] = [a, b, a, a, b, b]
			var sides: Array[float] = [0.0, 0.0, 1.0, 1.0, 0.0, 1.0]
			for vertex in range(6):
				builder.set_color(Color(heights[vertex], heights[vertex], heights[vertex], 1.0))
				builder.set_uv(Vector2(sides[vertex], heights[vertex]))
				builder.add_vertex(vertices[vertex])
	builder.generate_normals()
	_grass_tuft = builder.commit()
	return _grass_tuft

static func apply_palm(root: Node3D) -> void:
	if _leaves == null:
		_leaves = ShaderMaterial.new()
		_leaves.shader = preload("res://shaders/palm_leaf.gdshader")
		_bark = ShaderMaterial.new()
		_bark.shader = preload("res://shaders/palm_bark.gdshader")
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var original := mesh_instance.mesh.surface_get_material(surface)
			var label := str(mesh_instance.name).to_lower()
			if original != null:
				label += original.resource_name.to_lower()
			if label.contains("leaf"):
				mesh_instance.mesh = palm_fronds()
				mesh_instance.set_surface_override_material(surface, _leaves)
				mesh_instance.extra_cull_margin = maxf(mesh_instance.extra_cull_margin, 0.3)
			elif label.contains("palm") or label.contains("bark"):
				mesh_instance.set_surface_override_material(surface, _bark)
