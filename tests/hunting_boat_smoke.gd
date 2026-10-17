extends SceneTree
const SAVE:=preload("res://scripts/save_storage.gd")
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var inv: Node
var equipment: Node
var action: Node
var service: Node
var boats: Node
var camera: Camera3D
func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: hunting and boat timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
	await process_frame
func shot(label: String) -> void:
	if not preview:return
	await frames(5);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/hunting-"+label+".png")==OK,"Rendered "+label)
func equip(item: String) -> void:
	if not inv.has(item,1):inv.add(item,1)
	service.equip_owned(item);action.stop()
func aim(at: Vector3) -> void:
	player.camera.current=true;player.camera.global_position=player.global_position+Vector3.UP*.9;player.camera.look_at(at)
	player.call("_update_aim")
func dive_probe() -> void:
	var sea:=current_scene.get_node("UnderwaterWorld")
	var creatures:=get_nodes_in_group("dive_creature")
	check(creatures.size()==50 and creatures.any(func(c):return c.species=="Grouper") and creatures.any(func(c):return c.species=="Octopus"),"Fifty bounded marine animals include groupers and octopuses")
	check(creatures.filter(func(c):return c.creature_id.begins_with("NearRaft:")).size()==8,"Eight huntable animals are present in nearby starter waters")
	player.global_position=Vector3(10,-12,-24);player.is_swimming=true
	sea.stream.request_position(Vector2(10,-24))
	for unused in 1400:
		await frames(1)
		if sea.stream.ready_at(Vector2(10,-24)):break
	var tile: Node3D=sea.stream.chunks[Vector2i(0,-1)]
	for kind in ["Grass","Kelp","RibbonWeed","RedAlgae","Anemone"]:
		var batch:=tile.get_node(kind+"Batch") as MultiMeshInstance3D
		check(batch!=null and batch.multimesh.visible_instance_count>0,"Nearby seabed includes visible "+kind)
	check(tile.get_node("GrassBatch").multimesh.instance_count>=80,"Seagrass density increases without per-plant nodes")
	camera.global_position=Vector3(12,-11.4,-22);camera.look_at(Vector3(19,-14,-29));camera.current=true
	player.get_node("CanvasLayer").hide();await shot("underwater-garden");player.get_node("CanvasLayer").show()
	var fish:=creatures.filter(func(c):return c.species=="Grouper")[0] as CharacterBody3D
	fish.global_position=Vector3(0,-5,-25);fish.health=40;fish.velocity=Vector3.ZERO
	player.global_position=Vector3(0,-5.9,-12);player.cam_mode=0;player.call("_apply_camera_mode")
	equip("Spear");inv.add("Spear",2);equipment.cooldown=0
	aim(fish.global_position);equipment.begin_draw();equipment.draw_time=1.1;action.call("_process",0);player.call("_update_hand_sway",0)
	check(equipment.drawing and player.can_interact_now(),"A spear can be aimed and charged at a target beyond melee reach")
	await shot("spear-aim")
	var before: int=inv.total("Spear");equipment.call("_fire")
	check(inv.total("Spear")==before-1 and get_nodes_in_group("recoverable_spear").size()==1,"Throwing spends exactly one spear and creates one recoverable projectile")
	var spear:=get_nodes_in_group("recoverable_spear")[0] as Node3D
	for unused in 160:
		await frames(1)
		if not spear.flying:break
	check(fish.health==0 and fish.respawn>0 and not spear.flying,"An actual thrown underwater spear hits and kills the aimed grouper")
	check(spear.is_in_group("debris") and spear.collision_layer==2,"An impacted spear becomes a normal collectible")
	var bags: Array=service._drops
	check(not bags.is_empty() and bags[-1].contents.any(func(entry):return entry.get("item")=="Fish" and entry.get("count")==2),"A projectile kill leaves two fish in persistent floating loot")
	var state: Array=equipment.save_spears()
	check(state.size()==1 and SAVE._valid_save({"version":1,"slots":[],"thrown_spears":state}),"Recoverable spear position is accepted by save validation")
	player.global_position=spear.global_position+Vector3.UP*.8;player.active_item="";player.call("_collect_debris",spear);await frames()
	check(inv.total("Spear")==before and equipment.save_spears().is_empty(),"Retrieving the thrown spear restores exactly one and clears its saved pickup")
	var bag:=bags[-1] as Node3D;player.global_position=bag.global_position+Vector3(0,1,1)
	service.open_storage(bag);var fish_before: int=inv.total("Fish")
	check(service.transfer(true,0,false,29) and inv.total("Fish")==fish_before+2,"Hunted fish can be collected from their floating loot for transport home")
	service.close_menu();action.stop()
	var surface_fish:=creatures.filter(func(c):return c.species=="Grouper")[1] as CharacterBody3D
	surface_fish.global_position=Vector3(0,-4,-25);surface_fish.velocity=Vector3.ZERO;surface_fish.health=40
	player.global_position=Vector3(0,.8,-12);player.is_swimming=false;equip("Spear");equipment.cooldown=0
	aim(surface_fish.global_position);equipment.begin_draw();equipment.draw_time=1.1;equipment.call("_fire")
	for unused in 160:
		await frames(1)
		if surface_fish.respawn>0:break
	check(surface_fish.respawn>0,"An aimed spear thrown from above water can hit a creature below the surface")
	# Owned touch cancellation must preserve a charged spear just like a bow.
	equip("Spear");equipment.cooldown=0
	var mobile:=player.get_node("CanvasLayer/MobileControls");mobile.force_show=true;mobile.call("_process",0)
	var touch:=InputEventScreenTouch.new();touch.index=17;touch.position=mobile._btn_use.get_global_rect().get_center();touch.pressed=true;mobile.call("_input",touch)
	check(equipment.drawing,"The right-thumb spear button starts charging on touch-down")
	var drag:=InputEventScreenDrag.new();drag.index=17;drag.position=touch.position+Vector2(-130,-35);drag.relative=Vector2(-18,-5);mobile.call("_input",drag)
	check(mobile._button_touches.has(17) and Input.is_action_pressed("interact"),"A spear throw finger keeps ownership while dragging outside the button to aim")
	before=inv.total("Spear");touch.pressed=false;touch.canceled=true;mobile.call("_input",touch)
	check(not equipment.drawing and not Input.is_action_pressed("interact") and inv.total("Spear")==before,"Cancelling a charged spear neither throws nor spends it")
	mobile.reset_input()
