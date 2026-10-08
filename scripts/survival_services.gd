extends Node
## Authoritative local gameplay commands; UI passes intent, never costs or rewards.
const RULES := preload("res://scripts/food_rules.gd")
const JOB := preload("res://scripts/station_job.gd")
const BOX := preload("res://scripts/storage_box.gd")
const HUD_FIELDS := ["_bag_open","_craft_open","_map_open","_paused","_death_open"]
const LIGHT_GROUPS := ["campfire","wall_torch","electric_lamp"]
var player: CharacterBody3D
var ui: CanvasLayer
var menu_open := false
var action: Dictionary = {}
var storage: Node3D
var station: Node3D
var focused_job: Node3D
var _action_start := Vector3.ZERO
var _damage_revision := 0
var _light_tick := 0.0
var _progress_tick := 0.0
var _job_label := ""
var _drops: Array[Node3D] = []

func _ready() -> void:
	player=get_parent() as CharacterBody3D
	ui=preload("res://scripts/survival_service_ui.gd").new();ui.service=self;add_child(ui)
	call_deferred("_restore_drops")
func is_modal() -> bool:return menu_open
func busy() -> bool:return not action.is_empty()
func equip_owned(item: String) -> void:
	for index in Inventory.SLOT_COUNT:
		if Inventory.slot_item(index)!=item:continue
		var hotbar:=clampi(player.active_slot_index,0,Inventory.HOTBAR_COUNT-1)
		if index>=Inventory.HOTBAR_COUNT:Inventory.swap_slots(index,hotbar)
		else:hotbar=index
		player.call("select_hotbar_slot",hotbar)
		return
func _blocked() -> bool:
	if get_tree().paused or GameSettings.is_open or Stats.health<=0 or player.build_mode or player.get("_editing")!=null:return true
	var hud:=player.get_node_or_null("CanvasLayer/SurvivalHUD")
	if hud!=null:
		for field in HUD_FIELDS:
			if hud.get(field)==true:return true
	return false
func _near(target: Node3D) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_inside_tree() \
		and player.global_position.distance_to(target.global_position)<=5.0
func is_fire(target: Node3D) -> bool:return _near(target) and target.is_in_group("campfire")
func is_filter(target: Node3D) -> bool:
	return _near(target) and str(target.get("machine_type")) in ["SandFilter","WaterPurifier","ElectricPurifier"]
func _station_ready(target: Node3D) -> bool:
	return is_fire(target) and target.get("burning")==true and float(target.get("fuel"))>0.0 \
		and not bool(target.call("exposed_to_rain"))

func use_item(item: String) -> bool:
	if _blocked() or menu_open or busy() or item!=str(player.active_item) or not Inventory.has(item,1):return false
	if item=="Medkit":
		if Stats.health>=Stats.MAX_VALUE:return false
		_start_action("medkit",1.5,item)
		player.call("play_action","bandage",1.5)
		player.call("play_world_sfx",preload("res://audio/pickup_rustle.ogg"),-14.0)
		return true
	if item=="Can":
		var at:=ocean_point()
		if not at.is_finite():player.call("_hud_toast","AIM AT REACHABLE OCEAN WATER");return false
		_start_action("fill",2.0,item)
		player.call("play_action","fill",2.0,at)
		return true
	if RULES.edible(item):
		var return_can: Dictionary={"Can":1} if item.ends_with("Water Can") else {}
		if not Inventory.try_exchange({item:1},return_can):return false
		var values:=RULES.effects(item)
		Stats.eat(float(values[0]));Stats.drink(float(values[1]));Stats.change_health(float(values[2]))
		player.call("play_action","drink" if item in ["Water","Dirty Water Can","Clean Water Can"] else "eat",0.95)
		player.call("_queue_save")
		return true
	return false

func _start_action(kind: String,seconds: float,item: String) -> void:
	action={"kind":kind,"remaining":seconds,"duration":seconds,"item":item}
	_action_start=player.global_position
	_damage_revision=Stats.damage_revision
	ui.show_progress(kind.to_upper(),0.0)
func cancel_action() -> void:
	if action.is_empty():return
	action.clear();ui.hide_progress()
	player.get_node("SurvivalAction").call("stop")
	player.call("_hud_toast","ACTION CANCELLED · ITEM KEPT")
