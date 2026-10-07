extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("FAIL: cinematic verification timed out"); quit(1))
	call_deferred("_run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+description)
	else: print("PASS: "+description)
func frames(count: int) -> void:
	for i in range(count): await process_frame
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280,720)
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset",true)
	var intro := load("res://scripts/flooded_world_intro.gd").new() as Control
	root.add_child(intro)
	intro.set_process(false)
	check(not intro.get("_skip").get_global_rect().intersects(intro.get("_cancel").get_global_rect()),"Cinematic buttons are separate on their first frame")
	var film := intro.get("_video") as VideoStreamPlayer
	check(film.stream is VideoStreamTheora and film.is_playing() and not film.loop,"New Game plays the bundled film once")
	check(film.bus == &"Master" and film.buffering_msec >= 500,"Film audio honors volume and mute with buffered playback")
	check(intro.call("total_duration") > 30 and intro.call("total_duration") < 32,"Full film is about 31 seconds")
	check(absf(film.size.x / film.size.y - 848.0 / 480.0) < 0.01,"Landscape film retains its aspect ratio")
	for i in range(8):
		var cue: Array = intro.CUES[i]
		intro.call("_update_caption", float(cue[0]) + 0.1)
		check(intro.get("_caption").text == cue[2] and intro.get("_caption_panel").visible,"Scene subtitle "+str(i)+" displays completely")
	intro.call("_update_caption",3.8)
	check(not intro.get("_caption_panel").visible,"Captions clear between spoken lines")
	var before: float = film.stream_position
	intro.call("_process",100.0)
	check(not intro.complete and intro.elapsed == before,"A long frame cannot end the film or run captions ahead of audio")
	intro.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(film.paused,"Backgrounding pauses the film and its embedded narration together")
	intro.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not film.paused,"Returning resumes synchronized video and sound")
	intro.set_anchors_preset(Control.PRESET_TOP_LEFT)
	intro.size = Vector2(640,360)
	intro.call("_layout")
	check(not intro.get("_skip").get_global_rect().intersects(intro.get("_cancel").get_global_rect()),"Small-screen Skip and Back keep separate touch targets")
	intro.size = Vector2(1280,720)
	intro.call("_layout")
	var finishes := [0]
	intro.finished.connect(func(): finishes[0] += 1)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = intro.get("_skip").get_global_rect().get_center()
	intro.call("_input",tap)
	check(intro.complete and not film.is_playing() and intro.handoff_texture != null,"Touch Skip stops embedded audio and holds a frame for the transition")
	intro.call("finish")
	check(finishes[0] == 1,"Repeated Skip cannot start multiple scene transitions")
	intro.progress = 0.62
	intro.call("_process",0.1)
	check(intro.get("_status").visible and intro.get("_loading_bar").value == 62,"Finished film shows preparation feedback until the world loads")
	intro.queue_free()
	await frames(2)
	var completed_intro := load("res://scripts/flooded_world_intro.gd").new() as Control
	root.add_child(completed_intro)
	completed_intro.call("_on_video_finished")
	check(completed_intro.complete and completed_intro.playback_finished and completed_intro.handoff_texture == completed_intro.ARRIVAL,"Normal completion retains the film's final raft frame")
	completed_intro.queue_free()
	await frames(2)
	var cancelled_intro := load("res://scripts/flooded_world_intro.gd").new() as Control
	root.add_child(cancelled_intro)
	var cancels := [0]
	cancelled_intro.cancelled.connect(func(): cancels[0] += 1)
	tap.position = cancelled_intro.get("_cancel").get_global_rect().get_center()
	cancelled_intro.call("_input",tap)
	check(cancels[0] == 1 and not cancelled_intro.get("_video").is_playing(),"Touch Back releases video audio before returning to the menu")
	cancelled_intro.queue_free()
	await frames(2)
	var pending_menu := load("res://scripts/main_menu.gd").new() as Control
	pending_menu.set("_story_pending",true)
	pending_menu.set("_busy",true)
	pending_menu.set("_selected_id","new")
	var pending_slots: Array = inv.slots.duplicate(true)
	pending_menu.call("_swap_scene",PackedScene.new())
	check(pending_menu.get("_waiting_to_enter") and inv.slots == pending_slots,"Preparing a story cannot enter gameplay or reset inventory before playback")
	pending_menu.call("_cancel_loading")
	check(not pending_menu.get("_story_pending") and not pending_menu.get("_busy") and pending_menu.get("_selected_id") == "","Cancel also clears a story waiting for script preparation")
	pending_menu.hide()
	pending_menu.call("_process",0.1)
	check(pending_menu.get("_intro") == null,"Late script preparation cannot start a cancelled story")
	pending_menu.free()
	var handoff := load("res://scripts/wake_transition.gd").new() as CanvasLayer
	root.add_child(handoff)
	handoff.set_process(false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await frames(8)
	var player := get_first_node_in_group("player") as CharacterBody3D
	var controls := player.get_node("CanvasLayer/MobileControls")
	var raft := current_scene.get_node("Raft")
	check(player != null and handoff.layer == 100 and player.get("cam_mode") == 0,"Wake-up image leads into the matching first-person game view")
	var visual := raft.get_node_or_null("StarterRaftVisual")
	check(visual != null and visual.get_node("RoundedTimbers").multimesh.instance_count == 9,"Starter raft has nine batched rounded logs")
	check(visual.get_node_or_null("RopeLashing0") != null and visual.get_node_or_null("CrossBraces") != null,"Timber raft has lashings and supporting cross-poles")
	check(not raft.get_node("MeshInstance3D").visible,"Starter raft no longer renders as a plain block")
	check(visual.get_node("DecorativeRig").get_meta("cosmetic_only") and raft.call("get_navigation_speed") == 0,"Small cloth rig is decorative and cannot steer for free")
	check(absf(float(current_scene.get_node("Sky3D").get("current_time"))-6.25) < 0.1,"Story arrival starts at matching dawn light")
	handoff.call("_process",0.1)
	check(not player.is_physics_processing() and not controls.is_processing_input() and not player.get_node("CanvasLayer").visible and not root.get_node("Stats").enabled,"Wake fade holds movement, touch input, HUD and survival drain")
	root.get_node("GameSettings").notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not paused,"Android Back cannot pause the game underneath its wake overlay")
	var setup := current_scene.get_node("IslandSetup")
	var setup_ready: bool = setup.setup_complete
	setup.setup_complete = false
	for i in range(60): handoff.call("_process",0.016)
	check(not handoff.get("_revealing") and not player.is_processing_unhandled_input(),"Wake transition waits for actual world preparation with input held")
	setup.setup_complete = setup_ready
	# Let the real asynchronous island preparation finish in physics frames.
	for i in range(400):
		if handoff.call("_world_ready"): break
		await physics_frame
	for i in range(240):
		if handoff.is_queued_for_deletion(): break
		handoff.call("_process",0.016)
	await frames(2)
	check(not is_instance_valid(handoff) and player.is_physics_processing() and controls.is_processing_input() and player.is_processing_unhandled_input() and player.get_node("CanvasLayer").visible,"Wake fade releases movement, touch input and HUD and removes its overlay")
	var slow_handoff := load("res://scripts/wake_transition.gd").new() as CanvasLayer
	root.add_child(slow_handoff)
	slow_handoff.set_process(false)
	for i in range(80):
		if slow_handoff.is_queued_for_deletion(): break
		slow_handoff.call("_process",0.1)
	await frames(2)
	check(not is_instance_valid(slow_handoff) and player.is_physics_processing(),"A phone below 20 FPS still completes the wake transition after world preparation")
	raft.call("set_upgrade_tier",1)
	check(not visual.get_node("DecorativeRig").visible and raft.call("get_navigation_speed") == 2.7 and raft.get_node_or_null("SailUpgradeVisual") != null,"Real Sail Kit replaces the display cloth and keeps navigation")
	var foundation := (load("res://scenes/foundation.tscn") as PackedScene).instantiate()
	current_scene.add_child(foundation)
	var material: ShaderMaterial = foundation.get_node("MeshInstance3D").get_active_material(0)
	check(material.get_shader_parameter("photographic_wood") and material.get_shader_parameter("wood_texture") is Texture2D,"Foundation uses the shared photographic timber texture")
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null: ambient.call("stop_environment")
	# Give the dummy audio backend time to release its stopped streams.
	await create_timer(0.2).timeout
	print("CINEMATIC RAFT SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
