extends AnimatableBody3D
class_name Door
@export var open_angle: float = 90.0
@export var swing_speed: float = 4.0
var is_open: bool = false
var _target_rotation: float = 0.0
func toggle() -> void:
  is_open = !is_open
  _target_rotation = deg_to_rad(open_angle) if is_open else 0.0
func _physics_process(delta: float) -> void:
  rotation.y = lerp_angle(rotation.y, _target_rotation, delta * swing_speed)
