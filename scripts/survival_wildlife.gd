extends CharacterBody3D
## Original stylized wildlife with terrain collision, fleeing and predator attacks.
var kind := "Fish"
var home := Vector3.ZERO
var phase := 0.0
var health := 1
var harvested := false
var wings: Array[MeshInstance3D] = []
var attack_timer := 0.0
var flee_time := 0.0
var player: Node3D
var imported_model: Node3D
var distance_clock := 0.0
var nearby := true

func _part(size: Vector3, at: Vector3, color: Color, box := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	if box:
		var mesh := BoxMesh.new()
		mesh.size = size
		part.mesh = mesh
	else:
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 16
		mesh.rings = 8
		part.mesh = mesh
		part.scale = size
	part.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.65
	part.material_override = mat
	add_child(part)
	return part

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	add_to_group("wildlife")
	player = get_tree().get_first_node_in_group("player")
	health = 4 if kind == "Shark" else (3 if kind == "Boar" else 1)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6 if kind == "Boar" else (0.8 if kind == "Shark" else 0.4)
	shape.shape = sphere
	add_child(shape)
	var asset: String = {"Bird": "bird", "Fish": "fish", "Shark": "shark", "Boar": "boar"}[kind]
	var length: float = {"Bird": 1.2, "Fish": 0.75, "Shark": 2.8, "Boar": 1.5}[kind]
	imported_model = preload("res://scripts/mobile_assets.gd").make(asset, length)
	if imported_model != null:
		add_child(imported_model)
		preload("res://scripts/mobile_assets.gd").animate(imported_model, ["walk", "swim", "fly", "run", "idle"])
func _physics_process(delta: float) -> void:
	if harvested:
		return
	distance_clock -= delta
	if distance_clock <= 0.0 and is_instance_valid(player):
		distance_clock = 0.5
		nearby = global_position.distance_squared_to(player.global_position) < 10000.0
		visible = nearby
	if not nearby:
		return
	if imported_model != null and kind == "Bird":
		imported_model.rotation.z = sin(phase * 6.0) * 0.08
	attack_timer = maxf(0.0, attack_timer - delta)
	flee_time = maxf(0.0, flee_time - delta)
	phase += delta * 0.45
	var desired := home + Vector3(cos(phase) * 7.0, sin(phase * 2.0) * 0.4, sin(phase) * 7.0)
	var predator := kind == "Shark" or kind == "Boar"
	if is_instance_valid(player):
		var distance := global_position.distance_to(player.global_position)
		var can_attack: bool = predator and distance < 12.0 and ((kind == "Shark" and player.get("is_swimming")) or (kind == "Boar" and not player.get("is_swimming")))
		if can_attack:
			desired = player.global_position
			if distance < 1.8 and attack_timer == 0.0:
				Stats.change_health(-12.0 if kind == "Shark" else -8.0)
				attack_timer = 2.0
		elif distance < 5.0 or flee_time > 0.0:
			desired = global_position + (global_position - player.global_position).normalized() * 6.0
	var direction := (desired - global_position).normalized()
	if kind == "Boar":
		velocity.x = direction.x * 2.6
		velocity.z = direction.z * 2.6
		velocity.y -= 9.8 * delta
		if is_on_floor():
			velocity.y = 0.0
	else:
		velocity = direction * (4.0 if kind == "Bird" else 2.5)
		if kind != "Bird":
			var ocean := get_tree().get_first_node_in_group("ocean")
			if ocean != null:
				var ceiling: float = ocean.call("get_height", global_position)
				if global_position.y > ceiling - 0.7:
					velocity.y = -2.0
	move_and_slide()
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.1:
		look_at(global_position + flat, Vector3.UP)
	for limb in wings:
		if kind == "Bird":
			limb.rotation.z = sin(phase * 18.0) * 0.5 * signf(limb.position.x)
		elif kind == "Boar":
			limb.rotation.x = sin(phase * 16.0 + limb.position.z * 3.0) * 0.3

func hit() -> void:
	if harvested:
		return
	health -= 1
	flee_time = 5.0
	if health > 0:
		return
	var item := "Raw Meat" if kind == "Bird" or kind == "Boar" else "Raw Fish"
	if Inventory.add(item, 1) > 0:
		health = 1
		return
	harvested = true
	queue_free()


