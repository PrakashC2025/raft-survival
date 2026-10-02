extends StaticBody3D
class_name PlantInstance

## Generic growing-plant node. Works for every entry in PlantDB — nothing
## here is specific to potato/coconut/banana; all the differences come from
## the Dictionary returned by PlantDB.get_def(id).
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
# Height fraction reached at the END of each stage (indexed by Stage.SEED..MATURE)
const STAGE_FRAC := [0.06, 0.22, 0.55, 1.0]

# ---- REAL-MODEL GROWTH (baked once by tools/bake_island_vegetation.gd
# from the coconut_palm.glb scan). Planted coconut trees grow through the
# actual scanned model: seed = tiny frond tuft, growing = short trunk +
# young crown, mature = full palm with NO coconuts baked in — fruits appear
# only through the ripening slots below. Falls back to the primitive
# cylinder/sphere tree automatically if the bake files are missing.
const GROWTH_VARIANTS := {
	"Coconut": {
		Stage.SPROUT: "res://grass/baked/coconut_sprout.res",
		Stage.GROWING: "res://grass/baked/coconut_young.res",
		Stage.MATURE: "res://grass/baked/coconut_mature.res",
	},
	# Apple tree: ONE baked glb mesh; the continuous container-scale growth
	# makes it read as small tree -> big tree -> full fruiting tree. A 1.25x
	# mesh scale at every stage (applied via the stage-entry multipliers below)
	# makes the island's rare tree a proper BIG tree — at the scanned 5.7 m it
	# read as a sapling next to the 6-7 m palms.
	"Apple": {
		Stage.SPROUT: "res://grass/baked/apple_tree.res",
		Stage.GROWING: "res://grass/baked/apple_tree.res",
		Stage.MATURE: "res://grass/baked/apple_tree.res",
	},
}
const PALM_FROND_SHADER := "res://shaders/palm_fronds_sway.gdshader"
## Preloaded (not class_name-resolved) so it works in every boot mode —
## the global class cache can lag behind newly added scripts.
const ApplePickupScript := preload("res://scripts/apple_pickup.gd")
const CoconutPickupScript := preload("res://scripts/coconut_pickup.gd")
const ISLAND_DAY_SECONDS := 900.0 # Sky3D cycle: 15 real minutes per in-game day
const PALM_DROP_DELAY := 20.0     # ripe nut hangs this long before letting go (keeps drops rare)
const PALM_REGROW_DAYS := 2.0     # a slot grows a NEW coconut every ~2 in-game days
## Tree collision lives on its OWN layer (16, "aim-only"): the player's
## CharacterBody and fruit RigidBodies (mask 1) NEVER collide with it, so
## trees stop being invisible walls and dropped fruit stops being launched
## into the sky by depenetration out of the canopy box. The player AIM ray
## (mask 3 | 1<<15) still hits it, so picking/chopping work unchanged.
const AIM_ONLY_LAYER := 1 << 15
static var _sway_mat_cache: Dictionary = {} # mesh -> Array[Material] per-surface overrides
## Extra mesh scale per plant id (on top of growth animation). The scanned
## apple tree reads small next to palms; 1.25x makes it a real tree.
const MESH_SCALE := {"Apple": 1.25}

@export var plant_id: String = ""
## Initial stage. -1 = normal seed growth; world trees (the island's rare
## apple tree) spawn already MATURE and fruiting via start_stage = 3.
@export_range(-1, 3) var start_stage: int = -1

var _def: Dictionary = {}
var _db: Node = null
var _stage: int = Stage.SEED
var _stage_timer: float = 0.0
var _grow: float = STAGE_FRAC[0]   # current visual growth scale (continuous)

var _visual: Node3D = null
var _container: Node3D = null      # scaled stage content (whole-plant growth)
var _col_shape: CollisionShape3D = null
var _trunk_shape: CollisionShape3D = null # aim cylinder along the trunk (removed on stump)

# Deterministic per-plant variation (stable for the life of the plant)
var _rng := RandomNumberGenerator.new()
var _hvar: float = 1.0             # height variation 0.93..1.07
var _wind_phase: float = 0.0
var _wind_phase2: float = 0.0
var _wind_freq: float = 1.0

# One entry per fruit slot:
# {"pos": Vector3 (local), "elapsed": float, "regrow": float, "mesh": MeshInstance3D}
var _fruits: Array = []

# Hold-to-harvest state (chop / dig / stump removal)
var _holding: bool = false
var _hold_progress: float = 0.0
var _hold_target: float = 1.0
var _hold_kind: String = ""
var _health: int = 0
var _fell_axis: Vector3 = Vector3.FORWARD

# Small debris chips (wood/soil) flying briefly after hits
var _chips: Array = []

var _player: Node3D = null
var _progress_ui: Control = null
var _progress_bar: ColorRect = null
var _prompt_label: Label = null
var _anim_t: float = 0.0

# Real-model growth state (empty when using primitive fallback):
var _growth: Dictionary = {} # stage(int) -> Mesh
var _tree_top := 0.0         # measured mature height (collision + fruit anchor)
var _crown_y := 0.0          # crown center height on the mature model
var _crown_r := 0.0          # crown spread radius on the mature model
var _crown_off := Vector2.ZERO # crown XZ offset (baked palm trunk LEANS — the crown is not above the origin)
var _regrow_wait := 0.0      # >0 while a felled island stump counts down to automatic regrowth
var _ms := 1.0               # MESH_SCALE for this plant (metrics multiply by it)


