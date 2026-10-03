extends StaticBody3D
const SURFACES := preload("res://scripts/object_materials.gd")
var water := 0
var collected_seconds := 0.0
var _sample := 0.0
var _preview := false

func _ready() -> void:
	_preview = get_parent() != null and get_parent().name == "BuildPreviewRoot"
	add_to_group("build_surface")
	var wood_material := SURFACES.make(SURFACES.Kind.WOOD, Color(0.28, 0.19, 0.10), 0.92)
	var band_material := SURFACES.make(SURFACES.Kind.METAL, Color(0.22, 0.24, 0.23), 0.65, 0.7)
	# Open staves form a true hollow rain barrel, with a visible inner rim.
	var staves := MultiMeshInstance3D.new()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	var shape := BoxMesh.new()
	shape.size = Vector3(0.074, 0.7, 0.04)
	batch.mesh = shape
	batch.instance_count = 24
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		batch.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle) * 0.29, 0, cos(angle) * 0.29)))
	staves.multimesh = batch
	staves.material_override = wood_material
	add_child(staves)
	for height in [-0.24, 0.24]:
		var band := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.29
		ring.outer_radius = 0.325
		ring.rings = 32
		ring.ring_segments = 6
		band.mesh = ring
		band.material_override = band_material
		band.position.y = height
		add_child(band)
	var surface := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.29
	disk.bottom_radius = 0.29
	disk.height = 0.012
	disk.radial_segments = 24
	surface.mesh = disk
	surface.position.y = 0.29
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.06, 0.23, 0.28)
	water_mat.roughness = 0.22
	water_mat.metallic = 0.15
	surface.material_override = water_mat
	add_child(surface)

func _process(delta: float) -> void:
	if _preview or water >= 5:
		return
	_sample += delta
	if _sample < 1.0:
		return
	var step := _sample
	_sample = 0.0
	var rain := get_tree().get_first_node_in_group("rain_system")
	if rain == null or not rain.call("is_raining"):
		return
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8, 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	collected_seconds += step
	if collected_seconds >= 20.0:
		water = mini(5, water + 1)
		collected_seconds -= 20.0

func interact_survival(player: Node) -> void:
	if water <= 0:
		player.call("_hud_toast", "COLLECTOR EMPTY · LEAVE IT OUT IN RAIN")
	elif Inventory.add("Water", 1) == 0:
		water -= 1
		player.call("_hud_toast", "FRESH WATER COLLECTED · DRINK OR WATER CROPS")
		player.call("_queue_save")

func save_survival_state() -> Dictionary:
	return {"water": water, "seconds": collected_seconds}

func restore_survival_state(data: Dictionary) -> void:
	water = clampi(int(data.get("water", 0)), 0, 5)
	collected_seconds = clampf(float(data.get("seconds", 0)), 0, 20)
