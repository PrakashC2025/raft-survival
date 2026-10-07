extends SceneTree
var checks:=0
var failures:=0
var player: Node3D
var raft: Node3D
var built: Node3D
var inventory: Node
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func piece(kind: String,pos: Vector3) -> Node3D:
	var result: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name=kind+"_Action_%d"%result.get_instance_id();result.position=pos;built.add_child(result)
	return result
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	inventory=root.get_node("Inventory");inventory.call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	await frames(100)
	inventory.infinite=false
	check(not inventory.call("can_afford","PlanterPot"),"Wood alone cannot build a soil-less planter")
	inventory.call("add","Soil",2)
	var wood: int=inventory.call("total","Wood")
	check(inventory.call("craft","PlanterPot") and int(inventory.call("total","Soil"))==0 and int(inventory.call("total","Wood"))==wood-4,"Pot atomically spends wood and two soil")
	check(not inventory.call("can_afford","SandFilter"),"Filter requires both sand and sponge, even with testing salvage")
	inventory.call("add","Sand",4);inventory.call("add","Sponge",2)
	var plastic: int=inventory.call("total","Plastic")
	inventory.call("remove","Plastic",plastic)
	var metal: int=inventory.call("total","Metal")
	check(inventory.call("recipe_cost","SandFilter").has("Metal"),"Filter accepts metal when no plastic container is available")
	check(inventory.call("craft","SandFilter") and int(inventory.call("total","Metal"))==metal-2 and int(inventory.call("total","Sand"))==0 and int(inventory.call("total","Sponge"))==0,"Alternative container and filter fill are spent together")
	inventory.call("add","Plastic",plastic)
	var pot:=piece("PlanterPot",Vector3(0,.325,0))
	var soil:=pot.get_node("LivingSoil") as MeshInstance3D
	check(soil.mesh.get_aabb().size.y>0.015,"Soil has real raised clods rather than a flat box")
	check(soil.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()>1700,"Full seedbed stays indexed alongside raised clods")
	pot.call("_process",1.0)
	check(soil.material_override is ShaderMaterial and float((soil.material_override as ShaderMaterial).get_shader_parameter("moisture"))>0,"Soil material responds to moisture")
	pot.queue_free();await frames()
	var filter:=piece("SandFilter",Vector3(0,.90,0))
	filter.set_process(false)
	var rain:=player.get_node("RainSystem");rain.call("start_rain",120)
	await frames()
	filter.call("advance",20.0)
	check(filter.water==1,"Exposed sand filter produces one rainwater in twenty active seconds")
	var saved: Dictionary=filter.call("save_survival_state")
	var roof:=piece("Roof",Vector3(0,2.725,0));await frames()
	filter.call("advance",40.0)
	check(filter.water==1,"A roof stops rain entering the sand filter")
	filter.call("restore_survival_state",saved)
	check(filter.water==1,"Filter water survives save restoration")
	inventory.slots.clear();inventory.call("_ensure_slots")
	for index in 30:inventory.call("place_at",index,"Wood",2000)
	filter.call("interact_survival",player)
	check(filter.water==1,"A full bag leaves filtered water in its container")
	inventory.call("remove","Wood",2000)
	filter.call("interact_survival",player)
	check(filter.water==0 and int(inventory.call("total","Water"))==1,"Filter collection delivers stored water exactly once")
	filter.queue_free();roof.queue_free();await frames()
	inventory.call("new_game_reset",true)
	inventory.call("grant_testing_resources")
	player.global_position=raft.to_global(Vector3(0,1.05,0))
	player.build_mode=true;player.selected_piece_index=0;player.call("_spawn_ghost")
	player.aim_valid=true;player.aim_collider=raft;player.aim_point=raft.to_global(Vector3(1,.15,0));player.aim_normal=Vector3.RIGHT;player.aim_distance=2
	player.call("_update_build_preview")
	wood=inventory.call("total","Wood")
	var count:=built.get_child_count()
	player.call("_begin_build_action")
	check(not player._pending_build.is_empty() and int(inventory.call("total","Wood"))==wood,"Place starts visible assembly without spending early")
	player.call("_tick_build_action",.4)
	check(built.get_child_count()==count,"Build waits for assembly instead of silently appearing")
	player.call("_tick_build_action",.4)
	check(built.get_child_count()==count+1 and int(inventory.call("total","Wood"))==wood-5,"Build completion revalidates and spends once")
	var serialized: Array=player.call("_serialize_built_pieces")
	var spent_saved := false
	for entry in serialized:
		if entry.t=="Foundation" and entry.get("cost",{}).get("Wood",0)==5:spent_saved=true
	check(spent_saved,"Built pieces save their actual spent recipe for compatible refunds")
	player.aim_point=raft.to_global(Vector3(-1,.15,0));player.call("_update_build_preview")
	player.call("_begin_build_action");wood=inventory.call("total","Wood")
	player.build_mode=false;player.call("_tick_build_action",1.0)
	check(player._pending_build.is_empty() and int(inventory.call("total","Wood"))==wood,"Exiting build mode cancels assembly without loss")
	var action:=player.get_node("SurvivalAction")
	action.set_process(false)
	player.cam_mode=1;player.call("_apply_camera_mode")
	var signatures:=[]
	for kind in ["cast","reel","chop","harvest","grab","scoop","plant","water","build","eat","drink","bandage","strike"]:
		player.call("play_action",kind,1.0,raft.global_position)
		action.elapsed=.5
		var pose: Dictionary=action.call("sample_pose")
		signatures.append(pose.right)
		check(pose.right.is_finite() and pose.left.is_finite(),"Reachable finite key poses: "+kind)
	check(signatures[0]!=signatures[1] and signatures[2]!=signatures[3] and signatures[4]!=signatures[5],"Cast/reel, chop/pull and grab/dig use different hand trajectories")
	await frames()
	var rig:=player.get_node("Body").find_child("Skeleton3D",true,false) as Skeleton3D
	if rig==null:
		var rigs: Array[Node]=player.get_node("Body").find_children("*","Skeleton3D",true,false);rig=rigs[0]
	check(rig.get_node_or_null("HeldArmPose")!=null,"Actions modify the actual animated skeleton")
	action.call("stop")
	player.active_item="Fishing Rod";player.call("_update_hand_item");action.call("_process",0.0)
	check(is_instance_valid(action._held) and action._held.find_child("FishingTip",true,false)!=null,"Third-person fishing rod follows the hand with a real line tip")
	check(action._held.find_children("HumanHand*","Node3D",true,false).is_empty(),"Third-person held item never duplicates the first-person hand")
	var duplicate_hand := false
	for visual in action._held.get_children():
		if visual.has_meta("first_person_hand"):duplicate_hand=true
	check(not duplicate_hand,"Deferred node renaming cannot copy a first-person hand into third person")
	player._fishing_time_remaining=5.0
	var equipment:=player.get_node("SurvivalEquipment")
	equipment.call("show_cast",raft.to_global(Vector3(0,0,-8)))
	equipment.call("_update_cast")
	check((equipment._bobber as Node3D).global_position.distance_to(raft.to_global(Vector3(0,0,-8)))>2,"Fishing float travels along a cast arc instead of teleporting")
	player._fishing_time_remaining=0.6;equipment.call("_update_cast")
	check(is_instance_valid(equipment._catch_visual) and equipment._catch_visual.visible,"Reeling shows a fish rising towards the rod")
	player._fishing_time_remaining=0
	# Dense water probes around an expanded, moving raft over several swells.
	for z in range(1,4):
		for x in range(-2,3):piece("Foundation",Vector3(x*2,0,z*2))
	await frames()
	raft.call("_refresh_deck_samples")
	var ocean:=current_scene.get_node("Ocean")
	ocean.set_process(false)
	var min_clearance:=INF
	var max_tilt:=0.0
	var low_y:=INF
	var high_y:=-INF
	for time in range(0,80,2):
		ocean._time=float(time);raft.rotation.y=float(time)*0.03
		raft.set_physics_process(true)
		await frames(2)
		raft.set_physics_process(false)
		max_tilt=maxf(max_tilt,maxf(absf(raft.rotation.x),absf(raft.rotation.z)))
		low_y=minf(low_y,raft.global_position.y);high_y=maxf(high_y,raft.global_position.y)
		var centres: Array[Vector3]=[Vector3.ZERO]
		for child in built.get_children():
			if child is Node3D and str(child.name).begins_with("Foundation"):centres.append(child.position)
		for center in centres:
			for z in range(-4,5):
				for x in range(-4,5):
					var at: Vector3=raft.to_global(center+Vector3(x*.25,.15,z*.25))
					min_clearance=minf(min_clearance,at.y-float(ocean.call("get_height",at)))
	print("Minimum deck clearance: ",min_clearance)
	check(min_clearance>0.12,"Expanded rotating raft keeps its deck above dense wave-crest probes")
	check(raft._deck_samples.size()<200,"Deck buoyancy deduplicates shared samples for mobile")
	check(max_tilt>0.0005 and max_tilt<=0.029,"Real raft collision body rocks gently with the swell")
	check(high_y-low_y>0.05,"Raft visibly bobs instead of staying at a fixed height")
	var saved_yaw: float=raft.rotation.y
	player.build_mode=true;raft.set_physics_process(true);await frames(2);raft.set_physics_process(false)
	check(absf(raft.rotation.x)<0.0001 and absf(raft.rotation.z)<0.0001 and absf(raft.rotation.y-saved_yaw)<0.001,"Construction levels pitch and roll while preserving the raft heading")
	player.build_mode=false
	ocean.call("_process",0.0)
	check(absf(float(ocean.get_active_material(0).get_shader_parameter("wave_time"))-ocean._time)<0.0001,"Rendered water and raft buoyancy use the exact same wave clock")
	player.global_position=raft.to_global(Vector3(0,1.07,0));player.velocity=Vector3.ZERO;player.is_swimming=false
	raft.set_physics_process(true);player.set_physics_process(true);await frames(30)
	check(player.is_on_floor() and not player.is_swimming,"Player can stand safely on the physically rocking raft")
	var course_start: Vector3=raft.global_position
	raft.upgrade_tier=1;raft.call("set_course",course_start+Vector3(100,0,100))
	await frames(12)
	check(raft.global_position.x-course_start.x>0.15 and raft.global_position.z-course_start.z>0.15,"Combined raft transform preserves navigation on both axes")
	raft.call("clear_course");raft.set_physics_process(false);player.set_physics_process(false)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(30)
	print("ACTION FARMING SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
