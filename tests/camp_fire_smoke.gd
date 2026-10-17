extends SceneTree
const ART:=preload("res://scripts/item_art.gd")
const RULES:=preload("res://scripts/food_rules.gd")
var checks:=0
var failures:=0
var player: Node3D
var raft: Node3D
var built: Node3D
var inv: Node
var actions: Node
var pose: Node
var progress: Node
var service: Node
var preview:=false
func _initialize() -> void:
	create_timer(120).timeout.connect(func():push_error("FAIL: camp fire timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+label)
	else:print("PASS: "+label)
func frames(count: int=4) -> void:
	for unused in count:await process_frame
func fixture(kind: String,pos: Vector3) -> Node3D:
	var result:=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate() as Node3D
	result.position=pos;built.add_child(result);result.set_process(false);return result
func aim(target: Node3D) -> void:
	player.aim_valid=true;player.aim_collider=target;player.aim_point=target.global_position;player.aim_normal=Vector3.BACK;player.aim_distance=1
func hold(item: String) -> void:
	if not inv.call("has",item,1):inv.call("add",item,1)
	service.call("equip_owned",item);pose.call("stop")
func advance(seconds: float) -> void:
	actions.call("_process",seconds);pose.call("_process",seconds)
func complete() -> void:
	if not actions.busy():check(false,"Expected a pending contact action");return
	advance(float(actions.pending.seconds)*.71);advance(1.0)
func shot(label: String) -> void:
	await frames(6);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/camp-"+label+".png")==OK,"Rendered "+label)
func pointer(at: Vector2) -> void:
	var finger:=InputEventScreenTouch.new();finger.index=21;finger.position=at;finger.pressed=true;root.push_input(finger,true)
	var mouse:=InputEventMouseButton.new();mouse.device=-1;mouse.position=at;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true;root.push_input(mouse,true)
	mouse.pressed=false;root.push_input(mouse,true);finger.pressed=false;root.push_input(finger,true)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false)
	await frames(110)
	actions=player.get_node("FireActions");actions.set_process(false);pose=player.get_node("SurvivalAction");pose.set_process(false)
	progress=player.get_node("SurvivalProgression");progress.set_process(false);service=player.get_node("SurvivalServices");service.set_process(false)
	player.global_position=raft.to_global(Vector3(0,1.1,0))
	check(built.get_child_count()==1 and player._grid_occupancy.has(Vector2i(0,1)),"New Game doubles the deck with one real supported starter foundation")
	var starter:=built.get_child(0) as Node3D
	check(starter.position==Vector3(0,0,2) and starter.get_node("CollisionShape3D").shape.size.x==2,"Starter extension has matching 2m visual/collision and original grid")
	check(player.call("_serialize_built_pieces").size()==1,"Extended starter uses existing backwards-compatible structure saves")
	check(player.call("_count_supporting_neighbors",Vector2i(0,2))==1,"Starting extension supports the next connected grid cell")
	var camera_before: Transform3D=player.camera.transform
	var candidate: Transform3D=player.call("_compute_foundation_transform",Vector2i(0,2))
	player.camera.global_position=candidate.origin+Vector3(0,3,3);player.camera.look_at(candidate.origin+Vector3(0,.15,0))
	player.aim_valid=true;player.aim_collider=starter;player.aim_point=candidate.origin+Vector3(0,.15,0);player.aim_normal=Vector3.UP
	player.call("_toggle_build");player.call("_update_build_preview")
	check(player.build_valid,"Green foundation preview extends the larger starter without overlapping its tile")
	player.call("_toggle_build");player.call("_apply_camera_mode");player.camera.transform=camera_before
	var paths:=[];var hashes:=[]
	for station in ART.STATION_IMAGES:
		var texture:=ART.station_texture(station)
		check(texture!=null and texture.get_width()>=160 and texture.get_width()==texture.get_height(),"Distinct square actual-model picture exists: "+station)
		paths.append(texture.resource_path);hashes.append(texture.get_image().get_data().hex_encode().sha256_text())
	check(paths.size()==ART.STATION_IMAGES.size() and paths.all(func(path):return paths.count(path)==1) and hashes.all(func(pixel_hash):return hashes.count(pixel_hash)==1),"Every camp product has a unique picture file and pixels")
	var fire:=fixture("Bonfire",Vector3(0,.15,-1.5));aim(fire);hold("Stone")
	check(not fire.burning and not fire._flames.visible,"Newly placed bonfire waits for player ignition")
	var stones: int=inv.call("total","Stone");var wood: int=inv.call("total","Wood")
	check(actions.start("ignite_fire",fire),"Owned pair of stones starts ignition")
	check(not fire.burning and pose.kind=="ignite_fire" and pose._view_tool.get_child_count()==3,"Ignition first shows two hands and spark rig before lighting")
	check(pose._tool!=null and pose._left_tool!=null,"Third person holds one real stone in each hand")
	pose.elapsed=pose.duration*.22;var before: Vector3=pose.sample_pose().right
	pose.elapsed=pose.duration*.30;pose.call("_advance_feedback")
	check(before.distance_to(pose.sample_pose().right)>.20 and pose._sparks.visible,"Strike reaches the other stone with timed local sparks")
	pose.elapsed=0
	if preview:
		player.camera.rotation=Vector3(-.45,0,0);pose.elapsed=pose.duration*.49;pose.call("_process",0.0);await shot("strike-first")
		player.cam_mode=1;player.call("_apply_camera_mode");pose.call("_process",0.0)
		var side:=Camera3D.new();current_scene.add_child(side);side.global_position=player.global_position+Vector3(1.4,1.1,-2.4);side.look_at(player.global_position+Vector3.UP*.18);side.current=true
		await shot("strike-third");side.queue_free();player.camera.current=true
		player.cam_mode=0;player.call("_apply_camera_mode");pose.elapsed=0
	advance(1.45);check(not fire.burning,"First strikes cannot light fire before final contact")
	advance(.12);check(fire.burning and int(inv.call("total","Stone"))==stones and int(inv.call("total","Wood"))==wood,"Final strike lights stored fuel and keeps reusable stones")
	advance(1);check(not actions.busy(),"Ignition releases action ownership after recovery")
	var fuel_before: float=fire.fuel
	check(actions.start("snuff_fire",fire),"Bonfire supports deliberate OFF action");complete()
	check(not fire.burning and fire.fuel==fuel_before,"Putting out fire preserves remaining fuel")
	check(fire.save_survival_state().burning==false,"Off state survives save/Continue")
	actions.start("ignite_fire",fire);root.get_node("Stats").damage_revision+=1;advance(.8)
	check(not fire.burning and not actions.busy(),"Damage cancels ignition before contact")
	actions.start("ignite_fire",fire);paused=true;actions.call("_process",.8);paused=false
	check(not fire.burning and not actions.busy(),"Pausing cancels ignition without a delayed fire")
	actions.start("ignite_fire",fire);player.global_position+=Vector3.RIGHT*2;advance(1.8)
	check(not fire.burning and int(inv.call("total","Wood"))==wood,"Walking away cancels ignition without fuel consumption")
	player.global_position=raft.to_global(Vector3(0,1.1,0));aim(fire)
	inv.call("remove","Stone",stones-1)
	check(not actions.start("ignite_fire",fire),"One stone cannot start the two-stone action");inv.call("add","Stone",stones-1)
	player.get_node("RainSystem").call("start_rain",20.0)
	check(not actions.start("ignite_fire",fire),"Exposed wet bonfire refuses ignition");player.get_node("RainSystem").call("stop_rain")
	fire.fuel=0;actions.start("ignite_fire",fire);complete()
	check(fire.burning and fire.fuel==90 and int(inv.call("total","Wood"))==wood-1,"An empty fireplace spends exactly one Wood only at successful contact")
	hold("Torch");player.aim_valid=false;player.aim_collider=null
	var held_torch:=player._hand_item.get_child(player._hand_item.get_child_count()-1) as Node3D
	check(not held_torch.flames.visible,"A newly equipped unlit stick starts without a flame")
	check(not player.can_interact_now() and player.interaction_caption().is_empty(),"An unlit hand torch has no light button when looking away")
	var hint_hud:=player.get_node("CanvasLayer/SurvivalHUD")
	check(str(hint_hud._toast).contains("Aim at a burning bonfire") and absf(hint_hud._toast_until-Time.get_ticks_msec()/1000.0-4)<.15,"Equipping a torch shows its usage snackbar for four seconds")
	hint_hud.call("_compute_layout")
	check(hint_hud._toast_rect.size.x<=hint_hud._vp.x-48,"Equipment instructions wrap within the mobile screen")
	hint_hud.call("_process",0.0)
	check(hint_hud.visible and not hint_hud.call("claims_touch",Vector2(10,10)),"Desktop equipment feedback is visible and does not capture camera input")
	if preview:
		progress.call("_process",0.0)
		await shot("torch-use-tip")
		var tip_controls:=player.get_node("CanvasLayer/MobileControls")
		tip_controls.force_show=true;tip_controls.call("_update_visibility");tip_controls.call("_sync_mode")
		hint_hud.call("_process",.1)
		check(not tip_controls._btn_use.visible,"Mobile light button stays hidden while an unlit torch looks away")
		await shot("torch-mobile-tip")
		tip_controls.force_show=false;tip_controls.call("_update_visibility")
	aim(fire)
	check(player.can_interact_now() and player.interaction_caption()=="LIGHT TORCH","Aimed burning bonfire offers the light torch action")
	progress.use_torch()
	check(not progress.is_held_lit() and pose.kind=="torch_light" and pose._torch_first!=null,"Torch dips toward fire with visible prop before exchanging")
	if preview:pose.elapsed=pose.duration*.5;pose.call("_process",0.0);await shot("light-torch");pose.elapsed=0
	complete();progress.call("_process",0.0)
	check(inv.call("has","Burning Torch",1) and progress.is_held_lit(),"Torch lights at contact and equips the burning version")
	await frames();progress.call("_process",0.0)
	held_torch=player._hand_item.get_child(player._hand_item.get_child_count()-1) as Node3D
	check(held_torch.flames.visible and progress._third_torch.flames.visible and progress._torch_light.visible,"Both held views and the real light follow the lit state after deferred item replacement")
	# Replacements can receive generated names while their old siblings await free.
	held_torch.name="RenamedHeldTorch"
	progress.torch_fuel=0;progress.call("sync_torch_effects")
	check(not held_torch.flames.visible and not progress._torch_light.visible,"A renamed live torch still loses its flame when its fuel is depleted")
	progress.extinguish_torch()
	service.equip_owned("Torch")
	check(actions.start("torch_light",fire),"An extinguished stick can relight after its visual was renamed")
	complete();await frames();progress.call("_process",0.0)
	var pickup_torch:=pose.call("_pickup_visual","Torch") as Node3D
	var pickup_burning:=pose.call("_pickup_visual","Burning Torch") as Node3D
	current_scene.add_child(pickup_torch);current_scene.add_child(pickup_burning)
	check(not pickup_torch.flames.visible and pickup_burning.flames.visible,"Pickup props preserve the actual unlit or burning item state")
	pickup_torch.queue_free();pickup_burning.queue_free()
	var deadline: float=progress.torch_end_time;check(deadline>0,"Torch retains dawn expiry")
	player.aim_valid=false;progress.use_torch();check(progress.is_held_lit() and pose.kind=="torch_off","OFF first brings both hands around the torch")
	check(pose._fire_left.get_node_or_null("SnuffingCloth")!=null and pose._left_tool!=null,"Both camera views snuff with a cloth cap instead of touching a flame bare-handed")
	if preview:pose.elapsed=pose.duration*.6;pose.call("_process",0.0);await shot("snuff-torch");pose.elapsed=0
	complete();check(not progress.is_held_lit() and inv.call("has","Torch",1),"Snuff contact returns a reusable unlit torch")
	check(not progress._torch_light.visible and not progress._third_torch.flames.visible,"Snuff contact immediately removes light and third-person fire")
	await frames();progress.call("_process",0.0)
	held_torch=player._hand_item.get_child(player._hand_item.get_child_count()-1) as Node3D
	check(not held_torch.flames.visible,"The replacement first-person stick stays unlit after its old named sibling is freed")
	if preview:await shot("torch-off-first")
	player.cam_mode=1;player.call("_apply_camera_mode");progress.call("_process",0.0)
	check(progress._third_torch.visible and not progress._third_torch.flames.visible,"Switching to third person cannot restore extinguished fire")
	if preview:await shot("torch-off-third")
	player.cam_mode=0;player.call("_apply_camera_mode")
	var wall:=fixture("Wall",Vector3(1,1.4,0));aim(wall);player.aim_point=wall.to_global(Vector3(0,0,.15));player.aim_normal=wall.global_basis.z
	check(player.call("_resolve_wall_torch").valid and player.interaction_caption()=="PLACE TORCH","Unlit torch has a valid wall mount preview/action")
	var count: int=inv.call("total","Torch");progress.use_torch();check(actions.busy() and inv.call("total","Torch")==count,"Mount reach delays inventory removal")
	if preview:pose.elapsed=pose.duration*.6;pose.call("_process",0.0);await shot("mount-torch");pose.elapsed=0
	complete();await frames()
	var mounted:=built.find_child("WallTorch_*",false,false) as Node3D
	check(mounted!=null and not mounted.burning and inv.call("total","Torch")==count-1,"Unlit torch transfers to wall without another recipe cost")
	if mounted==null:current_scene.queue_free();await frames(10);quit(1);return
	mounted.set_process(false);hold("Stone");aim(mounted);mounted.interact_survival(player);complete()
	check(mounted.burning and mounted.end_time>0,"Two stones light a wall-mounted torch until dawn")
	mounted.interact_survival(player);complete();check(not mounted.burning,"Mounted torch also switches off")
	hold("");mounted.interact_survival(player);await frames()
	check(inv.call("total","Torch")==count and not is_instance_valid(mounted),"Taking wall torch returns exactly one reusable item")
	for dish in ["Grilled Fish and Onion","Coconut Fish Stew","Crab Tomato Broth"]:
		check(RULES.RECIPES.has(dish) and ART.food_texture(dish)!=null,"Camp recipe has real ingredients, values and original dish picture: "+dish)
		for ingredient in RULES.RECIPES[dish].ingredients:if not inv.call("has",ingredient,3):inv.call("add",ingredient,3)
	fire.burning=true;service.open_cooking(fire);await frames()
	check(service.ui._rows.size()==26 and service.ui._fire_button.text=="PUT OUT FIRE","Camp Kitchen has twenty-six recipes and working fire controls")
	check(service.ui._rows[0].button.custom_minimum_size.y>=48 and service.ui._rows[0].ingredients.text.contains(" / "),"Cooking cards show owned/required ingredients and large touch buttons")
	service.ui._filter_recipes("SOUPS & STEWS")
	check(not service.ui._rows[0].card.visible and service.ui._rows[-1].card.visible,"Category tabs select real soups and hide grill recipes")
	service.ui._filter_recipes("ALL")
	if preview:await shot("kitchen")
	service.ui._filter_recipes("SOUPS & STEWS")
	if preview:
		await frames();var scroll:=service.ui._rows[-2].card.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(service.ui._rows[-2].card);await shot("stews")
	service.close_menu();service.station=fire
	var fish: int=inv.call("total","Fish");var coconut: int=inv.call("total","Coconut");var onion: int=inv.call("total","Onion")
	var started:=false
	if preview:
		service.open_cooking(fire);service.ui._filter_recipes("SOUPS & STEWS");await frames()
		var scroll:=service.ui._rows[-2].card.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(service.ui._rows[-2].card);await frames()
		pointer(service.ui._rows[-2].button.get_global_rect().get_center());await frames()
		started=fire.has_node("StationJob") and fire.get_node("StationJob").job.get("item","")=="Coconut Fish Stew"
	else:started=service.start_cooking("Coconut Fish Stew")
	check(started,"New survival recipe enters the existing station job; preview uses real touch/mouse GUI routing")
	if not started:service.close_menu();current_scene.queue_free();await frames(15);quit(1);return
	check(inv.call("total","Fish")==fish-1 and inv.call("total","Coconut")==coconut-1 and inv.call("total","Onion")==onion-1,"Cooking spends actual fish, coconut and onion exactly once")
	var job:=fire.get_node("StationJob");job.call("advance",100.0);service.finish_station_job(job)
	check(inv.call("has","Coconut Fish Stew",1) and not fire.burning,"Completed stew enters bag and turns off fire")
	if preview:
		var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud.toggle_crafting();hud._craft_menu.select_item("Bonfire");await shot("craft")
		check(not pose._panel.visible,"Action text never covers Bag or craft recipe panels")
		hud._close_crafting()
	# Explicit empty legacy structure must stay empty; no regeneration on Continue.
	starter.queue_free();await frames();inv.loaded_meta={"built":[]};player._fresh_starter=false;player._starter_extended=false
	var number:=built.get_child_count();await player.call("_restore_built_pieces")
	check(built.get_child_count()==number,"Continue does not add a starter tile into an existing save")
	print("CAMP FIRE SMOKE: %d checks, %d failures"%[checks,failures])
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(25);quit(0 if failures==0 else 1)