func _ready() -> void:
	add_to_group("plant")
	collision_layer = AIM_ONLY_LAYER # aim raycast target only — never a physical wall
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
	_load_growth_variants()
	if start_stage >= Stage.SEED and start_stage <= Stage.MATURE:
		_stage = start_stage

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
	_grow = STAGE_FRAC[_stage]
	_container.scale = Vector3(_grow, _grow, _grow)
	_rebuild_visual()
	_build_progress_ui()


# ============================================================
# REAL-MODEL GROWTH (scanned coconut palm)
# ============================================================
func _load_growth_variants() -> void:
	var variants: Dictionary = GROWTH_VARIANTS.get(plant_id, {})
	if variants.is_empty():
		return
	for st in variants:
		var path: String = _mobile_bake(variants[st])
		if ResourceLoader.exists(path):
			var gm: Mesh = load(path)
			_strip_detail_maps(gm)
			_growth[int(st)] = gm
	if not _growth.has(Stage.MATURE):
		_growth.clear() # incomplete set -> primitive fallback everywhere
		return
	# Per-plant mesh scale BEFORE measuring, so all metrics below are the
	# SCALED ones collision + fruit anchors actually need.
	_ms = float(MESH_SCALE.get(plant_id, 1.0))
	# Measure the mature model once: drives collision size + fruit anchors.
	var mature: Mesh = _growth[Stage.MATURE]
	var aabb := mature.get_aabb()
	_tree_top = aabb.position.y + aabb.size.y
	_crown_y = _tree_top * 0.86
	_crown_r = maxf(aabb.size.x, aabb.size.z) * 0.5
	# Canopy-fruit plants (apple tree): measure the REAL foliage mass instead
	# of guessing. The scanned tree's AABB top is bare upper twigs, so the
	# 0.86 heuristic anchored apples ~1 m ABOVE the leaves — fruit floating
	# in the air around the crown. Mean foliage-vertex height = canopy center,
	# max foliage radius = crown spread. Hang-layout plants (palm) keep the
	# heuristic: nuts belong just UNDER the fronds, not at frond height.
	if String(_def.get("fruit_layout", "hang")) == "canopy":
		var leaf_sum := 0.0
		var leaf_n := 0
		var leaf_r := 0.0
		for s in mature.get_surface_count():
			var lm := mature.surface_get_material(s)
			if lm is BaseMaterial3D and (lm as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				var lverts: PackedVector3Array = mature.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in lverts:
					leaf_sum += v.y
					leaf_n += 1
					leaf_r = maxf(leaf_r, Vector2(v.x, v.z).length())
		if leaf_n > 0:
			_crown_y = clampf(leaf_sum / float(leaf_n), aabb.position.y * 0.5 + 0.2, _tree_top)
			_crown_r = maxf(leaf_r * 0.75, 0.5)
	# Apply the mesh scale to the measured metrics (the anchors stored in mesh
	# meta are unscaled; fruit positions multiply them by _ms downstream).
	_tree_top *= _ms
	_crown_y *= _ms
	_crown_r *= _ms
	# HANG-LAYOUT CROWN OFFSET: the baked palm trunk LEANS, so the crown sits
	# displaced sideways from the plant origin. Fruit slots were placed on a
	# ring around the ORIGIN — on leaned palms the bunch (and its sparkle)
	# floated in open air beside the real crown. Mean XZ of the top-quarter
	# vertices = where the crown actually is.
	if String(_def.get("fruit_layout", "hang")) != "canopy":
		var off := Vector2.ZERO
		var on := 0
		var top_y: float = aabb.position.y + aabb.size.y
		for s in mature.get_surface_count():
			var verts: PackedVector3Array = mature.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				if v.y > top_y * 0.72:
					off += Vector2(v.x, v.z)
					on += 1
		if on > 0:
			_crown_off = (off / float(on)) * _ms

## Per-surface material overrides for a growth mesh: the alpha-scissor
## frond surface renders through the sway shader (keeping its real baked
## albedo texture); opaque surfaces (trunk, crown layers) keep their own
## imported materials. Cached statically — every planted tree shares it.
static func _tree_surface_overrides(mesh: Mesh) -> Array:
	if _sway_mat_cache.has(mesh):
		return _sway_mat_cache[mesh]
	var shader: Shader = null
	if ResourceLoader.exists(PALM_FROND_SHADER):
		shader = load(PALM_FROND_SHADER)
	var overrides: Array = []
	# ONLY the palm gets the frond sway shader. The apple tree's leaf cards
	# are alpha-scissor too — sway (keyed to palm crown heights) squeezed the
	# whole canopy down to the trunk and shredded the silhouette. Baked meshes
	# carry meta "src" (their source model), so key the shader to the palm.
	var mesh_src := String(mesh.get_meta("src", ""))
	var sway_allowed := not mesh_src.containsn("apple")
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		var use: Material = null
		if sway_allowed and shader != null and m is BaseMaterial3D \
				and (m as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			var tex = (m as BaseMaterial3D).albedo_texture
			if tex != null:
				sm.set_shader_parameter("albedo_tex", tex)
			# Scale the sway band to THIS variant's crown height so young
			# and sprout models sway too, not just the full-size palm.
			var aabb := mesh.get_aabb()
			var top := aabb.position.y + aabb.size.y
			sm.set_shader_parameter("sway_start", top * 0.55)
			sm.set_shader_parameter("sway_span", maxf(top * 0.45, 0.2))
			use = sm
		overrides.append(use)
	_sway_mat_cache[mesh] = overrides
	return overrides

func _build_real_tree_visual(mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var overrides := _tree_surface_overrides(mesh)
	for s in overrides.size():
		if overrides[s] != null:
			mi.set_surface_override_material(s, overrides[s])
	mi.scale = Vector3.ONE * _ms
	_container.add_child(mi)
	_update_collision()


# ============================================================
# GROWTH
# ============================================================
func _stage_time(idx: int) -> float:
	var arr: Array = _def.get("grow_stage_time", [15.0, 25.0, 20.0])
	if idx < 0 or idx >= arr.size():
		return 20.0
	return float(arr[idx])


func _process(delta: float) -> void:
	_anim_t += delta
	_update_chips(delta)

	if _stage == Stage.FALLING or _stage == Stage.STUMP:
		# Felled stumps count down to automatic regrowth (~1 in-game day).
		if _stage == Stage.STUMP and _regrow_wait > 0.0:
			_regrow_wait -= delta
			if _regrow_wait <= 0.0:
				_regrow_plant()
		_update_interaction(delta)
		return

	# --- Continuous growth: advance the stage timer and, while not mature,
	#     keep the container scale interpolating through the stage so the
	#     plant grows smoothly instead of popping between models.
	if _stage < Stage.MATURE:
		_stage_timer += delta
		var needed: float = _stage_time(_stage)
		if _stage_timer >= needed:
			_stage_timer = 0.0
			_stage += 1
			_rebuild_visual()
			_grow = STAGE_FRAC[clampi(_stage, 0, 3)]
			_container.scale = Vector3(_grow, _grow, _grow)
			_play_grow_pop()
		else:
			var from: float = STAGE_FRAC[_stage]
			var to: float = STAGE_FRAC[clampi(_stage + 1, 0, 3)]
			_grow = lerpf(from, to, clampf(_stage_timer / needed, 0.0, 1.0))
			_container.scale = Vector3(_grow, _grow, _grow)
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
		c.queue_free()
	_fruits.clear()
	var cat: String = _def.get("category", "")
	if _stage == Stage.FALLING:
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


func _grow_y(v: float) -> float:
	# bakes in per-plant height variation
	return v * _hvar


func _root_leaf_count(stage: int) -> int:
	match stage:
		Stage.SPROUT:
			return 3
		Stage.GROWING:
			return 5
		Stage.MATURE:
			return 7
		_:
			return 0


func _build_root_visual(stage: int) -> void:
	# SEED: a tiny seed bump half-sunk in the soil (no above-ground leaves).
	if stage == Stage.SEED:
		var seed_mesh := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.035
		sph.height = sph.radius * 2.0
		seed_mesh.mesh = sph
		seed_mesh.position = Vector3(0, 0.015, 0)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.42, 0.32, 0.16)
		seed_mesh.material_override = smat
		_container.add_child(seed_mesh)
		return

	var leaf_col: Color = _def.get("leaf_color", Color(0.25, 0.55, 0.2))
	# Mature potato foliage reads slightly brighter/yellower = harvest-ready.
	if stage == Stage.MATURE:
		leaf_col = leaf_col.lightened(0.08)
	var n := _root_leaf_count(stage)
	var blade_h: float = 0.42 * _hvar
	for i in n:
		var blade := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.028
		cyl.height = blade_h
		blade.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = leaf_col.lightened(_rng.randf_range(0.0, 0.12))
		blade.material_override = mat
		var ang: float = float(i) / float(n) * TAU + _rng.randf_range(-0.3, 0.3)
		var r: float = _rng.randf_range(0.03, 0.07)
		blade.position = Vector3(cos(ang) * r, blade_h * 0.5, sin(ang) * r)
		blade.rotation = Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
		_container.add_child(blade)
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
	# Real scanned-model growth for plants that have bake variants (coconut):
	# SEED/SPROUT show the frond tuft, GROWING the young palm, MATURE the
	# full nut-free palm. The container scale (_grow) animates continuously,
	# so the model itself visibly grows between stage swaps.
	if not _growth.is_empty():
		var gmesh: Mesh = _growth.get(stage, _growth.get(Stage.SPROUT))
		if gmesh != null:
			_build_real_tree_visual(gmesh)
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


func _update_collision() -> void:
	if _col_shape == null or not (_col_shape.shape is BoxShape3D):
		return
	var box := _col_shape.shape as BoxShape3D
	if _stage == Stage.STUMP:
		box.size = Vector3(0.4, 0.3, 0.4)
		_col_shape.position = Vector3(0, 0.15, 0)
		if _trunk_shape != null and is_instance_valid(_trunk_shape):
			_trunk_shape.queue_free() # no invisible tree trunk left over the stump
		_trunk_shape = null
		return
	if not _growth.is_empty():
		# AIM box sized from the real mature model. It covers the canopy so the
		# aim ray can reach the fruit for picking. It is on the aim-only layer:
		# the player walks straight through it and dropped fruit (rigid mask 1)
		# ignores it entirely — the old layer-1 box both blocked movement around
		# every tree AND ejected spawned apples sky-high via depenetration.
		box.size = Vector3(maxf(_crown_r * 1.6, 0.4), maxf(_tree_top, 0.5), maxf(_crown_r * 1.6, 0.4))
		_col_shape.position = Vector3(0, box.size.y * 0.5, 0)
		# Solid trunk cylinder so a chop-aim low on the tree always registers
		# even when the canopy box is thin there.
		if _trunk_shape == null or not is_instance_valid(_trunk_shape):
			_trunk_shape = CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(_tree_top * 0.045, 0.14, 0.30)
			cyl.height = maxf(_tree_top * 0.8, 0.6)
			_trunk_shape.shape = cyl
			_trunk_shape.position = Vector3(0, cyl.height * 0.5, 0)
			_col_shape.add_sibling(_trunk_shape)
		return
	var trunk_h: float = _grow_y(float(_def.get("trunk_height", 2.2)))
	var canopy_r: float = _grow_y(float(_def.get("canopy_radius", 0.9)))
	box.size = Vector3(maxf(canopy_r * 1.5, 0.4), maxf(trunk_h + canopy_r, 0.5), maxf(canopy_r * 1.5, 0.4))
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
	var count: int = int(_def.get("fruit_count", 4))
	var regrow: float = float(_def.get("fruit_regrow_time", 60.0))
	var layout: String = _def.get("fruit_layout", "hang")
	for i in count:
		var local_pos: Vector3
		if not _growth.is_empty() and layout == "canopy":
			# FRUIT ANCHORS: the bake measured dense points INSIDE the real
			# foliage (meta "fruit_anchors" on the mesh). Hanging apples from
			# those puts fruit IN the leaf mass on the twigs — the old random
			# sphere scatter floated apples in empty air and let them hover
			# beside branches.
			var anchors := PackedVector3Array()
			var mature_mesh: Mesh = _growth.get(Stage.MATURE)
			if mature_mesh != null and mature_mesh.has_meta("fruit_anchors"):
				anchors = mature_mesh.get_meta("fruit_anchors")
			if anchors.size() > 0:
				# Deterministic shuffle so each tree picks a different subset.
				var order := []
				for j in anchors.size():
					order.append(j)
				for j in range(order.size() - 1, 0, -1):
					var k := _rng.randi_range(0, j)
					var tmp: int = order[j]
					order[j] = order[k]
					order[k] = tmp
				for j in count:
					var ap: Vector3 = anchors[order[j % order.size()]] * _ms # anchors are in unscaled mesh space
					local_pos = ap + Vector3(
						_rng.randf_range(-0.06, 0.06),
						-_rng.randf_range(0.02, 0.10), # hang just below the leaf point
						_rng.randf_range(-0.06, 0.06))
			else:
				# Fallback (old bake without anchors): scatter in the crown
				# volume, like a real apple tree.
				var dir := Vector3(
					_rng.randf_range(-1.0, 1.0),
					_rng.randf_range(-0.45, 0.6),
					_rng.randf_range(-1.0, 1.0)).normalized()
				local_pos = Vector3(_crown_off.x, _crown_y, _crown_off.y) + dir * _crown_r * _rng.randf_range(0.35, 0.9)
		else:
			# Coconut-style hanging cluster tucked well UNDER the frond bases,
			# hugging the trunk — real bunches nestle in the crown axils. The old
			# ring (0.30 crown_r, only 0.24 crown_r below the crown center) let
			# nuts poke THROUGH the drooping fronds. 0.20 radius + 0.45 below
			# puts the whole cluster in the clear zone under the frond bases.
			var ring_r: float
			var ring_y: float
			if not _growth.is_empty():
				ring_r = _crown_r * 0.20
				ring_y = _crown_y - _crown_r * 0.45
			else:
				var canopy: Node3D = _container.get_node_or_null("Canopy")
				if canopy == null:
					return
				ring_r = _grow_y(float(_def.get("canopy_radius", 0.9)))
				ring_y = canopy.position.y
			# PER-TREE BUNCH PLACEMENT: the bunch sits on a RANDOM side of the
			# crown (base angle), split across 1-2 arcs — one palm carries its
			# nuts on the north side, its neighbor on the south, some spread
			# wide. The old even TAU ring made every tree look identical.
			var base_ang: float = _rng.randf() * TAU
			var two_sides: bool = _rng.randf() < 0.5 and count >= 4
			var ang: float
			if two_sides:
				# split the slots between the base side and the opposite side
				var side: float = 0.0 if i % 2 == 0 else PI
				@warning_ignore("integer_division")
				var k := i / 2 # slot pair index (i even -> base side, odd -> opposite)
				var half: int = int(ceil(float(count) * 0.5))
				var spread := 0.9 # ~52° arc per bunch
				ang = base_ang + side + (float(k) / maxf(1.0, float(half - 1)) - 0.5) * spread \
					+ _rng.randf_range(-0.18, 0.18)
			else:
				var spread := _rng.randf_range(1.1, 2.2) # single bunch, size varies per tree
				ang = base_ang + (float(i) / maxf(1.0, float(count - 1)) - 0.5) * spread \
					+ _rng.randf_range(-0.15, 0.15)
			var jitter: float = _rng.randf_range(0.65, 0.95) # tight bunch, like a real cluster
			local_pos = Vector3(_crown_off.x + cos(ang) * ring_r * jitter, \
				ring_y - (0.0 if not _growth.is_empty() else ring_r * _rng.randf_range(0.1, 0.25)) \
					+ _rng.randf_range(-0.06, 0.10), \
				_crown_off.y + sin(ang) * ring_r * jitter)
		# PALM CROP VARIATION: every tree gets a random number of ACTIVE slots
		# — weighted so the island mixes bare palms, sparse 1-2 nut trees and
			# heavy full bunches (a uniform randi_range made half the island
			# carry the same 2-3 nuts). Inactive slots stay listed with
			# slot_active = false so later seasons can promote them.
		var active := count
		if String(_def.get("fruit_layout", "hang")) == "hang" and not _growth.is_empty() and _def.get("fruit_variation", false):
			var roll := _rng.randf()
			if roll < 0.20:
				active = 0 # bare this season
			elif roll < 0.55:
				active = _rng.randi_range(1, 2)
			else:
				active = _rng.randi_range(3, count)
		# Staggered start so fruits reach ripeness at different times.
		_fruits.append({
			"pos": local_pos,
			"elapsed": _rng.randf_range(0.0, regrow * 0.5),
			"regrow": regrow * _rng.randf_range(0.9, 1.1),
			"mesh": null,
			"fall_at": -1.0, # set once ripe when fruit_falls is enabled
			"slot_active": i < active,
		})


func _fruit_green() -> Color:
	# Young fruit is green regardless of its ripe color.
	return Color(0.3, 0.45, 0.22)


func _update_fruits(delta: float) -> void:
	for f in _fruits:
		if not bool(f.get("slot_active", true)):
			continue # this palm's crop variation left the slot empty this season
		f["elapsed"] = float(f["elapsed"]) + delta
		var regrow: float = float(f["regrow"])
		var prog: float = clampf(float(f["elapsed"]) / regrow, 0.0, 1.0)
		var m: MeshInstance3D = f.get("mesh")
		if prog < 0.06:
			if m != null and is_instance_valid(m):
				m.queue_free()
				f["mesh"] = null
			continue
		if m == null or not is_instance_valid(m):
			m = _make_fruit_mesh()
			f["mesh"] = m
			f["tint"] = m.material_override if m.material_override is ShaderMaterial else null
			_container.add_child(m)
		m.position = f["pos"]
		var ripe_col: Color = _def.get("fruit_color", Color(0.8, 0.6, 0.2))
		var green_col: Color = _def.get("fruit_green_color", _fruit_green())
		var size_t := prog * prog * (3.0 - 2.0 * prog)  # smoothstep ease
		m.scale = Vector3.ONE * (0.35 + 0.65 * size_t) * float(_def.get("fruit_scale", 1.0))
		# Color drifts from green toward the ripe fruit color as it matures
		# (works for BOTH the real-mesh shader path and the primitive spheres
		# used by coconuts).
		var color_t: float = clampf((prog - 0.15) / 0.85, 0.0, 1.0)
		var tint: ShaderMaterial = f.get("tint")
		if tint != null:
			tint.set_shader_parameter("ripeness", color_t) # real-mesh path
		var mat: StandardMaterial3D = m.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = green_col.lerp(ripe_col, color_t)
			mat.emission = (ripe_col * 0.25) * color_t
		# RIPE HINT: a twinkle right above the fruit once it's pickable.
		# Off on mobile: a handful of additive billboards inside the canopy
		# is several layers of fill-rate overdraw — a real cost on phones.
		# Bunch-fruit (coconuts) never sparkle: the glowing dot read as the
		# "yellow balls" next to the bunch.
		_set_sparkle(f, prog >= 1.0 and not bool(_def.get("fruit_unlit", false)) and not OS.has_feature("mobile"))
		# NATURAL FRUIT-FALL: a ripe apple left unpicked drops to the ground
		# after fruit_fall_delay seconds, where it lies as a collectible —
		# then the slot quietly grows a new apple. Like a real orchard.
		# ISLAND PALM DROP CYCLE (real-coconut feel): hang layout + palm keys →
		# ~one ripe nut lets go per DAY (drop times spread across the day by
			# the staggered ripening, one slot at a time), and the empty slot
			# regrows its nut over fruit_palm_regrow_days (default 2 days).
		var is_palm_drop: bool = String(_def.get("fruit_layout", "hang")) == "hang" \
			and String(_def.get("fruit_fall_item", "")) != "" and float(_def.get("fruit_fall_days", 0.0)) > 0.0
		if _def.get("fruit_falls", false) or is_palm_drop:
			if float(f["fall_at"]) < 0.0 and prog >= 1.0:
				var delay: float = float(_def.get("fruit_fall_delay", 20.0))
				if is_palm_drop:
					delay = PALM_DROP_DELAY + _rng.randf_range(0.0, ISLAND_DAY_SECONDS)
				f["fall_at"] = float(f["elapsed"]) + delay
			elif float(f["fall_at"]) > 0.0 and float(f["elapsed"]) >= float(f["fall_at"]):
				_drop_fruit(f)


const FRUIT_TINT_SHADER := "res://shaders/fruit_tint.gdshader"
static var _fruit_tint_shader: Shader = null

## Ripeness sparkle: a tiny additive billboard that pops in above a fruit
## the moment it becomes pickable. Shared quad mesh + one canvas-texture
## gradient; only the energy animates. Created lazily, freed on pick/drop.
const SPARKLE_QUAD := 0.22 # meters

static func _sparkle_mesh() -> QuadMesh:
	if _sparkle_mesh_cache == null:
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * SPARKLE_QUAD
		_sparkle_mesh_cache = qm
	return _sparkle_mesh_cache

static var _sparkle_mesh_cache: QuadMesh = null
static var _sparkle_mat_cache: StandardMaterial3D = null

static func _sparkle_material() -> StandardMaterial3D:
	if _sparkle_mat_cache == null:
		# RADIAL soft-dot texture (GradientTexture2D FILL_RADIAL): the old 1D
		# vertical gradient left hard top/bottom edges, and on the Mobile
		# renderer the per-instance `transparency` fade is ignored — ripe trees
		# showed rows of OPAQUE WHITE SQUARES floating in the crown (user
		# screenshot). A radial falloff makes the quad edge fully transparent on
		# every renderer, and the twinkle animates via SCALE only.
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.97, 0.78, 1.0))
		g.set_color(1, Color(1.0, 0.85, 0.3, 0.0))
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = false
		mat.albedo_texture = gt
		mat.disable_receive_shadows = true
		mat.no_depth_test = false
		_sparkle_mat_cache = mat
	return _sparkle_mat_cache

