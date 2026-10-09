extends SceneTree
var checks := 0
var failures := 0
var player: Node3D
var inventory: Node
var garden: Node3D
func _initialize() -> void:
	create_timer(80).timeout.connect(func():push_error("FAIL: wild plant timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func aim(index: int, body: Node=null) -> void:
	player.aim_collider = garden.targets[index] if body==null else body
	player.aim_valid=true
	player.aim_distance=2.0
	player.aim_normal=Vector3.UP
	player.aim_point=garden.to_global(garden.records[index].at)
	garden._cooldown=0.0
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	inventory=root.get_node("Inventory")
	inventory.call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player=get_first_node_in_group("player")
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	get_first_node_in_group("raft").set_physics_process(false)
	for unused in 1800:
		await process_frame
		if get_nodes_in_group("island_wild_plants").size()==4:
			var ready := true
			for field in get_nodes_in_group("island_wild_plants"):ready=ready and field.prepared
			if ready:break
	check(get_nodes_in_group("island_wild_plants").size()==4,"All four islands receive the owner plant kit")
	if get_nodes_in_group("island_wild_plants").size()!=4:
		print("ISLAND WILD PLANTS SMOKE: %d checks, %d failures" % [checks,failures]);quit(1);return
	for field in get_nodes_in_group("island_wild_plants"):
		field.set_process(false)
		print("WILD FIELD ",field.island_node().name," plants=",field.records.size())
		check(field.prepared and field.records.size()>=20 and field.records.size()<=64,str(field.island_node().name)+" finishes a bounded interactive field")
		check(field.batches.size()==8 and field.targets.size()==field.records.size(),"Every wild plant has one lifecycle and shared visual batch")
		var valid := true
		for entry in field.records:
			valid=valid and field.to_global(entry.at).y>=0.42
		check(valid,"Wild roots remain on dry island ground")
		check(field.batches[0].multimesh.mesh==field.meshes[0] and field.batches[5].multimesh.mesh==field.meshes[5],"Trees and flowers reuse the prepared kit resources")
	garden=current_scene.get_node("Island/IslandLandscape/WildPlants")
	for kind in 8:
		var mesh: Mesh=garden.meshes[kind]
		check(mesh!=null and mesh.get_aabb().position.y>=-0.001,"Kit variant %d has grounded normalized roots"%kind)
		if kind==5:
			var petals:=mesh.surface_get_material(0) as ShaderMaterial
			check(petals!=null and petals.shader==load("res://shaders/flower_petals.gdshader"),"Flowers use curved opaque petals and a shared breeze shader")
		else:
			var leaf := mesh.surface_get_material(0) as BaseMaterial3D
			check(leaf!=null and leaf.albedo_texture!=null and leaf.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,"Kit variant %d has textured cutout leaves"%kind)
	check(garden.meshes[0].surface_get_material(0)==garden.meshes[4].surface_get_material(0),"Kit shares one leaf atlas across trees and small plants")
	var small := 10
	aim(small)
	check(player.interaction_caption()=="GATHER PLANT" and player.can_interact_now(),"Use button offers gathering on a small wild plant")
	check(not player._is_sand_surface_hit(),"A wild plant target cannot accidentally gather soil or spend a seed")
	check(garden.targets[small].collision_layer==2,"Small plants remain walkable pickup targets")
	var rope_before: int=inventory.call("total","Rope")
	check(garden.collect(small,player),"Small plants can be gathered")
	check(int(inventory.call("total","Rope"))==rope_before+1 and garden.records[small].growth==0.0,"Gathering delivers fiber as rope and clears its visual")
	check(garden.targets[small].collision_layer==0 and garden.records[small].wait==180.0,"Cleared small plants release their target and wait three game minutes")
	var cleared_at: Vector3=garden.to_global(garden.records[small].at)
	# Clear the complete crop footprint; planting must never erase a nearby tree for free.
	for index in garden.records.size():
		var entry: Dictionary=garden.records[index]
		if entry.growth<=0 or garden._flat_distance(garden.to_global(entry.at),cleared_at)>=(2.0 if entry.kind<2 else 1.15):continue
		for unused in (4 if entry.kind<2 else 1):aim(index);garden.collect(index,player)
	aim(small)
	check(not garden.blocks_crop(player.aim_point),"Cleared ground is available for farming")
	var mask: Image=garden._mask_image
	var at: Vector3=garden.records[small].at
	var uv: Vector2 = Vector2(at.x,at.z)/(garden.radius+1.0)*0.5+Vector2.ONE*0.5
	check(mask.get_pixel(clampi(int(uv.x*64),0,63),clampi(int(uv.y*64),0,63)).r>0.5,"Clearing removes surrounding decorative grass through the ground mask")
	var saved: Dictionary=garden.save_state()
	check(saved.records[small].growth==0.0 and saved.records[small].wait==180.0,"Save state preserves cleared ground and remaining regrowth delay")
	var probe: Node = load("res://scripts/island_wild_plants.gd").new()
	probe.radius=garden.radius
	probe.call("_restore_records",saved.records)
	check(probe.records.size()==garden.records.size() and probe.records[small].wait==180.0,"Wild state restores every plant without instantly refilling clearings")
	probe.free()
	garden.advance(179.0)
	check(garden.records[small].growth==0.0 and garden.records[small].wait==1.0,"Empty ground waits before regrowing")
	garden.advance(1.0)
	check(garden.records[small].growth>0.0 and garden.records[small].growth<0.1,"A random small wild seedling appears after the delay")
	garden.advance(75.0)
	check(garden.records[small].growth==1.0,"Wild seedlings grow gradually to full size")
	aim(small);garden.collect(small,player)
	var plot: Node3D = load("res://scripts/ground_plot.gd").new()
	plot.position=garden.records[small].at
	garden.island_node().add_child(plot)
	check(plot.plant_seed("Potato"),"The cleared location accepts a cultivated potato")
	garden.advance(900.0)
	check(garden.records[small].growth==0.0 and garden.records[small].wait==180.0,"A planted crop suppresses wild plants for its entire growing time")
	var crop=plot._plant
	var crop_before: float=crop._stage_timer
	crop.call("_process",12.0)
	check(crop._stage_timer>crop_before or crop._stage>0,"The player's crop keeps growing while wild plants wait")
	plot.clear_plant();await frames()
	garden.advance(181.0)
	check(garden.records[small].growth>0.0,"Wild plants can return after harvest leaves the location empty")
	# Nearby trees were also held back by that crop's clearance radius.
	garden.advance(360.0)
	aim(0)
	check(player.interaction_caption().begins_with("CHOP") and garden.targets[0].collision_layer==3,"Trees offer chopping and have a matching solid trunk")
	var wood_before: int=inventory.call("total","Wood")
	for hit in 3:aim(0);garden.collect(0,player)
	check(garden.records[0].health==1 and garden.records[0].growth==1.0,"Chopping takes four hits without awarding wood early")
	var slots_backup: Array=inventory.slots.duplicate(true)
	inventory.slots.clear();inventory.call("_ensure_slots")
	for slot in 30:inventory.call("place_at",slot,"Rope",2000)
	aim(0)
	check(not garden.collect(0,player) and garden.records[0].health==1 and garden.records[0].growth==1.0,"A full bag preserves the tree on the final hit")
	inventory.slots=slots_backup;inventory.call("_recompute")
	aim(0);garden.collect(0,player)
	check(garden.records[0].growth==0.0 and int(inventory.call("total","Wood"))==wood_before+4,"Final chopping hit clears the trunk and delivers four wood atomically")
	check(garden.targets[0].collision_layer==0 and garden.records[0].wait==360.0,"A chopped tree leaves walkable soil and a six-minute return delay")
	garden.advance(361.0)
	check(garden.records[0].growth>0.0 and garden.records[0].growth<0.1,"Wild trees return as small seedlings")
	garden.advance(180.0)
	check(garden.records[0].growth==1.0,"Wild trees reach full size over three game minutes")
	var palm_index := -1
	for index in garden.records.size():
		if str(garden.records[index].get("external","")).begins_with("Palm"):palm_index=index;break
	check(palm_index>=0,"Existing island palms are also registered for chopping")
	if palm_index>=0:
		var palm: Node3D=garden._original_tree(garden.records[palm_index])
		var body: Node=palm.find_children("*","StaticBody3D",true,false)[0]
		check(body.has_method("interact_survival") and palm.visible,"Original palm keeps its visual and matching imported trunk collision")
		for hit in 4:aim(palm_index,body);garden.collect(palm_index,player)
		check(not palm.visible and body.collision_layer==0,"Chopping an existing palm clears both its visual and original collision")
		garden.advance(361.0)
		check(not palm.visible and garden.records[palm_index].growth>0.0 and garden.targets[palm_index].collision_layer==3,"A cleared palm location returns as a random kit tree without an overlapping old trunk")
	check(player.call("_write_save","quick"),"Wild plant state writes through the normal isolated save flow")
	check(inventory.call("load_game","quick") and inventory.loaded_meta.get("wild_plants",{}).size()==4,"All four islands survive a real save and load")
	var performance:=get_first_node_in_group("mobile_performance")
	performance.set("_mobile",true)
	root.get_node("GameSettings").call("update_setting","quality",1)
	var visible := true
	for batch in garden.batches:visible=visible and batch.multimesh.visible_instance_count==batch.multimesh.instance_count and batch.visibility_range_end==55.0
	check(visible,"Mobile Battery Saver never leaves invisible interactive trees")
	Input.action_release("interact")
	if OS.get_cmdline_user_args().has("--preview"):
		await _preview()
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(25)
	print("ISLAND WILD PLANTS SMOKE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)

func _preview() -> void:
	root.get_node("GameSettings").call("update_setting","quality",2)
	var camera:=Camera3D.new()
	current_scene.add_child(camera)
	camera.global_position=garden.to_global(Vector3(1.5,5.4,9.5))
	camera.look_at(garden.to_global(Vector3(-2,2.4,-3)))
	camera.current=true
	player.visible=false
	player.get_node("CanvasLayer").visible=false
	for unused in 90:await process_frame
	var image:=root.get_texture().get_image()
	image.save_png("C:/GodotProjects/raft-survival/build/island-wild-plants-preview.png")
