extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("FAIL: Advanced verification timed out")
		quit(1))
	call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset",true)
	root.get_node("Stats").set("enabled",false)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await frames(30)
	var player := get_first_node_in_group("player") as CharacterBody3D
	check(player != null,"Main scene loads advanced player systems")
	if player == null:
		quit(1)
		return
	player.set_physics_process(false)
	var progress := player.get_node("SurvivalProgression")
	progress.set_process(false)
	check(progress.level == 1,"Testing materials do not skip progression")
	check(not inv.call("can_afford","WaterPurifier"),"Purifier cannot be built before level 2")
	check(not inv.call("craft_item","Diving Tank"),"Locked tank never consumes crafting materials")
	check(inv.call("craft_item","Fishing Rod") and inv.call("craft_item","Spear"),"Starter equipment records actual successful crafts")
	progress.call("record","build:Bonfire")
	check(progress.level == 2 and inv.call("recipe_unlocked","WaterPurifier"),"Completing camp unlocks water level")
	var machines: Dictionary = {}
	var scene_paths := {"WaterPurifier":"water_purifier", "WindGenerator":"wind_generator", "ElectricLamp":"electric_lamp", "ElectricPurifier":"electric_purifier", "RescueRadio":"rescue_radio"}
	for kind in scene_paths:
		var machine := (load("res://scenes/" + scene_paths[kind] + ".tscn") as PackedScene).instantiate() as Node3D
		current_scene.add_child(machine)
		machine.position = Vector3(1000,10,1000) + Vector3(machines.size(),0,0)
		machine.set_process(false)
		machines[kind] = machine
		check(machine.has_method("interact_survival") and machine.get_node("BuildSockets/Socket_Base") != null,"Playable machine and building socket: "+kind)
	await frames(3)
	var still: Node = machines.WaterPurifier
	progress.call("record","build:WaterPurifier")
	var wood_before := int(inv.call("total","Wood"))
	still.call("interact_survival",player)
	check(still.fuel == 40 and int(inv.call("total","Wood")) == wood_before-1,"Still uses exactly one wood for forty seconds")
	still.call("advance",40.0)
	check(still.water == 2 and still.fuel == 0,"Seawater still distils two safe portions per wood")
	still.call("interact_survival",player)
	still.call("interact_survival",player)
	check(progress.level == 3 and int(inv.call("total","Water")) == 2,"Water mission advances only after collecting two portions")
	var generator: Node = machines.WindGenerator
	progress.call("record","build:WindGenerator")
	progress.call("record","build:ElectricLamp")
	generator.call("advance",10.0)
	check(generator.charge > 5 and progress.level == 4,"Exposed turbine generates charge and completes electricity mission")
	var pump: Node = machines.ElectricPurifier
	progress.call("record","build:ElectricPurifier")
	generator.charge = 100
	pump.call("advance",20.0)
	check(pump.water == 2 and is_equal_approx(generator.charge,94.0),"Electric purifier consumes six charge for two portions")
	pump.call("interact_survival",player)
	pump.call("interact_survival",player)
	check(progress.level == 5,"Powered-water collection unlocks rescue level")
	inv.call("add","Cooked Meat",1)
	for slot in range(6,30):
		if inv.call("slot_item",slot) == "Cooked Meat":
			inv.call("drop_into",slot,0)
			break
	player.call("select_hotbar_slot",0)
	root.get_node("Stats").set("hunger",25.0)
	player.call("_handle_selected_item_use")
	check(root.get_node("Stats").hunger == 59 and not inv.call("has","Cooked Meat",1),"Eating the final equipped meat portion refreshes safely and restores configured hunger")
	var radio: Node = machines.RescueRadio
	progress.call("record","build:RescueRadio")
	generator.charge = 19
	radio.call("interact_survival",player)
	check(radio.transmissions == 0 and generator.charge == 19,"Radio refuses an undercharged SOS without spending energy")
	generator.charge = 25
	radio.call("interact_survival",player)
	check(radio.transmissions == 1 and generator.charge == 5 and progress.level == 6,"Charged radio transmits SOS and finishes chapter sequence")
	var lamp: Node = machines.ElectricLamp
	current_scene.get_node("Sky3D/TimeOfDay").set("current_time",22.0)
	lamp.call("advance",1.0)
	check(lamp.get("_light").visible,"Automatic powered lamp illuminates the camp at night")
	lamp.call("interact_survival",player)
	check(not lamp.enabled and not lamp.get("_light").visible,"Turning lamp off immediately stops light")
	pump.position.x += 20
	generator.charge = 50
	var before := int(pump.water)
	pump.call("advance",20.0)
	check(pump.water == before and generator.charge == 50,"Distant machines cannot consume another camp's electricity")
	var saved_generator: Dictionary = generator.call("save_survival_state")
	generator.charge = 0
	generator.call("restore_survival_state",saved_generator)
	check(generator.charge == 50,"Battery charge survives machine restoration")
	var slots: Array = inv.get("slots")
	var original: Array = slots.duplicate(true)
	for i in range(slots.size()):
		slots[i] = {"item":"Stone","count":2000}
	inv.call("_recompute")
	still.water = 1
	still.call("interact_survival",player)
	check(still.water == 1,"Full inventory preserves finished purifier water")
	inv.set("slots",original)
	inv.call("_recompute")
	check(inv.call("craft_item","Diving Tank"),"Unlocked diving tank has a capacity-safe recipe")
	player.set("active_item","Diving Tank")
	player.call("_handle_selected_item_use")
	check(progress.diving_tank and int(inv.call("total","Diving Tank")) == 0,"Tank equips persistently without a repeat cost")
	var saved_progress: Dictionary = progress.call("save_state")
	progress.call("restore_state",{})
	check(progress.level == 1 and progress.oxygen == 100,"Legacy saves initialize healthy optional condition state")
	progress.call("restore_state",saved_progress)
	check(progress.level == 6 and progress.diving_tank,"Levels, mission counters and diving equipment restore")
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	player.position = Vector3(1200,10,1200)
	camera.global_position = Vector3(1200,-4,1200)
	progress.oxygen = 50
	progress.call("_process",1.0)
	check(progress.oxygen < 50 and progress.oxygen > 48,"Tank slows actual underwater breath consumption")
	progress.diving_tank = false
	progress.oxygen = 1
	var stats := root.get_node("Stats")
	var health_before := float(stats.health)
	progress.call("_process",1.0)
	check(progress.oxygen == 0 and stats.health < health_before,"Staying submerged without air damages health")
	camera.global_position.y = 10
	progress.call("_process",1.0)
	check(progress.oxygen > 0,"Surfacing restores air")
	var boar: CharacterBody3D = load("res://scripts/survival_animal.gd").new()
	boar.species = "Boar"
	current_scene.add_child(boar)
	boar.position = Vector3(1100,10,1100)
	boar.home = boar.position
	boar.set_physics_process(false)
	check(boar.health == 60 and boar.get_child_count() >= 2,"Original boar GLB and hunting collision load")
	boar.call("take_damage",30.0,player)
	check(boar.alarm > 0 and boar.health == 30,"Wounding a boar triggers threatened behaviour")
	boar.call("take_damage",30.0,player)
	await frames(2)
	check(boar.respawn > 0 and not boar.visible,"Hunted animal dies once and starts bounded recovery")
	var loot := false
	for drop in get_nodes_in_group("debris"):
		if drop.get("item_name") == "Raw Meat":
			loot = true
	check(loot,"Hunting creates collectible meat rewards")
	var saved_animal: Dictionary = boar.call("save_state")
	boar.call("restore_state",saved_animal)
	check(not boar.visible and boar.collision_layer == 0,"Dead-animal save restore cannot duplicate hunting rewards")
	# Every new machine must use the actual preview/cost/placement path.
	check(inv.call("craft_item","Torch"),"Torch crafts through the capacity-safe equipment recipe")
	for slot in range(6,30):
		if inv.call("slot_item",slot) == "Torch":
			inv.call("drop_into",slot,0)
			break
	player.call("select_hotbar_slot",0)
	progress.torch_fuel = 0
	progress.call("use_torch")
	check(progress.torch_fuel == 0,"Torch cannot light spontaneously away from fire")
	var fire := (load("res://scenes/bonfire.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(fire)
	fire.global_position = player.global_position+Vector3(1,0,0)
	fire.set_process(false)
	fire.set("burning",true)
	fire.set("fuel",100.0)
	wood_before = int(inv.call("total","Wood"))
	player.set("aim_valid",true);player.set("aim_collider",fire);player.set("aim_point",fire.global_position)
	progress.call("use_torch")
	check(progress.torch_fuel > 0 and int(inv.call("total","Wood")) == wood_before and inv.call("has","Burning Torch",1),"Aimed fire lights a Burning Torch until dawn without an extra crafting charge")
	var lit_fuel: float=progress.torch_fuel
	progress.call("_process",0.5)
	check(progress.torch_fuel <= lit_fuel and progress.get("_torch_light").visible,"Held Burning Torch follows the clock and casts nearby light")
	player.set("is_swimming",true)
	progress.call("_process",0.5)
	check(progress.torch_fuel == 0,"Immersing torch extinguishes its flame")
	player.set("is_swimming",false)
	var collector := (load("res://scenes/rain_collector.tscn") as PackedScene).instantiate() as Node3D
	current_scene.add_child(collector)
	collector.position = Vector3(1400,10,1400)
	collector.set_process(false)
	collector.call("restore_survival_state",{"water":12,"seconds":7.0})
	check(collector.get("water") == 12,"Rain barrel stores twelve portions with legacy-safe restore")
	collector.call("interact_survival",player)
	check(collector.get("water") == 11 and collector.call("save_survival_state")["water"] == 11,"Collecting rainwater reduces saved storage exactly once")
	var birds := current_scene.get_node_or_null("IslandBirds")
	if birds == null:
		for candidate in current_scene.find_children("*","Node3D",true,false):
			if candidate.has_method("flight_position"): birds = candidate; break
	check(birds != null,"Ocean-travelling gull flock exists")
	if birds != null:
		var bird_data: Dictionary = birds.get("_birds")[0]
		var near: Vector3 = birds.call("flight_position",bird_data,0.0)
		var far: Vector3 = birds.call("flight_position",bird_data,110.0)
		check(near.distance_to(far) > 50,"Birds travel over the sea beyond their feeding circle")
	var intro := load("res://scripts/flooded_world_intro.gd").new() as Control
	root.add_child(intro)
	intro.call("_process",0.016)
	var skip_touch := InputEventScreenTouch.new()
	skip_touch.pressed = true
	skip_touch.position = intro.get("_skip").get_global_rect().get_center()
	intro.call("_input",skip_touch)
	check(intro.get("complete"),"Opening story Skip completes safely")
	intro.queue_free()
	var raft := current_scene.get_node("Raft") as Node3D
	raft.set_physics_process(false)
	var built := raft.get_node("BuiltPieces")
	# A continuous path to the raft is required, just as in real construction.
	for cell_x in range(1, 12):
		var support_tile := (load("res://scenes/foundation.tscn") as PackedScene).instantiate() as Node3D
		support_tile.name = "Foundation_AdvancedFixture_"+str(cell_x)
		built.add_child(support_tile)
		support_tile.global_transform = player.call("_compute_foundation_transform",Vector2i(cell_x,0))
		support_tile.add_to_group("build_surface")
		player.call("_grid_register",Vector2i(cell_x,0),support_tile)
	for index in range(11,16):
		var foundation := built.get_node("Foundation_AdvancedFixture_"+str((index-10)*2)) as Node3D
		await frames(2)
		player.global_position = foundation.global_position+Vector3(0,2,4)
		player.call("select_piece_for_build",index)
		camera.global_position = foundation.global_position+Vector3(0,3,4)
		camera.look_at(foundation.global_position)
		player.set("aim_valid",true)
		player.set("aim_collider",foundation)
		player.set("aim_normal",Vector3.UP)
		player.set("aim_point",foundation.global_position+Vector3.UP*0.15)
		player.call("_update_build_preview")
		if not player.build_valid:
			print("MACHINE PREVIEW DIAGNOSTIC ", player.get("_diag"))
		var kind: String = player.BUILD_RECIPE_NAMES[index]
		check(player.build_valid,"Real supported machine preview: "+kind)
		var metal_before := int(inv.call("total","Metal"))
		if player.build_valid:
			player.call("_try_build")
		var placed := built.find_child(kind+"_*",false,false)
		check(placed != null and int(inv.call("total","Metal")) == metal_before-int(inv.RECIPES[kind].get("Metal",0)),"Real placement spends exact recipe: "+kind)
		if placed != null:
			placed.set_process(false)
			placed.set("charge",41.0)
			placed.set("water",3)
			placed.set("fuel",55.0)
			placed.set("seconds",4.0)
	if player.build_mode:
		player.call("_toggle_build")
	progress.diving_tank = true
	player.call("_write_save","main")
	var save: Dictionary = inv.call("save_info")
	check(save.has("progression") and save.has("wildlife"),"New state joins the owner's existing save format")
	inv.call("load_game")
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await frames(20)
	player = get_first_node_in_group("player") as CharacterBody3D
	check(player.get_node("SurvivalProgression").level == 6 and player.get_node("SurvivalProgression").diving_tank,"Actual Continue restores completed missions and diving equipment")
	var restored := current_scene.get_node("Raft/BuiltPieces")
	for kind in scene_paths:
		var machine := restored.find_child(kind+"_*",false,false)
		check(machine != null and machine.get("water") == 3 and machine.get("charge") >= 40 and machine.get("fuel") == 55,"Actual Continue restores machine state: "+kind)
	var ambient := current_scene.get_node_or_null("OceanAmbience")
	if ambient != null:
		ambient.call("stop_environment")
	await frames(3)
	print("ADVANCED SURVIVAL SMOKE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
