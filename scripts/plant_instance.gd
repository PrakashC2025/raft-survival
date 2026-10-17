extends StaticBody3D
class_name PlantInstance

## Shared growth/harvest behavior reads PlantDB definitions. Supplied crop
## geometry is selected in the visual builders below.
##
## Stages: SEED -> SPROUT -> GROWING -> MATURE
##   ROOT plants:  MATURE = ready to dig (hold E). Digging removes the plant.
##   FRUIT_TREE:   MATURE = trunk+canopy grown; fruit slots then progress
##                 bud -> small -> growing -> ripe on their own timers. Tap E
##                 near a ripe fruit to pick THAT fruit (tree stays, slot
##                 regrows). Aim at the trunk and hold E to chop; when the
##                 tree runs out of health it falls over and becomes a STUMP.
##
## Growth is not a static model swap: every stage is built from parts whose
## container scale animates continuously through the stage, so the plant
## visibly grows rather than popping. Trees get a gentle wind sway.

enum Stage { SEED, SPROUT, GROWING, MATURE, FALLING, STUMP }

const CAT_ROOT := "ROOT"
const CAT_FRUIT := "FRUIT_TREE"
const PALM_TALL_SCENE: PackedScene = preload("res://models/coconut_palm_single.glb")
const TOMATO_SCENE: PackedScene = preload("res://models/tomato_plant.glb")
const POTATO_SCENE: PackedScene = preload("res://models/potato_plant.glb")
const CARROT_SCENE: PackedScene = preload("res://models/carrot_plant.glb")
const ONION_STAGES := [preload("res://models/onion_sprout.glb"),preload("res://models/onion_young.glb"),preload("res://models/onion_growing.glb"),preload("res://models/onion_plant.glb")]
const BANANA_PLANT_SCENE: PackedScene = preload("res://models/banana_plant.glb")
const VEGETATION_VISUAL := preload("res://scripts/vegetation_visual.gd")
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")
const PRODUCE_VISUAL := preload("res://scripts/produce_visual.gd")
const COCONUT_SCENE: PackedScene = preload("res://models/kenney_coconut.glb")
const BANANA_SCENE: PackedScene = preload("res://models/kenney_banana.glb")
const CHOP_SOUND: AudioStream = preload("res://audio/contact/hammer.wav")
const HARVEST_SOUND: AudioStream = preload("res://audio/contact/cloth.wav")
const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/food_pickup.tscn")
# Height fraction reached at the END of each stage (indexed by Stage.SEED..MATURE)
const STAGE_FRAC := [0.16, 0.30, 0.62, 1.0]
const COCONUT_FRAC := [0.16, 0.30, 0.62, 1.0]

@export var plant_id: String = ""

var _def: Dictionary = {}
var _db: Node = null
var _stage: int = Stage.SEED
var _stage_timer: float = 0.0
var _grow: float = STAGE_FRAC[0]   # current visual growth scale (continuous)

var _visual: Node3D = null
var _container: Node3D = null      # scaled stage content (whole-plant growth)
var _col_shape: CollisionShape3D = null

# Deterministic per-plant variation (stable for the life of the plant)
var _rng := RandomNumberGenerator.new()
var _hvar: float = 1.0             # height variation 0.93..1.07
var _wind_phase: float = 0.0
var _wind_phase2: float = 0.0
var _wind_freq: float = 1.0

# One entry per fruit slot:
# {"pos": Vector3 (local), "elapsed": float, "regrow": float, "mesh": Node3D}
var _fruits: Array = []

# Hold-to-harvest state (chop / dig / stump removal)
var _holding: bool = false
var _hold_progress: float = 0.0
var _hold_target: float = 1.0
var _hold_kind: String = ""
var _hold_contact := false
var _health: int = 0
var _fell_axis: Vector3 = Vector3.FORWARD
var _pending_dig_drop: Dictionary = {}
var _harvesting := false
var _pending_fell_drops: Dictionary = {}

# Small debris chips (wood/soil) flying briefly after hits
var _chips: Array = []

var _player: Node3D = null
var _progress_ui: Control = null
var _progress_bar: ColorRect = null
var _prompt_label: Label = null
var _anim_t: float = 0.0