func advance_action(seconds: float) -> void:
	if action.is_empty():return
	if _blocked() or player.active_item!=action.item or not Inventory.has(action.item,1) \
		or (action.kind=="medkit" and (player.global_position.distance_to(_action_start)>0.12 \
		or player.velocity.length()>0.15 or Stats.damage_revision!=_damage_revision)):
		cancel_action();return
	if action.kind=="fill" and not ocean_point().is_finite():cancel_action();return
	action.remaining=maxf(0.0,float(action.remaining)-seconds)
	ui.show_progress("USING MEDKIT" if action.kind=="medkit" else "FILLING CAN",1.0-float(action.remaining)/float(action.duration))
	if float(action.remaining)>.000001:return
	var completed:=action.duplicate();action.clear();ui.hide_progress()
	player.get_node("SurvivalAction").call("stop")
	if completed.kind=="medkit":
		if Inventory.try_exchange({"Medkit":1},{}):Stats.change_health(Stats.MAX_VALUE*.5)
	elif completed.kind=="fill":
		if Inventory.try_exchange({"Can":1},{"Dirty Water Can":1}):player.call("_hud_toast","DIRTY SEAWATER · FILTER BEFORE DRINKING")
	player.call("_queue_save")

func ocean_point() -> Vector3:
	var camera:=player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	var ocean:=get_tree().get_first_node_in_group("ocean")
	if ocean==null:return Vector3(INF,INF,INF)
	var from:=camera.global_position;var direction: Vector3=-camera.global_basis.z
	if direction.y>=-0.04:return Vector3(INF,INF,INF)
	var height:=float(ocean.call("get_height",from))
	var distance_value: float=(height-from.y)/direction.y
	if distance_value<=0 or distance_value>6:return Vector3(INF,INF,INF)
	var at:=from+direction*distance_value
	for unused in 2:at=from+direction*((float(ocean.call("get_height",at))-from.y)/direction.y)
	if player.global_position.distance_to(at)>5.0:return Vector3(INF,INF,INF)
	var ray:=PhysicsRayQueryParameters3D.create(from,at+direction*.06,1,[player.get_rid()])
	if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return Vector3(INF,INF,INF)
	return at

func open_cooking(target: Node3D) -> void:
	if _blocked() or busy() or not is_fire(target):return
	station=target;_open_menu();ui.show_cooking()
func open_filter(target: Node3D) -> void:
	if _blocked() or busy() or not is_filter(target):return
	station=target;_open_menu();ui.show_filter()
func open_storage(target: Node3D) -> void:
	if _blocked() or busy() or not _near(target) or not target.is_in_group("storage_box"):return
	storage=target;_open_menu();ui.show_storage()
func _open_menu() -> void:
	menu_open=true
	GameSettings.release_gameplay_input();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func close_menu() -> void:
	menu_open=false;storage=null;station=null;ui.close()
	GameSettings.release_gameplay_input()
	if not _blocked():Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func can_cook(dish: String) -> bool:
	if _blocked() or not RULES.RECIPES.has(dish) or not _station_ready(station):return false
	var job:=station.get_node_or_null("StationJob")
	if job!=null and not job.job.is_empty():return false
	for item in RULES.RECIPES[dish].ingredients:
		if not Inventory.has(item,int(RULES.RECIPES[dish].ingredients[item])):return false
	return true
func start_cooking(dish: String) -> bool:
	if not can_cook(dish):return false
	var recipe: Dictionary=RULES.RECIPES[dish]
	var empties: Dictionary={}
	if recipe.ingredients.has("Clean Water Can"):empties["Can"]=int(recipe.ingredients["Clean Water Can"])
	if not Inventory.try_exchange(recipe.ingredients,empties):return false
	var target:=station
	var job:=ensure_job(target)
	job.restore_job({"kind":"cook","item":dish,"remaining":recipe.seconds})
	focused_job=job
	_job_label=dish.to_upper()
	close_menu()
	player.call("play_action","fire",1.2,target.global_position)
	player.call("_queue_save")
	return true
func start_filtering() -> bool:
	if _blocked() or not is_filter(station) or not Inventory.has("Dirty Water Can",1):return false
	var existing:=station.get_node_or_null("StationJob")
	if existing!=null and not existing.job.is_empty():return false
	if not Inventory.try_exchange({"Dirty Water Can":1},{}):return false
	var target:=station;var job:=ensure_job(target)
	job.restore_job({"kind":"filter","item":"Clean Water Can","remaining":5.0})
	job.begin_insertion(player.global_position+Vector3.UP)
	focused_job=job
	_job_label="FILTERING WATER"
	close_menu();player.call("play_action","install",.8,target.global_position);player.call("_queue_save")
	return true
func ensure_job(target: Node3D) -> Node3D:
	var existing:=target.get_node_or_null("StationJob") as Node3D
	if existing!=null:return existing
	var job:=JOB.new();job.name="StationJob";target.add_child(job);return job
