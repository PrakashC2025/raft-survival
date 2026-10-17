extends SceneTree
## Actual travel controls, opaque relocation, continued sailing and safe interruption.
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var hud: Control
var controls: Control
var inv: Node
var skip: Script

func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
	await process_frame
func tap(at: Vector2,index: int=54) -> void:
	var finger:=InputEventScreenTouch.new();finger.index=index;finger.position=at;finger.pressed=true;root.push_input(finger,true)
	var mouse:=InputEventMouseButton.new();mouse.device=-1;mouse.position=at;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	root.push_input(mouse,true);mouse.pressed=false;root.push_input(mouse,true);finger.pressed=false;root.push_input(finger,true)
func shot(label: String) -> void:
	if not preview:return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/trip-skip-"+label+".png")==OK,"Rendered "+label)

func finish_fade(effect: CanvasLayer,label: String) -> void:
	var opaque_jump:=false
	var fractional_out:=false
	var fractional_in:=false
	var captured_out:=false
	var captured_black:=false
	var captured_in:=false
	for unused in 700:
		await process_frame
		if not is_instance_valid(effect) or not effect.active:break
		var alpha: float=effect._black.color.a
		if effect.phase=="out" and alpha>.15 and alpha<.9:
			fractional_out=true
			if not captured_out:captured_out=true;await shot(label+"-fade-out")
		if effect.committed and effect.phase=="warm":
			opaque_jump=opaque_jump or alpha>.999
			if not captured_black:captured_black=true;await shot(label+"-black")
		if effect.phase=="in" and alpha>.15 and alpha<.9:
			fractional_in=true
			if not captured_in and alpha<.6:captured_in=true;await shot(label+"-fade-in")
	check(not hud.call("_trip_skipping"),label+" transition finishes without a permanent black screen")
	check(fractional_out and fractional_in and opaque_jump,label+" fades gradually and relocates only under opaque black")
	await frames(3)