func _set_sparkle(f: Dictionary, on: bool) -> void:
	var s = f.get("sparkle")
	if on:
		if s == null or not is_instance_valid(s):
			s = MeshInstance3D.new()
			s.mesh = _sparkle_mesh()
			s.material_override = _sparkle_material()
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var fx: float = SPARKLE_QUAD * 0.5 + 0.06 # above the fruit
			s.position = Vector3(f["pos"]) + Vector3(0, fx, 0)
			_container.add_child(s)
			f["sparkle"] = s
			f["sparkle_seed"] = _rng.randf_range(0.0, TAU)
		# twinkle — SCALE pulse only: GeometryInstance3D.transparency is ignored
	# by the Mobile renderer (rendered as an opaque box). The radial texture
	# already fades the edges to zero alpha, so pulsing size is enough.
		s.visible = true
		var t := _anim_t * 2.6 + float(f.get("sparkle_seed", 0.0))
		s.scale = Vector3.ONE * (0.45 + 0.55 * (0.5 + 0.5 * sin(t)))
	else:
		if s != null and is_instance_valid(s):
			s.queue_free()
		f["sparkle"] = null

## MOBILE BAKE VARIANTS — heavy bakes ship a `_mobile` twin (half-density
## leaves / fewer tris / smaller textures, same filenames + metas). On
## phones the variant loads instead of the desktop bake; any device falls
## back to the full file when the twin is missing (e.g. a stale export).
## Desktop is byte-identical to before.
static func _mobile_bake(path: String) -> String:
	if path == "" or not OS.has_feature("mobile"):
		return path
	var dot := path.rfind(".")
	var base := path if dot < 0 else path.substr(0, dot)
	var ext := "" if dot < 0 else path.substr(dot)
	var twin := base + "_mobile" + ext
	return twin if ResourceLoader.exists(twin) else path

