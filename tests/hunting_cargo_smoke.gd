extends SceneTree
const SAVE:=preload("res://scripts/save_storage.gd")
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var inv: Node
var stats: Node
var boats: Node
var cargo: Node
var service: Node
var action: Node
func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: hunting cargo timeout");quit(1));call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
	await process_frame
func shot(label: String) -> void:
	if not preview:return
	if is_instance_valid(player.boat_vehicle):player._update_survivor_animation(false)
	await frames(5);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/hunting-cargo-"+label+".png")==OK,"Rendered "+label)
func clear_bag() -> void:
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	inv._recompute();inv.changed.emit()
func pose(progress: float) -> void:
	action.elapsed=action.duration*progress;action._process(0);player._update_hand_sway(0)
func ground(at: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.3,20);collider.shape=box;body.add_child(collider);current_scene.add_child(body);body.position=at;return body
func transitions() -> void:
	boats.ready_to_launch=true;check(boats.launch(),"Fixture launches one usable rowboat")
	var boat: CharacterBody3D=boats.boat;boat.set_physics_process(false);boat.position=Vector3(220,0,-90)
	player.global_position=boat.global_position+Vector3(1.8,1.2,0);player.cam_mode=1;player._apply_camera_mode();var start:=player.global_position;var body_y: float=player.get_node("Body").position.y
	check(boat.board(player) and boat.transition_kind=="board" and player.global_position.distance_to(start)<.05,"Boarding begins at the player's actual position")
	boat.advance_transition(.4);pose(.5)
	check(not is_instance_valid(player._third_person_launcher) or not player._third_person_launcher.visible,"Boarding hides the selected launcher while hands brace")
	check(boat.transition_progress>.4 and boat.transition_progress<.6 and player.global_position.distance_to(start)>.2,"Boarding moves through a visible intermediate step")
	await shot("boarding")
	boat.advance_transition(.5);action.stop()
	check(boat.transition_kind.is_empty() and player.global_position.distance_to(boat.to_global(Vector3(0,1.03,.48)))<.01,"Boarding ends in the stable seat pose")
	check(boat.disembark() and boat.transition_kind=="leave" and player.boat_vehicle==boat,"Leaving retains ownership during its step animation")
	boat.advance_transition(.4);pose(.5);await shot("leaving")
	boat.advance_transition(.5);action.stop()
	check(player.boat_vehicle==null and boat.driver==null and is_equal_approx(player.get_node("Body").position.y,body_y),"Disembarking restores body height and releases boat ownership")
	player.global_position=boat.global_position+Vector3(1.5,1,0);boat.board(player);boat.advance_transition(1);action.stop()