func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(170).timeout.connect(func():push_error("FAIL: travel skip timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	skip=load("res://scripts/course_skip.gd");inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player") as CharacterBody3D;raft=get_first_node_in_group("raft") as Node3D
	for unused in 3000:
		await process_frame
		if player.restoration_complete and current_scene.get_node("SpringIsle").prepared and current_scene.get_node("WinterIsle").prepared and current_scene.get_node("UnderwaterWorld").prepared:break
	check(player.restoration_complete and current_scene.get_node("SpringIsle").prepared,"World and real island colliders prepare in isolated storage")
	controls=player.get_node("CanvasLayer/MobileControls");controls.force_show=true;controls.call("_update_visibility");controls.call("_sync_mode")
	hud=player.get_node("CanvasLayer/SurvivalHUD");hud.visible=true
	player.set_process(false);player.set_physics_process(false);player.build_mode=false;player.is_swimming=false;player.velocity=Vector3.ZERO
	player.get_node("SurvivalAction").stop();raft.set_upgrade_tier(1);raft.set_anchored(false,false)
	player.global_position=raft.to_global(Vector3(0,1.06,0));await frames(4)
	var spring_direction: Vector3=current_scene.get_node("SpringIsle").global_position-player.global_position
	player.rotation.y=atan2(-spring_direction.x,-spring_direction.z)
	check(skip.aboard(raft,player),"Skip requires the player to be standing on the actual raft")
	check(player.request_course_to(current_scene.get_node("SpringIsle")),"A raft-to-island course uses the existing map navigation")
	for resolution in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(960,540),Vector2i(1280,960)]:
		root.size=resolution;await frames();hud.call("_compute_layout");controls.call("_apply_viewport_size");controls.call("_sync_mode")
		check(hud._trip_skip_rect.size.y>=48 and Rect2(Vector2.ZERO,hud.size).encloses(hud._trip_skip_rect) and hud.claims_touch(hud._trip_skip_rect.get_center()),"Dedicated Skip Trip is readable and owns its touch at %s"%resolution)
		var separated:=true
		for button in controls._all_buttons:
			if button.visible and hud._trip_skip_rect.intersects(button.get_global_rect()):separated=false
		check(separated,"Skip Trip stays clear of steering and activity controls at %s"%resolution)
	root.size=Vector2i(1280,720);await frames();hud.call("_compute_layout")
	controls.force_show=false;controls.call("_update_visibility");hud._toast="";await frames()
	check(hud.call("_feedback_only") and hud.call("_should_show") and hud._trip_skip_rect.has_area(),"Desktop travel retains a Skip Trip card while touch controls are hidden")
	controls.force_show=true;controls.call("_update_visibility");controls.call("_sync_mode");await frames()
	await shot("raft-button")
	var counts: Array=inv.slots.duplicate(true)
	var initial_distance: float=raft.get_course_distance()
	var rider_offset:=player.global_position-raft.global_position
	var floor_layers:=player.platform_floor_layers
	var leave_mode:=player.platform_on_leave
	tap(hud._trip_skip_rect.get_center())
	var transition: CanvasLayer=hud._trip_transition
	check(hud.call("_trip_skipping") and not paused and hud.gameplay_input_blocked(),"One Skip tap begins one fade and releases gameplay without pausing the sea")
	check(not transition.committed and raft.get_course_distance()>initial_distance-10,"The jump waits for the fade-out")
	check(controls._move_id==-1 and controls._look_id==-1 and not Input.is_action_pressed("interact"),"Skip releases owned movement, camera and interaction fingers")
	player.set_physics_process(true)
	await finish_fade(transition,"raft")
	check(raft.has_active_course() and raft.get_course_distance()<150 and raft.get_course_distance()>raft._arrival_radius+10,"Raft skip leaves an active final sailing approach near the island")
	check((player.global_position-raft.global_position).distance_to(rider_offset)<.65 and not player.is_swimming and player.velocity.length()<5,"The actual player stays on deck without being flung by platform velocity")
	check(player.platform_floor_layers==floor_layers and player.platform_on_leave==leave_mode and not raft.has_meta("trip_skip_active"),"Normal platform and input ownership restore after the fade")
	var raft_at:=raft.global_position;await frames(15)
	check(Vector2(raft.global_position.x-raft_at.x,raft.global_position.z-raft_at.z).length()>.2,"The raft continues sailing after the reveal")
	check(inv.slots==counts,"Skipping preserves every inventory slot and count")
	await shot("raft-arrival")
	raft.clear_course();player.set_physics_process(false)
	var boat: CharacterBody3D=load("res://scripts/rowboat.gd").new();current_scene.add_child(boat)
	boat.global_position=raft.global_position+Vector3(8,0,0);boat.global_position.y=.03
	player.get_node("BoatBuilding").boat=boat;player.is_swimming=false
	check(boat.board(player,true),"Player boards a real rowboat at the arrival island")
	var body: StaticBody3D=load("res://scripts/animal_carcass.gd").new();body.species="Boar";boat.add_child(body);body.position=Vector3(.3,.24,-.55);body.contents[0]={"item":"Raw Meat","count":3}
	var cargo_local:=body.position
	check(player.request_course_to(current_scene.get_node("WinterIsle")),"An island-to-island rowboat course is available")
	var direction: Vector3=current_scene.get_node("WinterIsle").global_position-boat.global_position;direction.y=0;direction=direction.normalized()
	boat.rotation.y=atan2(-direction.x,-direction.z);boat.velocity=direction*boat.SPEED
	await frames(8);hud.toggle_map();await frames();hud.call("_compute_layout")
	check(hud._map_cancel_course_rect.has_area() and not hud._map_course_rect.intersects(hud._map_cancel_course_rect),"MAP separates Skip Trip from Cancel for both vessels")
	await shot("map-controls")
	tap(hud._map_cancel_course_rect.get_center())
	check(not boat.has_active_course() and hud._map_open,"Cancel stops auto rowing separately and keeps the chart available")
	hud._selected_island=current_scene.get_node("WinterIsle");tap(hud._map_course_rect.get_center());await frames()
	check(boat.has_active_course() and not hud._map_open,"Selecting another island starts a fresh course after Cancel")
	hud.toggle_map();await frames();hud.call("_compute_layout")
	tap(hud._map_course_rect.get_center());transition=hud._trip_transition
	check(not hud._map_open and not paused and hud.call("_trip_skipping"),"Map Skip closes the chart and fades into moving gameplay")
	var stroke: float=boat._stroke_phase
	player.set_physics_process(true)
	await finish_fade(transition,"boat")
	check(player.boat_vehicle==boat and boat.driver==player and boat.has_active_course(),"Skip keeps driver ownership and the rowboat course")
	check(boat.velocity.length()>3 and boat._rowing_weight>.5 and boat._stroke_phase>stroke,"The rowboat keeps its speed and animated rowing through the transition")
	check(boat.get_course_distance()<170 and boat.get_course_distance()>boat._arrival_radius+10,"Rowboat reveals near the second island with a remaining approach")
	check(body.get_parent()==boat and body.position.is_equal_approx(cargo_local) and body.contents[0].count==3,"Hunted cargo keeps its support, local position and exact contents")
	check(player.global_position.distance_to(boat.to_global(Vector3(0,1.03,.48)))<.1,"The driver remains in the moving seat")
	var boat_at:=boat.global_position;await frames(12)
	check(boat.global_position.distance_to(boat_at)>.4,"Rowboat keeps travelling after the fade-in finishes")
	check(boat.save_state().aboard and Vector3(boat.save_state().p[0],boat.save_state().p[1],boat.save_state().p[2]).distance_to(boat.global_position)<.01,"Existing boat save data describes the new position and seated driver")
	await shot("boat-arrival")
	if preview:
		var previous_camera: int=player.cam_mode
		player.cam_mode=player.CAM_TPS_MEDIUM;player.call("_apply_camera_mode");await frames(6)
		await shot("boat-arrival-third-person")
		player.cam_mode=previous_camera;player.call("_apply_camera_mode")
	# Cancelling a fade before the jump preserves the ordinary voyage.
	boat.clear_course();boat.global_position=Vector3(-700,.03,700);boat.velocity=Vector3(0,0,-3);boat.sync_driver()
	boat.set_course(Vector3(-700,0,350),18);hud.call("_compute_layout");boat.set_physics_process(false)
	tap(hud._trip_skip_rect.get_center());var before_cancel:=boat.global_position
	hud.handle_back();await frames()
	check(not hud.call("_trip_skipping") and boat.global_position.is_equal_approx(before_cancel) and boat.has_active_course(),"Back before relocation cancels the fade and preserves the voyage")
	check(not boat.has_meta("trip_skip_active") and player.platform_floor_layers==floor_layers,"Cancelling clears the overlay and restores ownership")
	# All candidate landing positions are inside this isolated blocking wall.
	var obstacle:=StaticBody3D.new();obstacle.collision_layer=1;current_scene.add_child(obstacle)
	var collision:=CollisionShape3D.new();var wall:=BoxShape3D.new();wall.size=Vector3(250,10,190);collision.shape=wall;obstacle.add_child(collision)
	var target:=Vector3(-700,0,450);obstacle.global_position=target+Vector3(0,0,100)
	boat.set_course(target,18);await frames(3)
	var before_block:=boat.global_position
	check(not boat.skip_course() and boat.global_position.is_equal_approx(before_block) and boat.has_active_course(),"A blocked destination rejects the jump without stopping or moving the boat")
	obstacle.queue_free();await frames()
	boat.set_course(boat.global_position+Vector3(0,0,-40),18);hud.call("_compute_layout")
	check(not boat.can_skip_course() and not hud._trip_skip_rect.has_area(),"The final approach hides Skip instead of making a tiny or backwards jump")
	boat.set_course(Vector3(-700,0,350),18);hud.call("_compute_layout");tap(hud._trip_skip_rect.get_center())
	var interrupted: CanvasLayer=hud._trip_transition
	interrupted.phase="move";interrupted._black.color.a=1;interrupted._physics_process(0)
	check(interrupted.committed and player.platform_floor_layers==0,"A completed jump retains temporary platform ownership until its reveal")
	interrupted._notification(NOTIFICATION_APPLICATION_FOCUS_OUT);await frames()
	check(not hud.call("_trip_skipping") and not boat.has_meta("trip_skip_active") and not hud.gameplay_input_blocked(),"Backgrounding safely clears the fade without leaving blocked controls")
	check(player.platform_floor_layers==floor_layers and player.platform_on_leave==leave_mode,"Backgrounding after relocation also restores normal platform settings")
	boat._release_driver();player.is_swimming=true;hud.call("_compute_layout")
	check(not skip.aboard(boat,player) and not hud._trip_skip_rect.has_area(),"A swimmer cannot skip a boat or be carried across the sea")
	player.is_swimming=false;raft.set_anchored(true,false)
	check(not raft.can_skip_course() and not raft.skip_course(),"Anchored raft and inactive routes cannot skip")
	boat.queue_free();current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(25)
	print("TRIP SKIP SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
