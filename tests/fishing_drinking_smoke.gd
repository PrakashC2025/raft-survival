extends SceneTree
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var inv: Node
var action: Node
var equipment: Node
var service: Node
var review_camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func take() -> void:
	Input.action_press("interact");player.call("_handle_pickup");Input.action_release("interact")
	# Headless runners may consume just_pressed at a different frame boundary.
	# Exercise the same command directly if the input edge was not observed.
	if action.kind!="take_fish":player.call("_handle_selected_item_use")
func pose(progress: float) -> void:
	action.elapsed=action.duration*progress;action.call("_process",0.0)
	player.call("_update_hand_sway",0.0)
	player.call("_update_survivor_animation",false)
	equipment.call("_update_cast")
func shot(label: String) -> void:
	if not preview:return
	for unused in 6:
		player.call("_update_survivor_animation",false);await physics_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/fishing-"+label+".png")==OK,"Rendered "+label+" with actual held props")
func full_bag() -> void:
	for index in inv.SLOT_COUNT:inv.slots[index]={"item":"Wood","count":inv.MAX_STACK}
	inv.slots[0]={"item":"Rope","count":1};inv.slots[1]={"item":"Fishing Rod","count":1}
	inv.call("_recompute");inv.changed.emit();service.call("equip_owned","Fishing Rod")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(90).timeout.connect(func():push_error("FAIL: fishing preview timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false
	root.get_node("Stats").enabled=false
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	for child in scene.get_children():
		if str(child.name) not in ["Player","Raft","Ocean","Sky3D","OceanAtmosphere"]:scene.remove_child(child);child.free()
	var packed:=PackedScene.new();packed.pack(scene);scene.free();change_scene_to_packed(packed);await scene_changed
	player=current_scene.get_node("Player");player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	player.get_node("SurvivalProgression").set_process(false)
	current_scene.get_node("Raft").set_physics_process(false)
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause");clock.current_time=12.0;clock.call("_update_celestial_coords");clock.get_node("Timer").emit_signal("timeout")
	action=player.get_node("SurvivalAction");equipment=player.get_node("SurvivalEquipment");service=player.get_node("SurvivalServices")
	while not action.hands_prepared:await frames()
	action.set_process(false);equipment.set_physics_process(false);service.set_process(false)
	player.get_node("RainSystem").call("stop_rain");current_scene.get_node("OceanAtmosphere").set_process(false)
	player.global_position=Vector3(0,1.3,0);player.rotation.y=0;player.cam_mode=0;player.call("_apply_camera_mode")
	for unused in 40:
		await physics_frame;player.call("_physics_process",1.0/60.0)
	player.get_node("CanvasLayer").hide()
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	inv.call("_recompute");inv.changed.emit();inv.call("add","Fishing Rod",1);service.call("equip_owned","Fishing Rod")
	check(not player._fishing_catch,"New or older saves default to an empty hook")
	player.camera.look_at(Vector3(0,0,-8));await frames()
	check(player.call("_valid_fishing_cast"),"Downward open-ocean aim accepts a cast")
	player.camera.look_at(player.camera.global_position+Vector3(0,1,-1))
	check(not player.call("_valid_fishing_cast"),"Sky aim cannot cast into the air")
	player.camera.look_at(Vector3(0,0,-8));player.call("_handle_selected_item_use")
	check(player._fishing_time_remaining>=4.0 and action.kind=="cast" and equipment._line.visible,"Casting releases a visible line and float over water")
	pose(.5);await shot("cast-first-person")
	action.call("stop");player._fishing_time_remaining=2.0;player.call("_tick_fishing",.9)
	check(action.kind=="reel" and player._fishing_time_remaining>0,"Reel action begins before the catch leaves the water")
	player.call("_tick_fishing",2.0);action.call("stop");equipment.call("_update_cast")
	check(player._fishing_catch and int(inv.call("total","Fish"))==0,"Reeled fish stays on the hook without an automatic bag reward")
	check(equipment._catch_visual.visible and equipment._line.visible,"Caught textured fish and line remain visible after the timer ends")
	equipment._cast_clock=.15;equipment.call("_update_cast");var caught_rotation: Vector3=equipment._catch_visual.rotation
	equipment._cast_clock=.45;equipment.call("_update_cast")
	check(equipment._catch_visual.rotation.distance_to(caught_rotation)>.01,"Caught fish struggles in short swinging bursts")
	check(player.call("interaction_caption")=="TAKE FISH" and player.call("can_interact_now"),"Hand action explicitly offers TAKE FISH")
	var controls:=player.get_node("CanvasLayer/MobileControls");controls.call("_sync_mode")
	check(controls._btn_use.visible and controls._use_caption=="TAKE FISH","Mobile uses the existing large hand control for unhooking")
	await shot("caught-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode");equipment.call("_update_cast");action.call("_process",0.0)
	if preview:
		review_camera=Camera3D.new();review_camera.fov=42;current_scene.add_child(review_camera);review_camera.current=true
		review_camera.global_position=player.global_position+Vector3(1.5,.75,-2.0);review_camera.look_at(player.global_position+Vector3(0,.18,-.15))
	await shot("caught-third-person")
	pose(.0);await frames()
	check(player.call("get_fishing_rod_tip").y>equipment._catch_visual.global_position.y+.18,"Raised rod tip supports the hanging fish from above")
	player.call("_write_save","main");check(inv.call("load_game") and bool(inv.loaded_meta.get("fishing_catch",false)),"Pending catch is preserved in the existing save metadata")
	service.call("equip_owned","Fishing Rod")
	take();pose(.39)
	check(player._fishing_catch and int(inv.call("total","Fish"))==0 and not action._pickup_third.visible,"Reach animation cannot collect before unhooking contact")
	pose(.405)
	check(not player._fishing_catch and int(inv.call("total","Fish"))==1 and not equipment._catch_visual.visible and action._pickup_third.visible,"One fish moves from line to left hand at visible contact")
	check(action._held.visible and action._tool.get_node("AnimatedHandGrip").wrist==action._tool.get_node("AnimatedHandGrip").skeleton.find_bone("Wrist.L"),"Right hand keeps the rod while left hand takes the fish")
	await shot("unhook-third-person")
	player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true;pose(.55)
	var rod_transform: Transform3D=player._hand_item.transform
	pose(.70)
	check(player._hand_item.position.distance_to(rod_transform.origin)<.001 and player._hand_item.basis.is_equal_approx(rod_transform.basis),"First-person rod stays steady while the separate left hand withdraws")
	await shot("unhook-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode")
	if preview:review_camera.current=true
	pose(.60);pose(.60)
	check(int(inv.call("total","Fish"))==1 and not player.call("take_fishing_catch"),"Repeated contact and collect calls cannot duplicate fish")
	action.call("stop");full_bag();player._fishing_catch=true;equipment.call("_update_cast");take()
	check(player._fishing_catch and action.kind!="take_fish" and equipment._catch_visual.visible,"Full bag leaves caught fish on the line")
	inv.slots[2]={};inv.call("_recompute");inv.changed.emit();take()
	inv.slots[2]={"item":"Wood","count":inv.MAX_STACK};inv.call("_recompute");inv.changed.emit();pose(.405)
	check(player._fishing_catch and action.kind.is_empty() and int(inv.call("total","Fish"))==0,"Late bag overflow safely cancels handoff without losing the fish")
	inv.slots[2]={};inv.call("_recompute");inv.changed.emit();take();player.is_swimming=true;pose(.405)
	check(player._fishing_catch and action.kind.is_empty(),"Entering water interrupts unhooking without awarding or discarding the catch")
	player.is_swimming=false;take();player.active_item="Wood";pose(.405)
	check(player._fishing_catch and action.kind.is_empty(),"Changing tools before contact retains the catch")
	service.call("equip_owned","Fishing Rod");equipment.call("_update_cast");take();pose(.405)
	check(int(inv.call("total","Fish"))==1 and not player._fishing_catch,"A retained catch can be collected later when space is available")
	action.call("stop")
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	inv.call("_recompute");inv.changed.emit();inv.call("add","Boiled Water Tumbler",2);service.call("equip_owned","Boiled Water Tumbler")
	player.cam_mode=0;player.call("_apply_camera_mode");player.camera.current=true;player.camera.rotation=Vector3.ZERO
	check(service.call("use_item","Boiled Water Tumbler") and action.duration>=2.7,"Drinking leaves time to raise, sip, swallow and lower the cup")
	check(not service.call("use_item","Boiled Water Tumbler") and int(inv.call("total","Boiled Water Tumbler"))==1,"Repeated use cannot restart a drink and consume extra cups")
	pose(.285)
	check(action._cues_played==1 and action._sound.stream==action.FOLEY.sip and action._sound.playing,"Recorded sip begins once at mouth contact")
	pose(.285);check(action._cues_played==1,"Held mouth pose cannot repeat the sip")
	pose(.55)
	check(action._food_first.rotation.x>.9 and action._food_first.get_node("DrinkingWater").position.y<.05,"Rim tilts toward lips as liquid steadily lowers")
	var mouth_pose: Dictionary=action.call("sample_pose");pose(.70)
	check(action.call("sample_pose").view_pos.distance_to(mouth_pose.view_pos)<.001,"Cup stays steady at the mouth during the recorded swallow")
	await shot("drink-first-person")
	player.cam_mode=1;player.call("_apply_camera_mode");pose(.55)
	if preview:review_camera.current=true
	await shot("drink-third-person")
	pose(.995);check(action.call("sample_pose").view_pos.length()<.001,"Drinking lowers smoothly to rest")
	action.call("stop");check(not action._sound.playing and action._food_first==null,"Completion removes drink props and stops sound")
	player.call("_write_save","main");check(inv.call("load_game") and not bool(inv.loaded_meta.get("fishing_catch",true)),"Collected fish does not return on Continue")
	current_scene.queue_free();await frames(12)
	print("FISHING DRINKING: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
