extends Node
## Correct the legacy FBX arm retarget pose; maintain a natural relaxed stance.
var skeleton: Skeleton3D
var arms: Array = []
func _ready() -> void:
	var found := get_parent().find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		set_process(false)
		return
	skeleton = found[0]
	for name in ["LeftArm", "RightArm"]:
		var index := skeleton.find_bone(name)
		if index >= 0:
			var rest := skeleton.get_bone_global_rest(index)
			arms.append([index, (rest.basis.inverse() * Vector3.BACK).normalized(), -1.0])
func _process(_delta: float) -> void:
	for arm in arms:
		skeleton.set_bone_pose_rotation(int(arm[0]), Quaternion(arm[1], float(arm[2]) * 1.2))

