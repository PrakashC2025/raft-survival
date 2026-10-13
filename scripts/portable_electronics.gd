extends Node
## Portable solar tools. Battery state is stored separately from stackable spare cells.
const TOOLS := ["Solar Torch","Binoculars","Walkie Talkie","ElectricLamp"]
const POWERED := ["Solar Torch","Walkie Talkie","ElectricLamp"]
const AUDIO := preload("res://scripts/survival_audio.gd")
var charge := {"Solar Torch":100.0,"Walkie Talkie":100.0,"ElectricLamp":100.0}
var installed := {"Solar Torch":true,"Walkie Talkie":true,"ElectricLamp":true}
var enabled := {"Solar Torch":false,"Walkie Talkie":false,"ElectricLamp":false}
var solar := false
var zoomed := false
var cover_open := false
var faults: Dictionary={"Solar Torch":"","Walkie Talkie":"","ElectricLamp":""}
var fault_after: Dictionary={"Solar Torch":300.0,"Walkie Talkie":420.0,"ElectricLamp":540.0}
var _flicker:=0.0
var _repair_button: Button
var _shake_button: Button
var battery_animation := 0.0
var battery_operation := ""
var _battery_item := ""
var _reply := 0.0
var _radio_cooldown := 0.0
var _solar_tick := 1.0
var _normal_fov := 75.0
var player: CharacterBody3D
var beam: SpotLight3D
var led: OmniLight3D
var _mount: Button
var _audio: AudioStreamPlayer
var _ui: CanvasLayer
var _panel: PanelContainer
var _buttons: VBoxContainer
var _status: Label
var _power: Button
var _cover: Button
var _remove: Button
var _replace: Button
var _solar_button: Button
var _desktop_cursor := false
var _ui_tick := 0.0
var _visuals: Array[Dictionary] = []
var _first_root: Node3D
var _third_root: Node3D
var _hand_generation := 0

func _ready() -> void:
	player=get_parent() as CharacterBody3D
	restore_state(Inventory.loaded_meta.get("electronics",{}))
	beam=SpotLight3D.new()
	beam.name="SolarFlashlightBeam"
	beam.light_color=Color(0.94,0.97,1)
	beam.light_energy=3.0
	beam.spot_range=32
	beam.spot_angle=28
	beam.spot_attenuation=1.2
	beam.shadow_enabled=false
	player.get_node("CamPivot/SpringArm3D/Camera3D").add_child(beam)
	beam.position=Vector3(0.16,-0.12,-0.25)
	beam.hide()
	led=OmniLight3D.new();led.name="HeldSalvagedLED";led.light_color=Color(1,.87,.65);led.light_energy=1.4;led.omni_range=12;led.omni_attenuation=1.25
	led.shadow_enabled=false;led.position=Vector3(.16,-.10,-.30);player.get_node("CamPivot/SpringArm3D/Camera3D").add_child(led);led.hide()
	_audio=AudioStreamPlayer.new();_audio.volume_db=-12;add_child(_audio)
	_build_ui()

func _build_ui() -> void:
	_ui=CanvasLayer.new();_ui.layer=8;add_child(_ui)
	_panel=PanelContainer.new();_panel.name="PortableToolControls"
	_panel.theme=preload("res://scripts/ocean_ui.gd").theme()
	_panel.add_theme_stylebox_override("panel",preload("res://scripts/ocean_ui.gd").box(Color("092333"),Color("346073"),14))
	_ui.add_child(_panel)
	_buttons=VBoxContainer.new();_buttons.add_theme_constant_override("separation",6);_panel.add_child(_buttons)
	_status=Label.new();_status.add_theme_font_size_override("font_size",16);_buttons.add_child(_status)
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_power=_button("POWER ON / OFF",toggle_power)
	_mount=_button("MOUNT / PLACE LED",func():
		if str(player.active_item)=="ElectricLamp" and not _blocked():player.select_piece_for_build(player.BUILD_RECIPE_NAMES.find("ElectricLamp")))
	_solar_button=_button("RAISE PANEL TO SUN",raise_solar)
	_cover=_button("OPEN BATTERY COVER",toggle_cover)
	_remove=_button("REMOVE BATTERY",func():battery_action("remove"))
	_replace=_button("INSERT / REPLACE BATTERY",func():battery_action("replace"))
	_repair_button=_button("REPAIR · VIEW PARTS",func():player.get_node("EquipmentRepairs").open(self,str(player.active_item)))
	_shake_button=_button("SHAKE LOOSE CONTACT",func():player.get_node("EquipmentRepairs").start("shake",self,str(player.active_item)))
	_panel.hide()

