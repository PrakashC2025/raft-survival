extends SceneTree
const TERRAIN:=preload("res://scripts/underwater_terrain.gd")
const SAVE:=preload("res://scripts/save_storage.gd")
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var sea: Node3D
var review_camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await process_frame
func settle(point: Vector2) -> void:
	player.global_position=Vector3(point.x,TERRAIN.surface_height(point)+2.0,point.y)
	sea.stream.call("request_position",point)
	for unused in 420:
		await frames(1)
		if sea.stream.call("ready_at",point) and sea.stream._pending.is_empty() and not sea.stream._busy:break
	await frames(3)
func shot(label: String, at: Vector3, target: Vector3) -> void:
	if not preview:return
	review_camera.global_position=at;review_camera.look_at(target)
	player.global_position=at-Vector3.UP
	await frames(12);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/reef-reference-"+str(RenderingServer.get_current_rendering_method())+"-"+label+".png")==OK,"Rendered "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	var clearance_preview := preview and "--clearance-preview" in OS.get_cmdline_user_args()
	create_timer(260 if clearance_preview else 120).timeout.connect(func():push_error("FAIL: underwater reference timeout");quit(1))
	var settings:=root.get_node("GameSettings");settings.quality=2
	var inv:=root.get_node("Inventory");inv.call("new_game_reset",true);inv.infinite=false
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player") as CharacterBody3D;sea=current_scene.get_node("UnderwaterWorld")
	for unused in 3000:
		await frames(1)
		if sea.prepared and player.restoration_complete and current_scene.get_node("SpringIsle").prepared:break
	check(sea.prepared and player.restoration_complete,"Existing world and saves finish preparation")
	if not sea.prepared:quit(1);return
	player.set_process(false);player.set_physics_process(false);player.set_process_unhandled_input(false)
	player.get_node("RopeSystem").set_physics_process(false);player.get_node("RainSystem").call("stop_rain")
	player.get_node("SurvivalProgression").set_process(false);player.get_node("SurvivalAction").set_process(false)
	player.get_node("CanvasLayer").hide();player.camera.top_level=true
	sea.set_process(false);sea._hands.hide();player.camera.get_node("HandPivot").hide()
	player.get_node("SurvivalAction").call("stop")
	if preview:
		review_camera=Camera3D.new();review_camera.fov=68;current_scene.add_child(review_camera);review_camera.current=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;player.is_swimming=true
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause");clock.current_time=12;clock.call("_update_celestial_coords");clock.get_node("Timer").emit_signal("timeout")
	current_scene.get_node("OceanAtmosphere").call("_process",1)
	sea.call("_update_light",1.0)
	check(TERRAIN.surface_height(Vector2(140,80))<=-TERRAIN.MIN_SEABED_DEPTH and TERRAIN.surface_height(Vector2(140,80))> -24,"Reef keeps clear water above its plants and rocks")
	check(TERRAIN.surface_height(Vector2(-100,-180))< -10 and TERRAIN.surface_height(Vector2(-100,-180))> -30,"Harbour occupies the middle shelf")
	check(TERRAIN.surface_height(Vector2(-650,-480))< -30 and TERRAIN.surface_height(Vector2(-650,-480))> -60,"City lies in the deep zone")
	check(TERRAIN.surface_height(Vector2(-370,-500))< -60,"The trench reaches the very deep zone")
	await settle(Vector2(145,95))
	check(sea.stream.chunks.size()<=25 and sea.stream._pending.is_empty(),"Medium limits active terrain to 25 tiles")
	var highest_ground := -INF
	for x in range(-2100, 2101, 24):
		for z in range(-2100, 2101, 24): highest_ground=maxf(highest_ground,TERRAIN.surface_height(Vector2(x,z)))
	check(highest_ground<=-14.0,"All generated ocean terrain stays at least fourteen metres underwater")
	var highest_solid := -INF
	for draw in sea.find_children("*","MeshInstance3D",true,false):
		if str(draw.name).begins_with("FilteredSunlight"):continue
		if draw.mesh!=null:highest_solid=maxf(highest_solid,(draw.global_transform*draw.mesh.get_aabb()).end.y)
	check(highest_solid< -3.0,"Reef rocks, arch, ruins and fauna stay below the wave troughs")
	if preview:
		var highest_plant := -INF
		for draw in sea.find_children("*","MultiMeshInstance3D",true,false):
			var batch: MultiMesh=draw.multimesh
			var count: int=batch.instance_count if batch.visible_instance_count<0 else batch.visible_instance_count
			for index in count:
				var bounds: AABB=(draw.global_transform*batch.get_instance_transform(index))*batch.mesh.get_aabb()
				highest_plant=maxf(highest_plant,bounds.end.y)
		check(highest_plant< -3.0,"Actual instanced kelp, coral and fish remain safely submerged")
	var point:=Vector2(145,95);var level:=TERRAIN.surface_height(point)
	var floor_node:=sea.get_node("CollectibleSeabed")
	var hit:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,level+1,point.y),Vector3(point.x,level-2,point.y),1))
	check(not hit.is_empty() and hit.collider==floor_node and absf(hit.position.y-level)<.01,"Detailed terrain collision matches the rendered sand")
	var arch_at:=Vector2(130,82);var passage_height:=TERRAIN.surface_height(arch_at)+2.0
	var arch_ray:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(130,passage_height,77),Vector3(130,passage_height,87),1))
	check(arch_ray.is_empty(),"Natural reef arch has a real open swimming corridor")
	check(sea.get_node("ReefRockPassages").find_children("*","StaticBody3D",true,false).size()>=12,"Large rock formations use simple static collision")
	var tile: Node3D=sea.stream.chunks[Vector2i(3,1)]
	for kind in ["Grass","Kelp","Sponge","BranchCoral","FanCoral","BrainCoral","Urchin","Shell","Rock"]:
		check(tile.get_node(kind+"Batch") is MultiMeshInstance3D,"Instanced "+kind+" uses shared geometry")
	check(sea._ground_material.get_shader_parameter("surface_arm") is Texture2D and sea._ruin_material.get_shader_parameter("surface_normal") is Texture2D,"Sand and rocks retain licensed roughness and normal maps")
	check(sea._shafts.size()==4,"Sunbeams have a fixed transparent-plane budget")
	check(sea._accents.size()==7 and sea._accents[-1].multimesh.instance_count==90,"Coral gardens and small pebbles have fixed instancing budgets")
	var shoal: Node3D=sea.get_node("FishSchoolReefGarden")
	# Dummy rendering does not retain instance colour buffers; real renderers do.
	if preview:check(shoal._parts[0].multimesh.get_instance_color(0)!=shoal._parts[0].multimesh.get_instance_color(1),"Fish pools include distinct species pigments")
	player.global_position=shoal.global_position+shoal._centre+Vector3.RIGHT
	shoal.call("_process",.11)
	check(shoal._flee and shoal._target.is_finite(),"Nearby fish steer away from the player")
	var start_heading: Vector3=shoal._forward
	shoal.call("_process",.016)
	check(start_heading.distance_to(shoal._forward)<.1,"School headings change gradually between steering ticks")
	if clearance_preview:
		# Source checks retain the full save/pickup/quality suite. This native
		# pass only renders the changed reef and checks the real instance bounds.
		var reef_floor := TERRAIN.surface_height(Vector2(144,102))
		await shot("shallow",Vector3(144,reef_floor+2.1,102),Vector3(136,TERRAIN.surface_height(Vector2(136,80))+2.5,80))
		await shot("open-ocean",Vector3(145,2.5,100),Vector3(140,1,50))
		current_scene.queue_free();await frames(5)
		print("UNDERWATER CLEARANCE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
		return
	var loot: Node3D=tile.get_node("Gatherable");var id: String=loot.resource_id
	player.global_position=loot.global_position+Vector3.UP*.6
	var reward: String=loot.rewards.keys()[0];var before: int=inv.call("total",reward)
	loot.call("interact_survival",player)
	check(loot.taken and inv.call("total",reward)==before+int(loot.rewards[reward]),"Underwater salvage grants its displayed reward")
	loot.call("interact_survival",player);check(inv.call("total",reward)==before+int(loot.rewards[reward]),"Collected salvage cannot be taken twice")
	var saved: Dictionary=sea.call("save_resources")
	await settle(Vector2(-100,-180));await settle(Vector2(145,95))
	check(sea.stream.chunks[Vector2i(3,1)].get_node("Gatherable").taken and saved[id],"Collected salvage survives tile unloading and revisiting")
	var bag_copy: Array=inv.slots.duplicate(true)
	for index in inv.SLOT_COUNT:inv.slots[index]={"item":"Stone","count":inv.MAX_STACK}
	var full_loot: Node3D=sea.stream.chunks[Vector2i(2,1)].get_node("Gatherable")
	player.global_position=full_loot.global_position+Vector3.UP*.6
	full_loot.call("interact_survival",player)
	check(not full_loot.taken and not sea.resource_state.has(full_loot.resource_id),"A full bag retains the seabed pickup")
	inv.slots=bag_copy;inv.call("_recompute")
	var legacy: Dictionary={"version":1,"slots":[]}
	check(SAVE._valid_save(legacy),"Existing saves remain valid without new reef data")
	legacy["underwater_resources"]=saved
	check(SAVE.write("user://reef-roundtrip.save",legacy) and SAVE.read("user://reef-roundtrip.save").underwater_resources[id],"Encrypted saves round-trip collected reef resources")
	legacy["underwater_resources"]={"bad":12};check(not SAVE._valid_save(legacy),"Malformed collected-resource state is rejected")
	settings.quality=1;sea.stream.call("_quality_changed");await settle(Vector2(145,95))
	check(sea.stream.chunks.size()<=9,"Low limits terrain to nine tiles")
	settings.quality=4;sea.stream.call("_quality_changed");await settle(Vector2(145,95))
	check(sea.stream.chunks.size()<=49 and sea.stream.chunks.size()>25,"Ultra adds detail within a 49-tile cap")
	settings.quality=2;sea.stream.call("_quality_changed");await settle(Vector2(145,95))
	var floor_y:=TERRAIN.surface_height(Vector2(144,102))
	player.is_swimming=true;player.active_item="";player.cam_mode=0;player.call("_apply_camera_mode")
	player.camera.get_node("HandPivot").hide()
	await shot("shallow",Vector3(144,floor_y+2.1,102),Vector3(136,TERRAIN.surface_height(Vector2(136,80))+2.5,80))
	await shot("arch",Vector3(130,passage_height+.4,94),Vector3(130,passage_height+1.3,81))
	await shot("surface",Vector3(143,-4,95),Vector3(145,0,88))
	await shot("coral",Vector3(155,TERRAIN.surface_height(Vector2(155,105))+.85,105),Vector3(150,TERRAIN.surface_height(Vector2(150,96))+.35,96))
	await shot("open-ocean",Vector3(145,2.5,100),Vector3(140,1,50))
	await settle(Vector2(-650,-480));floor_y=TERRAIN.surface_height(Vector2(-650,-455))
	await shot("deep",Vector3(-650,floor_y+4,-455),Vector3(-650,TERRAIN.surface_height(Vector2(-650,-480))+3,-480))
	if preview:player.camera.make_current()
	var ocean:=current_scene.get_node("Ocean");player.camera.global_position=Vector3(145,-3,95);ocean.call("_update_underwater",.1)
	var blend: float=ocean._dive_blend;player.camera.global_position=Vector3(145,4,95);ocean.call("_update_underwater",.02)
	check(ocean._dive_blend>0 and ocean._dive_blend<blend,"Surfacing fades the water tint smoothly")
	current_scene.queue_free();await frames(5)
	print("UNDERWATER REFERENCE SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
