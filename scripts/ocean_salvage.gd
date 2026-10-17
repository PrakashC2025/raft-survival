extends Node
## Active-play expeditions: one persistent cache, fixed manifests, no expiry or rerolls.
const CACHE := preload("res://scripts/drift_cache.gd")
const GUIDE := preload("res://scripts/item_guide.gd")
const NAMES := ["Galley Cargo", "Repair Cargo", "Garden Cargo", "Medical Cargo"]
const REWARDS := [
	{"Wrapped Cooked Fish":2,"Water":2,"Cooking Foil":2},
	{"Screw":6,"Wire":3,"Motor":1,"Battery":1},
	{"Soil":4,"Carrot Seed":2,"Tomato Seed":2,"Potato":2},
	{"Bandage":3,"Medkit":1,"Water":2}
]
const NOTES := [
	"Galley note: cook raw fish at a sheltered fire; pack meals before a voyage.",
	"Mechanic's note: screws, wire, a motor and a battery make a wind generator useful.",
	"Gardener's note: plant seeds in soil, water them, then save seeds from your harvest.",
	"Medic's note: carry bandages and drinking water before exploring far from camp."
]
const DURATION := 3.0
var player: CharacterBody3D
var cache: StaticBody3D
var next_arrival := 90.0
var serial := 0
var recovered := 0
var catalog: Array[int] = []
var last_note := -1
var pending: Dictionary = {}
var menu_open := false
var _journal: CanvasLayer
var _journal_panel: PanelContainer
var _restored := false
var _save_clock := 0.0
var _was_raining := false
var _clearance: BoxShape3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	_clearance = BoxShape3D.new()
	_clearance.size = Vector3(1.7,.9,1.45)
	get_viewport().size_changed.connect(_fit_journal)
	call_deferred("_restore")

func _restore() -> void:
	while is_inside_tree() and is_instance_valid(player) and not player.restoration_complete:await get_tree().process_frame
	if not is_instance_valid(player) or not is_inside_tree():return
	restore_state(Inventory.loaded_meta.get("ocean_salvage",{}))
	_restored = true

func cargo_name(kind: int) -> String:return NAMES[clampi(kind,0,3)]
func manifest(kind: int) -> String:
	var parts: PackedStringArray = []
	var index := clampi(kind,0,3)
	for item in REWARDS[index]:parts.append("%d %s"%[REWARDS[index][item],GUIDE.label(item)])
	return " · ".join(parts)

func open_journal() -> void:
	if busy() or _blocked():return
	if is_instance_valid(_journal):_journal.free()
	_journal = CanvasLayer.new()
	_journal.layer = 15
	add_child(_journal)
	var shade := ColorRect.new()
	shade.color = Color(.015,.025,.03,.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_journal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_journal.add_child(center)
	_journal_panel = PanelContainer.new()
	_journal_panel.theme = preload("res://scripts/ocean_ui.gd").theme()
	_journal_panel.add_theme_stylebox_override("panel",preload("res://scripts/ocean_ui.gd").box(Color("0c2836"),Color("d5b573")))
	center.add_child(_journal_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	_journal_panel.add_child(column)
	var title := Label.new()
	title.text = "OCEAN RECOVERY LOG"
	title.add_theme_font_size_override("font_size",24)
	column.add_child(title)
	var summary := Label.new()
	summary.text = "%d OF 4 NOTES FOUND · %d CARGO RECOVERED"%[catalog.size(),recovered]
	column.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation",18)
	scroll.add_child(pages)
	var instructions := Label.new()
	instructions.text = "Watch for coloured flags on floating cargo. Use MAP to sail close, then aim at the case and RECOVER CARGO. You can recover from a stopped rowboat. Cargo stays until collected; make room in your bag first.\n\n"+objective()
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pages.add_child(instructions)
	for index in NAMES.size():
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.text = ("✓ "+NAMES[index].to_upper()+"\n"+NOTES[index]+"\nRecovered supplies: "+manifest(index)) if catalog.has(index) else "? "+NAMES[index].to_upper()+"\nRecover this cargo to find its survivor's field note."
		entry.modulate = Color(.88,.93,.85) if catalog.has(index) else Color(.57,.71,.73)
		pages.add_child(entry)
	var close_button := Button.new()
	close_button.text = "RETURN TO MAP"
	close_button.custom_minimum_size.y = 54
	close_button.pressed.connect(func():close_journal();player.get_node("CanvasLayer/SurvivalHUD").toggle_map())
	column.add_child(close_button)
	_fit_journal()
	menu_open = true
	GameSettings.release_gameplay_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _fit_journal() -> void:
	if not is_instance_valid(_journal_panel):return
	var view := get_viewport().get_visible_rect().size
	_journal_panel.custom_minimum_size = Vector2(minf(650,view.x*.88),minf(550,view.y*.82))

func close_journal() -> void:
	menu_open = false
	if is_instance_valid(_journal):_journal.hide()
	GameSettings.release_gameplay_input()
	if not get_tree().paused and not GameSettings.is_open:Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func busy() -> bool:return not pending.is_empty()
func _blocked() -> bool:
	return not _restored or not player.restoration_complete or player.get_node("SurvivalServices")._blocked() or player.get_node("SurvivalServices").is_modal()

func water_clear(at: Vector3) -> bool:
	if not at.is_finite() or not is_instance_valid(player):return false
	var sea := get_tree().get_first_node_in_group("ocean") as Node3D
	if sea == null:return false
	var surface := float(sea.call("get_height",at))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.transform = Transform3D(Basis.IDENTITY,Vector3(at.x,surface+.35,at.z))
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var bottom := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,surface+.25,at.z),Vector3(at.x,surface-2.0,at.z),1,[player.get_rid()]))
	return bottom.is_empty()