func _button(label: String,action: Callable) -> Button:
	var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(250,48)
	button.add_theme_font_size_override("font_size",14)
	button.pressed.connect(func():
		GameSettings.release_gameplay_input()
		action.call());_buttons.add_child(button)
	return button

func _blocked() -> bool:
	var hud:=player.get_node_or_null("CanvasLayer/SurvivalHUD")
	return get_tree().paused or GameSettings.is_open or bool(player.get("build_mode")) \
		or player.get("_editing")!=null or player.get_node("SurvivalServices").busy() or player.get_node("SurvivalServices").is_modal() or (hud!=null and hud.call("gameplay_input_blocked"))

func use() -> void:
	var item:=str(player.get("active_item"))
	if _blocked() or not Inventory.has(item,1):return
	if not fault_for(item).is_empty():
		if fault_for(item)=="contact":player.get_node("EquipmentRepairs").start("shake",self,item)
		else:player.get_node("EquipmentRepairs").open(self,item)
		return
	if item=="Binoculars":set_zoom(not zoomed)
	elif item in ["Solar Torch","ElectricLamp"]:toggle_power()
	elif item=="Walkie Talkie":
		if not enabled[item]:toggle_power();return
		if not installed[item] or float(charge[item])<=0.0:player.call("_hud_toast","BATTERY EMPTY · CHARGE IN SUNLIGHT OR REPLACE");return
		if _radio_cooldown>0:return
		_radio_cooldown=5.0
		_reply=2.4
		_sound("radio_send")
		player.call("play_action","radio",0.9)
		player.call("_hud_toast","CH 16 · TRANSMITTING LOCATION SIGNAL")
		player.call("_queue_save")

func toggle_power() -> void:
	var item:=str(player.get("active_item"))
	if item not in POWERED or _blocked() or cover_open or battery_animation>0.0 or not Inventory.has(item,1):return
	if not installed[item] or float(charge[item])<=0.0:
		player.call("_hud_toast","INSERT A CHARGED BATTERY" if item=="ElectricLamp" else "INSERT A CHARGED BATTERY OR RAISE THE PANEL TO SUNLIGHT");return
	enabled[item]=not enabled[item]
	_sound("switch")
	player.call("play_action","switch",0.35)
	player.call("_queue_save")

func set_zoom(value: bool) -> void:
	if zoomed==value:return
	var camera:=player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	if value:
		player.get_node("SurvivalEquipment").call("set_aiming",false)
		_normal_fov=camera.fov
		camera.fov=18.0
		player.call("play_action","look",0.6)
	else:camera.fov=_normal_fov
	zoomed=value

func toggle_cover() -> void:
	if _blocked() or battery_animation>0 or str(player.active_item) not in POWERED:return
	cover_open=not cover_open
	if cover_open:enabled[str(player.active_item)]=false
	_sound("switch")
	player.call("play_action","battery",0.65)

func raise_solar() -> void:
	if _blocked() or battery_animation>0:return
	player.call("play_action","solar",1.2)
	_solar_tick=1.0
	player.call("_hud_toast","SOLAR CHARGING · FULL IN FOUR MINUTES OF DIRECT SUN" if _sun_exposed() else "NEED DAYLIGHT AND AN OPEN VIEW OF THE SUN")

func battery_action(operation: String) -> bool:
	var item:=str(player.get("active_item"))
	if item not in POWERED or _blocked() or not cover_open or battery_animation>0:return false
	if operation=="remove" and not installed[item]:return false
	var replacement := "Battery" if Inventory.has("Battery",1) else "Used Battery"
	if operation=="replace" and not Inventory.has(replacement,1):player.call("_hud_toast","CRAFT A BATTERY FIRST");return false
	# An inserted charged cell is exchanged for the old spent/partial cell atomically.
	var rewards: Dictionary={"Used Battery":1} if installed[item] else {}
	if operation=="remove" and float(charge[item])>=99.9:rewards={"Battery":1}
	if not Inventory.try_exchange({replacement:1} if operation=="replace" else {},rewards):
		player.call("_hud_toast","BAG FULL · LEAVE ROOM FOR THE REMOVED BATTERY");return false
	installed[item]=operation=="replace"
	charge[item]=100.0 if installed[item] and replacement=="Battery" else 0.0
	enabled[item]=false
	_battery_item=item
	battery_operation=operation
	battery_animation=1.8
	_sound("battery")
	player.call("play_action","battery",1.8)
	player.call("_queue_save")
	return true

