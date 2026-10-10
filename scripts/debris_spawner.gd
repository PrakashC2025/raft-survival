extends Node3D

# Continuous ocean-current debris stream.
# Debris flows from UPSTREAM → past player → DOWNSTREAM → despawn.

@export var debris_scene: PackedScene
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 0.32
@export var spawn_width: float = 28.0
@export var upstream_distance: float = 52.0
@export var downstream_distance: float = 34.0
@export var max_debris: int = 80
@export var prewarm_count: int = 35

# Current spacing avoids filling the far edge with a single dense clump.
@export var spawn_interval_min: float = 2.5
@export var spawn_interval_max: float = 4.5

var _timer: float = 0.0
var _next_interval: float = 0.0
var _active: Array = []
var player: Node3D
var _direction: Vector3 = Vector3.ZERO
var _side: Vector3 = Vector3.ZERO
var _raft: Node3D
var _spawn_serial := 0
var _rare_day:=1
var _rare_cycle:=0
const GARDEN:=preload("res://scripts/garden_items.gd")
const NEAR_RADIUS := 24.0
# Guarantees regular building/soil supplies instead of random dry spells.
const SUPPLY_CYCLE := ["Wood","Rope","Plastic","Wood","Metal","Stone","Soil","Metal","Wood","Rope","Plastic","Salvage"]
const SALVAGE_POOL := ["Sponge","Potato","Coconut","Banana","Tomato","Carrot","Onion","ElectricLamp","Screw","Wire","Motor","Battery","Solar Torch","Walkie Talkie","Binoculars"]

const ITEM_POOL := [
	"Wood", "Wood", "Wood", "Wood", "Wood", "Wood",
	"Rope", "Rope", "Rope",
	"Plastic", "Plastic",
	"Soil", "Soil",
	"Stone", "Stone",
	"Metal",
	# Whole produce drifts in occasionally. Distinct planting seeds use rare crates.
	"Sponge", "Sponge", "Potato", "Coconut", "Banana", "Tomato", "Carrot", "Onion",
	# Small worn electronics wash up; barrels/turbines must be built.
	"ElectricLamp", "Screw", "Wire", "Motor", "Battery", "Solar Torch", "Walkie Talkie", "Binoculars",
]

func _ready() -> void:
	# Keep the ambient physics-body count modest on phones. The desktop stream
	# remains denser, while mobile still starts with a visible spread of loot.
	if GameSettings.mobile_effects_profile():
		max_debris = mini(max_debris, 48)
		prewarm_count = mini(prewarm_count, 24)
	player = get_tree().get_first_node_in_group("player")
	var garden: Dictionary=Inventory.loaded_meta.get("garden_supply",{}) if Inventory.loaded_meta.get("garden_supply",{}) is Dictionary else {}
	_rare_day=maxi(1,int(garden.get("last_day",Inventory.loaded_meta.get("game_day",1))))
	_rare_cycle=maxi(0,int(garden.get("cycle",0)))
	_raft = get_tree().get_first_node_in_group("raft")
	_direction = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	if _direction.length() < 0.001:
		_direction = Vector3(0, 0, 1)
	_side = Vector3(-_direction.z, 0.0, _direction.x).normalized()
	_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
	call_deferred("_prewarm")


func _get_player() -> Node3D:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	return player

func _origin() -> Vector3:
	# Continue supplying the raft while the player explores an island, not land.
	if not is_instance_valid(_raft):_raft=get_tree().get_first_node_in_group("raft")
	if is_instance_valid(_raft):return _raft.global_position
	var p:=_get_player()
	return p.global_position if p!=null else Vector3.ZERO

func _near_count() -> int:
	var count:=0
	var origin:=_origin()
	for d in _active:
		if not is_instance_valid(d) or d.collected or d.is_hooked or d._is_fading_out:continue
		var offset: Vector3=d.global_position-origin
		offset.y=0
		if offset.length_squared()<=NEAR_RADIUS*NEAR_RADIUS:count+=1
	return count

func _next_item() -> String:
	var kind: String=SUPPLY_CYCLE[_spawn_serial%SUPPLY_CYCLE.size()]
	_spawn_serial+=1
	return str(SALVAGE_POOL.pick_random()) if kind=="Salvage" else kind


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_interval:
		_timer = 0.0
		_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
		_cleanup()
		_tick_rare_supply()
		if _active.size() < max_debris:
			_spawn_upstream()


