extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var instance := scene.instantiate()
	root.add_child(instance)
	current_scene = instance
	await create_timer(5.0).timeout
	var player := get_first_node_in_group("player")
	var director := player.get_node("SurvivalDirector")
	assert(director.world.survivors.size() == 3)
	assert(director.audio.sounds.size() == 9)
	assert(director.intro_running)
	for child in current_scene.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("survival_intro.gd"):
			child.time = 17.9
			child._process(0.2)
	assert(director.intro_seen and not director.intro_running)
	assert(player.is_physics_processing())
	var island: Node3D = director.world.survivors[0]
	var query := PhysicsRayQueryParameters3D.create(island.global_position + Vector3(3, 10, 3), island.global_position + Vector3(3, -5, 3), 1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not hit.is_empty(), "Island top must have collision")
	assert(absf(hit.position.y - 2.5) < 0.1)
	player.set_physics_process(false)
	for location: Vector3 in director.world.LOCATIONS:
		player.global_position = location + Vector3(0, 4, 0)
		director.world.tick(player)
	assert(director.world.visited.size() == 3)
	var inventory := root.get_node("Inventory")
	inventory.add("Signal Beacon", 1)
	director._signal_rescue()
	assert(director.rescued)
	var state: Dictionary = director.save_state()
	assert(state.visited.size() == 3 and state.rescued and state.intro_seen)
	director._toggle()
	director._toggle()
	director._mute()
	assert(director.audio.muted)
	director._mute()
	var pot: Node = load("res://scenes/planter_pot.tscn").instantiate()
	var raft: Node3D = player._get_raft_node()
	var pieces: Node = raft.get_node_or_null("BuiltPieces")
	if pieces == null:
		pieces = Node3D.new()
		pieces.name = "BuiltPieces"
		raft.add_child(pieces)
	pot.name = "PlanterPot_Test"
	pieces.add_child(pot)
	assert(pot.plant_seed("Potato"))
	pot._plant._stage_timer = 9.0
	var plant_state: Dictionary = pot._plant.survival_snapshot()
	pot._plant.restore_survival_snapshot(plant_state)
	assert(pot._plant._stage_timer == 9.0)
	var built: Array = player._serialize_built_pieces()
	assert(built.any(func(entry: Dictionary) -> bool: return entry.get("plant_id", "") == "Potato"))
	var fire: Node3D = load("res://scenes/bonfire.tscn").instantiate()
	fire.name = "Bonfire_Test"
	pieces.add_child(fire)
	player.global_position = fire.global_position + Vector3(0, 1, 1)
	assert(director._near_fire())
	inventory.add("Raw Fish", 1)
	inventory.add("Wood", 1)
	director._cook()
	assert(not director.cooking.is_empty())
	director.cooking.remaining = 0.0
	director._expansion_tick(0.1, false)
	assert(inventory.has("Cooked Fish", 1))
	assert(director.cooking.is_empty())
	assert(player.BUILD_RECIPE_NAMES.has("Bonfire"))
	pot.queue_free()
	fire.queue_free()
	await physics_frame
	await physics_frame
	player.select_piece_for_build(player.BUILD_RECIPE_NAMES.find("Bonfire"))
	for socket in player._get_all_sockets(raft):
		if socket.is_compatible("Bonfire"):
			player.aim_valid = true
			player.aim_collider = raft
			player.aim_point = socket.global_position
			player.aim_normal = Vector3.UP
			player.aim_distance = 3.0
			break
	var placement: Dictionary = player._resolve_placement("Bonfire", player.aim_point)
	print("BONFIRE PLACEMENT: ", placement.get("valid", false), " ", player._diag.get("invalid_reason", ""))
	assert(placement.get("valid", false))
	player._toggle_build()
	assert(player.build_pieces.size() == player.BUILD_RECIPE_NAMES.size())
	if OS.get_cmdline_user_args().has("--capture"):
		player.set_process(false)
		player.global_position = director.world.LOCATIONS[0] + Vector3(0, 4, 12)
		player.camera.current = true
		player.camera.look_at(director.world.LOCATIONS[0] + Vector3(0, 3, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/survival_world_preview.png")
		director.panel.show()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/survival_journal_preview.png")
	print("PASS: world collision, opening completion, audio, exploration, rescue, saved campaign, journal, mute")
	quit()