func _sun_exposed() -> bool:
	var scene:=get_tree().current_scene
	if scene==null:return false
	var sky:=scene.get_node_or_null("Sky3D")
	if sky==null or bool(player.get("is_swimming")):return false
	var hour:=float(sky.get("current_time"))
	if hour<6.5 or hour>17.5:return false
	var rain:=get_tree().get_first_node_in_group("rain_system")
	if rain!=null and rain.call("is_raining"):return false
	var origin: Vector3=player.get_node("CamPivot").global_position+Vector3.UP*.05
	var sun:=sky.find_child("SunLight",true,false) as DirectionalLight3D
	var toward:=sun.global_basis.z if sun!=null else Vector3.UP
	if toward.y<=0.1:return false
	var hit:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+toward*80,1,[player.get_rid()]))
	return hit.is_empty()

func _process(delta: float) -> void:
	# Scene transitions briefly clear current_scene before the player exits.
	var scene:=get_tree().current_scene
	if scene==null:return
	var item:=str(player.get("active_item"))
	var blocked:=_blocked()
	if not blocked:
		_flicker=maxf(0.0,_flicker-delta)
		if item in POWERED and enabled[item] and installed[item] and float(charge[item])>0 and fault_for(item).is_empty():
			fault_after[item]=maxf(0.0,float(fault_after[item])-minf(delta,.25))
			if float(fault_after[item])<=0.0:develop_fault(item,"contact" if randf()<.8 else "wiring")
	if zoomed and (item!="Binoculars" or blocked):set_zoom(false)
	_solar_tick+=delta
	if _solar_tick>=0.5:_solar_tick=0.0;solar=_sun_exposed()
	var sky:=scene.get_node_or_null("Sky3D")
	var day_seconds:=absf(float(sky.get("minutes_per_day")))*60.0 if sky!=null else 1440.0
	if day_seconds<1:day_seconds=1440.0
	advance_power(delta,day_seconds,solar)
	beam.visible=item=="Solar Torch" and working(item) and not blocked
	led.visible=item=="ElectricLamp" and working(item) and not blocked
	if battery_animation>0.0:
		battery_animation=maxf(0,battery_animation-delta)
		if battery_animation==0.0:cover_open=false;battery_operation=""
	_radio_cooldown=maxf(0,_radio_cooldown-delta)
	if _reply>0.0:
		_reply=maxf(0,_reply-delta)
		if _reply==0.0 and working("Walkie Talkie"):
			_sound("radio_receive")
			var nearest: Node3D
			var distance_value:=INF
			for island in get_tree().get_nodes_in_group("island"):
				var distance_to:=player.global_position.distance_to(island.global_position)
				if distance_to<distance_value:nearest=island;distance_value=distance_to
			var location:=str(nearest.get("map_label")) if nearest!=null else "open ocean"
			player.call("_hud_toast","CH 16 · SIGNAL RECEIVED: "+location.to_upper()+" · %d M"%int(distance_value))
	_ui_tick+=delta
	var update_text:=_ui_tick>=.1
	if update_text:_ui_tick=0.0
	_update_visuals(item,update_text)
	_panel.visible=item in POWERED and Inventory.has(item,1) and not blocked
	if _panel.visible and update_text:
		var ui_scale:=preload("res://scripts/ocean_ui.gd").scale_for(get_viewport())
		_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_panel.scale=Vector2.ONE*ui_scale
		_panel.size=Vector2(278,0)
		_panel.position=Vector2(get_viewport().get_visible_rect().size.x-(_panel.size.x+20)*ui_scale,80*ui_scale)
		var status_text:=("RADIO CH 16" if item=="Walkie Talkie" else "SALVAGED LED" if item=="ElectricLamp" else "SOLAR FLASHLIGHT")+" · "+("ON" if enabled[item] else "OFF")+"\n"+("BATTERY %d%%"%roundi(float(charge[item])) if installed[item] else "NO BATTERY")+(" · SOLAR ☀" if solar and item!="ElectricLamp" else "")
		if _status.text!=status_text:_status.text=status_text
		var fault:=fault_for(item)
		if not GameSettings.mobile_effects_profile():_status.text+="\nHold Alt to use these controls"
		if not fault.is_empty():_status.text+="\n"+("LOOSE CONTACT · SHAKE / REPAIR" if fault=="contact" else "WIRING DAMAGED · REPAIR")
		_repair_button.visible=not fault.is_empty();_shake_button.visible=fault=="contact"
		_mount.visible=item=="ElectricLamp" and fault.is_empty()
		_solar_button.visible=fault.is_empty() and item!="ElectricLamp";_cover.visible=fault.is_empty()
		_power.text="POWER OFF" if enabled[item] else "POWER ON"
		_cover.text="CLOSE BATTERY COVER" if cover_open else "OPEN BATTERY COVER"
		_mount.disabled=battery_animation>0 or cover_open
		_power.disabled=battery_animation>0 or cover_open
		_remove.visible=cover_open and fault.is_empty();_replace.visible=cover_open and fault.is_empty()
		_remove.disabled=battery_animation>0 or not installed[item]
		_replace.disabled=battery_animation>0

