extends SceneTree
const ROOF:=preload("res://scripts/smart_roof.gd")
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var built: Node3D
var inv: Node
var action: Node
var inspect_camera: Camera3D
func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: survival repairs timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
	await process_frame
func shot(label: String) -> Image:
	if not preview:return null
	await frames(5);await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	check(picture.save_png("C:/GodotProjects/raft-survival/build/repairs-"+label+".png")==OK,"Rendered "+label)
	return picture
func piece(kind: String,at: Vector3,yaw: float=0) -> Node3D:
	var result: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name=kind+"_Repair_%d"%result.get_instance_id()
	result.transform=Transform3D(Basis(Vector3.UP,yaw),at);built.add_child(result);result.add_to_group("build_surface")
	return result
func arrow_tip_faces_forward(arrow: Node3D,bounds: AABB) -> bool:
	var front:=AABB();var back:=AABB();var has_front:=false;var has_back:=false
	for child in arrow.get_children():
		if not child is MeshInstance3D:continue
		var mesh:=child as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3=mesh.transform*vertex
				if point.z<bounds.position.z+.001:
					front=front.expand(point) if has_front else AABB(point,Vector3.ZERO);has_front=true
				if point.z>bounds.end.z-.001:
					back=back.expand(point) if has_back else AABB(point,Vector3.ZERO);has_back=true
	return has_front and has_back and Vector2(front.size.x,front.size.y).length()<Vector2(back.size.x,back.size.y).length()*.5
func roof_probe() -> void:
	piece("Foundation",Vector3(12,0,0))
	var last_wall: Node3D
	for floor_index in 3:
		var floor_height:=.15+floor_index*2.65
		for side in 4:
			last_wall=piece("Wall",Vector3(12+sin(side*PI/2),floor_height+1.25,cos(side*PI/2)),side*PI/2)
		if floor_index<2:piece("Roof",Vector3(12,floor_height+2.575,0))
	await frames()
	player.global_position=raft.to_global(Vector3(12,6.4,0))
	player.aim_valid=true;player.aim_collider=last_wall;player.aim_point=last_wall.global_position;player.aim_normal=last_wall.global_basis.z
	var solved: Dictionary=player.call("_resolve_placement","Roof",player.aim_point)
	check(solved.get("valid",false) and solved.has("roof_plan"),"Third-floor room gets an automatic ceiling plan")
	if not solved.get("valid",false):return
	check(solved.roof_plan.transforms.size()==1 and absf(raft.to_local(solved.transform.origin).y-8.025)<.001,"Third-floor ceiling is at 8.025m and ignores occupied lower ceilings")
	var second:=ROOF.plan(raft,raft.to_global(Vector3(12,4.05,0)),null,false,5.375)
	check(second.get("occupied",false),"An occupied second-floor roof is checked separately from the third floor")
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find("Roof"))
	player.call("_update_build_preview")
	check(player.build_valid and player._ghost_valid_mat.albedo_color.a<.4 and player._ghost_valid_mat.albedo_color.b>player._ghost_valid_mat.albedo_color.g,"Roof preview is translucent cyan instead of an opaque green ceiling")
	inspect_camera.global_position=raft.to_global(Vector3(17,10,7));inspect_camera.look_at(raft.to_global(Vector3(12,5,0)));inspect_camera.current=true
	await shot("third-floor-roof-preview")
	var wood: int=inv.total("Wood");var rope: int=inv.total("Rope")
	player._smart_roof_plan=solved.roof_plan;player.call("_build_smart_roof");await frames()
	check(inv.total("Wood")==wood-8 and inv.total("Rope")==rope-1,"Third-floor roof commits once and spends exactly one tile recipe")
	check(ROOF.plan(raft,raft.to_global(Vector3(12,6.7,0)),null,false,8.025).get("occupied",false),"The completed third-floor ceiling cannot be placed twice")
	var extension: Dictionary=player.call("_resolve_roof_plane_tile",raft.to_global(Vector3(14.2,8.025,0)),player.ghost)
	check(extension.has("transform") and absf(raft.to_local(extension.transform.origin).y-8.025)<.001,"Roof extension selects the third-floor chain instead of a lower roof at the same grid cell")
	await shot("third-floor-roof-built")
	if player.build_mode:player.call("_toggle_build")
	player._smart_roof_plan={};action.stop()
