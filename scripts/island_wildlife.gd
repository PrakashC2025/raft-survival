extends Node
## Bounded island wildlife, with two boars and one amphibious shore crocodile.
const ANIMAL := preload("res://scripts/survival_animal.gd")
var animals: Array[Node] = []
var player: Node3D
var _saved: Dictionary = {}
var prepared:=false
func _ready() -> void:
	player = get_parent() as Node3D
	var stored: Variant = Inventory.loaded_meta.get("wildlife", {})
	if stored is Dictionary:
		_saved = stored.duplicate(true)
	call_deferred("_populate")
func _populate() -> void:
	for frame in range(360):
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var setup := get_tree().current_scene.get_node_or_null("IslandSetup")
		if setup != null and setup.get("setup_complete") == true:
			break
	var saved: Variant = _saved
	for island in get_tree().get_nodes_in_group("island"):
		if not is_instance_valid(island) or not island is Node3D:
			continue
		if island.is_in_group("biome_island"):
			if island.biome=="volcano":continue
			while is_instance_valid(island) and not island.prepared:
				await get_tree().physics_frame
				if not is_inside_tree():return
		for index in range(6):
			if not is_instance_valid(island):
				break
			if not is_inside_tree() or not is_instance_valid(player) or player.get_world_3d() == null:
				return
			if index==5 and island.get_meta("biome","")=="winter":continue
			var from := (island as Node3D).global_position + Vector3(-3 + index * 2, 35, 2.5 + index % 2 * 2)
			var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 65, 1)
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or Vector3(hit["position"]).y <= 0.25:
				continue
			var body := ANIMAL.new() as CharacterBody3D
			body.species = ["Boar", "Crab", "Turtle", "Crab","Boar","Crocodile"][index]
			body.animal_id = str(island.name) + ":animal:" + str(index)
			body.name = body.species + "_" + str(index)
			get_tree().current_scene.add_child(body)
			body.global_position = Vector3(hit["position"]) + Vector3.UP * 0.08
			body.home = body.global_position
			if index==5:
				# Pick an actual shoreline, keeping crocodiles out of deep open sea.
				for probe in 24:
					var point: Vector3=island.global_position+Vector3(cos(probe*2.4),0,sin(probe*2.4))*(8+float(probe%6)*6)
					var shore:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*40,point+Vector3.DOWN*4,1))
					if not shore.is_empty() and Vector3(shore.position).y<1.2 and Vector3(shore.position).y>-.5 and Vector3(shore.normal).y>.7:
						var space:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.95,.70,3.1);space.shape=shape
						space.transform=Transform3D(Basis.IDENTITY,Vector3(shore.position)+Vector3.UP*.44);space.collision_mask=1;space.exclude=[body.get_rid()]
						if not player.get_world_3d().direct_space_state.intersect_shape(space,1).is_empty():continue
						body.global_position=Vector3(shore.position)+Vector3.UP*.08;body.home=body.global_position;break
			if saved is Dictionary and saved.get(body.animal_id, null) is Dictionary:
				body.call("restore_state", saved[body.animal_id])
			animals.append(body)
			await get_tree().physics_frame
			if not is_inside_tree():
				return
	prepared=true
func save_state() -> Dictionary:
	var result: Dictionary = _saved.duplicate(true)
	for animal in animals:
		if is_instance_valid(animal):
			result[str(animal.get("animal_id"))] = animal.call("save_state")
	return result
