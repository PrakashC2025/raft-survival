extends SceneTree
var checks:=0
var failures:=0
var player:Node3D
var raft:Node3D
var built:Node3D
var inventory:Node
var hud:Control
var preview:=false
var view_camera:Camera3D
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count:int=3) -> void:
	for unused in count:await physics_frame
func piece(kind:String,at:Vector3,yaw:float=0) -> Node3D:
	var result:Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name="%s_Check_%d"%[kind,result.get_instance_id()]
	result.transform=Transform3D(Basis(Vector3.UP,yaw),at);built.add_child(result);result.add_to_group("build_surface")
	if kind=="Foundation":player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),result)
	return result
func aim(kind:String,at:Vector3,body:Node3D) -> Dictionary:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_point=raft.to_global(at);player.aim_collider=body;player.aim_valid=true;player.aim_normal=Vector3.UP
	player.camera.global_position=player.aim_point+Vector3(0,3,3);player.camera.look_at(player.aim_point)
	player.call("_update_build_preview")
	return player.call("_resolve_placement",kind,player.aim_point)
func tap(at:Vector2) -> void:
	var event:=InputEventScreenTouch.new();event.index=21;event.position=at;event.pressed=true
	hud.call("_input",event);event.pressed=false;hud.call("_input",event)
func shot(label:String) -> void:
	if not preview:return
	for unused in 20:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/fixed-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,720)
	inventory=root.get_node("Inventory");inventory.call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	hud=player.get_node("CanvasLayer/SurvivalHUD")
	player.set_process(false);player.set_physics_process(false);root.get_node("Stats").enabled=false
	if preview:
		player.get_node("SurvivalProgression").set_process(false)
		player.get_node("RopeSystem").set_physics_process(false)
		player.camera.get_node("HandPivot").visible=false
		view_camera=Camera3D.new();current_scene.add_child(view_camera)
		view_camera.global_transform=player.camera.global_transform
		player.camera.current=false;view_camera.current=true
	player.build_mode=true;await frames(5);raft.set_physics_process(false);await frames(5)
	player.build_mode=false
	player.get_node("CanvasLayer/MobileControls").force_show=true
	inventory.call("add","Soil",30)
	var stock:int=inventory.call("total","Wood")
	var starting_pieces:int=built.get_child_count()
	hud.call("toggle_crafting");hud._craft_menu.select_item("PlanterPot")
	await frames()
	check(inventory.call("total","Wood")==stock and built.get_child_count()==starting_pieces,"Recipe tap opens details without spending or placing")
	check(hud._craft_menu.selected=="PlanterPot" and hud.CRAFT_ORDER.has("TreePot"),"Plant pot and tree pot are visible in crafting")
	await shot("craft-confirmation")
	hud._craft_menu._build.pressed.emit()
	check(player.build_mode and player.BUILD_RECIPE_NAMES[player.selected_piece_index]=="PlanterPot" and inventory.call("total","Wood")==stock,"Confirm pot chooses placement mode; PLACE owns the actual spend")
	var pot_deck:=piece("Foundation",Vector3(-2,0,0));await frames()
	var pot_placement:=aim("PlanterPot",Vector3(-2,0.15,0.5),pot_deck)
	check(pot_placement.get("valid",false),"Pot can be placed on top of a foundation without a centre socket")
	var soil_before:int=inventory.call("total","Soil")
	player.call("_try_build");await frames()
	var pot:=built.find_child("PlanterPot_*",false,false) as Node3D
	check(pot!=null and inventory.call("total","Wood")==stock-4 and inventory.call("total","Soil")==soil_before-2,"Placed pot is visible, solid and spends four wood plus two soil")
	if pot!=null:
		check(pot.find_child("LivingSoil",true,false)!=null,"The real placed pot contains its soil visual")
		check(not aim("PlanterPot",Vector3(-2,0.15,0.5),pot_deck).get("valid",false),"A pot overlapping an existing pot gets a red preview")
		pot.queue_free();await frames()
	hud.call("toggle_crafting");hud._craft_menu.select_item("Spear")
	var spear_before:int=inventory.call("total","Spear")
	await frames()
	check(inventory.call("total","Spear")==spear_before,"Selecting equipment does not craft it")
	hud._craft_menu._build.pressed.emit()
	check(inventory.call("total","Spear")==spear_before+1,"Separate equipment confirmation crafts exactly one item")
	hud.call("_close_crafting")
	if player.build_mode:player.call("_toggle_build")
	# Old saved seed names retain every item, becoming edible/plantable produce.
	var prior:int=inventory.call("total","Potato")
	inventory.call("add","Potato Seed",2)
	check(inventory.call("total","Potato")==prior+2 and inventory.call("total","Potato Seed")==prior+2,"Legacy seed identifiers alias produce without losing counts")
	var all_produce:=true
	for slot in inventory.slots:
		if not slot.is_empty() and str(slot.item).ends_with(" Seed"):all_produce=false
	check(all_produce,"Inventory presents actual produce instead of seed packets")
	root.get_node("Stats").health=21;root.get_node("Stats").hunger=20;root.get_node("Stats").thirst=18
	hud.visible=true;hud._bag_open=true;hud._inspect_slot=1;hud.call("_compute_layout");hud.queue_redraw()
	await shot("produce-use-and-percentages")
	var hunger_before:float=root.get_node("Stats").hunger
	var count_before:int=inventory.call("total","Potato")
	tap(hud._bag_use_rect.get_center())
	check(inventory.call("total","Potato")==count_before-1 and root.get_node("Stats").hunger>hunger_before,"Bag USE consumes one potato and restores hunger")
	check(hud.RESOURCE_PILL_ITEMS.is_empty() and hud.STATS[1][0]=="thirst","Survival percentages replace resource counters at the top")
	var controls:=player.get_node("CanvasLayer/MobileControls")
	var action_scale:=clampf(controls.size.y/720.0,.80,1.35)
	check(is_equal_approx(controls._btn_use.size.x,92*action_scale) and controls._btn_use.size.x>controls._btn_run.size.x and controls._btn_use.position.is_equal_approx(controls._btn_climb.position) and not (controls._btn_use.visible and controls._btn_climb.visible),"Ergonomic Use action target shares its position only with mutually exclusive Climb")
	if preview:
		hud._toast=""
		player.get_node("SurvivalAction").call("stop")
		player.get_node("SurvivalAction").set_process(false)
	piece("Foundation",Vector3(-4,0,0));await frames()
	for crop in ["Potato","Tomato","Carrot","Coconut","Banana","Onion"]:
		var bed:=piece("TreePot" if crop in ["Coconut","Banana"] else "PlanterPot",Vector3(-4,0.4 if crop in ["Coconut","Banana"] else 0.325,0)) as Node3D
		check(bed.plant_seed(crop),crop+" plants from the same edible crop")
		var plant:Node3D=bed._plant
		check(plant._container.get_child_count()>0 and plant._container.scale.y>=0.15,crop+" shows a visible small plant immediately")
		var initial_time:float=plant.call("growth_seconds_remaining")
		player.build_mode=false;player.aim_valid=true;player.aim_collider=bed;player.aim_distance=2
		plant.call("_update_interaction",0.0)
		check(plant._progress_ui.visible and plant._prompt_label.text.contains("until grown"),crop+" countdown appears when aiming its pot")
		player.aim_collider=plant;plant.call("_update_interaction",0.0)
		check(plant._progress_ui.visible and plant._prompt_label.text.contains(":"),crop+" countdown also appears when aiming the young plant")
		plant.call("_process",1.0)
		check(plant.call("growth_seconds_remaining")<initial_time and plant._container.scale.y>0.16,crop+" visibly grows while its countdown decreases")
		bed.moisture=0.0
		check(plant.call("growth_seconds_remaining")>initial_time*3 and plant.call("growth_caption").contains("DRY SOIL"),crop+" dry-soil countdown reflects slower growth")
		bed.moisture=0.75
		if crop=="Carrot":
			check(plant._container.find_child("CarrotPlantModel",true,false)!=null,"Carrot uses the supplied Blender plant model")
			var bounds:AABB=plant.call("_node_local_aabb",plant._container.get_node("CarrotPlantModel"))
			check(absf(bounds.get_center().x)<0.2 and bounds.size.y>0.6,"Carrot geometry grows at the soil slot rather than its source display offset")
			if preview:
				view_camera.global_position=raft.to_global(Vector3(-3.6,1.0,0.9));view_camera.look_at(bed.global_position+Vector3.UP*0.15)
				await shot("carrot-sapling-countdown")
		if crop=="Banana":
			check(plant._container.find_child("BananaPlantModel",true,false)!=null,"Planted banana uses the supplied FBX derivative")
			if preview:
				view_camera.global_position=raft.to_global(Vector3(-3,1.35,1.7));view_camera.look_at(bed.global_position+Vector3.UP*0.35)
				await shot("banana-sapling-countdown")
		for unused in 3:bed._plant.call("_process",130.0)
		check(bed._plant._stage==3,crop+" grows to harvestable maturity")
		var state:Dictionary=bed.call("save_plant_state")
		check(state.id==crop and state.stage==3,crop+" preserves mature planting state")
		if crop=="Banana":
			plant.call("_update_fruits",100.0);await frames()
			var fruit:Dictionary=plant._fruits[0]
			var at:Vector3=plant.to_global(fruit.pos)
			var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.4,at,1)
			var hit:Dictionary=current_scene.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and hit.collider==plant,"Ripe bananas have reachable aiming collision separate from the stem")
			var before:int=inventory.call("total","Banana")
			player.aim_collider=plant;player.aim_point=at;plant.call("_pick_fruit",fruit)
			check(inventory.call("total","Banana")>before and fruit.elapsed==0.0,"Picking ripe banana gives edible planting fruit and starts regrowth")
			if preview:player.get_node("SurvivalAction").call("stop")
		if crop=="Banana" and preview:
			view_camera.global_position=raft.to_global(Vector3(-1.4,2.1,3.2));view_camera.look_at(bed.global_position+Vector3.UP*1.2)
			await shot("banana-grown")
		if crop=="Carrot" and preview:
			view_camera.global_position=raft.to_global(Vector3(-3.3,1.4,1.4));view_camera.look_at(bed.global_position+Vector3.UP*0.4)
			await shot("carrot-grown")
			plant._container.position.y=0.45
			await shot("carrot-root-harvest")
		var prompt:Control=plant._progress_ui
		bed.queue_free();await frames()
		check(not is_instance_valid(prompt),crop+" countdown is removed with the plant")
	var island_banana:Node=null
	for unused in 600:
		for plant in get_nodes_in_group("plant"):
			if plant.plant_id=="Banana" and plant.get_parent().is_in_group("island_grove"):island_banana=plant;break
		if island_banana!=null:break
		await physics_frame
	check(island_banana!=null and island_banana._container.find_child("BananaPlantModel",true,false)!=null,"Island bananas use the same supplied tree model")
	# An isolated dry island surface proves actual ground planting and restore.
	var island:=StaticBody3D.new();island.name="TestGardenIsland";island.position=Vector3(90,2,90)
	var ground_col:=CollisionShape3D.new();var ground_shape:=BoxShape3D.new();ground_shape.size=Vector3(12,0.2,12)
	ground_col.shape=ground_shape;island.add_child(ground_col);current_scene.add_child(island);island.add_to_group("island")
	await frames()
	inventory.call("add","Tomato",2);player.active_item="Tomato"
	player.aim_valid=true;player.aim_collider=island;player.aim_point=island.to_global(Vector3(0,0.1,0));player.aim_normal=Vector3.UP;player.aim_distance=2
	check(player.call("_plant_on_ground"),"A tomato plants directly in dry level island sand/soil")
	var gardens:Array=player.call("_serialize_ground_crops")
	check(gardens.size()==1 and gardens[0].plant.id=="Tomato","Ground crop saves island position, moisture and growth")
	for bed in get_nodes_in_group("ground_plot"):bed.queue_free()
	await frames();inventory.loaded_meta["ground_crops"]=gardens;player.call("_restore_ground_crops")
	check(get_nodes_in_group("ground_plot").size()==1,"Ground farming restores into the same island without requiring a pot")
	for bed in get_nodes_in_group("ground_plot"):bed.queue_free()
	island.queue_free();inventory.loaded_meta.erase("ground_crops");await frames()
	# Build a ceiling and verify a single narrow corridor, including real travel.
	piece("Foundation",Vector3(2,0,0));piece("Foundation",Vector3(0,0,2))
	for z in range(1,5):
		for x in range(1,4):piece("Foundation",Vector3(x*2,0,z*2))
	await frames()
	var deck:Node3D=player._grid_occupancy[Vector2i(2,2)]
	player._editing=deck
	player.call("_set_edit_color",player._ghost_invalid_mat)
	player.call("_apply_building_color",deck);player._editing=null
	check(deck.get_node("TimberDetails/JoinedRoundedTimbers").material_override==null,"Finishing an edit restores timber instead of leaving the red highlight")
	player.build_rotation=PI/12
	var gap:=aim("Foundation",Vector3(8,0.15,4),deck)
	check(gap.get("valid",false) and absf((raft.global_basis.inverse()*gap.transform.basis).x.z)<0.001,"Fine rotation keeps a square foundation aligned with its 2m grid")
	check(not aim("Foundation",Vector3(4,0.15,4),deck).get("valid",false),"An occupied foundation cell stays red instead of jumping to another cell")
	check((player.ghost.get_node("TimberDetails/JoinedRoundedTimbers").material_override as StandardMaterial3D).albedo_color.r>0.8,"Invalid preview overrides the visible timber material")
	player.build_rotation=0
	var roofs:Array[Node3D]=[]
	for z in range(1,5):
		for x in range(1,4):roofs.append(piece("Roof",Vector3(x*2,2.725,z*2)))
	var flight:=piece("Stairs",Vector3(4,0.25,3))
	await frames(15)
	for roof in roofs:roof.call("refresh")
	await frames()
	var physical:PhysicsDirectSpaceState3D=current_scene.get_world_3d().direct_space_state
	var clear:=true
	for fraction in [.25,.55,.8,.98]:
		var z:float=flight.position.z+float(flight.run)*fraction
		var q:=PhysicsRayQueryParameters3D.create(raft.to_global(Vector3(4,3.0,z)),raft.to_global(Vector3(4,2.5,z)),1)
		var hit:=physical.intersect_ray(q)
		if not hit.is_empty() and str(hit.collider.name).begins_with("Roof"):clear=false
	check(clear,"The stair opening is one continuous unobstructed corridor")
	var beside:=PhysicsRayQueryParameters3D.create(raft.to_global(Vector3(4.85,3.0,4.5)),raft.to_global(Vector3(4.85,2.5,4.5)),1)
	check(not physical.intersect_ray(beside).is_empty(),"Ceiling remains beside the stairs instead of losing whole tiles")
	var rain:=player.get_node("RainSystem");rain.call("start_rain",120);rain.call("_refresh_shelter_masks")
	check(not rain.call("rain_visible_at",raft.to_global(Vector3(2,1.5,4))),"Covered room blocks rain below a real ceiling panel")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(4,2.2,4.5))),"Rain remains visible through the real stair opening")
	var wall:=piece("Wall",Vector3(1,1.4,4),PI/2);await frames();rain.call("_refresh_shelter_masks")
	check(not rain.call("rain_visible_at",wall.global_position),"Rain streaks cannot render inside a solid wall")
	if preview:
		player.get_node("SurvivalAction").call("stop");hud._toast=""
		if player.build_mode:player.call("_toggle_build")
		view_camera.global_position=raft.to_global(Vector3(4,6.8,7.4));view_camera.look_at(raft.to_global(Vector3(4,1.8,4.7)))
		await shot("single-stair-opening")
		view_camera.global_position=raft.to_global(Vector3(2,1.7,5.8));view_camera.look_at(raft.to_global(Vector3(0,1.5,4)))
		rain._camera=view_camera;rain._intensity=1.0
		await shot("sheltered-rain")
	if player.build_mode:player.call("_toggle_build")
	rain.call("stop_rain")
	player.global_position=raft.to_global(Vector3(4,1.05,2.5));player.velocity=Vector3.ZERO;player.is_swimming=false
	for step in 210:
		await physics_frame
		player.velocity=Vector3(0,player.velocity.y-18.0*player.get_physics_process_delta_time(),1.6)
		player.call("_try_step_up");player.move_and_slide()
		if raft.to_local(player.global_position).z>6.4:break
	check(raft.to_local(player.global_position).y>3.55 and raft.to_local(player.global_position).z>6.1,"Player walks up the stairs through the ceiling without jumping or obstruction")
	for step in 210:
		await physics_frame
		player.velocity=Vector3(0,player.velocity.y-18.0*player.get_physics_process_delta_time(),-1.6)
		player.move_and_slide()
		if raft.to_local(player.global_position).z<2.65:break
	check(raft.to_local(player.global_position).y<1.2 and raft.to_local(player.global_position).z<3.2,"Player walks back down through the same opening")
	flight.queue_free();await frames(15)
	var closed:=PhysicsRayQueryParameters3D.create(raft.to_global(Vector3(4,3,4.5)),raft.to_global(Vector3(4,2.5,4.5)),1)
	check(not physical.intersect_ray(closed).is_empty(),"Removing stairs closes the generated ceiling opening")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(25)
	print("SHELTER FARMING UI SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
