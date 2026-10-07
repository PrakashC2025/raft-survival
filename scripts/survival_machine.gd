extends StaticBody3D
## Bounded active-time machine simulation; no background timers or physics loops.
const ART := preload("res://scripts/machine_visual.gd")
@export_enum("WaterPurifier", "WindGenerator", "ElectricLamp", "ElectricPurifier", "RescueRadio", "SandFilter") var machine_type := "WaterPurifier"
var fuel := 0.0
var water := 0
var seconds := 0.0
var charge := 0.0
var enabled := true
var automatic_night := true
var transmissions := 0
var _preview := false
var _sample := 0.0
var _light: OmniLight3D
var _rotor: Node3D
var _label: Label3D
var _power_reported := false
var _drip: Node3D
var _stored_water: Node3D

func _ready() -> void:
	_preview = get_parent() != null and get_parent().name == "BuildPreviewRoot"
	add_to_group("build_surface")
	if not _preview and machine_type == "WindGenerator":
		add_to_group("power_source")
	var cost: Dictionary=get_meta("construction_cost",{})
	var visual: Node3D = preload("res://scripts/sand_filter_visual.gd").create(cost.has("Metal")) if machine_type=="SandFilter" else ART.create(machine_type)
	add_child(visual)
	if machine_type=="SandFilter":
		_drip=visual.get_node("FilterDrip");_stored_water=visual.get_node("CollectedWater")
		_drip.hide();_stored_water.hide()
	_rotor = visual.get_node_or_null("Rotor")
	_label = Label3D.new()
	_label.position.y = 0.85 if machine_type != "WindGenerator" else 2.15
	_label.font_size = 28
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.visibility_range_end = 5
	_label.modulate = Color(0.8, 0.89, 0.81)
	if machine_type=="SandFilter":
		_label.position.y=1.0;_label.font_size=22;_label.pixel_size=0.002
	add_child(_label)
	if machine_type == "ElectricLamp":
		_light = OmniLight3D.new()
		_light.position.y = 0.45
		_light.light_color = Color(1, 0.83, 0.56)
		_light.omni_range = 7
		_light.light_energy = 1.6
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)
	_refresh_label()

func _process(delta: float) -> void:
	if _preview:
		return
	if _rotor != null and enabled:
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.global_position.distance_squared_to(global_position) < 4225:
			_rotor.rotation.z += delta * 2.2
	_sample += delta
	if _sample < 1.0:
		return
	var step := minf(_sample, 2.0)
	_sample = 0.0
	advance(step)
	_refresh_label()

func advance(step: float) -> void:
	if not enabled or _preview:
		return
	match machine_type:
		"SandFilter":
			var rain := get_tree().get_first_node_in_group("rain_system")
			if water<5 and rain!=null and bool(rain.call("is_raining")) and exposed():
				seconds+=step
				while seconds>=20.0 and water<5:
					seconds-=20.0
					water+=1
		"WindGenerator":
			if exposed():
				var rain := get_tree().get_first_node_in_group("rain_system")
				var rate := 1.8 if rain != null and rain.call("is_raining") else 0.75
				charge = minf(120, charge + step * rate)
				if charge >= 5.0 and not _power_reported:
					_power_reported = true
					_record("power")
		"WaterPurifier":
			if fuel > 0.0 and water < 5:
				var used := minf(fuel, step)
				fuel -= used
				seconds += used
				while seconds >= 20 and water < 5:
					seconds -= 20
					water += 1
		"ElectricPurifier":
			if water < 5 and request_power(step * 0.3):
				seconds += step
				while seconds >= 10 and water < 5:
					seconds -= 10
					water += 1
		"ElectricLamp":
			if _light != null:
				var atmosphere := get_tree().current_scene.get_node_or_null("Sky3D/TimeOfDay")
				var hour: float = atmosphere.get("current_time") if atmosphere != null else 0.0
				_light.visible = (not automatic_night or hour < 6.0 or hour >= 18.0) and request_power(step * 0.08)

func request_power(amount: float) -> bool:
	for source in get_tree().get_nodes_in_group("power_source"):
		if source == self or not source.enabled or source.global_position.distance_squared_to(global_position) > 144:
			continue
		if source.charge >= amount:
			source.charge -= amount
			return true
	return false

