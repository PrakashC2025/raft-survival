extends Node3D

# Continuous ocean-current debris stream.
# Debris flows from UPSTREAM → past player → DOWNSTREAM → despawn.

@export var debris_scene: PackedScene
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var spawn_width: float = 60.0
@export var upstream_distance: float = 80.0
@export var downstream_distance: float = 120.0
@export var max_debris: int = 80
@export var prewarm_count: int = 35

# Staggered timing — 1 piece every 0.2–0.5 seconds
@export var spawn_interval_min: float = 0.2
@export var spawn_interval_max: float = 0.5

var _timer: float = 0.0
var _next_interval: float = 0.0
var _active: Array = []
var player: Node3D
var _direction: Vector3 = Vector3.ZERO
var _side: Vector3 = Vector3.ZERO

const ITEM_POOL := [
	"Wood", "Wood", "Wood", "Wood", "Wood", "Wood",
	"Rope", "Rope", "Rope",
	"Plastic", "Plastic",
	"Barrel",
	"Stone", "Stone",
	"Metal",
]

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	_direction = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	if _direction.length() < 0.001:
		_direction = Vector3(0, 0, 1)
	_side = Vector3(-_direction.z, 0.0, _direction.x).normalized()
	_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
	_prewarm()


func _get_player() -> Node3D:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	return player


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_interval:
		_timer = 0.0
		_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
		_cleanup()
		if _active.size() < max_debris:
			_spawn_upstream()


# Fill the upstream corridor at startup — debris visible from frame 1.
func _prewarm() -> void:
	for i in prewarm_count:
		# Spread evenly from upstream to just past the player
		var dist := randf_range(-upstream_distance, downstream_distance * 0.5)
		_spawn_at(dist)


# New debris always enters from upstream.
func _spawn_upstream() -> void:
	_spawn_at(-randf_range(upstream_distance * 0.8, upstream_distance))


func _spawn_at(along_t: float) -> void:
	if not debris_scene:
		return

	var d = debris_scene.instantiate()

	var p := _get_player()
	var origin := p.global_position if p != null else Vector3.ZERO

	# Random lateral position + small along-current jitter
	var lateral := randf_range(-spawn_width * 0.5, spawn_width * 0.5)
	var jitter := randf_range(-5.0, 5.0)
	var spawn_point := origin + _direction * (along_t + jitter) + _side * lateral

	d.item_name = ITEM_POOL.pick_random()
	d.current_direction = _direction
	d.current_speed = current_speed * randf_range(0.7, 1.3)
	d.travel_start = spawn_point
	d.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))

	d.position = spawn_point
	d.position.y = 0.0

	add_child(d)
	_active.append(d)


func _cleanup() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var d = _active[i]
		if not is_instance_valid(d):
			_active.remove_at(i)
			continue
		if d.freeze:
			continue
		var travelled: float = (Vector3(d.global_position) - Vector3(d.travel_start)).dot(_direction)
		if travelled > downstream_distance and not d._is_fading_out:
			d.start_fade_out()
		if d.is_fade_done():
			d.queue_free()
			_active.remove_at(i)
