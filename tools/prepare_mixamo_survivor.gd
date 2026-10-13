extends SceneTree
## Bake one textured Remy and compatible motion clips, without runtime FBX loading.
const ALIASES: Dictionary={"Hips":"Hips","Spine":"Spine","Spine1":"Abdomen","Spine2":"Chest","Neck":"Neck","Head":"Head","Shoulder":"Shoulder","Arm":"UpperArm","ForeArm":"LowerArm","Hand":"Wrist","UpLeg":"UpperLeg","Leg":"LowerLeg","Foot":"Foot","ToeBase":"Toe"}
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var paths:=OS.get_cmdline_user_args()
	if paths.size()>0 and paths[0].ends_with(".json"):
		_build(paths);return
	_inspect(paths)

func canonical(source: String) -> String:
	var name_value:=source.trim_prefix("mixamorig_").trim_prefix("mixamorig:")
	var side:=".L" if name_value.begins_with("Left") else (".R" if name_value.begins_with("Right") else "")
	if not side.is_empty():name_value=name_value.substr(4 if side==".L" else 5)
	if name_value.begins_with("Hand") and name_value.length()>4:name_value=name_value.trim_prefix("Hand")
	return str(ALIASES.get(name_value,name_value))+side

func read_fbx(path: String) -> Node3D:
	var document:=FBXDocument.new();var state:=FBXState.new()
	var result:=document.append_from_file(path,state)
	if result!=OK:push_error("FBX read failed: "+path+" code "+str(result));return null
	var scene:=document.generate_scene(state,30)
	root.add_child(scene)
	return scene

func motion(scene: Node) -> Animation:
	for animator in scene.find_children("*","AnimationPlayer",true,false):
		for name_value in animator.get_animation_list():
			var clip: Animation=animator.get_animation(name_value)
			if clip.get_track_count()>0:return clip
	return null

