extends CharacterBody3D
const TERRAIN := preload("res://scripts/underwater_terrain.gd")
var species := "Fish"
var creature_id := ""
var health := 20.0
var home := Vector3.ZERO
var school_centre := Vector3.ZERO
var school_offset := Vector3.ZERO
var respawn := 0.0
var _time := 0.0
var _alarm := 0.0
var _tick := 0.0
var _player: Node3D
var _model: Node3D
var _legs: Array[Node] = []
var _tail: Node3D
var _desired_velocity:=Vector3.ZERO
var _leg_rest: Array[Vector3]=[]
func maximum_health() -> float:return 40.0 if species=="Grouper" else (20.0 if species=="Fish" else 30.0)

func _ready() -> void:
	add_to_group("huntable_animal");add_to_group("dive_creature")
	collision_layer=2;collision_mask=1
	health=maximum_health()
	var collider:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.32 if species=="Fish" else (.60 if species=="Ray" else (.38 if species=="Turtle" else .24));collider.shape=sphere;add_child(collider)
	_model=(preload("res://models/coastal_fish.glb") if species=="Fish" else (preload("res://models/sea_turtle.glb") if species=="Turtle" else preload("res://models/shore_crab.glb"))).instantiate() as Node3D
	if species=="Ray":_model.free();_model=preload("res://scripts/sea_fauna_visual.gd").ray()
	if species=="Grouper":_model.free();_model=preload("res://models/coastal_fish.glb").instantiate() as Node3D
	if species=="Octopus":_model.free();_model=preload("res://scripts/hunting_visual.gd").octopus()
	_model.scale=Vector3.ONE*(1.3 if species=="Fish" else 1.2);add_child(_model)
	if species=="Grouper":_model.scale=Vector3(2.4,2.8,2.8)
	_tail=_model.find_child("TailFin",true,false) as Node3D
	_legs=_model.find_children("Leg_*","Node3D",true,false)
	for leg in _legs:_leg_rest.append((leg as Node3D).rotation)
	for part in _model.find_children("*","MeshInstance3D",true,false):
		part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;part.visibility_range_end=110
	_player=get_tree().get_first_node_in_group("player") as Node3D

func _physics_process(delta: float) -> void:
	_time+=delta;_alarm=maxf(0,_alarm-delta)
	if respawn>0:
		respawn=maxf(0,respawn-delta)
		if respawn<=0:health=maximum_health();visible=true;collision_layer=2;global_position=home
		return
	if _player==null or global_position.distance_squared_to(_player.global_position)>10000:return
	if _tail!=null:_tail.rotation.y=sin(_time*(5+velocity.length()*3))*.19
	for index in _legs.size():
		if species in ["Ray","Turtle"]:(_legs[index] as Node3D).rotation.z=sin(_time*2.2)*.28*(-1 if index%2==0 else 1)
		elif species=="Octopus":
			var leg:=_legs[index] as Node3D;var phase:=_time*1.7-index*.8
			leg.rotation=_leg_rest[index]+Vector3(sin(phase)*.11,sin(phase*.8)*.09,cos(phase)*.045)
		else:(_legs[index] as Node3D).rotation.x=sin(_time*6+index*PI)*.28
	if species=="Octopus":_model.scale.y=1.2*(1+sin(_time*1.8)*.018)
	_tick+=delta
	if _tick>=.1:
		_steer();_tick=0
	# Steering stays bounded at 10 Hz, while real collision/motion runs every physics frame.
	velocity=velocity.lerp(_desired_velocity,1-exp(-delta*3))
	move_and_slide()
	if species not in ["Crab","Octopus"]:global_position.y=minf(global_position.y,TERRAIN.MARINE_CEILING)
	if velocity.length_squared()>.01:
		rotation.y=lerp_angle(rotation.y,atan2(-velocity.x,-velocity.z),1-exp(-delta*3))
		if species in ["Fish","Grouper"]:_model.rotation.x=lerp_angle(_model.rotation.x,asin(clampf(velocity.normalized().y,-.7,.7)),1-exp(-delta*2))

