extends Node3D
## Activity-based chapters. Materials granted for testing never advance missions.
const UNLOCKS := {"WaterPurifier": 2, "WindGenerator": 3, "ElectricLamp": 3,
	"ElectricPurifier": 4, "Diving Tank": 4, "RescueRadio": 5}
const CHAPTERS := [
	["MAKE CAMP", "Craft a fishing rod and spear; build a campfire.", {"craft:Fishing Rod": 1, "craft:Spear": 1, "build:Bonfire": 1}],
	["SAFE WATER", "Build a Water Purifier; collect two distilled waters.", {"build:WaterPurifier": 1, "purify": 2}],
	["HARNESS THE WIND", "Build a Wind Generator and lamp; generate power.", {"build:WindGenerator": 1, "build:ElectricLamp": 1, "power": 1}],
	["POWERED CAMP", "Build an Electric Purifier; collect two powered waters.", {"build:ElectricPurifier": 1, "electric_water": 2}],
	["SEND A SIGNAL", "Build a Rescue Radio; power and transmit an SOS.", {"build:RescueRadio": 1, "signal": 1}],
	["OCEAN SURVIVOR", "Rescue signal sent. Explore, hunt and expand your camp.", {}]
]
var level := 1
var events: Dictionary = {}
var diving_tank := false
var oxygen := 100.0
var stamina := 100.0
var wetness := 0.0
var torch_fuel := 0.0
var _torch_light: OmniLight3D
var _third_torch: Node3D
var _crackle: AudioStreamPlayer3D
var _tick := 0.0
var player: CharacterBody3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	add_to_group("survival_progression")
	var saved: Variant = Inventory.loaded_meta.get("progression", {})
	if saved is Dictionary:
		restore_state(saved)
	# Existing owned/built equipment remains valid and contributes to knowledge.
	call_deferred("_recover_existing_camp")
	_torch_light = OmniLight3D.new()
	_torch_light.name = "TorchLight"
	_torch_light.light_color = Color(1,0.51,0.19)
	_torch_light.light_energy = 1.2
	_torch_light.omni_range = 5
	_torch_light.shadow_enabled = false
	_torch_light.position = Vector3(0,1.2,0)
	add_child(_torch_light)
	_third_torch = preload("res://scripts/torch_visual.gd").new()
	_third_torch.position = Vector3(0.35,0.7,-0.12)
	add_child(_third_torch)
	preload("res://scripts/rope_hand_grip.gd").attach(_third_torch,player.get_node("Body"))
	var grip := _third_torch.get_node_or_null("AnimatedHandGrip")
	if grip != null: grip.set("upright",true)
	_torch_light.hide()
	_third_torch.hide()
	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = preload("res://scripts/survival_audio.gd").fire_stream()
	_crackle.volume_db = -28
	_crackle.max_distance = 8
	add_child(_crackle)

func _recover_existing_camp() -> void:
	await get_tree().physics_frame
	for item in Inventory.ITEM_RECIPES:
		if Inventory.has(item, 1):
			record("craft:" + item)
	for piece in get_tree().get_nodes_in_group("build_surface"):
		var type := str(player.call("_find_piece_name", piece))
		if not type.is_empty():
			record("build:" + type)

