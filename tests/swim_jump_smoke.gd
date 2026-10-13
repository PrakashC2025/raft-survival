extends SceneTree
var checks := 0
var failures := 0
var preview := false
var player: CharacterBody3D
var ocean: Node3D
var review_camera: Camera3D
var rig: Skeleton3D

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)
func frames(count: int) -> void:
	for unused in count: await physics_frame
func step(count: int) -> void:
	for index in count:
		# Static water/deck fixtures can simulate three fixed steps per capture
		# frame; this preview does not measure frame rate or phone performance.
		if not preview or index%3==0:await physics_frame
		player.call("_physics_process",1.0/60.0)
		player.get_node("SurvivalAction").call("_process",0.0)
		player.get_node("SurvivalProgression").call("_update_back_tank")
func bone(name_value: String) -> Vector3:
	return (rig.global_transform*rig.get_bone_global_pose(rig.find_bone(name_value))).origin
func shot(label: String, offset: Vector3) -> void:
	if not preview: return
	review_camera.global_position=player.global_position+offset
	review_camera.look_at(player.global_position+Vector3(0,.1,0))
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/movement-"+label+".png")==OK,"Rendered actual "+label+" movement in the ocean scene")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	create_timer(70).timeout.connect(func():push_error("FAIL: swimming transition timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args(); root.size=Vector2i(1280,720)
	root.get_node("Stats").set("enabled",false)
	root.get_node("Inventory").call("new_game_reset",true)
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	for child in scene.get_children():
		if str(child.name) not in ["Player","Raft","Ocean","Sky3D","OceanAtmosphere"]:scene.remove_child(child);child.free()
	var packed:=PackedScene.new();packed.pack(scene);scene.free();change_scene_to_packed(packed);await scene_changed
	player=current_scene.get_node("Player");player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	player.get_node("SurvivalProgression").set_process(false)
	player.get_node("CanvasLayer").hide()
	current_scene.get_node("Raft").set_physics_process(false)
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause");clock.set("current_time",12.0);clock.call("_update_celestial_coords");clock.get_node("Timer").emit_signal("timeout")
	await frames(65)
	current_scene.get_node("OceanAtmosphere").set_process(false)
	ocean=current_scene.get_node("Ocean");ocean.set("wave_height",0.0);ocean.set_process(false)
	var water_material: ShaderMaterial=(ocean as MeshInstance3D).get_active_material(0) as ShaderMaterial
	if water_material!=null:water_material.set_shader_parameter("wave_height",0.0)
	player.cam_mode=1;player.call("_apply_camera_mode")
	rig=player.get_node("Body/BeachSurvivor").find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	if preview:
		review_camera=Camera3D.new();review_camera.fov=48;current_scene.add_child(review_camera);review_camera.current=true
	var animator: AnimationPlayer=player.get("_survivor_animator")
	var progress:=player.get_node("SurvivalProgression")
	check(not progress.get("_back_tank").visible,"Unequipped air tank cannot appear during startup")
	check(animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"Movement and animation use one physics clock")
	var jump_name: String=player.call("_find_survivor_clip",animator,"Jump")
	var landing_name: String=player.call("_find_survivor_clip",animator,"Land")
	check(absf(animator.get_animation(jump_name).length-.70)<.002 and absf(animator.get_animation(landing_name).length-.83)<.002,"Recorded flight and landing use separate correctly trimmed windows")
	player.global_position=Vector3(12,2.0,0);player.velocity=Vector3(0,1,0);player.is_swimming=true
	player.call("_update_swimming_state",0.0,true)
	check(not player.is_swimming and is_equal_approx(player.velocity.y,1.0),"Stale swimming above water clears without erasing airborne momentum")
	player.velocity=Vector3.ZERO;await step(1)
	check(str(player.get("_survivor_animation")).get_file()=="Fall","Dropping toward water selects falling rather than a jump or swim pose")
	# A shallow shelf: feet are wet, but a supported torso is above the water.
	var shelf:=StaticBody3D.new();shelf.position=Vector3(18,-1.05,0);current_scene.add_child(shelf)
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,.2,4);collider.shape=box;shelf.add_child(collider)
	player.global_position=Vector3(18,.05,0);player.velocity=Vector3.ZERO;player.is_swimming=false
	await step(35)
	check(player.is_on_floor() and not player.is_swimming,"Supported shallow-water walking cannot repeatedly activate swimming")
	var camera_transform: Transform3D=player.camera.transform
	player.camera.position.y=-5;player.call("_update_swimming_state",0.0,true)
	check(not player.is_swimming,"A submerged follow camera cannot turn a dry supported body into a swimmer")
	player.camera.transform=camera_transform
	player.global_position=Vector3(12,-.34,0);player.velocity=Vector3.ZERO;player.is_swimming=false
	await step(150)
	check(player.is_swimming and absf(player.position.y-player.SURFACE_TREAD_OFFSET)<.10,"Idle swimmer settles with the torso immersed instead of floating in air")
	check(str(player.get("_survivor_animation")).get_file()=="TreadWater" and bone("Hips").y<-.20 and bone("Head").y>-.03,"Treading keeps the hips under water and the head above it")
	check(player.call("movement_owns_hands") and not player.get("_third_person_launcher").visible,"Default rope launcher is stowed while both arms tread water")
	await shot("treading",Vector3(2.2,1.0,-2.8))
	var left_start:=bone("Wrist.L")-player.global_position
	var right_start:=bone("Wrist.R")-player.global_position
	Input.action_press("move_forward")
	await step(120)
	var left_end:=bone("Wrist.L")-player.global_position
	var right_end:=bone("Wrist.R")-player.global_position
	check(player.is_swimming and absf(player.position.y-player.SURFACE_SWIM_OFFSET)<.12,"Third-person forward swimming follows the surface despite its downward camera angle")
	check(left_start.distance_to(left_end)>.12 and right_start.distance_to(right_end)>.12,"Both recorded arm strokes remain free of idle weapon IK")
	check(str(player.get("_survivor_animation")).get_file()=="Swim" and bone("Hips").y<.02,"Surface stroke keeps the body at the actual waterline")
	progress.set("diving_tank",true);progress.call("_update_back_tank")
	var tank:=progress.get("_back_tank") as Node3D
	var chest: Transform3D=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("Chest"))
	check(tank.visible and tank.global_basis.y.normalized().dot(chest.basis.y.normalized())>.98 and tank.global_position.distance_to(chest.origin)<.30,"Equipped tank follows the recorded swimmer's back instead of standing in air")
	var splash:=player.get("_swim_splash") as GPUParticles3D
	var splash_material := (splash.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	check(splash.emitting and absf(splash.global_position.y)<.05 and splash_material.albedo_texture!=null,"Small rounded splash droplets emit at the actual water surface")
	await shot("surface-swim",Vector3(2.2,1.0,-2.8))
	Input.action_release("move_forward");Input.action_press("jump")
	var highest:=player.position.y
	for unused in 90:
		await step(1);highest=maxf(highest,player.position.y)
	Input.action_release("jump")
	check(highest<.15 and player.is_swimming,"Holding swim-up cannot sustain swimming in clear air")
	player.global_position=Vector3(12,-4,0);player.velocity=Vector3.ZERO;player.is_swimming=true
	Input.action_press("move_forward");Input.action_press("sprint");await step(35)
	check(Vector2(player.velocity.x,player.velocity.z).length()>3.0 and player.position.y< -3.5,"Fast underwater swimming remains available without forced surface buoyancy")
	check(not splash.visible and not splash.emitting,"Deep swimming cannot emit floating rectangular splash particles")
	await shot("underwater-swim",Vector3(2.2,1.0,-2.8))
	Input.action_release("move_forward");Input.action_release("sprint")
	# First person uses both swimming hands even with the default Rope selected.
	player.cam_mode=0;player.call("_apply_camera_mode")
	progress.call("_update_back_tank");check(not tank.visible,"First person hides the third-person back equipment")
	var water_visual: Node3D=load("res://scripts/underwater_world.gd").new()
	water_visual.set("_player",player)
	var hands:=Node3D.new();player.camera.add_child(hands);hands.add_child(Node3D.new());hands.add_child(Node3D.new());water_visual.set("_hands",hands)
	water_visual.call("_process",.016)
	check(hands.visible and hands.get_child(1).visible and not player.get("_fist_node").visible,"First-person swimming shows two hands and hides the idle held fist")
	player.is_swimming=false;water_visual.call("_process",.016)
	check(not hands.visible and player.get("_fist_node").visible,"Leaving water restores normal first-person hand presentation")
	water_visual.free();hands.queue_free()
	player.cam_mode=1;player.call("_apply_camera_mode")
	player.global_position=current_scene.get_node("Raft").global_position+Vector3(0,1.3,0);player.velocity=Vector3.ZERO
	await step(45)
	check(player.is_on_floor() and not player.is_swimming and player.get("_third_person_launcher").visible,"Boarding a dry raft restores grounded motion and the selected tool")
	current_scene.queue_free();await frames(8)
	print("SWIM JUMP: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