func exposed() -> bool:
	var from := global_position + Vector3.UP * (0.77 if machine_type=="SandFilter" else 2.1)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func interact_survival(player: Node) -> void:
	if _preview:
		return
	match machine_type:
		"SandFilter":
			if water>0:
				if Inventory.add("Water",1)==0:
					water-=1
					player.call("play_action","grab",0.6,global_position)
					player.call("_hud_toast","FILTERED RAINWATER COLLECTED")
				else: player.call("_hud_toast","BAG FULL · WATER STAYS IN THE CAN")
			else: player.call("_hud_toast","RAIN FILTER · PLACE OUTSIDE · SAND DOES NOT REMOVE OCEAN SALT")
		"WaterPurifier", "ElectricPurifier":
			if water > 0:
				if Inventory.add("Water", 1) == 0:
					water -= 1
					player.call("play_action","grab",0.65,global_position)
					_record("purify" if machine_type == "WaterPurifier" else "electric_water")
					player.call("_hud_toast", "SAFE WATER COLLECTED · DRINK OR WATER CROPS")
				else:
					player.call("_hud_toast", "BAG FULL · WATER STAYS IN THE TANK")
			elif machine_type == "WaterPurifier":
				if Inventory.has("Wood", 1) and fuel < 160:
					Inventory.remove("Wood", 1)
					fuel = minf(200, fuel + 40)
					player.call("play_action","fire",0.8,global_position)
					player.call("_hud_toast", "STILL FUELLED · ONE WOOD DISTILS TWO WATERS")
				else:
					player.call("_hud_toast", "DISTILLING · NEED WOOD TO HEAT SEAWATER")
			else:
				player.call("_hud_toast", "PUMP NEEDS A CHARGED WIND GENERATOR WITHIN 12 METRES")
		"WindGenerator":
			player.call("_hud_toast", "WIND BATTERY %d/120 · POWERS MACHINES WITHIN 12 METRES" % int(charge))
		"ElectricLamp":
			enabled = not enabled
			if not enabled and _light != null:
				_light.visible = false
			player.call("_hud_toast", "LAMP AUTO · ON AT NIGHT" if enabled and automatic_night else ("LAMP ON" if enabled else "LAMP OFF"))
		"RescueRadio":
			if request_power(20):
				transmissions += 1
				_record("signal")
				player.call("_hud_toast", "SOS TRANSMITTED · RESCUE BEACON ACTIVE")
			else:
				player.call("_hud_toast", "SOS NEEDS 20 BATTERY CHARGE WITHIN 12 METRES")
	_refresh_label()
	player.call("_queue_save")

func _record(event: String) -> void:
	var progress := get_tree().get_first_node_in_group("survival_progression")
	if progress != null:
		progress.call("record", event)

func _refresh_label() -> void:
	if _preview:
		_label.visible = false
		return
	match machine_type:
		"SandFilter":
			_label.text="RAIN FILTER · %d/5 WATER · %d%%" % [water,int(seconds/20.0*100)]
			_stored_water.visible=water>0
			_stored_water.position.y=-0.68+float(water)*0.060
			var rain := get_tree().get_first_node_in_group("rain_system")
			_drip.visible=water<5 and seconds>0 and rain!=null and bool(rain.call("is_raining")) and exposed()
		"WaterPurifier": _label.text = "STILL · %d/5 WATER · %ds FUEL" % [water, int(fuel)]
		"ElectricPurifier": _label.text = "POWERED WATER · %d/5" % water
		"WindGenerator": _label.text = "WIND BATTERY · %d/120" % int(charge)
		"ElectricLamp": _label.text = "LAMP · " + (("AUTO NIGHT" if automatic_night else "ON") if enabled else "OFF")
		"RescueRadio": _label.text = "SOS SENT" if transmissions > 0 else "RADIO · NEEDS 20 CHARGE"

func save_survival_state() -> Dictionary:
	return {"fuel": fuel, "water": water, "seconds": seconds, "charge": charge,
		"enabled": enabled, "automatic_night": automatic_night, "transmissions": transmissions, "power_reported": _power_reported}

func restore_survival_state(data: Dictionary) -> void:
	fuel = clampf(float(data.get("fuel", 0)), 0, 200)
	water = clampi(int(data.get("water", 0)), 0, 5)
	seconds = clampf(float(data.get("seconds", 0)), 0, 20)
	charge = clampf(float(data.get("charge", 0)), 0, 120)
	enabled = bool(data.get("enabled", true))
	automatic_night = bool(data.get("automatic_night", true))
	transmissions = clampi(int(data.get("transmissions", 0)), 0, 10000)
	_power_reported = bool(data.get("power_reported", false))
	_refresh_label()
