extends SceneTree
var checks:=0
var failures:=0
var preview:=false
var player: Node3D
var raft: Node3D
var built: Node3D
var inv: Node
var camera: Camera3D
func _initialize() -> void:
	create_timer(100).timeout.connect(func():push_error("FAIL: realism timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func shot(label: String) -> void:
	if not preview:return
	await frames(8);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/realism-"+label+".png")==OK,"Rendered "+label)
func fixture(kind: String,at: Vector3) -> Node3D:
	var piece: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	piece.name=kind+"_Realism"+str(piece.get_instance_id());piece.position=at;built.add_child(piece);piece.add_to_group("build_surface")
	if kind=="Foundation":player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),piece)
	return piece
func place(kind: String,at: Vector3,support: Node3D) -> Node3D:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_point=raft.to_global(at);player.aim_collider=support;player.aim_normal=Vector3.UP;player.aim_valid=true;player.aim_distance=3.0
	player.camera.global_position=player.aim_point+Vector3(0,3,3);player.camera.look_at(player.aim_point)
	player.call("_update_build_preview")
	var plan: Dictionary=player.call("_resolve_placement",kind,player.aim_point)
	if not plan.get("valid",false):print("SALVAGE PLAN ",kind," ",plan," ",player._diag)
	check(plan.get("valid",false),"Salvaged "+kind+" has supported green placement")
	player.call("_try_build");await frames()
	for piece in built.get_children():
		if str(piece.name).begins_with(kind):return piece
	return null
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false;root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false)
	await frames(140)
	player.get_node("RainSystem").call("stop_rain")
	raft.rotation=Vector3.ZERO;player.global_position=raft.to_global(Vector3(2,1.1,2))
	check(raft.get_node_or_null("StarterRaftVisual/DecorativeRig")==null,"Starter raft has no decorative white flag")
	var rules:=preload("res://scripts/food_rules.gd")
	for dish in rules.RECIPES:
		var picture:=preload("res://scripts/item_art.gd").food_texture(dish)
		check(picture!=null and picture.get_width()>=64 and picture.get_height()>=64,"Current photographic or rendered food picture loads: "+dish)
		var food:=preload("res://scripts/meal_visual.gd").create(dish)
		check(food.get_node_or_null("SlicedIngredients")!=null,"Dish contains recognizable sliced ingredients: "+dish);food.free()
	fixture("Foundation",Vector3(2,0,0));fixture("Foundation",Vector3(2,0,2));fixture("Foundation",Vector3(4,0,2));fixture("Foundation",Vector3(6,0,2))
	var deck:=fixture("Foundation",Vector3(4,0,4));var deck2:=fixture("Foundation",Vector3(6,0,4));await frames()
	var pool: Array=load("res://scripts/debris_spawner.gd").get_script_constant_map()["ITEM_POOL"]
	check(pool.has("WindGenerator") and not pool.has("ElectricLamp") and pool.has("Solar Torch"),"Weathered generator and portable torch replace new lamps in debris")
	var bag_snapshot: Array=inv.slots.duplicate(true)
	for slot in inv.SLOT_COUNT:inv.slots[slot]={"item":"Stone","count":inv.MAX_STACK}
	inv.call("_recompute");inv.changed.emit()
	var full_bag_salvage: Node3D=load("res://scenes/debris.tscn").instantiate();full_bag_salvage.item_name="WindGenerator";current_scene.add_child(full_bag_salvage)
	player.call("_collect_debris",full_bag_salvage)
	check(not full_bag_salvage.collected and not full_bag_salvage.is_queued_for_deletion(),"Full bag keeps rare generator salvage in the ocean")
	full_bag_salvage.queue_free();inv.slots=bag_snapshot;inv.call("_recompute");inv.changed.emit()
	for kind in ["WindGenerator","ElectricLamp"]:
		var debris: Node3D=load("res://scenes/debris.tscn").instantiate();debris.item_name=kind;current_scene.add_child(debris)
		check(debris._model_visual.get_node_or_null("RecoveredEquipment")!=null,"Floating equipment has its own recognizable model")
		player.call("_collect_debris",debris);await frames()
		check(int(inv.call("total",kind))==1 and inv.call("recipe_cost",kind)=={kind:1},"Collected kit is the entire placement cost")
		check(inv.call("recipe_unlocked",kind),"Owned salvage can be installed at any campaign level")
		var action:=player.get_node("SurvivalAction");action.set_process(false);action.elapsed=.1;action.call("_process",0.0)
		check(action._pickup_first!=null and not action._pickup_first.visible,"Pickup reaches with an empty palm")
		action.elapsed=.5;action.call("_process",0.0)
		check(action._pickup_first.visible and action._pickup_third.visible,"Grip carries actual collected equipment in both views")
		if kind=="ElectricLamp":
			if player.build_mode:player.call("_toggle_build")
			player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true
			await shot("pickup")
		action.call("stop")
	var metal: int=inv.call("total","Metal")
	var generator:=await place("WindGenerator",Vector3(4,.15,4),deck)
	var lamp:=await place("ElectricLamp",Vector3(6,.15,4),deck2)
	check(generator!=null and lamp!=null,"Both recovered machines install on foundations")
	if generator==null or lamp==null:quit(1);return
	check(int(inv.call("total","WindGenerator"))==0 and int(inv.call("total","ElectricLamp"))==0 and int(inv.call("total","Metal"))==metal,"Installation consumes kits once without spending extra metal")
	generator.set_process(false);lamp.set_process(false);generator.charge=10;lamp.automatic_night=false;lamp.call("advance",1.0)
	check(lamp._light.visible and generator.charge<10 and lamp._bulb_material.emission_energy_multiplier>0,"Installed generator powers the LED lens and nearby light")
	var saved: Array=player.call("_serialize_built_pieces");var kit_saves: Array=[]
	for entry in saved:
		if entry.t in ["WindGenerator","ElectricLamp"]:kit_saves.append(entry)
	check(kit_saves.size()==2 and kit_saves[0].cost=={"WindGenerator":1},"Save records the exact salvaged construction cost")
	if player.build_mode:player.call("_toggle_build")
	camera=Camera3D.new();current_scene.add_child(camera);camera.current=true
	camera.global_position=raft.to_global(Vector3(8,3.8,7));camera.look_at(generator.global_position+Vector3(.8,.7,0))
	await shot("equipment")
	generator.queue_free();lamp.queue_free();await frames()
	inv.loaded_meta["built"]=kit_saves;await player.call("_restore_built_pieces");inv.loaded_meta["built"]=[];await frames()
	var restored: Node3D
	for piece in built.get_children():
		if str(piece.name).begins_with("WindGenerator"):restored=piece
	check(restored!=null and restored.get_meta("construction_cost",{})=={"WindGenerator":1},"Continue preserves kit refund rather than minting raw materials")
	player._editing=restored;player.call("_remove_editing");await frames()
	check(int(inv.call("total","WindGenerator"))==1 and int(inv.call("total","Metal"))==metal,"Removing salvaged generator returns exactly its kit")
	var service:=player.get_node("SurvivalServices");service.set_process(false)
	var fire:=fixture("CookingSetup",Vector3(2,.25,4));fire.set_process(false);fire.burning=true;fire.fuel=100
	camera.global_position=fire.global_position+Vector3(.8,1.2,.9);camera.look_at(fire.global_position+Vector3.UP*.48)
	var job: Node3D=service.call("ensure_job",fire);job.set_process(false)
	job.call("restore_job",{"kind":"cook","item":"Root Vegetable Soup","remaining":12.0})
	check(job._steam.visible and job._steam.get_child_count()==3,"Hot cooking uses three soft steam ribbons without particles")
	check(job._meal.get_node("SlicedMeal").get_node_or_null("Broth")!=null,"Soup contains liquid and cut roots")
	await shot("cooking")
	fire.burning=false;job.call("_sync_visual");check(not job._steam.visible,"Extinguished cooking stops steam immediately")
	fire.burning=true;service.station=fire;service.call("open_cooking",fire);await frames()
	var pictures: Array=service.ui._body.find_children("DishPicture","TextureRect",true,false)
	check(pictures.size()==preload("res://scripts/food_rules.gd").RECIPES.size()+1 and pictures.all(func(pic: TextureRect):return pic.texture!=null),"Every food and boiling menu row has a loaded dish picture")
	await shot("food-menu");service.call("close_menu")
	var flowers:=preload("res://scripts/flower_visual.gd").meadow_mesh()
	check(flowers==preload("res://scripts/flower_visual.gd").meadow_mesh() and flowers.get_faces().size()<12000,"Curved petals, leaves and stems share one bounded flower mesh")
	var cluster:=MeshInstance3D.new();cluster.mesh=flowers;cluster.position=raft.to_global(Vector3(0,.3,4));current_scene.add_child(cluster)
	camera.global_position=cluster.global_position+Vector3(.42,.4,.55);camera.look_at(cluster.global_position+Vector3.UP*.25);await shot("flowers")
	var atmosphere:=current_scene.get_node("OceanAtmosphere");atmosphere.set_process(false)
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.set_process(false)
	var dome:=current_scene.get_node("Sky3D/SkyDome")
	var palettes: Array=[]
	for date in range(1,7):
		var profile: Dictionary=atmosphere.call("sky_profile_for_day",date)
		check(profile==atmosphere.call("sky_profile_for_day",date),"Daily sky remains deterministic after Continue")
		if date>1:check(profile!=palettes.back(),"Consecutive days have different sky palettes")
		palettes.append(profile)
	for variant in ["day-one","day-two","sunset","night"]:
		clock.day=9 if variant!="day-two" else 10
		clock.current_time=23.0 if variant=="night" else (18.0 if variant=="sunset" else 12.0)
		clock.call("_process",0.0);atmosphere.call("_process",1.0)
		camera.global_position=raft.to_global(Vector3(0,2,-2));camera.look_at(camera.global_position+Vector3(-5,2,-20))
		await shot("sky-"+variant)
	check(not current_scene.get_node("Sky3D").environment.fog_enabled,"Mobile sky variety keeps global fog disabled")
	check(not dome.sky_material.get_shader_parameter("cumulus_visible"),"Mobile sky retains its cheap cloud path")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(20)
	print("REALISM POLISH SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
