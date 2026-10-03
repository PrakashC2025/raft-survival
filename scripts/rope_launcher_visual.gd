extends RefCounted
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")
const HUMAN_HAND: PackedScene = preload("res://models/human_hand.glb")
## Original lightweight rope-launcher geometry, batched once by material.
## Units are metres; the barrel points down local -Z.

static func create_launcher(with_hand: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "RopeLauncher"
	var batches: Dictionary = {}
	var steel := _material(Color(0.43, 0.48, 0.50), 0.32, 0.82)
	var dark := _material(Color(0.07, 0.09, 0.10), 0.66, 0.2)
	var body := _material(Color(0.27, 0.31, 0.23), 0.62, 0.35)
	var brass := _material(Color(0.63, 0.42, 0.15), 0.42, 0.65)
	var cord := _material(Color(0.58, 0.43, 0.25), 0.95, 0.0)
	# Receiver, barrel shroud, exposed steel muzzle and bore.
	_box(batches, body, Vector3(0.125, 0.12, 0.28), Vector3(0, 0.065, -0.16))
	_cylinder(batches, steel, 0.039, 0.043, 0.46, Vector3(0, 0.08, -0.39), Vector3.RIGHT, PI / 2.0)
	_cylinder(batches, dark, 0.047, 0.047, 0.19, Vector3(0, 0.08, -0.35), Vector3.RIGHT, PI / 2.0)
	_cylinder(batches, steel, 0.056, 0.056, 0.022, Vector3(0, 0.08, -0.62), Vector3.RIGHT, PI / 2.0)
	_cylinder(batches, dark, 0.033, 0.033, 0.008, Vector3(0, 0.08, -0.636), Vector3.RIGHT, PI / 2.0)
	# Sight rail and its raised posts.
	_box(batches, dark, Vector3(0.026, 0.025, 0.25), Vector3(0, 0.145, -0.2))
	_box(batches, steel, Vector3(0.011, 0.024, 0.011), Vector3(0, 0.166, -0.32))
	_box(batches, brass, Vector3(0.045, 0.016, 0.027), Vector3(0, 0.163, -0.095))
	# Angled grip, ridges and a closed trigger guard.
	_box(batches, dark, Vector3(0.072, 0.19, 0.092), Vector3(0, -0.06, -0.04), Basis(Vector3.RIGHT, -0.2))
	for index in range(4):
		_box(batches, body, Vector3(0.076, 0.008, 0.095), Vector3(0, -0.015 - index * 0.036, -0.04), Basis(Vector3.RIGHT, -0.2))
	var guard := PackedVector3Array([Vector3(0, 0.007, -0.1), Vector3(0, -0.055, -0.17), Vector3(0, -0.105, -0.15), Vector3(0, -0.12, -0.08)])
	_tube(batches, steel, guard, 0.008, 6)
	_box(batches, brass, Vector3(0.015, 0.043, 0.012), Vector3(0, -0.028, -0.108), Basis(Vector3.RIGHT, -0.25))
	# Side reel: narrow wound rope inside two flanges, axle and crank.
	var spool := Vector3(-0.108, 0.047, -0.20)
	_cylinder(batches, dark, 0.071, 0.071, 0.10, spool, Vector3.FORWARD, PI / 2.0)
	for side in [-1.0, 1.0]:
		_cylinder(batches, steel, 0.092, 0.092, 0.013, spool + Vector3(side * 0.056, 0, 0), Vector3.FORWARD, PI / 2.0)
	var winding := PackedVector3Array()
	for index in range(193):
		var fraction := float(index) / 192.0
		var angle := fraction * TAU * 9.0
		winding.append(spool + Vector3(lerpf(-0.048, 0.048, fraction), cos(angle) * 0.076, sin(angle) * 0.076))
	_tube(batches, cord, winding, 0.0058, 5)
	_cylinder(batches, brass, 0.018, 0.018, 0.035, spool + Vector3(-0.08, 0, 0), Vector3.FORWARD, PI / 2.0)
	_box(batches, steel, Vector3(0.01, 0.075, 0.014), spool + Vector3(-0.105, -0.032, 0))
	_cylinder(batches, dark, 0.014, 0.014, 0.035, spool + Vector3(-0.12, -0.069, 0), Vector3.FORWARD, PI / 2.0)
	# Cord guide from the reel to the rear of the firing channel.
	_tube(batches, cord, PackedVector3Array([spool + Vector3(-0.025, 0.074, 0), Vector3(-0.05, 0.13, -0.36), Vector3(0, 0.08, -0.58)]), 0.006, 5)
	for z in [-0.075, -0.22]:
		_cylinder(batches, steel, 0.011, 0.011, 0.007, Vector3(0.066, 0.07, z), Vector3.FORWARD, PI / 2.0)
	if with_hand:
		var hand := HUMAN_HAND.instantiate() as Node3D
		OBJECT_MATERIALS.apply_model(hand, OBJECT_MATERIALS.Kind.SKIN)
		hand.name = "HumanHand"
		hand.position = Vector3(0.04, -0.065, -0.015)
		root.add_child(hand)
	_finish(root, batches)
	var muzzle := Marker3D.new()
	muzzle.name = "LaunchMuzzle"
	muzzle.position = Vector3(0, 0.08, -0.654)
	root.add_child(muzzle)
	# A compact four-prong head sits on the barrel while loaded.
	var loaded := create_hook()
	loaded.name = "LoadedHook"
	loaded.position = muzzle.position
	loaded.scale = Vector3.ONE * 0.64
	root.add_child(loaded)
	return root

static func create_hook() -> Node3D:
	var root := Node3D.new()
	root.name = "GrapplingHook"
	var batches: Dictionary = {}
	var metal := _material(Color(0.51, 0.56, 0.58), 0.35, 0.88)
	var dark := _material(Color(0.12, 0.16, 0.17), 0.65, 0.5)
	_cylinder(batches, metal, 0.022, 0.029, 0.21, Vector3(0, 0, -0.03), Vector3.RIGHT, PI / 2.0)
	_cylinder(batches, dark, 0.039, 0.039, 0.04, Vector3(0, 0, 0.04), Vector3.RIGHT, PI / 2.0)
	for index in range(4):
		var angle := float(index) * TAU / 4.0
		var points := PackedVector3Array()
		for point in [Vector2(0.025, 0.025), Vector2(0.07, -0.07), Vector2(0.09, -0.14), Vector2(0.06, -0.19)]:
			points.append(Vector3(cos(angle) * point.x, sin(angle) * point.x, point.y))
		_tube(batches, metal, points, 0.009, 6)
	_finish(root, batches)
	return root

static func _material(color: Color, roughness: float, metallic: float) -> Material:
	var kind := OBJECT_MATERIALS.Kind.METAL if metallic > 0.3 else OBJECT_MATERIALS.Kind.CLOTH
	return OBJECT_MATERIALS.make(kind, color, roughness, metallic)

static func _box(batches: Dictionary, material: Material, size: Vector3, position: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := _beveled_box(size)
	_append(batches, material, mesh, Transform3D(basis, position))

static func _beveled_box(size: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var bevel := minf(0.009, minf(size.x, minf(size.y, size.z)) * 0.16)
	var core := half - Vector3.ONE * bevel
	# Six flat panels, twelve chamfer strips and eight clipped corners.
	for axis in range(3):
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var points: Array[Vector3] = []
			for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = half[axis] * sign_value
				point[a] = core[a] * offset.x
				point[b] = core[b] * offset.y
				points.append(point)
			_triangle(surface, points[0], points[1], points[2], normal)
			_triangle(surface, points[0], points[2], points[3], normal)
	for axes in [[0, 1], [0, 2], [1, 2]]:
		var a: int = axes[0]
		var b: int = axes[1]
		var c := 3 - a - b
		for sign_a in [-1.0, 1.0]:
			for sign_b in [-1.0, 1.0]:
				var normal := Vector3.ZERO
				normal[a] = sign_a
				normal[b] = sign_b
				var first := Vector3.ZERO
				first[a] = half[a] * sign_a
				first[b] = core[b] * sign_b
				first[c] = -core[c]
				var second := first
				second[a] = core[a] * sign_a
				second[b] = half[b] * sign_b
				var third := second
				third[c] = core[c]
				var fourth := first
				fourth[c] = core[c]
				_triangle(surface, first, second, third, normal.normalized())
				_triangle(surface, first, third, fourth, normal.normalized())
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var signs := Vector3(x, y, z)
				var points: Array[Vector3] = []
				for axis in range(3):
					var point := core * signs
					point[axis] = half[axis] * signs[axis]
					points.append(point)
				_triangle(surface, points[0], points[1], points[2], signs.normalized())
	surface.index()
	return surface.commit()

static func _triangle(surface: SurfaceTool, first: Vector3, second: Vector3, third: Vector3, normal: Vector3) -> void:
	# Godot fronts use clockwise winding, opposite the outward normal cross.
	var points: Array[Vector3] = [first, second, third]
	if (second - first).cross(third - first).dot(normal) > 0.0:
		points[1] = third
		points[2] = second
	for point in points:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)
static func _cylinder(batches: Dictionary, material: Material, top: float, bottom: float, height: float, position: Vector3, axis: Vector3, angle: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	_append(batches, material, mesh, Transform3D(Basis(axis, angle), position))

static func _capsule(batches: Dictionary, material: Material, radius: float, height: float, position: Vector3, basis: Basis) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 3
	_append(batches, material, mesh, Transform3D(basis, position))

static func _append(batches: Dictionary, material: Material, mesh: Mesh, transform: Transform3D) -> void:
	if not batches.has(material):
		var new_batch := SurfaceTool.new()
		new_batch.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[material] = new_batch
	var surface: SurfaceTool = batches[material]
	surface.append_from(mesh, 0, transform)

static func _tube(batches: Dictionary, material: Material, points: PackedVector3Array, radius: float, sides: int) -> void:
	if not batches.has(material):
		var new_batch := SurfaceTool.new()
		new_batch.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[material] = new_batch
	var surface: SurfaceTool = batches[material]
	for segment in range(points.size() - 1):
		var direction := (points[segment + 1] - points[segment]).normalized()
		var helper := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
		var right := direction.cross(helper).normalized()
		var up := right.cross(direction).normalized()
		for side in range(sides):
			var a := TAU * float(side) / sides
			var b := TAU * float(side + 1) / sides
			var na := right * cos(a) + up * sin(a)
			var nb := right * cos(b) + up * sin(b)
			var verts := [points[segment] + na * radius, points[segment + 1] + nb * radius, points[segment + 1] + na * radius, points[segment] + na * radius, points[segment] + nb * radius, points[segment + 1] + nb * radius]
			for index in range(6):
				surface.set_normal(nb if index in [1, 4, 5] else na)
				surface.set_uv(Vector2(float(side) / sides, float(segment)))
				surface.add_vertex(verts[index])

static func _finish(root: Node3D, batches: Dictionary) -> void:
	for material in batches:
		var surface: SurfaceTool = batches[material]
		surface.index()
		var instance := MeshInstance3D.new()
		instance.mesh = surface.commit()
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