func predators_and_carry() -> void:
	var boat: CharacterBody3D=boats.boat
	var croc: CharacterBody3D=load("res://scripts/survival_animal.gd").new();croc.species="Crocodile";current_scene.add_child(croc);croc.set_physics_process(false);croc.position=boat.position+Vector3(0,-.23,8);croc.home=croc.position+Vector3(0,0,27)
	croc._physics_process(.16)
	check(croc.velocity.dot(player.global_position-croc.global_position)>0 and croc.home_radius()==80,"A crocodile pursues the boat beyond its normal shore leash")
	croc.position=boat.position+Vector3(0,-.23,-.6);stats.reset();croc._physics_process(.16)
	check(stats.health==86 and boat._oar_audio.playing,"A close crocodile attacks a seated driver with a hull splash")
	var before: float=stats.health;croc._physics_process(.16);check(stats.health==before,"Boat attacks retain the crocodile bite cooldown")
	var floor_body:=ground(boat.position+Vector3(0,1,0))
	var boar: CharacterBody3D=load("res://scripts/survival_animal.gd").new();boar.species="Boar";current_scene.add_child(boar);boar.set_physics_process(false);boar.position=boat.position+Vector3(0,1.2,-.6);boar.home=boar.position;await frames();boar._physics_process(.16)
	check(stats.health==before,"A land boar does not attack or chase a seated boat driver")
	boar.queue_free();floor_body.queue_free();await frames()
	var count_before: int=service._drops.size();croc.take_damage(1000,player);await frames()
	var body: StaticBody3D=service._drops.back()
	check(service._drops.size()==count_before+1 and body.is_in_group("animal_carcass") and body.species=="Crocodile" and body.contents[0].count==3,"A killed crocodile leaves exactly one whole body owning its three meat portions")
	croc.take_damage(1000,player);check(service._drops.size()==count_before+1,"Repeated hits cannot duplicate a hunted body")
	croc.queue_free();boat._release_driver();stats.reset();player.is_swimming=false;player.global_position=body.global_position+Vector3(0,1,1)
	inv.add("Spear",1);player.active_item="Spear";player.aim_valid=true;player.aim_collider=body;player.aim_distance=1
	Input.action_press("interact");player._handle_pickup();Input.action_release("interact")
	check(cargo.menu_open and player.interaction_caption()=="CARRY / CUT","Normal interaction opens a hunted body while the spear is still selected")
	cargo.close();var controls:=player.get_node("CanvasLayer/MobileControls");controls.force_show=true;controls._process(0);controls._on_use_down()
	check(not player.get_node("SurvivalEquipment").drawing,"The animal's mobile action does not start another spear throw")
	controls.reset_input()
	clear_bag()
	for index in inv.SLOT_COUNT:inv.slots[index]={"item":"Spear" if index==0 else "Wood","count":1 if index==0 else inv.MAX_STACK}
	inv._recompute();inv.changed.emit();var slots_before: Array=inv.slots.duplicate(true)
	check(cargo.take(body) and inv.slots==slots_before and body.collision_layer==0,"A full backpack can carry one whole animal without changing inventory")
	Input.action_press("rope_throw");player.rope_system._physics_process(.02);player.get_node("SurvivalEquipment").begin_draw();Input.action_release("rope_throw")
	check(not player.rope_system._is_charging and not player.get_node("SurvivalEquipment").drawing,"Carrying owns both hands and blocks rope casting and spear charging")
	cargo._process(0);player.cam_mode=0;player._apply_camera_mode();cargo._process(0);await shot("carrying-first-person")
	check(not player.camera.get_node("HandPivot").visible,"Carrying uses two cargo hands without drawing the selected weapon over the animal")
	check(not cargo.prepare(body) and not body.empty(),"Full-bag preparation keeps the animal and all meat")
	var land:=ground(Vector3(400,1,0));player.global_position=Vector3(400,2.1,0);player.camera.global_position=player.global_position+Vector3.UP*.6;player.camera.look_at(Vector3(400,1.2,-2));player.aim_collider=null;cargo._process(0);await frames()
	check(cargo.place() and not body.floating and body.global_position.y>1,"A carried animal can be placed on real solid land")
	player.global_position=body.global_position+Vector3(0,1,1);check(cargo.take(body),"A placed animal can be picked up again")
	player.global_position=Vector3(450,1,0);player.camera.global_position=player.global_position+Vector3.UP*.5;player.camera.look_at(Vector3(450,0,-2));player.aim_collider=null;cargo._process(0)
	check(cargo.place() and body.floating,"An animal placed in the ocean floats instead of disappearing")
	var sea:=get_first_node_in_group("ocean");body._process(.2);check(absf(body.global_position.y-float(sea.get_height(body.global_position)))<.2,"Floating bodies follow the actual ocean height")
	player.global_position=body.global_position+Vector3(0,1,1);cargo.take(body);player.global_position=boat.global_position+Vector3(1.5,1,0);cargo._process(0)
	check(cargo.load_boat(boat) and body.get_parent()==boat and not body.carried,"The whole animal loads into the boat as visible cargo")
	var local_position:=body.position;boat.position+=Vector3(3,0,0);check(body.position==local_position,"Boat cargo follows travel in boat-local coordinates")
	player.cam_mode=1;player._apply_camera_mode()
	var cargo_camera:=Camera3D.new();current_scene.add_child(cargo_camera);cargo_camera.global_position=boat.global_position+Vector3(3,2.2,3);cargo_camera.look_at(boat.global_position+Vector3.UP*.3);cargo_camera.current=true;await shot("boat-cargo");cargo_camera.queue_free();player.camera.current=true
	var saved: Dictionary=service.save_state();var record: Dictionary=saved.drops.filter(func(entry):return entry.get("species")=="Crocodile")[0]
	check(record.support=="boat" and record.local_p.size()==3 and SAVE._valid_save({"version":1,"slots":[],"survival_services":saved}),"Saved hunted cargo retains species, meat and local boat placement")
	check(not SAVE._valid_save({"version":1,"slots":[],"survival_services":{"drops":[{"p":[0,0,0],"contents":[],"local_p":[{},0,0]}]}}),"Malformed cargo coordinates are rejected before restoration")
	inv.slots[29]={};inv._recompute();inv.changed.emit();player.global_position=body.global_position+Vector3(0,1,1);player.is_swimming=false
	check(cargo.prepare(body),"Freeing one bag slot enables meat preparation")
	cargo._process(1);stats.change_health(-1);cargo._process(.1)
	check(cargo.pending.is_empty() and not body.empty() and inv.total("Raw Meat")==0,"Damage cancels butchering without losing the animal")
	stats.reset();cargo.prepare(body);pose(.4);await shot("preparing-animal");cargo._process(2.5);await frames()
	check(inv.total("Raw Meat")==3 and not is_instance_valid(body),"Completed preparation transfers all meat exactly once and removes the body")
	land.queue_free()
