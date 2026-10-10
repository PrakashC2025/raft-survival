extends Node3D
## Small original GLB shoal. No physics bodies; nearby only, with no shadows.
const FISH: PackedScene = preload("res://models/coastal_fish.glb")
@export var follow_raft:=false
var _fish: Array[Node3D] = []
var _cooldowns: Array[float]=[]
var _return_depth: Array[float]=[]
var _time := 0.0
var _ocean: Node
var _player: Node3D

func _ready() -> void:
	add_to_group("no_collision")
	add_to_group("surface_fish_school")
	_ocean = get_tree().current_scene.get_node_or_null("Ocean")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	for i in range(6 if follow_raft else 4):
		var model := FISH.instantiate() as Node3D
		model.scale = Vector3.ONE * ((.40+i*.025) if follow_raft else (0.65+i*.07))
		for candidate in model.find_children("*", "MeshInstance3D", true, false):
			(candidate as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
		_fish.append(model)
		_cooldowns.append(0.0)
		_return_depth.append(0.0)

func _process(delta: float) -> void:
	_time += delta
	if follow_raft:
		var raft:=get_tree().get_first_node_in_group("raft") as Node3D
		if raft!=null:global_position=global_position.lerp(raft.global_position,1.0-exp(-delta*.8))
	for index in _cooldowns.size():_cooldowns[index]=maxf(0,_cooldowns[index]-delta)
	visible = _player != null and _player.global_position.distance_to(global_position) < 45.0
	if not visible:
		return
	for i in range(_fish.size()):
		var phase := _time * (0.12 if follow_raft else .045) + i * 0.38
		var model := _fish[i]
		var radius: float = 3.4+i*.08 if follow_raft else 21.0+i*.65
		var at := global_position + Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
		at.y = float(_ocean.call("get_height", at)) - 0.65 - i * 0.12 if _ocean != null else -0.7
		if _cooldowns[i]<=0:_return_depth[i]=maxf(0,_return_depth[i]-delta*.3)
		at.y-=_return_depth[i]
		model.global_position = at
		model.visible=_cooldowns[i]<=0
		model.rotation.y = -phase - PI / 2.0
		model.rotation.z = sin(_time * 8.0 + i) * 0.06

func take_nearby(at: Vector3, radius: float) -> bool:
	for index in _fish.size():
		if _cooldowns[index]<=0 and _fish[index].global_position.distance_squared_to(at)<=radius*radius:
			_cooldowns[index]=65.0;_return_depth[index]=8.0;_fish[index].hide();return true
	return false