# Fill the upstream corridor at startup — debris visible from frame 1.
func _prewarm() -> void:
	var saved: Variant=Inventory.loaded_meta.get("garden_supply",{})
	if saved is Dictionary and saved.get("boxes",[]) is Array:
		for entry in saved.get("boxes",[]).slice(0,4):
			if not entry is Dictionary or not entry.get("p") is Array or entry.p.size()!=3 or GARDEN.box_crop(str(entry.get("item",""))).is_empty():continue
			var valid:=true
			for value in entry.p:if not (value is float or value is int) or not is_finite(float(value)):valid=false
			if not valid:continue
			var at:=Vector3(float(entry.p[0]),float(entry.p[1]),float(entry.p[2]))
			if at.length()>200000:continue
			var box:=_spawn_at(-upstream_distance,8,str(entry.item))
			if box!=null:box.global_position=at;box.travel_start=at
	for i in mini(prewarm_count, max_debris):
		if not is_inside_tree() or _active.size()>=max_debris:
			return
		# Populate the existing current behind the loading screen. Runtime
		# arrivals never appear in the near lane, even when supplies run low.
		var fraction := float(i) / float(maxi(1,prewarm_count-1))
		_spawn_at(lerpf(-6.0,-upstream_distance,fraction),8.0)
		if i % 2 == 1:
			await get_tree().process_frame


# New debris always enters from upstream.
func _spawn_upstream() -> void:
	_spawn_at(-randf_range(upstream_distance,upstream_distance+6.0),8.0)


func _spawn_at(along_t: float, half_width: float=-1.0, forced_item: String="") -> Debris:
	if not debris_scene or _active.size()>=max_debris:
		return null

	var d = debris_scene.instantiate()

	var origin := _origin()

	# Random lateral position + small along-current jitter
	var width:=spawn_width*.5 if half_width<0 else half_width
	var lateral := randf_range(-width,width)
	var jitter := randf_range(-1.0,1.0)
	if absf(along_t)<5.0 and absf(lateral)<3.0:lateral=3.5 if lateral>=0 else -3.5
	var spawn_point := origin + _direction * (along_t + jitter) + _side * lateral

	d.item_name = _next_item() if forced_item.is_empty() else forced_item
	d.current_direction = _direction
	d.current_speed = clampf(current_speed,0.1,0.45) * randf_range(0.85, 1.10)
	d.travel_start = spawn_point
	d._fade_duration = 4.0
	d.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))

	d.position = spawn_point
	d.position.y = 0.0

	add_child(d)
	_active.append(d)
	return d

func _tick_rare_supply() -> void:
	var actor:=_get_player()
	if actor==null or not actor.restoration_complete or _active.size()>=max_debris:return
	var day: int=actor.get_survival_day()
	if day-_rare_day<3:return
	var item: String=GARDEN.NEW_CROPS[_rare_cycle%GARDEN.NEW_CROPS.size()]+" Garden Box"
	if _spawn_at(-randf_range(upstream_distance,upstream_distance+6),2.5,item)==null:return
	_rare_day=day;_rare_cycle+=1;actor.call("_queue_save")

func save_garden_supply() -> Dictionary:
	var boxes: Array=[]
	for debris in _active:
		if not is_instance_valid(debris) or debris.collected or debris._is_fading_out or GARDEN.box_crop(debris.item_name).is_empty():continue
		var at: Vector3=debris.global_position
		boxes.append({"item":debris.item_name,"p":[at.x,at.y,at.z]})
	return {"last_day":_rare_day,"cycle":_rare_cycle,"boxes":boxes}


func _cleanup() -> void:
	var origin:=_origin()
	for i in range(_active.size() - 1, -1, -1):
		var d = _active[i]
		if not is_instance_valid(d):
			_active.remove_at(i)
			continue
		if d.freeze or d.is_hooked or d.collected:
			continue
		var offset: Vector3=d.global_position-origin
		offset.y=0
		var along:=offset.dot(_direction)
		# Relative to the sailing raft, so distant bodies cannot fill the cap.
		if (along>downstream_distance or along< -upstream_distance-10 or absf(offset.dot(_side))>spawn_width*.8) and not d._is_fading_out:
			d.start_fade_out()
		if d.is_fade_done():
			d.queue_free()
			_active.remove_at(i)