func _ready() -> void:
	add_to_group("plant")
	collision_layer = 1
	collision_mask = 0
	# Resolve the PlantDB autoload at RUNTIME (/root) rather than by the global
	# identifier: class_name scripts are parsed before autoload names exist in
	# a freshly-loaded editor, which used to raise "PlantDB not declared".
	_db = get_node_or_null("/root/PlantDB")
	if _db == null:
		push_warning("[Plant] PlantDB autoload missing")
		queue_free()
		return
	_def = _db.get_def(plant_id)
	if _def.is_empty():
		push_warning("[Plant] Unknown plant_id: " + plant_id)
		queue_free()
		return
	# Deterministic variation: same plant always looks the same, different
	# plants of the same type differ slightly.
	_rng.seed = int(get_instance_id())
	_hvar = 1.0 + _rng.randf_range(-0.07, 0.07)
	_wind_phase = _rng.randf_range(0.0, TAU)
	_wind_phase2 = _rng.randf_range(0.0, TAU)
	_wind_freq = _rng.randf_range(0.9, 1.3)
	_health = int(_def.get("chop_hits_required", 4))

	_col_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	_col_shape.shape = shape
	_col_shape.position = Vector3(0, 0.25, 0)
	add_child(_col_shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_container = Node3D.new()
	_container.name = "StageMesh"
	_visual.add_child(_container)
	_grow = _growth_fraction(Stage.SEED)
	_container.scale = Vector3(_grow, _grow, _grow)
	_rebuild_visual()
	_build_progress_ui()


func _exit_tree() -> void:
	if is_instance_valid(_progress_ui):_progress_ui.queue_free()


func save_state() -> Dictionary:
	var saved_stage := _stage
	var saved_health := _health
	# Do not persist a half-played fall tween: retry the final chop after load.
	if saved_stage == Stage.FALLING:
		saved_stage = Stage.MATURE
		saved_health = 1
	var fruit_states: Array[Dictionary] = []
	for fruit in _fruits:
		var fruit_position: Vector3 = fruit.get("pos", Vector3.ZERO)
		fruit_states.append({
			"p": [fruit_position.x, fruit_position.y, fruit_position.z],
			"r": float(fruit.get("rotation_y", 0.0)),
			"e": float(fruit.get("elapsed", 0.0)),
			"g": float(fruit.get("regrow", 60.0)),
		})
	return {
		"id": plant_id,
		"stage": saved_stage,
		"timer": _stage_timer,
		"health": saved_health,
		"fruits": fruit_states,
		"fruit_layout": 2 if plant_id == "Coconut" else 0,
	}


func restore_state(state: Dictionary) -> void:
	if str(state.get("id", plant_id)) != plant_id:
		return
	_stage = clampi(int(state.get("stage", Stage.SEED)), Stage.SEED, Stage.STUMP)
	if _stage == Stage.FALLING:
		_stage = Stage.MATURE
		_health = 1
	else:
		_health = maxi(0, int(state.get("health", _health)))
	_stage_timer = maxf(0.0, float(state.get("timer", 0.0)))
	if _stage < Stage.MATURE:
		_stage_timer = minf(_stage_timer, _stage_time(_stage))
	else:
		_stage_timer = 0.0
	_rebuild_visual()
	if _stage < Stage.MATURE:
		var needed := maxf(_stage_time(_stage), 0.001)
		var from_scale: float = _growth_fraction(_stage)
		var to_scale: float = _growth_fraction(clampi(_stage + 1, 0, Stage.MATURE))
		_grow = lerpf(from_scale, to_scale, clampf(_stage_timer / needed, 0.0, 1.0))
	else:
		_grow = 1.0
	_container.scale = Vector3.ONE * _grow
	_update_collision()
	if _stage == Stage.STUMP:
		_container.scale = Vector3.ONE
		return
	if _stage != Stage.MATURE or _def.get("category", "") != CAT_FRUIT:
		return
	var fruit_states: Variant = state.get("fruits", [])
	if fruit_states is Array:
		for i in range(mini(fruit_states.size(), _fruits.size())):
			var saved_fruit: Variant = fruit_states[i]
			if not (saved_fruit is Dictionary):
				continue
			var fruit: Dictionary = _fruits[i]
			var coordinates: Array = saved_fruit.get("p", [])
			# Legacy coconut positions belong to the former 3.37m tree. Keep
			# ripeness/timers, using new crown sockets rather than floating fruit.
			if coordinates.size() >= 3 and (plant_id != "Coconut" or int(state.get("fruit_layout",0)) == 2):
				fruit["pos"] = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
			fruit["rotation_y"] = float(saved_fruit.get("r", fruit.get("rotation_y", 0.0)))
			fruit["regrow"] = maxf(0.1, float(saved_fruit.get("g", fruit.get("regrow", 60.0))))
			fruit["elapsed"] = clampf(float(saved_fruit.get("e", 0.0)), 0.0, float(fruit["regrow"]))
			_fruits[i] = fruit
	_update_fruits(0.0)


# ============================================================
# GROWTH
# ============================================================
func _stage_time(idx: int) -> float:
	var arr: Array = _def.get("grow_stage_time", [15.0, 25.0, 20.0])
	if idx < 0 or idx >= arr.size():
		return 20.0
	return float(arr[idx])


func growth_seconds_remaining() -> float:
	if _stage >= Stage.MATURE:return 0.0
	var remaining := maxf(0.0,_stage_time(_stage)-_stage_timer)
	for stage_index in range(_stage+1,Stage.MATURE):remaining += _stage_time(stage_index)
	var planter := get_parent().get_parent() as Planter
	return remaining / (planter.growth_factor() if planter != null else 1.0)


func growth_caption() -> String:
	var seconds := ceili(growth_seconds_remaining())
	var timer := "%d:%02d" % [floori(seconds/60.0),seconds%60]
	var planter := get_parent().get_parent() as Planter
	return plant_id+" · "+timer+" until grown"+(" · DRY SOIL — WATER" if planter != null and planter.moisture<0.15 else "")


func _process(delta: float) -> void:
	_anim_t += delta
	_update_chips(delta)
	if _harvesting:
		return

	if _stage == Stage.FALLING or _stage == Stage.STUMP:
		_update_interaction(delta)
		return

	# --- Continuous growth: advance the stage timer and, while not mature,
	#     keep the container scale interpolating through the stage so the
	#     plant grows smoothly instead of popping between models.
	if _stage < Stage.MATURE:
		var planter := get_parent().get_parent() as Planter
		_stage_timer += delta * (planter.growth_factor() if planter != null else 1.0)
		var needed: float = _stage_time(_stage)
		if _stage_timer >= needed:
			_stage_timer = 0.0
			_stage += 1
			_rebuild_visual()
			_grow = _growth_fraction(clampi(_stage, 0, 3))
			_container.scale = Vector3(_grow, _grow, _grow)
			_play_grow_pop()
		else:
			var from: float = _growth_fraction(_stage)
			var to: float = _growth_fraction(clampi(_stage + 1, 0, 3))
			_grow = lerpf(from, to, clampf(_stage_timer / needed, 0.0, 1.0))
			_container.scale = Vector3(_grow, _grow, _grow)
		_update_collision()
	elif _def.get("category", "") == CAT_FRUIT:
		_update_fruits(delta)

	_update_wind(delta)
	_update_interaction(delta)


func _update_wind(_delta: float) -> void:
	if _stage == Stage.FALLING or _stage == Stage.STUMP:
		return
	var t := _anim_t
	# Gentle irregular sway — stronger for tall plants. Base sway is small so
	# the plant feels alive without looking storm-tossed.
	var height_amp: float = 0.02 + minf(0.035, float(_def.get("trunk_height", 0.6)) * 0.012 * _hvar)
	var rot_z := sin(t * _wind_freq + _wind_phase) * height_amp \
		+ sin(t * _wind_freq * 0.53 + _wind_phase2) * height_amp * 0.5
	var rot_x := sin(t * _wind_freq * 0.71 + _wind_phase2) * height_amp * 0.35
	_visual.rotation = Vector3(rot_x, 0.0, rot_z)
	_visual.rotation.y = 0.0


# ============================================================
# VISUALS
# ============================================================
func _rebuild_visual() -> void:
	for c in _container.get_children():
		_container.remove_child(c)
		c.queue_free()
	for fruit in _fruits:
		var hit: CollisionShape3D = fruit.get("hit_shape")
		if is_instance_valid(hit):remove_child(hit);hit.queue_free()
	_fruits.clear()
	var cat: String = _def.get("category", "")
	if _stage >= Stage.FALLING:
		return
	if _stage == Stage.STUMP:
		_build_stump_visual()
		return
	if cat == CAT_ROOT:
		_build_root_visual(_stage)
	else:
		_build_tree_visual(_stage)
	if _stage == Stage.MATURE and cat == CAT_FRUIT:
		_init_fruit_slots()


func _growth_fraction(stage: int) -> float:
	return float(COCONUT_FRAC[stage] if plant_id=="Coconut" else STAGE_FRAC[stage])

func _grow_y(v: float) -> float:
	# bakes in per-plant height variation
	return v * _hvar


func _root_leaf_count(stage: int) -> int:
	match stage:
		Stage.SEED:
			return 2
		Stage.SPROUT:
			return 3
		Stage.GROWING:
			return 5
		Stage.MATURE:
			return 7
		_:
			return 0


func _build_root_visual(stage: int) -> void:
	if bool(_def.get("garden_crop",false)):
		var garden:=preload("res://scripts/garden_visual.gd").plant(plant_id,stage==Stage.MATURE)
		garden.scale=Vector3.ONE*_hvar;_container.add_child(garden);return
	if plant_id == "Onion":
		var onion := ONION_STAGES[clampi(stage,Stage.SEED,Stage.MATURE)].instantiate() as Node3D
		onion.name = "OnionPlantModel"
		onion.scale = Vector3.ONE * _hvar
		_container.add_child(onion)
		VEGETATION_VISUAL.apply_crop(onion)
		return
	# A recognisable small plant is visible from planting onward.
	if plant_id in ["Tomato", "Potato", "Carrot"]:
		var scene := TOMATO_SCENE if plant_id == "Tomato" else (POTATO_SCENE if plant_id=="Potato" else CARROT_SCENE)
		var crop := scene.instantiate() as Node3D
		crop.name = plant_id + "PlantModel"
		_container.add_child(crop)
		# Import roots are at the soil line; tubers stay underneath until pulled.
		crop.scale = Vector3.ONE * (0.55 if plant_id == "Tomato" else (0.85 if plant_id=="Potato" else 1.0)) * _hvar
		for part in crop.find_children("*", "MeshInstance3D", true, false):
			var part_name := str(part.name)
			if part_name == "PotatoTuber" or part_name.begins_with("Tomato_"):
				# Growing fruit uses the same irregular skin as the harvested food.
				var food := PRODUCE_VISUAL.create("Potato" if part_name == "PotatoTuber" else "Tomato")
				var bounds: AABB = (part as MeshInstance3D).get_aabb()
				var source: AABB = (food.get_child(0) as MeshInstance3D).get_aabb()
				food.position = bounds.get_center()
				food.scale = bounds.size/source.size
				(part as MeshInstance3D).mesh = null
				part.add_child(food)
			if part_name.begins_with("Tomato_") or part_name in ["Flower", "PotatoFlower"]:
				(part as Node3D).visible = stage == Stage.MATURE
		VEGETATION_VISUAL.apply_crop(crop)
		return

	var leaf_col: Color = _def.get("leaf_color", Color(0.25, 0.55, 0.2))
	# Mature potato foliage reads slightly brighter/yellower = harvest-ready.
	if stage == Stage.MATURE:
		leaf_col = leaf_col.lightened(0.08)
	var n := _root_leaf_count(stage)
	var blade_h: float = 0.42 * _hvar
	for i in n:
		var blade := MeshInstance3D.new()
		var leaf := SphereMesh.new()
		leaf.radius = 1.0
		leaf.height = 2.0
		leaf.radial_segments = 12
		leaf.rings = 6
		blade.mesh = leaf
		blade.scale = Vector3(0.035, blade_h * 0.45, 0.009)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = leaf_col.lightened(_rng.randf_range(0.0, 0.12))
		blade.material_override = mat
		var ang: float = float(i) / float(n) * TAU + _rng.randf_range(-0.3, 0.3)
		var r: float = _rng.randf_range(0.03, 0.07)
		blade.position = Vector3(cos(ang) * r, blade_h * 0.5, sin(ang) * r)
		blade.rotation = Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
		_container.add_child(blade)
	# Produce is visible among mature leaves; carrots show a root crown.
	if stage == Stage.MATURE and plant_id in ["Tomato", "Carrot"]:
		for fruit_index in range(3):
			var produce := MeshInstance3D.new()
			var fruit_mesh := SphereMesh.new()
			fruit_mesh.radius = 0.042
			fruit_mesh.height = 0.084
			fruit_mesh.radial_segments = 16
			fruit_mesh.rings = 8
			produce.mesh = fruit_mesh
			produce.position = Vector3(cos(fruit_index * 2.1) * 0.08, 0.24 if plant_id == "Tomato" else 0.025, sin(fruit_index * 2.1) * 0.08)
			produce.material_override = OBJECT_MATERIALS.make(OBJECT_MATERIALS.Kind.FOOD, Color(0.66, 0.055, 0.018) if plant_id == "Tomato" else Color(0.8, 0.32, 0.04), 0.6)
			_container.add_child(produce)
	# Mature ready cue: two tiny pale tuber bumps at the base.
	if stage == Stage.MATURE:
		for k in 2:
			var bump := MeshInstance3D.new()
			var bs := SphereMesh.new()
			bs.radius = 0.022
			bs.height = 0.044
			bump.mesh = bs
			var a: float = TAU * 0.5 * float(k) + 0.7
			bump.position = Vector3(cos(a) * 0.045, 0.012, sin(a) * 0.045)
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.55, 0.44, 0.26)
			bump.material_override = bmat
			_container.add_child(bump)


