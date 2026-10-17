extends Node3D
## Follow the actual animated wrist. Import bone scale is removed so a 100x
## armature never stretches the weapon or changes its muzzle distance.
var skeleton: Skeleton3D
var wrist := -1
var grip_basis := Basis.IDENTITY
var owner_body: Node3D
var upright := false
var grip_offset := Vector3(0,-0.055,-0.04)
var animated_tool := false
var palm_clearance := 0.0
static func attach(weapon: Node3D, body: Node3D) -> void:
	var follower := load("res://scripts/rope_hand_grip.gd").new() as Node3D
	follower.name = "AnimatedHandGrip"
	follower.set("owner_body", body)
	weapon.add_child(follower)
	for candidate in body.find_children("*","Skeleton3D",true,false):
		var rig := candidate as Skeleton3D
		var bone := rig.find_bone("Wrist.R")
		if bone < 0: continue
		follower.set("skeleton",rig)
		follower.set("wrist",bone)
		var pose := rig.get_node_or_null("HeldArmPose")
		if pose == null:
			pose = load("res://scripts/held_arm_pose.gd").new()
			pose.name = "HeldArmPose"
			pose.set("player",body.get_parent())
			pose.set("upper",rig.find_bone("UpperArm.R"))
			pose.set("lower",rig.find_bone("LowerArm.R"))
			pose.set("wrist",bone)
			rig.add_child(pose)
		pose.connect("modification_processed",Callable(follower,"_process").bind(0.0))
		var hand_basis := (rig.global_transform*rig.get_bone_global_pose(bone)).basis.orthonormalized()
		follower.set("grip_basis",hand_basis.inverse()*body.global_basis.orthonormalized())
		follower.call("_process",0.0)
		return
func _process(_delta: float) -> void:
	if skeleton == null or wrist < 0: return
	var hand := skeleton.global_transform*skeleton.get_bone_global_pose(wrist)
	var weapon := get_parent() as Node3D
	# Wrist animation supplies position, but aim supplies direction. Bone roll
	# must never point the barrel sideways or backwards while walking.
	var orientation := owner_body.global_basis.orthonormalized()
	var player := owner_body.get_parent()
	if not upright and player.get("camera") is Camera3D:
		orientation = (player.get("camera") as Camera3D).global_basis.orthonormalized()
	if animated_tool:
		orientation=owner_body.global_basis.orthonormalized()
		var action := player.get_node_or_null("SurvivalAction")
		if action!=null:
			var pose: Dictionary=action.call("sample_pose")
			orientation=orientation*Basis.from_euler(pose.view_rot)
		if str(player.get("active_item"))=="Bow":orientation=(player.get("camera") as Camera3D).global_basis.orthonormalized()
	var palm := hand.origin+hand.basis*Vector3(0,0.00085,0)
	palm-=hand.basis.z.normalized()*palm_clearance
	# Place the centre of the pistol grip in the palm rather than its receiver.
	var grip := grip_offset if not upright else Vector3(0,-0.12,0)
	weapon.global_transform = Transform3D(orientation.scaled(Vector3.ONE*0.8),palm-orientation*grip*0.8)
