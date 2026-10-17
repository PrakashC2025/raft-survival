extends SceneTree
var checks:=0
var failures:=0
var player: Node3D
var service: Node
var inv: Node
var stats: Node
var progress: Node
const RULES:=preload("res://scripts/food_rules.gd")
const SAVE:=preload("res://scripts/save_storage.gd")
func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("FAIL: survival services timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func hold(item: String) -> void:service.equip_owned(item)
func put(item: String,count_value: int=1) -> void:inv.call("add",item,count_value)
func clear_bag() -> void:
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	inv.call("_recompute");inv.changed.emit()
func station(scene: String,offset: Vector3) -> Node3D:
	var result: Node3D=load("res://scenes/"+scene+".tscn").instantiate()
	current_scene.add_child(result);result.global_position=player.global_position+offset;result.set_process(false)
	return result
func screenshot(name_value: String) -> void:
	await frames(12)
	var picture:=root.get_texture().get_image()
	if picture!=null:picture.save_png("C:/GodotProjects/raft-survival/build/"+name_value+".png")
func stable_lights() -> void:
	var previous_position:=player.global_position
	player.global_position=Vector3(0,50,0)
	var torches: Array[Node3D]=[]
	for index in 8:
		var torch:=station("wall_torch",Vector3.ZERO)
		var offset:=Vector3(float(index)*.1,0,0) if index<5 else Vector3(2 if index==5 else (-2 if index==6 else 20),0,0)
		torch.global_position=player.global_position+offset
		torch.restore_survival_state({"burning":true,"fuel":120,"end_time":1000})
		torches.append(torch)
	service.call("_limit_lights")
	var selected: Dictionary=service._light_ids.duplicate()
	check(selected.size()==6,"Six burning sources receive lighting without unlit fires taking slots")
	var stable:=true
	for index in 12:
		player.global_position.x=.05 if index%2==0 else -.05
		service.call("_limit_lights")
		stable=stable and service._light_ids==selected
	check(stable,"Small movement across a light-distance tie does not switch room brightness")
	player.global_position.x=-2
	service.call("_limit_lights")
	check(torches[6].get_meta("light_allowed",false) and not torches[5].get_meta("light_allowed",false),"Moving clearly closer still transfers a slot to the nearer torch")
	torches[0].burning=false;torches[0].fuel=0
	service.call("_limit_lights")
	check(not torches[0].get_meta("light_allowed",false) and service._light_ids.size()==6,"An extinguished source releases its slot to another burning source")
	for torch in torches:torch.queue_free()
	await frames()
	player.global_position=previous_position
	service.call("_limit_lights")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	inv=root.get_node("Inventory");stats=root.get_node("Stats");inv.call("new_game_reset",true);stats.enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");player.set_process(false);player.set_physics_process(false)
	get_first_node_in_group("raft").set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false)
	service=player.get_node("SurvivalServices");service.set_process(false)
	progress=player.get_node("SurvivalProgression");progress.set_process(false)
	await frames(90)
	player.get_node("RainSystem").call("stop_rain");player.velocity=Vector3.ZERO
	check(inv.call("craft_item","Medkit") and inv.call("craft_item","Can"),"Medkit and empty Can craft through validated inventory recipes")
	clear_bag();put("Medkit",4);hold("Medkit");stats.call("load_state",{"health":1,"hunger":50,"thirst":50})
	check(service.use_item("Medkit") and service.ui._progress_root.visible,"Medkit starts a timed hand action and visible progress")
	check(player.get_node("SurvivalAction").kind=="bandage","Medkit uses the registered hand animation")
	service.advance_action(1.49);check(stats.health==1 and inv.call("total","Medkit")==4,"Medkit does not spend or heal before 1.5 seconds")
	service.advance_action(.01);check(stats.health==51 and inv.call("total","Medkit")==3,"Medkit heals exactly half maximum health and consumes one")
	check(service.use_item("Medkit"),"Second medkit starts")
	service.advance_action(1.5);check(stats.health==100 and inv.call("total","Medkit")==2,"Second medkit clamps to full health")
	check(not service.use_item("Medkit"),"Full-health medkit cannot waste an item")
	stats.change_health(-20);service.use_item("Medkit");player.global_position.x+=.2;service.advance_action(.2)
	check(not service.busy() and inv.call("total","Medkit")==2,"Movement cancels medkit without spending it")
	check(player.get_node("SurvivalAction").kind.is_empty(),"Cancelling stops the medkit hand pose too")
	service.use_item("Medkit");stats.change_health(-1);service.advance_action(.2)
	check(not service.busy() and inv.call("total","Medkit")==2,"Damage cancels medkit without spending it")
	check(not service.use_item("Clean Water Can"),"Unowned or unequipped item intent is rejected")
	put("Can");hold("Can");player.global_position=Vector3(1400,1,1400)
	player.camera.global_position=Vector3(1400,3,1400);player.camera.look_at(Vector3(1400,0,1398))
	await frames()
	check(service.ocean_point().is_finite(),"Ocean filling uses the actual reachable camera aim")
	check(service.use_item("Can"),"Empty can starts two-second ocean dip")
	check(player.get_node("SurvivalAction").kind=="fill","Water dip uses the registered can animation")
	service.advance_action(1.9);check(inv.call("total","Dirty Water Can")==0,"Partially filled can cannot award dirty water")
	service.advance_action(.2);check(inv.call("total","Dirty Water Can")==1 and inv.call("total","Can")==0,"Filling exchanges exactly one empty can")
	hold("Dirty Water Can");stats.call("load_state",{"health":60,"hunger":40,"thirst":10});service.use_item("Dirty Water Can")
	check(stats.thirst==22 and stats.health==52 and inv.call("total","Can")==1,"Dirty drinking gives small water, damages health and returns can")
	put("Dirty Water Can");hold("Dirty Water Can")
	var filter:=station("sand_filter",Vector3(1,0,0));service.open_filter(filter)
	check(service.menu_open and not service.ui._filter_button.disabled,"Aimed filter opens an insert prompt")
	check(service.start_filtering(),"Filter consumes dirty can once and starts five-second job")
	var filtering:=filter.get_node("StationJob");filtering.set_process(false)
	check(filtering._insert>0 and filtering._drops.size()==4,"Filter reuses insertion can and four dripping visuals")
	filtering.advance(4.9);check(inv.call("total","Clean Water Can")==0,"Clean can is unavailable before filtering finishes")
	filtering.advance(.2);service.finish_station_job(filtering)
	check(inv.call("total","Clean Water Can")==1 and filtering.job.is_empty(),"Filter completion awards once even if requested twice")
	hold("Clean Water Can");service.use_item("Clean Water Can")
	check(stats.thirst==100 and inv.call("total","Can")==2,"Clean can fills thirst and returns the reusable container")
	var fire:=station("cooking_setup",Vector3(-1,0,0));fire.burning=true;service.open_cooking(fire)
	check(service.menu_open and service.ui._rows.size()==RULES.RECIPES.size(),"Cooking Setup lists every dish from the single configuration")
	player.get_node("CanvasLayer/SurvivalHUD").call("handle_back")
	check(not service.menu_open and not paused,"Android Back closes cooking without opening pause")
	service.open_cooking(fire)
	check(not service.can_cook("Fish Potato Tomato Soup") and not service.start_cooking("Forged Meal"),"Missing ingredients and forged dish names cannot start cooking")
	for raw in ["Potato","Tomato","Fish","Banana","Carrot","Onion","Coconut","Raw Meat","Raw Bird","Raw Crab"]:put(raw,20)
	put("Clean Water Can",20)
	var potato_row: Dictionary={}
	for row in service.ui._rows:
		if row.dish=="Cooked Potato":potato_row=row;break
	check(not potato_row.is_empty() and potato_row.ingredients.text.contains("#8dd49c") and not potato_row.button.disabled,"Recipe Have/Need counts turn green and enable affordable dishes")
	if "--preview" in OS.get_cmdline_user_args():await screenshot("cooking-recipes-preview")
	var cans_before: int=inv.call("total","Can")
	check(service.start_cooking("Fish Potato Tomato Soup"),"Soup consumes fish, potato, tomato and clean water centrally")
	check(inv.call("total","Fish")==19 and inv.call("total","Can")==cans_before+1,"Cooking returns the ingredient's empty can atomically")
	var job:=fire.get_node("StationJob");job.set_process(false);var saved_job: Dictionary=job.save_job()
	job.job.clear();job.restore_job(saved_job)
	check(job.job.item=="Fish Potato Tomato Soup" and job.job.remaining==20,"Pending cooking job restores its dish and remaining duration")
	fire.burning=false;job.advance(3);check(job.job.remaining==20,"Cooking pauses while its fire is out")
	fire.burning=true;job.advance(20);service.finish_station_job(job)
	check(inv.call("total","Fish Potato Tomato Soup")==1,"Cooked output arrives exactly once")
	stats.call("load_state",{"health":40,"hunger":10,"thirst":10});hold("Fish Potato Tomato Soup");service.use_item("Fish Potato Tomato Soup")
	check(stats.health==55 and stats.hunger==55 and stats.thirst==40,"Soup applies configured +45 hunger, +30 thirst and +15 health")
	for dish in RULES.RECIPES:
		check(RULES.effects(dish)[0]>=17 and RULES.effects(dish)[1]>0 and RULES.effects(dish)[2]>0,dish+" has stronger cooked nutrition, water and healing")
	player.get_node("SurvivalAction").stop()
	hold("Banana");stats.call("load_state",{"health":60,"hunger":20,"thirst":20});service.use_item("Banana")
	check(stats.hunger==28 and stats.health==59,"Banana can be eaten raw with configured nutrition and small damage")
	check(RULES.effects("Fish")[2]<RULES.effects("Potato")[2],"Raw fish carries more health damage than raw vegetables")
	check(service.ui._popups.size()==4,"Stat change popups reuse a fixed pool")
	var box:=station("storage_box",Vector3(0,0,-1));service.open_storage(box)
	check(service.ui._slots.size()==inv.SLOT_COUNT+box.capacity,"Storage shows all player slots and the box's actual capacity")
	var potato_slot: int=-1
	for index in inv.SLOT_COUNT:
		if inv.call("slot_item",index)=="Potato":potato_slot=index;break
	check(service.transfer(false,potato_slot,true,0),"Validated storage transfer moves a whole stack")
	check(box.contents[0].item=="Potato" and inv.call("total","Potato")==0,"Storage items leave player inventory without duplication")
	check(not service.transfer(true,-1,false,0) and not service.transfer(true,100,false,0),"Invalid storage slot commands are rejected")
	var box_state: Dictionary=box.save_survival_state();box.contents[0]={};box.restore_survival_state(box_state)
	check(box.contents[0].item=="Potato" and box.contents[0].count==19,"Storage contents restore with counts intact")
	var slot: Control=service.ui._slots[30]
	check(not slot.call("_can_drop_data",Vector2.ZERO,{"owner":0,"box":false,"slot":0}),"Storage rejects drag payloads from another owner")
	var event:=InputEventScreenTouch.new();event.index=2;event.pressed=true;event.position=slot.size*.5
	slot.call("_gui_input",event);event.pressed=false;event.index=3;slot.call("_gui_input",event)
	check(not box.contents[0].is_empty() and slot._touch_owner==2,"An unrelated finger cannot release the storage drag")
	event.index=2;slot.call("_gui_input",event)
	check(box.contents[0].is_empty() and inv.call("total","Potato")==19,"Touch tap transfers the stack with gameplay input released")
	service.transfer(false,inv.slots.find({"item":"Potato","count":19}),true,0)
	if "--preview" in OS.get_cmdline_user_args():await screenshot("storage-box-preview")
	service.close_menu();var contents_before: Array=box.contents.duplicate(true)
	var station_position:=player.global_position
	var kept_before: Array=inv.slots.duplicate(true);var drops_before: int=service._drops.size();service.on_death()
	check(inv.slots==kept_before and box.contents==contents_before,"Death keeps backpack, hotbar and stored supplies unchanged")
	check(player.global_position.distance_to(get_first_node_in_group("raft").global_position)<2,"Death recovery returns the player to the home raft")
	check(service._drops.size()==drops_before,"Recovery does not duplicate inventory into a new death bag")
	# Resume the remaining station fixture beside its existing camp equipment.
	player.global_position=station_position
	stats.call("reset");put("Wood",10);put("Rope",10);check(inv.call("craft_item","Torch"),"Unlit Torch is craftable in the normal recipe table")
	hold("Torch");player.aim_valid=false;progress.use_torch()
	check(progress.torch_fuel==0 and not progress._torch_light.visible,"Unlit torch cannot light without aiming at a fire")
	var sky:=current_scene.get_node("Sky3D");sky.set_process(false);sky.get_node("TimeOfDay").set_process(false);sky.current_time=23.0;sky.get_node("TimeOfDay").current_time=23.0
	# The completed meal now puts out its fire. Relight before the torch test.
	fire.burning=true;fire.fuel=100;fire.call("_process",0.0)
	player.aim_valid=true;player.aim_collider=fire;player.aim_distance=1.0;player.aim_point=fire.global_position
	progress.use_torch();player.get_node("FireActions")._process(.93);player.get_node("FireActions")._process(.40);progress._process(.01)
	check(inv.call("has","Burning Torch",1) and player.active_item=="Burning Torch" and progress._torch_light.visible,"Aimed Cooking Setup lights and equips a Burning Torch with real light")
	put("Torch");hold("Torch");progress._process(.01)
	check(not progress._torch_light.visible and player.interaction_caption()=="LIGHT TORCH","An unlit torch stays dark while another Burning Torch is in the bag")
	hold("Burning Torch");progress._process(.01)
	var deadline: float=progress.torch_end_time
	check(deadline==float(player.get_survival_day()+1)*24+6,"Torch deadline is next dawn, not an arbitrary duration")
	progress.restore_state(progress.save_state());check(progress.torch_end_time==deadline,"Held torch dawn deadline survives save restoration")
	player.survival_day+=1;sky.current_time=6.0;sky.get_node("TimeOfDay").current_time=6.0;progress._process(.01)
	check(inv.call("total","Burning Torch")==0 and inv.call("has","Torch",1) and not progress._torch_light.visible,"Dawn converts the Burning Torch to a reusable unlit torch")
	stats.call("load_state",{"health":80,"hunger":80,"thirst":80});stats.enabled=true;player.velocity=Vector3.ZERO;player.is_swimming=false
	stats.call("_process",10);var idle: float=80-stats.hunger
	stats.call("load_state",{"health":80,"hunger":80,"thirst":80});player.velocity=Vector3(5,0,0);stats.call("_process",10)
	check(is_equal_approx(80-stats.hunger,idle*1.6),"Sprinting increases hunger and water drain")
	stats.call("load_state",{"health":80,"hunger":80,"thirst":80});player.is_swimming=true;stats.call("_process",10)
	check(is_equal_approx(80-stats.hunger,idle*2),"Swimming uses the higher survival drain")
	stats.call("load_state",{"health":80,"hunger":0,"thirst":0});stats.call("_process",1)
	check(is_equal_approx(stats.health,79.8),"Empty hunger/water cause the slower 0.2 health damage per second")
	stats.enabled=false;player.is_swimming=false;player.velocity=Vector3.ZERO
	stats.call("load_state",{"health":{},"hunger":NAN,"thirst":9999})
	check(stats.health==100 and stats.hunger==100 and stats.thirst==100,"Stats reject invalid types and NaN and clamp valid values")
	for index in 8:station("bonfire",Vector3(index*.2,0,2))
	service.call("_limit_lights");var allowed:=0
	for group in service.LIGHT_GROUPS:
		for source in get_nodes_in_group(group):
			if source.get_meta("light_allowed",false):allowed+=1
	check(allowed<=6,"Built campfires, wall torches and lamps share a six-light budget")
	await stable_lights()
	clear_bag();put("Potato");service.open_cooking(fire);service.start_cooking("Cooked Potato")
	put("Stone",inv.SLOT_COUNT*inv.MAX_STACK);job.advance(8)
	check(inv.call("total","Cooked Potato")==0 and service._drops.back().contents[0].item=="Cooked Potato","Cooking into a full inventory drops its finished dish without losing it")
	var drop_count: int=service._drops.size();job.advance(8);service.finish_station_job(job)
	check(service._drops.size()==drop_count,"Completed overflow cooking cannot duplicate its dropped meal")
	check(player.call("_write_save","quick"),"New systems save through the authenticated atomic save format")
	var saved: Dictionary=SAVE.read(inv.QUICK_SAVE_PATH)
	check(saved.version==1 and saved.survival_services.drops.size()==drop_count,"Versioned save preserves existing loot and cooking overflow bags")
	for invalid in [{"version":99,"slots":[]},{"slots":[],"built":{}},{"slots":[],"electronics":{"charge":[]}},{"slots":[],"survival_services":{"drops":[{"p":[{},0,0],"contents":[]}]}},{"slots":[],"island_groves":{"Island":{"Banana0":[]}}},{"slots":[],"built":[{"t":"StorageBox","survival":{"contents":[{"item":"Medkit","count":{}}]}}]}]:
		var file:=FileAccess.open("user://damaged-check.json",FileAccess.WRITE);file.store_string(JSON.stringify(invalid));file.close()
		check(SAVE.read_one("user://damaged-check.json").is_empty(),"Malformed nested or unsupported-version save is rejected before restoration")
	print("SURVIVAL SERVICES SMOKE: %d checks, %d failures"%[checks,failures])
	if "--preview" in OS.get_cmdline_user_args():
		current_scene.get_node("OceanAmbience").call("stop_environment")
		# Render the final light-budget fixture before requesting engine shutdown.
		# It was created synchronously after the screenshots, with GPU work pending.
		for unused in 30:await process_frame
		quit(0 if failures==0 else 1);return
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(25)
	quit(0 if failures==0 else 1)
