extends CharacterBody3D
const SURFACES := preload("res://scripts/object_materials.gd")
const PICKUP := preload("res://scenes/food_pickup.tscn")
const CONTACT:=preload("res://scripts/contact_audio.gd")
const MODELS := {"Boar": "res://models/wild_boar.glb", "Crab": "res://models/shore_crab.glb", "Turtle": "res://models/sea_turtle.glb"}
var species := "Crab"
var animal_id := ""
var home := Vector3.ZERO
var health := 30.0
var respawn := 0.0
var alarm := 0.0
var _bite := 0.0
var _time := 0.0
var _sample := 0.0
var _legs: Array[Node] = []
var _model: Node3D
var _player: Node3D
var _swimming:=false
var _projectile_hit:=false
var _gait_phase:=0.0
var _facing:=Vector3.ZERO
var _tail: Node3D
var _tail_middle: Node3D
var _tail_tip: Node3D
var _animation: AnimationPlayer
var _playing_clip:=""
var _combat_audio: AudioStreamPlayer3D
func maximum_health() -> float:return 90.0 if species=="Crocodile" else (60.0 if species=="Boar" else 30.0)
func home_radius() -> float:return (80.0 if _player!=null and is_instance_valid(_player.get("boat_vehicle")) else 20.0) if species=="Crocodile" else 12.0 if species=="Boar" else 7.0
func _ready() -> void:
	add_to_group("huntable_animal")
	collision_layer = 2
	collision_mask = 1
	health = maximum_health()
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27 if species == "Boar" else (0.25 if species == "Turtle" else 0.15)
	shape.height = 1.0 if species == "Boar" else shape.radius * 2
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	if species=="Crocodile":
		var box:=BoxShape3D.new();box.size=Vector3(.8,.55,2.7);collision.shape=box;collision.position=Vector3(0,.25,.12)
	add_child(collision)
	_model = (load("res://models/hunting_crocodile.glb") as PackedScene).instantiate() as Node3D if species=="Crocodile" else (load(MODELS[species]) as PackedScene).instantiate() as Node3D
	if species=="Boar":_model.free();_model=(load("res://models/hunting_boar.glb") as PackedScene).instantiate() as Node3D
	add_child(_model)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		if species=="Crocodile":
			var skin:=ShaderMaterial.new();skin.shader=preload("res://shaders/hunting_real_croc.gdshader")
			skin.set_shader_parameter("skin_photo",preload("res://models/hunting_crocodile_Image_7.png"))
			skin.set_shader_parameter("source_details",preload("res://models/hunting_crocodile_croc_diffuse.png"))
			(node as MeshInstance3D).material_override=skin
		elif species=="Boar" and node.name.begins_with("SmoothFullBoarBody"):
			(node as MeshInstance3D).material_override=preload("res://scripts/hunting_materials.gd").skin("Boar")
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if species in ["Boar","Crocodile"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(node as MeshInstance3D).visibility_range_end = 65
	_legs = _model.find_children("Leg_*", "Node3D", true, false)
	_tail=_model.find_child("TailFin",true,false) as Node3D
	_tail_middle=_model.find_child("TailMiddle",true,false) as Node3D
	_tail_tip=_model.find_child("TailTip",true,false) as Node3D
	_animation=_model.find_child("AnimationPlayer",true,false) as AnimationPlayer
	if _animation!=null:
		_animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in ["Idle","Walk","Swim"]:
			if _animation.has_animation(clip):_animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_combat_audio=AudioStreamPlayer3D.new();_combat_audio.name="AnimalContactAudio";_combat_audio.unit_size=10;_combat_audio.max_distance=45;_combat_audio.max_polyphony=3;add_child(_combat_audio)

func _contact_sound(attacking: bool) -> void:
	# Recorded wet/body and hide contacts; these are impacts, not animal voices.
	_combat_audio.stream=CONTACT.pick_action("animal_snap" if attacking else "body_impact")
	_combat_audio.volume_db=-4 if attacking else -7
	_combat_audio.pitch_scale=.62 if species=="Crocodile" else .83
	_combat_audio.play()

func _physics_process(delta: float) -> void:
	_time += delta
	_bite = maxf(0, _bite - delta)
	alarm = maxf(0, alarm - delta)
	if respawn > 0:
		respawn = maxf(0, respawn - delta)
		if respawn <= 0:
			health = maximum_health()
			visible = true
			collision_layer = 2
			global_position = home
		return
	if _player == null:
		return
	var distance := global_position.distance_squared_to(_player.global_position)
	if distance > 4225:
		return
	if species=="Crocodile" and _swimming:
		var ocean:=get_tree().get_first_node_in_group("ocean")
		var water_y: float=float(ocean.call("get_height",global_position)) if ocean!=null else 0.0
		global_position.y=move_toward(global_position.y,water_y-.23,delta*2);velocity.y=0
	else:velocity.y = maxf(-3.0, velocity.y - 9.8 * delta)
	move_and_slide()
	_animate_motion(delta)
	if _facing.length_squared()>.01:rotation.y=lerp_angle(rotation.y,atan2(-_facing.x,-_facing.z),1-exp(-delta*4))
	_sample += delta
	if _sample < 0.15:
		return
	var step := minf(_sample, 0.3)
	_sample = 0
	var rain := get_tree().get_first_node_in_group("rain_system")
	if rain != null and rain.call("is_raining") and alarm <= 0 and species not in ["Boar","Crocodile"]:
		velocity.x = 0
		velocity.z = 0
		return # shelter in storms, rather than endlessly roaming
	var direction := home + Vector3(sin(_time*0.13+home.x)*3,0,cos(_time*0.12)*3) - global_position
	var speed := 0.7 if species == "Boar" else (0.20 if species == "Turtle" else 0.45)
	var predator:=species in ["Boar","Crocodile"]
	var aboard: bool=is_instance_valid(_player.get("boat_vehicle"))
	var aggro_range: float=(576.0 if aboard else 144.0) if species=="Crocodile" else 100.0
	var hunting:=predator and distance<((1600.0 if aboard else 196.0) if alarm>0 else aggro_range) and _player.global_position.y>(-2.0 if species=="Crocodile" else .2) and (species=="Crocodile" or not aboard)
	if hunting and aboard:alarm=maxf(alarm,4)
	if hunting:
		direction=_player.global_position-global_position;speed=3.2 if species=="Crocodile" else 2.6
	elif distance < 36:
		direction = global_position - _player.global_position
		speed *= 2
	if hunting:
		for fire in get_tree().get_nodes_in_group("campfire"):
			if fire.burning and fire.global_position.distance_squared_to(global_position) < 36:
				direction = global_position - fire.global_position;hunting=false
				break
		if hunting and distance < (5.0 if species=="Crocodile" else 2.8) and _bite <= 0 and Stats.health>0:
			var query:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.4,_player.global_position,1,[get_rid(),_player.get_rid()])
			if aboard and species=="Crocodile":query.exclude=[get_rid(),_player.get_rid(),(_player.get("boat_vehicle") as CharacterBody3D).get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():hunting=false
		if hunting and distance < (5.0 if species=="Crocodile" else 2.8) and _bite <= 0 and Stats.health>0:
			_contact_sound(true)
			if aboard and species=="Crocodile":_player.get("boat_vehicle").call("_water_contact",-3.0)
			Stats.change_health(-14 if species=="Crocodile" else -10)
			_bite = 2
			_player.call("_hud_toast", species.to_upper()+" ATTACK · KEEP YOUR DISTANCE")
	direction.y = 0
	direction = direction.normalized()
	var next := global_position + direction * speed * step
	if Vector2(next.x-home.x,next.z-home.z).length() > home_radius():
		velocity.x = 0
		velocity.z = 0
		return
	var ground := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(next+Vector3.UP*2,next+Vector3.DOWN*3,1))
	if species=="Crocodile":_swimming=ground.is_empty() or Vector3(ground.position).y<-.12
	if species!="Crocodile" and (ground.is_empty() or Vector3(ground["position"]).y < 0.20):
		velocity.x = 0
		velocity.z = 0
		return
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_facing=direction