func _build_tree_visual(stage: int) -> void:
	if plant_id=="Papaya":
		var papaya:=preload("res://scripts/garden_visual.gd").plant(plant_id,stage==Stage.MATURE)
		papaya.scale=Vector3.ONE*_hvar;_container.add_child(papaya)
		papaya.get_node("Canopy").reparent(_container)
		_update_collision();return
	if plant_id == "Coconut":
		_build_coconut_palm_visual(stage)
		return
	if plant_id == "Banana":
		var banana := BANANA_PLANT_SCENE.instantiate() as Node3D
		banana.name = "BananaPlantModel"
		_container.add_child(banana)
		for candidate in banana.find_children("*","MeshInstance3D",true,false):
			var mesh := candidate as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material != null:material.vertex_color_use_as_albedo=true
		VEGETATION_VISUAL.apply_crop(banana)
		var target_height: float = _grow_y(float(_def.get("trunk_height",2.2)))
		var bounds := _node_local_aabb(banana)
		var model_scale := target_height/maxf(bounds.size.y,0.01)
		banana.scale = Vector3.ONE*model_scale
		banana.position = Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*model_scale
		if stage >= Stage.MATURE:
			var crown := Node3D.new()
			crown.name = "Canopy"
			crown.position = Vector3(0,target_height*0.84,0)
			_container.add_child(crown)
		_update_collision()
		return
	var trunk_h: float = _grow_y(float(_def.get("trunk_height", 2.2)))
	var trunk_r: float = float(_def.get("trunk_radius", 0.13))
	var canopy_r: float = _grow_y(float(_def.get("canopy_radius", 0.9)))

	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_r * 0.8
	cyl.bottom_radius = trunk_r
	cyl.height = maxf(trunk_h, 0.05)
	trunk.mesh = cyl
	trunk.position = Vector3(0, cyl.height * 0.5, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = _def.get("trunk_color", Color(0.5, 0.36, 0.2))
	trunk.material_override = tmat
	_container.add_child(trunk)

	if stage >= Stage.GROWING:
		var canopy := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = maxf(canopy_r, 0.05)
		sph.height = sph.radius * 2.0
		canopy.mesh = sph
		canopy.position = Vector3(0, trunk_h + canopy_r * 0.55, 0)
		canopy.name = "Canopy"
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = _def.get("canopy_color", Color(0.2, 0.5, 0.2))
		canopy.material_override = cmat
		_container.add_child(canopy)

	_update_collision()


func _build_coconut_palm_visual(stage: int) -> void:
	var target_height:=_grow_y(float(_def.get("trunk_height",5.8))+float(_def.get("canopy_radius",2.0))*0.7)
	if stage<Stage.GROWING:
		var young:=Node3D.new();young.name="CoconutSeedling";_container.add_child(young)
		var stem:=MeshInstance3D.new();stem.name="YoungPalmStem"
		var shape:=CylinderMesh.new();shape.height=target_height*.70;shape.bottom_radius=.16;shape.top_radius=.065;shape.radial_segments=10;stem.mesh=shape
		stem.position.y=shape.height*.5;stem.material_override=OBJECT_MATERIALS.make(OBJECT_MATERIALS.Kind.WOOD,Color(.39,.36,.16),.92);young.add_child(stem)
		var leaves:=MeshInstance3D.new();leaves.name="YoungPalmLeaves";leaves.mesh=VEGETATION_VISUAL.palm_fronds();leaves.scale=Vector3(6,target_height*1.9,6);leaves.position.y=shape.height
		var material:=ShaderMaterial.new();material.shader=preload("res://shaders/palm_leaf.gdshader");leaves.material_override=material;leaves.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;young.add_child(leaves)
		var young_bounds:=_node_local_aabb(young)
		young.scale=Vector3.ONE*target_height/maxf(young_bounds.end.y,.01)
		_update_collision();return
	var palm := PALM_TALL_SCENE.instantiate() as Node3D
	if palm == null:
		push_warning("[Plant] Could not instance coconut palm model")
		return
	palm.name = "CoconutPalm"
	_container.add_child(palm)
	VEGETATION_VISUAL.apply_palm(palm)
	var bounds := _node_local_aabb(palm)
	if bounds.size.y <= 0.001:
		push_warning("[Plant] Coconut palm model has no measurable height")
		return
	var model_scale: float=target_height/bounds.size.y
	palm.scale=Vector3.ONE*model_scale
	# Anchor the curved model at its lowest trunk vertices, not canopy centre.
	var trunk:=palm.find_child("Tree_0_Trunk",true,false) as MeshInstance3D
	var root_point:=Vector3(0,bounds.position.y,0)
	var crown_point:=Vector3(0,bounds.position.y+bounds.size.y*.76,0)
	if trunk!=null:
		var relative:=palm.global_transform.affine_inverse()*trunk.global_transform
		var points: PackedVector3Array=trunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lower:=INF;var upper:=-INF
		for point in points:
			lower=minf(lower,(relative*point).y);upper=maxf(upper,(relative*point).y)
		var sum:=Vector3.ZERO;var count:=0
		for point in points:
			var at: Vector3=relative*point
			if at.y<=lower+.03:sum+=at;count+=1
		if count>0:root_point=sum/float(count);root_point.y=lower
		sum=Vector3.ZERO;count=0
		for point in points:
			var at: Vector3=relative*point
			if at.y>=upper-.03:sum+=at;count+=1
		if count>0:crown_point=sum/float(count)
	palm.position=-root_point*model_scale

	# Fruit sockets sit just beneath the crown; keeping this as a lightweight
	# marker preserves the existing staggered grow/pick/regrow behaviour.
	if stage >= Stage.MATURE:
		var canopy := Node3D.new()
		canopy.name = "Canopy"
		canopy.position = (crown_point-root_point)*model_scale
		_container.add_child(canopy)
	_update_collision()


func _node_local_aabb(root: Node3D) -> AABB:
	return VEGETATION_VISUAL.local_bounds(root)


func _update_collision() -> void:
	if _col_shape == null or not (_col_shape.shape is BoxShape3D):
		return
	var box := _col_shape.shape as BoxShape3D
	if _stage == Stage.STUMP:
		box.size = Vector3(0.4, 0.3, 0.4)
		_col_shape.position = Vector3(0, 0.15, 0)
		return
	if _def.get("category","")==CAT_ROOT:
		box.size = Vector3(0.30,maxf(0.16,0.6*_grow),0.30)
	else:
		var trunk_h: float = _grow_y(float(_def.get("trunk_height", 2.2)))
		# Only the stem is solid; broad invisible canopy boxes blocked walking.
		box.size = Vector3(maxf(0.18,float(_def.get("trunk_radius",0.13))*2.0*_grow),maxf(0.25,trunk_h*_grow),maxf(0.18,float(_def.get("trunk_radius",0.13))*2.0*_grow))
	_col_shape.position = Vector3(0, box.size.y * 0.5, 0)


func _build_stump_visual() -> void:
	var trunk_r: float = float(_def.get("trunk_radius", 0.13))
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_r * 0.95
	cyl.bottom_radius = trunk_r * 1.25
	cyl.height = 0.3
	base.mesh = cyl
	base.position = Vector3(0, 0.15, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = _def.get("trunk_color", Color(0.5, 0.36, 0.2)).darkened(0.15)
	base.material_override = tmat
	_container.add_child(base)
	# Fresh lighter cut surface on top.
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = trunk_r * 0.8
	capm.bottom_radius = trunk_r * 0.9
	capm.height = 0.03
	cap.mesh = capm
	cap.position = Vector3(0, 0.3, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.68, 0.55, 0.36)
	cap.material_override = cmat
	_container.add_child(cap)
	_update_collision()


# ============================================================
# FRUITS — per-slot progression: bud -> small -> growing -> ripe
# ============================================================
func _init_fruit_slots() -> void:
	var canopy: Node3D = _container.get_node_or_null("Canopy")
	if canopy == null:
		return
	var count: int = int(_def.get("fruit_count", 4))
	var canopy_r: float = .5 if plant_id=="Coconut" else _grow_y(float(_def.get("canopy_radius", 0.9)))
	var regrow: float = float(_def.get("fruit_regrow_time", 60.0))
	for i in count:
		var ang: float = float(i) / float(count) * TAU + _rng.randf_range(-0.25, 0.25)
		var jitter: float = _rng.randf_range(0.62, 0.82)
		var local_pos: Vector3 = canopy.position \
			+ Vector3(cos(ang) * canopy_r * jitter, -canopy_r * _rng.randf_range(0.1, 0.25), sin(ang) * canopy_r * jitter)
		# Staggered start so fruits reach ripeness at different times.
		var slot_regrow: float = regrow * _rng.randf_range(0.9, 1.1)
		var fruit_hit := CollisionShape3D.new()
		var sphere := SphereShape3D.new();sphere.radius = maxf(0.13,float(_def.get("fruit_radius",0.1))*1.3)
		fruit_hit.shape = sphere;fruit_hit.position = local_pos;fruit_hit.disabled = true
		add_child(fruit_hit)
		_fruits.append({
			"pos": local_pos,
			"rotation_y": ang + _rng.randf_range(-0.6, 0.6),
			"elapsed": _rng.randf_range(0.0, regrow * 0.5),
			"regrow": slot_regrow,
			"mesh": null,
			"hit_shape": fruit_hit,
		})


func _update_fruits(delta: float) -> void:
	for f in _fruits:
		f["elapsed"] = float(f["elapsed"]) + delta
		var regrow: float = float(f["regrow"])
		var prog: float = clampf(float(f["elapsed"]) / regrow, 0.0, 1.0)
		var fruit_hit: CollisionShape3D = f.get("hit_shape")
		if is_instance_valid(fruit_hit):
			fruit_hit.position = f["pos"]
			fruit_hit.set_deferred("disabled",prog<1.0)
		var m := f.get("mesh") as Node3D
		if prog < 0.06:
			if m != null and is_instance_valid(m):
				m.queue_free()
				f["mesh"] = null
			continue
		if m == null or not is_instance_valid(m):
			m = _make_fruit_mesh()
			f["mesh"] = m
			_container.add_child(m)
		m.position = f["pos"]
		m.rotation.y = float(f.get("rotation_y", 0.0))
		var size_t := clampf((prog - 0.06) / 0.94, 0.0, 1.0)
		size_t = size_t * size_t * (3.0 - 2.0 * size_t)
		m.scale = Vector3.ONE * (0.12 + 0.88 * size_t)


func _make_fruit_mesh() -> Node3D:
	if plant_id=="Papaya":return preload("res://scripts/garden_visual.gd").produce(plant_id)
	if plant_id == "Banana":
		return preload("res://scripts/produce_visual.gd").create("Banana")
	var root := Node3D.new()
	root.name = "FruitVisual"
	var fruit_scene: PackedScene = null
	if plant_id == "Coconut":
		fruit_scene = COCONUT_SCENE
	elif plant_id == "Banana":
		fruit_scene = BANANA_SCENE
	if fruit_scene != null:
		var model := fruit_scene.instantiate() as Node3D
		if model != null:
			OBJECT_MATERIALS.apply_model(model, OBJECT_MATERIALS.Kind.FOOD)
			root.add_child(model)
			var bounds := _node_local_aabb(model)
			var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			if largest > 0.001:
				var target_size: float = float(_def.get("fruit_radius", 0.1)) * 2.0
				var model_scale: float = target_size / largest
				model.scale = Vector3.ONE * model_scale
				model.position = -bounds.get_center() * model_scale
				return root
			model.queue_free()

	# Safe visual fallback for custom plant definitions without a matching GLB.
	var fallback := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var fruit_radius: float = float(_def.get("fruit_radius", 0.1))
	sphere.radius = fruit_radius
	sphere.height = fruit_radius * 2.0
	fallback.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = _def.get("fruit_color", Color(0.8, 0.6, 0.2))
	material.roughness = 0.82
	fallback.material_override = material
	root.add_child(fallback)
	return root


# ============================================================
# SMALL EFFECTS
# ============================================================
func _play_grow_pop() -> void:
	# Gentle settle bump on stage change so growth reads as alive, not a pop.
	var tw := create_tween()
	var base: Vector3 = Vector3(_grow, _grow, _grow)
	_container.scale = base * 1.12
	tw.tween_property(_container, "scale", base, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_chips(color: Color, count: int, spread: float) -> void:
	if count <= 0:
		return
	for i in count:
		var chip := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.03, 0.03, 0.03) * _rng.randf_range(0.6, 1.4)
		chip.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.lightened(_rng.randf_range(-0.08, 0.1))
		chip.material_override = mat
		chip.position = Vector3(0, 0.4, 0)
		add_child(chip)
		var vel := Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(1.2, 2.2), _rng.randf_range(-spread, spread))
		_chips.append({"node": chip, "vel": vel, "life": _rng.randf_range(0.35, 0.6)})


func _update_chips(delta: float) -> void:
	var keep: Array = []
	for c in _chips:
		var node: Node3D = c["node"]
		if node == null or not is_instance_valid(node):
			continue
		c["life"] = float(c["life"]) - delta
		if float(c["life"]) <= 0.0:
			node.queue_free()
			continue
		c["vel"] = Vector3(c["vel"]) + Vector3(0, -9.0, 0) * delta
		node.position += Vector3(c["vel"]) * delta
		node.rotation.y += delta * 6.0
		keep.append(c)
	_chips = keep


# ============================================================
# INTERACTION (self-managed — uses the player's center crosshair raycast)
# ============================================================
func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _build_progress_ui() -> void:
	var p := _get_player()
	if p == null:
		return
	var canvas: Node = p.get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	_progress_ui = Control.new()
	_progress_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_ui.visible = false
	canvas.add_child(_progress_ui)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.4)
	back.size = Vector2(180, 14)
	_progress_ui.add_child(back)

	_progress_bar = ColorRect.new()
	_progress_bar.color = Color(0.4, 0.9, 0.4, 0.9)
	_progress_bar.size = Vector2(0, 14)
	_progress_ui.add_child(_progress_bar)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_progress_ui.add_child(_prompt_label)

	var vp := p.get_viewport().get_visible_rect().size
	back.position = Vector2(vp.x * 0.5 - 90.0, vp.y * 0.62)
	_progress_bar.position = back.position
	_prompt_label.position = Vector2(back.position.x, back.position.y - 22.0)


