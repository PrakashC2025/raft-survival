extends Node3D
## Follow the actual animated wrist. Import bone scale is removed so a 100x
## armature never stretches the weapon or changes its muzzle distance.
var skeleton: Skeleton3D
var wrist := -1
var grip_basis := Basis.IDENTITY
static func attach(weapon: Node3D, body: Node3D) -> void:
	var follower := load("res://scripts/rope_hand_grip.gd").new() as Node3D
	follower.name = "AnimatedHandGrip"
	weapon.add_child(follower)
	for candidate in body.find_children("*","Skeleton3D",true,false):
		var rig := candidate as Skeleton3D
		var bone := rig.find_bone("Wrist.R")
		if bone < 0: continue
		follower.set("skeleton",rig)
		follower.set("wrist",bone)
		var hand_basis := (rig.global_transform*rig.get_bone_global_pose(bone)).basis.orthonormalized()
		follower.set("grip_basis",hand_basis.inverse()*body.global_basis.orthonormalized())
		follower.call("_process",0.0)
		return
func _process(_delta: float) -> void:
	if skeleton == null or wrist < 0: return
	var hand := skeleton.global_transform*skeleton.get_bone_global_pose(wrist)
	var weapon := get_parent() as Node3D
	var orientation := hand.basis.orthonormalized()*grip_basis
	var palm := hand.origin+hand.basis*Vector3(0,0.00085,0)
	# Place the centre of the pistol grip in the palm rather than its receiver.
	weapon.global_transform = Transform3D(orientation.scaled(Vector3.ONE*0.8),palm-orientation*Vector3(0,-0.055,-0.04)*0.8)
