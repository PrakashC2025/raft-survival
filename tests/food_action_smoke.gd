extends SceneTree
var checks:=0
var failures:=0
var player: Node3D
var action: Node
var service: Node
var inv: Node
var preview:=false
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func pose(progress: float) -> void:
	action.elapsed=action.duration*progress;action.call("_process",0.0)
	player.call("_update_hand_sway",0.0)
func shot(label: String) -> void:
	if not preview:return
	await frames(8);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/food-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");player.set_process(false);player.set_physics_process(false)
	var raft:=get_first_node_in_group("raft");raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	await frames(100)
	player.get_node("RainSystem").call("stop_rain")
	service=player.get_node("SurvivalServices");service.set_process(false)
	action=player.get_node("SurvivalAction");action.set_process(false)
	player.global_position=raft.to_global(Vector3(0,1.05,0));player.rotation.y=0
	player.cam_mode=0;player.call("_apply_camera_mode")
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	inv.call("_recompute");inv.changed.emit()
	inv.call("add","Tomato",1);service.call("equip_owned","Tomato")
	check(service.call("use_item","Tomato"),"Last owned tomato can be eaten")
	check(int(inv.call("total","Tomato"))==0,"Eating spends exactly one item")
	check(action.kind=="eat" and is_instance_valid(action._food_first) and is_instance_valid(action._food_third),"Last food keeps independent first and third person props")
	pose(.15);var lowered: Vector3=action.call("sample_pose").view_pos
	# Advance through the actual contact before the later mouth-held pose.
	pose(.37)
	pose(.42);var raised: Dictionary=action.call("sample_pose")
	check(raised.view_pos.y>lowered.y+.12,"Food rises to the mouth before the bite")
	check(action._cues_played==1 and action._sound.playing,"Bite sound begins at mouth contact")
	pose(.42);check(action._cues_played==1,"Same pose cannot repeat a bite cue")
	check(action._view_tool.visible and not player._hand_item.visible,"Eating shows one first person hand prop")
	await shot("eating-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode");pose(.55)
	check(action._tool.visible and not action._view_tool.visible,"Third person switches to the skeleton-bound food")
	check(action._tool.find_children("HumanHand*","Node3D",true,false).is_empty(),"Third person never duplicates the first person hand")
	var camera:=Camera3D.new();camera.fov=42;current_scene.add_child(camera)
	camera.global_position=player.global_position+Vector3(1.6,.95,-2.0);camera.look_at(player.global_position+Vector3(0,.2,0));camera.current=true
	await shot("eating-third-person")
	pose(.65);check(action._cues_played==2,"Second bite has a separate sound contact")
	pose(.99);check(action.call("sample_pose").view_pos.length()<.002,"Eating settles back smoothly")
	action.call("stop");await frames()
	check(not is_instance_valid(action._tool) and not is_instance_valid(action._food_first) and not action._sound.playing,"Stopping frees eating props and sound")
	player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true
	inv.call("add","Clean Water Can",1);service.call("equip_owned","Clean Water Can")
	check(service.call("use_item","Clean Water Can"),"Last clean water can starts drinking")
	check(int(inv.call("total","Clean Water Can"))==0 and int(inv.call("total","Can"))==1,"Drinking returns exactly one empty can")
	pose(.5);check(action.kind=="drink" and action._food_first.rotation.x<-.8,"Drinking tilts the can with its own motion")
	await shot("drinking")
	action.call("stop")
	for item in ["Potato","Banana","Coconut","Onion","Carrot","Fish"]:
		var food:=preload("res://scripts/survival_item_visual.gd").create(item)
		check(food!=null and food.get_child_count()>0,"Visible edible prop: "+item);food.free()
	var fire: Node3D=load("res://scenes/cooking_setup.tscn").instantiate()
	current_scene.add_child(fire);fire.global_position=player.global_position+Vector3(0,-.75,-1.3);fire.set_process(false);fire.burning=true
	check(fire.get_node_or_null("CookingPan")!=null,"Cooking station has an open pan on its stand")
	inv.call("add","Potato",1);service.call("open_cooking",fire)
	check(service.call("start_cooking","Cooked Potato"),"Cooking still spends validated ingredients and starts a station job")
	check(action.kind=="cook" and action._view_tool!=null,"Cooking uses visible stirring hands and spoon")
	check(action._view_tool.get_node_or_null("PreparationBowl")!=null and action._left_tool!=null,"Preparation bowl is supported by the left hand in both camera views")
	pose(.35);await shot("preparing-food")
	player.cam_mode=1;player.call("_apply_camera_mode");camera.current=true;pose(.35)
	await shot("preparing-third-person")
	player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true;pose(.35)
	var job:=fire.get_node("StationJob");job.set_process(false);job.call("_sync_visual")
	check(job._meal.visible and not job._pan.visible,"Food appears in the existing station pan without a second pan")
	check(job._sizzle.playing,"Nearby active cooking has a quiet spatial sizzle")
	job.call("advance",2.0);var saved: Dictionary=job.call("save_job");var before: float=job.job.remaining
	var color_before: Color=job._food_material.albedo_color
	fire.burning=false;job.call("advance",2.0)
	check(job.job.remaining==before and not job._sizzle.playing,"Extinguished fire pauses progress and sound")
	check(job._bubbles.all(func(bubble: MeshInstance3D):return not bubble.visible),"Fire-out cooking hides simmer bubbles")
	job.call("restore_job",saved);check(is_equal_approx(float(job.job.remaining),before),"Existing job save restores the same cooking progress")
	fire.burning=true;job.call("advance",1.0)
	check(job.job.remaining<before and job._food_material.albedo_color!=color_before,"Relighting resumes cooking and progressive browning")
	action.call("stop");player.camera.current=false;camera.current=true
	camera.global_position=fire.global_position+Vector3(.9,1.35,1.1);camera.look_at(fire.global_position+Vector3(0,.55,0));job.call("_sync_visual")
	await shot("simmering-pan")
	camera.global_position+=Vector3(40,0,0);job.call("_sync_visual")
	check(not job._sizzle.playing,"Distant cooking stops its sound player")
	job.call("advance",100.0)
	check(job.job.is_empty() and int(inv.call("total","Cooked Potato"))==1 and not job._meal.visible,"Completion awards one dish and clears food visuals")
	job.call("advance",100.0);check(int(inv.call("total","Cooked Potato"))==1,"Completion cannot duplicate food")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(20)
	print("FOOD ACTION SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
