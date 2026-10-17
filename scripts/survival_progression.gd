extends Node3D
## Activity-based chapters. Materials granted for testing never advance missions.
const UNLOCKS := {"WaterPurifier": 2, "WindGenerator": 3, "ElectricLamp": 3,
	"ElectricPurifier": 4, "RescueRadio": 5}
const CHAPTERS := [
	["MAKE CAMP", "Craft a fishing rod and spear; build a campfire.", {"craft:Fishing Rod": 1, "craft:Spear": 1, "build:Bonfire": 1}],
	["SAFE WATER", "Build a Water Purifier; collect two distilled waters.", {"build:WaterPurifier": 1, "purify": 2}],
	["HARNESS THE WIND", "Build a Wind Generator; generate power.", {"build:WindGenerator": 1, "power": 1}],
	["POWERED CAMP", "Build an Electric Purifier; collect two powered waters.", {"build:ElectricPurifier": 1, "electric_water": 2}],
	["SEND A SIGNAL", "Build a Rescue Radio; power and transmit an SOS.", {"build:RescueRadio": 1, "signal": 1}],
	["OCEAN SURVIVOR", "Rescue signal sent. Explore, hunt and expand your camp.", {}]
]
var level := 1
var events: Dictionary = {}
var diving_tank := false
const AIR_CAPACITY := 180.0
var air_tank_seconds := 0.0
var _air_refill := 0.0
var _refill_damage := 0
var _refill_start := Vector3.ZERO
var _back_tank: Node3D
var _tank_rig: Skeleton3D
var _tank_chest := -1
var oxygen := 100.0
var stamina := 100.0
var wetness := 0.0
var torch_fuel := 0.0
var torch_end_time := 0.0
var legacy_torch := false
const TORCH_CYCLE := preload("res://scripts/torch_cycle.gd")
const TORCH_VISUAL := preload("res://scripts/torch_visual.gd")
var _mount_preview: MeshInstance3D
var _preview_tick := 0.0
var _torch_light: OmniLight3D
var _third_torch: Node3D
var _crackle: AudioStreamPlayer3D
var _tick := 0.0
var player: CharacterBody3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	var fire_actions:=preload("res://scripts/fire_actions.gd").new()
	fire_actions.name="FireActions";player.add_child(fire_actions)
	add_to_group("survival_progression")
	var saved: Variant = Inventory.loaded_meta.get("progression", {})
	if saved is Dictionary:
		restore_state(saved)
	# Existing owned/built equipment remains valid and contributes to knowledge.
	call_deferred("_recover_existing_camp")
	_torch_light = OmniLight3D.new()
	_torch_light.name = "TorchLight"
	_torch_light.light_color = Color(1,0.51,0.19)
	_torch_light.light_energy = TORCH_VISUAL.LIGHT_ENERGY
	_torch_light.omni_range = TORCH_VISUAL.LIGHT_RANGE
	_torch_light.omni_attenuation = TORCH_VISUAL.LIGHT_ATTENUATION
	_torch_light.shadow_enabled = false
	_torch_light.position = Vector3(0,1.2,0)
	add_child(_torch_light)
	_third_torch = TORCH_VISUAL.new()
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
	_mount_preview=MeshInstance3D.new()
	var ghost:=CylinderMesh.new();ghost.top_radius=.04;ghost.bottom_radius=.02;ghost.height=.72;ghost.radial_segments=8;_mount_preview.mesh=ghost
	var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.2,1,.4,.45);material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_mount_preview.material_override=material;_mount_preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mount_preview);_mount_preview.hide()
	_back_tank=preload("res://scripts/dive_visual.gd").tank()
	_back_tank.name="EquippedAirTank";player.get_node("Body").add_child(_back_tank)
	_back_tank.position=Vector3(0,.20,.23)
	_back_tank.hide()
	for candidate in player.get_node("Body").find_children("*","Skeleton3D",true,false):
		var rig := candidate as Skeleton3D
		var chest := rig.find_bone("Chest")
		if chest>=0:_tank_rig=rig;_tank_chest=chest;break

