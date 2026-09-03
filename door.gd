extends AnimatableBody3D
class_name Door
@export var open_angle: float = 90.0
@export var swing_speed: float = 4.0
var is_open: bool = false
var _target_rotation: float = 0.0
var _swinging: bool = false

# Only the LEAF swings like a real door — the frame stays fixed. The leaf
# pivots on its hinge edge (LeafPivot is positioned at the hinge line), so
# rotating the pivot swings the leaf without moving the static frame.
@onready var _leaf_pivot: Node3D = $LeafPivot

func toggle() -> void:
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0
	_swinging = true

func _physics_process(delta: float) -> void:
	if _swinging and _leaf_pivot != null:
		_leaf_pivot.rotation.y = lerp_angle(_leaf_pivot.rotation.y, _target_rotation, delta * swing_speed)
		if absf(_leaf_pivot.rotation.y - _target_rotation) < 0.01:
			_leaf_pivot.rotation.y = _target_rotation
			_swinging = false