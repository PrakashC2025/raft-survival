extends Node3D
## Small original GLB shoal. No physics bodies; nearby only, with no shadows.
const FISH: PackedScene = preload("res://models/coastal_fish.glb")
var _fish: Array[Node3D] = []
var _time := 0.0
var _ocean: Node
var _player: Node3D

func _ready() -> void:
	add_to_group("no_collision")
	_ocean = get_tree().current_scene.get_node_or_null("Ocean")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	for i in range(4):
		var model := FISH.instantiate() as Node3D
		model.scale = Vector3.ONE * (0.65 + i * 0.07)
		for candidate in model.find_children("*", "MeshInstance3D", true, false):
			(candidate as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
		_fish.append(model)

func _process(delta: float) -> void:
	_time += delta
	visible = _player != null and _player.global_position.distance_to(global_position) < 45.0
	if not visible:
		return
	for i in range(_fish.size()):
		var phase := _time * 0.20 + i * 0.28
		var model := _fish[i]
		var radius := 21.0 + i * 0.65
		var at := global_position + Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
		at.y = float(_ocean.call("get_height", at)) - 0.65 - i * 0.12 if _ocean != null else -0.7
		model.global_position = at
		model.rotation.y = -phase - PI / 2.0
		model.rotation.z = sin(_time * 8.0 + i) * 0.06
