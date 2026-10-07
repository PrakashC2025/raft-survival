extends StaticBody3D
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

func _ready() -> void:
	var timber := preload("res://scripts/construction_visual.gd")
	for part in [$FrameLeft,$FrameRight,$FrameTop]:
		part.mesh = timber.rounded_timber(part.mesh.size)
	$LeafPivot/Leaf.mesh = timber.panel(Vector3(1.4,2.15,0.10),true)
	for height in [-0.70,0.70]:
		var brace := MeshInstance3D.new()
		brace.mesh = timber.rounded_timber(Vector3(1.4,0.10,0.10),1)
		brace.position = Vector3(0.7,height,0.105)
		_leaf_pivot.add_child(brace)
	var diagonal := MeshInstance3D.new()
	diagonal.mesh = timber.rounded_timber(Vector3(1.95,0.10,0.08),1)
	diagonal.position = Vector3(0.7,0,0.15)
	diagonal.rotation.z = 0.79
	_leaf_pivot.add_child(diagonal)
	for height in [-0.70,0.70]:
		var binding := MeshInstance3D.new()
		binding.name = "DoorHempBinding"
		binding.mesh = timber.rope_loop(Vector2(0.71,0.065),1)
		binding.position = Vector3(0.7,height,0.03)
		_leaf_pivot.add_child(binding)

func save_survival_state() -> Dictionary:
	return {"open":is_open}

func restore_survival_state(data: Dictionary) -> void:
	is_open = bool(data.get("open",false))
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0
	if _leaf_pivot != null: _leaf_pivot.rotation.y = _target_rotation

func toggle() -> void:
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0
	_swinging = true
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_queue_save"): player.call("_queue_save")

func _physics_process(delta: float) -> void:
	if _swinging and _leaf_pivot != null:
		_leaf_pivot.rotation.y = lerp_angle(_leaf_pivot.rotation.y, _target_rotation, delta * swing_speed)
		if absf(_leaf_pivot.rotation.y - _target_rotation) < 0.01:
			_leaf_pivot.rotation.y = _target_rotation
			_swinging = false
