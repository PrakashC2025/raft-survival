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
	var beacon := get_node_or_null("IslandBeacon")
	if beacon != null:
		beacon.set("beacon_color", beacon_color)


func _ready() -> void:
	add_to_group("island")
	set_meta("map_label", map_label)
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
	if map_label == "Home Isle":
		for crop_index in range(2):
			var crop: String = ["Carrot", "Tomato"][crop_index]
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
		if setup != null and setup.get("setup_complete") == true:
			return
		# Any StaticBody3D under this island means the trimesh / palm bodies
		# are already in place (island_setup.gd cooks the terrain first).
		if find_children("*", "StaticBody3D", true, false).size() > 0:
			return
		await get_tree().physics_frame
