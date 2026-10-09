extends Node3D
## Instanced original fish, one nearby update at 10 Hz; no physics actors.
var _parts:Array[MultiMeshInstance3D]=[]
var _base:Array[Transform3D]=[]
var _player:Node3D
var _time:=0.0
var _tick:=0.0
const COUNT:=24
func _ready() -> void:
	add_to_group("underwater_shoal")
	_player=get_tree().get_first_node_in_group("player") as Node3D
	var source:=preload("res://models/coastal_fish.glb").instantiate() as Node3D
	for node in source.find_children("*","MeshInstance3D",true,false):
		var part:=node as MeshInstance3D;var tf:=part.transform;var ancestor:=part.get_parent()
		while ancestor!=source:tf=(ancestor as Node3D).transform*tf;ancestor=ancestor.get_parent()
		var draw:=MultiMeshInstance3D.new();var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=part.mesh;batch.instance_count=COUNT
		draw.multimesh=batch;draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;draw.visibility_range_end=100;add_child(draw);_parts.append(draw);_base.append(tf)
	source.free()
func _process(delta:float) -> void:
	_time+=delta;_tick+=delta
	visible=_player!=null and _player.global_position.distance_squared_to(global_position)<10000
	if not visible or _tick<.1:return
	_tick=0
	var phase:=_time*.12;var centre:=Vector3(sin(phase)*9,sin(_time*.17)*.6,cos(phase)*9)
	var orientation:=Basis(Vector3.UP,phase-PI*.5)
	for fish in COUNT:
		var offset:=Vector3((fish%6-2.5)*.6,sin(fish*2.4)*.6,-floorf(float(fish)/6)*.75)
		var tf:=Transform3D(orientation.scaled(Vector3.ONE*(.60+float(fish%4)*.08)),centre+orientation*offset)
		for part in _parts.size():_parts[part].multimesh.set_instance_transform(fish,tf*_base[part])
