extends SceneTree
var checks:=0
var failures:=0
var inv: Node
var player: Node3D
var service: Node
var stats: Node
var preview:=false
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func shot(label: String) -> void:
	if not preview:return
	await frames(8);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/tumbler-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false;stats=root.get_node("Stats");stats.enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");player.set_process(false);player.set_physics_process(false)
	get_first_node_in_group("raft").set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false)
	await frames(100);player.get_node("RainSystem").call("stop_rain")
	service=player.get_node("SurvivalServices");service.set_process(false)
	var action:=player.get_node("SurvivalAction");action.set_process(false)
	var metal: int=inv.call("total","Metal")
	check(inv.call("craft_item","Tumbler") and int(inv.call("total","Metal"))==metal-2,"Reusable tumbler crafts for two metal")
	service.call("equip_owned","Tumbler")
	player.global_position=Vector3(1400,1,1400);player.camera.global_position=Vector3(1400,3,1400);player.camera.look_at(Vector3(1400,0,1398))
	check(service.call("ocean_point").is_finite() and service.call("use_item","Tumbler"),"Tumbler begins a reachable ocean dip")
	check(action._food_first.name=="MetalTumbler" and action.kind=="fill","Filling shows the actual metal cup")
	service.call("advance_action",1.9);check(int(inv.call("total","Ocean Water Tumbler"))==0,"Fill cannot award water early")
	service.call("advance_action",.2)
	check(int(inv.call("total","Ocean Water Tumbler"))==1 and int(inv.call("total","Tumbler"))==0,"Filling exchanges one empty tumbler")
	stats.call("load_state",{"health":80,"hunger":40,"thirst":10})
	check(service.call("use_item","Ocean Water Tumbler"),"Unboiled seawater remains drinkable by choice")
	check(stats.thirst==22 and stats.health==72 and int(inv.call("total","Tumbler"))==1,"Raw water has its game penalty and returns the cup")
	check(action.kind=="drink" and action._food_first.get_node_or_null("RolledRim")!=null,"Drinking uses a rimmed steel vessel in the hand")
	action.elapsed=action.duration*.29;action.call("_process",0.0)
	check(action._cues_played==1 and action._sound.playing and action._food_first.rotation.x>.5,"Cup tilts at the mouth with a timed sip sound")
	check(action._food_first.get_node("DrinkingWater").position.y<.065,"Visible water lowers after each sip")
	player.cam_mode=0;player.call("_apply_camera_mode");player.call("_update_hand_sway",0.0);action.call("_process",0.0)
	await shot("drinking")
	if preview:
		player.cam_mode=1;player.call("_apply_camera_mode")
		var camera:=Camera3D.new();current_scene.add_child(camera);camera.current=true
		camera.global_position=player.global_position+Vector3(1.1,.65,-1.2);camera.look_at(player.global_position+Vector3(0,.45,0))
		action.call("_process",0.0);await shot("drinking-third-person")
		camera.queue_free();player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true
	action.call("stop");service.call("equip_owned","Tumbler")
	player.camera.global_position=Vector3(1400,3,1400);player.camera.look_at(Vector3(1400,0,1398))
	service.call("use_item","Tumbler");service.call("advance_action",2.0)
	var fire: Node3D=load("res://scenes/cooking_setup.tscn").instantiate();current_scene.add_child(fire);fire.global_position=player.global_position+Vector3(0,-.7,-1.3);fire.set_process(false);fire.burning=true
	service.call("open_cooking",fire)
	check(service.call("start_boiling"),"Ocean-filled tumbler starts an eight-second boiling job")
	var job:=fire.get_node("StationJob");job.set_process(false)
	check(int(inv.call("total","Ocean Water Tumbler"))==0 and job.job.kind=="boil","Boiling reserves the filled cup exactly once")
	check(not service.call("start_boiling"),"Repeated boil taps cannot start duplicate jobs")
	if preview:
		var camera:=Camera3D.new();current_scene.add_child(camera);camera.current=true
		camera.global_position=fire.global_position+Vector3(.6,1.3,.7);camera.look_at(fire.global_position+Vector3.UP*.85)
		job.call("_sync_visual");await shot("boiling");camera.queue_free();player.camera.current=true
	job.call("advance",2.0);var saved: Dictionary=job.call("save_job")
	fire.call("extinguish");job.call("advance",2.0)
	check(job.job.remaining==saved.remaining and not job._steam.visible,"Fire-out boiling pauses without losing water")
	job.call("restore_job",saved);check(job.job.kind=="boil" and job.job.remaining==saved.remaining,"Saved boiling progress restores compatibly")
	fire.burning=true;job.call("advance",100.0)
	check(int(inv.call("total","Boiled Water Tumbler"))==1 and job.job.is_empty(),"Boiling awards one ready tumbler")
	check(not fire.burning and not fire._flames.visible and not fire._light.visible and not job._steam.visible,"Completion puts out flame, light and steam automatically")
	job.call("advance",100.0);check(int(inv.call("total","Boiled Water Tumbler"))==1,"A completed boil cannot award twice")
	service.call("equip_owned","Boiled Water Tumbler");stats.call("load_state",{"health":70,"hunger":40,"thirst":10})
	check(service.call("use_item","Boiled Water Tumbler") and stats.thirst==75 and stats.health==70,"Boiled water restores thirst without the raw-water penalty")
	check(int(inv.call("total","Tumbler"))==1 and int(inv.call("total","Boiled Water Tumbler"))==0,"Drinking keeps the reusable empty tumbler")
	var meal: Node3D=service.call("ensure_job",fire);fire.burning=true;fire.fuel=100;meal.call("restore_job",{"kind":"cook","item":"Cooked Potato","remaining":.1});meal.call("advance",1.0)
	check(not fire.burning and int(inv.call("total","Cooked Potato"))==1,"Food completion also turns off its fire")
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(20)
	print("TUMBLER SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