func advance_power(seconds: float,day_seconds: float,in_sun: bool) -> void:
	for item in POWERED:
		if not Inventory.has(item,1) or not installed[item]:continue
		# Only the exposed held panel charges; an enclosed backpack cannot collect sunlight.
		if item!="ElectricLamp" and in_sun and str(player.get("active_item"))==item and fault_for(item)!="wiring":
			charge[item]=minf(100,float(charge[item])+seconds*100.0/240.0)
		elif enabled[item]:
			var lifetime:=day_seconds*30.0 if item=="Walkie Talkie" else 1800.0
			charge[item]=maxf(0,float(charge[item])-seconds*100.0/maxf(lifetime,1))
		if float(charge[item])<=0.000001:charge[item]=0.0;enabled[item]=false

func fault_for(item: String) -> String:return str(faults.get(item,""))
func working(item: String) -> bool:
	if item not in POWERED:return false
	var fault:=fault_for(item)
	var contact_on:=fault.is_empty() or (fault=="contact" and _flicker>0 and sin(_flicker*55.0)>0.25)
	return enabled[item] and installed[item] and float(charge[item])>0.0 and contact_on
func develop_fault(item: String, fault: String="contact") -> void:
	if item not in POWERED or fault not in ["contact","wiring"]:return
	faults[item]=fault;_flicker=.9;_reply=0.0
	_sound("battery");player.call("_hud_toast",item.to_upper()+" · "+("LOOSE CONTACT · SHAKE OR REPAIR" if fault=="contact" else "DAMAGED WIRING · REPAIR REQUIRED"))
	player.call("_queue_save")
func clear_fault(item: String) -> void:
	if item not in POWERED:return
	faults[item]="";fault_after[item]=randf_range(420.0,720.0);_flicker=0;_sound("switch")

