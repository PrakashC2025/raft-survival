extends AnimatableBody3D

@export var float_height: float = 0.6
@export var follow_speed: float = 4.0

var ocean: Ocean = null
var _markers: Array = []
var _extra_sample_points: Array[Node3D] = []

func _ready() -> void:
	add_to_group("build_surface")
	_markers = [
		get_node_or_null("F1"),
		get_node_or_null("F2"),
		get_node_or_null("F3"),
		get_node_or_null("F4"),
	]
	rotation = Vector3.ZERO

func _get_ocean() -> Ocean:
	if ocean == null or not is_instance_valid(ocean):
		ocean = get_tree().get_first_node_in_group("ocean")
	return ocean

# Called by player.gd after a piece is placed, passing one of the piece's
# own corner/center markers so the raft's buoyancy averaging expands to
# cover the growing structure.
func register_sample_point(marker: Node3D) -> void:
	if marker != null and not _extra_sample_points.has(marker):
		_extra_sample_points.append(marker)

# Called when a piece is removed (Fix support for X / remove_build).
func unregister_sample_point(marker: Node3D) -> void:
	_extra_sample_points.erase(marker)

func _physics_process(delta: float) -> void:
	var oc := _get_ocean()
	if oc == null:
		return

	var avg_height: float = 0.0
	var count: int = 0

	for m in _markers:
		if m != null and is_instance_valid(m):
			avg_height += float(oc.get_height(m.global_position))
			count += 1

	# Prune invalid refs lazily while summing (freed pieces, etc.)
	for i in range(_extra_sample_points.size() - 1, -1, -1):
		var m = _extra_sample_points[i]
		if not is_instance_valid(m):
			_extra_sample_points.remove_at(i)
			continue
		avg_height += float(oc.get_height(m.global_position))
		count += 1

	if count > 0:
		avg_height /= float(count)

	var target_y: float = avg_height + float_height
	global_position.y = lerpf(
		global_position.y, target_y,
		1.0 - exp(-follow_speed * delta)
	)
