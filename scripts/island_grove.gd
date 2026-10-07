extends Node3D
## Eight grounded trees per island; startup work is spread over frames.
const VISUAL := preload("res://scripts/coastal_tree_visual.gd")
const POINTS := [Vector2(3,-3),Vector2(5,-1),Vector2(-3,4),Vector2(-5,2),Vector2(1,5),Vector2(-4,-3),Vector2(6,4),Vector2(2,-5)]
var _clock := 0.0
var _away := 0.0
var _active := true
var _planted: Array[String] = []
func _ready() -> void:
	add_to_group("island_grove")
	call_deferred("_plant")
func _process(delta: float) -> void:
	_clock += delta
	if not _active: _away += delta
	if _clock < 0.5: return
	_clock = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null: return
	var near := player.global_position.distance_squared_to(global_position) < 85.0*85.0
	if near == _active: return
	_active = near
	for tree in get_children():
		if not tree.has_method("save_state"): continue
		if near and int(tree.get("_stage")) == 3: tree.call("_update_fruits",_away)
		tree.set_process(near)
	if near: _away = 0.0
func save_state() -> Dictionary:
	var state := {}
	for key in _planted:
		var tree := get_node_or_null(key)
		if tree == null:
			state[key] = {"removed":true}
		elif tree.has_method("save_state"):
			var record: Dictionary = tree.call("save_state")
			if not _active:
				for fruit in record.get("fruits",[]): fruit["e"] = float(fruit["e"])+_away
			state[key] = record
	return state
func _plant() -> void:
	var island := get_parent() as Node3D
	var setup := island.get_node_or_null("IslandSetup")
	if setup == null: setup = island.get_node_or_null("../IslandSetup")
	for frame in range(600):
		if setup != null and setup.get("setup_complete") == true: break
		await get_tree().physics_frame
		if not is_inside_tree(): return
	for index in range(POINTS.size()):
		var key := "Banana%d" % index if index < 2 else "Coconut%d" % index
		var groves: Dictionary = Inventory.loaded_meta.get("island_groves",{})
		var saved: Dictionary = groves.get(str(island.name),{})
		if index < 4 and saved.get(key,{}).get("removed",false):
			_planted.append(key)
			continue
		var point: Vector2 = POINTS[index]
		var from := island.to_global(Vector3(point.x,16,point.y))
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+Vector3.DOWN*40,1))
		if hit.is_empty() or Vector3(hit.position).y < 0.42:
			for step in range(1,7):
				var candidate := island.to_global(Vector3(point.x,0,point.y) * (1.0 - float(step) * 0.10))
				var dry_from := Vector3(candidate.x,26,candidate.z)
				var dry_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(dry_from,dry_from+Vector3.DOWN*54,1))
				if not dry_hit.is_empty() and Vector3(dry_hit.position).y >= 0.42:
					hit = dry_hit
					break
		if hit.is_empty(): continue
		var tree: Node3D
		if index < 4:
			tree = load("res://scripts/plant_instance.gd").new() as Node3D
			tree.set("plant_id","Banana" if index < 2 else "Coconut")
			tree.name = "Banana%d" % index if index < 2 else "Coconut%d" % index
		else:
			tree = VISUAL.create(1 if index%2 == 0 else 2)
		add_child(tree)
		tree.global_position = Vector3(hit.position)
		tree.rotation.y = float(index)*2.4
		if index < 4:
			_planted.append(str(tree.name))
			tree.call("restore_state",saved.get(str(tree.name),{"id":tree.get("plant_id"),"stage":3,"health":6,"timer":0.0}))
			tree.set_process(_active)
			for mesh in tree.find_children("*","MeshInstance3D",true,false):
				mesh.visibility_range_end = 120.0
		else:
			var body := StaticBody3D.new()
			var collider := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.18
			shape.height = 2.5
			collider.shape = shape
			collider.position.y = 1.25
			body.add_child(collider)
			tree.add_child(body)
		await get_tree().process_frame
		if not is_inside_tree(): return
