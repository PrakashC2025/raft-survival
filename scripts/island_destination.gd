extends Node3D
## Reusable remote island dressing and resource respawn seed.

@export var map_label := "Island"
@export var beacon_color := Color(0.28, 0.86, 1.0)
@export var pickup_seed := 8421
@export_range(1, 12, 1) var pickup_count := 6

const PICKUP_SCENE: PackedScene = preload("res://scenes/food_pickup.tscn")
const PICKUP_POINTS := [
	Vector2(-5.0, -2.0), Vector2(4.5, -3.5), Vector2(-2.0, 5.0),
	Vector2(5.2, 3.7), Vector2(0.0, -6.3), Vector2(-6.0, 3.3),
	Vector2(2.5, 6.0), Vector2(6.3, -0.5), Vector2(-3.2, -5.6),
	Vector2(0.5, 2.8), Vector2(3.5, 0.8), Vector2(-4.0, 1.8),
]
const PICKUP_TYPES := ["Coconut", "Banana", "Coconut", "Stone", "Banana", "Coconut"]


func _enter_tree() -> void:
	preload("res://scripts/island_layout.gd").apply(self,Inventory.loaded_meta)
	var beacon := get_node_or_null("IslandBeacon")
	if beacon != null:
		beacon.set("beacon_color", beacon_color)


func _ready() -> void:
	var landscape := preload("res://scripts/island_landscape.gd").new()
	landscape.name = "IslandLandscape"
	add_child(landscape)
	add_to_group("island")
	set_meta("map_label", map_label)
	var grove := preload("res://scripts/island_grove.gd").new() as Node3D
	grove.name = "CoastalGrove"
	add_child(grove)
	call_deferred("_spawn_pickups")


func _spawn_pickups() -> void:
	# Wait for the island's terrain collider instead of guessing a fixed delay;
	# imported islands can take different numbers of physics frames to cook, and
	# the home island's IslandSetup lives outside this node.
	await _wait_for_island_collider()
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = pickup_seed
	var count := mini(pickup_count, PICKUP_POINTS.size())
	for i in range(count):
		var pickup_id := "%s:%d:%02d" % [name, pickup_seed, i]
		if Inventory.has_collected_island_pickup(pickup_id):
			continue
		var point: Vector2 = PICKUP_POINTS[i]
		var from := to_global(Vector3(point.x, 9.0, point.y))
		var to := to_global(Vector3(point.x, -16.0, point.y))
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var pickup := PICKUP_SCENE.instantiate() as Node3D
		if pickup == null:
			continue
		pickup.name = "IslandPickup_%02d" % i
		pickup.set("item_name", PICKUP_TYPES[i % PICKUP_TYPES.size()])
		pickup.set("pickup_id", pickup_id)
		add_child(pickup)
		pickup.global_position = Vector3(hit["position"]) + Vector3.UP * 0.38
		pickup.rotation.y = rng.randf_range(0.0, TAU)

	# New crop caches have separate IDs so existing pickup progress stays valid.
	var medkit_id:="%s:%d:medkit"%[name,pickup_seed]
	if not Inventory.has_collected_island_pickup(medkit_id):
		var at:=to_global(Vector3(2.5,10,-1.5))
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at,at+Vector3.DOWN*28,1))
		if not hit.is_empty():
			var medkit:=PICKUP_SCENE.instantiate() as Node3D
			medkit.name="MedicalSupplyCache";medkit.item_name="Medkit";medkit.amount=1;medkit.pickup_id=medkit_id
			add_child(medkit);medkit.global_position=Vector3(hit.position)+Vector3.UP*.3
	if map_label == "Home Isle":
		for crop_index in range(3):
			var crop: String = ["Carrot", "Tomato", "Onion"][crop_index]
			var cache_id := "%s:%d:crop:%s" % [name, pickup_seed, crop]
			if Inventory.has_collected_island_pickup(cache_id):
				continue
			var point: Vector2 = PICKUP_POINTS[9 + crop_index] + Vector2(0.45, 0.45)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(to_global(Vector3(point.x, 9, point.y)), to_global(Vector3(point.x, -16, point.y)), 1))
			if hit.is_empty():
				continue
			var cache := PICKUP_SCENE.instantiate() as Node3D
			cache.name = "CropSeedCache_" + crop
			cache.set("item_name", crop + " Seed")
			cache.set("amount", 4)
			cache.set("pickup_id", cache_id)
			add_child(cache)
			cache.global_position = Vector3(hit["position"]) + Vector3.UP * 0.38


## Blocks until island_setup.gd has finished cooking this island's collider, so
## the spawn raycasts have ground to hit.
func _wait_for_island_collider() -> void:
	for _frame in range(360):
		if not is_inside_tree():
			return
		var setup := get_node_or_null("IslandSetup")
		if setup == null:
			var sibling := get_node_or_null("../IslandSetup")
			if sibling != null and sibling.get_node_or_null(sibling.get("island_root")) == self:
				setup = sibling
		if setup != null:
			if setup.get("setup_complete") == true:
				return
		else:
			# Fallback only for islands without a setup controller. Mountain and
			# palm colliders do not prove that the terrain is ready for pickups.
			if find_children("*", "StaticBody3D", true, false).size() > 0:
				return
		await get_tree().physics_frame