func _is_player_aiming_here() -> bool:
	var p := _get_player()
	if p == null:
		return false
	if p.get("build_mode") == true or p.get("_editing") != null:
		return false
	var hud := p.get_node_or_null("CanvasLayer/SurvivalHUD")
	if hud != null and hud.call("gameplay_input_blocked"):return false
	if p.get("aim_valid") != true:
		return false
	var planter := get_parent().get_parent() as Planter
	if p.get("aim_collider") != self and (planter == null or p.get("aim_collider") != planter):
		return false
	var dist = p.get("aim_distance")
	return dist != null and float(dist) <= 3.5


func _aim_local() -> Vector3:
	var p := _get_player()
	if p == null:
		return Vector3.ZERO
	var aim_point: Variant = p.get("aim_point")
	if aim_point is Vector3:
		return global_transform.affine_inverse() * (aim_point as Vector3)
	return Vector3.ZERO


# The exact fruit the crosshair points at = the ripe fruit whose position is
# nearest to the raycast hit point on the plant (within reach).
func _nearest_ripe_fruit() -> Dictionary:
	var aim_local := _aim_local()
	var best: float = 0.55
	var best_f = null
	for f in _fruits:
		var regrow: float = float(f["regrow"])
		if float(f["elapsed"]) < regrow:
			continue  # not ripe yet
		var d: float = (f["pos"] - aim_local).length()
		if d < best:
			best = d
			best_f = f
	return {"dist": best, "fruit": best_f}


