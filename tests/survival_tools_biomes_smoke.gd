extends SceneTree
const TOOLS := preload("res://scripts/survival_tool_visual.gd")
var checks:=0
var failures:=0
var inv: Node
var player: CharacterBody3D
var tools: Node
var preview:=false
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func equip(item: String) -> void:
	if not inv.call("has",item,1):inv.call("add",item,1)
	for index in inv.SLOT_COUNT:
		if inv.call("slot_item",index)==item:
			inv.call("swap_slots",index,0);player.call("select_hotbar_slot",0);return
func aim(node: Node3D,at: Vector3) -> void:
	player.aim_collider=node;player.aim_valid=true;player.aim_point=at;player.aim_normal=Vector3.UP;player.aim_distance=2.0
func shot(label: String) -> void:
	if not preview:return
	await frames(8);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/tools-biomes-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	create_timer(100.0).timeout.connect(func():push_error("Tools/biomes fixture timed out");quit(1))
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");tools=player.get_node("SurvivalTools");tools.set_physics_process(false)
	var raft:=get_first_node_in_group("raft") as Node3D;raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	var volcano:=current_scene.get_node("VolcanoIsle") as Node3D
	var winter:=current_scene.get_node("WinterIsle") as Node3D
	for unused in 1800:
		await frames(1)
		if volcano.prepared and winter.prepared and current_scene.get_node("SpringIsle").prepared and current_scene.get_node("UnderwaterWorld").prepared and player.restoration_complete:break
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RainSystem").call("stop_rain")
	var action:=player.get_node("SurvivalAction");action.set_process(false)
	check(volcano.prepared and winter.prepared,"Both biomes finish their bounded setup")
	if not volcano.prepared or not winter.prepared:quit(1);return
	check(get_nodes_in_group("island").size()==7,"Existing four islands plus three additive destinations")
	check(volcano.position==Vector3(-1500,0,900) and winter.position==Vector3(1100,0,-1300),"New biomes retain stable remote coordinates")
	check(volcano.get_meta("arrival_radius")==52.0,"Large islands use a safe sailing arrival radius")
	for island in [volcano,winter]:
		var terrain:=island.get_node("BiomeTerrain") as MeshInstance3D
		check(terrain.mesh.surface_get_array_len(0)==2809,str(island.name)+" has bounded indexed terrain")
		check(island.get_node("BiomeGround/CollisionShape3D").shape is ConcavePolygonShape3D,str(island.name)+" has real terrain collision")
		check(island.find_children("*","GPUParticles3D",true,false).is_empty(),str(island.name)+" adds no smoke, fog or particles")
		var at:Vector3=island.to_global(Vector3(22,30,0))
		var exclude:Array[RID]=[]
		for resource in get_nodes_in_group("biome_resource"):exclude.append(resource.get_rid())
		var hit:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at,at+Vector3.DOWN*50,1,exclude))
		check(not hit.is_empty() and absf(Vector3(hit.position).y-float(island.call("height_at",Vector2(22,0))))<.35,str(island.name)+" collision matches its visible terrain")
	check(volcano.get_node("CraterLava").material_override.shader.resource_path.ends_with("volcanic_lava.gdshader"),"Crater uses animated emissive lava")
	check(volcano.call("is_lava",Vector3(0,15,0)) and not volcano.call("is_lava",Vector3(20,3,0)),"Lava damages only its actual pool/channel")
	check(winter.get_node("Spruce6/ResourceVisual/SnowyNeedles").mesh==winter.get_node("Spruce7/ResourceVisual/SnowyNeedles").mesh,"Snowy trees share one wind animated mesh")
	check(get_nodes_in_group("biome_resource").size()==44,"Finite resources and winter trees have a fixed population")
	var ocean:=current_scene.get_node("Ocean")
	check(ocean._shore_zones.size()==7 and ocean._shore_zones[4].z==44 and ocean._shore_zones[5].z==44,"Both new coasts feed their own compact water masks")
	var hud:=player.get_node("CanvasLayer/SurvivalHUD")
	hud._map_open=true;hud.call("_compute_layout")
	check(hud._map_markers.size()==10,"Map lists every island and diving destination")
	var all_fit:=true
	for marker in hud._map_markers:all_fit=all_fit and Vector2(marker.pos).distance_to(hud._map_center)<float(hud._map_plot_radius)
	check(all_fit,"Distant islands remain visible and selectable inside the chart")
	await shot("map")
	hud._map_open=false
	for item in TOOLS.ITEMS:
		check(inv.ITEM_RECIPES.has(item) and item in hud.CRAFT_ORDER,item+" has a visible crafting recipe")
		var before:int=inv.call("total",item)
		var metal_cost:int=inv.ITEM_RECIPES[item].get("Metal",0);var before_metal:int=inv.call("total","Metal")
		var made:bool=inv.call("craft_item",item)
		check(made and inv.call("total",item)==before+1 and inv.call("total","Metal")==before_metal-metal_cost,item+" crafts one item and spends its actual materials")
		var model:=TOOLS.create(item)
		check(model.find_children("*","MeshInstance3D",true,false).size()>1,item+" uses an identifiable original tool model")
		model.free()
		equip(item)
		check(player._hand_item.find_child(item+"Tool",true,false)!=null,item+" is held in first person")
		action.call("_sync_held")
		check(action._held!=null and action._held.find_child(item+"Tool",true,false)!=null,item+" is held in third person")
	hud.toggle_crafting();hud._craft_menu.select_item("Pickaxe");await shot("crafting");hud._close_crafting()
	var deposit:=volcano.get_node("Mineral0") as Node3D
	player.global_position=deposit.global_position+Vector3(0,1.5,2)
	equip("Pickaxe");aim(deposit,deposit.global_position);tools.cooldown=0
	var metal_before:=int(inv.call("total","Metal"))
	check(tools.call("use"),"Aimed pickaxe starts one mining swing")
	tools.call("advance",.2);check(deposit.health==4,"Mining does not award before tool contact")
	player.active_item="Shovel";tools.call("advance",.4)
	check(deposit.health==4 and tools.pending.is_empty(),"Changing equipment cancels the unfinished swing")
	equip("Pickaxe");tools.cooldown=0;aim(deposit,deposit.global_position);tools.call("use");player.aim_distance=8;tools.call("advance",.6)
	check(deposit.health==4,"Leaving reach cancels mining without a reward")
	player.aim_distance=2;tools.cooldown=0;tools.call("use");hud._bag_open=true;tools.call("advance",.6);hud._bag_open=false
	check(deposit.health==4,"Opening the bag cancels tool contact")
	for hit in 4:
		tools.cooldown=0;aim(deposit,deposit.global_position);check(tools.call("use"),"Mining swing %d is accepted"%hit)
		tools.call("advance",.6);tools.call("advance",.4)
		deposit._cooldown=0
	check(deposit.health==0 and deposit.collision_layer==0,"Four impacts empty the deposit and remove its collision")
	check(int(inv.call("total","Metal"))==metal_before+2,"Mined resources are awarded exactly once")
	tools.cooldown=0;check(not tools.call("use"),"Empty deposits cannot be mined repeatedly")
	var full_deposit:=volcano.get_node("Mineral1") as Node3D;full_deposit.health=1
	var saved_slots:Array=inv.slots.duplicate(true)
	for slot in inv.SLOT_COUNT:inv.slots[slot]={"item":"Stone","count":inv.MAX_STACK}
	inv.slots[0]={"item":"Pickaxe","count":inv.MAX_STACK};inv.call("_recompute");player.active_item="Pickaxe"
	player.global_position=full_deposit.global_position+Vector3(0,1.5,2)
	check(not full_deposit.call("tool_hit",player,"Pickaxe") and full_deposit.health==1,"A full bag keeps the final deposit hit and its resources")
	for slot in inv.SLOT_COUNT:inv.slots[slot]={"item":["Wood","Metal","Rope","Stone","Plastic"][slot%5],"count":inv.MAX_STACK}
	inv.call("_recompute");var packed_slots:Array=inv.slots.duplicate(true)
	check(not inv.call("craft_item","Anchor") and inv.slots==packed_slots,"Full bag crafting rolls back all tool materials")
	inv.slots=saved_slots;inv.call("_recompute")
	var tree:=winter.get_node("Spruce6") as Node3D;equip("Axe");player.global_position=tree.global_position+Vector3(0,1.5,2);aim(tree,tree.global_position)
	check(tree.call("tool_hit",player,"Axe") and tree.health==2,"Axe cuts twice as effectively")
	tree._cooldown=0;check(tree.call("tool_hit",player,"Axe") and tree.health==0,"Winter trees can be felled and collected")
	equip("Potato");aim(winter.get_node("BiomeGround"),tree.global_position)
	check(player.call("_plant_on_ground"),"A cleared winter tree location can be planted without a pot")
	tree.regrow_wait=0;tree.call("advance_tree",.5)
	check(tree.health==0,"The seeded crop prevents natural tree regrowth in its clearing")
	for plot in get_nodes_in_group("ground_plot"):
		if plot.global_position.distance_to(tree.global_position)<1:plot.queue_free()
	await frames(2)
	tree.call("advance_tree",.5)
	check(tree.health==4 and tree.growth<1 and tree.collision_layer==0,"An empty clearing starts a small natural tree without blocking the player")
	equip("Potato");aim(winter.get_node("BiomeGround"),tree.global_position)
	check(player.call("_plant_on_ground"),"A seeded crop can also replace a young natural sapling")
	tree.call("advance_tree",.5);check(tree.health==0,"Player seeding takes priority over an already growing natural tree")
	for plot in get_nodes_in_group("ground_plot"):
		if plot.global_position.distance_to(tree.global_position)<1:plot.queue_free()
	await frames(2)
	tree.regrow_wait=0
	tree.call("advance_tree",30.0)
	check(tree.growth==1 and tree.collision_layer==1,"The regrown winter tree becomes harvestable after growing")
	equip("Shovel");var ground:=winter.get_node("BiomeGround") as Node3D
	var earth:=winter.to_global(Vector3(24,winter.call("height_at",Vector2(24,0)),0));player.global_position=earth+Vector3(0,1.5,1)
	aim(ground,earth);tools.cooldown=0;var soil_before:=int(inv.call("total","Soil"))
	check(tools.call("use"),"Shovel starts on reachable dry ground")
	tools.call("advance",.6);tools.call("advance",.4)
	check(int(inv.call("total","Soil"))==soil_before+3,"Shovel gathers three soil with one capacity safe transaction")
	check(action.LABELS.has("mine") and action.LABELS.has("paddle") and action.LABELS.has("anchor"),"New actions have their own visible feedback")
	for item in ["Pickaxe","Shovel","Paddle","Anchor"]:
		equip(item);var kind:String={"Pickaxe":"mine","Shovel":"dig","Paddle":"paddle","Anchor":"anchor"}[item]
		action.call("play",kind,1.0,Vector3.ZERO);action.elapsed=.45
		var pose:Dictionary=action.call("sample_pose")
		check(pose.weight>.8 and action._tool!=null and action._view_tool!=null,item+" animates both hands/tool in both camera views")
	check(raft.call("paddle_stroke",Vector3.FORWARD),"A paddle propels an unupgraded raft")
	var next:Vector3=raft.call("navigation_position",.5)
	check(next.z<raft.global_position.z and raft._paddle_velocity.length()<1.35,"Rowing uses direction, momentum and water drag")
	raft.call("set_anchored",true,false)
	check(not raft.call("paddle_stroke",Vector3.FORWARD) and raft.call("navigation_position",1.0)==raft.global_position,"Dropped anchor stops movement and rowing")
	raft.call("set_upgrade_tier",1)
	check(not raft.call("set_course",winter.global_position,52.0),"Anchor prevents a sail course until raised")
	check(player.call("_write_save","quick"),"New tool/biome state writes an authenticated isolated save")
	check(inv.call("load_game","quick") and inv.loaded_meta.raft_anchored and inv.loaded_meta.biome_resources[deposit.resource_id]==0,"Anchor and exhausted deposits survive an actual save/load")
	var restored:Node3D=load("res://scripts/biome_resource.gd").new();restored.resource_id=deposit.resource_id;current_scene.add_child(restored)
	check(restored.health==0 and restored.collision_layer==0,"Saved exhausted deposits restore without respawning loot");restored.queue_free()
	raft.call("set_anchored",false,false)
	check(raft.call("set_course",winter.global_position,52.0) and raft._arrival_radius==52,"Raised anchor restores sailing with shore clearance")
	var invalid:Dictionary={"slots":[],"biome_resources":{"bad":"wrong"}}
	check(not preload("res://scripts/save_storage.gd")._valid_save(invalid),"Malformed biome save records are rejected safely")
	check(preload("res://scripts/save_storage.gd")._valid_save({"slots":[]}),"Legacy saves remain valid without tool/biome metadata")
	# Exercise the actual HAND/E dispatch aboard the original compound raft.
	player.global_position=raft.global_position+Vector3(0,1.25,0);player.velocity=Vector3.ZERO;player.is_swimming=false
	player.set_physics_process(true);await frames(20);player.set_physics_process(false)
	equip("Paddle");raft.clear_course();raft._paddle_velocity=Vector3.ZERO;tools.cooldown=0
	var progress:=player.get_node("SurvivalProgression");progress.stamina=100.0
	check(tools.call("can_use") and tools.call("use"),"Paddle action is available only when actually aboard")
	tools.call("advance",.3);check(raft._paddle_velocity==Vector3.ZERO,"Rowing waits for paddle water contact")
	tools.call("advance",.4);check(raft._paddle_velocity.length()>1 and progress.stamina==94.0,"Water contact gives one impulse and spends six stamina")
	tools.call("advance",.5);equip("Anchor");tools.cooldown=0
	check(tools.call("use"),"Anchor uses the same owned interaction button aboard")
	tools.call("advance",.6);tools.call("advance",.4)
	check(raft.anchored and tools.call("caption")=="RAISE ANCHOR","Anchor action changes the actual raft and button caption")
	tools.cooldown=0;check(tools.call("use"),"The same reusable anchor can be raised")
	tools.call("advance",.6);tools.call("advance",.4)
	check(not raft.anchored,"Raising the anchor releases navigation")
	player.global_position=volcano.global_position+Vector3(0,15,0);tools.cooldown=0;equip("Paddle")
	check(not tools.call("can_use"),"Standing on island land cannot propel a nearby raft")
	var stats:=root.get_node("Stats");stats.health=100;stats.enabled=true
	volcano._tick=0;volcano.call("_process",.5)
	check(stats.health==95 and volcano._status.text.contains("LAVA"),"Actual lava contact damages health and warns the player")
	player.global_position=winter.to_global(Vector3(22,winter.call("height_at",Vector2(22,0))+1,0));winter.winter_exposure=179.8;winter._tick=0
	winter.call("_process",.5)
	check(stats.health<95 and winter._status.text.contains("COLD"),"Prolonged winter exposure warns and slowly damages health")
	equip("Burning Torch");progress.torch_fuel=50;var cold_before:float=winter.winter_exposure;winter._tick=0;winter.call("_process",.5)
	check(winter.winter_exposure<cold_before and winter._status.text=="WARMING UP","A lit torch warms the survivor in winter")
	stats.enabled=false
	# Presentation views use the real game world and camera, not mockups.
	var sky:=current_scene.get_node("Sky3D");sky.current_time=12.0
	player.cam_mode=0;player.call("_apply_camera_mode",true)
	player.camera.top_level=true;action.call("stop");player._hand_item.hide();player.get_node("CanvasLayer").hide()
	player.get_node("SurvivalServices").ui.hide()
	for island in [volcano,winter]:
		player.global_position=island.global_position+Vector3(46,52,48);player.camera.global_position=player.global_position
		player.camera.look_at(island.global_position+Vector3(0,7,0));action.call("stop");player._hand_item.hide();await shot("volcano" if island==volcano else "winter")
	player.get_node("CanvasLayer").show();player._hand_item.show()
	player.global_position=full_deposit.global_position+Vector3(0,1.5,2.2)
	player.camera.global_position=player.global_position+Vector3(0,.45,0);player.camera.look_at(full_deposit.global_position+Vector3(0,.6,0))
	equip("Pickaxe");action.call("play","mine",1.0,full_deposit.global_position);action.elapsed=.50;action.call("_process",0.0)
	await shot("mining-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode",true);player.camera.global_position=player.global_position+Vector3(2.6,1.9,3.4)
	player.camera.look_at(player.global_position+Vector3(0,.35,0));action.call("_process",0.0);await shot("mining-third-person")
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(20)
	print("TOOLS AND BIOMES SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
