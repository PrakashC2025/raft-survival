extends Node
## Four animals per island maximum; staged grounding, short AI ranges, saved respawn.
const ANIMAL := preload("res://scripts/survival_animal.gd")
var animals: Array[Node] = []
var player: Node3D
var _saved: Dictionary = {}
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
		if island.is_in_group("biome_island"):continue
		for index in range(4):
			if not is_instance_valid(island):
				break
			if not is_inside_tree() or not is_instance_valid(player) or player.get_world_3d() == null:
				return
			var from := (island as Node3D).global_position + Vector3(-3 + index * 2, 35, 2.5 + index % 2 * 2)
			var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 65, 1)
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or Vector3(hit["position"]).y <= 0.25:
				continue
			var body := ANIMAL.new() as CharacterBody3D
			body.species = ["Boar", "Crab", "Turtle", "Crab"][index]
			body.animal_id = str(island.name) + ":animal:" + str(index)
			body.name = body.species + "_" + str(index)
			get_tree().current_scene.add_child(body)
			body.global_position = Vector3(hit["position"]) + Vector3.UP * 0.08
			body.home = body.global_position
			if saved is Dictionary and saved.get(body.animal_id, null) is Dictionary:
				body.call("restore_state", saved[body.animal_id])
			animals.append(body)
			await get_tree().physics_frame
			if not is_inside_tree():
				return
func save_state() -> Dictionary:
	var result: Dictionary = _saved.duplicate(true)
	for animal in animals:
		if is_instance_valid(animal):
			result[str(animal.get("animal_id"))] = animal.call("save_state")
	return result