func meals_and_persistence() -> void:
	clear_bag();inv.add("Raw Meat",3);inv.add("Metal",3)
	check(inv.craft_item("Cooking Foil") and inv.total("Cooking Foil")==1,"CRAFT makes one cooking foil from one metal")
	player.global_position=raft.to_global(Vector3(0,1.1,1));player.is_swimming=false
	var fire: Node3D=load("res://scenes/cooking_setup.tscn").instantiate();current_scene.add_child(fire);fire.global_position=player.global_position+Vector3(0,-.7,-1.5);fire.set_process(false);fire.burning=true;fire.fuel=100
	service.open_cooking(fire);check(service.start_cooking("Cooked Meat"),"Prepared animal meat uses the real cooking-fire recipe")
	var job:=fire.get_node("StationJob");job.set_process(false);job.advance(20);action.stop();await frames()
	check(inv.total("Cooked Meat")==1,"The cooked carcass portion becomes safe cooked meat")
	service.open_cooking(fire)
	for unused in 120:
		await frames(1)
		if service.ui.cooking_prepared:break
	var row: Dictionary=service.ui._rows.filter(func(entry):return entry.dish=="Cooked Meat")[0]
	var wrapping_rows: Array[Dictionary]=[row]
	service.ui._refresh_cooking_rows(wrapping_rows);check(not row.wrap.disabled,"Camp Kitchen enables foil wrapping only when the meal and foil are owned")
	row.wrap.pressed.emit();check(cargo.busy() and inv.total("Cooking Foil")==1,"Wrapping starts with hands and keeps materials until completion")
	player.cam_mode=0;player._apply_camera_mode();pose(.4);await shot("wrapping-meal");cargo._process(1.7)
	check(inv.total("Wrapped Cooked Meat")==1 and inv.total("Cooking Foil")==0 and inv.total("Cooked Meat")==0,"Wrapping atomically makes one silver parcel using one meal and one foil")
	cargo._process(2);check(inv.total("Wrapped Cooked Meat")==1,"A finished wrap cannot duplicate food")
	var box: StaticBody3D=load("res://scenes/storage_box.tscn").instantiate();current_scene.add_child(box);box.global_position=player.global_position+Vector3(1,0,0)
	service.open_storage(box);var slot: int=inv.slots.find({"item":"Wrapped Cooked Meat","count":1})
	check(service.transfer(false,slot,true,0) and box.contents[0].item=="Wrapped Cooked Meat","Wrapped food can be stored in an ordinary storage box")
	var state: Dictionary=box.save_survival_state();box.contents[0]={};box.restore_survival_state(state)
	check(box.contents[0].count==1 and service.transfer(true,0,false,slot),"Storage restoration and retrieval preserve the wrapped meal")
	service.close_menu();service.equip_owned("Wrapped Cooked Meat");action.stop();stats.load_state({"health":60,"hunger":10,"thirst":10})
	check(service.use_item("Wrapped Cooked Meat") and stats.health==69 and stats.hunger==44,"Eating a stored wrapped meal retains the cooked-food nutrition")
	pose(.145);check(action._sound.stream.resource_path.ends_with("unpack.wav"),"Eating a foil parcel starts with an unwrapping sound")
	pose(.37);check(not action._food_first.get_node("PeelingFoil").visible and action._sound.stream.resource_path.contains("bite"),"Foil peels away before eating and the bite sound")
	await shot("eating-wrapped-meal");action.stop()
	var body: StaticBody3D=service.drop_items([{"item":"Raw Meat","count":2}],player.global_position+Vector3(1,0,0),"Boar")
	cargo.take(body);cargo.on_death();check(body.get_parent()==raft and not body.carried,"Death brings a carried hunted animal home intact")
	var snapshot: Dictionary=service.save_state();body.queue_free();await frames();inv.loaded_meta["survival_services"]=snapshot;service._restore_drops();await frames(8)
	var restored:=get_nodes_in_group("animal_carcass").filter(func(node):return node.species=="Boar")
	check(restored.size()==1 and restored[0].get_parent()==raft and restored[0].contents[0].count==2,"Continue restores the hunted body and its raft support without another reward")
	cargo.take(restored[0]);var carried_snapshot: Dictionary=service.save_state();cargo._clear_hold();restored[0].queue_free();await frames()
	inv.loaded_meta["survival_services"]=carried_snapshot;service._restore_drops();await frames(8)
	check(is_instance_valid(cargo.held) and cargo.held.contents[0].count==2,"Continue restores a carried animal into the hands without duplicating meat")
	cargo.on_death()
	check(player._write_save("quick") and not SAVE.read(inv.QUICK_SAVE_PATH).is_empty(),"Hunting cargo and wrapped food use the authenticated save format")
	fire.queue_free();box.queue_free()
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720);inv=root.get_node("Inventory");stats=root.get_node("Stats");inv.new_game_reset(true);stats.enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed;player=get_first_node_in_group("player");raft=get_first_node_in_group("raft")
	for unused in 3000:
		await frames(1)
		if player.restoration_complete and player.get_node("SurvivalAction").hands_prepared and player.get_node("IslandWildlife").prepared:break
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	for animal in get_nodes_in_group("huntable_animal"):animal.set_physics_process(false)
	for child in ["RopeSystem","SurvivalProgression","SurvivalTools","SurvivalEquipment"]:player.get_node(child).set_process(false);player.get_node(child).set_physics_process(false)
	player.get_node("RainSystem").stop_rain();boats=player.get_node("BoatBuilding");boats.set_process(false);service=player.get_node("SurvivalServices");service.set_process(false);action=player.get_node("SurvivalAction");action.set_process(false);cargo=player.get_node("HuntingCargo");cargo.set_process(false)
	await transitions();await predators_and_carry();await meals_and_persistence()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("HUNTING CARGO SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
