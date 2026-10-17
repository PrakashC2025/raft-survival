extends SceneTree
## Isolated real loader and large Continue fixture; no phone FPS assertions.
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func(): check(false,"Loading test timeout"); quit(1))
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280,720)
	var inventory := root.get_node("Inventory")
	var settings := root.get_node("GameSettings")
	check(settings.target_fps == 30 if settings.mobile_effects_profile() else settings.target_fps == 60,
		"A new phone installation starts at 30 FPS; desktop retains 60 FPS")
	inventory.new_game_reset(true)
	root.get_node("Stats").enabled = false
	var menu := load("res://scripts/main_menu.gd").new() as Control
	root.add_child(menu)
	current_scene = menu
	Engine.max_fps = 120
	var started := Time.get_ticks_msec()
	var heartbeats := 0
	var last_frame := started
	var worst_load_frame := 0
	while menu.get("_packed_game") == null and menu.get("_error") == "" and Time.get_ticks_msec()-started < 120000:
		await process_frame
		heartbeats += 1
		var now := Time.get_ticks_msec()
		worst_load_frame = maxi(worst_load_frame,now-last_frame)
		last_frame = now
	check(menu.get("_packed_game") != null and menu.get("_error") == "", "Real asynchronous model/script/game loading completes")
	check(heartbeats > 1, "Loading keeps producing render-frame heartbeats without a mandatory frame per resource")
	var warmed: Array=menu.get("_warm_resources")
	var retained:=true
	for path in menu.MODEL_WARM_PATHS+menu.SCRIPT_WARM_PATHS:
		retained=retained and ResourceLoader.has_cached(path) and warmed.has(load(path))
	var art:=preload("res://scripts/item_art.gd")
	for station in art.STATION_IMAGES:retained=retained and warmed.has(art.station_texture(station))
	for dish in ["Tumbler","Ocean Water Tumbler","Boiled Water Tumbler","Diving Tank"]:retained=retained and warmed.has(art.food_texture(dish))
	var thumbnail:=art.food_texture("Cooked Potato") as AtlasTexture
	check(retained and thumbnail!=null and warmed.has(thumbnail.atlas), "Prepared models, scripts, stations and the shared food atlas stay cached")
	print("LOAD DIAGNOSTIC: %d ms, %d heartbeats, largest observed frame %d ms (desktop only)" % [Time.get_ticks_msec()-started,heartbeats,worst_load_frame])
	var packed := menu.get("_packed_game") as PackedScene
	if packed == null:
		print("LOADING PERFORMANCE SMOKE: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	# A manual stress-fixture swap must remove the menu just like the real
	# change_scene path, or its animated full-screen sea keeps rendering too.
	menu.queue_free()
	var built: Array = []
	for index in range(96):
		var x := (index % 12)*2.0
		var z := floori(float(index)/12.0)*2.0
		built.append({"t":"Foundation","x":[1,0,0,0,1,0,0,0,1,x,0,z]})
	for index in range(24):
		built.append({"t":"Roof","x":[1,0,0,0,1,0,0,0,1,(index%12)*2.0,2.725,floori(float(index)/12.0)*2.0]})
	var meta := {"built":built,"game_time":15.5,"game_day":4}
	check(inventory.save_game(meta,"main"), "Large Continue fixture saves through the real authenticated format")
	check(not inventory.load_game("main").is_empty(), "Large Continue fixture loads through normal validation")
	var before := FileAccess.get_file_as_bytes("user://raft_save.json")
	settings.third_person = true
	var handoff := load("res://scripts/wake_transition.gd").new() as CanvasLayer
	handoff.resuming = true
	root.add_child(handoff)
	handoff.set_process(false)
	var world := packed.instantiate()
	root.add_child(world)
	current_scene = world
	var player := get_first_node_in_group("player") as CharacterBody3D
	var raft := world.get_node("Raft")
	check(not player.restoration_complete, "Continue explicitly tracks incomplete restoration")
	check(player.cam_mode == 1 and absf(float(world.get_node("Sky3D").current_time)-15.5)<0.1, "Continue overlay preserves saved clock and chosen third-person camera")
	check(not player.quick_save(), "Saving is refused while restoration is incomplete")
	player._tick_save(100.0)
	check(FileAccess.get_file_as_bytes("user://raft_save.json") == before, "Autosave cannot overwrite the complete save with a partial raft")
	handoff._process(.016)
	check(not handoff._world_ready() and not player.is_physics_processing(), "Continue overlay holds movement until restoration finishes")
	var restore_frames := 0
	while not player.restoration_complete and restore_frames < 1200:
		await process_frame
		restore_frames += 1
	check(player.restoration_complete and restore_frames > 1, "Large raft restoration yields across render frames and completes")
	var pieces := raft.get_node("BuiltPieces").get_children()
	check(pieces.size() == built.size(), "Incremental Continue restores all 120 pieces without duplicates")
	check(not raft.get_node("BuiltPieces").get_meta("restoring",true), "Restoration releases construction batching")
	var exact := true
	var sockets: Array = player._get_all_sockets(raft)
	for socket in sockets:
		var parent: Node3D = socket.get_parent_piece()
		if parent == null: parent = raft
		var at: Vector3 = player._get_flat_support_transform(parent)*socket.position
		var best: Node3D
		var distance := .45
		for piece in pieces:
			if piece == parent: continue
			var separation := Vector2(piece.global_position.x-at.x,piece.global_position.z-at.z).length()
			if separation < distance: best=piece;distance=separation
		if best != null and socket.occupying_piece != best: exact=false;break
	check(exact, "Spatial socket index matches the previous exhaustive nearest-piece result")
	check(player.quick_save(), "Completed restoration can be saved normally")
	var roof := pieces[96]
	roof.refresh(false)
	var snapshot: Array = raft.get_node("BuiltPieces").get_meta("roof_flights")
	for index in range(97,120): pieces[index].refresh(false)
	check(is_same(snapshot,raft.get_node("BuiltPieces").get_meta("roof_flights")), "All roofs reuse one frame's staircase scan")
	var rain := player.get_node("RainSystem")
	rain.stop_rain()
	rain._mask_boxes.clear()
	rain._cover_timer = 0
	rain._update_cover_state(.5)
	check(rain._mask_boxes.is_empty(), "Dry weather skips whole-raft shelter scans")
	var performance := world.get_node("MobilePerformance")
	settings.quality = 0
	performance._last_quality = -1
	performance._apply_profile()
	if settings.mobile_effects_profile():
		check(root.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(performance._render_scale,.82), "Mobile Auto starts at a clearer bounded render scale")
		check(root.screen_space_aa==Viewport.SCREEN_SPACE_AA_FXAA and root.scaling_3d_mode==Viewport.SCALING_3D_MODE_BILINEAR,"Mobile Auto smooths low-resolution edges instead of exposing raw jagged pixels")
		for window in 30:performance._update_quality(.09)
		check(performance._render_scale>=.65,"Sustained slow frames keep Auto above its clearer resolution floor")
		performance._last_quality=-1;performance._apply_profile()
		check(Engine.physics_ticks_per_second==30,"A 30 FPS phone uses 30 physics ticks rather than simulating twice per frame")
		var spawner := world.get_node("DebrisSpawner")
		check(spawner.max_debris<=48 and spawner.prewarm_count<=24,"Desktop mobile profiling uses the real phone debris limits")
	_verify_waves(get_first_node_in_group("ocean"))
	_verify_crest_cache(raft,get_first_node_in_group("ocean"))
	# Exercise actual gameplay, including visible phone controls; the earlier
	# assertions separately cover the handoff's restoration input lock.
	handoff._release_player()
	handoff.queue_free()
	player.global_position=raft.to_global(Vector3(8,1.0,8))
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.force_show=true
	var walk_origin := player.global_position
	# Exercise real look/movement callbacks while background islands prepare.
	var walk_frames := 0
	var walk_started := Time.get_ticks_msec()
	var walk_frame_times: Array[int]=[]
	var last_walk_frame := walk_started
	var physics_peak := 0.0
	var process_peak := 0.0
	Input.action_press("move_forward")
	while walk_frames < 90:
		player.rotate_y(.025)
		var local: Vector3=raft.to_local(player.global_position)
		if local.x<3 or local.x>19 or local.z<3 or local.z>11:
			player.look_at(raft.to_global(Vector3(11,local.y,7)))
		await process_frame
		var now := Time.get_ticks_msec()
		walk_frame_times.append(now-last_walk_frame)
		last_walk_frame=now
		physics_peak = maxf(physics_peak,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		process_peak = maxf(process_peak,Performance.get_monitor(Performance.TIME_PROCESS))
		walk_frames += 1
	Input.action_release("move_forward")
	check(player.global_position.is_finite() and walk_frames == 90 and player.global_position.distance_to(walk_origin)>.1, "Real movement and camera callbacks run during bounded island setup")
	print("CONTINUE DIAGNOSTIC: %d restore frames; 90 look/movement frames in %d ms (desktop only)" % [restore_frames,Time.get_ticks_msec()-walk_started])
	print("FRAME DIAGNOSTIC: peak physics %.1f ms; peak process %.1f ms" % [physics_peak*1000,process_peak*1000])
	walk_frame_times.sort()
	print("MOVEMENT DIAGNOSTIC: median frame %d ms; 95th percentile %d ms (desktop only)" % [walk_frame_times[45],walk_frame_times[85]])
	if "--profile-loading" in OS.get_cmdline_user_args(): _profile_callbacks(world)
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(get_script().resource_path.get_base_dir().path_join("../build/loading-gameplay-preview.png"))
	var ambient := world.get_node_or_null("OceanAmbience")
	if ambient != null: ambient.stop_environment()
	await create_timer(.25).timeout
	print("LOADING PERFORMANCE SMOKE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _verify_waves(ocean: Node3D) -> void:
	var before: float=ocean._time
	var exact := true
	var batch_exact := true
	var points := PackedVector3Array([Vector3(-9,0,5),Vector3(0,0,0),Vector3(11,0,-7)])
	var tilt := Basis.from_euler(Vector3(.02,.7,-.018))
	for time in [0.0,17.5,300.0]:
		ocean._time=time
		for index in range(80):
			var position := Vector3(index*6.13-250,0,index*-4.12+160)
			if absf(ocean.get_height(position)-_previous_height(ocean,position))>.00001: exact=false
		var origin := Vector3(12,1,-8)
		var crest := -INF
		for point in points:
			var offset := tilt*point
			crest=maxf(crest,_previous_height(ocean,origin+offset)-offset.y)
		if absf(ocean.get_deck_crest(origin,tilt,points)-crest)>.00001: batch_exact=false
	ocean._time=before
	check(exact,"Optimized wave heights match the original shader formula at 240 positions/times")
	check(batch_exact,"Batched buoyancy retains exact tilted-corner clearance")

func _previous_height(ocean: Node3D, at: Vector3) -> float:
	var p := Vector2(at.x,at.z)
	var tt: float=ocean._time*ocean.wave_speed
	var warp := Vector2(
		6.0*sin(p.dot(Vector2(.21,.98))*.020+tt*.10)+3.2*sin(p.dot(Vector2(.85,-.53))*.048+tt*.16),
		6.0*sin(p.dot(Vector2(.21,.98))*.020+tt*.10+2.1)+3.2*sin(p.dot(Vector2(.85,-.53))*.048+tt*.16+4.2))
	var pw := p+warp
	var env := .75+.25*sin(pw.dot(Vector2(-.31,.95))*.011+tt*.06)*sin(pw.dot(Vector2(.90,-.44))*.026+tt*.10)
	var h := 0.0
	for wave in ocean._WAVES:
		var direction: Vector2=wave[0]
		h+=float(wave[2])*sin(pw.dot(direction)*float(wave[1])+tt*float(wave[3]))
	return ocean.global_position.y+h*env*float(ocean.wave_height)*.33

func _verify_crest_cache(raft: Node3D, ocean: Node3D) -> void:
	raft._refresh_deck_samples()
	var origin := Vector3(0,1,0)
	var deck_basis := Basis.from_euler(Vector3(.002,.1,-.002))
	raft._deck_crest(ocean,origin,deck_basis)
	var moved := origin+Vector3(.02,0,-.01)
	var tilted := Basis.from_euler(Vector3(.0021,.1001,-.0021))
	var cached: float=raft._deck_crest(ocean,moved,tilted)
	var exact: float=ocean.get_deck_crest(moved,tilted,raft._deck_samples)
	check(raft._sample_origin==origin and cached>=exact-.00001 and cached-exact<.05,
		"Repeated physics ticks reuse the wave field with safe clearance for small movement/tilt")
	raft._deck_crest(ocean,origin+Vector3(2,0,0),deck_basis)
	check(raft._sample_origin==origin+Vector3(2,0,0),"Large navigation motion invalidates buoyancy cache")
	var clock: float=ocean._time
	ocean._time+=.1
	raft._deck_crest(ocean,origin,deck_basis)
	check(raft._sample_wave_time==ocean._time,"Each new visible wave clock invalidates buoyancy cache")
	ocean._time=clock
	raft._refresh_deck_samples()

func _profile_callbacks(world: Node) -> void:
	var totals := {}
	for node in world.find_children("*","",true,false):
		if not is_instance_valid(node) or node.get_script() == null: continue
		for method in ["_process","_physics_process"]:
			if not node.has_method(method): continue
			if not node.is_processing() if method == "_process" else not node.is_physics_processing(): continue
			var started := Time.get_ticks_usec()
			node.call(method,0.0)
			var key: String = str(node.get_script().resource_path)+" "+method
			totals[key] = int(totals.get(key,0))+Time.get_ticks_usec()-started
	var paths: Array = totals.keys()
	paths.sort_custom(func(a,b): return totals[a]>totals[b])
	for index in mini(paths.size(),8):
		print("CALLBACK DIAGNOSTIC: ",paths[index]," ",float(totals[paths[index]])/1000.0," ms")