## Low-end texture memory: on phones, drop NORMAL/ROUGHNESS detail maps from
## loaded bake materials (~2/3 of the palm's texture VRAM; invisible at
## phone view distances and 0.85 res scale). Same rule as
## island_generator._strip_detail_maps — kept separate to avoid a script
## cycle (island_generator references PlantInstance).
static var _stripped_meshes: Array = []

static func _strip_detail_maps(mesh: Mesh) -> void:
	if mesh == null or not OS.has_feature("mobile"):
		return
	if _stripped_meshes.has(mesh):
		return
	_stripped_meshes.append(mesh)
	for s in mesh.get_surface_count():
		var bm := mesh.surface_get_material(s) as BaseMaterial3D
		if bm != null:
			bm.normal_texture = null
			bm.roughness_texture = null

func _make_fruit_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	# Real baked fruit model (apple scan, king-coconut bunch): wrap its
	# texture in the ripening-tint shader so unripe fruit is visibly GREEN
	# and ripens to the real color.
	var mesh_path: String = _mobile_bake(_def.get("fruit_mesh", ""))
	if mesh_path != "" and ResourceLoader.exists(mesh_path):
		var fm: Mesh = load(mesh_path)
		mi.mesh = fm
		if _fruit_tint_shader == null and ResourceLoader.exists(FRUIT_TINT_SHADER):
			_fruit_tint_shader = load(FRUIT_TINT_SHADER)
		if _fruit_tint_shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = _fruit_tint_shader
			sm.set_shader_parameter("ripeness", 0.0)
			var bm := fm.surface_get_material(0) as BaseMaterial3D
			if bm != null:
				if bm.albedo_texture != null:
					sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
				if bm.normal_texture != null:
					sm.set_shader_parameter("normal_tex", bm.normal_texture)
				if bm.roughness_texture != null:
					sm.set_shader_parameter("roughness_tex", bm.roughness_texture)
				# UNLIT-ish FRUIT (coconut husks): a scanned bunch lit by the
				# full PBR stack renders as dark balls with faint emission
				# patches — the "black coconuts" report. Brighten via COLOR
				# (hue-preserving), not emission, and kill the normal-map
				# cavity darkening.
				if bool(_def.get("fruit_unlit", false)):
					sm.set_shader_parameter("unlit", 1.0)
			mi.material_override = sm
		return mi
	var sph := SphereMesh.new()
	var fruit_r: float = float(_def.get("fruit_radius", 0.1))
	sph.radius = fruit_r
	sph.height = fruit_r * 2.0
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _fruit_green()
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mi.material_override = mat
	return mi


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
	if p.get("aim_valid") != true:
		return false
	if p.get("aim_collider") != self:
		return false
	var dist = p.get("aim_distance")
	if dist == null:
		return false
	# REACH SCALES WITH THE PLANT: the flat 3.5 m meant a palm's crown
	# (4.65-5.3 m up) was NEVER in reach — you could not pick nuts (or chop)
	# from a standing tall palm at all. Bushes and small plants keep 3.5 m;
	# trees extend to just above their crown (real coconut harvesting
	# reach). _tree_top is measured in the PlantInstance's LOCAL frame, but
	# island palms sit inside a scaled parent container (up to 1.75x now) —
	# divide the aim distance by the accumulated parent scale so a BIG tree
	# is judged at its REAL world height and stays harvestable.
	var ps := 1.0
	var anc := get_parent()
	while anc is Node3D:
		ps *= (anc as Node3D).scale.x
		anc = anc.get_parent()
	# World-unit reach: the tree's real (scaled) crown height + margin;
	# the 3.5 m floor scales with the plant so a big palm is not a 6 m
	# interaction magnet, while unscaled plants keep exactly 3.5 m.
	var reach := maxf(3.5 * ps, _tree_top * ps + 0.6)
	return float(dist) <= reach


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
	# Hang-layout fruit (coconut bunches) tucks UNDER the crown — the aim hit
	# lands on the aim box wall/top beside the cluster, so the match radius
	# must cover the bunch zone (1.2 m). Canopy fruit (apples sit IN the leaf
	# mass you aim at directly) keeps the tight 0.55 m.
	var best := 1.2 if String(_def.get("fruit_layout", "hang")) == "hang" else 0.55
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
			_show_prompt("Growing...")
			return
		_show_prompt("Hold E — Dig up " + str(_def.get("display_name", "Plant")))
		_run_hold("dig", float(_def.get("dig_time", 1.5)), delta)
		return

	if cat == CAT_FRUIT:
		_show_prompt("Growing...")
		return


