extends StaticBody3D
## Bounded active-time machine simulation; no background timers or physics loops.
const ART := preload("res://scripts/machine_visual.gd")
@export_enum("WaterPurifier", "WindGenerator", "ElectricLamp", "ElectricPurifier", "RescueRadio", "SandFilter") var machine_type := "WaterPurifier"
var fuel := 0.0
var water := 0
var seconds := 0.0
var charge := 0.0
var led_battery:=100.0
var led_cell:=true
var machine_id:=""
var wired_source:=""
var _cable: MeshInstance3D
var _cable_end:=Vector3.INF
var enabled := true
var automatic_night := true
var transmissions := 0
var _preview := false
var _sample := 0.0
var _light: OmniLight3D
var _rotor: Node3D
var _wind_head: Node3D
var _brake: Node3D
var _charge_bars: Array[Node3D] = []
var _rotor_speed := 0.0
var _wind_time := 0.0
var _wind_exposed := false
var _label: Label3D
var _power_reported := false
var _drip: Node3D
var _stored_water: Node3D
var _bulb_material: StandardMaterial3D
var fault := ""
var fault_after := 540.0
var _flicker := 0.0
const ELECTRICAL := ["WindGenerator","ElectricPurifier","RescueRadio","ElectricLamp"]

func _ready() -> void:
	if machine_id.is_empty():machine_id=machine_type+"_"+str(get_instance_id())
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
	if machine_type=="WindGenerator":
		_wind_head=visual.get_node("WindHead")
		_rotor=_wind_head.get_node("Rotor")
		_brake=visual.get_node("BrakeSwitch")
		for index in 4: _charge_bars.append(visual.get_node("ChargeBar%d"%index))
	_label = Label3D.new()
	_label.position.y = 0.85 if machine_type != "WindGenerator" else 2.15
	_label.font_size = 28
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.visibility_range_end = 5
	_label.modulate = Color(0.8, 0.89, 0.81)
	if machine_type=="WindGenerator":
		_label.position=Vector3(0,.45,-.24);_label.font_size=22;_label.pixel_size=.003
	if machine_type=="SandFilter":
		_label.position.y=1.0;_label.font_size=22;_label.pixel_size=0.002
	add_child(_label)
	if machine_type == "ElectricLamp":
		_bulb_material=visual.get_node("LEDLens").material_override
		if not _preview:add_to_group("electric_lamp")
		_light = OmniLight3D.new()
		_light.position=Vector3(0,.04,-.20)
		_light.light_color = Color(1, 0.83, 0.56)
		_light.omni_range = 12
		_light.omni_attenuation=1.25
		_light.light_energy = 1.4
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)
	_refresh_label()

func _process(delta: float) -> void:
	if _preview:
		return
	_flicker=maxf(0.0,_flicker-delta)
	if _flicker>0.0:_refresh_label()
	if machine_type in ELECTRICAL and enabled and fault.is_empty() and not _repairs_busy():
		fault_after=maxf(0.0,fault_after-minf(delta,.25))
		if fault_after<=0:develop_fault("motor" if machine_type in ["WindGenerator","ElectricPurifier"] and randf()<.25 else "contact" if randf()<.8 else "wiring")
	if _rotor != null:
		_wind_time+=delta
		var target_speed := 3.0*wind_strength() if enabled and _wind_exposed and fault!="motor" else 0.0
		_rotor_speed=move_toward(_rotor_speed,target_speed,delta*(0.7 if target_speed>_rotor_speed else 1.1))
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.global_position.distance_squared_to(global_position) < 4225:
			_rotor.rotation.z += delta*_rotor_speed
			var rain := get_tree().get_first_node_in_group("rain_system")
			var direction: Vector2 = rain.wind_direction if rain!=null else Vector2(0.4,0.15)
			_wind_head.rotation.y=lerp_angle(_wind_head.rotation.y,atan2(direction.x,direction.y)-global_rotation.y,1.0-exp(-delta*0.6))
	_sample += delta
	if _sample < 1.0:
		return
	var step := minf(_sample, 2.0)
	_sample = 0.0
	_refresh_cable()
	advance(step)
	_refresh_label()

func advance(step: float) -> void:
	# Sample even while braked/being repaired, so a moved turbine never uses
	# an old outdoor exposure result when it starts again.
	if machine_type == "WindGenerator": _wind_exposed = exposed()
	if machine_type=="ElectricLamp":
		_advance_led(step)
		return
	if not enabled or _preview or not fault.is_empty() or _repairs_busy():
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
			if _wind_exposed:
				var rate := minf(2.2,0.75*pow(wind_strength()/0.6,3.0))
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

