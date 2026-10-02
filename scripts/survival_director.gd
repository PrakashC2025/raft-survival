extends Node
## Survival rules use the existing inventory, ocean, player and build systems.
const RECIPES := {
	"Fishing Rod": {"Wood": 4, "Rope": 2, "Metal": 1},
	"Spear": {"Wood": 3, "Stone": 2, "Rope": 1},
	"Bow": {"Wood": 5, "Rope": 3},
	"Arrow": {"Wood": 1, "Stone": 1},
	"Water Flask": {"Plastic": 3, "Rope": 1},
	"Signal Beacon": {"Metal": 8, "Glass": 3, "Rope": 3},
	"Potato Seed": {"Potato": 1},
	"Apple Seed": {"Apple": 1},
	"Coconut Seed": {"Coconut": 1},
	"Banana Seed": {"Banana": 1},
}
var player: CharacterBody3D
var oxygen := 100.0
var fishing_time := 0.0
var fishing_origin := Vector3.ZERO
var panel: PanelContainer
var status: Label
var message: Label
var hunt_cooldown := 0.0
var fish_caught := 0
var _save_clock := 0.0
var _previous_mouse := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	var saved: Dictionary = Inventory.loaded_meta.get("survival", {})
	fish_caught = int(saved.get("fish_caught", 0))
	Stats.health = clampf(float(saved.get("health", 100.0)), 1.0, 100.0)
	Stats.hunger = clampf(float(saved.get("hunger", 100.0)), 0.0, 100.0)
	Stats.thirst = clampf(float(saved.get("thirst", 100.0)), 0.0, 100.0)
	Stats.enabled = true
	Stats.player_died.connect(_rescue)
	_build_ui()
	call_deferred("_start_expansion")
	call_deferred("_spawn_wildlife")

func save_state() -> Dictionary:
	var pos := player.global_position
	return {"health": Stats.health, "hunger": Stats.hunger, "thirst": Stats.thirst,
		"fish_caught": fish_caught, "intro_seen": intro_seen, "rescued": rescued,
		"elapsed_days": elapsed_days, "sand_patches": sand_patches, "cooking": cooking,
		"visited": world.visited if is_instance_valid(world) else [],
		"harvested": world.harvested if is_instance_valid(world) else {},
		"position": [pos.x, pos.y, pos.z]}

