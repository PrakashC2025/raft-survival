extends SceneTree
var checks:=0
var failures:=0
var player:Node3D
var raft:Node3D
var built:Node3D
var inventory:Node
var preview:=false
var view_camera:Camera3D
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count:int=3) -> void:
	for unused in count:await physics_frame
func piece(kind:String,at:Vector3) -> Node3D:
	var result:Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name="%s_OnionCheck_%d"%[kind,result.get_instance_id()]
	result.position=at;built.add_child(result);result.add_to_group("build_surface")
	if kind=="Foundation":player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),result)
	return result
func aim(kind:String,at:Vector3,body:Node3D,normal:Vector3=Vector3.UP) -> Dictionary:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_point=raft.to_global(at);player.aim_collider=body;player.aim_valid=body!=null;player.aim_normal=normal;player.aim_distance=2
	player.camera.global_position=player.aim_point+Vector3(0,3,3);player.camera.look_at(player.aim_point)
	player.call("_update_build_preview")
	return player.call("_resolve_placement",kind,player.aim_point)
func shot(label:String) -> void:
	if not preview:return
	for unused in 12:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/onion-"+label+".png")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inventory=root.get_node("Inventory");inventory.call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);root.get_node("Stats").enabled=false
	player.build_mode=true;await frames(8);raft.set_physics_process(false);await frames(5)
	player.get_node("SurvivalProgression").set_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	if preview:
		view_camera=Camera3D.new();current_scene.add_child(view_camera);view_camera.current=true;player.camera.current=false
		player.camera.get_node("HandPivot").visible=false
	check(inventory.call("total","Onion")==4,"New games receive four edible, plantable onions")
	var deck:=piece("Foundation",Vector3(2,0,0))
	var roof:=piece("Roof",Vector3(2,2.725,0))
	piece("Wall",Vector3(2,1.4,1));await frames(8)
	for kind in ["PlanterPot","PlanterBox","TreePot"]:
		var result:=aim(kind,Vector3(2,0.15,0),deck)
		check(result.get("valid",false),kind+" is accepted on a foundation top")
		result=aim(kind,Vector3(2,2.8,0),roof)
		check(result.get("valid",false),kind+" is accepted on a roof top")
		check(not aim(kind,Vector3(3.9,0.15,0),null).get("valid",false),kind+" rejects ocean beside a foundation without plane fallback")
		check(not aim(kind,Vector3(2.95,0.15,0),deck).get("valid",false),kind+" rejects an overhanging base instead of clamping it onto the deck")
		check(not aim(kind,Vector3(2,0,0.99),deck,Vector3.FORWARD).get("valid",false),kind+" rejects a foundation side face")
		check(not aim(kind,Vector3(0,0.15,0),raft).get("valid",false),kind+" requires a foundation or roof instead of the bare raft")
	# Successful PLACE plus revalidation against a stale green preview.
	inventory.call("add","Soil",30)
	aim("PlanterPot",Vector3(2,0.15,0),deck)
	var wood:int=inventory.call("total","Wood")
	player.aim_collider=null;player.aim_valid=false;player.aim_point=raft.to_global(Vector3(4,0,0))
	player.call("_try_build")
	check(inventory.call("total","Wood")==wood and built.find_child("PlanterPot_*",false,false)==null,"PLACE rejects changed unsupported aim without spending materials")
	aim("PlanterPot",Vector3(2,0.15,0),deck);player.call("_try_build");await frames()
	var pot:=built.find_child("PlanterPot_*",false,false) as Node3D
	check(pot!=null and inventory.call("total","Wood")==wood-4,"A real pot builds on the foundation top")
	if pot!=null:
		player.call("_start_edit",pot);await frames()
		aim("PlanterPot",Vector3(2,2.8,0),roof);player.call("_update_edit_follow")
		check(player._edit_valid,"Moving a pot onto a roof top gives a valid preview")
		player.call("_confirm_edit");await frames()
		check(player._editing==null and absf(raft.to_local(pot.global_position).y-2.975)<0.02,"Moved pot rests on top of the roof")
		check(player._grid_occupancy.get(Vector2i(1,0))==deck,"Moving a pot preserves the foundation occupancy grid")
		var roof_position:Vector3=pot.global_position
		player.call("_start_edit",pot);await frames()
		aim("PlanterPot",Vector3(4,0.15,0),null);player.call("_update_edit_follow");player.call("_confirm_edit")
		check(not player._edit_valid and player._editing==pot,"Moving a pot over ocean stays red and cannot confirm")
		if preview:
			view_camera.global_position=raft.to_global(Vector3(5,4.5,5));view_camera.look_at(raft.to_global(Vector3(2,1.8,0)))
			await shot("roof-and-red-ocean")
		player.call("_cancel_edit");await frames()
		check(pot.global_position.is_equal_approx(roof_position) and player._grid_occupancy.get(Vector2i(1,0))==deck,"Cancel restores the pot and leaves its foundation grid intact")
		check(pot.plant_seed("Onion"),"Onion also plants in a pot on the roof")
		player.build_mode=false;player.aim_collider=pot;player.aim_valid=true;player.aim_distance=2
		pot._plant.call("_update_interaction",0.0)
		check(pot._plant._progress_ui.visible and pot._plant._prompt_label.text.contains("until grown"),"Aiming the roof pot shows onion growing time")
		if preview:
			view_camera.global_position=pot.global_position+Vector3(0.7,0.7,1.0);view_camera.look_at(pot.global_position+Vector3.UP*0.15)
			await shot("roof-pot-countdown")
		player.build_mode=true
		pot.queue_free();await frames()
	# The actual enabled roof panels, including a real stair opening, support pots.
	var flight:=piece("Stairs",Vector3(2,0.25,-1));await frames(10);roof.call("refresh");await frames()
	check(not aim("PlanterPot",Vector3(2,2.8,0),roof).get("valid",false),"Pot rejects a roof stair opening even if a roof node is selected")
	flight.queue_free();await frames(10);roof.call("refresh");await frames()
	check(aim("PlanterPot",Vector3(2,2.8,0),roof).get("valid",false),"Closing the stair opening restores valid roof-top placement")
	player.call("_toggle_build")
	# Every crop uses direct island planting, independent of pots.
	var island:=StaticBody3D.new();island.name="OnionFarmingTestIsland";island.position=Vector3(280,2,0)
	var ground_col:=CollisionShape3D.new();var ground_shape:=BoxShape3D.new();ground_shape.size=Vector3(14,0.2,8)
	ground_col.shape=ground_shape;island.add_child(ground_col);current_scene.add_child(island);island.add_to_group("island");await frames()
	var ground_visual:=MeshInstance3D.new();var ground_mesh:=BoxMesh.new();ground_mesh.size=ground_shape.size
	ground_visual.mesh=ground_mesh;ground_visual.material_override=load("res://scripts/object_materials.gd").make(7,Color(0.65,0.51,0.32));island.add_child(ground_visual)
	for crop_index in 6:
		var crop:String=["Potato","Coconut","Banana","Carrot","Tomato","Onion"][crop_index]
		inventory.call("add",crop,2);player.active_item=crop
		player.aim_valid=true;player.aim_collider=island;player.aim_point=island.to_global(Vector3(-4+crop_index*1.6,0.1,0));player.aim_normal=Vector3.UP;player.aim_distance=2
		var before:int=inventory.call("total",crop)
		check(player.call("_plant_on_ground") and inventory.call("total",crop)==before-1,crop+" plants directly in island soil and spends one produce")
		await frames()
	var onion_bed:Node3D=null
	for bed in get_nodes_in_group("ground_plot"):
		if bed.planted_id=="Onion":onion_bed=bed
	check(onion_bed!=null,"Onion ground crop exists without a pot")
	if onion_bed!=null:
		var onion:Node3D=onion_bed._plant
		onion.set_process(false)
		player.get_node("SurvivalAction").call("stop")
		check(onion._container.find_child("OnionPlantModel",true,false)!=null,"Onion uses the supplied model immediately after planting")
		var bounds:AABB=onion.call("_node_local_aabb",onion._container.get_node("OnionPlantModel"))
		check(absf(bounds.get_center().x)<0.1 and bounds.size.y>0.6 and absf(bounds.end.y-0.7)<0.02,"Onion source display offset is removed and growth model is normalized")
		player.aim_collider=onion_bed;onion.call("_update_interaction",0.0)
		check(onion._progress_ui.visible and onion._prompt_label.text.contains("Onion"),"Aiming onion ground soil displays its growth countdown")
		if preview:
			view_camera.global_position=onion.global_position+Vector3(0.4,0.6,0.8);view_camera.look_at(onion.global_position+Vector3.UP*0.08)
			await shot("sprout-countdown")
		for stage in 3:
			onion.call("_process",85.0)
			check(onion._stage==stage+1 and onion._container.find_child("OnionPlantModel",true,false)!=null,"Onion advances through supplied growth stage %d"%[stage+1])
		var saved:Array=player.call("_serialize_ground_crops")
		check(saved.size()==6,"All six direct crops serialize for a saved game")
		if preview:
			view_camera.global_position=onion.global_position+Vector3(0.65,0.9,1.1);view_camera.look_at(onion.global_position+Vector3.UP*0.3)
			await shot("grown-in-soil")
		var amount_before:int=inventory.call("total","Onion")
		onion.call("_do_dig")
		await create_timer(0.6).timeout
		check(onion._harvesting and onion._container.position.y>0.35,"Onion harvest lifts its golden bulb out of the soil")
		await shot("bulb-harvest")
		await create_timer(1.3).timeout;await frames()
		check(inventory.call("total","Onion")>=amount_before+4 and not is_instance_valid(onion_bed),"Harvest gives edible replantable onions and removes the ground patch")
		for bed in get_nodes_in_group("ground_plot"):bed.queue_free()
		await frames();inventory.loaded_meta["ground_crops"]=saved;player.call("_restore_ground_crops");await frames()
		var restored:Node3D=null
		for bed in get_nodes_in_group("ground_plot"):
			if bed.planted_id=="Onion":restored=bed
		check(restored!=null and restored._plant._stage==3,"Onion ground crop restores at its saved mature stage")
	# Alias, eating, and the real bulb carried in the hand/pickups.
	var count:int=inventory.call("total","Onion")
	inventory.call("add","Onion Seed",2)
	check(inventory.call("total","Onion")==count+2,"Onion Seed aliases the edible onion item")
	player.active_item="Onion";player.call("_update_hand_item")
	check(player._hand_item.get_child_count()>0,"Held onion has a visible bulb model")
	root.get_node("Stats").hunger=20.0;player.aim_valid=false;player.aim_collider=null
	count=inventory.call("total","Onion");player.call("_handle_selected_item_use")
	check(inventory.call("total","Onion")==count-1 and root.get_node("Stats").hunger>20,"USE eats one onion and restores hunger")
	var pickup:Node3D=load("res://scenes/food_pickup.tscn").instantiate();pickup.item_name="Onion";current_scene.add_child(pickup)
	check(pickup.get_node_or_null("PickupModel")!=null,"Onion pickups display the supplied golden bulb instead of a seed packet")
	inventory.loaded_meta.erase("ground_crops")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(25)
	print("PLANTER ONION SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