func _advance_led(step: float) -> void:
	if _preview or _light==null or _repairs_busy():return
	if led_cell and led_battery<100 and fault!="wiring" and request_power(step*.15):led_battery=minf(100,led_battery+step*.8)
	var scene:=get_tree().current_scene
	var sky:=scene.get_node_or_null("Sky3D") if scene!=null else null
	var hour: float=float(sky.get("current_time")) if sky!=null else 0.0
	var on: bool=enabled and led_cell and led_battery>0 and fault.is_empty() and (not automatic_night or hour<6 or hour>=18)
	if on:led_battery=maxf(0,led_battery-step*100.0/1800.0)
	_light.visible=on and led_battery>0 and bool(get_meta("light_allowed",true))
	_bulb_material.emission_energy_multiplier=1.5 if _light.visible else 0.0

func request_power(amount: float) -> bool:
	if amount<=0.0 or not is_finite(amount): return false
	var source:=_wired_generator()
	# Braking stops generation; the connected storage battery still supplies power.
	if source!=null and str(source.fault).is_empty() and source.charge>=amount:
		source.charge-=amount
		return true
	return false

func _wired_generator() -> Node3D:
	if wired_source.is_empty():return null
	for source: Node3D in get_tree().get_nodes_in_group("power_source"):
		if source!=self and not source.is_queued_for_deletion() and source.machine_id==wired_source and source.global_position.distance_squared_to(global_position)<=144:return source
	return null

func _refresh_cable() -> void:
	if _preview:return
	var source:=_wired_generator()
	if source==null:
		if _cable!=null:_cable.hide()
		return
	if _cable==null:
		_cable=MeshInstance3D.new();_cable.name="InsulatedPowerCable";_cable.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cable.material_override=preload("res://scripts/object_materials.gd").worn(4,Color(.07,.08,.06),.95);add_child(_cable)
	var a:=Vector3(0,0,.12);var b:=to_local(source.to_global(Vector3(.16,.08,.1)))
	_cable.show()
	if _cable.mesh!=null and _cable_end.distance_squared_to(b)<.00001:return
	_cable_end=b
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous:=a
	for index in range(1,13):
		var t:=index/12.0
		var point:=a.lerp(b,t)-Vector3.UP*sin(t*PI)*minf(.3,a.distance_to(b)*.05)
		preload("res://scripts/fishing_net_visual.gd").strand(mesh,previous,point);previous=point
	mesh.surface_end();_cable.mesh=mesh;_cable.show()

func wind_strength() -> float:
	var rain := get_tree().get_first_node_in_group("rain_system")
	var storm := rain!=null and bool(rain.call("is_raining"))
	return clampf(0.6+sin(_wind_time*0.08)*0.09+sin(_wind_time*0.021)*0.06+(0.26 if storm else 0.0),0.35,1.0)

func _repairs_busy() -> bool:
	var actor:=get_tree().get_first_node_in_group("player")
	var repairs:=actor.get_node_or_null("EquipmentRepairs") if actor!=null else null
	return repairs!=null and (repairs.menu_open or (repairs.busy() and repairs.pending.get("target")==self))
func fault_for(_item: String="") -> String:return fault
func interaction_caption() -> String:return "REPAIR" if not fault.is_empty() else "USE"
func develop_fault(kind: String="contact") -> void:
	if machine_type not in ELECTRICAL or kind not in ["contact","wiring","motor"]:return
	fault=kind;_flicker=.9
	if _light!=null:_light.visible=false;_bulb_material.emission_energy_multiplier=0
	_refresh_label()
	var actor:=get_tree().get_first_node_in_group("player")
	if actor!=null:actor.call("_queue_save")
func clear_fault(_item: String="") -> void:
	fault="";fault_after=randf_range(540.0,900.0);_flicker=0;_refresh_label()

