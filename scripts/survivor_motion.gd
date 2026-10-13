extends RefCounted
## Mixamo body states; the existing interaction rig keeps exact hand/tool contact.
const ACTIONS: Dictionary={
	"grab":"Gather","pick":"PickFruit","harvest":"Harvest","plant":"Plant",
	"water":"Water","scoop":"Gather","dig":"Plant","drink":"Drink",
	"eat":"Hold","cook":"Hold","prepare_seed":"Hold","unpack":"Hold",
	"bandage":"Hold","install":"Hold","door":"Hold","battery":"Hold",
	"build":"Hold","repair":"Hold","assemble_electronics":"Hold",
	"ignite_fire":"Work","snuff_fire":"Work","torch_light":"Hold",
	"torch_off":"Hold","torch_mount":"Hold","cast":"Hold","reel":"Hold",
	"chop":"Hold","strike":"Hold","paddle":"Hold","anchor":"Work",
	"pump":"Hold","brake":"Hold","shake":"Hold"
}
var walk_stride:=1.84
var run_stride:=2.37
var _airborne:=false
var _jumping:=false
var _landing_age:=-1.0
var _last_yaw:=0.0
var _have_yaw:=false
var _turn_age:=-1.0
var _turn_clip:="TurnLeft"

func configure(walk_distance: float,run_distance: float) -> void:
	walk_stride=walk_distance
	run_stride=run_distance

func sample(actor: CharacterBody3D,sprinting: bool,delta: float) -> Dictionary:
	var yaw_delta:=wrapf(actor.rotation.y-_last_yaw,-PI,PI) if _have_yaw else 0.0
	_last_yaw=actor.rotation.y;_have_yaw=true
	var grounded:=actor.is_on_floor()
	var swimming: bool=actor.get("is_swimming")
	var speed: float=actor.get("_gait_speed")
	if swimming:
		_airborne=false;_jumping=false;_landing_age=-1.0;_turn_age=-1.0
		var moving:=Vector2(actor.velocity.x,actor.velocity.z).length()>.35 or absf(actor.velocity.y)>.7
		return {"clip":"Swim" if moving else "TreadWater","phase":-1.0,"speed":clampf(Vector2(actor.velocity.x,actor.velocity.z).length()/2.0,.7,1.5) if moving else 1.0}
	if not grounded:
		if not _airborne: _jumping=actor.velocity.y>.25
		_airborne=true;_landing_age=-1.0;_turn_age=-1.0
		if not _jumping or actor.velocity.y < -float(actor.JUMP_VELOCITY)-1.0:return {"clip":"Fall","phase":-1.0,"speed":1.0}
		return {"clip":"Jump","phase":clampf((float(actor.JUMP_VELOCITY)-actor.velocity.y)/(2.0*float(actor.JUMP_VELOCITY)),0.0,.98),"speed":1.0}
	if _airborne:_landing_age=0.0;_airborne=false;_jumping=false
	if _landing_age>=0:
		_landing_age+=delta
		if _landing_age<.30 and speed<.65:return {"clip":"Land","phase":clampf(_landing_age/.30,0,1),"speed":1.0}
		_landing_age=-1.0
	# Moving away immediately resumes locomotion instead of dragging an action.
	if speed>=.65:
		_turn_age=-1.0
		var local_velocity:=actor.global_basis.inverse()*(actor.get_real_velocity()-actor.get_platform_velocity())
		var clip:="Run" if sprinting else "Walk"
		if absf(local_velocity.x)>absf(local_velocity.z)*1.25:clip=("Run" if sprinting else "Walk")+("Right" if local_velocity.x>0 else "Left")
		elif local_velocity.z>.3:clip="WalkBack"
		return {"clip":clip,"phase":float(actor.get("_gait_phase")),"speed":1.0}
	var action:=actor.get_node_or_null("SurvivalAction")
	if action!=null and not str(action.get("kind")).is_empty():
		_turn_age=-1.0
		var phase:=clampf(float(action.get("elapsed"))/maxf(float(action.get("duration")),.15),0,1)
		return {"clip":str(ACTIONS.get(str(action.get("kind")),"Hold")),"phase":phase,"speed":1.0}
	if absf(yaw_delta)>.003:
		var desired:="TurnLeft" if yaw_delta>0 else "TurnRight"
		if _turn_age<0 or _turn_clip!=desired:_turn_age=0.0;_turn_clip=desired
	if _turn_age>=0:
		_turn_age+=delta
		if _turn_age<.32:return {"clip":_turn_clip,"phase":clampf(_turn_age/.32,0,1),"speed":1.0}
		_turn_age=-1.0
	return {"clip":"Idle","phase":-1.0,"speed":1.0}