func _show_prompt(text: String) -> void:
	if _progress_ui == null:
		return
	_progress_ui.visible = true
	_prompt_label.text = text


func _run_hold(kind: String, per_hit_time: float, delta: float) -> void:
	if not Input.is_action_pressed("interact"):
		if _holding:
			_cancel_hold()
		return
	if not _holding or _hold_kind != kind:
		_holding = true
		_hold_kind = kind
		_hold_progress = 0.0
		_hold_target = per_hit_time
	_hold_progress += delta
	if _progress_bar != null:
		_progress_bar.size.x = 180.0 * clampf(_hold_progress / _hold_target, 0.0, 1.0)
	if _hold_progress >= _hold_target:
		_hold_progress = 0.0
		match kind:
			"dig":
				_do_dig()
			"chop":
				_do_chop_hit()
			"stump":
				_do_remove_stump()


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
	fruit["elapsed"] = 0.0
	fruit["fall_at"] = -1.0
	# Picked slots on a drop-cycle palm regrow over DAYS, not the regrow time.
	if _def.get("fruit_fall_days", 0.0) > 0.0 and String(_def.get("fruit_layout", "hang")) == "hang":
		fruit["regrow"] = float(_def.get("fruit_fall_days")) * ISLAND_DAY_SECONDS * _rng.randf_range(0.9, 1.1)
	_set_sparkle(fruit, false)
	var m = fruit.get("mesh")
	if m != null and is_instance_valid(m):
		m.queue_free()
	fruit["mesh"] = null
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
	_spawn_chips(_def.get("fruit_color", Color(0.8, 0.6, 0.2)), 3, 0.25)