func _build(paths: PackedStringArray) -> void:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	var project_root:=paths[0].get_base_dir().get_base_dir()
	var downloads:=paths[1]
	var base:=read_fbx(downloads.path_join(config.character_file))
	if base==null:quit(1);return
	var rig:=base.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var bounds:=AABB()
	for visual in base.find_children("*","MeshInstance3D",true,false):bounds=bounds.merge(visual.get_aabb())
	var scale_factor:=1.80/bounds.size.y
	var rest_by_name: Dictionary={}
	for index in rig.get_bone_count():rest_by_name[canonical(rig.get_bone_name(index))]=rig.get_bone_rest(index)
	var library:=AnimationLibrary.new()
	var manifest: Dictionary={"character":"Remy","source":"https://www.mixamo.com/","license":"Adobe Mixamo - royalty-free game use, not CC0","height_m":1.80,"clips":[],"textures":[]}
	manifest["turn_root_yaw"]="Removed Y-axis twist from turn hips; gameplay owns yaw; limb clips retained."
	for spec in config.clips:
		var input_path: String=downloads.path_join(spec.file) if not spec.has("pack") else project_root.path_join("tools/asset_downloads/mixamo/"+str(spec.pack)+"/"+str(spec.file))
		var source:=read_fbx(input_path)
		if source==null:base.free();quit(1);return
		var source_rig:=source.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
		var source_clip:=motion(source)
		if source_clip==null:push_error("No source motion: "+input_path);source.free();base.free();quit(1);return
		var tracks: Dictionary={}
		for track in source_clip.get_track_count():
			var track_path:=source_clip.track_get_path(track)
			if track_path.get_subname_count()==0:continue
			var bone_name:=canonical(str(track_path.get_subname(0)))
			if not rest_by_name.has(bone_name):continue
			var source_index:=source_rig.find_bone(str(track_path.get_subname(0)))
			var target_rest: Transform3D=rest_by_name[bone_name]
			if source_index<0 or target_rest.basis.get_rotation_quaternion().angle_to(source_rig.get_bone_rest(source_index).basis.get_rotation_quaternion())>.01:
				push_error("Incompatible rig in "+input_path+": "+bone_name);source.free();base.free();quit(1);return
			tracks[bone_name+"/"+str(source_clip.track_get_type(track))]=track
		var start_time:=float(spec.get("start_seconds",source_clip.length*float(spec.get("start_fraction",0.0))))
		var end_time:=minf(source_clip.length,float(spec.get("end_seconds",source_clip.length)))
		var animation:=Animation.new()
		animation.length=end_time-start_time;animation.loop_mode=Animation.LOOP_LINEAR if spec.get("loop",false) else Animation.LOOP_NONE
		for bone_name in rest_by_name:
			var target_rest: Transform3D=rest_by_name[bone_name]
			var rotation_track:=animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(rotation_track,NodePath("Rig/Skeleton3D:"+str(bone_name)))
			var input_track: int=int(tracks.get(str(bone_name)+"/"+str(Animation.TYPE_ROTATION_3D),-1))
			if input_track<0:animation.rotation_track_insert_key(rotation_track,0,target_rest.basis.get_rotation_quaternion());continue
			for frame in ceili(animation.length*30)+1:
				var time_value:=minf(float(frame)/30,animation.length)
				var rotation_value := source_clip.rotation_track_interpolate(input_track,time_value+start_time)
				if bone_name == "Hips" and str(spec.name) in ["TurnLeft", "TurnRight", "Jump", "Land"]:
					var rest_rotation := target_rest.basis.get_rotation_quaternion()
					var relative_rotation := rotation_value * rest_rotation.inverse()
					var yaw_twist := Quaternion(0,relative_rotation.y,0,relative_rotation.w).normalized()
					rotation_value = yaw_twist.inverse() * relative_rotation * rest_rotation
				animation.rotation_track_insert_key(rotation_track,time_value,rotation_value)
		var hips_rest: Transform3D=rest_by_name.Hips
		var position_track:=animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track,NodePath("Rig/Skeleton3D:Hips"))
		var hips_track: int=int(tracks.get("Hips/"+str(Animation.TYPE_POSITION_3D),-1))
		for frame in ceili(animation.length*30)+1:
			var time_value:=minf(float(frame)/30,animation.length)
			var position_value:=hips_rest.origin
			if hips_track>=0 and str(spec.name) not in ["Jump","Fall","Swim","TreadWater"]:
				var source_position:=source_clip.position_track_interpolate(hips_track,time_value+start_time)
				var crouch_limit:=float(spec.get("crouch_limit",.95 if spec.get("work",false) else .14))
				position_value.y+=clampf(source_position.y-hips_rest.origin.y,-crouch_limit/scale_factor,.08/scale_factor)
			animation.position_track_insert_key(position_track,time_value,position_value)
		library.add_animation(spec.name,animation)
		var stride:=0.0
		if hips_track>=0:
			var displacement:=source_clip.position_track_interpolate(hips_track,source_clip.length)-source_clip.position_track_interpolate(hips_track,start_time)
			stride=Vector2(displacement.x,displacement.z).length()*scale_factor*.99
		manifest.clips.append({"name":spec.name,"file":input_path.get_file(),"pack":spec.get("pack",""),"sha256":FileAccess.get_sha256(input_path),"seconds":animation.length,"loop":spec.get("loop",false),"stride_m":stride})
		print("BAKED ",spec.name," ",animation.length," seconds")
		source.free()
	for index in rig.get_bone_count():rig.set_bone_name(index,canonical(rig.get_bone_name(index)))
	rig.name="Skeleton3D"
	var texture_cache: Dictionary={}
	for visual in base.find_children("*","MeshInstance3D",true,false):
		# These clips animate bones only. Unused facial morph buffers add load,
		# memory and shader cost without changing the rendered character.
		if visual.mesh.get_blend_shape_count()>0:
			var original_mesh: ArrayMesh=visual.mesh
			var clean_mesh:=ArrayMesh.new()
			for surface in original_mesh.get_surface_count():
				var flags: int=original_mesh.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
				clean_mesh.add_surface_from_arrays(original_mesh.surface_get_primitive_type(surface),original_mesh.surface_get_arrays(surface),[],{},flags)
				clean_mesh.surface_set_material(surface,original_mesh.surface_get_material(surface))
			visual.mesh=clean_mesh
			print("REMOVED UNUSED MORPHS ",visual.name," ",original_mesh.get_blend_shape_count())
		if visual.skin!=null:
			for bind in visual.skin.get_bind_count():
				var bind_name:=str(visual.skin.get_bind_name(bind))
				if not bind_name.is_empty():visual.skin.set_bind_name(bind,canonical(bind_name))
		for surface in visual.mesh.get_surface_count():
			var material:=visual.get_active_material(surface) as StandardMaterial3D
			if material==null:continue
			material.metallic=0.0;material.roughness=.72
			for texture_kind in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture:=material.get_texture(texture_kind)
				if texture==null:continue
				var key:=texture.get_instance_id()
				if not texture_cache.has(key):
					var image_value:=texture.get_image()
					if image_value.is_compressed():image_value.decompress()
					var ratio:=minf(1.0,1024.0/maxi(image_value.get_width(),image_value.get_height()))
					image_value.resize(maxi(1,roundi(image_value.get_width()*ratio)),maxi(1,roundi(image_value.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
					texture_cache[key]=ImageTexture.create_from_image(image_value)
					manifest.textures.append({"width":image_value.get_width(),"height":image_value.get_height()})
				material.set_texture(texture_kind,texture_cache[key])
	for animator in base.find_children("*","AnimationPlayer",true,false):animator.free()
	root.remove_child(base)
	var survivor:=Node3D.new();survivor.name="MixamoSurvivor";root.add_child(survivor)
	base.name="Rig";survivor.add_child(base);base.scale=Vector3.ONE*scale_factor;base.position.y=-bounds.position.y*scale_factor
	var animator:=AnimationPlayer.new();animator.name="AnimationPlayer";survivor.add_child(animator);animator.add_animation_library("",library)
	var export_document:=GLTFDocument.new();var export_state:=GLTFState.new()
	var output_path:=project_root.path_join("models/mixamo_survivor.glb")
	var error:=export_document.append_from_scene(survivor,export_state)
	if error==OK:error=export_document.write_to_filesystem(export_state,output_path)
	if error!=OK:push_error("GLB export failed: "+str(error));survivor.free();quit(1);return
	_restore_joint_names(output_path,rig)
	var manifest_file:=FileAccess.open(project_root.path_join("models/mixamo_survivor.source.json"),FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest,"\t"));manifest_file.close()
	var walk_stride:=1.84;var run_stride:=2.37
	for clip in manifest.clips:
		if float(clip.stride_m)<.6:continue
		if str(clip.name)=="Walk":walk_stride=float(clip.stride_m)
		elif str(clip.name)=="Run":run_stride=float(clip.stride_m)
	var gait_file:=FileAccess.open(project_root.path_join("scripts/mixamo_motion_data.gd"),FileAccess.WRITE)
	gait_file.store_string("extends RefCounted\n## Generated by tools/prepare_mixamo_survivor.gd; included by normal script export.\nconst WALK_STRIDE_M := %.6f\nconst RUN_STRIDE_M := %.6f\n"%[walk_stride,run_stride]);gait_file.close()
	print("EXPORTED ",output_path," clips ",library.get_animation_list().size())
	survivor.free();quit()

func _restore_joint_names(path: String,rig: Skeleton3D) -> void:
	# Godot's scene exporter changes dots to underscores. Bone names themselves
	# can contain dots; restore the established wrist/finger paths in the GLB.
	var data:=FileAccess.get_file_as_bytes(path)
	var json_length:=data.decode_u32(12)
	var document: Dictionary=JSON.parse_string(data.slice(20,20+json_length).get_string_from_utf8())
	var names: Dictionary={}
	for index in rig.get_bone_count():
		var bone_name:=str(rig.get_bone_name(index))
		names[bone_name.replace(".","_")]=bone_name
	for skin in document.get("skins",[]):
		for joint in skin.joints:
			var node: Dictionary=document.nodes[int(joint)]
			if names.has(str(node.get("name",""))):node.name=names[str(node.name)]
	var json_bytes:=JSON.stringify(document).to_utf8_buffer()
	while json_bytes.size()%4!=0:json_bytes.append(32)
	var rest:=data.slice(20+json_length)
	var output:=PackedByteArray();output.resize(20)
	output.encode_u32(0,0x46546C67);output.encode_u32(4,2)
	output.encode_u32(8,20+json_bytes.size()+rest.size())
	output.encode_u32(12,json_bytes.size());output.encode_u32(16,0x4E4F534A)
	output.append_array(json_bytes);output.append_array(rest)
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(output);file.close()

func _inspect(paths: PackedStringArray) -> void:
	var reference_rests: Dictionary={}
	for path in paths:
		var document:=FBXDocument.new()
		var state:=FBXState.new()
		var result:=document.append_from_file(path,state)
		if result!=OK:push_error("FBX read failed: "+path+" code "+str(result));quit(1);return
		var scene:=document.generate_scene(state,30)
		root.add_child(scene)
		print("FBX ",path.get_file())
		for rig in scene.find_children("*","Skeleton3D",true,false):
			print("SKELETON ",rig.get_path()," scale ",rig.global_basis.get_scale()," bones ",rig.get_bone_count())
			var difference:=0.0
			for index in rig.get_bone_count():
				var bone_name: String=rig.get_bone_name(index)
				var rest: Transform3D=rig.get_bone_rest(index)
				if reference_rests.has(bone_name):difference=maxf(difference,(reference_rests[bone_name] as Transform3D).basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion()))
				else:reference_rests[bone_name]=rest
			print("REST ROTATION DIFFERENCE ",difference)
		for animator in scene.find_children("*","AnimationPlayer",true,false):
			for clip in animator.get_animation_list():
				var animation: Animation=animator.get_animation(clip)
				print("CLIP ",clip," length ",animation.length," tracks ",animation.get_track_count())
		var triangles:=0
		for visual in scene.find_children("*","MeshInstance3D",true,false):
			print("MESH ",visual.name," bounds ",visual.get_aabb()," basis ",visual.global_basis.get_scale())
			for surface in visual.mesh.get_surface_count():
				triangles+=visual.mesh.surface_get_array_index_len(surface)/3
		print("TRIANGLES ",triangles)
		scene.free()
	quit()
