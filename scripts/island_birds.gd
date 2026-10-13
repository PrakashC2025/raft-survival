extends Node3D
## Original CC0 gull GLB, wing animation and bounded huntable population.
const GULL: PackedScene = preload("res://models/coastal_gull.glb")
const PICKUP: PackedScene = preload("res://scenes/food_pickup.tscn")
@export_file("*.glb") var sketchfab_bird_model := ""
@export_range(1, 8, 1) var bird_count := 4
@export var orbit_radius := 10.0
@export var flight_height := 8.5
@export var follow_raft := false
var _raft: Node3D
var _time := 0.0
var _birds: Array[Dictionary] = []
var _destinations: Array[Vector3] = []
var FADE_START_DISTANCE := 80.0
var FADE_END_DISTANCE := 120.0

func _ready() -> void:
	_raft=get_tree().get_first_node_in_group("raft") as Node3D
	for island in get_tree().get_nodes_in_group("island"):
		if island is Node3D and (island as Node3D).global_position.distance_to(global_position) > 30:
			_destinations.append((island as Node3D).global_position)
	if _destinations.is_empty(): _destinations.append(global_position+Vector3(180,0,-130))
	var packed := GULL
	if not sketchfab_bird_model.is_empty() and ResourceLoader.exists(sketchfab_bird_model):
		packed = load(sketchfab_bird_model) as PackedScene
	for i in range(bird_count):
		var bird := Node3D.new()
		bird.name = "IslandBird_%02d" % i
		bird.add_to_group("no_collision")
		add_child(bird)
		var model := packed.instantiate() as Node3D
		bird.add_child(model)
		for candidate in model.find_children("*", "MeshInstance3D", true, false):
			(candidate as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var target := Area3D.new()
		target.collision_layer = 2
		target.collision_mask = 0
		target.add_to_group("huntable_bird")
		target.set_meta("flock", self)
		target.set_meta("bird_index", i)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.38
		shape.shape = sphere
		target.add_child(shape)
		bird.add_child(target)
		_birds.append({"root": bird, "target": target, "left": model.find_child("WingLeft", true, false),
			"right": model.find_child("WingRight", true, false), "phase": TAU * float(i) / float(maxi(bird_count, 1)),
			"radius": orbit_radius + i % 2 * 2.0, "speed": 0.10 + i % 3 * 0.018,
			"height": flight_height + i % 2 * 1.2, "state": "flying", "cooldown": 0.0, "fall_speed": 0.0,
			"origin": global_position, "travel": 0.0})

func hit_bird(index: int) -> bool:
	if index < 0 or index >= _birds.size() or _birds[index]["state"] != "flying":
		return false
	_birds[index]["state"] = "falling"
	(_birds[index]["target"] as Area3D).set_deferred("collision_layer", 0)
	return true

func _physics_process(delta: float) -> void:
	_time += delta
	for data in _birds:
		var bird := data["root"] as Node3D
		if data["state"] == "resting":
			data["cooldown"] = float(data["cooldown"]) - delta
			if float(data["cooldown"]) <= 0.0:
				data["state"] = "flying"
				bird.visible = true
				(data["target"] as Area3D).collision_layer = 2
			continue
		if data["state"] == "falling":
			data["fall_speed"] = float(data["fall_speed"]) + 9.8 * delta
			var before := bird.global_position
			var after := before + Vector3.DOWN * float(data["fall_speed"]) * delta
			var ray := PhysicsRayQueryParameters3D.create(before, after + Vector3.DOWN * 0.12, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			bird.global_position = after
			bird.rotation.z += delta * 2.0
			if not hit.is_empty() or after.y <= 0.1:
				var at: Vector3 = hit["position"] if not hit.is_empty() else Vector3(after.x, 0.15, after.z)
				var pickup := PICKUP.instantiate() as Node3D
				pickup.set("item_name", "Raw Bird")
				pickup.set("amount", 1)
				get_tree().current_scene.add_child(pickup)
				pickup.global_position = at + Vector3.UP * 0.15
				bird.visible = false
				data["state"] = "resting"
				data["cooldown"] = randf_range(100.0, 180.0)
				data["fall_speed"] = 0.0
			continue
		var phase := _time * float(data["speed"]) + float(data["phase"])
		var pos := flight_position(data,_time)
		# A 3D node has no modulate property. Distance culling belongs on meshes;
		# flying birds must reappear when their route returns to the island.
		bird.visible=true
		bird.global_position = pos
		var tangent := (flight_position(data,_time+0.25)-bird.global_position).normalized()
		bird.rotation = Vector3(0.0, atan2(-tangent.x, -tangent.z), sin(phase * 2.0) * 0.10)
		var flap := sin(_time * 6.4 + float(data["phase"])) * 0.42
		if data["left"] != null:
			(data["left"] as Node3D).rotation.z = flap
		if data["right"] != null:
			(data["right"] as Node3D).rotation.z = -flap

func flight_position(data: Dictionary, at_time: float) -> Vector3:
	# Feed near shore, travel across water, then return; each bird has its own phase.
	if follow_raft and is_instance_valid(_raft):
		var sea_angle:=at_time*.14+float(data.phase)
		var centre:=_raft.global_position
		return centre+Vector3(cos(sea_angle)*float(data.radius),float(data.height)+sin(sea_angle*1.4)*1.2,sin(sea_angle)*float(data.radius))
	var cycle := fposmod(at_time/180.0+float(data["phase"])/TAU,1.0)
	var destination := _destinations[int(float(data["phase"])/TAU*bird_count)%_destinations.size()]
	var origin := global_position
	var center := origin
	var radius := float(data["radius"])
	var angle := at_time*0.10+float(data["phase"])
	if cycle >= 0.2 and cycle < 0.55:
		center = origin.lerp(destination,smoothstep(0.2,0.55,cycle))
	elif cycle >= 0.55 and cycle < 0.75:
		center = destination
	elif cycle >= 0.75:
		center = destination.lerp(origin,smoothstep(0.75,1.0,cycle))
	return Vector3(center.x+cos(angle)*radius,maxf(center.y,0)+float(data["height"])+sin(angle*2)*0.48,center.z+sin(angle)*radius)
