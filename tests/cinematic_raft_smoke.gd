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
	for i in range(4):
		var clip: AudioStream = intro.VOICES[i]
		var duration: float = intro.call("shot_start",i+1)-intro.call("shot_start",i)
		check(clip.get_length() > 2 and duration >= clip.get_length()+0.8,"Recorded voice finishes before story shot "+str(i)+" changes")
	check(intro.call("total_duration") > 20 and intro.call("total_duration") < 60,"Narrated story stays bounded and lightweight")
	intro.call("_process",100.0)
	check(intro.get("_shot") == 0 and intro.get("started_shots") == [0],"Long loading frames cannot skip narration shots")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = intro.get("_skip").get_global_rect().get_center()
	intro.call("_input",tap)
	check(intro.complete and not intro.get("_voice").playing and not intro.get("_effects").playing,"Skip releases narration and effects immediately")
	intro.queue_free()
	await frames(2)
	var handoff := load("res://scripts/wake_transition.gd").new() as CanvasLayer
	root.add_child(handoff)
	handoff.set_process(false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await frames(8)
	var player := get_first_node_in_group("player") as CharacterBody3D
	var raft := current_scene.get_node("Raft")
	check(player != null and handoff.layer == 100 and player.get("cam_mode") == 0,"Wake-up image leads into the matching first-person game view")
	var visual := raft.get_node_or_null("StarterRaftVisual")
	check(visual != null and visual.get_node("RoundedTimbers").multimesh.instance_count == 9,"Starter raft has nine batched rounded logs")
	check(visual.get_node_or_null("RopeLashing0") != null and visual.get_node_or_null("CrossBraces") != null,"Timber raft has lashings and supporting cross-poles")
	check(not raft.get_node("MeshInstance3D").visible,"Starter raft no longer renders as a plain block")
	check(visual.get_node("DecorativeRig").get_meta("cosmetic_only") and raft.call("get_navigation_speed") == 0,"Small cloth rig is decorative and cannot steer for free")
	check(absf(float(current_scene.get_node("Sky3D").get("current_time"))-6.25) < 0.1,"Story arrival starts at matching dawn light")
	handoff.call("_process",0.1)
	check(not player.is_physics_processing() and not player.get_node("CanvasLayer").visible and not root.get_node("Stats").enabled,"Wake fade holds movement, HUD and survival drain")
	for i in range(26): handoff.call("_process",0.1)
	await frames(2)
	check(not is_instance_valid(handoff) and player.is_physics_processing() and player.get_node("CanvasLayer").visible,"Wake fade releases gameplay and removes its overlay")
	raft.call("set_upgrade_tier",1)
	check(not visual.get_node("DecorativeRig").visible and raft.call("get_navigation_speed") == 2.7 and raft.get_node_or_null("SailUpgradeVisual") != null,"Real Sail Kit replaces the display cloth and keeps navigation")
	var foundation := (load("res://scenes/foundation.tscn") as PackedScene).instantiate()
	current_scene.add_child(foundation)
	var material: ShaderMaterial = foundation.get_node("MeshInstance3D").get_active_material(0)
	check(material.get_shader_parameter("photographic_wood") and material.get_shader_parameter("wood_texture") is Texture2D,"Foundation uses the shared photographic timber texture")
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null: ambient.call("stop_environment")
	print("CINEMATIC RAFT SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
