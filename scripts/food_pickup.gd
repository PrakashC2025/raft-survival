extends StaticBody3D
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")
const RESOURCE_VISUAL := preload("res://scripts/resource_visual.gd")
## Fixed world pickups share the debris group so the existing raycast and
## inventory flow can collect island items and overflow drops anywhere.

const MODEL_PATHS := {
	"Fish": "res://models/coastal_fish.glb",
	"Cooked Fish": "res://models/coastal_fish.glb",
	"Raw Bird": "res://models/coastal_gull.glb",
	"Roast Bird": "res://models/coastal_gull.glb",
	"Coconut": "res://models/kenney_coconut.glb",
	"Banana": "res://models/kenney_banana.glb",
	"Stone": "res://models/kenney_rock_small.glb",
	"Wood": "res://models/kenney_log.glb",
}
const TARGET_SIZES := {"Coconut": 0.42, "Banana": 0.48, "Stone": 0.46, "Wood": 0.72}

@export var item_name := "Coconut"
@export var amount := 1
@export var pickup_id := ""

var collected := false
var _visual: Node3D = null
var _amount_label: Label3D = null
var _bob_time := 0.0
var _base_y := 0.0


func _ready() -> void:
	add_to_group("debris")
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "PickupCollision"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	shape.position.y = 0.28
	add_child(shape)
	amount = maxi(1, amount)
	_visual = _make_visual()
	if _visual != null:
		OBJECT_MATERIALS.apply_model(_visual, OBJECT_MATERIALS.kind_for_item(item_name))
		add_child(_visual)
		_base_y = _visual.position.y
	_update_amount_label()


func set_pickup_amount(value: int) -> void:
	amount = maxi(1, value)
	_update_amount_label()


func _update_amount_label() -> void:
	if amount <= 1:
		if _amount_label != null and is_instance_valid(_amount_label):
			_amount_label.queue_free()
		_amount_label = null
		return
	if _amount_label == null or not is_instance_valid(_amount_label):
		_amount_label = Label3D.new()
		_amount_label.name = "AmountLabel"
		_amount_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_amount_label.position = Vector3(0.0, 0.62, 0.0)
		_amount_label.pixel_size = 0.005
		_amount_label.font_size = 42
		_amount_label.outline_size = 6
		_amount_label.modulate = Color(1.0, 0.96, 0.82)
		add_child(_amount_label)
	_amount_label.text = str(amount)


func _process(delta: float) -> void:
	if _visual == null or collected:
		return
	_bob_time += delta
	_visual.position.y = _base_y + sin(_bob_time * 2.2) * 0.035
	_visual.rotation.y += delta * 0.45


func get_pickup_id() -> String:
	return pickup_id


func _make_visual() -> Node3D:
	if not MODEL_PATHS.has(item_name):
		return _make_generic_visual()
	var path: String = str(MODEL_PATHS[item_name])
	var packed := load(path) as PackedScene
	if packed == null:
		return _make_generic_visual()
	var model := packed.instantiate() as Node3D
	if model == null:
		return _make_generic_visual()
	model.name = "PickupModel"
	var bounds := _local_bounds(model)
	var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if largest <= 0.001:
		model.queue_free()
		return _make_generic_visual()
	var scale_to_fit := float(TARGET_SIZES.get(item_name, 0.45)) / largest
	model.scale = Vector3.ONE * scale_to_fit
	model.position = -bounds.get_center() * scale_to_fit
	return model


func _make_generic_visual() -> Node3D:
	if item_name in ["Rope", "Plastic", "Metal"] or item_name.ends_with(" Seed"):
		return RESOURCE_VISUAL.create(item_name)
	var root := Node3D.new()
	root.name = "GenericPickupVisual"
	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.78
	var mesh: Mesh
	var dimensions := Vector3.ONE
	match item_name:
		"Tomato", "Carrot", "Baked Potato", "Potato":
			var potato := SphereMesh.new()
			potato.radius = 0.19
			potato.height = 0.32
			potato.radial_segments = 10
			potato.rings = 5
			mesh = potato
			dimensions = Vector3(0.9, 0.7, 1.25)
			material.albedo_color = Color(0.48, 0.3, 0.16)
			if item_name == "Tomato":
				material.albedo_color = Color(0.67, 0.07, 0.025)
				dimensions = Vector3.ONE
			elif item_name == "Carrot":
				material.albedo_color = Color(0.8, 0.3, 0.04)
				dimensions = Vector3(0.35, 1.2, 0.35)
		"Rope":
			var rope := CylinderMesh.new()
			rope.top_radius = 0.12
			rope.bottom_radius = 0.12
			rope.height = 0.1
			rope.radial_segments = 10
			mesh = rope
			material.albedo_color = Color(0.68, 0.52, 0.3)
		"Plastic":
			var plastic := BoxMesh.new()
			plastic.size = Vector3(0.32, 0.38, 0.18)
			mesh = plastic
			material.albedo_color = Color(0.2, 0.56, 0.76)
		"Metal":
			var metal := BoxMesh.new()
			metal.size = Vector3(0.3, 0.26, 0.3)
			mesh = metal
			material.albedo_color = Color(0.65, 0.69, 0.72)
			material.metallic = 0.72
		_:
			var fallback := BoxMesh.new()
			fallback.size = Vector3(0.3, 0.22, 0.3)
			mesh = fallback
			material.albedo_color = Color(0.72, 0.56, 0.34)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.scale = dimensions
	mesh_instance.position.y = 0.14
	root.add_child(mesh_instance)
	return root


func _make_fish_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "FishVisual"
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.55, 0.7, 0.77)
	silver.roughness = 0.38
	var belly_material := StandardMaterial3D.new()
	belly_material.albedo_color = Color(0.82, 0.85, 0.81)
	belly_material.roughness = 0.62
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.15
	body_mesh.height = 0.32
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.scale = Vector3(0.76, 0.72, 1.35)
	body.position = Vector3(0.0, 0.11, 0.0)
	body.material_override = silver
	root.add_child(body)
	# Godot has no ConeMesh class — a cone is a CylinderMesh whose top radius
	# is (almost) zero. Keep the taper explicit so the tail reads as a fin.
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.01
	tail_mesh.bottom_radius = 0.105
	tail_mesh.height = 0.2
	tail_mesh.radial_segments = 4
	var tail := MeshInstance3D.new()
	tail.name = "Tail"
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, 0.11, 0.2)
	tail.rotation.x = PI * 0.5
	tail.material_override = silver
	root.add_child(tail)
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.018
	eye_mesh.height = 0.036
	eye_mesh.radial_segments = 6
	eye_mesh.rings = 3
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(0.025, 0.04, 0.05)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.085, 0.13, -0.095)
		eye.material_override = eye_material
		root.add_child(eye)
	var belly := MeshInstance3D.new()
	belly.mesh = body_mesh
	belly.scale = Vector3(0.63, 0.34, 1.14)
	belly.position = Vector3(0.0, 0.045, 0.0)
	belly.material_override = belly_material
	root.add_child(belly)
	return root


func _local_bounds(root: Node3D) -> AABB:
	var found := false
	var low := Vector3.ZERO
	var high := Vector3.ZERO
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mi := candidate as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.transform * mi.get_aabb()
		if not found:
			low = box.position
			high = box.position + box.size
			found = true
		else:
			low = low.min(box.position)
			high = high.max(box.position + box.size)
	if not found:
		return AABB()
	return AABB(low, high - low)
