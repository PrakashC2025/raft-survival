extends CharacterBody3D
## A separate, steerable boat. The raft and its buildings stay where they are.
const SPEED:=4.6
const CONTACT:=preload("res://scripts/contact_audio.gd")
const COURSE_SKIP:=preload("res://scripts/course_skip.gd")
var driver: CharacterBody3D
var _course_active:=false
var _course_target:=Vector3.ZERO
var _arrival_radius:=18.0
var _time:=0.0
var _save_clock:=0.0
var _visual: Node3D
var _ocean: Node3D
var _old_body_y:=0.0
var _stroke_phase:=0.0
var _rowing_weight:=0.0
var _oar_audio: AudioStreamPlayer3D
var _hull_audio: AudioStreamPlayer3D
var _next_stroke:=0.0
var _creak_clock:=0.0
var _impact_clock:=0.0
var transition_kind:=""
var transition_progress:=0.0
var _transition_start:=Vector3.ZERO
var _transition_end:=Vector3.ZERO
const TRANSITION_SECONDS:=.85

func _ready() -> void:
	name="Rowboat";add_to_group("player_boat");add_to_group("map_vehicle")
	set_meta("map_label","Your Rowboat");set_meta("biome","boat")
	collision_layer=1;collision_mask=1;motion_mode=CharacterBody3D.MOTION_MODE_FLOATING
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.4,.64,3.1);shape.shape=box;shape.position.y=.06;add_child(shape)
	_visual=preload("res://scripts/rowboat_visual.gd").create();add_child(_visual)
	_ocean=get_tree().get_first_node_in_group("ocean") as Node3D
	add_to_group("interactable_boat")
	_oar_audio=_make_audio("OarWaterAudio",-8)
	_hull_audio=_make_audio("HullTimberAudio",-14)

func _make_audio(label: String,level: float) -> AudioStreamPlayer3D:
	var audio:=AudioStreamPlayer3D.new();audio.name=label;audio.volume_db=level;audio.unit_size=12;audio.max_distance=50;audio.max_polyphony=2;add_child(audio);return audio

func _water_contact(level: float=-8.0) -> void:
	_oar_audio.stream=CONTACT.pick_action("water");_oar_audio.volume_db=level;_oar_audio.pitch_scale=randf_range(.85,1.05);_oar_audio.play()

func interaction_caption() -> String:return "BOARD ROWBOAT"
func interact_survival(actor: Node3D) -> void:
	if actor.global_position.distance_to(global_position)<4.5:board(actor)

func board(actor: CharacterBody3D,restoring: bool=false) -> bool:
	if is_instance_valid(driver) or Stats.health<=0 or actor.build_mode:return false
	if not restoring and actor.global_position.distance_to(global_position)>4.5:return false
	var cargo:=actor.get_node("HuntingCargo")
	if is_instance_valid(cargo.held) and not cargo.load_boat(self):return false
	_transition_start=actor.global_position;transition_kind="" if restoring else "board";transition_progress=1 if restoring else 0
	driver=actor;driver.boat_vehicle=self;driver.is_swimming=false;driver.velocity=Vector3.ZERO
	driver.add_collision_exception_with(self);add_collision_exception_with(driver)
	driver.get_node("SurvivalEquipment").cancel_draw();driver.get_node("SurvivalEquipment").set_aiming(false)
	driver.get_node("SurvivalAction").stop();driver.rope_system._force_cancel()
	_old_body_y=driver.get_node("Body").position.y;driver.get_node("Body").position.y=_old_body_y-.42
	GameSettings.release_gameplay_input();sync_driver()
	driver.call("_apply_camera_mode");driver.call("_queue_save")
	_water_contact(-12)
	if not restoring:driver.play_action("board_boat",TRANSITION_SECONDS,global_position)
	driver.call("_hud_toast","ROWBOAT · STEER WITH JOYSTICK · SELECT FOOD TO EAT · SPACE / LEAVE TO EXIT",5.0)
	return true