func _update_back_tank() -> void:
	if not is_instance_valid(_back_tank): return
	_back_tank.visible=diving_tank and player.cam_mode>=1
	if not _back_tank.visible or not is_instance_valid(_tank_rig) or _tank_chest<0: return
	var chest := _tank_rig.global_transform*_tank_rig.get_bone_global_pose(_tank_chest)
	var orientation := chest.basis.orthonormalized()
	# Match the recorded torso pitch, without inheriting FBX bone scale.
	_back_tank.global_transform=Transform3D(orientation*Basis(Vector3.UP,PI),chest.origin+orientation*Vector3(0,-.05,-.20))

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
	var salvage:=player.get_node_or_null("OceanSalvage")
	return str(salvage.objective()) if level==CHAPTERS.size() and salvage!=null else str(CHAPTERS[level - 1][1])

func _process(delta: float) -> void:
	var scene:=get_tree().current_scene
	if scene==null:return
	_update_back_tank()
	if _air_refill>0:
		var hud:=player.get_node_or_null("CanvasLayer/SurvivalHUD")
		if player.is_swimming or GameSettings.is_open or Stats.damage_revision!=_refill_damage or player.global_position.distance_squared_to(_refill_start)>1 or (hud!=null and hud.call("gameplay_input_blocked")):
			_air_refill=0;player.get_node("SurvivalAction").call("stop")
		else:
			_air_refill=maxf(0,_air_refill-delta)
			if _air_refill==0:air_tank_seconds=AIR_CAPACITY;player.call("_hud_toast","AIR TANK REFILLED · 3:00");player.call("_queue_save")
	var equipped := str(player.get("active_item")) in ["Torch","Burning Torch"]
	var construction: bool = bool(player.get("build_mode")) or is_instance_valid(player.get("_editing"))
	if torch_fuel>0 or torch_end_time>0:
		if torch_end_time<=0:torch_end_time=TORCH_CYCLE.next_dawn(player)
		var remaining:=TORCH_CYCLE.seconds_left(player,torch_end_time)
		if remaining<=0:extinguish_torch()
		elif torch_fuel>0 or Inventory.has("Burning Torch",1):torch_fuel=remaining
	if str(player.get("active_item"))=="Burning Torch" and torch_fuel<=0:extinguish_torch()
	sync_torch_effects()
	var lit := is_held_lit() and Stats.health > 0
	var fire_pose: bool=player.get_node("SurvivalAction").kind in ["ignite_fire","snuff_fire","torch_light","torch_off","torch_mount"]
	_preview_tick+=delta
	if _preview_tick>=.1:
		_preview_tick=0.0;_update_mount_preview(equipped and not construction and not fire_pose)
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
		var start: Vector3 = player.get_node("CamPivot").global_position+Vector3.UP*.05
		var ray := PhysicsRayQueryParameters3D.create(start,start+Vector3.UP*8,1,[player.get_rid()])
		exposed = player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	if lit and (swimming or exposed):
		extinguish_torch()
		player.call("_hud_toast","TORCH WET · RELIGHT AT A SHELTERED CAMPFIRE")
	stamina = clampf(stamina + (-5.0 if swimming and moving > 1.8 else (-3.0 if moving > 4.0 else 7.0)) * step, 0, 100)
	wetness = clampf(wetness + (12.0 if swimming else (3.0*clampf(float(rain.get("_intensity")),0.0,1.0) if exposed else (-3.0 if lit else -0.8))) * step, 0, 100)
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	var ocean := scene.get_node_or_null("Ocean")
	var underwater := ocean != null and camera.global_position.y < float(ocean.call("get_height", camera.global_position)) - 0.30
	var supplied := underwater and diving_tank and air_tank_seconds>0
	if supplied: air_tank_seconds=maxf(0,air_tank_seconds-step)
	var breath_rate := (1.0 if supplied else -5.0) if underwater else 18.0
	oxygen = clampf(oxygen + breath_rate * step, 0, 100)
	if underwater and oxygen <= 0.0:
		Stats.change_health(-8.0 * step)