func spawn_cache() -> bool:
	if is_instance_valid(cache) or _blocked():return false
	var origin := player.global_position
	# Enter upstream beyond the immediate view, using the same flow as ordinary driftwood.
	var stream := get_tree().current_scene.get_node_or_null("DebrisSpawner")
	var upstream := Vector3.FORWARD
	if stream != null:
		var flow: Vector3 = stream.current_direction
		flow.y = 0
		if flow.length_squared()>.01:upstream = -flow.normalized()
	for attempt in 12:
		var heading := upstream.rotated(Vector3.UP,(float(attempt)-5.5)*.25)
		var at := origin+heading*(85.0+float(attempt%3)*10.0)
		if not water_clear(at):continue
		_create(serial%NAMES.size(),at,randf()*TAU)
		serial += 1
		player.call("_hud_toast","DRIFT CARGO SIGHTED · OPEN MAP TO INVESTIGATE",4.5)
		player.call("_queue_save")
		return true
	return false

func _create(kind: int, at: Vector3, yaw: float) -> void:
	cache = CACHE.new()
	cache.name = "DriftingSupplyCache"
	cache.service = self
	cache.cargo_kind = kind
	cache.position = at
	cache.rotation.y = yaw
	get_tree().current_scene.add_child(cache)

func aimed_cache() -> StaticBody3D:
	if not is_instance_valid(cache) or not cache.available or not player.aim_valid:return null
	if player.aim_collider == cache and player.aim_distance <= 5.0 and player.global_position.distance_to(cache.global_position)<=4.5:return cache
	return null

func _reachable(target: StaticBody3D) -> bool:
	if not is_instance_valid(target) or target != cache or not target.available or target.is_queued_for_deletion() or player.global_position.distance_to(target.global_position)>4.5:return false
	var boat := player.get("boat_vehicle") as CollisionObject3D
	if boat != null and not str(boat.get("transition_kind")).is_empty():return false
	var skip: Array[RID] = [player.get_rid()]
	if boat != null:skip.append(boat.get_rid())
	var from := player.global_position+Vector3.UP*.45
	return player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,target.global_position+Vector3.UP*.4,1,skip)).is_empty()

func start_recovery(target: StaticBody3D) -> bool:
	if _blocked() or busy() or player.get_node("SurvivalServices").busy() or is_instance_valid(player.get_node("HuntingCargo").held) or not _reachable(target):return false
	if not Inventory.can_exchange({},REWARDS[target.cargo_kind]):
		player.call("_hud_toast","BAG FULL · CARGO KEPT · MAKE ROOM FOR "+manifest(target.cargo_kind),4.5)
		return false
	var boat := player.get("boat_vehicle") as Node3D
	if boat != null:boat.call("clear_course")
	player.rope_system._force_cancel()
	player.get_node("SurvivalEquipment").cancel_draw()
	GameSettings.release_gameplay_input()
	pending = {"age":0.0,"damage":Stats.damage_revision,"at":player.global_position,"boat":boat}
	player.call("play_action","recover_cargo",DURATION,target.global_position)
	return true

func cancel() -> void:
	if pending.is_empty():return
	pending.clear()
	if is_instance_valid(player):
		player.get_node("SurvivalAction").stop()
		player.call("_hud_toast","RECOVERY STOPPED · CARGO KEPT")

