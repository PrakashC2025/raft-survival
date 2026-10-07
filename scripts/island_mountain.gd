extends Node3D
## Original smooth coastal ridge GLB, one shared material and one static collider.

@export_range(3.0, 9.0, 0.1) var base_radius := 4.5
@export_range(4.0, 12.0, 0.1) var peak_height := 7.2
@export_range(16, 64, 1) var radial_segments := 32
@export_range(6, 20, 1) var height_rings := 11
@export var random_seed := 77531

const MOUNTAIN_SHADER: Shader = preload("res://shaders/island_mountain.gdshader")
const RIDGE: PackedScene = preload("res://models/coastal_ridge.glb")
static var _rock_material: ShaderMaterial
static var _ridge_mesh: Mesh
static var _scaled_meshes: Dictionary = {}
static var _shapes: Dictionary = {}


func _ready() -> void:
	add_to_group("island_visual_detail")
	if _ridge_mesh == null:
		var model := RIDGE.instantiate()
		_ridge_mesh = (model.find_child("CraggyRockMesh", true, false) as MeshInstance3D).mesh
		model.free()
	var body := StaticBody3D.new()
	body.name = "MountainCollision"
	body.add_to_group("island_ground")
	add_child(body)
	# Three solid, cached headlands retain the existing beach and resource IDs.
	var size := _ridge_mesh.get_aabb().size
	var dimensions := Vector3(base_radius * 2.0 / size.x, peak_height / size.y, base_radius * 1.65 / size.z)
	for index in range(3):
		var scale_factor: float = [1.0, 0.64, 0.72][index]
		var scale_value := dimensions * scale_factor
		var key := str(scale_value)
		if not _scaled_meshes.has(key):
			var arrays := _ridge_mesh.surface_get_arrays(0).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex in range(vertices.size()):
				vertices[vertex] *= scale_value
				normals[vertex] = (normals[vertex] / scale_value).normalized()
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			var scaled := ArrayMesh.new()
			scaled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_scaled_meshes[key] = scaled
			_shapes[key] = scaled.create_trimesh_shape()
		var visual := MeshInstance3D.new()
		visual.name = "CraggyRockMesh" if index == 0 else "RockHeadland%d" % index
		visual.mesh = _scaled_meshes[key]
		visual.material_override = rock_material()
		visual.position = [Vector3.ZERO, Vector3(-base_radius * 1.1, -0.4, 1.3), Vector3(base_radius * 1.2, -0.65, 2.0)][index]
		visual.rotation.y = [0.0, -0.7, 0.55][index]
		visual.visibility_range_end = 900
		visual.add_to_group("no_collision")
		add_child(visual)
		var collision := CollisionShape3D.new()
		collision.shape = _shapes[key]
		collision.transform = visual.transform
		body.add_child(collision)

static func rock_material() -> ShaderMaterial:
	if _rock_material == null:
		_rock_material = ShaderMaterial.new()
		_rock_material.shader = MOUNTAIN_SHADER
		_rock_material.set_shader_parameter("rock_albedo", preload("res://textures/island/rock_diff.jpg"))
		_rock_material.set_shader_parameter("rock_normal", preload("res://textures/island/rock_nor_gl.jpg"))
		_rock_material.set_shader_parameter("rock_arm", preload("res://textures/island/rock_arm.jpg"))
	return _rock_material


func _build_mountain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var angle_offsets: PackedFloat32Array = PackedFloat32Array()
	for i in range(radial_segments):
		angle_offsets.append(rng.randf_range(-0.12, 0.12))

	var rings: Array[PackedVector3Array] = []
	for ring in range(height_rings + 1):
		var t := float(ring) / float(height_rings)
		var ring_points := PackedVector3Array()
		var taper := pow(maxf(0.0, 1.0 - t), 0.86)
		for i in range(radial_segments):
			var a := TAU * float(i) / float(radial_segments) + angle_offsets[i]
			var ridge_a := sin(a * 5.0 + 0.8) * 0.11 + sin(a * 9.0 - 1.4) * 0.055
			var broken_ridge := sin(a * 13.0 + t * 8.0) * 0.035
			var radius := base_radius * maxf(0.015, taper * (1.0 + ridge_a + broken_ridge))
			var vertical_crag := sin(a * 4.0 + 1.1) * 0.12 + sin(a * 11.0 + t * 4.0) * 0.055
			var y := peak_height * t + vertical_crag * (1.0 - t * 0.45)
			ring_points.append(Vector3(cos(a) * radius, y, sin(a) * radius))
		rings.append(ring_points)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(height_rings):
		for segment in range(radial_segments):
			var next := (segment + 1) % radial_segments
			var a := rings[ring][segment]
			var b := rings[ring][next]
			var c := rings[ring + 1][segment]
			var d := rings[ring + 1][next]
			_add_rock_triangle(surface, a, c, b)
			_add_rock_triangle(surface, b, c, d)
	# Cap the peak and the buried foot for a closed trimesh collider.
	var summit := Vector3(0.0, peak_height + 0.12, 0.0)
	for segment in range(radial_segments):
		var next := (segment + 1) % radial_segments
		_add_rock_triangle(surface, rings[height_rings][segment], summit, rings[height_rings][next])
		_add_rock_triangle(surface, Vector3.ZERO, rings[0][segment], rings[0][next])

	var mesh := surface.commit()
	if mesh == null:
		return
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_SHADER
	var visual := MeshInstance3D.new()
	visual.name = "CraggyRockMesh"
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.add_to_group("no_collision") # this script owns its single collider
	add_child(visual)

	var body := StaticBody3D.new()
	body.name = "MountainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.name = "MountainTrimesh"
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	print("[IslandMountain] generated %d-facet island peak" % (radial_segments * height_rings * 2))


func _add_rock_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var face_normal := (b - a).cross(c - a).normalized()
	if face_normal.length_squared() < 0.01:
		return
	var center_y := (a.y + b.y + c.y) / 3.0
	var elevation := clampf(center_y / peak_height, 0.0, 1.0)
	var slope := 1.0 - clampf(face_normal.y, 0.0, 1.0)
	var low_rock := Color(0.34, 0.245, 0.16)
	var mid_rock := Color(0.40, 0.39, 0.36)
	var high_rock := Color(0.62, 0.55, 0.43)
	var color := low_rock.lerp(mid_rock, smoothstep(0.08, 0.63, elevation))
	color = color.lerp(high_rock, smoothstep(0.66, 0.98, elevation) * 0.78)
	color = color.lerp(Color(0.26, 0.29, 0.29), clampf(slope * 0.20, 0.0, 0.18))
	var variation := 0.94 + absf(sin((a.x + b.z + c.y) * 21.37)) * 0.10
	color *= variation
	surface.set_color(color)
	surface.set_normal(face_normal)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.set_normal(face_normal)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.set_normal(face_normal)
	surface.add_vertex(c)
