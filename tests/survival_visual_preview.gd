extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func capture(label: String) -> void:
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/survival-" + label + ".png")
	print("CAPTURE ", label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	var settings := root.get_node("GameSettings")
	settings.set("quality", 2)
	settings.set("third_person", false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for i in range(600):
		await physics_frame
		if current_scene.get_node_or_null("Island/IslandGrass/GrassField") != null:
			break
	var player := get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	player.get_node("CanvasLayer/MobileControls").set("force_show", true)
	player.get_node("CanvasLayer/MobileControls").call("_update_visibility")
	var hud := player.get_node("CanvasLayer/SurvivalHUD")
	hud.set("_craft_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("crafting")
	hud.set("_craft_open", false)
	hud.call("_compute_layout")
	player.call("_update_hud")
	await capture("controls")
	hud.set("_bag_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("bag")
	hud.set("_bag_open", false)
	hud.call("_compute_layout")
	hud.queue_redraw()
	player.set("active_item", "Fish")
	player.call("_update_hand_item")
	await capture("hand-fish")
	inv.call("add", "Arrow", 12)
	inv.call("add", "Bow", 1)
	for slot_index in range(6, 30):
		if inv.call("slot_item", slot_index) == "Bow":
			inv.call("drop_into", slot_index, 0)
			break
	player.call("select_hotbar_slot", 0)
	player.set("active_item", "Bow")
	player.call("_update_hand_item")
	player.get_node("SurvivalEquipment").set_physics_process(false)
	player.get_node("SurvivalEquipment").set("drawing", true)
	player.get_node("SurvivalEquipment").set("draw_time", 1.0)
	player.call("_update_hand_sway", 0.016)
	await capture("bow")
	player.get_node("SurvivalEquipment").call("toggle_aim")
	player.get_node("CanvasLayer/MobileControls").call("_sync_mode")
	player.get_node("CanvasLayer/MobileControls").queue_redraw()
	player.get_node("CanvasLayer/Crosshair").queue_redraw()
	await capture("bow-aim")
	player.get_node("SurvivalEquipment").call("set_aiming", false)
	player.get_node("CanvasLayer").visible = false
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.make_current()
	var island := current_scene.get_node("Island") as Node3D
	camera.global_position = island.global_position + Vector3(20, 7, 22)
	camera.look_at(island.global_position + Vector3(0, 2.0, 0))
	await capture("island")
	var origin := Vector3(300, 4, 300)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -25, 0)
	key.light_energy = 0.8
	current_scene.add_child(key)
	var deck := (load("res://scenes/foundation.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(deck)
	deck.position = origin
	deck.scale = Vector3(2.6, 1, 1.8)
	for i in range(3):
		var pot := (load("res://scenes/planter_pot.tscn") as PackedScene).instantiate()
		current_scene.add_child(pot)
		pot.position = origin + Vector3(float(i - 1) * 0.7 - 0.5, 0.34, -0.70)
		pot.plant_seed(["Potato", "Carrot", "Tomato"][i])
		var plant := pot.get("_plant") as Node
		plant.set("_grow", 1.0)
		(plant.get("_container") as Node3D).scale = Vector3.ONE
		plant.set("_stage", 3)
		plant.call("_rebuild_visual")
		plant.set_process(false)
	var fire := (load("res://scenes/bonfire.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(fire)
	fire.position = origin + Vector3(-1.15, 0.11, 0.50)
	var collector := (load("res://scenes/rain_collector.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(collector)
	collector.position = origin + Vector3(1.45, 0.45, -0.2)
	for i in range(2):
		var model := (load("res://models/coastal_fish.glb") as PackedScene).instantiate() as Node3D
		current_scene.add_child(model)
		model.position = origin + Vector3(0.3, 0.17, float(i) * 0.35 + 0.4)
	camera.global_position = origin + Vector3(3.5, 2.6, 3.8)
	camera.look_at(origin + Vector3(0, 0.35, 0))
	await capture("garden-fire")
	var rain := player.get_node("RainSystem")
	rain.call("start_rain", 60.0)
	camera.global_position = island.global_position + Vector3(16, 5, 19)
	camera.look_at(island.global_position + Vector3(0, 2.0, 0))
	await capture("rain")
	rain.call("stop_rain")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	await create_timer(0.1).timeout
	quit()
