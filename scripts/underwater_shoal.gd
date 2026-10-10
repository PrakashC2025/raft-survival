extends Node3D
## Fixed instanced fish pool: 10 Hz school steering, smooth nearby transforms.
const TERRAIN:=preload("res://scripts/underwater_terrain.gd")
const COUNT:=24
var _parts:Array[MultiMeshInstance3D]=[]
var _base:Array[Transform3D]=[]
var _player:Node3D
var _time:=0.0
var _tick:=0.0
var _centre:=Vector3(0,0,9)
var _target:=Vector3(0,0,9)
var _forward:=Vector3.RIGHT
var _desired:=Vector3.RIGHT
var _flee:=false
func _ready() -> void:
	add_to_group("underwater_shoal")
	_player=get_tree().get_first_node_in_group("player") as Node3D
	var source:=preload("res://models/coastal_fish.glb").instantiate() as Node3D
	var species:=4 if str(name).contains("DeepCity") else (1 if str(name).contains("SunkenHarbour") else 0)
	var colours:=[Color(.85,.91,.92),Color(1.0,.78,.34),Color(.56,.88,.87),Color(.52,.68,.81),Color(.48,.53,.56)]
	for node in source.find_children("*","MeshInstance3D",true,false):
		var part:=node as MeshInstance3D;var tf:=part.transform;var ancestor:=part.get_parent()
		while ancestor!=source:tf=(ancestor as Node3D).transform*tf;ancestor=ancestor.get_parent()
		var draw:=MultiMeshInstance3D.new();var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true;batch.mesh=part.mesh;batch.instance_count=COUNT
		for fish in COUNT:
			var pigment: int = posmod(species+1+fish%3,5) if fish%5==0 else species
			batch.set_instance_color(fish,colours[pigment].lerp(Color.WHITE,float(fish%4)*.045))
		var material:=ShaderMaterial.new();material.shader=preload("res://shaders/underwater_fish.gdshader")
		var original:=part.get_active_material(0) as BaseMaterial3D
		if original!=null:
			material.set_shader_parameter("body_colour",original.albedo_color)
			if original.albedo_texture!=null:material.set_shader_parameter("fish_skin",original.albedo_texture);material.set_shader_parameter("textured",true)
		draw.multimesh=batch;draw.material_override=material;draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;draw.visibility_range_end=110;add_child(draw);_parts.append(draw);_base.append(tf)
	source.free()
	_draw_fish()
func _process(delta:float) -> void:
	_time+=delta;_tick+=delta
	visible=is_instance_valid(_player) and _player.global_position.distance_squared_to(global_position)<12100
	if not visible:return
	if _tick>=.1:
		_tick=0
		var phase:=_time*.12
		var wanted:=Vector3(sin(phase)*9,sin(_time*.17)*.6,cos(phase)*9)
		var actor:=_player.global_position-global_position
		_flee=actor.distance_squared_to(_centre)<64
		if _flee:wanted+=(_centre-actor).normalized()*5.0
		var world_point:=global_position+wanted
		wanted.y=clampf(wanted.y,TERRAIN.surface_height(Vector2(world_point.x,world_point.z))+1.4-global_position.y,TERRAIN.MARINE_CEILING-1.5-global_position.y)
		var direction:=(_target.direction_to(wanted))
		if direction.length_squared()>.1:
			var query:=PhysicsRayQueryParameters3D.create(global_position+_centre,global_position+_centre+direction*4.5,1)
			var hit:=get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():wanted=_centre+Vector3(hit.normal).slide(Vector3.UP)*3.0+Vector3.UP*.8
			_desired=(_centre.direction_to(wanted))
		wanted.y=minf(wanted.y,TERRAIN.MARINE_CEILING-1.5-global_position.y)
		_target=wanted
	_centre=_centre.move_toward(_target,delta*(2.0 if _flee else 1.1))
	_forward=_forward.lerp(_desired,1.0-exp(-delta*1.8)).normalized()
	_draw_fish()
func _draw_fish() -> void:
	var orientation:=Basis.looking_at(_forward,Vector3.UP)
	for fish in COUNT:
		var offset:=Vector3((fish%6-2.5)*.55,sin(fish*2.4)*.5,-floorf(float(fish)/6)*.7)
		offset.y+=sin(_time*.65+fish*1.7)*.10
		var tf:=Transform3D(orientation.scaled(Vector3.ONE*(.60+float(fish%4)*.08)),_centre+orientation*offset)
		for part in _parts.size():_parts[part].multimesh.set_instance_transform(fish,tf*_base[part])
