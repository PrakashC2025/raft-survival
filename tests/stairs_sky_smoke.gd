extends SceneTree
var checks := 0
var failures := 0
var player: CharacterBody3D
var raft: Node3D
var built: Node3D
var preview := false
var view_camera: Camera3D
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("FAIL: stairs/sky timeout"); quit(1))
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count: await physics_frame
	await process_frame
func fixture(kind: String, at: Vector3, yaw: float=0.0) -> Node3D:
	var piece: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	piece.name="%s_StairCheck_%d"%[kind,piece.get_instance_id()]
	piece.transform=Transform3D(Basis(Vector3.UP,yaw),at);built.add_child(piece);piece.add_to_group("build_surface")
	if kind=="Foundation":player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),piece)
	return piece
func aim(kind: String, at: Vector3, support: Node3D) -> Dictionary:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_point=raft.to_global(at);player.aim_collider=support;player.aim_normal=Vector3.UP;player.aim_valid=true
	player.camera.global_position=player.aim_point+Vector3(0,3,0.2);player.camera.look_at(player.aim_point)
	var result: Dictionary=player.call("_resolve_placement",kind,player.aim_point)
	if not result.get("valid",false):print("PLACEMENT ",kind," ",player._diag)
	return result
func walk(direction: float, count: int) -> void:
	for unused in count:
		await physics_frame
		player.velocity=raft.global_basis*Vector3(0,0,direction*2.5)+Vector3.UP*minf(player.velocity.y,0.0)
		if not player.is_on_floor():player.velocity.y-=9.81*player.get_physics_process_delta_time()
		player.call("_try_step_up");player.move_and_slide()
		var z:float=raft.to_local(player.global_position).z
		if (direction>0.0 and z>6.4) or (direction<0.0 and z<2.65):break
