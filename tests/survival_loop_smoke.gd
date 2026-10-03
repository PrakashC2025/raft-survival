extends SceneTree
var checks := 0
var failures := 0
var inv: Node
var player: CharacterBody3D
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	inv = root.get_node("Inventory")
	inv.call("new_game_reset", true)
	root.get_node("Stats").set("enabled", false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await frames(20)
	player = get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		check(false, "Game player script loads")
		quit(1)
		return
	player.set_process(false)
	player.set_physics_process(false)
	check(int(inv.call("total", "Carrot Seed")) == 4 and int(inv.call("total", "Tomato Seed")) == 4, "New Game grants the new crop seeds")
	check(player.BUILD_RECIPE_NAMES.size() == 11 and player.BUILD_RECIPE_NAMES[3] == "Stairs", "New structures preserve legacy build indexes")
	var hud := player.get_node("CanvasLayer/SurvivalHUD")
	hud.set("_craft_open", true)
	hud.call("_compute_layout")
	var cards: Array = hud.get("_craft_card_rects")
	var panel: Rect2 = hud.get("_craft_panel_rect")
	check(cards.size() == 7 and panel.encloses(cards[6]), "Bow and arrow crafting cards fit inside the panel")
	hud.set("_craft_open", false)
	hud.call("_compute_layout")
	# Exercise real placement and saved state, rather than only instantiating props.
	var raft := current_scene.get_node("Raft") as Node3D
	var container := raft.get_node("BuiltPieces")
	var camera_build := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	player.global_position = raft.global_position + Vector3(0, 2, 4)
	camera_build.look_at(raft.global_position)
	player.call("select_piece_for_build", 9)
	player.set("aim_valid", true)
	player.set("aim_collider", raft)
	player.set("aim_normal", Vector3.UP)
	player.set("aim_point", raft.global_position + Vector3.UP * 0.15)
	player.call("_update_build_preview")
	check(bool(player.get("build_valid")), "A real raft socket offers a valid campfire preview")
	if bool(player.get("build_valid")):
		player.call("_try_build")
	var built_fire := container.find_child("Bonfire_*", false, false)
	check(built_fire != null, "Confirming the preview builds a playable campfire")
	var foundation := (load("res://scenes/foundation.tscn") as PackedScene).instantiate() as Node3D
	foundation.name = "Foundation_SurvivalFixture"
	container.add_child(foundation)
	foundation.global_transform = player.call("_compute_foundation_transform", Vector2i(1, 0))
	foundation.add_to_group("build_surface")
	player.call("_grid_register", Vector2i(1, 0), foundation)
	await frames(3)
	player.call("select_piece_for_build", 10)
	player.set("aim_valid", true)
	player.set("aim_collider", foundation)
	player.set("aim_normal", Vector3.UP)
	player.set("aim_point", foundation.global_position + Vector3.UP * 0.15)
	player.call("_update_build_preview")
	check(bool(player.get("build_valid")), "A supported foundation offers a valid rain collector preview")
	if bool(player.get("build_valid")):
		player.call("_try_build")
	var built_collector := container.find_child("RainCollector_*", false, false)
	check(built_collector != null, "Confirming builds a playable rain collector")
	if built_collector != null:
		built_collector.set("water", 3)
	var structure: Array = player.call("_serialize_built_pieces")
	var collector_saved := false
	var fire_saved := false
	for entry in structure:
		if entry.get("t") == "RainCollector":
			collector_saved = int(entry.get("survival", {}).get("water", 0)) == 3
		if entry.get("t") == "Bonfire":
			fire_saved = entry.get("survival", {}).has("fuel")
	check(collector_saved and fire_saved, "Built fire fuel and collected water join the normal save records")
	player.call("_toggle_build")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	current_scene.add_child(floor_body)
	floor_body.position = Vector3(1000, 3.5, 1000)
	var stairs := (load("res://scenes/stairs.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(stairs)
	stairs.position = Vector3(1000, 4.1, 1000)
	player.global_position = Vector3(1000, 4.92, 999.25)
	player.velocity = Vector3.ZERO
	await frames(3)
	for i in range(15):
		await physics_frame
		player.velocity = Vector3(0, -2, 0)
		player.move_and_slide()
	var start_y := player.position.y
	check(player.is_on_floor(), "Movement fixture starts with the player grounded")
	var maximum := start_y
	player.velocity.y = player.JUMP_VELOCITY
	for i in range(70):
		await physics_frame
		player.velocity.y -= player.GRAVITY / 60.0
		player.move_and_slide()
		maximum = maxf(maximum, player.position.y)
	check(maximum - start_y > 0.40 and maximum - start_y < 0.65, "Actual land jump rises about half a metre")
	player.global_position = Vector3(1000, 4.92, 999.25)
	player.velocity = Vector3.ZERO
	await frames(3)
	for i in range(185):
		await physics_frame
		player.velocity = Vector3(0, -2, 2.4)
		player.call("_try_step_up")
		player.move_and_slide()
		if player.position.z >= 1003.25:
			break
	print("STAIR ASCENT ", player.position)
	check(player.position.z > 1003.05 and player.position.y > 7.2, "Player walks to the stair landing without jumping")
	for i in range(185):
		await physics_frame
		player.velocity = Vector3(0, -2, -2.4)
		player.move_and_slide()
	check(player.position.z < 1000.0 and player.position.y < 5.1, "Player walks back down the stairs")
	stairs.rotation.y = PI / 2.0
	player.global_position = Vector3(999.25, 4.92, 1000)
	player.velocity = Vector3.ZERO
	await frames(3)
	for i in range(185):
		await physics_frame
		player.velocity = Vector3(2.4, -2, 0)
		player.call("_try_step_up")
		player.move_and_slide()
		if player.position.x >= 1003.25:
			break
	print("ROTATED ASCENT ", player.position)
	check(player.position.x > 1003.05 and player.position.y > 7.2, "Rotated stairs are also walkable")
	var rain := player.get_node("RainSystem")
	rain.call("start_rain", 120.0)
	var time_of_day := current_scene.get_node("Sky3D/TimeOfDay")
	var clock_before := float(time_of_day.get("current_time"))
	var rain_before := float(rain.get("_rain_remaining"))
	paused = true
	await create_timer(0.5, true).timeout
	check(is_equal_approx(float(time_of_day.get("current_time")), clock_before), "Daylight stops during pause")
	check(is_equal_approx(float(rain.get("_rain_remaining")), rain_before), "Rain duration stops during pause")
	paused = false
	await frames(3)
	check(float(time_of_day.get("current_time")) - clock_before < 0.01, "Resuming does not skip the paused minutes")
	check(is_equal_approx(float(time_of_day.get("minutes_per_day")), 18.0), "Default day lasts eighteen active minutes")
	var pot := (load("res://scenes/planter_pot.tscn") as PackedScene).instantiate()
	current_scene.add_child(pot)
	pot.position = Vector3(1008, 4.3, 1005)
	pot.set_process(false)
	pot.moisture = 0.0
	check(is_equal_approx(pot.growth_factor(), 0.25), "Dry soil slows growth without killing a legacy crop")
	check(pot.water_soil() and pot.moisture > 0.7, "A portion of fresh water restores soil moisture")
	pot.moisture = 0.0
	await frames(3)
	pot.call("_process", 2.0)
	check(pot.moisture > 0.09, "Rain waters exposed soil")
	check(pot.plant_seed("Tomato"), "Tomato seeds grow in existing small planters")
	var plant := pot.get("_plant") as Node
	plant.set_process(false)
	plant.set("_stage", 3)
	plant.call("_rebuild_visual")
	var seeds_before := int(inv.call("total", "Tomato Seed"))
	plant.call("_do_dig")
	await create_timer(0.5).timeout
	check(int(inv.call("total", "Tomato")) >= 2 and int(inv.call("total", "Tomato Seed")) == seeds_before + 2, "Harvest delivers food and renewable seeds")
	var fire := (load("res://scenes/bonfire.tscn") as PackedScene).instantiate()
	current_scene.add_child(fire)
	fire.position = Vector3(1005, 4.0, 1005)
	fire.set_process(false)
	await frames(3)
	fire.call("_process", 1.1)
	check(not fire.burning, "Rain extinguishes an exposed fire")
	var roof := StaticBody3D.new()
	var roof_shape := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(4, 0.2, 4)
	roof_shape.shape = roof_box
	roof.add_child(roof_shape)
	current_scene.add_child(roof)
	roof.position = Vector3(1005, 7.0, 1005)
	await frames(3)
	check(not fire.exposed_to_rain(), "A solid roof shelters the campfire")
	fire.burning = true
	inv.call("add", "Fish", 2)
	player.set("active_item", "Fish")
	fire.call("interact_survival", player)
	check(fire.cook_remaining > 0, "Selected raw fish starts cooking")
	fire.call("_process", 12.1)
	check(int(inv.call("total", "Cooked Fish")) == 1 and int(inv.call("total", "Fish")) == 1, "Cooking exchanges exactly one raw fish for a cooked meal")
	var fire_state: Dictionary = fire.call("save_survival_state")
	fire.fuel = 0
	fire.call("restore_survival_state", fire_state)
	check(fire.fuel > 150 and fire.burning, "Saved fire state restores remaining fuel")
	var collector := (load("res://scenes/rain_collector.tscn") as PackedScene).instantiate()
	current_scene.add_child(collector)
	collector.position = Vector3(1008, 4.35, 1007)
	collector.set_process(false)
	await frames(3)
	collector.call("_process", 21.0)
	check(collector.water == 1, "An exposed collector turns twenty rain seconds into water")
	collector.call("interact_survival", player)
	check(collector.water == 0 and int(inv.call("total", "Water")) == 1, "Collecting fresh water transfers one portion")
	var saved_weather: Dictionary = rain.call("save_weather_state")
	rain.call("stop_rain")
	rain.call("restore_weather_state", saved_weather)
	check(bool(rain.call("is_raining")) and float(rain.get("_rain_remaining")) > 100, "Weather resumes from saved remaining duration")
	rain.call("stop_rain")
	var birds := current_scene.get_node("Island/IslandBirds")
	check(get_nodes_in_group("huntable_bird").size() == 4, "All four animated gulls have huntable hitboxes")
	check(birds.call("hit_bird", 0) and not birds.call("hit_bird", 0), "An arrow can kill a gull only once per flight")
	for i in range(200):
		await physics_frame
		if birds.get("_birds")[0]["state"] == "resting":
			break
	var dropped := false
	for pickup in get_nodes_in_group("debris"):
		if pickup.get("item_name") == "Raw Bird":
			dropped = true
	check(dropped, "A hunted bird falls and creates collectible raw bird food")
	inv.call("add", "Bow", 1)
	inv.call("add", "Arrow", 3)
	var equipment := player.get_node("SurvivalEquipment")
	player.set("active_item", "Bow")
	Input.action_press("interact")
	equipment.call("begin_draw")
	equipment.call("_physics_process", 0.7)
	check(float(equipment.call("get_draw_fraction")) > 0.5, "Holding HAND draws the bow")
	hud.set("_bag_open", true)
	equipment.call("_physics_process", 0.01)
	Input.action_release("interact")
	hud.set("_bag_open", false)
	equipment.call("_physics_process", 0.01)
	check(int(inv.call("total", "Arrow")) == 3 and not equipment.drawing, "Opening the bag cancels the draw without using an arrow")
	Input.action_press("interact")
	equipment.call("begin_draw")
	equipment.call("_physics_process", 1.1)
	Input.action_release("interact")
	equipment.call("_physics_process", 0.01)
	check(int(inv.call("total", "Arrow")) == 2 and equipment.get("_arrows").size() == 1, "Releasing a drawn bow spends one arrow and launches a projectile")
	player.set("active_item", "Fish")
	player.call("_update_hand_item")
	check(player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist/HandItem/HumanHand") != null, "Held fish has the human hand GLB")
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	camera.global_position = Vector3(1200, 4, 1200)
	camera.global_rotation = Vector3.ZERO
	check(not player.call("_valid_fishing_cast"), "Fishing cannot cast into the sky")
	camera.global_rotation.x = -0.5
	check(player.call("_valid_fishing_cast"), "Fishing accepts a clear ray to open ocean")
	camera.global_position = Vector3(1005, 8.0, 1005)
	camera.global_rotation.x = -PI / 2.0
	check(not player.call("_valid_fishing_cast"), "Fishing rejects a solid deck or roof before the water")
	var slots: Array = inv.get("slots")
	for i in range(slots.size()):
		slots[i] = {"item": "Stone", "count": inv.MAX_STACK}
	slots[0] = {"item": "Fish", "count": 2}
	inv.call("_recompute")
	check(not inv.call("try_exchange", {"Fish": 1}, {"Cooked Fish": 1}) and int(inv.call("total", "Fish")) == 2, "Full-bag cooking never loses a raw ingredient")
	slots[0] = {"item": "Fish", "count": 1}
	inv.call("_recompute")
	check(inv.call("try_exchange", {"Fish": 1}, {"Cooked Fish": 1}) and int(inv.call("total", "Cooked Fish")) == 1, "Cooking can reuse the slot freed by its final ingredient")
	print("SURVIVAL LOOP SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