func _steer() -> void:
	var target:=home+Vector3(sin(_time*.18+home.x)*4.5,sin(_time*.37)*.9 if species!="Crab" else 0.0,cos(_time*.16+home.z)*4.5)
	if species=="Fish":
		var phase:=float(get_parent().get("_swim_time"))*.12
		target=school_centre+Vector3(sin(phase)*9,sin(phase*.7)*.6,cos(phase)*9)+Basis(Vector3.UP,phase-PI/2)*school_offset
	if _alarm>0:target=home+(_player.global_position.direction_to(global_position))*6
	if species in ["Crab","Octopus"]:
		var world:=get_parent()
		target.y=float(world.call("surface_height",Vector2(target.x,target.z)))+.22
	else:
		# Hunting/fleeing must not pull diving fauna toward the air above waves.
		target.y=minf(target.y,TERRAIN.MARINE_CEILING)
	var direction:=global_position.direction_to(target)
	var speed:=.32 if species=="Octopus" else (1.1 if species!="Crab" else .4)
	_desired_velocity=direction*speed*(1.65 if _alarm>0 else 1.0)

func take_damage(amount: float, actor: Node=null) -> void:
	if amount<=0 or respawn>0:return
	if is_instance_valid(actor):actor.call("play_world_sfx",preload("res://scripts/contact_audio.gd").pick_action("water"),-5.0,global_position)
	if health<=amount:
		var item:="Fish" if species in ["Fish","Ray","Grouper"] else ("Raw Crab" if species=="Crab" else "Raw Meat")
		var service:=actor.get_node_or_null("SurvivalServices") if is_instance_valid(actor) else null
		if service!=null:
			service.drop_items([{"item":item,"count":2 if species=="Grouper" else 1}],global_position,species)
			health=0;respawn=600;visible=false;set_deferred("collision_layer",0);actor._queue_save()
			var progression:=get_tree().get_first_node_in_group("survival_progression")
			if progression!=null:progression.record("hunt:"+species)
			return
		if not Inventory.try_exchange({},{item:1}):
			if actor!=null:actor.call("_hud_toast","BAG FULL · CREATURE RETAINED")
			return
		Inventory.notify_pickup(item,1)
		if actor!=null:actor.call("play_action","grab",.6,global_position,item);actor.call("_queue_save")
		visible=false;collision_layer=0;respawn=600.0;health=0
		var progress:=get_tree().get_first_node_in_group("survival_progression")
		if progress!=null:progress.call("record","hunt:"+species)
	else:health-=amount;_alarm=6

func take_projectile_damage(amount: float,actor: Node=null) -> void:
	if amount<=0 or respawn>0:return
	if is_instance_valid(actor):actor.call("play_world_sfx",preload("res://scripts/contact_audio.gd").pick_action("water"),-5.0,global_position)
	if health>amount:health-=amount;_alarm=6;return
	var service:=actor.get_node_or_null("SurvivalServices") if is_instance_valid(actor) else null
	if service==null:take_damage(amount,actor);return
	var item:="Fish" if species in ["Fish","Ray","Grouper"] else ("Raw Crab" if species=="Crab" else "Raw Meat")
	service.call("drop_items",[{"item":item,"count":2 if species=="Grouper" else 1}],global_position,species)
	health=0;respawn=600;visible=false;set_deferred("collision_layer",0)
	actor.call("_hud_toast","HUNTED "+species.to_upper()+" · COLLECT FLOATING LOOT")
	actor.call("_queue_save")
	var progress:=get_tree().get_first_node_in_group("survival_progression")
	if progress!=null:progress.call("record","hunt:"+species)

func save_state() -> Dictionary: return {"health":health,"respawn":respawn}
func restore_state(data: Dictionary) -> void:
	health=clampf(float(data.get("health",maximum_health())),0,maximum_health())
	respawn=clampf(float(data.get("respawn",0)),0,600)
	if health<=0:respawn=maxf(1,respawn)
	visible=respawn<=0;collision_layer=2 if visible else 0