func _animate_motion(delta: float) -> void:
	var speed:=Vector2(velocity.x,velocity.z).length()
	if _animation!=null:
		var clip:="Attack" if _bite>1.6 else (("Swim" if _animation.has_animation("Swim") else "Walk") if _swimming and species=="Crocodile" else ("Walk" if speed>.06 else "Idle"))
		if _animation.has_animation(clip):
			if clip!=_playing_clip:_animation.play(clip,.14);_playing_clip=clip
			_animation.speed_scale=clampf(speed/(.7 if species=="Boar" else .6),.55,2.6) if clip=="Walk" else 1.0
			_animation.advance(delta)
		return
	_gait_phase+=speed*delta*(7 if species=="Boar" else 8)
	var effort:=minf(1,speed/.6)
	for index in _legs.size():
		var leg:=_legs[index] as Node3D
		var phase:=_gait_phase+(PI if index in [1,2] else 0.0)
		if species=="Crocodile":
			leg.rotation.x=lerp_angle(leg.rotation.x,-.25 if _swimming else sin(phase)*.20*effort,1-exp(-delta*9))
			leg.rotation.y=sin(phase)*(.05 if _swimming else .15)*effort
		else:
			leg.rotation.x=sin(phase)*(.38 if species=="Boar" else .22)*effort
			var knee:=leg.get_node_or_null("Knee") as Node3D
			if knee!=null:knee.rotation.x=-maxf(0,sin(phase))*.48*effort
	if species=="Boar":
		_model.position.y=absf(cos(_gait_phase))*.018*effort
		_model.rotation.z=sin(_gait_phase*.5)*.018*effort
		for side in [-1,1]:(_model.get_node("Ear_%d"%side) as Node3D).rotation.x=sin(_time*2.1+side)*.025
	if _tail!=null:
		var amplitude:=.23 if _swimming else .055
		_tail.rotation.y=sin(_time*3.8)*amplitude
		_tail_middle.rotation.y=sin(_time*3.8-.7)*amplitude*.9
		_tail_tip.rotation.y=sin(_time*3.8-1.4)*amplitude*.8
		var jaw:=_model.get_node("UpperJaw") as Node3D
		jaw.rotation.x=lerp_angle(jaw.rotation.x,-.30 if _bite>1.6 else 0.0,1-exp(-delta*14))