func _update_interaction(delta: float) -> void:
	var p := _get_player()
	if p == null:
		return
	var aiming: bool = _is_player_aiming_here()
	if not aiming:
		if _holding:
			_cancel_hold()
		if _progress_ui != null:
			_progress_ui.visible = false
		return

	var cat: String = _def.get("category", "")

	# Stump: hold E to clear it and free the planter for a new seed.
	if _stage == Stage.STUMP:
		_show_prompt("Hold E — Remove Stump")
		_run_hold("stump", 0.6, delta)
		return

	if _stage == Stage.FALLING:
		return
	if _stage < Stage.MATURE:
		_show_prompt(growth_caption())
		return
	# Aiming soil also shows progress, but harvesting/chopping belongs to the plant.
	if p.get("aim_collider") != self:
		_show_prompt(plant_id+" · Ready — aim at plant to harvest")
		return

	if cat == CAT_FRUIT and _stage == Stage.MATURE:
		var near := _nearest_ripe_fruit()
		if near["fruit"] != null:
			_show_prompt("E — Pick " + str(_def.get("display_name", "Fruit")))
			if Input.is_action_just_pressed("interact"):
				_pick_fruit(near["fruit"])
			return
		_show_prompt("Hold E — Chop for Wood")
		_run_hold("chop", 0.9, delta)
		return

	if cat == CAT_ROOT:
		if _stage != Stage.MATURE:
			_show_prompt(growth_caption())
			return
		_show_prompt("Hold E — Harvest " + str(_def.get("display_name", "Plant")))
		_run_hold("dig", float(_def.get("dig_time", 1.5)), delta)
		return

	if cat == CAT_FRUIT:
		_show_prompt(growth_caption())
		return


