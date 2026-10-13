extends SceneTree
const SAVE:=preload("res://scripts/save_storage.gd")
var checks:=0
var failures:=0
var player:CharacterBody3D
var inv:Node
var preview:=false
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count:int=3) -> void:
	for unused in count:await physics_frame
func equip(item:String) -> void:
	if not inv.call("has",item,1):inv.call("add",item,1)
	for slot in inv.SLOT_COUNT:
		if inv.call("slot_item",slot)==item:inv.call("swap_slots",slot,0);player.call("select_hotbar_slot",0);return
func aim(node:Node3D,point:Vector3) -> void:
	player.aim_valid=true;player.aim_collider=node;player.aim_point=point;player.aim_normal=Vector3.UP;player.aim_distance=2
func shot(label:String) -> void:
	if not preview:return
	await frames(8);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/underwater-"+label+".png")==OK,"Rendered "+label)
func stand(raft:Node3D) -> void:
	player.global_position=raft.global_position+Vector3(0,1,0);player.velocity=Vector3(0,-2,0)
	for unused in 14:player.move_and_slide();await frames(1)
	player.is_swimming=false
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(240).timeout.connect(func():push_error("FAIL: underwater fixture timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false
	var stats:=root.get_node("Stats");stats.enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player") as CharacterBody3D
	var sea:=current_scene.get_node("UnderwaterWorld")
	var spring:=current_scene.get_node("SpringIsle")
	var winter:=current_scene.get_node("WinterIsle")
	var volcano:=current_scene.get_node("VolcanoIsle")
	# Process-frame counts vary dramatically between Dummy and real renderers.
	# Wait on physical frames with a wall-clock bound for asynchronous startup.
	# This full-world headless fixture includes every imported island/model.
	# Its time bound is a deadlock guard, not a phone loading benchmark.
	var startup_deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<startup_deadline:
		await physics_frame
		if sea.prepared and spring.prepared and winter.prepared and volcano.prepared and player.restoration_complete and player.get_node("SurvivalAction").hands_prepared and player.get_node("SurvivalServices").ui.cooking_prepared:break
	if not sea.prepared:
		print("SEA SETUP: ",sea.get_children().map(func(node:Node):return str(node.name)))
	check(sea.prepared and spring.prepared and winter.prepared and volcano.prepared and player.restoration_complete,"Diving and all biome islands finish bounded startup (sea=%s spring=%s winter=%s volcano=%s player=%s)"%[sea.prepared,spring.prepared,winter.prepared,volcano.prepared,player.restoration_complete])
	if not sea.prepared or not spring.prepared or not winter.prepared or not volcano.prepared:quit(1);return
	player.set_process(false);player.set_physics_process(false)
	# This fixture exercises aimed first-person gathering/diving even when a
	# previous isolated suite persisted the owner's third-person preference.
	player.cam_mode=0;player.call("_apply_camera_mode")
	player.set_process_unhandled_input(false);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var raft:=get_first_node_in_group("raft") as Node3D;raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false);player.get_node("RainSystem").call("stop_rain")
	var progress:=player.get_node("SurvivalProgression");progress.set_process(false)
	var action:=player.get_node("SurvivalAction");action.set_process(false)
	var tools:=player.get_node("SurvivalTools");tools.set_physics_process(false)
	var hud:=player.get_node("CanvasLayer/SurvivalHUD")
	if preview:player.get_node("CanvasLayer/MobileControls").force_show=true
	check("Torch" in hud.CRAFT_ORDER and "Diving Tank" in hud.CRAFT_ORDER and "Bonfire" not in hud.CRAFT_ORDER and inv.RECIPES.has("Bonfire"),"Torch and air tank stay in portable Craft; bonfire stays in Build")
	check(inv.ITEM_RECIPES["Diving Tank"]=={"Plastic":8,"Rope":3,"Metal":2},"Air tank uses salvaged plastic, lashings and fittings")
	check(progress.call("unlocked","Diving Tank"),"Diving equipment is available from the first level")
	check(get_nodes_in_group("island").size()==7 and get_nodes_in_group("dive_site").size()==3,"Seven islands and three diving destinations exist")
	hud._map_open=true;hud.call("_compute_layout")
	check(hud._map_markers.size()==10,"Map includes spring, winter, volcano and submerged sites")
	var original_rotation:Vector3=player.rotation;player.rotation.y=0
	var north:=hud.call("map_player_arrow") as PackedVector2Array
	player.rotation.y=-PI/2
	var east:=hud.call("map_player_arrow") as PackedVector2Array
	check(north[0].y<north[2].y and east[0].x>east[2].x,"Map player arrow turns with the survivor's facing direction")
	player.rotation=original_rotation
	await shot("map");hud._map_open=false
	check(current_scene.get_node("Ocean")._shore_zones[6].z==44,"Spring has its own water shoreline mask")
	var debris:=current_scene.get_node("DebrisSpawner")
	check(debris.current_speed<=.35,"Floating loot drifts with a slow ocean current")
	check(raft.float_height<.08 and raft.follow_speed>=8,"Raft logs sit into water and settle promptly after a swell")
	check(spring.get_node("IslandSetup/WildPlants").prepared and spring.get_node("IslandSetup/WildPlants").records.size()>=30,"Spring meadow contains clearable trees, plants and flowers")
	check(spring.get_node("BiomeTerrain").material_override.get_shader_parameter("spring")==true,"Spring terrain has its own grass and beach material")
	check(current_scene.get_node("WinterIsle").find_children("GlacialIce*","MeshInstance3D",true,false).size()==8,"Winter has grounded blue glacial outcrops")
	var floor_node:=sea.get_node("CollectibleSeabed") as StaticBody3D
	player.global_position=Vector3(145,-2,85)
	sea.stream.call("request_position",Vector2(145,85))
	for unused in 240:
		await frames(1)
		if sea.stream.call("ready_at",Vector2(145,85)):break
	var from:=Vector3(145,float(sea.call("surface_height",Vector2(145,85)))+3,85)
	var hit:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+Vector3.DOWN*40,1))
	check(not hit.is_empty() and hit.collider==floor_node and absf(Vector3(hit.position).y-float(sea.call("surface_height",Vector2(145,85))))<.01,"Sand floor collision matches interpolated mesh heights")
	check(sea.get_node("OceanSandFloor").mesh.surface_get_array_len(0)==4225,"The broad ocean floor has a fixed mesh budget")
	check(sea.find_children("RuinedHouse*","Node3D",false,false).size()==18,"Two deep sites contain ruined neighbourhoods with openings")
	check(sea.find_children("BrokenWalls","MeshInstance3D",true,false).size()==18,"Ruins merge wall rendering into one mesh per building")
	check(sea.find_children("SeaGrass*","MultiMeshInstance3D",false,false).size()==3,"Sea plants use three shared instanced batches")
	var creatures:=get_nodes_in_group("dive_creature")
	check(creatures.size()==30,"Fish, crabs, turtles and rays have a fixed huntable population")
	check(get_nodes_in_group("underwater_shoal").size()==3 and get_nodes_in_group("underwater_shoal")[0].COUNT==24,"Three moving schools contain 72 instanced background fish")
	check(sea._kelp_material.get_shader_parameter("leaf_texture") is Texture2D,"Sea fronds have a shared botanical vein texture")
	for creature in creatures:creature.set_physics_process(false)
	player.global_position=Vector3(145,float(sea.call("surface_height",Vector2(145,85)))+.3,85);player.is_swimming=true
	player.active_item="";player.call("_update_hand_item");aim(floor_node,Vector3(hit.position))
	var sand_before:int=inv.call("total","Sand");floor_node.call("interact_survival",player)
	check(inv.call("total","Sand")==sand_before+1,"Empty-hand underwater gathering gives one sand")
	equip("Shovel");tools.cooldown=0;aim(floor_node,Vector3(hit.position))
	check(tools.call("use"),"Shovel can dig actual seabed")
	tools.call("advance",.2);check(inv.call("total","Sand")==sand_before+1,"Shovel does not award sand before contact")
	tools.call("advance",.4);check(inv.call("total","Sand")==sand_before+4,"Seabed shovel gives three sand at contact")
	tools.call("advance",.4)
	var fish:=creatures[0] as Node3D;var crab:=creatures[6] as Node3D
	player.global_position=fish.global_position+Vector3(0,-1.0,1.8);player.is_swimming=true
	equip("Spear");tools.cooldown=0;aim(fish,fish.global_position)
	var fish_before:int=inv.call("total","Fish")
	check(player.call("interaction_caption")=="HUNT FISH" and tools.call("use"),"Aimed fish offers a spear hunting action")
	check(action.kind=="strike" and action._view_tool!=null,"Spear thrust has a visible first-person prop")
	action.elapsed=.46
	if preview:player.camera.top_level=true;player.camera.global_position=player.global_position+Vector3.UP*.9;player.camera.look_at(fish.global_position)
	await shot("spear")
	if preview:player.camera.top_level=false;player.camera.transform=Transform3D.IDENTITY
	tools.call("advance",.2);check(fish.health==20 and inv.call("total","Fish")==fish_before,"Hunt waits for the contact pose")
	tools.call("advance",.4);check(fish.respawn==600 and inv.call("total","Fish")==fish_before+1,"Successful spear hit collects a fish and starts its regrowth timer")
	tools.call("advance",.4);action.call("stop")
	player.global_position=crab.global_position+Vector3(0,-.5,1.8);aim(crab,crab.global_position);tools.cooldown=0
	var crab_before:int=inv.call("total","Raw Crab");tools.call("use");tools.call("advance",.6)
	check(crab.respawn==600 and inv.call("total","Raw Crab")==crab_before+1,"Seabed crabs can be hunted and collected for cooking")
	tools.call("advance",.4);action.call("stop")
	var slots:Array=inv.slots.duplicate(true)
	for index in inv.SLOT_COUNT:inv.slots[index]={"item":"Wood","amount":999}
	inv.call("_recompute");var healthy:=creatures[1]
	healthy.call("take_damage",38,player)
	check(healthy.health>0 and healthy.respawn==0,"Full bag preserves a hunted creature")
	player.global_position=Vector3(145,float(sea.call("surface_height",Vector2(145,85)))+.3,85);aim(floor_node,Vector3(hit.position));floor_node._cooldown=0;floor_node.call("interact_survival",player)
	check(inv.call("total","Sand")==0,"Full bag gathering cannot lose or invent a sand reward")
	inv.slots=slots;inv.call("_recompute")
	check(sea.call("save_state")[fish.creature_id].respawn==600,"Caught underwater creatures persist by stable identity")
	var legacy:Dictionary={"version":1,"slots":[],"progression":{"diving_tank":true}}
	check(SAVE._valid_save(legacy),"Legacy saves without air or underwater fields remain valid")
	legacy.progression["air_tank_seconds"]="bad";check(not SAVE._valid_save(legacy),"Malformed tank time is rejected before restoration")
	legacy.progression["air_tank_seconds"]=181;check(not SAVE._valid_save(legacy),"Impossible tank duration is rejected")
	legacy.progression["air_tank_seconds"]=120;legacy["underwater_creatures"]=sea.call("save_state")
	check(SAVE._valid_save(legacy),"Finite air and creature states pass save validation")
	check(SAVE.write("user://diving-roundtrip.save",legacy) and SAVE.read("user://diving-roundtrip.save").underwater_creatures[fish.creature_id].respawn==600,"Encrypted saves round-trip diving data")
	progress.call("restore_state",{"diving_tank":true});check(progress.air_tank_seconds==180,"Previously equipped tanks receive a backwards-compatible full charge")
	progress.diving_tank=false;equip("Diving Tank");player.call("_handle_selected_item_use")
	check(progress.diving_tank and progress.air_tank_seconds==180,"Crafted tank equips and contains three minutes of air")
	player.global_position=Vector3(-100,-30,-150);player.is_swimming=true;progress.oxygen=50;progress._tick=0;progress.call("_process",1)
	current_scene.get_node("Ocean").call("_update_underwater")
	check(current_scene.get_node("Sky3D").environment.background_mode==Environment.BG_COLOR,"Diving horizon uses deep water instead of leaking stars or sky")
	check(progress.air_tank_seconds==179 and progress.oxygen==51,"Submerged tank supplies breath and consumes elapsed air")
	progress.air_tank_seconds=0;progress.oxygen=1;stats.health=100;progress._tick=0;progress.call("_process",1)
	check(progress.oxygen==0 and stats.health<100,"Exhausted tank requires surfacing before breath runs out")
	stats.health=100;await stand(raft);player.active_item="";player.call("_update_hand_item");progress.air_tank_seconds=30
	current_scene.get_node("Ocean").call("_update_underwater")
	check(current_scene.get_node("Sky3D").environment.background_mode==Environment.BG_SKY,"Surfacing restores the day and night sky")
	check(progress.call("can_refill_air") and player.call("interaction_caption")=="REFILL AIR","Empty hands on a dry deck offer an air refill")
	check(progress.call("refill_air") and action.kind=="pump","Air refill starts a manual pump animation")
	progress.call("_process",2);check(progress.air_tank_seconds==30,"Refill requires completing the pumping time")
	player.global_position.x+=2;progress.call("_process",.1);check(progress._air_refill==0 and progress.air_tank_seconds==30,"Walking away cancels a partial refill")
	await stand(raft);progress.call("refill_air");progress.call("_process",6)
	check(progress.air_tank_seconds==180 and progress._air_refill==0,"Finished six-second pump replenishes the equipped tank")
	progress.air_tank_seconds=30;progress.call("refill_air");progress.call("_notification",Node.NOTIFICATION_PAUSED)
	check(progress._air_refill==0 and progress.air_tank_seconds==30,"Pausing cancels unfinished pumping")
	var sharks:=get_nodes_in_group("shark");check(sharks.size()==2,"Only two sharks patrol the remote raft perimeter")
	var remote:=true
	for shark in sharks:remote=remote and shark.global_position.distance_to(raft.global_position)>85;shark.set_physics_process(false)
	check(remote,"Sharks start well away from the raft")
	var shark:=sharks[0] as Node3D;player.is_swimming=true;shark._encounter=9
	var safe:=true
	for level in range(1,6):progress.level=level;safe=safe and not shark.call("can_attack",player)
	check(safe,"Sharks never attack during levels one through five")
	progress.level=6;check(shark.call("can_attack",player),"Late-game sharks can attack only during a rare encounter")
	shark._encounter=0;check(not shark.call("can_attack",player),"Falling in water does not itself trigger an attack")
	var spawner:=shark.get_parent();spawner._cooldown=0
	check(spawner.call("allow_encounter",shark) and not spawner.call("allow_encounter",sharks[1]),"Sharks share a cooldown so encounters cannot stack")
	player.global_position=Vector3(-100,-29,-145);player.cam_pivot.rotation=Vector3.ZERO;player.camera.rotation.x=-.45;player.velocity=Vector3.ZERO
	Input.action_press("move_forward");player.call("_update_swimming",.2,Vector3.FORWARD,0,false);Input.action_release("move_forward")
	check(player.velocity.y<0,"Looking down and swimming forward dives smoothly")
	player.camera.rotation.x=.45;player.velocity=Vector3.ZERO;Input.action_press("move_forward");player.call("_update_swimming",.2,Vector3.FORWARD,0,false);Input.action_release("move_forward")
	check(player.velocity.y>0,"Looking up while swimming forward returns toward the surface")
	check(player.MAX_SWIM_DEPTH>=70,"Deep ruins can be reached below the old depth limit")
	player.active_item="";player.cam_mode=0;player.call("_apply_camera_mode");player.camera.rotation=Vector3.ZERO;action.call("stop")
	sea.call("_process",.1);var first_pose:Vector3=sea._hands.get_child(0).position;sea.call("_process",.4)
	check(sea._hands.visible and first_pose.distance_to(sea._hands.get_child(0).position)>.03,"First-person swimming alternates real hand strokes")
	var swim_clip: String=player.call("_find_survivor_clip",player._survivor_animator,"Swim")
	check(not swim_clip.is_empty() and player._survivor_animator.get_animation(swim_clip).loop_mode==Animation.LOOP_LINEAR,"Third-person swimmer has a dedicated looping recorded stroke")
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause");clock.current_time=12;current_scene.get_node("OceanAtmosphere").call("_process",1)
	clock.call("_update_celestial_coords")
	clock.get_node("Timer").emit_signal("timeout");progress.oxygen=100;progress.air_tank_seconds=180
	if preview:player.camera.top_level=true
	player.global_position=Vector3(-100,-30,-144);player.camera.global_position=player.global_position+Vector3.UP*.9;player.camera.look_at(Vector3(-100,-30,-180));player.camera.get_node("HandPivot").visible=true
	await shot("ruins")
	player.global_position=Vector3(140,-31,105);player.camera.global_position=player.global_position+Vector3.UP*.9;player.camera.look_at(Vector3(140,-33,80));await shot("reef")
	player.cam_mode=1;player.call("_apply_camera_mode");player._body_visual.rotation.x=0.0 if player._survivor_motion!=null else -1.1;player._survivor_animator.play(swim_clip);player._survivor_animator.advance(.4)
	sea.call("_process",.1);progress.call("_process",.01)
	player.camera.global_position=player.global_position+Vector3(2,1.3,3);player.camera.look_at(player.global_position+Vector3(0,.3,0));await shot("swimmer")
	player.cam_mode=0;player.call("_apply_camera_mode");player._body_visual.rotation.x=0;player.is_swimming=false
	player.global_position=spring.global_position+Vector3(0,7,32);player.camera.global_position=player.global_position+Vector3.UP*.9;player.camera.look_at(spring.global_position+Vector3(0,4,0));await shot("spring")
	hud.toggle_crafting();hud._craft_menu.select_item("Diving Tank");await shot("craft");hud._close_crafting()
	if preview:
		player.global_position=raft.global_position+Vector3.UP*1.0;player.is_swimming=false;player.cam_mode=1;player.call("_apply_camera_mode")
		var review_camera:=Camera3D.new();review_camera.fov=65;current_scene.add_child(review_camera);review_camera.current=true
		player.get_node("CanvasLayer").hide()
		raft.set_physics_process(true);await frames(8)
		review_camera.global_position=raft.global_position+Vector3(2.8,.30,3.1);review_camera.look_at(raft.global_position+Vector3(0,-.10,0));await shot("raft-waterline")
		raft.set_physics_process(false);shark.global_position=raft.global_position+Vector3(8,-.7,7)
		review_camera.global_position=shark.global_position+Vector3(2.2,.4,3.2);review_camera.look_at(shark.global_position);await shot("shark")
	player.call("_write_save","main")
	check(SAVE.read(inv.call("_save_path_for","main")).has("underwater_creatures"),"Player save writes underwater world state")
	current_scene.queue_free();await frames(4)
	print("UNDERWATER EXPANSION SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