## A ripe fruit lets go: spawn a physical pickup at the fruit's world
## position, clear the slot (it regrows). Apples spawn ApplePickup, island
## palms spawn CoconutPickup. Palm slots regrow over fruit_fall_days (the
## ~2-day "new coconut appears" cycle); apples over the normal regrow time.
func _drop_fruit(fruit) -> void:
	fruit["elapsed"] = 0.0
	fruit["fall_at"] = -1.0
	_set_sparkle(fruit, false)
	var m = fruit.get("mesh")
	var world_pos: Vector3 = _container.to_global(Vector3(fruit["pos"]))
	if m != null and is_instance_valid(m):
		m.queue_free()
	fruit["mesh"] = null
	var palm_drop: bool = String(_def.get("fruit_fall_item", "")) != "" and float(_def.get("fruit_fall_days", 0.0)) > 0.0 \
		and String(_def.get("fruit_layout", "hang")) == "hang"
	if palm_drop:
		fruit["regrow"] = float(_def.get("fruit_fall_days")) * ISLAND_DAY_SECONDS * _rng.randf_range(0.9, 1.1)
	else:
		# APPLE DAY-SPREAD: a natural drop rate of ~4-5 apples per in-game day
		# regardless of slot count. drops/day = count * day_seconds / regrow,
		# so regrow = count * 200 s averages ~4.5/day with 8 slots. Picked
		# apples keep the fast fruit_regrow_time; only SELF-DROPPED slots use
		# the slow cycle (the tree "spends" its energy on fruit you left).
		var n_slots: int = maxi(1, int(_def.get("fruit_count", 4)))
		fruit["regrow"] = float(n_slots) * 200.0 * _rng.randf_range(0.8, 1.2)
	_spawn_fruit_pickup(world_pos, Vector3(_rng.randf_range(-0.4, 0.4), -0.5, _rng.randf_range(-0.4, 0.4)))