func disembark() -> bool:
	if not is_instance_valid(driver) or not transition_kind.is_empty():return false
	var actor:=driver
	# Test several sides and require space for the player's actual capsule.
	for offset in [Vector3(1.65,1.25,.2),Vector3(-1.65,1.25,.2),Vector3(0,1.25,2.5),Vector3(0,1.25,-2.5)]:
		var destination:=to_global(offset)
		var ground:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(destination+Vector3.UP*2,destination+Vector3.DOWN*3,1,[get_rid(),actor.get_rid()]))
		if not ground.is_empty():destination.y=maxf(destination.y,Vector3(ground.position).y+1.03)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=(actor.get_node("CollisionShape3D") as CollisionShape3D).shape
		query.transform=Transform3D(Basis.IDENTITY,destination);query.collision_mask=1;query.exclude=[get_rid(),actor.get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		transition_kind="leave";transition_progress=0;_transition_start=actor.global_position;_transition_end=destination
		velocity=Vector3.ZERO;clear_course();GameSettings.release_gameplay_input();actor.play_action("leave_boat",TRANSITION_SECONDS,destination);return true
	actor.call("_hud_toast","NO CLEAR EXIT · MOVE THE BOAT INTO OPEN WATER");return false

func _release_driver() -> void:
	transition_kind="";transition_progress=1
	if not is_instance_valid(driver):driver=null;return
	driver.get_node("Body").position.y=_old_body_y;driver.get_node("Body").rotation.y=0;driver.boat_vehicle=null
	driver.remove_collision_exception_with(self);remove_collision_exception_with(driver)
	driver.call("_apply_camera_mode");driver.get_node("SurvivalAction").stop()
	driver=null;velocity=Vector3.ZERO;clear_course();GameSettings.release_gameplay_input()
	_oar_audio.stop();_hull_audio.stop();_next_stroke=_stroke_phase

func sync_driver() -> void:
	if not is_instance_valid(driver):return
	var seat:=to_global(Vector3(0,1.03,.48))
	var blend:=smoothstep(0,1,transition_progress)
	driver.global_position=_transition_start.lerp(_transition_end if transition_kind=="leave" else seat,blend)+Vector3.UP*sin(blend*PI)*.23 if not transition_kind.is_empty() else seat
	driver.velocity=Vector3.ZERO;driver.is_swimming=false
	driver.get_node("Body").position.y=lerpf(_old_body_y-.42,_old_body_y,blend) if transition_kind=="leave" else lerpf(_old_body_y,_old_body_y-.42,blend)
	driver.get_node("Body").rotation.y=rotation.y-driver.rotation.y

func advance_transition(delta: float) -> void:
	if transition_kind.is_empty() or not is_instance_valid(driver):return
	transition_progress=minf(1,transition_progress+delta/TRANSITION_SECONDS);sync_driver()
	if transition_progress<1:return
	if transition_kind=="leave":
		var actor:=driver;var destination:=_transition_end;_release_driver();actor.global_position=destination;actor.velocity=Vector3.ZERO;actor._queue_save();_water_contact(-10)
	else:transition_kind="";driver._queue_save()

func get_navigation_speed() -> float:return SPEED
func set_course(target: Vector3,arrival: float=18) -> bool:
	if not is_instance_valid(driver):return false
	_course_target=Vector3(target.x,0,target.z);_arrival_radius=clampf(arrival,4,85)
	_course_active=Vector2(target.x-global_position.x,target.z-global_position.z).length()>_arrival_radius+1
	return _course_active
func clear_course() -> void:_course_active=false
func has_active_course() -> bool:return _course_active
func get_course_distance() -> float:return Vector2(_course_target.x-global_position.x,_course_target.z-global_position.z).length() if _course_active else 0.0
func skip_course() -> bool:
	if not can_skip_course():return false
	var destination:=COURSE_SKIP.landing(self,_course_target,_arrival_radius)
	if not destination.is_finite():return false
	var direction:=_course_target-destination;direction.y=0;direction=direction.normalized()
	var sailing_speed:=maxf(Vector2(velocity.x,velocity.z).length(),SPEED*.8)
	global_position=destination;velocity=direction*sailing_speed
	reset_physics_interpolation();sync_driver();driver.reset_physics_interpolation()
	return true

func can_skip_course() -> bool:
	return is_instance_valid(driver) and transition_kind.is_empty() and not driver.boat_consumption_active() and COURSE_SKIP.can_skip(self,_arrival_radius)

func _physics_process(delta: float) -> void:
	_time+=delta
	_impact_clock=maxf(0,_impact_clock-delta)
	if is_instance_valid(driver) and Stats.health<=0:_release_driver()
	advance_transition(delta)
	var desired:=Vector3.ZERO
	if is_instance_valid(driver):
		var hud:=driver.get_node("CanvasLayer/SurvivalHUD")
		var trip_fade:=bool(get_meta("trip_skip_active",false))
		if transition_kind.is_empty() and not GameSettings.is_open and (not hud.gameplay_input_blocked() or trip_fade) and not driver.boat_consumption_active():
			if not trip_fade:
				var input_dir:=Input.get_vector("move_left","move_right","move_back","move_forward")
				desired=driver.call("_get_movement_direction",input_dir)
			if desired.length_squared()>.01:clear_course()
			elif _course_active:
				var to_target:=_course_target-global_position;to_target.y=0
				if to_target.length()<=_arrival_radius:
					clear_course();driver.call("_hud_toast","ARRIVED · LEAVE BOAT TO EXPLORE");driver.call("_queue_save")
				else:desired=to_target.normalized()
	if desired.length_squared()>.001:
		rotation.y=lerp_angle(rotation.y,atan2(-desired.x,-desired.z),1-exp(-delta*3))
	velocity=velocity.move_toward(desired*SPEED,delta*(2.3 if desired.length_squared()>.01 else 5.0));velocity.y=0
	var collision:=move_and_collide(velocity*delta)
	if collision!=null:
		if _impact_clock<=0 and velocity.length()>.5:_water_contact(-5);_impact_clock=.7
		velocity=velocity.slide(collision.get_normal())
		if _course_active:
			clear_course();if is_instance_valid(driver):driver.call("_hud_toast","SHORE OR OBSTACLE · STEER AROUND IT")
	if is_instance_valid(_ocean):global_position.y=lerpf(global_position.y,float(_ocean.call("get_height",global_position))+.03,1-exp(-delta*6))
	var speed:=Vector2(velocity.x,velocity.z).length()
	_rowing_weight=lerpf(_rowing_weight,1.0 if desired.length_squared()>.01 and is_instance_valid(driver) else 0.0,1-exp(-delta*5))
	_stroke_phase+=delta*lerpf(2.7,3.5,minf(1,speed/SPEED))
	if _rowing_weight>.3 and speed>.25 and _stroke_phase>=_next_stroke:
		_water_contact();_next_stroke=_stroke_phase+TAU
	_creak_clock-=delta
	if speed>.4 and is_instance_valid(driver) and _creak_clock<=0:
		_hull_audio.stream=CONTACT.pick_action("reel");_hull_audio.pitch_scale=randf_range(.65,.85);_hull_audio.play();_creak_clock=2.2
	_visual.rotation.x=sin(_time*1.7)*.010+sin(_stroke_phase)*.008*_rowing_weight
	_visual.rotation.z=sin(_time*1.15)*.014
	for side in [-1,1]:
		var oar:=_visual.get_node("Oars/OarLeft" if side<0 else "Oars/OarRight") as Node3D
		# Blades dip through the power stroke, lift for recovery, and settle when rowing stops.
		oar.rotation.y=side*sin(_stroke_phase)*.32*_rowing_weight
		oar.rotation.z=side*(maxf(0,cos(_stroke_phase))*.14-maxf(0,-cos(_stroke_phase))*.07)*_rowing_weight
	sync_driver()
	_save_clock+=delta
	if is_instance_valid(driver) and _save_clock>5:_save_clock=0;driver.call("_queue_save")

func save_state() -> Dictionary:
	return {"p":[global_position.x,global_position.y,global_position.z],"yaw":rotation.y,"aboard":is_instance_valid(driver)}