func finish_station_job(job: Node3D) -> void:
	if not is_instance_valid(job) or job.get_script()!=JOB or job.job.is_empty() or float(job.job.remaining)>0:return
	var item:=str(job.job.item)
	if item!="Clean Water Can" and not RULES.RECIPES.has(item):return
	# Clear before inventory signals/save callbacks; completion can only award once.
	job.job.clear();job.call("_sync_visual")
	if Inventory.add(item,1)>0:drop_items([{"item":item,"count":1}],job.global_position+Vector3.UP*.35)
	player.call("_hud_toast","READY · "+item.to_upper())
	player.call("_queue_save")

func transfer(from_box: bool,source: int,to_box: bool,destination: int) -> bool:
	if _blocked() or not menu_open or not _near(storage) or not storage.is_in_group("storage_box"):return false
	var bag: Array=Inventory.slots.duplicate(true);var chest: Array=storage.contents.duplicate(true)
	var source_array: Array=chest if from_box else bag
	var destination_array: Array=chest if to_box else bag
	if source<0 or source>=source_array.size() or destination<0 or destination>=destination_array.size() \
		or (from_box==to_box and source==destination) or source_array[source].is_empty():return false
	var entry: Dictionary=source_array[source];var target: Dictionary=destination_array[destination]
	if target.is_empty():destination_array[destination]=entry;source_array[source]={}
	elif str(target.item)==str(entry.item):
		var amount:=mini(int(entry.count),Inventory.MAX_STACK-int(target.count))
		if amount<=0:return false
		target.count=int(target.count)+amount;entry.count=int(entry.count)-amount
		if int(entry.count)==0:source_array[source]={}
	else:source_array[source]=target;destination_array[destination]=entry
	Inventory.slots=bag;storage.contents=chest;Inventory.call("_recompute");Inventory.changed.emit();storage.contents_changed.emit()
	player.call("_queue_save");ui.refresh_storage();return true

func drop_items(items: Array,at: Vector3) -> Node3D:
	var bag:=BOX.new();bag.name="LostBackpack";bag.loot_bag=true;bag.capacity=30
	get_tree().current_scene.add_child(bag)
	bag.global_position=at
	var ocean:=get_tree().get_first_node_in_group("ocean")
	if ocean!=null:bag.global_position.y=maxf(at.y,float(ocean.call("get_height",at))+.35)
	bag.restore_survival_state({"contents":items})
	_drops.append(bag)
	return bag
func on_death() -> void:
	cancel_action();close_menu()
	var lost: Array=Inventory.slots.duplicate(true)
	var any:=false
	for entry in lost:
		if not entry.is_empty():any=true;break
	if any:drop_items(lost,player.global_position)
	for index in Inventory.SLOT_COUNT:Inventory.slots[index]={}
	Inventory.call("_recompute");Inventory.changed.emit();player.call("_queue_save")
func save_state() -> Dictionary:
	var drops: Array=[]
	for bag in _drops:
		if not is_instance_valid(bag) or bag.empty():continue
		var at:=bag.global_position
		drops.append({"p":[at.x,at.y,at.z],"contents":bag.contents.duplicate(true)})
	return {"version":1,"drops":drops}
func _restore_drops() -> void:
	var data: Variant=Inventory.loaded_meta.get("survival_services",{})
	if not data is Dictionary or not data.get("drops",[]) is Array:return
	for entry in data.get("drops",[]).slice(0,64):
		if not entry is Dictionary or not entry.get("p") is Array or entry.p.size()!=3 or not entry.get("contents") is Array:continue
		var numeric:=true
		for coordinate in entry.p:
			if not (coordinate is float or coordinate is int):numeric=false;break
		if not numeric:continue
		var at:=Vector3(float(entry.p[0]),float(entry.p[1]),float(entry.p[2]))
		if not at.is_finite() or at.length()>200000:continue
		drop_items(entry.contents,at)

func _process(delta: float) -> void:
	advance_action(delta)
	if menu_open and (_blocked() or (is_instance_valid(storage) and not _near(storage)) or (is_instance_valid(station) and not _near(station))):close_menu()
	_progress_tick+=delta
	if _progress_tick>=.1:
		_progress_tick=0.0
		if is_instance_valid(focused_job) and not focused_job.job.is_empty() and not busy():
			ui.show_progress(_job_label,1.0-float(focused_job.job.remaining)/float(focused_job.job.duration))
		elif not busy():ui.hide_progress()
	_light_tick+=delta
	if _light_tick>=.5:_light_tick=0.0;_limit_lights()
func _limit_lights() -> void:
	var sources: Array[Node3D]=[]
	for group in LIGHT_GROUPS:
		for source in get_tree().get_nodes_in_group(group):sources.append(source)
	sources.sort_custom(func(a,b):return player.global_position.distance_squared_to(a.global_position)<player.global_position.distance_squared_to(b.global_position))
	for index in sources.size():sources[index].set_meta("light_allowed",index<6)