func fish_and_sand_probe() -> void:
	var sea:=current_scene.get_node("UnderwaterWorld")
	var school:=sea.get_node("OpenOceanFish")
	school.set_process(false)
	player.global_position=Vector3(0,-5,-40);player.is_swimming=true;player.active_item="";player.cam_mode=0;player.call("_apply_camera_mode");player.call("_update_hand_item")
	player.camera.current=true;player.camera.global_position=Vector3(0,-4.2,-40);player.camera.global_rotation=Vector3.ZERO
	school.global_position=Vector3(0,-5.5,-51);school._centre=Vector3.ZERO;school._target=Vector3.ZERO;school._process(.1)
	check(school.follow_diver and school.visible and school._parts[0].multimesh.instance_count==24,"A 24-fish instanced school is visible near the swimmer in open ocean")
	check(school.global_position.distance_to(player.global_position)<16,"Nearby fish do not require travelling to a distant dive site")
	await shot("open-ocean-fish")
	var sand_target:=Vector3(0,-6.1,-40.8)
	action.play("scoop",1.15,sand_target);action.elapsed=.20;action.call("_advance_feedback")
	check(not action._view_tool.get_node("PalmSand").visible,"Sand gathering starts with an empty reaching hand")
	action.elapsed=.64;action.call("_advance_feedback");action.call("_process",0.0)
	check(action._view_tool.get_node("PalmSand").visible and action._tool.get_node("PalmSand").visible,"Sand appears in the cupped palm after the scoop in both views")
	check(action._view_tool.find_children("*","Node3D",true,false).size()>2 and action.sample_pose().right.y<.1,"The collection pose reaches down with two visible hands")
	player.call("_update_hand_sway",0.0)
	await shot("sand-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode");action.call("_process",0.0)
	inspect_camera.global_position=player.global_position+Vector3(1.8,1.0,-1.5);inspect_camera.look_at(player.global_position);inspect_camera.current=true
	await shot("sand-third-person")
	action.stop();player.is_swimming=false