func predator_probe() -> void:
	var rain:=player.get_node("RainSystem");rain.start_rain(60)
	var wildlife:=player.get_node("IslandWildlife")
	check(wildlife.prepared and wildlife.animals.any(func(a):return a.species=="Crocodile"),"Island population creates crocodiles with saved stable identities")
	check(wildlife.animals.filter(func(a):return a.species=="Boar").size()>=8,"Island trips encounter multiple wild boars, including added island habitats")
	var floor_body:=StaticBody3D.new();floor_body.position=Vector3(240,1,-80);var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,.3,30);shape.shape=box;floor_body.add_child(shape);current_scene.add_child(floor_body)
	var boar: CharacterBody3D=load("res://scripts/survival_animal.gd").new();boar.species="Boar";current_scene.add_child(boar);boar.position=Vector3(240,1.2,-80);boar.home=boar.position;boar.set_physics_process(false)
	player.global_position=boar.global_position+Vector3(0,.9,5);player.is_swimming=false;root.get_node("Stats").health=100
	await frames();boar.call("_physics_process",.16)
	check(boar.alarm==0 and boar.velocity.dot(player.global_position-boar.global_position)>0,"An unwounded boar actively charges a nearby island visitor even in rain")
	player.global_position=boar.global_position+Vector3(0,.9,.5);boar.call("_physics_process",.16)
	check(root.get_node("Stats").health==90,"A close boar attack damages health once")
	boar.call("_physics_process",.16);check(root.get_node("Stats").health==90,"Boar bite cooldown prevents damage every frame")
	check(boar._animation!=null and boar._animation.has_animation("Walk") and boar._animation.get_animation("Walk").loop_mode==Animation.LOOP_LINEAR,"The full boar has a looping skeletal walk")
	check(boar._model.find_child("PhotographedBoarHead",true,false)!=null and boar._model.find_child("SmoothFullBoarBody",true,false)!=null,"The detailed scanned boar head is attached to a complete animated body")
	var island_boar:=wildlife.animals.filter(func(a):return a.species=="Boar")[0] as Node3D
	camera.global_position=island_boar.global_position+Vector3(2.5,1.5,2.5);camera.look_at(island_boar.global_position+Vector3.UP*.6);camera.current=true
	player.get_node("CanvasLayer").hide();await shot("boar");player.get_node("CanvasLayer").show()
	var croc: CharacterBody3D=load("res://scripts/survival_animal.gd").new();croc.species="Crocodile";current_scene.add_child(croc);croc.position=Vector3(244,1.2,-80);croc.home=croc.position;croc.set_physics_process(false)
	player.global_position=croc.global_position+Vector3(0,.8,-1);croc.call("_physics_process",.16)
	check(root.get_node("Stats").health==76 and croc.health==90,"A crocodile retains its distinct health and close bite in rain")
	check(croc._animation!=null and croc._animation.has_animation("Attack") and croc._animation.get_animation("Walk").loop_mode==Animation.LOOP_LINEAR,"The crocodile has actual skeletal bite and looping locomotion clips")
	var coastal_croc:=wildlife.animals.filter(func(a):return a.species=="Crocodile")[0] as Node3D
	for view in 16:
		var from:=coastal_croc.global_position+Vector3(cos(view*TAU/16)*3.2,1.8,sin(view*TAU/16)*3.2)
		var query:=PhysicsRayQueryParameters3D.create(from,coastal_croc.global_position+Vector3.UP*.3,1)
		if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():camera.global_position=from;break
	camera.look_at(coastal_croc.global_position+Vector3.UP*.3);camera.current=true
	player.call("_set_viewmodel_visible",false);player.get_node("CanvasLayer").hide();await shot("crocodile");player.get_node("CanvasLayer").show();player.call("_apply_camera_mode")
	player.cam_mode=0;player.call("_apply_camera_mode");player.global_position=croc.global_position+Vector3(0,.9,8);croc.velocity=Vector3.ZERO
	equip("Spear");equipment.cooldown=0;aim(croc.global_position+Vector3.UP*.25);equipment.begin_draw();equipment.draw_time=1.1;equipment.call("_fire")
	for unused in 160:
		await frames(1)
		if croc.health<90:break
	check(croc.health==25 and croc.alarm>0,"A real spear thrown through the air wounds a crocodile and triggers retaliation")
	var drops: int=service._drops.size();equipment.cooldown=0;aim(croc.global_position+Vector3.UP*.25);equipment.begin_draw();equipment.draw_time=1.1;equipment.call("_fire")
	for unused in 160:
		await frames(1)
		if croc.respawn>0:break
	check(croc.respawn>0 and service._drops.size()==drops+1 and service._drops[-1].contents[0].count==3,"Hunting a crocodile yields three raw meat in recoverable loot exactly once")
	croc.take_projectile_damage(65,player);check(service._drops.size()==drops+1,"A dead crocodile cannot produce duplicate meat")
	var meat_bag: Node3D=service._drops[-1];player.global_position=meat_bag.global_position+Vector3(0,1,1);service.open_storage(meat_bag)
	var empty_slot: int=-1
	for index in range(inv.BAG_START,inv.SLOT_COUNT):
		if inv.slot_empty(index):empty_slot=index;break
	check(empty_slot>=0 and service.transfer(true,0,false,empty_slot) and inv.has("Raw Meat",3),"Crocodile meat can be carried back to the raft for cooking")
	service.close_menu()
	boar.queue_free();croc.queue_free();floor_body.queue_free();action.stop()
	rain.stop_rain()