func _exit_tree() -> void:
	Stats.enabled = false

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var toggle := Button.new()
	toggle.text = "SURVIVAL / JOURNAL [J]"
	toggle.position = Vector2(16, 110)
	toggle.pressed.connect(_toggle)
	layer.add_child(toggle)
	status = Label.new()
	status.position = Vector2(16, 150)
	status.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	layer.add_child(status)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 182)
	panel.size = Vector2(440, maxf(160.0, get_viewport().get_visible_rect().size.y - 200.0))
	panel.custom_minimum_size = Vector2(420, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.065, 0.085, 0.96)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 10)
	panel.add_child(margin)
	var all_scroll := ScrollContainer.new()
	all_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(all_scroll)
	all_scroll.add_child(column)
	var story := Label.new()
	story.text = "AFTER THE DELUGE\nThe earthquake shattered your home island.\nYou escaped on a raft as the coast disappeared.\nSearch the remaining islands. Grow food. Stay alive.\n\nGoal: collect debris, expand your raft, plant a crop,\ncraft a rod and catch your first fish."
	column.add_child(story)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 210)
	column.add_child(scroll)
	var recipes := VBoxContainer.new()
	recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(recipes)
	for item: String in RECIPES:
		var cost: Array[String] = []
		for ingredient: String in RECIPES[item]:
			cost.append("%d %s" % [RECIPES[item][ingredient], ingredient])
		var button := Button.new()
		button.text = "%s — %s" % [item, ", ".join(cost)]
		button.pressed.connect(_craft.bind(item))
		recipes.add_child(button)
	for entry in [["Hunt: bow / spear [H]", _hunt], ["Fish: cast / reel", _fish], ["Collect seabed sand", _sand], ["Cook fish or meat near bonfire", _cook], ["Fill flask from fresh water", _fill_water], ["Eat cooked food / drink water", _consume]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		column.add_child(button)
	message = Label.new()
	message.text = "Craft from collected resources. J closes this journal."
	column.add_child(message)
	panel.hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		_hunt()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_J:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_previous_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _previous_mouse

func _say(value: String) -> void:
	if is_instance_valid(audio):
		audio.play("craft" if value.begins_with("Crafted") else "impact")
	message.text = value
	player.call("_hud_toast", value)

func _craft(item: String) -> void:
	var costs: Dictionary = RECIPES[item]
	if not Inventory.try_exchange(costs, {item: 4 if item == "Arrow" else 1}):
		_say("Missing materials or inventory space.")
		return
	_say("Crafted " + item)

func _process(delta: float) -> void:
	if intro_running:
		return
	hunt_cooldown = maxf(0.0, hunt_cooldown - delta)
	var ocean: Node = player.call("_get_ocean")
	var head: Vector3 = player.camera.global_position
	var underwater := ocean != null and head.y < float(ocean.call("get_height", head)) - 0.15
	_expansion_tick(delta, underwater)
	oxygen = clampf(oxygen + (-5.0 if underwater else 22.0) * delta, 0.0, 100.0)
	if oxygen <= 0.0:
		Stats.change_health(-10.0 * delta)
	status.text = "HEALTH %d  FOOD %d  WATER %d  AIR %d%%" % [int(Stats.health), int(Stats.hunger), int(Stats.thirst), int(oxygen)]
	if fishing_time > 0.0:
		if player.global_position.distance_to(fishing_origin) > 3.0 or underwater:
			fishing_time = 0.0
			_say("Line withdrawn: stay near your casting position.")
		else:
			fishing_time = maxf(0.0, fishing_time - delta)
			status.text += "   •   Fishing %.0fs" % fishing_time
			if fishing_time == 0.0:
				if Inventory.add("Raw Fish", 1) == 0:
					fish_caught += 1
					_say("Caught a fish! Cook it at a bonfire.")
				else:
					_say("Bag full — the fish escaped.")
	_save_clock += delta
	if _save_clock >= 20.0:
		_save_clock = 0.0
		player.call("_queue_save")

func _fish() -> void:
	if fishing_time > 0.0:
		fishing_time = 0.0
		_say("Line reeled in.")
		return
	if not Inventory.has("Fishing Rod", 1):
		_say("Craft a Fishing Rod first.")
		return
	var ocean: Node = player.call("_get_ocean")
	var target: Vector3 = player.camera.global_position - player.camera.global_basis.z * 7.0
	if ocean == null or player.is_swimming:
		_say("Cast from the raft or shoreline.")
		return
	var water_y: float = ocean.call("get_height", target)
	var query := PhysicsRayQueryParameters3D.create(Vector3(target.x, water_y + 15.0, target.z), Vector3(target.x, water_y - 1.0, target.z), 1)
	query.exclude = [player.get_rid()]
	if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_say("Face open water to cast.")
		return
	fishing_origin = player.global_position
	fishing_time = randf_range(8.0, 15.0)
	_say("Line cast. Keep still while waiting for a bite.")

func _sand() -> void:
	if not player.is_swimming or not player.aim_valid or player.aim_distance > 3.0:
		_say("Dive and aim at the seabed within 3 metres.")
		return
	var target: Node = player.aim_collider
	while target != null and not target.is_in_group("island"):
		target = target.get_parent()
	if target == null or player.aim_point.y >= -0.5:
		_say("Find submerged island terrain.")
		return
	var cell := "sand_%d_%d" % [floori(player.aim_point.x / 2.0), floori(player.aim_point.z / 2.0)]
	if sand_patches.has(cell):
		_say("This sand patch is depleted. Try another patch.")
		return
	if Inventory.add("Sand", 1) == 0:
		sand_patches[cell] = true
		_checkpoint()
		_say("Collected seabed sand.")

func _cook() -> void:
	if not cooking.is_empty():
		_say("Cooking in progress, or bag full. %.0f seconds left." % float(cooking.remaining))
		return
	if not _near_fire():
		_say("Stand within 4 metres of a bonfire.")
		return
	var raw := "Raw Fish" if Inventory.has("Raw Fish", 1) else "Raw Meat"
	if Inventory.try_exchange({raw: 1, "Wood": 1}, {}):
		cooking = {"item": "Cooked Fish" if raw == "Raw Fish" else "Cooked Meat", "remaining": 12.0}
		_say("Cooking started. Food will be ready in 12 seconds.")
		_checkpoint()
	else:
		_say("Need raw fish or meat, plus one wood.")

func _fill_water() -> void:
	if not Inventory.has("Water Flask", 1):
		_say("Craft a Water Flask first.")
		return
	# Freshwater must be explicitly tagged; ocean water is never drinkable.
	for source in get_tree().get_nodes_in_group("fresh_water"):
		if source is Node3D and absf(player.global_position.y - source.global_position.y) < 3.0 and Vector2(player.global_position.x - source.global_position.x, player.global_position.z - source.global_position.z).length() <= float(source.get_meta("water_radius", 1.0)) + 1.5:
			if Inventory.try_exchange({"Water Flask": 1}, {"Fresh Water": 1}):
				_say("Flask filled.")
			return
	_say("Find fresh water. Coconuts also restore thirst.")

func _consume() -> void:
	if Inventory.has("Fresh Water", 1) and Inventory.try_exchange({"Fresh Water": 1}, {"Water Flask": 1}):
		Stats.drink(60.0)
		_say("Drank fresh water.")
	elif Inventory.has("Cooked Fish", 1) or Inventory.has("Cooked Meat", 1):
		Inventory.remove("Cooked Fish" if Inventory.has("Cooked Fish", 1) else "Cooked Meat", 1)
		Stats.eat(45.0)
		_say("Ate cooked food.")
	elif Inventory.has("Coconut", 1):
		Inventory.remove("Coconut", 1)
		Stats.eat(20.0)
		Stats.drink(35.0)
		_say("Ate and drank a coconut.")
	else:
		_say("Need cooked fish, fresh water or a coconut.")

func _rescue() -> void:
	Stats.health = 100.0
	Stats.hunger = 60.0
	Stats.thirst = 60.0
	oxygen = 100.0
	fishing_time = 0.0
	var raft: Node3D = player.call("_get_raft_node")
	if raft != null:
		player.global_position = raft.global_position + Vector3(0, 3, 0)
	player.velocity = Vector3.ZERO
	_say("You washed back onto the raft. Your supplies survived.")

func _hunt() -> void:
	if intro_running:
		return
	if hunt_cooldown > 0.0:
		return
	hunt_cooldown = 0.8
	if player.build_mode:
		_say("Leave build mode before hunting.")
		return
	if Inventory.has("Bow", 1) and Inventory.has("Arrow", 1):
		Inventory.remove("Arrow", 1)
		var arrow := load("res://scripts/survival_arrow.gd").new() as Node3D
		arrow.set("shooter", player)
		arrow.set("velocity", -player.camera.global_basis.z * 35.0)
		get_tree().current_scene.add_child(arrow)
		arrow.global_position = player.camera.global_position - player.camera.global_basis.z * 0.6
		_say("Arrow released.")
		audio.play("bow")
	elif Inventory.has("Spear", 1):
		var origin: Vector3 = player.camera.global_position
		var query := PhysicsRayQueryParameters3D.create(origin, origin - player.camera.global_basis.z * 3.0, 1)
		query.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.has_method("hit"):
			hit.collider.hit()
			_say("Spear hit.")
		else:
			_say("Spear missed. Move within 3 metres.")
	else:
		_say("Craft a spear, or a bow and arrows.")

func _spawn_wildlife() -> void:
	var ocean: Node = player.call("_get_ocean")
	if ocean == null:
		return
	var budget := 8 if preload("res://scripts/mobile_perf.gd").mobile_like() else 12
	for i in range(budget):
		var wildlife := load("res://scripts/survival_wildlife.gd").new() as CharacterBody3D
		var kind := "Bird" if i < 4 else ("Shark" if i == budget - 1 else "Fish")
		var center := player.global_position + Vector3(25.0 * cos(i * 1.7), 0, 25.0 * sin(i * 1.7))
		center.y = float(ocean.call("get_height", center)) + (8.0 if kind == "Bird" else -3.0)
		wildlife.set("kind", kind)
		wildlife.set("home", center)
		wildlife.set("phase", float(i))
		get_tree().current_scene.add_child(wildlife)
		wildlife.global_position = center




# Campaign, exploration and persisted world state.
var audio: Node
var world: Node3D
var intro_seen := false
var intro_running := false
var rescued := false
var elapsed_days := 0.0
var cooking: Dictionary = {}
var sand_patches: Dictionary = {}
var _world_tick := 0.0
var _population_tick := 0.0
var _objective: Label

func _start_expansion() -> void:
	var saved: Dictionary = Inventory.loaded_meta.get("survival", {})
	intro_seen = bool(saved.get("intro_seen", not Inventory.loaded_meta.is_empty()))
	rescued = bool(saved.get("rescued", false))
	elapsed_days = float(saved.get("elapsed_days", 0.0))
	cooking = saved.get("cooking", {})
	sand_patches = saved.get("sand_patches", {})
	audio = load("res://scripts/survival_audio.gd").new()
	add_child(audio)
	world = load("res://scripts/survival_world.gd").new()
	world.set("director", self)
	world.set("visited", saved.get("visited", []))
	world.set("harvested", saved.get("harvested", {}))
	get_tree().current_scene.add_child(world)
	for node in get_tree().get_nodes_in_group("survival_resource"):
		if world.harvested.has(node.get_meta("resource_id", "")):
			node.hide()
	var p: Array = saved.get("position", [])
	if p.size() == 3:
		player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var column := panel.get_child(0).get_child(0).get_child(0) as VBoxContainer
	_objective = Label.new()
	column.add_child(_objective)
	for entry in [["Gather ore nearby", _gather], ["Smelt glass near a bonfire", _smelt], ["Distill seawater near a bonfire", _distill], ["Raise rescue signal at Last Signal island", _signal_rescue], ["Mute / unmute sound", _mute]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		column.add_child(button)
	for piece_name in ["Bonfire", "PlanterPot", "PlanterBox", "TreePot"]:
		var build_button := Button.new()
		build_button.text = "Build " + piece_name
		build_button.pressed.connect(_build_piece.bind(piece_name))
		column.add_child(build_button)
	var close := Button.new()
	close.text = "Close journal"
	close.pressed.connect(_toggle)
	column.add_child(close)
	if not intro_seen:
		intro_running = true
		var opening := load("res://scripts/survival_intro.gd").new() as Node3D
		opening.set("director", self)
		get_tree().current_scene.add_child(opening)
	_spawn_land_animals()

func _expansion_tick(delta: float, underwater: bool) -> void:
	if not is_instance_valid(audio) or intro_running:
		return
	audio.tick(delta, player, underwater)
	elapsed_days += delta / 900.0
	_world_tick += delta
	_population_tick += delta
	if _world_tick >= 1.0:
		_world_tick = 0.0
		world.tick(player)
		_objective.text = "DAY %d • Islands %d/3\n%s" % [1 + int(elapsed_days), world.visited.size(), "Rescue signal received. You can keep surviving." if rescued else "Rescue: explore all 3 islands, craft a Signal Beacon,\nthen activate it at Last Signal."]
	if _population_tick > 90.0:
		_population_tick = 0.0
		for animal in get_tree().get_nodes_in_group("wildlife"):
			if animal.global_position.distance_to(player.global_position) > 230.0 and animal.kind != "Boar":
				animal.queue_free()
		if get_tree().get_nodes_in_group("wildlife").size() < (10 if preload("res://scripts/mobile_perf.gd").mobile_like() else 20):
			_spawn_wildlife()
	if not cooking.is_empty():
		cooking["remaining"] = maxf(0.0, float(cooking.get("remaining", 0.0)) - delta)
		if float(cooking.remaining) <= 0.0:
			if Inventory.add(str(cooking.item), 1) == 0:
				cooking.clear()
				_say("Cooking finished. Food added to your bag.")
				_checkpoint()

func _checkpoint() -> void:
	player.call("_queue_save")

func _near_fire() -> bool:
	var raft: Node3D = player.call("_get_raft_node")
	if raft == null:
		return false
	for node in raft.find_children("*", "Node3D", true, false):
		if str(node.scene_file_path).ends_with("bonfire.tscn") and player.global_position.distance_to(node.global_position) < 4.0:
			return true
	return false

func _gather() -> void:
	_say(world.gather(player))
	_checkpoint()

func _smelt() -> void:
	if not _near_fire():
		_say("Stand near a bonfire to smelt sand.")
	elif Inventory.try_exchange({"Sand": 3, "Wood": 2}, {"Glass": 1}):
		_say("Smelted glass for your rescue beacon.")
	else:
		_say("Need 3 sand, 2 wood and bag space.")

func _distill() -> void:
	if not _near_fire() or not Inventory.has("Water Flask", 1):
		_say("Bring an empty flask to a bonfire.")
	elif Inventory.try_exchange({"Water Flask": 1, "Wood": 2}, {"Fresh Water": 1}):
		_say("Distilled seawater. Flask filled.")
	else:
		_say("Need 2 wood and inventory space.")

func _signal_rescue() -> void:
	if rescued:
		_say("Your signal is already guiding rescue. Keep exploring.")
	elif world.visited.size() < 3:
		_say("Explore all three outlying islands first.")
	elif player.global_position.distance_to(world.LOCATIONS[2]) > 20.0:
		_say("Raise the beacon at Last Signal island.")
	elif not Inventory.has("Signal Beacon", 1):
		_say("Craft a Signal Beacon: metal, glass and rope.")
	else:
		rescued = true
		Inventory.remove("Signal Beacon", 1)
		audio.play("rescue")
		_say("SIGNAL RECEIVED — rescue is coming! You survived the deluge.")
		_checkpoint()

func _mute() -> void:
	audio.set_muted(not audio.muted)
	_say("Sound muted." if audio.muted else "Sound on.")

func _spawn_land_animals() -> void:
	for location: Vector3 in world.LOCATIONS:
		for i in range(2):
			var animal := load("res://scripts/survival_wildlife.gd").new() as CharacterBody3D
			animal.set("kind", "Boar")
			animal.set("home", location + Vector3(i * 3, 3.3, 0))
			get_tree().current_scene.add_child(animal)
			animal.global_position = location + Vector3(i * 3, 3.3, 0)


func _build_piece(piece_name: String) -> void:
	_toggle()
	player.select_piece_for_build(player.BUILD_RECIPE_NAMES.find(piece_name))