func birds_and_bow_probe() -> void:
	var flock:=current_scene.get_node("OceanBirds")
	flock.set_physics_process(false);flock._migration_cycle=0;flock._migration_anchor=Vector3(0,2,-60);flock._time=10;flock._physics_process(0)
	check(flock.migrating and flock._birds.size()==8 and flock._birds.all(func(bird):return bird.root.visible),"Eight migrating birds share a visible flock pass")
	var first_velocity: Vector3=flock.bird_velocity(0)
	check(first_velocity.dot(flock.bird_velocity(6))>35,"Flock members travel in the same direction instead of circling separately")
	flock._time=40;flock._physics_process(0)
	check(flock._birds.all(func(bird):return not bird.root.visible and bird.target.collision_layer==0),"The group leaves a quiet interval without invisible hunt targets")
	flock._time=10;flock._physics_process(0)
	player.cam_mode=0;player.call("_apply_camera_mode");player.global_position=Vector3(0,6.2,-38)
	inv.add("Bow",1);inv.add("Arrow",3);player.get_node("SurvivalServices").equip_owned("Bow");action.stop()
	player.camera.global_position=Vector3(0,7,-38);player.camera.look_at(flock._birds[0].root.global_position);player.camera.current=true
	var equipment:=player.get_node("SurvivalEquipment");equipment.set_physics_process(false);equipment.cooldown=0
	var arrow_bounds: AABB=preload("res://scripts/vegetation_visual.gd").local_bounds(equipment._arrow_mesh)
	check(absf(arrow_bounds.size.z-.72)<.01 and arrow_bounds.size.x<.10 and arrow_bounds.size.y<.10,"Imported arrows have a visible 72cm shaft aligned with the projectile direction")
	check(arrow_tip_faces_forward(equipment._arrow_mesh,arrow_bounds),"The sharp arrow tip faces forward and the wider nock trails behind")
	equipment.drawing=true;equipment.draw_time=1.1;equipment.set_aiming(true);action.call("_process",0.0);player.call("_update_hand_sway",0.0)
	var solution: Dictionary=equipment.shot_solution(1.0)
	var travel: float=Vector2(solution.target.x-solution.origin.x,solution.target.z-solution.origin.z).length()/Vector2(solution.velocity.x,solution.velocity.z).length()
	check((solution.origin+solution.velocity*travel+Vector3.DOWN*4.9*travel*travel).distance_to(solution.target)<.01,"The aimed arrow's ballistic path reaches its reticle target")
	player.get_node("CanvasLayer").show()
	for child in player.get_node("CanvasLayer").get_children():
		if child is Control and child.name!="Crosshair":child.set_process(false);child.hide()
	await shot("bow-aim-first-person")
	player.get_node("CanvasLayer").hide()
	var aim_camera: Transform3D=player.camera.global_transform
	player.cam_mode=1;player.call("_apply_camera_mode");action.call("_process",0.0)
	inspect_camera.global_position=player.global_position+Vector3(-2,1.1,1.6);inspect_camera.look_at(player.global_position+Vector3.UP*.3);inspect_camera.current=true
	await shot("bow-aim-third-person")
	player.cam_mode=0;player.call("_apply_camera_mode");player.camera.global_transform=aim_camera;player.camera.current=true
	var ammo: int=inv.total("Arrow");equipment.call("_fire")
	check(inv.total("Arrow")==ammo-1 and equipment._arrows.size()==1,"A real aimed bow release creates one arrow and spends one ammo")
	for unused in 100:
		flock._physics_process(1.0/60.0);equipment.call("_physics_process",1.0/60.0);await frames(1)
		if flock._birds.any(func(bird):return bird.state=="falling"):break
	check(flock._birds.any(func(bird):return bird.state=="falling"),"An aimed ballistic arrow hits a moving migrating bird without repositioning the projectile")
	equipment.set_aiming(false);equipment.cancel_draw();action.stop()
	inspect_camera.global_position=Vector3(0,6,-35);inspect_camera.look_at(Vector3(0,15,-60));inspect_camera.current=true
	await shot("migrating-birds")
func sky_probe() -> void:
	var sky:=current_scene.get_node("Sky3D");var clock:=sky.get_node("TimeOfDay");var dome:=sky.get_node("SkyDome")
	clock.set_process(false);dome.set_process(false);clock.current_time=12.0
	var atmosphere:=current_scene.get_node("OceanAtmosphere");atmosphere.set_process(false);atmosphere.call("_process",.5)
	check(is_zero_approx(float(dome.sky_material.get_shader_parameter("evening_rotation"))),"Daytime sky photograph no longer rotates with the sun's azimuth")
	inspect_camera.global_position=Vector3(0,3,-35);inspect_camera.global_rotation=Vector3.ZERO;inspect_camera.current=true
	var before: Image=await shot("sky-before-clouds")
	var offset: Vector2=dome._panorama_cloud_position;dome.process_tick(40.0)
	check(dome._panorama_cloud_position.distance_to(offset)>.1,"Cloud drift advances independently while the celestial clock is held still")
	var after: Image=await shot("sky-after-clouds")
	if preview:
		check(before.get_pixel(100,350).is_equal_approx(after.get_pixel(100,350)),"A fixed horizon pixel stays stationary while clouds drift")
		for hour in [6.25,18.3,22.0]:
			clock.current_time=hour;atmosphere.call("_process",.5)
			await shot("sky-"+str(hour))
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	for unused in 2400:
		await frames(1)
		if current_scene.get_node("UnderwaterWorld").prepared and player.get_node("SurvivalAction").hands_prepared and player.restoration_complete:break
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false);player.get_node("SurvivalProgression").set_process(false);player.get_node("RainSystem").stop_rain()
	action=player.get_node("SurvivalAction");action.set_process(false)
	player.get_node("CanvasLayer").hide()
	inspect_camera=Camera3D.new();current_scene.add_child(inspect_camera)
	await roof_probe();await fish_and_sand_probe();await birds_and_bow_probe();await sky_probe()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("SURVIVAL REPAIRS SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
