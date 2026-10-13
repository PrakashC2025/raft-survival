extends SkeletonModifier3D
## Solve two arm bones after animation; legs and torso keep their walking clips.
var player: Node3D
var upper := -1
var lower := -1
var wrist := -1
var _finger_bones: Array[int]=[]
var _thumb_bones: Array[int]=[]
var _spine := -1
var _cached := false

func _process_modification() -> void:
	var rig := get_skeleton()
	if rig == null or player == null or upper < 0 or lower < 0 or wrist < 0: return
	if int(player.get("cam_mode")) != 1: return
	if player.call("movement_owns_hands"): return
	var action := player.get_node_or_null("SurvivalAction")
	var pose: Dictionary = action.call("sample_pose") if action!=null else {}
	var acting := not pose.is_empty() and float(pose.weight)>0.001
	var holding := bool(player.get("rope_gun_selected")) or not str(player.get("active_item")).is_empty()
	if not holding and not acting:return
	if not _cached:
		_cached=true;_spine=rig.find_bone("Chest")
		for side in ["R","L"]:
			for finger in ["Index","Middle","Ring","Pinky"]:
				for joint in [1,2,3,4]:
					var bone := rig.find_bone("%s%d.%s"%[finger,joint,side])
					if bone>=0:_finger_bones.append(bone)
			var thumb := rig.find_bone("Thumb2."+side)
			if thumb>=0:_thumb_bones.append(thumb)
	var curl := 0.8 if holding else 0.0
	if acting and str(action.get("kind")) in ["eat","drink","cook"]:curl=.8
	if acting and str(action.get("kind")) in ["grab","pick","harvest","plant"]:
		var progress:=float(action.get("elapsed"))/float(action.get("duration"))
		curl=.85*smoothstep(.28,.42,progress)*(1.0-smoothstep(.92,1.0,progress))
	if acting and _spine>=0:
		var torso := rig.get_bone_pose_rotation(_spine)
		rig.set_bone_pose_rotation(_spine,Quaternion.from_euler(pose.torso)*torso)
	var aim := (player.get("camera") as Camera3D).global_basis.orthonormalized()
	var target := player.global_transform*Vector3(0.30,0.18,0.0)-aim.z*0.32
	if acting:
		target=target.lerp(player.global_transform*pose.right,pose.weight)
	_solve(rig,upper,lower,wrist,target,1.0)
	if acting or str(player.get("active_item")) in ["Fishing Rod","Bow","Spear"]:
		var left_target: Vector3=player.global_transform*(pose.left if acting else Vector3(-0.12,0.13,-0.39))
		_solve(rig,rig.find_bone("UpperArm.L"),rig.find_bone("LowerArm.L"),rig.find_bone("Wrist.L"),left_target,-1.0)
	if acting and str(action.get("kind"))=="drink":
		# Turn the palm around the cup rather than keeping the idle wrist roll.
		var knuckle:=rig.find_bone("Middle1.R")
		if knuckle>=0:
			var hand_pose:=rig.get_bone_global_pose(wrist)
			var direction:=rig.get_bone_global_pose(knuckle).origin-hand_pose.origin
			var forward:=rig.global_basis.inverse()*player.global_basis*Vector3(0,.12,-1)
			if direction.length_squared()>.000001:
				hand_pose.basis=Basis(Quaternion(direction.normalized(),forward.normalized()))*hand_pose.basis
				rig.set_bone_global_pose(wrist,hand_pose)
	# Apply fingers after the upper/lower-arm global overrides; local pose edits
	# made before those overrides were lost in the rendered skin.
	var left_grip := acting or str(player.get("active_item")) in ["Fishing Rod","Bow","Spear"]
	var left_curl := curl
	if acting and str(action.get("kind"))=="take_fish":
		left_curl=.85*smoothstep(.26,.40,float(action.get("elapsed"))/float(action.get("duration")))
	for bone in _finger_bones:
		var right_finger:=rig.get_bone_name(bone).ends_with(".R")
		_curl_finger(rig,bone,curl if right_finger else left_curl if left_grip else 0.0)
	for bone in _thumb_bones:
		var right_thumb:=rig.get_bone_name(bone).ends_with(".R")
		_curl_finger(rig,bone,(curl if right_thumb else left_curl if left_grip else 0.0)*.65)

func _curl_finger(rig: Skeleton3D,bone: int,curl: float) -> void:
	var finger_pose := rig.get_bone_global_pose(bone)
	# Finger bones extend along local Y; flexion is negative local X. The
	# metacarpal stays almost straight while the actual phalanges wrap the grip.
	var angle := -curl*0.1 if rig.get_bone_name(bone).contains("1.") else -curl
	finger_pose.basis=finger_pose.basis*Basis(Vector3.RIGHT,angle)
	rig.set_bone_global_pose(bone,finger_pose)

func _solve(rig: Skeleton3D,up: int,low: int,end: int,target: Vector3,side: float) -> void:
	if up<0 or low<0 or end<0:return
	var xf := rig.global_transform
	var shoulder := (xf*rig.get_bone_global_pose(up)).origin
	var elbow := (xf*rig.get_bone_global_pose(low)).origin
	var hand := (xf*rig.get_bone_global_pose(end)).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(hand)
	if a < 0.001 or b < 0.001: return
	var direction := (target-shoulder).normalized()
	var reach := clampf(shoulder.distance_to(target),absf(a-b)+0.003,a+b-0.003)
	target = shoulder+direction*reach
	var along := (a*a+reach*reach-b*b)/(2.0*reach)
	var bend := player.global_basis*Vector3(0.4*side,-1,0)
	bend = (bend-direction*bend.dot(direction)).normalized()
	var desired_elbow := shoulder+direction*along+bend*sqrt(maxf(0.0,a*a-along*along))
	_rotate_segment(rig,up,elbow-shoulder,desired_elbow-shoulder)
	elbow = (xf*rig.get_bone_global_pose(low)).origin
	hand = (xf*rig.get_bone_global_pose(end)).origin
	_rotate_segment(rig,low,hand-elbow,target-elbow)

func _rotate_segment(rig: Skeleton3D,bone: int,from: Vector3,to: Vector3) -> void:
	if from.length_squared()<0.000001 or to.length_squared()<0.000001: return
	var pose := rig.global_transform*rig.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(from.normalized(),to.normalized()))*pose.basis
	rig.set_bone_global_pose(bone,rig.global_transform.affine_inverse()*pose)
