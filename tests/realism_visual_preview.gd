extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func capture(label: String) -> void:
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/realism-" + label + ".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.get_node("Inventory").call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	var settings := root.get_node("GameSettings")
	settings.set("quality", 2)
	settings.set("third_person", false)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	await capture("menu")
	for frame in range(3600):
		if current_scene.get("_packed_game") != null:
			break
		await process_frame
	if OS.get_cmdline_user_args().has("--menu-only"):
		if current_scene.get("_packed_game") == null:
			push_error("Rendered menu could not finish its real scene load")
			quit(1)
		else:
			print("REAL MENU LOAD READY · ", current_scene.get("_warm_resources").size(), " prepared script dependencies")
			quit()
		return
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for frame in range(600):
		await physics_frame
		if current_scene.get_node_or_null("Island/IslandGrass/GrassField") != null:
			break
	var player := get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var performance := get_first_node_in_group("mobile_performance")
	performance.set("_mobile", true)
	performance.set("_last_quality", -1)
	performance.call("_apply_profile")
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.set("force_show", true)
	controls.call("_update_visibility")
	player.call("_update_hud")
	await capture("hud")
	var hud := player.get_node("CanvasLayer/SurvivalHUD")
	hud.set("_bag_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("inventory")
	hud.set("_bag_open", false)
	hud.set("_craft_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("crafting")
	hud.set("_craft_open", false)
	settings.call("open")
	await capture("settings")
	settings.call("close")
	player.get_node("CanvasLayer").visible = false
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.make_current()
	var island := current_scene.get_node("Island") as Node3D
	camera.global_position = island.global_position + Vector3(22, 7, 23)
	camera.look_at(island.global_position + Vector3(0, 2.5, 0))
	await capture("island")
	# A lit tabletop lets the original salvage silhouettes and surface detail
	# be inspected together instead of relying on small distant debris.
	var origin := Vector3(300, 4, 300)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.0
	current_scene.add_child(light)
	var deck := (load("res://scenes/foundation.tscn") as PackedScene).instantiate() as Node3D
	deck.position = origin
	deck.scale = Vector3(2, 1, 1)
	current_scene.add_child(deck)
	var resource_script := load("res://scripts/resource_visual.gd")
	for i in range(3):
		var prop: Node3D = resource_script.create(["Rope", "Plastic", "Metal"][i])
		prop.position = origin + Vector3(float(i-1) * 0.85, 0.40, 0)
		current_scene.add_child(prop)
		var label := Label3D.new()
		label.text = ["ROPE", "PLASTIC", "METAL"][i]
		label.font_size = 32
		label.pixel_size = 0.003
		label.position = prop.position + Vector3(0, 0.5, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		current_scene.add_child(label)
	camera.global_position = origin + Vector3(0, 1.75, 2.35)
	camera.look_at(origin + Vector3(0, 0.3, 0))
	await capture("objects")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	await create_timer(0.1).timeout
	quit()