func food_probe() -> void:
	player.global_position=raft.to_global(Vector3(0,1.06,0));player.is_swimming=false;root.get_node("Stats").health=100
	equip("Raw Meat");check(service.use_item("Raw Meat") and root.get_node("Stats").health==90,"Eating uncooked hunted meat drains ten health")
	action.stop()
	var fire: Node3D=load("res://scenes/cooking_setup.tscn").instantiate();current_scene.add_child(fire);fire.position=player.global_position+Vector3(0,-.7,-1.5);fire.set_process(false);fire.burning=true;fire.fuel=50
	service.open_cooking(fire)
	check(service.start_cooking("Cooked Meat"),"Hunted meat starts the ordinary fire cooking recipe")
	var job:=fire.get_node("StationJob");job.set_process(false);job.advance(20);action.stop()
	check(inv.has("Cooked Meat",1) and job.job.is_empty(),"The completed cooking job produces one safe cooked meat")
	equip("Cooked Meat");root.get_node("Stats").health=70
	check(service.use_item("Cooked Meat") and root.get_node("Stats").health==79,"Eating cooked meat restores health instead of draining it")
	action.stop();fire.queue_free();await frames()
func boat_probe() -> void:
	player.global_position=raft.to_global(Vector3(0,1.06,1.2));player.is_swimming=false;player.active_item="";action.stop()
	var workshop: Node3D=load("res://scenes/boat_workshop.tscn").instantiate();raft.get_node("BuiltPieces").add_child(workshop);workshop.position=Vector3(0,.6,-.5)
	inv.add("Screw",8)
	workshop.interact_survival(player)
	check(boats.menu_open and not boats._build_button.disabled and boats._launch_button.disabled,"Boat Workshop offers an enabled build action and a separate launch action")
	await shot("boat-workshop-menu")
	var wood: int=inv.total("Wood");var rope: int=inv.total("Rope");var screw: int=inv.total("Screw")
	check(boats.start_build(workshop),"Workshop assembly starts with the shown materials")
	boats.call("_process",2)
	check(inv.total("Wood")==wood and is_instance_valid(boats._assembly),"Boat assembly is visible and does not charge before completion")
	camera.global_position=workshop.global_position+Vector3(3.2,2,3.5);camera.look_at(workshop.global_position+Vector3.UP*.7);camera.current=true
	await shot("boat-assembly")
	boats.cancel_build();check(inv.total("Wood")==wood and not boats.ready_to_launch,"Interrupted assembly preserves all materials")
	check(boats.start_build(workshop),"Cancelled assembly can restart")
	boats.call("_process",5.6)
	check(boats.ready_to_launch and inv.total("Wood")==wood-12 and inv.total("Rope")==rope-6 and inv.total("Screw")==screw-4,"Finished rowboat spends exactly 12 Wood, 6 Rope and 4 Screw once")
	check(not boats.start_build(workshop),"A completed rowboat blocks a duplicate build charge")
	check(boats.launch() and is_instance_valid(boats.boat),"Launch places the usable boat in clear water beside the raft")
	var boat:=boats.boat as CharacterBody3D;boat.set_physics_process(false)
	check(boat._visual.has_node("Hull") and boat._visual.has_node("Interior") and boat._visual.has_node("Seats") and boat._visual.has_node("Oars/OarLeft") and boat._visual.has_node("Oars/OarRight"),"The detailed boat preserves four construction stages and two rowing pivots")
	var saved_raft:=raft.global_transform
	player.global_position=boat.global_position+Vector3(1.5,1,0);player.cam_mode=1;player.call("_apply_camera_mode")
	check(boat.board(player) and player.boat_vehicle==boat and not player.is_swimming,"The launched rowboat can be boarded from beside its hull")
	boat.advance_transition(1);action.stop()
	check(player.interaction_caption()=="LEAVE BOAT" and player.get_node("CanvasLayer/MobileControls")._btn_use!=null,"Driving provides a leave action while keeping the movement joystick")
	var origin:=boat.global_position
	player.rotation.y=0
	var mobile:=player.get_node("CanvasLayer/MobileControls");mobile.force_show=true;mobile.call("_process",0)
	check(mobile._btn_use.visible and mobile._use_caption=="LEAVE BOAT" and not mobile._btn_jump.visible and not mobile._btn_aim.visible,"Boat touch controls show LEAVE and keep weapon/jump actions out of steering")
	var move_touch:=InputEventScreenTouch.new();move_touch.index=20;move_touch.position=mobile._dock+Vector2(0,-mobile.call("_joy_radius"));move_touch.pressed=true
	mobile.call("_input",move_touch);mobile.call("_process",0)
	for unused in 25:boat.call("_physics_process",.1);await frames(1)
	move_touch.pressed=false;mobile.call("_input",move_touch);mobile.call("_process",0)
	check(not Input.is_action_pressed("move_forward") and mobile._move_id==-1,"Releasing the rowing joystick clears its owned movement")
	check(boat.global_position.distance_to(origin)>5 and player.global_position.distance_to(boat.to_global(Vector3(0,1.03,.48)))<.01,"Joystick rowing moves the boat and carries its driver")
	check(raft.global_transform.is_equal_approx(saved_raft),"Driving the boat leaves the raft and buildings in place")
	camera.global_position=boat.global_position+Vector3(2.8,1.8,3.2);camera.look_at(boat.global_position+Vector3.UP*.45);camera.current=true
	player.get_node("CanvasLayer").hide();await shot("rowing-third-person");player.get_node("CanvasLayer").show()
	var destination:=Node3D.new();destination.name="TestIsland";current_scene.add_child(destination);destination.global_position=boat.global_position+Vector3(0,0,-65);destination.set_meta("arrival_radius",18)
	check(player.request_course_to(destination) and boat.has_active_course(),"MAP courses target the boarded boat")
	for unused in 180:
		boat.call("_physics_process",.1);await frames(1)
		if not boat.has_active_course():break
	check(not boat.has_active_course() and Vector2(boat.global_position.x-destination.global_position.x,boat.global_position.z-destination.global_position.z).length()<=18.5,"Auto rowing reaches the destination and stops before shore")
	var barrier:=StaticBody3D.new();var collision:=CollisionShape3D.new();var wall:=BoxShape3D.new();wall.size=Vector3(8,3,.6);collision.shape=wall;barrier.add_child(collision)
	barrier.position=boat.global_position+Vector3(0,.4,-4);current_scene.add_child(barrier);await frames()
	boat.set_course(boat.global_position+Vector3(0,0,-60),18)
	for unused in 60:
		boat.call("_physics_process",.1);await frames(1)
		if not boat.has_active_course():break
	check(not boat.has_active_course() and boat.global_position.z>barrier.global_position.z+1.5,"A real obstacle stops the hull and cancels automatic rowing")
	barrier.queue_free();await frames()
	var state: Dictionary=boats.save_state()
	check(state.get("aboard",false) and SAVE._valid_save({"version":1,"slots":[],"rowboat":state}),"Boat position, heading and aboard state are save-compatible")
	check(SAVE.write("user://boat-trip.save",{"version":1,"slots":[],"rowboat":state}) and SAVE.read("user://boat-trip.save").rowboat.aboard,"An encrypted save round-trips an active boat trip")
	var leaving: bool=boat.disembark();boat.advance_transition(1)
	check(leaving and player.boat_vehicle==null,"A clear side exit returns the player to normal swimming or walking after its animation")
	check(not boats.save_state().aboard and boat.driver==null,"Leaving the boat clears passenger state without deleting it")
	var on_foot: Dictionary=boats.save_state();boat.queue_free();boats.boat=null;await frames()
	inv.loaded_meta={"rowboat":state};boats._restore_done=false;boats.restore();await frames()
	check(is_instance_valid(player.boat_vehicle) and boats.boat.global_position.distance_to(Vector3(state.p[0],state.p[1],state.p[2]))<.1,"Continue restores the boat and puts a saved aboard player back in it")
	boats.boat.disembark();boats.boat.advance_transition(1);boats.boat.queue_free();boats.boat=null;await frames()
	player.global_position=raft.global_position+Vector3.UP*2
	inv.loaded_meta={"rowboat":on_foot};boats._restore_done=false;boats.restore();await frames()
	check(player.boat_vehicle==null and player.global_position.distance_to(Vector3(on_foot.traveller_p[0],on_foot.traveller_p[1],on_foot.traveller_p[2]))<.1,"Continue also restores a traveller who left the boat to explore an island")
	boats.boat.queue_free();boats.boat=null;await frames();inv.loaded_meta={};player.raft_boat_built=true;boats._restore_done=false;boats.restore();await frames()
	check(is_instance_valid(boats.boat) and get_nodes_in_group("player_boat").size()==1,"An older raft_boat_built save gains one usable rowboat without a duplicate charge")
	check(SAVE._valid_save({"version":1,"slots":[]}),"Older saves without boats or thrown spears still load")
	check(not SAVE._valid_save({"version":1,"slots":[],"rowboat":{"p":[1,"bad",3]}}),"Malformed boat coordinates are rejected")
	destination.queue_free()
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft")
	for unused in 3000:
		await frames(1)
		if current_scene.get_node("UnderwaterWorld").prepared and player.get_node("SurvivalAction").hands_prepared and player.restoration_complete and player.get_node("IslandWildlife").prepared:break
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	for creature in get_nodes_in_group("huntable_animal"):creature.set_physics_process(false)
	for child in ["RopeSystem","SurvivalProgression","SurvivalTools","SurvivalEquipment"]:player.get_node(child).set_process(false);player.get_node(child).set_physics_process(false)
	player.get_node("RainSystem").stop_rain()
	action=player.get_node("SurvivalAction");action.set_process(false)
	equipment=player.get_node("SurvivalEquipment");service=player.get_node("SurvivalServices");service.set_process(false)
	boats=player.get_node("BoatBuilding");boats.set_process(false)
	camera=Camera3D.new();current_scene.add_child(camera)
	await dive_probe();await predator_probe();await food_probe();await boat_probe()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("HUNTING BOAT SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
