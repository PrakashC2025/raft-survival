extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func capture(label: String) -> void:
	for i in range(15):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/advanced-"+label+".png")
	print("CAPTURE "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset",true)
	root.get_node("Stats").set("enabled",false)
	root.get_node("GameSettings").set("quality",2)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	for i in range(90):
		await physics_frame
	var player := get_first_node_in_group("player")
	player.set_process(false)
	player.set_physics_process(false)
	player.get_node("SurvivalProgression").set_process(false)
	player.get_node("CanvasLayer/MobileControls").set("force_show",true)
	player.get_node("CanvasLayer/MobileControls").call("_update_visibility")
	var hud := player.get_node("CanvasLayer/SurvivalHUD")
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("mission")
	hud.set("_craft_open",true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await capture("crafting")
	player.get_node("CanvasLayer").visible = false
	var origin := Vector3(350,8,350)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-25,0)
	light.light_energy = 0.85
	current_scene.add_child(light)
	var deck := (load("res://scenes/foundation.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(deck)
	deck.position = origin
	deck.scale = Vector3(4.0,1,2.4)
	var names := ["water_purifier","wind_generator","electric_lamp","electric_purifier","rescue_radio"]
	for i in range(names.size()):
		var machine := (load("res://scenes/"+names[i]+".tscn") as PackedScene).instantiate() as Node3D
		current_scene.add_child(machine)
		machine.position = origin + Vector3((i-2)*1.35,0.5,0)
		machine.set_process(false)
		machine.set("water",3)
		machine.set("charge",80)
		machine.call("_refresh_label")
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.make_current()
	camera.position = origin+Vector3(7.0,4.6,9)
	camera.look_at(origin+Vector3(0,0.8,0))
	await capture("machines")
	for i in range(3):
		var model := (load("res://models/"+["wild_boar","sea_turtle","shore_crab"][i]+".glb") as PackedScene).instantiate() as Node3D
		current_scene.add_child(model)
		model.position = origin+Vector3((i-1)*1.4,0.16,1.3)
		model.rotation.y = 2.8
	camera.position = origin+Vector3(3,2.1,5.5)
	camera.look_at(origin+Vector3(0,0.40,1.3))
	await capture("wildlife")
	var raft := current_scene.get_node("Raft") as Node3D
	raft.set_physics_process(false)
	camera.position = raft.global_position+Vector3(2.8,2.3,3.5)
	camera.look_at(raft.global_position+Vector3(0,0.5,0))
	await capture("starter-raft")
	var intro := load("res://scripts/flooded_world_intro.gd").new() as Control
	root.add_child(intro)
	intro.set_process(false)
	for frame_index in range(4):
		intro.set("elapsed",intro.call("shot_start",frame_index)+2.5)
		intro.queue_redraw()
		await capture("story-"+str(frame_index))
	intro.queue_free()
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null:
		ambient.call("stop_environment")
	for i in range(3):
		await process_frame
	quit()
