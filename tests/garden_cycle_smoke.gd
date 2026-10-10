extends SceneTree
const ITEMS:=preload("res://scripts/garden_items.gd")
const VISUAL:=preload("res://scripts/garden_visual.gd")
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var built: Node3D
var inv: Node
var beds: Array[Node3D]=[]
func _initialize() -> void:
	create_timer(180).timeout.connect(func():push_error("FAIL: garden timeout");quit(1));call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=4) -> void:
	for unused in count:await physics_frame
	await process_frame
func piece(kind: String,at: Vector3) -> Node3D:
	var node: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	node.name=kind+"_GardenCheck_"+str(node.get_instance_id());node.position=at;built.add_child(node);return node
func shot(name: String) -> void:
	if not preview:return
	await frames(10);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../"+name+".png")==OK,"Garden preview: "+name)
func render_art() -> void:
	if not preview:return
	var atlas:=Image.create(800,1120,false,Image.FORMAT_RGBA8);atlas.fill(Color.TRANSPARENT)
	var view:=SubViewport.new();view.size=Vector2i(160,160);view.own_world_3d=true;view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_energy=.8;environment.environment=settings;view.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,155,0);light.light_energy=1.4;view.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;view.add_child(camera)
	for row in ITEMS.CROPS.size():
		var crop: String=ITEMS.CROPS[row]
		for column in 5:
			var item: String=crop if column==0 else "Sliced "+crop if column==1 else "Dry "+crop+" Seeds" if column==2 else "Wet "+crop+" Seeds" if column==3 else (crop if crop in ITEMS.NEW_CROPS else "Bell Pepper")+" Garden Box"
			var model: Node3D=preload("res://scripts/produce_visual.gd").create("Tomato") if column==0 and crop=="Tomato" else VISUAL.produce(item)
			view.add_child(model)
			camera.size=.64 if column==4 else .14 if column in [2,3] else .37
			camera.position=Vector3(1,.75,-2);camera.look_at(Vector3.ZERO)
			await frames(3);await RenderingServer.frame_post_draw
			atlas.blit_rect(view.get_texture().get_image(),Rect2i(0,0,160,160),Vector2i(column*160,row*160));model.queue_free();await frames(1)
	var tray: Node3D=load("res://scenes/seed_drying_tray.tscn").instantiate();view.add_child(tray);tray._preview=true;tray._label.hide();tray.restore_survival_state({"crop":"Cucumber","count":4,"seconds":120})
	camera.size=.74;camera.position=Vector3(1,1,-1.5);camera.look_at(Vector3.ZERO)
	await frames(3);await RenderingServer.frame_post_draw
	var tray_picture:=view.get_texture().get_image()
	check(tray_picture.save_png("res://textures/ui/stations/seed_drying_tray.png")==OK,"Rendered the real wooden seed tray craft picture")
	preload("res://scripts/item_art.gd")._pictures["station:SeedDryingTray"]=ImageTexture.create_from_image(tray_picture);tray.queue_free();await frames(1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://textures/ui/garden"))
	check(atlas.save_png("res://textures/ui/garden/garden_atlas.png")==OK,"Rendered distinct whole / sliced / dry / wet / crate pictures")
	preload("res://scripts/item_art.gd")._pictures.garden_atlas=ImageTexture.create_from_image(atlas)
	view.queue_free();await frames()
	var dishes: Array=preload("res://scripts/food_rules.gd").RECIPES.keys().slice(0,8)
	for dish in dishes:
		var v:=SubViewport.new();v.size=Vector2i(160,160);v.own_world_3d=true;v.transparent_bg=true;v.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(v)
		var env:=WorldEnvironment.new();env.environment=settings;v.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,155,0);sun.light_energy=1.4;v.add_child(sun)
		var meal:=preload("res://scripts/survival_item_visual.gd").create(dish);v.add_child(meal)
		var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=.31;v.add_child(cam);cam.position=Vector3(.7,1,-1);cam.look_at(Vector3.ZERO);cam.current=true
		await frames(3);await RenderingServer.frame_post_draw
		var picture:=v.get_texture().get_image();var file:="res://textures/ui/food/"+str(dish).to_lower().replace(" ","_")+".png"
		check(picture.save_png(file)==OK,"Rendered garden recipe: "+str(dish));preload("res://scripts/item_art.gd")._pictures["dish:"+dish]=ImageTexture.create_from_image(picture)
		v.queue_free();await frames(1)
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces");await frames(150)
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);raft.rotation=Vector3.ZERO
	var spawner:=current_scene.get_node("DebrisSpawner");spawner.set_process(false)
	check(player.BUILD_RECIPE_NAMES.size()==24 and player.BUILD_RECIPE_NAMES[23]=="SeedDryingTray","Drying tray appends without shifting existing building indexes")
	check(not spawner.SALVAGE_POOL.any(func(item):return str(item).ends_with(" Seed") or str(item).ends_with(" Seeds")),"Loose ocean salvage contains fruit, but no common planting packets")
	for index in ITEMS.NEW_CROPS.size():
		var crop: String=ITEMS.NEW_CROPS[index];var dry:="Dry "+crop+" Seeds"
		check(root.get_node("PlantDB").crop_for_item(dry)==crop and root.get_node("PlantDB").crop_for_item("Wet "+crop+" Seeds")=="" and root.get_node("PlantDB").crop_for_item(crop)=="",crop+" requires dried seeds rather than wet seeds or sliced fruit")
		inv.add(dry,2);var at:=Vector3(20+(index%3)*2,.4 if crop=="Papaya" else .325,floori(index/3.0)*2)
		piece("Foundation",Vector3(at.x,0,at.z));var bed:=piece("TreePot" if crop=="Papaya" else "PlanterPot",at);beds.append(bed)
		player.active_item=dry;player.rope_gun_selected=false;player.aim_valid=true;player.aim_collider=bed;player.aim_point=bed.global_position;player.aim_distance=1
		Input.action_press("interact");player._handle_pickup();Input.action_release("interact");await frames()
		check(bed.has_plant() and inv.total(dry)==1,crop+" plants through the actual player interaction and spends one seed")
		if not bed.has_plant():continue
		var plant: Node3D=bed._plant;plant.set_process(false);var young: float=plant._grow
		plant._process(20);check(plant._grow>young and plant._container.get_child_count()>0,crop+" visibly grows from a small textured sapling")
		plant.restore_state({"id":crop,"stage":3});check(plant.save_state().stage==3,crop+" restores a mature crop")
		var seeds_before: int=inv.total(dry);var fruit_before: int=inv.total(crop)
		if crop=="Papaya":plant._update_fruits(140);plant._pick_fruit(plant._fruits[0])
		else:plant._do_dig();await frames(28)
		check(inv.total(crop)>fruit_before and inv.total(dry)==seeds_before,crop+" harvest gives edible produce; new seeds must be separated from it")
		if not bed.has_plant():bed.plant_seed(crop)
		bed._plant.set_process(false);bed._plant.restore_state({"id":crop,"stage":3});bed.set_process(false)
		if crop=="Papaya":bed._plant._update_fruits(140)
		if bed._plant._progress_ui!=null:bed._plant._progress_ui.hide()
	player.get_node("SurvivalAction").stop();inv.add("Cucumber",2);player.active_item="Cucumber";player.global_position=raft.to_global(Vector3(0,.9,0));player._update_hand_item()
	var prep: Node=player._garden_prep();prep.set_process(false);var whole_before: int=inv.total("Cucumber")
	check(prep.start("Cucumber") and player.get_node("SurvivalAction").kind=="prepare_seed","Cutting starts a dedicated knife / seed separation animation")
	player.global_position.x+=1;prep.advance(.5);check(prep.pending.is_empty() and inv.total("Cucumber")==whole_before,"Moving before preparation finishes keeps the whole fruit")
	check(prep.start("Cucumber"),"A stationary survivor can restart seed preparation")
	prep.advance(2.8);check(inv.total("Cucumber")==whole_before-1 and inv.total("Sliced Cucumber")==1 and inv.total("Wet Cucumber Seeds")==2,"One cut fruit atomically yields cooking portions and two wet seed lots")
	var tray:=piece("SeedDryingTray",Vector3(0,.3,0));tray.set_process(false);player.active_item="Wet Cucumber Seeds";player.aim_collider=tray;player.aim_point=tray.global_position;player.aim_distance=1;player.aim_valid=true
	Input.action_press("interact");player._handle_pickup();Input.action_release("interact");await frames()
	check(tray.count==2 and inv.total("Wet Cucumber Seeds")==0,"The tray takes the held wet seeds without discarding them")
	tray.advance(60);var saved: Dictionary=tray.save_survival_state();tray.seconds=0;tray.restore_survival_state(saved)
	check(tray.seconds==60 and tray.crop=="Cucumber" and tray.count==2,"Drying progress and seed count survive save restoration")
	var rain:=get_first_node_in_group("rain_system");rain.start_rain(120);tray.advance(10)
	check(tray.seconds==60,"Exposed rain pauses seed drying")
	var cover:=StaticBody3D.new();var col:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(2,.1,2);col.shape=shape;cover.add_child(col);current_scene.add_child(cover);cover.global_position=tray.global_position+Vector3.UP*1.5;await frames()
	tray.advance(60);check(tray.seconds==120 and tray.interaction_caption()=="COLLECT DRY SEEDS","A sheltered tray finishes drying even while it rains")
	var original: Array=inv.slots.duplicate(true)
	for index in inv.slots.size():inv.slots[index]={"item":"Metal","count":inv.MAX_STACK}
	inv._recompute();tray.interact_survival(player);check(tray.count==2,"A full bag leaves dry seeds on their tray")
	inv.slots[29]={"item":"Cucumber","count":1};inv._recompute();player.active_item="Cucumber"
	check(not prep.start("Cucumber") and inv.total("Cucumber")==1,"Cutting refuses a full bag when the freed fruit slot cannot hold both rewards")
	inv.slots=original;inv._recompute();inv.changed.emit();player.active_item="Wet Cucumber Seeds";var seed_before: int=inv.total("Dry Cucumber Seeds");tray.interact_survival(player)
	check(tray.empty() and inv.total("Dry Cucumber Seeds")==seed_before+2,"Collected dry seeds can be stored and planted again")
	cover.queue_free();rain.stop_rain();await frames()
	spawner._rare_day=1;spawner._rare_cycle=0;player.survival_day=3;var before: int=spawner._active.size();spawner._tick_rare_supply()
	check(spawner._active.size()==before,"A rare garden box does not spawn before three game days")
	player.survival_day=4;spawner._tick_rare_supply();var box: Node3D=spawner._active.back()
	check(spawner._active.size()==before+1 and box.item_name=="Bell Pepper Garden Box" and box.global_position.distance_to(raft.global_position)>50,"The first rare crate enters from the distant ocean on day four")
	spawner._tick_rare_supply();check(spawner._active.size()==before+1,"Repeated checks cannot duplicate the same three-day delivery")
	player.survival_day=7;spawner._tick_rare_supply();check(spawner._active.back().item_name=="Cucumber Garden Box","The next three-day box introduces another useful edible crop")
	var supply: Dictionary=spawner.save_garden_supply();check(supply.last_day==7 and supply.cycle==2 and supply.boxes.size()==2,"Schedule and unopened floating crates are saved together")
	inv.loaded_meta.garden_supply=supply
	var restored: Node3D=load("res://scripts/debris_spawner.gd").new();restored.debris_scene=load("res://scenes/debris.tscn");restored.prewarm_count=0;restored.set_process(false);current_scene.add_child(restored);await frames()
	check(restored._rare_day==7 and restored._rare_cycle==2 and restored._active.size()==2,"Continue restores the existing rare crates instead of inventing extra ones")
	restored.queue_free();inv.loaded_meta.erase("garden_supply");await frames()
	inv.add("Bell Pepper Garden Box",1);player.active_item="Bell Pepper Garden Box";var dry_before: int=inv.total("Dry Bell Pepper Seeds")
	player.aim_valid=false;player.aim_collider=null;Input.action_press("interact");player._handle_pickup();Input.action_release("interact");await frames()
	check(prep.menu_open and player.get_node("SurvivalServices").is_modal(),"The actual use control opens the held rare box reward review")
	player.get_node("SurvivalServices").close_menu();check(not prep.menu_open,"The shared back/close route releases the garden review menu")
	check(prep.start(player.active_item),"Rare box opening requires a deliberate action")
	prep.advance(2);check(inv.total("Bell Pepper Garden Box")==0 and inv.total("Dry Bell Pepper Seeds")==dry_before+2,"Opening a rare box saves its dry seeds, fruit and recovered parts")
	player.get_node("SurvivalAction").stop();var services:=player.get_node("SurvivalServices");var camp:=piece("Bonfire",Vector3(4,.4,-3));camp.burning=true;camp.fuel=120;services.station=camp;player.global_position=camp.global_position+Vector3(0,.6,1);inv.add("Sliced Pumpkin",1)
	check(services.start_cooking("Roasted Pumpkin"),"Sliced garden harvest works in the existing cooking station")
	var job:=camp.get_node("StationJob");job.advance(12);check(inv.total("Roasted Pumpkin")==1,"Cooking sliced pumpkin delivers a useful cooked meal")
	player.get_node("SurvivalAction").stop();check(player._write_save("quick"),"The real save writer stores the new garden alongside old structures")
	var metadata: Dictionary=inv.load_game("quick");check(metadata.get("garden_supply",{}).last_day==7,"The three-day schedule survives an actual save/load")
	check(metadata.built.any(func(entry):return entry.t=="SeedDryingTray"),"The drying tray uses the backwards-compatible structure save flow")
	await render_art()
	if preview:
		var view:=Camera3D.new();current_scene.add_child(view);view.current=true;view.global_position=raft.to_global(Vector3(27,3.8,-4));view.look_at(raft.to_global(Vector3(22,.9,1)))
		player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot").hide();await shot("garden-edible-plants")
		view.queue_free();player.camera.current=true;player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot").show();player.camera.global_position=raft.to_global(Vector3(0,2,1));player.camera.look_at(raft.to_global(Vector3(0,1.4,-2)))
		root.size=Vector2i(390,844);await frames();inv.add("Cucumber",1);player.active_item="Cucumber";player._update_hand_item();prep.use("Cucumber");await shot("garden-seed-preparation-mobile");prep.close()
		prep.start("Cucumber");var animation:=player.get_node("SurvivalAction");animation.set_process(false);animation.elapsed=2.1;animation._process(0);await shot("garden-cutting-animation-mobile");prep.pending.clear();animation.stop()
	var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud.toggle_crafting();await frames();hud._craft_menu.select_item("SeedDryingTray");await frames()
	check(hud._craft_menu.cards.has("SeedDryingTray") and hud._craft_menu._build.text=="Build","The scrollable craft menu exposes the seed tray and confirmation")
	await shot("garden-seed-tray-craft-mobile");hud._close_crafting()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();current_scene=null;player=null;raft=null;built=null;inv=null;beds.clear();await frames(8)
	print("GARDEN CYCLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
