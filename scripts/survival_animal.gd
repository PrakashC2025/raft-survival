extends CharacterBody3D
const SURFACES := preload("res://scripts/object_materials.gd")
const PICKUP := preload("res://scenes/food_pickup.tscn")
const MODELS := {"Boar": "res://models/wild_boar.glb", "Crab": "res://models/shore_crab.glb", "Turtle": "res://models/sea_turtle.glb"}
var species := "Crab"
var animal_id := ""
var home := Vector3.ZERO
var health := 30.0
var respawn := 0.0
var alarm := 0.0
var _bite := 0.0
var _time := 0.0
var _sample := 0.0
var _legs: Array[Node] = []
var _model: Node3D
var _player: Node3D
func _ready() -> void:
	add_to_group("huntable_animal")
	collision_layer = 2
	collision_mask = 1
	health = 60 if species == "Boar" else 30
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27 if species == "Boar" else (0.25 if species == "Turtle" else 0.15)
	shape.height = 1.0 if species == "Boar" else shape.radius * 2
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_model = (load(MODELS[species]) as PackedScene).instantiate() as Node3D
	add_child(_model)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(node as MeshInstance3D).visibility_range_end = 65
	_legs = _model.find_children("Leg_*", "Node3D", true, false)
	_player = get_tree().get_first_node_in_group("player") as Node3D

func _physics_process(delta: float) -> void:
	_time += delta
	_bite = maxf(0, _bite - delta)
	alarm = maxf(0, alarm - delta)
	if respawn > 0:
		respawn = maxf(0, respawn - delta)
		if respawn <= 0:
			health = 60 if species == "Boar" else 30
			visible = true
			collision_layer = 2
			global_position = home
		return
	if _player == null:
		return
	var distance := global_position.distance_squared_to(_player.global_position)
	if distance > 4225:
		return
	velocity.y = maxf(-3.0, velocity.y - 9.8 * delta)
	move_and_slide()
	for index in range(_legs.size()):
		(_legs[index] as Node3D).rotation.x = sin(_time * velocity.length() * 8 + index * PI) * 0.22
	_sample += delta
	if _sample < 0.15:
		return
	var step := minf(_sample, 0.3)
	_sample = 0
	var rain := get_tree().get_first_node_in_group("rain_system")
	if rain != null and rain.call("is_raining") and alarm <= 0:
		velocity.x = 0
		velocity.z = 0
		return # shelter in storms, rather than endlessly roaming
	var direction := home + Vector3(sin(_time*0.13+home.x)*3,0,cos(_time*0.12)*3) - global_position
	var speed := 0.7 if species == "Boar" else (0.20 if species == "Turtle" else 0.45)
	if distance < 36:
		direction = global_position - _player.global_position
		speed *= 2
	if species == "Boar" and alarm > 0 and distance < 196:
		direction = _player.global_position - global_position
		speed = 2.6
		for fire in get_tree().get_nodes_in_group("campfire"):
			if fire.burning and fire.global_position.distance_squared_to(global_position) < 36:
				direction = global_position - fire.global_position
				break
		if distance < 2.8 and _bite <= 0:
			Stats.change_health(-10)
			_bite = 2
			_player.call("_hud_toast", "BOAR ATTACK · KEEP YOUR DISTANCE")
	direction.y = 0
	direction = direction.normalized()
	var next := global_position + direction * speed * step
	if Vector2(next.x-home.x,next.z-home.z).length() > 7:
		velocity.x = 0
		velocity.z = 0
		return
	var ground := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(next+Vector3.UP*2,next+Vector3.DOWN*3,1))
	if ground.is_empty() or Vector3(ground["position"]).y < 0.20:
		velocity.x = 0
		velocity.z = 0
		return
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y,atan2(-direction.x,-direction.z),step*4)

func take_damage(amount: float, _attacker: Node = null) -> void:
	if amount <= 0 or respawn > 0:
		return
	health = maxf(0, health-amount)
	alarm = 15
	if health <= 0:
		visible = false
		set_deferred("collision_layer",0)
		respawn = 240
		var drop := PICKUP.instantiate() as Node3D
		drop.set("item_name", "Raw Crab" if species == "Crab" else "Raw Meat")
		drop.set("amount",1 if species == "Crab" else 2)
		get_tree().current_scene.add_child(drop)
		drop.global_position = global_position + Vector3.UP*0.2
		var progress := get_tree().get_first_node_in_group("survival_progression")
		if progress != null:
			progress.call("record","hunt:"+species)

func save_state() -> Dictionary:
	return {"health": health,"respawn":respawn}
func restore_state(data: Dictionary) -> void:
	health = clampf(float(data.get("health",60 if species == "Boar" else 30)),0,60 if species == "Boar" else 30)
	respawn = clampf(float(data.get("respawn",0)),0,240)
	if health <= 0:
		respawn = maxf(respawn,1)
	visible = respawn <= 0
	collision_layer = 2 if visible else 0