## Spawn the physical pickup for this plant's fruit at a world position.
## Shared by the natural drop and the fell-scatter. Ground-clamped so the
## fruit never starts inside the terrain (CCD handles the landing impact).
func _spawn_fruit_pickup(world_pos: Vector3, vel: Vector3) -> void:
	var palm_drop: bool = String(_def.get("fruit_fall_item", "")) != "" and float(_def.get("fruit_fall_days", 0.0)) > 0.0 \
		and String(_def.get("fruit_layout", "hang")) == "hang"
	# if/else instead of a ternary: the two pickup scripts are unrelated
	# classes, so a ternary trips INCOMPATIBLE_TERNARY in strict checks.
	var drop: RigidBody3D
	if palm_drop:
		drop = CoconutPickupScript.new()
	else:
		drop = ApplePickupScript.new()
	get_tree().current_scene.add_child(drop)
	# Never spawn under the surface (slope edge cases) — the nut must land
	# ON the land, not inside it (CCD inside the pickup handles the impact).
	var gy := _ground_below(world_pos)
	if world_pos.y < gy + 0.15:
		world_pos.y = gy + 0.15
	drop.global_position = world_pos
	drop.linear_velocity = vel


## FELL SCATTER: every grown fruit becomes a physical pickup that tumbles
## outward around the trunk — cutting a palm rains its coconuts onto the
## sand (user request). Slots with unripe/no mesh contribute nothing.
func _scatter_all_fruits() -> void:
	for f in _fruits:
		if not bool(f.get("slot_active", true)):
			continue
		_set_sparkle(f, false)
		var m = f.get("mesh")
		if m == null or not is_instance_valid(m):
			continue
		var world_pos: Vector3 = _container.to_global(Vector3(f["pos"]))
		var away := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		if away.length() < 0.2:
			away = Vector3.FORWARD
		away = away.normalized()
		_spawn_fruit_pickup(world_pos + away * 0.3,
			away * _rng.randf_range(1.2, 2.6) + Vector3(0, 1.5, 0))
	_fruits.clear()