func can_refill_air() -> bool:
	return diving_tank and air_tank_seconds<AIR_CAPACITY-1 and _air_refill<=0 and not player.is_swimming and player.is_on_floor()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and _air_refill>0:
		_air_refill=0
		if is_instance_valid(player):player.get_node("SurvivalAction").call("stop")

func refill_air() -> bool:
	if not can_refill_air(): return false
	_air_refill=6.0;_refill_damage=Stats.damage_revision;_refill_start=player.global_position
	player.call("play_action","pump",6.0,player.global_position)
	return true

func save_state() -> Dictionary:
	return {"level": level, "events": events.duplicate(), "diving_tank": diving_tank,
		"oxygen": oxygen,"air_tank_seconds":air_tank_seconds, "stamina": stamina, "wetness": wetness, "torch_fuel": torch_fuel,"torch_end_time":torch_end_time,"legacy_torch":legacy_torch}

func restore_state(data: Dictionary) -> void:
	level = clampi(int(data.get("level", 1)), 1, CHAPTERS.size())
	events.clear()
	var stored: Variant = data.get("events", {})
	if stored is Dictionary:
		for key in stored:
			events[str(key)] = clampi(int(stored[key]), 0, 10000)
	diving_tank = bool(data.get("diving_tank", false))
	air_tank_seconds=clampf(float(data.get("air_tank_seconds",AIR_CAPACITY if diving_tank else 0.0)),0,AIR_CAPACITY)
	oxygen = clampf(float(data.get("oxygen", 100)), 10, 100)
	stamina = clampf(float(data.get("stamina", 100)), 10, 100)
	wetness = clampf(float(data.get("wetness", 0)), 0, 100)
	torch_fuel = clampf(float(data.get("torch_fuel",0)),0,86400)
	torch_end_time=clampf(float(data.get("torch_end_time",0)),0,240000000.0)
	legacy_torch=bool(data.get("legacy_torch",torch_fuel>0 and torch_end_time<=0))

func is_held_lit() -> bool:
	return torch_fuel>0 and (str(player.active_item)=="Burning Torch" or (legacy_torch and str(player.active_item)=="Torch"))

func sync_torch_effects() -> void:
	var lit := is_held_lit() and Stats.health > 0
	var construction: bool = bool(player.get("build_mode")) or is_instance_valid(player.get("_editing"))
	var action := player.get_node_or_null("SurvivalAction")
	var fire_pose: bool = action != null and action.kind in ["ignite_fire","snuff_fire","torch_light","torch_off","torch_mount"]
	var first: bool = int(player.get("cam_mode")) == 0
	var source: Node3D = null
	if is_instance_valid(_third_torch):
		_third_torch.visible = str(player.active_item) in ["Torch","Burning Torch"] and not first and not construction and not fire_pose
		_third_torch.call("set_burning",lit)
		if not first: source = _third_torch
	# Item swaps defer freeing the old Torch. Godot may rename its replacement,
	# so update the live model by script instead of looking up a fixed node name.
	var hand := player.get("_hand_item") as Node3D
	if is_instance_valid(hand):
		for held in hand.get_children():
			if held.get_script() == TORCH_VISUAL and not held.is_queued_for_deletion():
				held.call("set_burning",lit)
				if first: source = held
	if action != null:
		for prop in [action.get("_torch_first"),action.get("_torch_third")]:
			if is_instance_valid(prop): prop.call("set_burning",lit)
		var action_torch := action.get("_torch_first" if first else "_torch_third") as Node3D
		if fire_pose and is_instance_valid(action_torch): source = action_torch
	if is_instance_valid(_torch_light):
		_torch_light.visible = lit and not construction
		_torch_light.light_energy = TORCH_VISUAL.light_energy_at(Time.get_ticks_msec() / 1000.0)
		if is_instance_valid(source): _torch_light.global_position = source.to_global(Vector3(0,.46,0))
	if is_instance_valid(_crackle):
		if is_instance_valid(_torch_light): _crackle.global_position = _torch_light.global_position
		if lit and not _crackle.playing: _crackle.play()
		elif not lit and _crackle.playing: _crackle.stop()

