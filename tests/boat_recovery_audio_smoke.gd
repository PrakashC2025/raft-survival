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
var service: Node
var action: Node
var mobile: Control

func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: boat recovery timeout");quit(1))
	call_deferred("run")
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
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/boat-update-"+label+".png")==OK,"Rendered "+label)
func equip(item: String) -> void:
	if not inv.has(item,1):inv.add(item,2)
	service.equip_owned(item);action.stop()
func edge_interact() -> void:
	Input.action_press("interact");player.call("_poll_gameplay_actions");Input.action_release("interact")

func workshop_probe() -> void:
	player.global_position=raft.to_global(Vector3(0,1.06,1.2));player.is_swimming=false;action.stop()
	var workshop: Node3D=load("res://scenes/boat_workshop.tscn").instantiate();raft.get_node("BuiltPieces").add_child(workshop);workshop.position=Vector3(0,.6,-.5)
	inv.remove("Screw",inv.total("Screw"));boats.open(workshop)
	var ui: CanvasLayer=boats._layer
	check(boats.menu_open and boats._build_button.disabled and ui.material_rows.Screw.text.ends_with("/ 4"),"Workshop shows the missing screw count and blocks an unaffordable boat")
	await shot("materials-missing")
	inv.add("Screw",4);boats._refresh()
	check(not boats._build_button.disabled and ui.steps.size()==3,"Available supplies enable assembly with three clear steps")
	for viewport_size in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(960,540),Vector2i(1280,960)]:
		root.size=viewport_size;await frames(3);ui.fit();await frames(2)
		var bounds: Rect2=ui.panel.get_global_rect()
		var visible_size:=root.get_visible_rect().size
		check(bounds.position.x>=0 and bounds.position.y>=0 and bounds.end.x<=visible_size.x+1 and bounds.end.y<=visible_size.y+1,"Workshop stays inside stretched viewport "+str(viewport_size))
		check(ui.close_button.get_global_rect().end.y<=visible_size.y and ui.build_button.get_global_rect().end.y<=visible_size.y,"Workshop action buttons remain visible "+str(viewport_size))
	root.size=Vector2i(1280,720);await frames();ui.fit();await frames()
	await shot("workshop")
	var before: Array=inv.slots.duplicate(true)
	check(boats.start_build(workshop) and boats.menu_open,"Assembly keeps the workshop open with progress and cancel")
	action._process(.45)
	check(action.kind=="build" and action._foley_count>0 and action._sound.playing,"Boat construction retains its actual action and plays the first hammer contact")
	boats._process(2.2);boats._refresh()
	check(ui.progress.value>.35 and ui.stage.text.contains("40%") and ui.close_button.text=="CANCEL BUILD","Visible assembly progress reaches the correct stage")
	await shot("assembly")
	boats.close()
	check(not boats.building and not boats.menu_open and inv.slots==before,"Closing assembly cancels cleanly with every material kept")
	boats.open(workshop);boats.start_build(workshop);stats.change_health(-1);boats._process(.01)
	check(not boats.building and inv.slots==before,"Taking damage during assembly cancels without charging")
	action.stop();stats.reset();boats.start_build(workshop);boats._process(5.6);boats._refresh()
	check(boats.ready_to_launch and ui.launch_button.visible and not ui.launch_button.disabled and not ui.build_button.visible,"Completed boat replaces assembly with the launch action")
	check(inv.total("Screw")==0 and not boats.start_build(workshop),"Completion charges screws once and rejects a duplicate boat")
	await shot("ready-to-launch")
	check(boats.launch(),"The completed boat launches into clear water")
	check(not boats.menu_open and not ui.visible,"Launching releases the workshop modal")
	await frames();ui._process(.1)
	check(ui.preview.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Closing the workshop stops the preview renderer")
	boats.boat.set_physics_process(false)

func food_and_audio_probe() -> void:
	var boat: CharacterBody3D=boats.boat
	boat.global_position=raft.global_position+Vector3(30,0,-30)
	player.global_position=boat.global_position+Vector3(1.5,1,0);player.cam_mode=0;player._apply_camera_mode()
	check(boat.board(player),"Boarding a boat succeeds before the food regression")
	boat.advance_transition(1);action.stop()
	equip("Cooked Fish");stats.hunger=12;var before: int=inv.total("Cooked Fish")
	await frames();edge_interact();action._process(.64)
	check(player.boat_vehicle==boat and stats.hunger==40 and inv.total("Cooked Fish")==before-1,"The normal interaction eats one cooked meal while staying seated")
	check(action.kind=="eat" and player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot").visible and not player.movement_owns_hands(),"First-person eating shows hands and releases the oar pose")
	check(action._sound.playing and action._foley_count>0,"Boat eating emits actual bite foley")
	mobile.force_show=true;mobile._process(0)
	check(mobile._btn_use.visible and mobile._use_caption=="EAT" and mobile._btn_leave.visible,"Mobile boat controls offer EAT and a separate LEAVE BOAT action")
	check(not mobile._btn_use.get_global_rect().intersects(mobile._btn_leave.get_global_rect()),"Food and boat-exit touch targets do not overlap")
	player.set_physics_process(true);await shot("eat-in-boat-first-person");player.set_physics_process(false)
	action.stop();player.cam_mode=1;player._apply_camera_mode();equip("Clean Water Can");stats.thirst=1
	await frames();edge_interact();action._process(.8)
	check(player.boat_vehicle==boat and stats.thirst==100 and inv.has("Can",1),"Drinking aboard returns the empty can and restores thirst")
	player.set_physics_process(true);await shot("drink-in-boat-third-person");player.set_physics_process(false)
	action.stop();equip("Bandage");stats.health=40;await frames();edge_interact()
	check(stats.health==65 and player.boat_vehicle==boat,"A bandage heals without leaving the boat")
	action.stop();mobile.reset_input();player.active_item="";player.rope_gun_selected=false
	Input.action_press("move_forward");boat._next_stroke=0;boat._creak_clock=0
	for unused in 8:boat._physics_process(.1)
	check(boat._oar_audio.playing and boat._hull_audio.playing,"Moving the boat plays water strokes and hull creaks")
	Input.action_release("move_forward");boat._release_driver()
	check(not boat._oar_audio.playing and not boat._hull_audio.playing,"Releasing the driver stops active rowing audio")
	player.is_swimming=true;player.velocity=Vector3(2,-1,0);player._swim_audio_clock=0;player._update_movement_audio(.1,false,false)
	check(player._motion_audio.playing,"Entering water plays a splash")
	player._update_movement_audio(.3,true,false)
	check(player._motion_audio.stream.resource_path.ends_with("swim_stroke.wav") and player._motion_audio.volume_db>=-8,"Swimming emits an audible stroke at movement cadence")
	var ambience:=current_scene.get_node("OceanAmbience");var camera: Camera3D=player.camera
	camera.global_position=Vector3(30,-3,-30);camera.current=true
	for unused in 4:ambience._process(.5)
	check(ambience._underwater.playing and ambience._underwater.volume_db>-16 and ambience._low_pass.cutoff_hz<1600,"A submerged listener hears looping bubbles with muffled surface ambience")
	camera.global_position.y=5
	for unused in 5:ambience._process(.5)
	check(ambience._underwater.volume_db<-55 and ambience._low_pass.cutoff_hz>17000,"Surfacing fades bubbles out and restores clear ambience")
	player.is_swimming=false;player.velocity=Vector3.ZERO
	# Exercise the real boar/crocodile AI contact path on isolated solid ground.
	var floor_body:=StaticBody3D.new();floor_body.position=Vector3(260,1,-80)
	var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.3,20);floor_shape.shape=box;floor_body.add_child(floor_shape);current_scene.add_child(floor_body)
	for species in ["Boar","Crocodile"]:
		var animal: CharacterBody3D=load("res://scripts/survival_animal.gd").new();animal.species=species;current_scene.add_child(animal);animal.position=Vector3(260,1.2,-80);animal.home=animal.position;animal.set_physics_process(false)
		stats.reset();player.global_position=animal.global_position+Vector3(0,.8,-.5);await frames();animal._physics_process(.16)
		check(stats.health<100 and animal._combat_audio.playing and player._damage_audio.playing,species+" attacks play a bite contact and player impact")
		var health_before: float=stats.health;animal._physics_process(.16)
		check(stats.health==health_before,species+" sound wiring preserves the bite cooldown")
		animal.take_damage(1,player)
		check(animal._combat_audio.stream.resource_path.ends_with("body_impact.wav"),"Hitting a "+species+" plays its body contact")
		animal.queue_free();await frames()
	floor_body.queue_free();stats.reset()

func recovery_probe() -> void:
	var boat: CharacterBody3D=boats.boat
	boat.global_position=raft.global_position+Vector3(200,0,-190);player.global_position=boat.global_position+Vector3(1.5,1,0);boat.board(player);boat.advance_transition(1)
	for index in inv.SLOT_COUNT:inv.slots[index]={"item":"Wood" if index%2==0 else "Rope","count":inv.MAX_STACK-index}
	inv._recompute();inv.changed.emit();var before: Array=inv.slots.duplicate(true)
	var drop_count: int=service._drops.size();stats.change_health(-1000)
	check(inv.slots==before and service._drops.size()==drop_count,"Death keeps every slot of a full inventory without duplicating a loot bag")
	check(player.boat_vehicle==null and boat.driver==null and player.global_position.distance_to(raft.global_position)<2,"Death releases the driver and returns the player to the raft")
	var distance_value:=Vector2(boat.global_position.x-raft.global_position.x,boat.global_position.z-raft.global_position.z).length()
	check(distance_value>float(raft._deck_radius)+2 and distance_value<float(raft._deck_radius)+15,"The boat returns beside the raft outside the entire deck footprint")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=(boat.get_child(0) as CollisionShape3D).shape;query.transform=boat.global_transform;query.collision_mask=1;query.exclude=[boat.get_rid(),player.get_rid()]
	check(player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"The returned hull does not overlap raft buildings or shore")
	check(player._write_save("quick"),"Death-screen recovery can be saved")
	var saved: Dictionary=SAVE.read(inv.QUICK_SAVE_PATH)
	check(saved.rowboat.aboard==false and saved.health>0 and saved.slots.size()==30,"Quit from death stores a survivable player and an unboarded boat")
	check(inv.load_game("quick") and inv.slots==before,"Continue retains every full-inventory item after death")
	player.get_node("CanvasLayer/SurvivalHUD")._close_death();player.respawn_from_death();player.set_physics_process(false)
	check(stats.health==100 and inv.slots==before and get_nodes_in_group("player_boat").size()==1,"Respawn restores health without duplicating boats or changing inventory")
	service.on_death();check(inv.slots==before and get_nodes_in_group("player_boat").size()==1,"Repeated death recovery stays idempotent")
	# Enclosed water keeps the paid boat ready rather than placing it through land.
	var blockade:=StaticBody3D.new();blockade.position=raft.global_position;var collision:=CollisionShape3D.new();var wall:=BoxShape3D.new();wall.size=Vector3(100,8,100);collision.shape=wall;blockade.add_child(collision);current_scene.add_child(blockade);await frames()
	boats.return_home();await frames()
	check(boats.boat==null and boats.ready_to_launch and boats.save_state().get("ready")==true,"Blocked recovery preserves the completed boat as ready to relaunch")
	blockade.queue_free();await frames();check(boats.launch() and inv.slots==before,"Clearing the water relaunches the recovered boat without another cost")

func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");stats=root.get_node("Stats");inv.new_game_reset(true);stats.enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft")
	for unused in 3000:
		await frames(1)
		if player.restoration_complete and player.get_node("SurvivalAction").hands_prepared and player.get_node("IslandWildlife").prepared:break
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	for animal in get_nodes_in_group("huntable_animal"):animal.set_physics_process(false)
	for child in ["RopeSystem","SurvivalProgression","SurvivalTools","SurvivalEquipment"]:player.get_node(child).set_process(false);player.get_node(child).set_physics_process(false)
	player.get_node("RainSystem").stop_rain()
	boats=player.get_node("BoatBuilding");boats.set_process(false);service=player.get_node("SurvivalServices");service.set_process(false);action=player.get_node("SurvivalAction");action.set_process(false);mobile=player.get_node("CanvasLayer/MobileControls")
	await workshop_probe();await food_and_audio_probe();await recovery_probe()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("BOAT RECOVERY AUDIO SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