func _show_prompt(text: String) -> void:
	if _progress_ui == null:
		return
	_progress_ui.visible = true
	_prompt_label.text = text


func _run_hold(kind: String, per_hit_time: float, delta: float) -> void:
	var tool_actor := _get_player()
	if tool_actor!=null:
		var equipped := str(tool_actor.get("active_item"))
		if (kind in ["chop","stump"] and equipped=="Axe" and Inventory.has("Axe",1)) \
				or (kind=="dig" and equipped=="Shovel" and Inventory.has("Shovel",1)):per_hit_time*=.60
	if not Input.is_action_pressed("interact"):
		if _holding:
			_cancel_hold()
		return
	if not _holding or _hold_kind != kind:
		_holding = true
		_hold_kind = kind
		_hold_progress = 0.0
		_hold_target = per_hit_time
		_hold_contact = false
		var actor := _get_player()
		if actor!=null:actor.call("play_action","chop" if kind in ["chop","stump"] else "scoop",per_hit_time,global_position)
	_hold_progress += delta
	if _progress_bar != null:
		_progress_bar.size.x = 180.0 * clampf(_hold_progress / _hold_target, 0.0, 1.0)
	# Axe hits, tree damage and its recorded impact share the downstroke.
	var contact_fraction:=.57 if kind in ["chop","stump"] else 1.0
	if not _hold_contact and _hold_progress >= _hold_target*contact_fraction:
		_hold_contact=true
		match kind:
			"dig":
				_do_dig()
			"chop":
				_do_chop_hit()
			"stump":
				_do_remove_stump()
	if _holding and _hold_progress >= _hold_target:
		_hold_progress=0.0;_hold_contact=false
		var actor:=_get_player()
		if actor!=null and kind in ["chop","stump"]:actor.call("play_action","chop",per_hit_time,global_position)


