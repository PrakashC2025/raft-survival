extends SceneTree
## Offline pose measurements, in isolated storage only.
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var body:=Node3D.new();body.scale=Vector3.ONE*1.1;body.position.y=-.042;root.add_child(body)
	var avatar:=load("res://models/mixamo_survivor.glb").instantiate() as Node3D
	avatar.scale=Vector3.ONE*.9;avatar.position.y=-.84;avatar.rotation.y=PI;body.add_child(avatar)
	var rig:=avatar.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var animator:=avatar.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	for clip_name in ["Idle","Swim","TreadWater","Jump","Land"]:
		var clip:=animator.get_animation(clip_name)
		animator.play(clip_name)
		for index in 11:
			var time_value:=clip.length*index/10.0
			animator.seek(time_value,true);animator.advance(0)
			var points:=[]
			for bone_name in ["Hips","Head","Foot.L","Foot.R","Wrist.L","Wrist.R"]:
				points.append((rig.global_transform*rig.get_bone_global_pose(rig.find_bone(bone_name))).origin)
			print(clip_name," ",snappedf(time_value,.001)," ",points)
	body.free()
	var document:=FBXDocument.new();var state:=FBXState.new()
	if document.append_from_file("C:/Users/praka/Downloads/Standing Jump.fbx",state)!=OK:quit(1);return
	var source:=document.generate_scene(state,30);root.add_child(source)
	var source_rig:=source.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var source_animator:=source.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	var name_value: String=""
	for candidate in source_animator.get_animation_list():
		if str(candidate)!="RESET" and source_animator.get_animation(candidate).get_track_count()>0:name_value=str(candidate);break
	print("SOURCE_CLIPS ",source_animator.get_animation_list()," SELECTED ",name_value)
	var source_clip:=source_animator.get_animation(name_value)
	var hip_track := -1
	for track in source_clip.get_track_count():
		if source_clip.track_get_type(track)==Animation.TYPE_POSITION_3D and str(source_clip.track_get_path(track)).contains("Hips"):hip_track=track;break
	var positions:=[]
	for frame in ceili(source_clip.length*60)+1:
		var time_value:=minf(frame/60.0,source_clip.length)
		var value:=source_clip.position_track_interpolate(hip_track,time_value)
		positions.append([time_value,value.x,value.y,value.z])
	var output:=FileAccess.open("C:/GodotProjects/raft-survival/build/mixamo-jump-root.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(positions));output.close()
	source_animator.play(name_value)
	for frame in ceili(source_clip.length*10)+1:
		var time_value:=minf(frame*.1,source_clip.length)
		source_animator.seek(time_value,true);source_animator.advance(0)
		var points:=[]
		for bone_name in ["mixamorig:Hips","mixamorig:LeftFoot","mixamorig:RightFoot"]:
			var index:=source_rig.find_bone(bone_name)
			if index<0:index=source_rig.find_bone(bone_name.replace(":","_"))
			points.append((source_rig.global_transform*source_rig.get_bone_global_pose(index)).origin)
		print("SOURCE_JUMP ",snappedf(time_value,.001)," ",points)
	source.free();quit()