func _update_visuals(item: String,update_text: bool=true) -> void:
	var hand:=player.get("_hand_item") as Node3D
	var action:=player.get_node_or_null("SurvivalAction")
	var third:=action.get("_held") as Node3D if action!=null else null
	var generation:=hand.get_child(hand.get_child_count()-1).get_instance_id() if is_instance_valid(hand) and hand.get_child_count()>0 else 0
	if hand!=_first_root or third!=_third_root or generation!=_hand_generation:
		_first_root=hand;_third_root=third;_visuals.clear()
		_hand_generation=generation
		_cache_visual(hand);_cache_visual(third)
	for parts in _visuals:
		var lens:=parts.get("lens") as MeshInstance3D
		if is_instance_valid(lens) and lens.material_override is StandardMaterial3D:
			(lens.material_override as StandardMaterial3D).emission_energy_multiplier=1.5 if item=="ElectricLamp" and working(item) else 0.0
		var screen: Label3D=parts.screen if is_instance_valid(parts.screen) else null
		if is_instance_valid(screen) and update_text:
			var screen_text:=("FAULT" if not fault_for("Walkie Talkie").is_empty() else "CH16" if enabled["Walkie Talkie"] else "OFF")+"\n"+("%d%%"%roundi(float(charge["Walkie Talkie"])) if installed["Walkie Talkie"] else "NO CELL")+(" SUN" if solar and item=="Walkie Talkie" else "")
			if screen.text!=screen_text:screen.text=screen_text
		if is_instance_valid(screen):screen.modulate=Color(.43,.72,.46) if working("Walkie Talkie") else Color(.20,.29,.21)
		var cover_origin: Vector3=parts.get("cover_origin",Vector3.ZERO)
		var cover: Node3D=parts.cover if is_instance_valid(parts.cover) else null
		if is_instance_valid(cover):
			cover.position.z=lerpf(cover.position.z,cover_origin.z+0.10 if cover_open else cover_origin.z,0.2)
			cover.rotation.x=lerpf(cover.rotation.x,-1.1 if cover_open else 0.0,0.2)
		var cell: Node3D=parts.cell if is_instance_valid(parts.cell) else null
		if is_instance_valid(cell):
			cell.visible=battery_animation>0.0 and item==_battery_item
			var t:=1.0-battery_animation/1.8
			var slide:=sin(t*PI)
			cell.position=(parts.get("cell_origin",Vector3.ZERO) as Vector3)+Vector3(0,-0.08*slide,0.16*slide)
			cell.rotation.z=0.35*slide

func _cache_visual(held: Node3D) -> void:
	if not is_instance_valid(held):return
	var cover:=held.find_child("BatteryCover",true,false) as Node3D
	var cell:=held.find_child("AnimatedBattery",true,false) as Node3D
	_visuals.append({"cover_origin":cover.position if cover!=null else Vector3.ZERO,"cell_origin":cell.position if cell!=null else Vector3.ZERO,"screen":held.find_child("RadioScreen",true,false),"cover":held.find_child("BatteryCover",true,false),"cell":held.find_child("AnimatedBattery",true,false),"lens":held.find_child("LEDLens",true,false)})

func store_led(machine: Node) -> void:
	charge.ElectricLamp=machine.led_battery;installed.ElectricLamp=machine.led_cell;enabled.ElectricLamp=machine.enabled
	faults.ElectricLamp=machine.fault;fault_after.ElectricLamp=machine.fault_after

func _sound(kind: String) -> void:
	_audio.stream=AUDIO.electronic_stream(kind);_audio.play()

func save_state() -> Dictionary:
	return {"charge":charge.duplicate(),"installed":installed.duplicate(),"enabled":enabled.duplicate(),"faults":faults.duplicate(),"fault_after":fault_after.duplicate()}
func restore_state(data: Variant) -> void:
	if not data is Dictionary:return
	for field in ["charge","installed","enabled"]:
		if not data.get(field,{}) is Dictionary:return
	for item in POWERED:
		var value: Variant=data.get("charge",{}).get(item,100.0)
		var amount:=float(value) if value is int or value is float else 0.0
		charge[item]=clampf(amount,0,100) if is_finite(amount) else 0.0
		installed[item]=bool(data.get("installed",{}).get(item,true))
		enabled[item]=bool(data.get("enabled",{}).get(item,false)) and installed[item] and float(charge[item])>0
		var saved_fault: Variant=data.get("faults",{})
		faults[item]=str(saved_fault.get(item,"")) if saved_fault is Dictionary and str(saved_fault.get(item,"")) in ["contact","wiring"] else ""
		var saved_clock: Variant=data.get("fault_after",{})
		var remaining: Variant=saved_clock.get(item,420.0) if saved_clock is Dictionary else 420.0
		fault_after[item]=clampf(float(remaining),30.0,720.0) if (remaining is float or remaining is int) and is_finite(float(remaining)) else 420.0

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED] and is_instance_valid(player):
		set_zoom(false)

func touch_button_at(at: Vector2) -> Button:
	if not _panel.visible:return null
	for child in _buttons.get_children():
		if child is Button and child.is_visible_in_tree() and child.get_global_rect().has_point(at):return child
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode==KEY_ALT and not event.echo:
		if event.pressed and (str(player.active_item) not in POWERED or _blocked()):return
		if not event.pressed and not _desktop_cursor:return
		_desktop_cursor=event.pressed
		GameSettings.release_gameplay_input()
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if event.pressed or _blocked() else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