func _cancel_hold() -> void:
	_holding = false
	_hold_kind = ""
	_hold_progress = 0.0
	if _progress_bar != null:
		_progress_bar.size.x = 0.0


# ============================================================
# HARVEST — fruit pick
# ============================================================
func _pick_fruit(fruit) -> void:
	if fruit == null:
		return
	var yield_item: String = str(_def.get("yield_item", ""))
	var amount: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if plant_id!="Coconut" and not yield_item.is_empty() and not Inventory.can_store_rewards({yield_item: amount}):
		_notify_bag_full()
		return
	var actor := _get_player()
	if actor!=null:actor.call("play_action","pick",.85,global_position,yield_item)
	fruit["elapsed"] = 0.0
	var fruit_hit: CollisionShape3D = fruit.get("hit_shape")
	if is_instance_valid(fruit_hit):fruit_hit.set_deferred("disabled",true)
	var m = fruit.get("mesh")
	if m != null and is_instance_valid(m):
		m.queue_free()
	fruit["mesh"] = null
	if plant_id=="Coconut":
		_drop_coconut(fruit,amount)
	elif not yield_item.is_empty():
		Inventory.add(yield_item, amount)
		var player := _get_player()
		if player != null and player.has_method("play_world_sfx"):
			player.call("play_world_sfx", HARVEST_SOUND, -12.0,global_position)
	_spawn_chips(_def.get("fruit_color", Color(0.8, 0.6, 0.2)), 3, 0.25)


func _notify_bag_full() -> void:
	var player := _get_player()
	if player != null and player.has_method("_hud_toast"):
		player.call("_hud_toast", "BAG FULL  •  CLEAR SPACE BEFORE HARVEST")


# ============================================================
# HARVEST — root crop dig (plant shrinks back, planter freed)
# ============================================================
func _do_dig() -> void:
	if _harvesting:
		return
	_cancel_hold()
	_pending_dig_drop.clear()
	var yield_item: String = str(_def.get("yield_item", ""))
	if not yield_item.is_empty():
		var amount := randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
		if not Inventory.can_store_rewards({yield_item: amount}):
			_notify_bag_full()
			return
		_pending_dig_drop[yield_item] = amount
	var seed_item: String = str(_def.get("seed_item", ""))
	if not seed_item.is_empty() and not bool(_def.get("garden_crop",false)):
		_pending_dig_drop[seed_item] = 2
	if not Inventory.can_store_rewards(_pending_dig_drop):
		_pending_dig_drop.clear()
		_notify_bag_full()
		return
	_harvesting = true
	if is_instance_valid(_progress_ui):_progress_ui.visible=false
	var actor := _get_player()
	if actor!=null:actor.call("play_action","harvest",1.7 if plant_id in ["Potato","Carrot","Onion"] else .85,global_position,yield_item)
	var tw := create_tween()
	if plant_id in ["Potato","Carrot","Onion"]:
		# Lift the complete root system out of the soil before collecting it.
		# Keep foliage/tubers full size during the readable reveal.
		tw.tween_property(_container, "position:y", 0.45 if plant_id=="Carrot" else 0.38, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.0)
	tw.tween_property(_container, "scale", Vector3.ONE * 0.04, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_dig)


