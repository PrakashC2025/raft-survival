extends SceneTree
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int) -> void:
	for unused in count:await physics_frame
func photo(label: String) -> void:
	if not preview:return
	await frames(5);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/mixamo-"+label+".png")==OK,"Rendered human "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(80).timeout.connect(func():push_error("FAIL: Mixamo character timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	root.get_node("Stats").set("enabled",false)
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	for child in scene.get_children():
		if str(child.name) not in ["Player","Raft","Ocean","Sky3D","OceanAtmosphere"]:scene.remove_child(child);child.free()
	var packed:=PackedScene.new();packed.pack(scene);scene.free();change_scene_to_packed(packed);await scene_changed
	player=current_scene.get_node("Player");player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false);current_scene.get_node("Raft").set_physics_process(false)
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause");clock.set("current_time",12.0);clock.call("_update_celestial_coords");clock.get_node("Timer").emit_signal("timeout")
	await frames(70)
	player.global_position=current_scene.get_node("Raft").global_position+Vector3(0,1.1,0)
	player.cam_mode=1;player.call("_apply_camera_mode")
	camera=Camera3D.new();camera.fov=42;current_scene.add_child(camera);camera.current=true
	camera.global_position=player.global_position+Vector3(2.3,.8,-3.7);camera.look_at(player.global_position+Vector3(0,-.05,0))
	var survivor:=player.get_node("Body/BeachSurvivor")
	var rig:=survivor.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var animator: AnimationPlayer=player.get("_survivor_animator")
	check(player.get("_survivor_motion")!=null,"Main game uses the textured Mixamo character and its motion controller")
	var binds_valid:=true
	for name_value in ["Hips","Chest","UpperArm.R","LowerArm.R","Wrist.R","Wrist.L","UpperLeg.L","LowerLeg.L","Foot.R","Index2.R","Thumb2.L"]:binds_valid=binds_valid and rig.find_bone(name_value)>=0
	check(binds_valid,"Imported human retains all gameplay wrist, finger, leg and torso bindings")
	var textured:=0
	for visual in survivor.find_children("*","MeshInstance3D",true,false):
		for surface in visual.mesh.get_surface_count():
			var material:=visual.get_active_material(surface) as StandardMaterial3D
			if material!=null and material.albedo_texture!=null:textured+=1
	check(textured>=5,"Face, hair, clothes, eyes and shoes keep their original textures")
	var clips_valid:=true
	var hip_position_valid:=true
	for name_value in ["Idle","Walk","Run","WalkLeft","WalkRight","WalkBack","Jump","Land","Fall","Swim","TreadWater","TurnLeft","TurnRight","Plant","Harvest","Gather","PickFruit","Water","Work","Hold","Drink"]:
		var clip_name: String=player.call("_find_survivor_clip",animator,name_value)
		if clip_name.is_empty():clips_valid=false;continue
		var clip:=animator.get_animation(clip_name)
		for track in clip.get_track_count():
			if clip.track_get_type(track)!=Animation.TYPE_POSITION_3D:continue
			var baseline: Vector3=clip.track_get_key_value(track,0)
			for key in clip.track_get_key_count(track):
				var value: Vector3=clip.track_get_key_value(track,key)
				hip_position_valid=hip_position_valid and value.is_finite() and absf(value.x-baseline.x)<.001 and absf(value.z-baseline.z)<.001
	check(clips_valid,"All movement, swimming, landing and farming clips are available to the real character")
	check(hip_position_valid,"Motion clips preserve bone lengths and cannot move the character away from its collision body")
	var idle_name: String=player.call("_find_survivor_clip",animator,"Idle")
	animator.play(idle_name);player.set("_survivor_animation",idle_name);animator.seek(.5,true)
	await photo("character")
	check(not rig.find_children("*","SkeletonModifier3D",true,false).is_empty(),"Existing hand contact rig is attached to the new human")
	for name_value in ["Jump","Swim","Plant","Harvest"]:
		var clip_name: String=player.call("_find_survivor_clip",animator,name_value)
		animator.play(clip_name);player.set("_survivor_animation",clip_name);animator.seek(animator.get_animation(clip_name).length*.5,true)
		await photo(name_value.to_lower())
	player.cam_mode=0;player.call("_apply_camera_mode")
	check(not player.get_node("Body").visible,"First person still hides the full human body")
	current_scene.queue_free();await frames(8)
	print("MIXAMO CHARACTER: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