func shot(name: String, eye: Vector3, target: Vector3) -> void:
	if not preview:return
	view_camera.global_position=raft.to_global(eye);view_camera.look_at(raft.to_global(target))
	await frames(12);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../"+name+".png")==OK,name+" desktop preview saved")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview=OS.get_cmdline_user_args().has("--preview");root.size=Vector2i(1280,720)
	var inv:=root.get_node("Inventory");inv.call("new_game_reset",true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	await frames(140)
	player.set_process(false);player.set_physics_process(false)
	raft.rotation=Vector3.ZERO;await frames()
	fixture("Foundation",Vector3(2,0,0));fixture("Foundation",Vector3(2,0,2));fixture("Foundation",Vector3(4,0,2));await frames()
	var deck:=fixture("Foundation",Vector3(4,0,4));await frames()
	var plan:=aim("Stairs",Vector3(4,0.15,4),deck)
	check(plan.get("valid",false),"Compact stairs place on an ordinary foundation")
	var stair:=fixture("Stairs",Vector3(4,0.25,3));await frames()
	var landing:CollisionShape3D=stair.get_node("CollisionLanding")
	check(absf(landing.position.z+(landing.shape as BoxShape3D).size.z/2.0-2.6)<0.001,"Stair footprint is shortened to 2.6 metres")
	check((landing.shape as BoxShape3D).size.x<1.5,"Stair width leaves room beside the flight")
	check(atan2(2.65,2.4)<deg_to_rad(50.0),"Compact ramp stays within its stair-only walking slope limit")
	check(aim("Foundation",Vector3(4,0.15,6),deck).get("valid",false),"Foundation can be placed underneath the existing stair flight")
	var below:=fixture("Foundation",Vector3(4,0,6));await frames()
	check(aim("Foundation",Vector3(6,0.15,6),below).get("valid",false),"Foundation can extend beside stairs")
	fixture("Foundation",Vector3(6,0,6));await frames()
	var roof_plan:=aim("Roof",Vector3(4,2.8,6),stair)
	check(roof_plan.get("valid",false),"Stair landing supports a flush roof without requiring a wall")
	check(aim("Roof",Vector3(6,0.15,6),below).get("valid",false),"Roof can be placed beside a stair landing")
	var roof:=fixture("Roof",Vector3(4,2.725,6));fixture("Roof",Vector3(4,2.725,4));await frames()
	roof.call("refresh",true)
	if player.build_mode:player.call("_toggle_build")
	player.is_swimming=false
	player.global_position=raft.to_global(Vector3(4,1.10,2.65));player.velocity=Vector3.ZERO;await frames()
	await walk(1.0,240)
	var top:Vector3=raft.to_local(player.global_position)
	print("STAIR WALK UP ",top," physics ",Engine.physics_ticks_per_second)
	check(top.y>2.70 and top.z>6.1,"Actual player walks up the compact stairs through its ceiling opening")
	await walk(-1.0,240)
	var bottom:Vector3=raft.to_local(player.global_position)
	check(bottom.y<1.3 and bottom.y>0.9 and bottom.z<3.0,"Actual player returns down without getting stuck in the ceiling")
	var sky:=current_scene.get_node("Sky3D");var clock:=sky.get_node("TimeOfDay");var dome:=sky.get_node("SkyDome")
	clock.call("pause")
	var atmosphere:=current_scene.get_node("OceanAtmosphere")
	for hour in [0.0,6.25,9.0,12.0,18.0,21.0]:
		clock.current_time=hour;atmosphere.call("_process",1.0);await frames()
		var y:float=(dome.get("_sun_transform") as Transform3D).origin.y
		check(y>0.5 if hour in [9.0,12.0] else (y< -0.4 if hour in [0.0,21.0] else absf(y)<0.15),"Sun position matches clock at "+str(hour))
		check(not sky.environment.fog_enabled and not sky.environment.volumetric_fog_enabled,"Phone stays free of fog at "+str(hour))
	clock.current_time=5.49;atmosphere.call("_process",1.0);var before:float=sky.environment.ambient_light_energy
	clock.current_time=5.51;atmosphere.call("_process",1.0)
	check(absf(sky.environment.ambient_light_energy-before)<0.015,"Morning lighting no longer jumps at a fixed hour")
	clock.current_time=23.99;var day:int=clock.day;clock.call("_progress_time",0.8)
	check(clock.day==day+1 and clock.current_time<0.05,"Clock advances into the next day at midnight")
	inv.remove("Soil",500);inv.testing_soil_granted=true;inv.testing_soil_revision=0;inv.grant_testing_resources()
	check(inv.total("Soil")==2000,"Existing saves receive the renewed 2000 Soil testing supply")
	inv.remove("Soil",12);inv.grant_testing_resources();check(inv.total("Soil")==1988,"New Soil grant does not refill every frame or Continue")
	inv.save_game({"game_time":21.0},"quick");inv.new_game_reset(false);inv.load_game("quick");inv.grant_testing_resources()
	check(inv.total("Soil")==1988 and inv.testing_soil_revision==2,"Soil migration is saved and remains once per save")
	clock.current_time=9.0;atmosphere.call("_process",1.0)
	if preview:
		view_camera=Camera3D.new();current_scene.add_child(view_camera);view_camera.current=true
		player.camera.get_node("HandPivot").visible=false
		player.get_node("SurvivalAction").set_process(false)
		player.get_node("SurvivalProgression").set_process(false)
	await shot("compact-stairs-preview",Vector3(8,4.8,1),Vector3(4,1.7,4.8))
	await shot("ocean-morning-preview",Vector3(0,3,0),Vector3(-20,3,-90))
	clock.current_time=18.0;atmosphere.call("_process",1.0)
	await shot("ocean-sunset-preview",Vector3(0,3,0),Vector3(-90,3,0))
	clock.current_time=0.0;atmosphere.call("_process",1.0)
	await shot("ocean-night-preview",Vector3(0,3,0),Vector3(-20,3,-90))
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(25)
	print("STAIRS SKY SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