## Ground height below a world point: physics ray first (terrain trimesh +
## raft decks), then the island's analytic field as fallback. Keeps fallen
## fruit ON the sand — the old fixed world_pos landed nuts slightly under
## slopes, where the collider popped them through the surface.
func _ground_below(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -30.0, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return (hit["position"] as Vector3).y
	var ig := get_tree().get_first_node_in_group("island") as Node3D
	if ig != null:
		return IslandGenerator.terrain_height_local(Vector2(p.x, p.z) \
			- Vector2(ig.global_position.x, ig.global_position.z))
	return 0.0


# ============================================================
# HARVEST — root crop dig (plant shrinks back, planter freed)
# ============================================================
func _do_dig() -> void:
	_cancel_hold()
	var tw := create_tween()
	tw.tween_property(_container, "scale", Vector3.ONE * 0.04, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_dig)


func _finish_dig() -> void:
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
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
	_health -= 1
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
	_stage = Stage.FALLING
	# RELEASE THE AIM VOLUME IMMEDIATELY: the falling tree's full-size aim box
	# used to stay active through the fall + 5 s fade, eating every aim ray —
	# the player could not target/chop the NEXT tree for ~6 s after each cut
	# ("can only cut one tree at a time"). A dying tree aims at nothing.
	if _col_shape != null and _col_shape.shape is BoxShape3D:
		(_col_shape.shape as BoxShape3D).size = Vector3(0.2, 0.2, 0.2)
		_col_shape.position = Vector3(0, 0.1, 0)
	if _trunk_shape != null and is_instance_valid(_trunk_shape):
		_trunk_shape.queue_free()
	_trunk_shape = null
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


func _finish_fell() -> void:
	# FELL IMPACT: all grown fruit scatters onto the ground as physical
	# pickups BEFORE the wood reward — cutting a palm rains coconuts.
	_scatter_all_fruits()
	# Wood resources (configurable per plant in PlantDB.fell_drops).
	var drops: Array = _def.get("fell_drops", [])
	for d in drops:
		if not (d is Array) or d.size() < 3:
			continue
		var item_name: String = str(d[0])
		var amt: int = randi_range(int(d[1]), int(d[2]))
		if amt > 0:
			Inventory.add(item_name, amt)
	_spawn_chips(_def.get("trunk_color", Color(0.5, 0.36, 0.2)).darkened(0.1), 6, 0.5)
	# SLOW FADE-OUT (user request: never vanish instantly): the felled tree
	# wilts — scales down + sinks slightly over 5 s — then the stump appears.
	# Cross-renderer safe: no material transparency mutation (baked materials
	# are shared across every palm, so animating their alpha is not possible).
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE * 0.06, 5.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_visual, "position:y", -0.35, 5.0)
	tw.tween_callback(_finish_fade)


## End of the fell fade: swap to the stump and start the auto-regrow clock.
func _finish_fade() -> void:
	_stage = Stage.STUMP
	for c in _container.get_children():
		c.queue_free()
	_fruits.clear()
	_build_stump_visual()
	_container.scale = Vector3.ONE
	_visual.rotation = Vector3.ZERO
	# ISLAND AUTO-REGROW: stumps that are NOT in a planter (island palms/
	# trees) grow back by themselves after ~1 in-game day; the player sees
	# the whole sprout -> young -> mature growth again. Potted stumps keep
	# the manual remove behavior (the planter slot stays occupied).
	var planter := get_parent().get_parent() as Planter
	if planter == null:
		_regrow_wait = ISLAND_DAY_SECONDS * _rng.randf_range(0.9, 1.15)


## Auto-regrow after the felled stump's day-long wait: restart from SPROUT.
func _regrow_plant() -> void:
	_regrow_wait = 0.0
	_stage = Stage.SPROUT
	_stage_timer = 0.0
	_health = int(_def.get("chop_hits_required", 4))
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_visual.position = Vector3.ZERO
	_rebuild_visual()
	_grow = STAGE_FRAC[Stage.SPROUT]
	_container.scale = Vector3.ONE * _grow
	_play_grow_pop()


func _do_remove_stump() -> void:
	_cancel_hold()
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()

func survival_snapshot() -> Dictionary:
	var fruit_times: Array = []
	for fruit in _fruits:
		fruit_times.append(float(fruit.get("elapsed", 0.0)))
	return {"stage": _stage, "timer": _stage_timer, "health": _health, "grow": _grow, "fruits": fruit_times}

func restore_survival_snapshot(data: Dictionary) -> void:
	_stage = clampi(int(data.get("stage", 0)), Stage.SEED, Stage.STUMP)
	if _stage == Stage.FALLING:
		_stage = Stage.STUMP
	_stage_timer = maxf(0.0, float(data.get("timer", 0.0)))
	_health = maxi(1, int(data.get("health", 4)))
	_grow = clampf(float(data.get("grow", STAGE_FRAC[0])), 0.04, 1.0)
	_rebuild_visual()
	_container.scale = Vector3.ONE * _grow
	var times: Array = data.get("fruits", [])
	for i in range(mini(times.size(), _fruits.size())):
		_fruits[i]["elapsed"] = maxf(0.0, float(times[i]))
