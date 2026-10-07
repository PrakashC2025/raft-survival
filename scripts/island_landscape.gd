extends Node3D
## Shared original geometry and CC0 scans. Terrain rays run once, in bounded batches.
const TREE_VISUAL := preload("res://scripts/coastal_tree_visual.gd")
const ROCK_VISUAL := preload("res://scripts/island_mountain.gd")
const SHORE_SIZE := 32
static var _boulder_mesh: ArrayMesh
var landscape_ready := false

func _ready() -> void:
	call_deferred("_prepare")

func _prepare() -> void:
	var island := get_parent() as Node3D
	var setup := island.get_node_or_null("IslandSetup")
	if setup == null: setup = island.get_node_or_null("../IslandSetup")
	for frame in range(900):
		if setup != null and setup.get("setup_complete") == true: break
		await get_tree().physics_frame
		if not is_inside_tree(): return
	var radius := 15.0 if island.name == "Island" else 9.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(island.get("pickup_seed"))
	var canopy: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var trunks := StaticBody3D.new()
	trunks.name = "LandscapeTrunks"
	add_child(trunks)
	for index in range(24):
		# The rear half becomes a layered grove while the approach beach stays open.
		var point := Vector2(rng.randf_range(-radius * 0.75, radius * 0.75),
			rng.randf_range(-radius * 0.65, radius * 0.12))
		var hit := _ground(island.to_global(Vector3(point.x, 0, point.y)))
		if not hit.is_empty() and Vector3(hit.normal).y > 0.48 and Vector3(hit.position).y >= 0.42:
			var scale_value := rng.randf_range(0.72, 1.18) if index < 12 else rng.randf_range(0.24, 0.45)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale_value)
			var local_position := to_local(Vector3(hit.position))
			var transform_value := Transform3D(basis, local_position)
			if index < 12:
				canopy.append(transform_value)
				var collider := CollisionShape3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = 0.13 * scale_value
				shape.height = 2.5 * scale_value
				collider.shape = shape
				collider.position = local_position + Vector3.UP * shape.height * 0.5
				trunks.add_child(collider)
			else:
				shrubs.append(transform_value)
		if index % 8 == 7:
			await get_tree().physics_frame
			if not is_inside_tree(): return
	_batch_trees(1, canopy, "Canopy")
	_batch_trees(0, shrubs, "Understory")
	var stones: Array[Transform3D] = []
	var shore_rocks := StaticBody3D.new()
	shore_rocks.name = "ShoreRockCollision"
	shore_rocks.add_to_group("island_ground")
	add_child(shore_rocks)
	for point in [Vector2(-0.82,0.28), Vector2(-0.74,0.48), Vector2(-0.64,0.59),
			Vector2(0.80,0.24), Vector2(0.75,0.47), Vector2(0.65,0.62), Vector2(-0.58,-0.68), Vector2(0.62,-0.66)]:
		var hit := _ground(island.to_global(Vector3(point.x * radius, 0, point.y * radius)))
		if hit.is_empty(): continue
		var position_value := Vector3(hit.position)
		if position_value.y < -1.0: continue
		var scale_value := rng.randf_range(0.75, 1.65)
		position_value.y += 0.38 * scale_value
		var local_position := to_local(position_value)
		stones.append(Transform3D(Basis(Vector3.UP,rng.randf() * TAU).scaled(Vector3.ONE * scale_value),local_position))
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.70 * scale_value
		shape.height = 1.40 * scale_value
		collider.shape = shape
		collider.position = local_position
		shore_rocks.add_child(collider)
	_add_batch("ShoreBoulders", _rock_mesh(), ROCK_VISUAL.rock_material(), stones, false)
	await get_tree().physics_frame
	if not is_inside_tree(): return
	await _shore_mask(radius + 6.0)
	if is_inside_tree(): landscape_ready = true

func _ground(position_value: Vector3) -> Dictionary:
	var from := Vector3(position_value.x, 26.0, position_value.z)
	return get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, Vector3(from.x,-28,from.z), 1))

func _batch_trees(kind: int, transforms: Array[Transform3D], label: String) -> void:
	var template := TREE_VISUAL.create(kind)
	for index in range(2):
		var part := template.get_child(index) as MeshInstance3D
		_add_batch(label + str(index), part.mesh, part.material_override, transforms, true)
	template.free()

func _add_batch(label: String, mesh_value: Mesh, material_value: Material, transforms: Array[Transform3D], foliage: bool) -> void:
	if transforms.is_empty(): return
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = mesh_value
	batch.multimesh.instance_count = transforms.size()
	for index in range(transforms.size()): batch.multimesh.set_instance_transform(index, transforms[index])
	batch.material_override = material_value
	batch.visibility_range_end = 110.0 if foliage else 220.0
	batch.visibility_range_end_margin = 12.0
	batch.extra_cull_margin = 0.2
	if foliage:
		batch.add_to_group("island_landscape_foliage")
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if label.ends_with("1") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(batch)
	var performance := get_tree().get_first_node_in_group("mobile_performance")
	if performance != null: performance.call("refresh_foliage")

static func _rock_mesh() -> ArrayMesh:
	if _boulder_mesh != null: return _boulder_mesh
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 12
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		var p := vertices[index]
		var wear := 1.0 + sin(p.x * 7.0 + p.z * 4.0) * 0.08 + sin(p.y * 9.0 - p.x * 3.0) * 0.05
		vertices[index] = p * Vector3(1.0,0.72,0.86) * wear
		normals[index] = (normals[index] / Vector3(1.0,0.72,0.86)).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	_boulder_mesh = ArrayMesh.new()
	_boulder_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _boulder_mesh

func _shore_mask(extent: float) -> void:
	# 4 KB per island, one optional water lookup; no screen/depth/reflection pass.
	var height_image := Image.create(SHORE_SIZE, SHORE_SIZE, false, Image.FORMAT_RF)
	var center := global_position
	var ray_batch := 16 if OS.has_feature("mobile") or OS.has_feature("android") else 64
	for index in range(SHORE_SIZE * SHORE_SIZE):
		var x := index % SHORE_SIZE
		var z := floori(float(index) / float(SHORE_SIZE))
		var position_value := center + Vector3(
			((float(x) + 0.5) / SHORE_SIZE * 2.0 - 1.0) * extent,0,
			((float(z) + 0.5) / SHORE_SIZE * 2.0 - 1.0) * extent)
		var hit := _ground(position_value)
		height_image.set_pixel(x,z,Color(float(Vector3(hit.position).y) if not hit.is_empty() else -20.0,0,0,1))
		if index % ray_batch == ray_batch - 1:
			await get_tree().physics_frame
			if not is_inside_tree(): return
	var ocean := get_tree().get_first_node_in_group("ocean")
	if ocean != null:
		ocean.call("register_island_shore", get_parent(), ImageTexture.create_from_image(height_image), extent)
