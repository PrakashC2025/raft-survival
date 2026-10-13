extends SceneTree
var checks:=0
var failures:=0
var player: CharacterBody3D
var preview:=false

func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int) -> void:
	for unused in count:await physics_frame
func shot(label: String) -> void:
	if not preview:return
	await process_frame;await RenderingServer.frame_post_draw
	if label=="airborne":
		check(not (player.get("_third_person_launcher") as Node3D).visible,"Airborne movement stows the idle launcher and frees both recorded arms")
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/jump-"+label+".png")==OK,"Rendered "+label+" jump pose")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(40).timeout.connect(func():push_error("FAIL: jump timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,720)
	root.get_node("Stats").set("enabled",false)
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	for child in scene.get_children():
		if str(child.name) not in ["Player","Sky3D"]:scene.remove_child(child);child.free()
	var packed:=PackedScene.new();packed.pack(scene);scene.free()
	change_scene_to_packed(packed);await scene_changed
	player=current_scene.get_node("Player")
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	var floor_body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(12,1,12)
	collider.shape=box;floor_body.add_child(collider);current_scene.add_child(floor_body);floor_body.position.y=-.5
	var floor_mesh:=MeshInstance3D.new();var visual_box:=BoxMesh.new();visual_box.size=box.size;floor_mesh.mesh=visual_box;floor_body.add_child(floor_mesh)
	player.global_position=Vector3(0,1.1,0);player.velocity=Vector3.ZERO;player.is_swimming=false
	player.cam_mode=1;player.call("_apply_camera_mode")
	var camera:=Camera3D.new();camera.fov=45;current_scene.add_child(camera)
	camera.position=Vector3(2.8,2,-4.8);camera.look_at(Vector3(0,.75,0));camera.current=true
	await frames(12)
	for unused in 12:
		await physics_frame;player.velocity=Vector3(0,-2,0);player.move_and_slide()
	check(player.is_on_floor(),"Real character settles onto the collision floor")
	player.call("_update_survivor_animation",false)
	var animator: AnimationPlayer=player.get("_survivor_animator")
	var clip_name: String=player.call("_find_survivor_clip",animator,"Jump")
	check(not clip_name.is_empty() and animator.get_animation(clip_name).loop_mode==Animation.LOOP_NONE,"Character has a non-looping Jump clip")
	var rig:=player.get_node("Body/BeachSurvivor").find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var knee:=rig.find_bone("LowerLeg.L")
	if knee<0:check(false,"Imported character retains the gameplay knee binding");quit(1);return
	var resting:=rig.get_bone_pose_rotation(knee)
	await shot("grounded")
	var start_y:=player.position.y
	Input.action_press("jump");await physics_frame
	player.call("_update_land",1.0/60.0,Vector3.ZERO,false);Input.action_release("jump")
	check(is_equal_approx(player.velocity.y,4.9),"The existing jump input applies the slightly stronger impulse")
	player.move_and_slide();player.call("_update_survivor_animation",false)
	check(not player.is_on_floor() and str(player.get("_survivor_animation"))==clip_name,"Takeoff selects Jump instead of Idle")
	Input.action_press("jump");await physics_frame;var before_retry:=player.velocity.y
	player.call("_update_land",1.0/60.0,Vector3.ZERO,false);Input.action_release("jump")
	check(player.velocity.y<before_retry,"Airborne input cannot trigger a second land jump")
	var maximum:=player.position.y
	var apex_captured:=false
	var knee_changed:=false
	for unused in 60:
		await physics_frame
		player.velocity.y-=player.GRAVITY*player.get_physics_process_delta_time()
		player.move_and_slide();player.call("_update_survivor_animation",false)
		maximum=maxf(maximum,player.position.y)
		if not apex_captured and player.velocity.y<=0:
			apex_captured=true;knee_changed=resting.angle_to(rig.get_bone_pose_rotation(knee))>.05
			await shot("airborne")
		if player.is_on_floor():break
	print("JUMP measured rise ",maximum-start_y," metres")
	check(maximum-start_y>.55 and maximum-start_y<.72,"Real collision movement rises about two-thirds of a metre")
	check(knee_changed,"Actual skeleton bends its knees around the jump apex")
	var landed_clip:=str(player.get("_survivor_animation")).get_file()
	check(player.is_on_floor() and landed_clip in ["Land","Idle"],"Landing selects the grounded recovery pose")
	for unused in 18:
		await physics_frame;player.call("_update_survivor_animation",false)
	check(str(player.get("_survivor_animation")).get_file()=="Idle","Landing recovery blends back to idle")
	player.is_swimming=true;player.call("_update_survivor_animation",false)
	check(str(player.get("_survivor_animation")).get_file() in ["Swim","TreadWater"] and is_equal_approx(player.WATER_JUMP_VELOCITY,2.8),"Swimming keeps its separate animation and existing upward impulse")
	player.is_swimming=false;player.cam_mode=0;player.call("_apply_camera_mode")
	check(not player.get_node("Body").visible,"First-person mode keeps the full character hidden")
	current_scene.queue_free();await frames(8)
	print("JUMP: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
