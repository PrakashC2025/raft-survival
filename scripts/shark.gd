extends CharacterBody3D
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")
## Lightweight low-poly ocean predator. Sharks stalk swimmers, bite at close
## range, and can be repelled with the crafted spear.

@export var max_health := 70.0
@export var chase_speed := 4.1
@export var patrol_speed := 1.7
@export var detect_range := 42.0
@export var bite_range := 2.6
@export var bite_damage := 12.0

var health := 70.0
var _ocean: Ocean = null
var _home := Vector3.ZERO
var _time := 0.0
var _bite_timer := 0.0
var _body_material: ShaderMaterial
var _was_flashing := false
var _tail_fin: Node3D
var _hit_flash := 0.0

const FISH_PICKUP_SCENE: PackedScene = preload("res://scenes/food_pickup.tscn")


func _ready() -> void:
	add_to_group("shark")
	health = max_health
	_home = global_position
	_ocean = get_tree().get_first_node_in_group("ocean") as Ocean
	_build_visual()


func _physics_process(delta: float) -> void:
	_time += delta
	_bite_timer = maxf(0.0, _bite_timer - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	var flashing := _hit_flash > 0.0
	if _body_material != null and flashing != _was_flashing:
		_body_material.set_shader_parameter("base_color", Color(0.9, 0.48, 0.35) if flashing else Color(0.22, 0.31, 0.34))
		_was_flashing = flashing
	if _tail_fin != null:
		_tail_fin.rotation.y = sin(_time * 7.0) * 0.24

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var chasing := false
	var target := _home + Vector3(sin(_time * 0.17) * 14.0, 0.0, cos(_time * 0.13) * 14.0)
	var speed := patrol_speed
	if player != null and player.get("is_swimming") == true:
		var distance := global_position.distance_to(player.global_position)
		if distance < detect_range:
			target = player.global_position
			speed = chase_speed
			chasing = true
			if distance <= bite_range and _bite_timer <= 0.0:
				_bite_player(player)
				_bite_timer = 1.8

	var flat_to_target := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var direction := flat_to_target.normalized() if flat_to_target.length_squared() > 0.04 else Vector3.ZERO
	var target_y := -0.45 + sin(_time * 1.4 + _home.x) * 0.22
	if _ocean != null:
		target_y = float(_ocean.get_height(global_position)) - 0.52 + sin(_time * 1.4 + _home.x) * 0.18
	var vertical := clampf((target_y - global_position.y) * 1.8, -1.2, 1.2)
	velocity = Vector3(direction.x * speed, vertical, direction.z * speed)
	move_and_slide()
	if direction.length_squared() > 0.01:
		var facing := global_position + direction
		look_at(facing, Vector3.UP)
	# A briefly startled shark backs away after taking a spear hit.
	if not chasing and _hit_flash > 0.0:
		global_position += Vector3(-direction.x, 0.0, -direction.z) * delta * 0.8


func take_damage(amount: float, attacker: Node = null) -> void:
	if amount <= 0.0 or not is_inside_tree():
		return
	health = maxf(0.0, health - amount)
	_hit_flash = 0.22
	if health > 0.0:
		return
	if attacker != null and is_instance_valid(attacker):
		var overflow := Inventory.add("Fish", 1)
		if overflow > 0:
			_drop_fish()
		if attacker.has_method("_hud_toast"):
			attacker.call("_hud_toast", "SHARK DEFEATED  •  FISH DROPPED" if overflow > 0 else "SHARK DEFEATED  •  FISH +1")
	queue_free()


func _drop_fish() -> void:
	var drop := FISH_PICKUP_SCENE.instantiate() as Node3D
	if drop == null:
		return
	drop.set("item_name", "Fish")
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		drop.free()
		return
	scene_root.add_child(drop)
	var water_y := -0.45
	if _ocean != null:
		water_y = float(_ocean.call("get_height", global_position))
	drop.global_position = Vector3(global_position.x, water_y + 0.2, global_position.z)


func _bite_player(player: Node3D) -> void:
	if player.has_method("take_shark_damage"):
		player.call("take_shark_damage", bite_damage)
	else:
		Stats.change_health(-bite_damage)


func _build_visual() -> void:
	var visual := Node3D.new()
	visual.name = "SharkVisual"
	add_child(visual)
	# A hit tint belongs to this shark alone, not every cached body material.
	_body_material = OBJECT_MATERIALS.make(OBJECT_MATERIALS.Kind.FOOD, Color(0.22, 0.31, 0.34), 0.36).duplicate() as ShaderMaterial
	var belly_material := _material(Color(0.76, 0.81, 0.81), 0.64)
	var eye_material := _material(Color(0.018, 0.026, 0.035), 0.18)

	var body := SphereMesh.new()
	body.radius = 0.78
	body.height = 2.45
	body.radial_segments = 20
	body.rings = 10
	_add_mesh(visual, "Body", body, _body_material, Vector3(0.0, 0.0, 0.0), Vector3(0.58, 0.48, 1.55))
	var belly := SphereMesh.new()
	belly.radius = 0.67
	belly.height = 2.2
	belly.radial_segments = 10
	belly.rings = 4
	_add_mesh(visual, "Belly", belly, belly_material, Vector3(0.0, -0.22, 0.02), Vector3(0.48, 0.19, 1.28))

	var fin := CylinderMesh.new()
	fin.top_radius = 0.015
	fin.bottom_radius = 0.33
	fin.height = 0.83
	fin.radial_segments = 5
	fin.rings = 1
	_add_mesh(visual, "DorsalFin", fin, _body_material, Vector3(0.0, 0.53, 0.05), Vector3.ONE)
	var rear_fin := CylinderMesh.new()
	rear_fin.top_radius = 0.015
	rear_fin.bottom_radius = 0.28
	rear_fin.height = 0.82
	rear_fin.radial_segments = 5
	rear_fin.rings = 1
	_tail_fin = Node3D.new()
	_tail_fin.name = "TailFin"
	_tail_fin.position = Vector3(0.0, 0.0, 1.65)
	visual.add_child(_tail_fin)
	_add_mesh(_tail_fin, "UpperTail", rear_fin, _body_material, Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.74, 0.68))
	_add_mesh(_tail_fin, "LowerTail", rear_fin, _body_material,
			Vector3(0.0, -0.28, 0.0), Vector3(1.0, 0.62, 0.65), Vector3(PI, 0.0, 0.0))

	var pectoral := CylinderMesh.new()
	pectoral.top_radius = 0.01
	pectoral.bottom_radius = 0.23
	pectoral.height = 0.92
	pectoral.radial_segments = 4
	pectoral.rings = 1
	_add_mesh(visual, "LeftFin", pectoral, _body_material, Vector3(-0.43, -0.2, 0.24), Vector3(0.8, 0.48, 1.0), Vector3(0.0, 0.0, -1.0))
	_add_mesh(visual, "RightFin", pectoral, _body_material, Vector3(0.43, -0.2, 0.24), Vector3(0.8, 0.48, 1.0), Vector3(0.0, 0.0, 1.0))

	var eye := SphereMesh.new()
	eye.radius = 0.075
	eye.height = 0.15
	eye.radial_segments = 8
	eye.rings = 4
	_add_mesh(visual, "LeftEye", eye, eye_material, Vector3(-0.29, 0.12, -0.64), Vector3.ONE)
	_add_mesh(visual, "RightEye", eye, eye_material, Vector3(0.29, 0.12, -0.64), Vector3.ONE)


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material,
		at: Vector3, mesh_scale: Vector3, mesh_rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = mesh_scale
	instance.rotation = mesh_rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