func exposed() -> bool:
	if machine_type == "WindGenerator":
		var space := get_world_3d().direct_space_state
		var hub := to_global(Vector3(0,1.7,0))
		# Start below the rotor: a ceiling intersecting its blades must count.
		var roof := PhysicsRayQueryParameters3D.create(to_global(Vector3(0,.35,0)),hub+Vector3.UP*8,1,[get_rid()])
		if not space.intersect_ray(roof).is_empty(): return false
		var rain := get_tree().get_first_node_in_group("rain_system")
		var wind: Vector2 = rain.wind_direction if rain!=null else Vector2(.4,.15)
		var direction := Vector3(wind.x,0,wind.y).normalized()
		if direction.length_squared()<.01: direction=Vector3.FORWARD
		var side := direction.cross(Vector3.UP).normalized()
		# Both sides and the blade tips need a clear, short wind corridor.
		# Walls built after the machine was placed stop generation too.
		for offset in [Vector3.ZERO,side*.64,-side*.64,Vector3.UP*.64,-Vector3.UP*.64]:
			var ray_start: Vector3=hub+offset
			var corridor:=PhysicsRayQueryParameters3D.create(ray_start-direction*4,ray_start+direction*4,1,[get_rid()])
			if not space.intersect_ray(corridor).is_empty(): return false
		return true
	var from := global_position + Vector3.UP * (0.77 if machine_type=="SandFilter" else 2.1)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func interact_survival(player: Node) -> void:
	if _preview:
		return
	if not fault.is_empty():
		player.get_node("EquipmentRepairs").open(self,machine_type);return
	if machine_type=="ElectricLamp" and (not led_cell or led_battery<=0):
		if not Inventory.has("Battery",1):player.call("_hud_toast","LED BATTERY EMPTY · REPLACE THE CELL OR WIRE IT TO A GENERATOR");return
		if not Inventory.try_exchange({"Battery":1},{"Used Battery":1} if led_cell else {}):player.call("_hud_toast","BAG FULL · LEAVE ROOM FOR THE OLD BATTERY");return
		led_cell=true;led_battery=100;enabled=true;automatic_night=false
		player.call("play_action","battery",1.8,global_position);player.call("_hud_toast","LED BATTERY REPLACED · 30 MINUTES OF LIGHT")
		player.call("_queue_save");_advance_led(0);_refresh_label();return
	if machine_type in ["SandFilter","WaterPurifier","ElectricPurifier"] and str(player.get("active_item"))=="Dirty Water Can":
		player.get_node("SurvivalServices").call("open_filter",self)
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
				player.call("_hud_toast", "CONNECT THE PUMP TO A CHARGED GENERATOR USING WIRE")
		"WindGenerator":
			enabled=not enabled
			player.call("play_action","brake",0.7,global_position+Vector3(0,0.2,-0.3))
			player.call("_hud_toast", "TURBINE %s · BATTERY %d%% · EQUIP WIRE TO CONNECT MACHINES" % ["RELEASED" if enabled else "BRAKED",roundi(charge/120.0*100.0)])
		"ElectricLamp":
			automatic_night=false
			enabled = not enabled
			if not enabled and _light != null:
				_light.visible = false
				_bulb_material.emission_energy_multiplier=0.0
			player.call("_hud_toast", "SALVAGED LED ON · %d%% BATTERY"%roundi(led_battery) if enabled else "SALVAGED LED OFF · BATTERY SAVED")
			_advance_led(0.0)
		"RescueRadio":
			if request_power(20):
				transmissions += 1
				_record("signal")
				player.call("_hud_toast", "SOS TRANSMITTED · RESCUE BEACON ACTIVE")
			else:
				player.call("_hud_toast", "WIRE THE RADIO TO A GENERATOR WITH 20 BATTERY CHARGE")
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
		"WindGenerator":
			_label.text = "BATTERY %d%% · %s" % [roundi(charge/120.0*100.0),"NO AIRFLOW · MOVE OUTSIDE" if not _wind_exposed else "BRAKED" if not enabled else "FULL" if charge>=120.0 else "CHARGING"]
			_brake.rotation.x=0.45 if enabled else -0.45
			for index in _charge_bars.size(): _charge_bars[index].visible=charge>float(index)*30.0 and (fault.is_empty() or (_flicker>0 and sin(_flicker*55)>0.25))
		"ElectricLamp": _label.text = "LED · %d%% · "%roundi(led_battery) + ("NO BATTERY" if not led_cell else "EMPTY · REPLACE / CHARGE" if led_battery<=0 else "ON" if enabled else "OFF")
		"RescueRadio": _label.text = "SOS SENT" if transmissions > 0 else "RADIO · NEEDS 20 CHARGE"
	if not fault.is_empty():_label.text=("LOOSE CONTACT" if fault=="contact" else "SEIZED MOTOR" if fault=="motor" else "DAMAGED WIRING")+" · USE TO REPAIR"

func save_survival_state() -> Dictionary:
	return {"fuel": fuel, "water": water, "seconds": seconds, "charge": charge,
		"enabled": enabled, "automatic_night": automatic_night, "transmissions": transmissions, "power_reported": _power_reported,"fault":fault,"fault_after":fault_after,"led_battery":led_battery,"led_cell":led_cell,"machine_id":machine_id,"wired_source":wired_source}

func restore_survival_state(data: Dictionary) -> void:
	machine_id=str(data.get("machine_id",machine_id)).left(96)
	wired_source=str(data.get("wired_source","")).left(96)
	fuel = clampf(float(data.get("fuel", 0)), 0, 200)
	water = clampi(int(data.get("water", 0)), 0, 5)
	seconds = clampf(float(data.get("seconds", 0)), 0, 20)
	charge = clampf(float(data.get("charge", 0)), 0, 120)
	var cell: Variant=data.get("led_battery",100.0)
	led_battery=clampf(float(cell),0,100) if (cell is int or cell is float) and is_finite(float(cell)) else 0.0
	led_cell=bool(data.get("led_cell",true))
	enabled = bool(data.get("enabled", true))
	automatic_night = bool(data.get("automatic_night", true))
	transmissions = clampi(int(data.get("transmissions", 0)), 0, 10000)
	_power_reported = bool(data.get("power_reported", false))
	fault=str(data.get("fault","")) if str(data.get("fault","")) in ["contact","wiring","motor"] else ""
	var clock: Variant=data.get("fault_after",540.0)
	fault_after=clampf(float(clock),30.0,900.0) if (clock is float or clock is int) and is_finite(float(clock)) else 540.0
	_refresh_label()