func advance_recovery(delta: float) -> void:
	if pending.is_empty():return
	if _blocked() or Stats.damage_revision!=int(pending.damage) or player.global_position.distance_squared_to(pending.at)>1.44 or pending.boat!=player.boat_vehicle or not _reachable(cache):
		cancel()
		return
	pending.age = float(pending.age)+maxf(0.0,delta)
	if float(pending.age)<DURATION:return
	var kind: int = cache.cargo_kind
	# The same all-or-nothing transaction is checked again at the contact frame.
	if not Inventory.try_exchange({},REWARDS[kind]):cancel();player.call("_hud_toast","BAG FULL · CARGO KEPT");return
	cache.available = false
	cache.collision_layer = 0
	cache.hide()
	cache.queue_free()
	cache = null
	pending.clear()
	player.get_node("SurvivalAction").stop()
	recovered += 1
	if not catalog.has(kind):catalog.append(kind)
	last_note = kind
	next_arrival = randf_range(300.0,480.0)
	for item in REWARDS[kind]:Inventory.notify_pickup(item,int(REWARDS[kind][item]))
	player.call("_hud_toast","CARGO RECOVERED · LOG %d/4 · %s"%[catalog.size(),NOTES[kind]],6.0)
	player.get_node("SurvivalProgression").record("salvage_cache")
	player.call("_queue_save")

func journal_caption() -> String:
	return "RECOVERY LOG %d/4 · %d CARGO RECOVERED"%[catalog.size(),recovered]

func objective() -> String:
	if is_instance_valid(cache):return "%s · %d m · Open MAP"%[cargo_name(cache.cargo_kind),roundi(player.global_position.distance_to(cache.global_position))]
	return "Explore, prepare supplies and watch the current."

func radio_report() -> String:
	if not is_instance_valid(cache):return ""
	var offset := cache.global_position-player.global_position
	var direction := wrapf(rad_to_deg(atan2(offset.x,-offset.z))+22.5,0,360)
	var bearing: String = ["N","NE","E","SE","S","SW","W","NW"][floori(direction/45.0)]
	return "DRIFT CARGO · %s · %d M %s · CHECK MAP"%[cargo_name(cache.cargo_kind).to_upper(),roundi(Vector2(offset.x,offset.z).length()),bearing]

func _process(delta: float) -> void:
	if not _restored:return
	if menu_open:
		_fit_journal()
		if Stats.health<=0:close_journal()
	advance_recovery(delta)
	if _blocked():return
	var rain := get_tree().get_first_node_in_group("rain_system")
	var raining: bool = rain != null and rain.call("is_raining")
	if _was_raining and not raining and not is_instance_valid(cache):next_arrival = minf(next_arrival,45.0)
	_was_raining = raining
	if not is_instance_valid(cache):
		next_arrival = maxf(0.0,next_arrival-minf(delta,.5))
		if next_arrival<=0.0 and not spawn_cache():next_arrival = 20.0
	_save_clock += delta
	if _save_clock>=30.0:_save_clock = 0.0;player.call("_queue_save")

func save_state() -> Dictionary:
	# A quit on the first restored frame must not overwrite the loaded expedition.
	if not _restored:
		var loaded: Variant = Inventory.loaded_meta.get("ocean_salvage",{})
		return loaded.duplicate(true) if loaded is Dictionary else {}
	return {"next_arrival":next_arrival,"serial":serial,"recovered":recovered,"catalog":catalog.duplicate(),"last_note":last_note,"cache":cache.save_state() if is_instance_valid(cache) and cache.available else {}}

static func _number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	return clampf(float(value),minimum,maximum) if (value is int or value is float) and is_finite(float(value)) else fallback

func restore_state(data: Variant) -> void:
	cancel()
	if is_instance_valid(cache):cache.free()
	cache = null
	next_arrival = 90.0;serial = 0;recovered = 0;catalog.clear();last_note = -1
	if not data is Dictionary:return
	next_arrival = _number(data.get("next_arrival"),90.0,0,480)
	serial = int(_number(data.get("serial"),0,0,1000000))
	recovered = int(_number(data.get("recovered"),0,0,1000000))
	last_note = int(_number(data.get("last_note"),-1,-1,3))
	if data.get("catalog") is Array:
		for entry in data.catalog.slice(0,4):
			if (entry is int or entry is float) and is_finite(float(entry)) and float(entry)==floorf(float(entry)) and int(entry)>=0 and int(entry)<4 and not catalog.has(int(entry)):catalog.append(int(entry))
	var saved: Variant = data.get("cache",{})
	if not saved is Dictionary or saved.is_empty() or not saved.get("p") is Array or saved.p.size()!=3:return
	for coordinate in saved.p:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>200000:return
	var kind: Variant = saved.get("kind")
	if not (kind is int or kind is float) or not is_finite(float(kind)) or float(kind)!=floorf(float(kind)) or float(kind)<0 or float(kind)>3:return
	_create(int(kind),Vector3(float(saved.p[0]),float(saved.p[1]),float(saved.p[2])),_number(saved.get("yaw"),0,-TAU,TAU))

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		cancel()
		if menu_open:close_journal()

func _exit_tree() -> void:
	if is_instance_valid(cache):cache.queue_free()