func _finish_dig() -> void:
	_deliver_rewards(_pending_dig_drop)
	_pending_dig_drop.clear()
	_spawn_chips(Color(0.32, 0.22, 0.14), 4, 0.35)
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()


# ============================================================
# CUTTING — health-based, configurable via PlantDB
# ============================================================
func _do_chop_hit() -> void:
	var player := _get_player()
	_health -= 2 if player!=null and player.get("active_item")=="Axe" and Inventory.has("Axe",1) else 1
	if player != null and player.has_method("play_world_sfx"):
		player.call("play_world_sfx", CHOP_SOUND, -9.0,global_position)
	var trunk_col: Color = _def.get("trunk_color", Color(0.5, 0.36, 0.2))
	_spawn_chips(trunk_col.lightened(0.15), 4, 0.3)
	# Small trunk reaction so the hit visibly registers (no camera shake).
	if is_instance_valid(_container):
		var tw := create_tween()
		_container.rotation.z += 0.06
		tw.tween_property(_container, "rotation:z", 0.0, 0.18)
	if _health <= 0:
		_start_fall()


func _start_fall() -> void:
	_cancel_hold()
	_pending_fell_drops = _roll_fell_drops()
	if not Inventory.can_store_rewards(_pending_fell_drops):
		_pending_fell_drops.clear()
		_health = 1
		_notify_bag_full()
		return
	if plant_id=="Coconut":
		for fruit in _fruits:
			if float(fruit.elapsed)>=float(fruit.regrow)*.65:_drop_coconut(fruit,1)
			fruit.elapsed=0.0
		var extra:=int(_pending_fell_drops.get("Coconut",0));_pending_fell_drops.erase("Coconut")
		if extra>0:_drop_coconut({"pos":Vector3(0,1,0)},extra)
	_stage = Stage.FALLING
	# Fall away from the player.
	var p := _get_player()
	var away := Vector3.FORWARD
	if p != null:
		var d: Vector3 = global_position - p.global_position
		if d.length() > 0.1:
			away = Vector3(d.x, 0.0, d.z).normalized()
	_fell_axis = Vector3(away.z, 0.0, -away.x).normalized()
	_visual.rotation = Vector3.ZERO
	var tw := create_tween()
	var target_ang: float = PI * 0.5 * 0.95
	tw.tween_method(_apply_fall, 0.0, target_ang, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_fell)


func _apply_fall(a: float) -> void:
	_visual.rotation = Vector3.ZERO
	_visual.rotate(_fell_axis, a)


func _roll_fell_drops() -> Dictionary:
	var rewards: Dictionary = {}
	var drops: Array = _def.get("fell_drops", [])
	for drop in drops:
		if not (drop is Array) or drop.size() < 3:
			continue
		var item_name := str(drop[0])
		var amount := randi_range(int(drop[1]), int(drop[2]))
		if amount > 0:
			rewards[item_name] = int(rewards.get(item_name, 0)) + amount
	return rewards


func _deliver_rewards(rewards: Dictionary) -> void:
	for item_name in rewards:
		var amount := maxi(0, int(rewards[item_name]))
		if amount <= 0:
			continue
		var overflow := Inventory.add(str(item_name), amount)
		if overflow > 0:
			_spawn_reward_pickup(str(item_name), overflow)


func _spawn_reward_pickup(item_name: String, amount: int) -> void:
	if amount <= 0:
		return
	var pickup := ITEM_PICKUP_SCENE.instantiate()
	if pickup == null or not (pickup is Node3D):
		if pickup != null:
			pickup.free()
		return
	pickup.set("item_name", item_name)
	pickup.set("amount", amount)
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		pickup.free()
		return
	scene_root.add_child(pickup)
	var offset := Vector3(randf_range(-0.3, 0.3), 0.55, randf_range(-0.3, 0.3))
	(pickup as Node3D).global_position = global_position + offset


func _finish_fell() -> void:
	_deliver_rewards(_pending_fell_drops)
	_pending_fell_drops.clear()
	_spawn_chips(_def.get("trunk_color", Color(0.5, 0.36, 0.2)).darkened(0.1), 6, 0.5)
	_stage = Stage.STUMP
	for c in _container.get_children():
		c.queue_free()
	for fruit in _fruits:
		var fruit_hit: CollisionShape3D = fruit.get("hit_shape")
		if is_instance_valid(fruit_hit):fruit_hit.queue_free()
	_fruits.clear()
	_build_stump_visual()
	_container.scale = Vector3.ONE
	_visual.rotation = Vector3.ZERO


func _do_remove_stump() -> void:
	_cancel_hold()
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()

func _drop_coconut(fruit: Dictionary, amount: int) -> void:
	var pickup:=ITEM_PICKUP_SCENE.instantiate() as Node3D
	pickup.item_name="Coconut";pickup.amount=amount;pickup.falling=true
	pickup.fall_exclude.append(get_rid())
	get_tree().current_scene.add_child(pickup)
	var at: Vector3=fruit.get("pos",Vector3.UP)
	var outward:=Vector3(at.x,0,at.z).normalized()
	if outward.length_squared()<.01:outward=Vector3.RIGHT
	pickup.global_position=_container.to_global(Vector3(outward.x*.82,maxf(.6,at.y),outward.z*.82))
