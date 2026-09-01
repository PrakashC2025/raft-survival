extends MeshInstance3D
class_name Ocean

@export var wave_height := 0.4
@export var wave_speed := 1.2
var _time := 0.0

func _ready() -> void:
	# Groups work across scene-file boundaries (unlike %UniqueName), so any
	# runtime-instanced node (debris, etc.) can always find this node.
	add_to_group("ocean")

func _process(delta: float) -> void:
	_time += delta

# Returns the exact water surface height (world Y) at any given world position.
func get_height(world_pos: Vector3) -> float:
	var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
		+ sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
		+ 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
	return global_position.y + h * wave_height * 0.33
