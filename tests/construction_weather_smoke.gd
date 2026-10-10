extends SceneTree
var checks := 0
var failures := 0
var player: Node3D
var raft: Node3D
var built: Node3D
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures += 1; push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count: await physics_frame
func fixture(kind: String,pos: Vector3,yaw: float=0.0) -> Node3D:
	var piece: Node3D = player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	piece.name = "%s_Check_%d"%[kind,piece.get_instance_id()]
	piece.transform = Transform3D(Basis(Vector3.UP,yaw),pos)
	built.add_child(piece)
	piece.add_to_group("build_surface")
	if kind=="Foundation": player.call("_grid_register",Vector2i(roundi(pos.x/2),roundi(pos.z/2)),piece)
	return piece
func aim(kind: String,point: Vector3,body: Node3D) -> Dictionary:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_point=raft.to_global(point)
	player.aim_collider=body
	player.aim_valid=true
	player.aim_normal=Vector3.UP
	player.camera.global_position=player.aim_point+Vector3(0,3,3)
	player.camera.look_at(player.aim_point)
	player.call("_update_build_preview")
	return player.call("_resolve_placement",kind,player.aim_point)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.get_node("Inventory").call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player=get_first_node_in_group("player"); raft=get_first_node_in_group("raft"); built=raft.get_node("BuiltPieces")
	player.set_process(false); player.set_physics_process(false); raft.set_physics_process(false)
	root.get_node("Stats").enabled=false
	await frames(100)
	for x in range(1,5):
		for z in range(1,5): fixture("Foundation",Vector3(x*2,0,z*2))
	await frames()
	var deck: Node3D=player._grid_occupancy[Vector2i(2,2)]
	for point in [Vector3(4.7,0.15,4.98),Vector3(3.2,0.15,3.02),Vector3(4.98,0.15,3.3),Vector3(3.02,0.15,4.7),Vector3(4,0.15,4)]:
		var result:=aim("Wall",point,deck)
		check(result.get("valid",false),"Wall snaps to supported edge at "+str(point))
		if result.has("transform"):
			var local: Vector3=raft.to_local(result.transform.origin)
			check((is_equal_approx(local.x,4) and absf(absf(local.z-4)-1)<0.01) or (is_equal_approx(local.z,4) and absf(absf(local.x-4)-1)<0.01),"Wall occupies an exact full-width deck edge")
	player.build_rotation=PI/2
	var rotated:=aim("Wall",Vector3(4.98,0.15,4.7),deck)
	check(rotated.get("valid",false) and absf((rotated.transform.basis as Basis).x.z)>0.99,"Rotate cannot turn an edge wall across the foundation")
	player.build_rotation=0
	var stair:=aim("Stairs",Vector3(4,0.15,4),deck)
	check(stair.get("valid",false),"Stairs get a green preview on a deck without a special socket")
	if stair.get("valid",false):
		var local: Vector3=raft.to_local(stair.transform.origin)
		check(local.distance_to(Vector3(4,0.25,3))<0.001,"Stair foot is centred at the foundation's entry edge")
		check(absf((raft.to_local(stair.transform*Vector3(0,2.55,2.9))).y-2.8)<0.001,"Landing meets the next roof/deck height exactly")
		var wood: int=root.get_node("Inventory").call("total","Wood")
		player.call("_try_build"); await frames()
		var placed:=built.find_child("Stairs_*",false,false) as Node3D
		check(placed!=null and root.get_node("Inventory").call("total","Wood")==wood-6,"Confirm places actual stairs and charges six wood")
		if placed!=null: placed.queue_free(); await frames()
	player.build_rotation=PI/2
	var turned:=aim("Stairs",Vector3(4,0.15,4),deck)
	check(turned.get("valid",false) and raft.to_local(turned.transform.origin).distance_to(Vector3(3,0.25,4))<0.001,"Rotated stair foot stays centred on its deck edge")
	var obstacle:=fixture("Wall",Vector3(4,1.4,4),PI/2)
	await frames()
	check(not aim("Stairs",Vector3(4,0.15,4),deck).get("valid",false),"Stair placement rejects a wall obstructing the real ramp")
	obstacle.queue_free(); await frames()
	player.build_rotation=0
	var wall:=fixture("Wall",Vector3(4,1.4,3))
	await frames()
	var side_wall:=aim("Wall",Vector3(4,1.2,3.1),wall)
	check(side_wall.get("valid",false),"Aiming at a ground wall continues the nearest foundation edge")
	if side_wall.get("valid",false):
		var wall_pos: Vector3=raft.to_local(side_wall.transform.origin)
		check(absf(wall_pos.z-3)<0.001 and absf(absf(wall_pos.x-4)-2)<0.001,"Continuation tiles flush, avoiding thin front/back wall sockets")
	var roof_result:=aim("Roof",Vector3(4,0.15,4),deck)
	check(roof_result.get("valid",false) and roof_result.has("roof_plan"),"One wall automatically supports a whole roof tile over the aimed deck")
	if roof_result.get("valid",false):
		check(raft.to_local(roof_result.transform.origin).distance_to(Vector3(4,2.725,4))<0.001,"Automatic roof is centred over its foundation")
		var previous_position:=player.global_position
		player.global_position=raft.to_global(Vector3(4,1.1,4))
		player.aim_point=raft.to_global(Vector3(400,90,400))
		player.aim_valid=false;player.aim_collider=null
		player.call("_begin_build_action")
		check(not player._pending_build.is_empty(),"Green fitted ceiling starts assembly even with a sky ray")
		player.call("_tick_build_action",.8);await frames()
		player.global_position=previous_position
	var roof:=built.find_child("Roof_*",false,false) as Node3D
	check(roof!=null,"Automatic roof confirmation places the ceiling")
	if roof!=null:
		check(not roof.get_node("MeshInstance3D").visible and roof.get_node("TimberDetails").visible,"Roof renders only its finished timbers, keeping the hidden solver box invisible")
		var stable:=roof.transform
		for turn in 20:
			raft.rotation=Vector3(sin(turn)*.02,turn*.04,cos(turn)*.02)
			roof.call("refresh",true)
			check(roof.transform.is_equal_approx(stable) and not roof.get_node("MeshInstance3D").visible,"Roof stays fixed to its grid during raft motion")
		raft.rotation=Vector3.ZERO
		check(not aim("Roof",Vector3(4,2.725,4),roof).get("valid",false),"An occupied ceiling rejects a second overlapping roof")
		wall.get_node("CollisionShape3D").disabled=true
		await frames()
		check(aim("Stairs",Vector3(4,0.15,4),deck).get("valid",false),"Stairs can cut their walking corridor into an existing ceiling")
		wall.get_node("CollisionShape3D").disabled=false
		var flight:=fixture("Stairs",Vector3(6,0.25,3))
		var opening: Dictionary=player.SMART_ROOF.plan(raft,raft.to_global(Vector3(6,0.15,4)))
		check(opening.get("stair_opening",false),"Automatic roofing preserves an opening above an existing stair flight")
		flight.queue_free();await frames()
		var extension:=aim("Roof",Vector3(4.95,2.8,4),roof)
		check(extension.get("valid",false) and raft.to_local(extension.transform.origin).distance_to(Vector3(6,2.725,4))<0.001,"Aiming near a roof edge automatically previews the neighbouring deck tile")
	var window:=fixture("Window",Vector3(8,1.4,7))
	window.call("restore_survival_state",{"open":false})
	check(window.find_child("Hinge",true,false)==null and window.find_children("*","CollisionShape3D",true,false).size()==4,"Legacy window has only its four solid frame pieces")
	var q:=PhysicsRayQueryParameters3D.create(raft.to_global(Vector3(8,1.5,6.5)),raft.to_global(Vector3(8,1.5,7.5)),1)
	await frames()
	check(current_scene.get_world_3d().direct_space_state.intersect_ray(q).is_empty(),"A physical ray passes through the open window gap")
	q=PhysicsRayQueryParameters3D.create(raft.to_global(Vector3(8.7,1.5,6.5)),raft.to_global(Vector3(8.7,1.5,7.5)),1)
	check(not current_scene.get_world_3d().direct_space_state.intersect_ray(q).is_empty(),"Smaller window has solid timber beside its 1.04 metre opening")
	var rain:=player.get_node("RainSystem")
	rain.call("start_rain",120.0)
	rain.call("_refresh_shelter_masks")
	check(not rain.call("rain_visible_at",raft.to_global(Vector3(4,1.5,4))),"Rain is blocked below the actual roof")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(4,3.2,4))),"Rain stays visible above the roof")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(6.5,1.5,4))),"Uncovered deck still receives outdoor rain")
	raft.rotation.y=0.73
	rain.call("_refresh_shelter_masks")
	check(not rain.call("rain_visible_at",raft.to_global(Vector3(4,1.5,4))),"Rain shelter remains aligned when the raft turns")
	raft.rotation.y=0
	if roof!=null: roof.queue_free(); await frames()
	rain.call("_refresh_shelter_masks")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(4,1.5,4))),"Removing a roof exposes its old interior to rain")
	rain.call("stop_rain")
	var ocean:=get_first_node_in_group("ocean")
	check(ocean.mesh is ArrayMesh and ocean.get_node_or_null("FarWater")!=null,"Dense near-water geometry retains an unbroken far horizon")
	ocean.call("_update_deck_displacement",1.0)
	var material: ShaderMaterial=ocean.get_active_material(0)
	var mask: Image=ocean._deck_coverage
	check(mask.get_pixel(66,66).r>0.5 and mask.get_pixel(74,74).r<0.5,"Water displacement follows real foundation cells and leaves open ocean clear")
	var low:=INF; var high:=-INF
	for x in range(80):
		var height: float=ocean.call("get_height",Vector3(x*1.5,0,5))
		low=minf(low,height); high=maxf(high,height)
	check(high-low>0.30 and high-low<1.5 and ocean.wave_height<0.75,"Calm sea retains low visible swells without the former tall waves")
	var before: float=ocean.call("get_height",Vector3(11,0,9))
	check(ocean.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Ocean waves cannot cast moving shadows onto the foundation")
	ocean._time+=3
	check(absf(float(ocean.call("get_height",Vector3(11,0,9)))-before)>0.04,"Wave geometry and buoyancy move over time")
	check(preload("res://scripts/construction_audio.gd").build_sound("Wall")==preload("res://audio/chop.ogg"),"Construction uses the included CC0 timber impact")
	check(FileAccess.get_file_as_bytes("res://3d models/coconut_palm (1).glb")==FileAccess.get_file_as_bytes("res://models/coconut_palm.glb"),"Live coconut palms use the exact owner supplied 3D model")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free(); await frames(20)
	print("CONSTRUCTION WEATHER SMOKE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