func take_damage(amount: float, _attacker: Node = null) -> void:
	if amount <= 0 or respawn > 0:
		return
	_contact_sound(false)
	health = maxf(0, health-amount)
	alarm = 15
	if health <= 0:
		visible = false
		set_deferred("collision_layer",0)
		respawn = 240
		var item:="Raw Crab" if species=="Crab" else "Raw Meat"
		var count:=3 if species=="Crocodile" else (1 if species=="Crab" else 2)
		var service:=_attacker.get_node_or_null("SurvivalServices") if is_instance_valid(_attacker) else null
		if service!=null:service.call("drop_items",[{"item":item,"count":count}],global_position+Vector3.UP*.2,species)
		else:
			var drop := PICKUP.instantiate() as Node3D;drop.set("item_name",item);drop.set("amount",count)
			get_tree().current_scene.add_child(drop);drop.global_position = global_position + Vector3.UP*0.2
		var progress := get_tree().get_first_node_in_group("survival_progression")
		if progress != null:
			progress.call("record","hunt:"+species)
		if is_instance_valid(_attacker):_attacker.call("_queue_save")

func take_projectile_damage(amount: float,actor: Node=null) -> void:
	_projectile_hit=true;take_damage(amount,actor);_projectile_hit=false

func save_state() -> Dictionary:
	return {"health": health,"respawn":respawn}
func restore_state(data: Dictionary) -> void:
	health = clampf(float(data.get("health",maximum_health())),0,maximum_health())
	respawn = clampf(float(data.get("respawn",0)),0,240)
	if health <= 0:
		respawn = maxf(respawn,1)
	visible = respawn <= 0
	collision_layer = 2 if visible else 0
