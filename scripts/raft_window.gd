extends StaticBody3D
## A rope-bound timber opening with a hinged wooden shutter, without glass.
## Existing window save records keep their open/closed state.
var is_open := false
var _swing: Tween
const TIMBER := preload("res://scripts/construction_visual.gd")
@onready var _hinge: Node3D = $Hinge

func _ready() -> void:
	for part in find_children("*", "MeshInstance3D", true, false):
		if part.name == "Latch": continue
		if part.mesh is BoxMesh:
			part.mesh = TIMBER.rounded_timber(part.mesh.size)
	$Bottom.mesh = TIMBER.panel(Vector3(2,0.5,0.22),true,0.0,5)
	var shutter := MeshInstance3D.new()
	shutter.name = "JoinedWoodenShutter"
	shutter.mesh = TIMBER.panel(Vector3(1.56,1.66,0.10),true)
	shutter.position.x = 0.78
	$Hinge/Sash.add_child(shutter)
	for height in [-0.52,0.52]:
		var binding := MeshInstance3D.new()
		binding.mesh = TIMBER.rope_loop(Vector2(0.79,0.065),1)
		binding.position = Vector3(0.78,height,0)
		$Hinge/Sash.add_child(binding)

func toggle() -> void:
	is_open = not is_open
	if _swing != null:
		_swing.kill()
	_swing = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing.tween_property(_hinge, "rotation:y", deg_to_rad(-85.0) if is_open else 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_queue_save"):
		player.call("_queue_save")

func save_survival_state() -> Dictionary:
	return {"open": is_open}

func interact_survival(player: Node) -> void:
	toggle()
	player.call("_hud_toast", "WINDOW OPEN" if is_open else "WINDOW CLOSED")

func restore_survival_state(data: Dictionary) -> void:
	is_open = bool(data.get("open", false))
	if _hinge != null:
		_hinge.rotation.y = deg_to_rad(-85.0) if is_open else 0.0