func held_torch_caption() -> String:
	var selected:=str(player.active_item)
	if selected not in ["Torch","Burning Torch"] or not Inventory.has(selected,1):return ""
	var target := player.get("aim_collider") as Node3D
	if bool(player.aim_valid) and is_instance_valid(target):
		if target.is_in_group("wall_torch") and player.global_position.distance_to(target.global_position)<=3.2:
			return "LIGHT TORCH" if not is_held_lit() and fire_source_ready(target) else "TAKE TORCH"
	if bool(player.call("_resolve_wall_torch").get("valid",false)):return "PLACE TORCH"
	if is_held_lit():return "PUT OUT"
	if bool(player.aim_valid) and is_instance_valid(target) and fire_source_ready(target):return "LIGHT TORCH"
	return ""

func use_torch() -> void:
	var selected:=str(player.get("active_item"))
	if selected not in ["Torch","Burning Torch"] or not Inventory.has(selected,1):return
	if player.get_node("SurvivalServices")._blocked() or player.get_node("SurvivalServices").is_modal():return
	if bool(player.get("aim_valid")) and player.get("aim_collider") != null:
		var target := player.get("aim_collider") as Node3D
		if str(player.call("_find_piece_name",target)) == "WallTorch" and player.global_position.distance_to(target.global_position) <= 3.2:
			if not is_held_lit() and fire_source_ready(target):player.get_node("FireActions").start("torch_light",target)
			else:target.call("interact_survival",player)
			return
	if bool(player.call("_resolve_wall_torch").get("valid",false)):
		player.get_node("FireActions").start("torch_mount",player.aim_collider);return
	if is_held_lit():
		player.get_node("FireActions").start("torch_off")
	else:
		var fire:=player.get("aim_collider") as Node3D
		if bool(player.get("aim_valid")) and fire_source_ready(fire):
			player.get_node("FireActions").start("torch_light",fire)
		else:player.call("_hud_toast","AIM AT A LIT TORCH, BONFIRE OR COOKING SETUP")
	player.call("_queue_save")

func extinguish_torch() -> void:
	torch_fuel=0;torch_end_time=0;legacy_torch=false
	var count_value:=Inventory.total("Burning Torch")
	if count_value>0:Inventory.try_exchange({"Burning Torch":count_value},{"Torch":count_value})
	for box in get_tree().get_nodes_in_group("storage_box"):
		var changed:=false
		for entry in box.contents:
			if entry.get("item","")=="Burning Torch":entry.item="Torch";changed=true
		if changed:box.contents_changed.emit()
	sync_torch_effects()

func _update_mount_preview(lit: bool) -> void:
	_mount_preview.hide()
	if not lit or player.get_node("SurvivalServices")._blocked() or player.get_node("SurvivalServices").is_modal():return
	var target:=player.get("aim_collider") as Node3D
	if not is_instance_valid(target) or not player.aim_valid or player.aim_distance>5:return
	if str(player.call("_find_piece_name",target)) not in ["Wall","Window","Door"]:return
	var placement: Dictionary=player.call("_resolve_wall_torch")
	var valid:=bool(placement.get("valid",false))
	if valid:_mount_preview.global_transform=placement.transform;_mount_preview.global_position+=_mount_preview.global_basis.y*.13
	else:_mount_preview.global_position=player.aim_point+player.aim_normal*.2
	(_mount_preview.material_override as StandardMaterial3D).albedo_color=Color(.2,1,.4,.45) if valid else Color(1,.15,.1,.45)
	_mount_preview.show()

func fire_source_ready(target: Node3D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion() \
		and player.global_position.distance_to(target.global_position)<=3.5 \
		and (target.is_in_group("campfire") or target.is_in_group("wall_torch")) \
		and target.get("burning")==true and float(target.get("fuel"))>0 and not target.call("exposed_to_rain")