func record(event: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	events[event] = mini(10000, int(events.get(event, 0)) + amount)
	var previous := level
	while level < CHAPTERS.size() and chapter_complete():
		level += 1
	if level != previous:
		player.call("_hud_toast", "LEVEL %d · %s" % [level, CHAPTERS[level - 1][0]])
	player.call("_queue_save")

func chapter_complete() -> bool:
	var needs: Dictionary = CHAPTERS[level - 1][2]
	if needs.is_empty():
		return false
	for event in needs:
		if int(events.get(event, 0)) < int(needs[event]):
			return false
	return true

func unlocked(recipe: String) -> bool:
	return level >= int(UNLOCKS.get(recipe, 1))

func objective() -> String:
	var needs: Dictionary = CHAPTERS[level - 1][2]
	for event in needs:
		var have := mini(int(events.get(event, 0)), int(needs[event]))
		if have >= int(needs[event]):
			continue
		var description := str(event).replace("craft:", "Craft ").replace("build:", "Build ")
		match event:
			"purify": description = "Collect distilled water"
			"power": description = "Generate wind electricity"
			"electric_water": description = "Collect powered water"
			"signal": description = "Transmit powered SOS"
		return "%s · %d/%d" % [description, have, int(needs[event])]
	return str(CHAPTERS[level - 1][1])

func _process(delta: float) -> void:
	var equipped := str(player.get("active_item")) == "Torch"
	var lit := equipped and torch_fuel > 0.0 and Stats.health > 0
	if lit and not _crackle.playing: _crackle.play()
	elif not lit and _crackle.playing: _crackle.stop()
	_torch_light.visible = lit
	_third_torch.visible = equipped and int(player.get("cam_mode")) == 1
	_third_torch.call("set_burning",lit)
	var held := player.get_node_or_null("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist/HandItem/Torch")
	if held != null: held.call("set_burning",lit)
	if lit: torch_fuel = maxf(0,torch_fuel-delta)
	if Stats.health <= 0.0:
		return
	_tick += delta
	if _tick < 0.25:
		return
	var step := minf(_tick, 1.0)
	_tick = 0.0
	var moving := Vector2(player.velocity.x, player.velocity.z).length()
	var swimming := bool(player.get("is_swimming"))
	var rain := get_tree().get_first_node_in_group("rain_system")
	var exposed := false
	if rain != null and rain.call("is_raining"):
		var start := player.global_position+Vector3.UP*1.8
		var ray := PhysicsRayQueryParameters3D.create(start,start+Vector3.UP*8,1,[player.get_rid()])
		exposed = player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	if equipped and torch_fuel > 0 and (swimming or exposed):
		torch_fuel = 0
		player.call("_hud_toast","TORCH WET · RELIGHT AT A SHELTERED CAMPFIRE")
	stamina = clampf(stamina + (-5.0 if swimming and moving > 1.8 else (-3.0 if moving > 4.0 else 7.0)) * step, 0, 100)
	wetness = clampf(wetness + (12.0 if swimming else (3.0 if exposed else (-3.0 if lit else -0.8))) * step, 0, 100)
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	var ocean := get_tree().current_scene.get_node_or_null("Ocean")
	var underwater := ocean != null and camera.global_position.y < float(ocean.call("get_height", camera.global_position)) - 0.30
	var breath_rate := (-1.2 if diving_tank else -5.0) if underwater else 18.0
	oxygen = clampf(oxygen + breath_rate * step, 0, 100)
	if underwater and oxygen <= 0.0:
		Stats.change_health(-8.0 * step)

func save_state() -> Dictionary:
	return {"level": level, "events": events.duplicate(), "diving_tank": diving_tank,
		"oxygen": oxygen, "stamina": stamina, "wetness": wetness, "torch_fuel": torch_fuel}

func restore_state(data: Dictionary) -> void:
	level = clampi(int(data.get("level", 1)), 1, CHAPTERS.size())
	events.clear()
	var stored: Variant = data.get("events", {})
	if stored is Dictionary:
		for key in stored:
			events[str(key)] = clampi(int(stored[key]), 0, 10000)
	diving_tank = bool(data.get("diving_tank", false))
	oxygen = clampf(float(data.get("oxygen", 100)), 10, 100)
	stamina = clampf(float(data.get("stamina", 100)), 10, 100)
	wetness = clampf(float(data.get("wetness", 0)), 0, 100)
	torch_fuel = clampf(float(data.get("torch_fuel",0)),0,900)

func use_torch() -> void:
	if bool(player.get("aim_valid")) and player.get("aim_collider") != null:
		var target := player.get("aim_collider") as Node3D
		if str(player.call("_find_piece_name",target)) == "WallTorch" and player.global_position.distance_to(target.global_position) <= 3.2:
			target.call("interact_survival",player)
			return
	if bool(player.call("mount_held_torch")): return
	if torch_fuel > 0:
		torch_fuel = 0
		player.call("_hud_toast","TORCH EXTINGUISHED")
	else:
		for fire in get_tree().get_nodes_in_group("campfire"):
			if fire.global_position.distance_to(player.global_position) < 3 and fire.get("burning") and fire.get("fuel") > 0:
				if Inventory.has("Wood",1):
					Inventory.remove("Wood",1)
					torch_fuel = 180
					player.call("_hud_toast","TORCH LIT · THREE MINUTES OF LIGHT")
					player.call("_queue_save")
					return
		player.call("_hud_toast","LIGHT AT A BURNING CAMPFIRE · NEED 1 WOOD")
	player.call("_queue_save")
