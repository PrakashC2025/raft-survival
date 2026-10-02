class_name IslandGenerator
extends Node3D
## ============================================================
## PROCEDURAL TROPICAL ISLAND — replaces the old beach-scan glb.
## Builds, at runtime (one-time ~1-2 s):
##   1. TERRAIN  — a square seabed sheet around the island: underwater
##      seabed -> lagoon shallows -> beach berm -> grass flats -> a rugged
##      central rock hill with side hills, erosion channels, a freshwater
##      pond, rocky headlands / low cliffs and an irregular eroded
##      coastline (closed-form wobble noise, never circular).
##   2. COLLIDER — one trimesh StaticBody3D over the terrain sheet.
##   3. PROPS    — REAL coconut palms (models/coconut_palm.glb, baked into
##      grass/baked/palm_island.tres by tools/bake_island_vegetation.gd,
##      capsule collider + wind sway on the fronds), rocks in many sizes
##      (headland, boulders, beach stones, shoreline, half-submerged),
##      bushes/ferns, driftwood + a fallen log.
##   4. INTERACTION — the ocean shader (main.gdshader) mirrors the BASE
##      depth profile of terrain_height_local() so the water knows the
##      real seabed: turquoise shallows, sand-glow surf zone, broken foam
##      lines hugging the coast, rolling breakers, shore rocks with foam.
##
## KEEP-IN-SYNC with main.gdshader (island_base()):
##   R_SHORE / R_OUTER / DEEP / BEACH_H, coast_wobble(), lagoon_mask(),
##   and the base radial profile + lagoon shelf formulas.
## Those use ONLY closed-form sin/cos/smoothstep math — GPU (float) and
## CPU (double) evaluate them identically. Hash noise would NOT match
## (fract(sin)*43758 diverges between float precisions), so all noise
## detail lives on the GDScript side only.
## ============================================================

## Device tiering + the runtime FPS governor (statics; safe via preload —
## island_grass.gd preloads this file, so no reference cycle).
const MobilePerf := preload("res://scripts/mobile_perf.gd")

# ---- shared with main.gdshader (keep in sync!) ----
const R_SHORE := 32.0 ## coastline radius: terrain height crosses y=0 here
const R_OUTER := 68.0 ## seabed reaches DEEP here
const DEEP := 12.0
const BEACH_H := 2.6 ## beach berm height at the center (dome apex)

# ---- layout (island-local XZ) ----
const HILL1 := Vector2(-2.5, -1.0)  ## central rocky hill
const HILL2 := Vector2(-14.0, -8.5) ## west hill
const HILL3 := Vector2(11.5, 13.0)  ## east hill
const POND_POS := Vector2(5.0, 6.0) ## high saddle between HILL1 and HILL3
const POND_R := 5.0

@export var grid_step := 1.75 ## terrain sheet vertex spacing (m)
@export var grid_half := 140.0 ## half-size of the generated seabed sheet
@export var seed_value := 20260910

@export var palm_count := 52 ## desktop; ~70% of this on mobile builds — a real island grove, not a thin sprinkle
@export var bush_count := 26
@export var rock_counts := [6, 10, 4, 12] ## headland / boulders / beach stones / shoreline+shallow

var _rng := RandomNumberGenerator.new()
var _palms_placed := 0 ## actual palms scattered (reported after generate)
## Palm chunked-placement state (see generate() — palms go up 5 per frame
## so 41 baked-tree instantiations never land in one frame).
var _palm_ok := false
var _palm_tries := 0
var _palm_spots: Array[Vector2] = []
## The terrain sheet's vertex heights (grid n x n) — kept so prop placement
## can query the RENDERED surface, not the analytic field (see _ground).
var _terrain_heights := PackedFloat32Array()
var _terrain_n := 0
var _rain: Node = null # cached RainSystem (pond rain-dimple uniform)

# ---- real vegetation (baked once by tools/bake_island_vegetation.gd) ----
const PALM_MESH_PATH := "res://grass/baked/palm_island.res"
const PALM_FROND_SHADER := "res://shaders/palm_fronds_sway.gdshader"
const ROCK_SHADER := "res://shaders/rock_triplanar.gdshader"
const FRESH_WATER_SHADER := "res://shaders/fresh_water.gdshader"
# Scanned undergrowth (photogrammetry library baked to light clumps):
const SCAN_BUSH_MESHES: Array[String] = [
	"res://grass/baked/scan_groundcover.res", # leafy ground cover
	"res://grass/baked/scan_flower.res",      # purple flower bush
	"res://grass/baked/scan_dandelion.res",   # dandelion weed
]

static var _palm_mesh: ArrayMesh = null
static var _palm_frond_shader: Shader = null
static var _frond_override_mat: ShaderMaterial = null

## MOBILE BAKE VARIANTS + DETAIL-MAP STRIP (low-end texture memory).
## Heavy bakes ship a `_mobile` twin (see tools/bake_island_vegetation.gd);
## on phones the twin loads instead. On top of that, phones drop NORMAL and
## ROUGHNESS maps from every baked vegetation material — the probe
## (tools/probe_vram.gd) measured them at ~8 MB of VRAM for the palm alone,
## and at 0.85 res scale on a 5-6" screen the detail they add is invisible.
## Runs once per mesh; shared by the palm and the scanned bush meshes.
static func _mobile_bake(path: String) -> String:
	if path == "" or not OS.has_feature("mobile"):
		return path
	var dot := path.rfind(".")
	var base := path if dot < 0 else path.substr(0, dot)
	var ext := "" if dot < 0 else path.substr(dot)
	var twin := base + "_mobile" + ext
	return twin if ResourceLoader.exists(twin) else path

static var _stripped_meshes: Array = [] # meshes already detail-stripped

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

## Load the baked coconut palm once; returns false if the bake is missing
## (run tools/bake_island_vegetation.gd) so the island silently keeps rocks.
static func _palm_assets() -> bool:
	if _palm_mesh != null:
		return true
	var palm_path := _mobile_bake(PALM_MESH_PATH)
	if ResourceLoader.exists(palm_path):
		_palm_mesh = load(palm_path) as ArrayMesh
	if _palm_mesh != null:
		_strip_detail_maps(_palm_mesh)
	if ResourceLoader.exists(PALM_FROND_SHADER):
		_palm_frond_shader = load(PALM_FROND_SHADER) as Shader
	return _palm_mesh != null

## Shared frond override: the baked frond surface keeps its real albedo
## texture, but renders through palm_fronds_sway.gdshader so the crown
## sways in the wind (trunk/nut surfaces keep their imported materials).
static func _palm_frond_material() -> ShaderMaterial:
	if _frond_override_mat != null or _palm_frond_shader == null:
		return _frond_override_mat
	var fs: int = int(_palm_mesh.get_meta("frond_surface", -1))
	if fs < 0 or fs >= _palm_mesh.get_surface_count():
		return null
	var src := _palm_mesh.surface_get_material(fs) as StandardMaterial3D
	if src == null or src.albedo_texture == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = _palm_frond_shader
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold)
	m.set_shader_parameter("wind_dir", Vector3(0.707, 0.0, 0.707)) # matches Sky3D 2.356 rad
	m.set_shader_parameter("wind_speed", 1.0)
	m.set_shader_parameter("sway_strength", 1.0)
	_frond_override_mat = m
	return _frond_override_mat

func _ready() -> void:
	if has_node("Terrain"):
		return # already generated (defensive)
	generate()

## STAGED GENERATION: the old single-frame generate() built EVERYTHING in one
## _ready — with the 40 PlantInstance palms + apple tree loading their baked
## meshes synchronously, that frame took 70+ s on first load and read as the
## game "stuck" after the loading bar. Splitting into per-frame phases lets
## the engine breathe between steps: terrain appears, then pond, then props
## stream in over a few frames. Tree meshes themselves are PREWARMED by the
## menu (load_threaded_request) so by the time props build, loads are cache-hot.
func generate() -> void:
	_rng.seed = seed_value
	add_to_group("island")
	var t0 := Time.get_ticks_msec()
	await _phase(_build_terrain)
	print("[IslandGenerator] phase terrain %d ms" % (Time.get_ticks_msec() - t0))
	await _phase(_build_pond_water)
	print("[IslandGenerator] phase pond %d ms" % (Time.get_ticks_msec() - t0))
	# PALMS IN CHUNKS: the old _scatter_props placed all 40 PlantInstance
	# palms + apple tree + 26 bushes in ONE frame — with their baked meshes
	# materializing, that frame froze 10+ s (probe: 11.8 s gap) — the
	# "struck when I click Continue" hang. Terrain/pond/rocks are cheap;
	# the trees are the wall. Chunks of 5 keep every frame under ~0.5 s.
	await _phase(_scatter_props)
	print("[IslandGenerator] phase props %d ms" % (Time.get_ticks_msec() - t0))
	# STALL GUARD: _place_palm_chunk spins only while a slot-free spot is
	# found within its try budget; if the bake is missing or every try is
	# rejected, waiting for _palms_placed to reach the target would loop
	# forever — the apple tree, beacon/grass placement and the ocean uniform
	# push (ALL after this line) would never run. Cap the rounds hard.
	var palm_guard := 0
	while _palms_placed < _palms_target() and palm_guard < _palms_target() * 8:
		palm_guard += 1
		_place_palm_chunk()
		await _phase(_noop)
	if _palms_placed < _palms_target():
		print("[IslandGenerator] palm placement short: %d/%d (continuing)" % [_palms_placed, _palms_target()])
	print("[IslandGenerator] phase palms %d ms" % (Time.get_ticks_msec() - t0))
	# ---- THE rare apple tree: exactly ONE on the island ----
	# Mature + fruiting from the start: pick its apples with E, or let ripe
	# ones drop and collect them off the ground. Chopping it fells the tree
	# and drops Wood + Apple Seeds so the raft orchard can begin.
	# Guaranteed: candidate spots are SCORED (flat + clear + low), the best
		# one always wins even if nothing is perfect. The island can never
		# spawn without its one rare apple tree.
	if ResourceLoader.exists("res://grass/baked/apple_tree.res"):
		var best_q := Vector2.ZERO
		var best_score := -INF
		for i in 160:
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * (R_SHORE - 8.0) + 4.0
			var q := Vector2(cos(a) * r, sin(a) * r)
			var h := _ground(q)
			var slope := _slope_y(q)
			if h < 1.2 or h > 8.5 or q.distance_to(POND_POS) < POND_R + 2.0:
				continue
			# score: flatter is better, stay clear of palms (soft penalty
			# instead of a hard reject so a spot ALWAYS survives)
			var score := slope * 2.0
			for p in _palm_spots:
				var d := p.distance_to(q)
				if d < 5.5:
					score -= (5.5 - d) * 0.6
			if score > best_score:
				best_score = score
				best_q = q
		var ah := _ground(best_q)
		# PlantInstance builds its own mesh + collision + fruits, so we only
		# need a bare positioned node — NOT _place_mesh (which adds a
		# duplicate MeshInstance3D + StaticBody3D on top).
		var atree := Node3D.new()
		atree.name = "AppleTree"
		atree.position = Vector3(best_q.x, ah - 0.06, best_q.y)
		atree.rotation.y = _rng.randf() * TAU
		# Size variation comes from PlantInstance itself (per-plant _hvar +
		# MESH_SCALE) — an extra node scale here would double-scale the tree.
		var apl := PlantInstance.new()
		apl.plant_id = "Apple"
		apl.start_stage = PlantInstance.Stage.MATURE
		atree.add_child(apl)
		apl.position = Vector3.ZERO
		add_child(atree)
		print("[IslandGenerator] rare apple tree placed at %v" % best_q)

	await _phase(_place_beacon_and_grass)
	_push_ocean_uniforms()
	print("[IslandGenerator] island built: terrain + %d palms + %d bushes + rocks" % [_palms_placed, bush_count])

func _noop() -> void:
	pass

## Per-plant height variation target for this device (mobile: fewer palms
## by tier — low phones drop almost half the grove; high phones keep most).
func _palms_target() -> int:
	return maxi(int(palm_count * MobilePerf.palms_scale()), 8)

## Phones get a DEDICATED compile-light terrain shader. The desktop beach
## shader stays ~20 fbm calls per pixel even after the 27th-pass cuts —
## within budget for PCs, but several phone GPUs (Mali/Adreno) blow their
## per-pixel ALU/compile budget building that pipeline and the terrain
## mesh NEVER DRAWS: the island shows as grass-only (the grass field, ocean
## and sky use far cheaper shaders). terrain_sand_mobile.gdshader keeps
## the identical masks/color stops with ~1/10 the noise work, so the look
## is preserved and the pipeline always compiles. Falls back silently to
## the desktop shader if the file is missing (e.g. stale export).
static func _terrain_shader_path() -> String:
	if MobilePerf.mobile_like() and ResourceLoader.exists("res://shaders/terrain_sand_mobile.gdshader"):
		return "res://shaders/terrain_sand_mobile.gdshader"
	return "res://shaders/terrain_sand.gdshader"

## Run one build phase, then yield one process frame (and a physics frame so
## raycast-dependent steps see fresh colliders) before the next phase.
## The callable is AWAITED: phases may suspend internally (e.g. the chunked
## first-launch terrain pass). Awaiting a plain (non-coroutine) result
## continues immediately, so sync phases are unaffected.
func _phase(fn: Callable) -> void:
	await fn.call()
	await get_tree().process_frame
	await get_tree().physics_frame

## Push the depth-profile constants into the ocean shader so water shading
## (turquoise shallows, surf foam) sits exactly on the real coastline.
func _push_ocean_uniforms() -> void:
	var oc := get_tree().get_first_node_in_group("ocean") as MeshInstance3D
	if oc == null:
		return
	var plane := oc.mesh as PlaneMesh
	if plane == null:
		return
	var m := plane.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("island_center", Vector2(global_position.x, global_position.z))
	m.set_shader_parameter("shore_radius", R_SHORE)
	m.set_shader_parameter("outer_radius", R_OUTER)
	m.set_shader_parameter("deep_depth", DEEP)
	m.set_shader_parameter("beach_height", BEACH_H)
	m.set_shader_parameter("island_active", 1.0)
	# Mobile terrain cut: phones keep the vertex-paint colors + grass mottle
	# but skip the heaviest per-pixel detail blocks (mountain minerals, seabed
	# + close-range grain bumps). The full shader overwhelmed phone GPUs and
	# left the ISLAND INVISIBLE on mobile while PCs were fine.
	var terrain := get_node_or_null("Terrain") as MeshInstance3D
	if terrain != null and terrain.mesh != null:
		var tm := terrain.mesh.surface_get_material(0) as ShaderMaterial
		if tm != null:
			tm.set_shader_parameter("high_detail", 0.0 if MobilePerf.mobile_like() else 1.0)
	# Half-submerged shore rocks get a foam collar in the shader.
	var rocks := PackedVector2Array()
	for child in get_children():
		if child.name.begins_with("Rock_Shore_"):
			var wp: Vector3 = (child as Node3D).global_position
			rocks.append(Vector2(wp.x, wp.z))
			if rocks.size() >= 16:
				break
	m.set_shader_parameter("foam_rocks", rocks)
	m.set_shader_parameter("foam_rock_count", rocks.size())

## The pond's freshwater surface: a translucent disc sunk into the carved
## bowl, reading as clear spring water (the OPPOSITE of the salty ocean —
## green-tinted, calm, floor visible through it).
func _build_pond_water() -> void:
	if not ResourceLoader.exists(FRESH_WATER_SHADER):
		return
	var disc := CylinderMesh.new()
	disc.top_radius = pond_disc_radius()
	disc.bottom_radius = pond_disc_radius()
	disc.height = 0.02
	disc.radial_segments = 48
	disc.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = load(FRESH_WATER_SHADER)
	mat.set_shader_parameter("pond_r", pond_disc_radius())
	mat.render_priority = 1 # draw after the opaque pond floor
	disc.material = mat
	var water := MeshInstance3D.new()
	water.name = "PondWater"
	water.add_to_group("fresh_water")
	water.set_meta("water_radius", pond_disc_radius())
	water.mesh = disc
	water.position = Vector3(POND_POS.x, pond_water_height(), POND_POS.y)
	add_child(water)

## Keep the pond's day/night factors in step with the ocean's (both driven
## by the same Sky3D time-of-day) — cheap 4-uniform copy per frame. Also
## feeds rain_strength so rain visibly dimples + darkens the pond surface.
func _process(_delta: float) -> void:
	var oc := get_tree().get_first_node_in_group("ocean") as MeshInstance3D
	if oc == null:
		return
	var plane := oc.mesh as PlaneMesh
	if plane == null:
		return
	var om := plane.material as ShaderMaterial
	if om == null:
		return
	var pw := get_node_or_null("PondWater") as MeshInstance3D
	if pw == null:
		return
	var pm := (pw.mesh as CylinderMesh).material as ShaderMaterial
	if pm == null:
		return
	pm.set_shader_parameter("night_factor", om.get_shader_parameter("night_factor"))
	pm.set_shader_parameter("twilight_factor", om.get_shader_parameter("twilight_factor"))
	pm.set_shader_parameter("sun_dir", om.get_shader_parameter("sun_dir"))
	pm.set_shader_parameter("moon_dir", om.get_shader_parameter("moon_dir"))
	if _rain == null:
		_rain = get_tree().get_first_node_in_group("rain_system")
	if _rain != null:
		pm.set_shader_parameter("rain_strength", float(_rain.get("_intensity")))

# ============================================================
# TERRAIN HEIGHT FIELD — the heart of the island.
# base = radial profile (MIRRORED in main.gdshader), everything after
# the land-mask is GDScript-only detail (grass, rocks, pond, channels).
# ============================================================
## Closed-form coastline wobble — IDENTICAL formula in main.gdshader.
static func coast_wobble(q: Vector2) -> float:
	return sin(q.x * 0.052 + 1.3) * cos(q.y * 0.047 + 0.7) \
		+ 0.6 * sin((q.x + q.y) * 0.031 + 2.1)

## East-lagoon mask in [0,1]: cos(ang - 0.9) rewritten without atan so
## CPU and GPU agree bit-for-bit. IDENTICAL formula in main.gdshader.
static func lagoon_mask(q: Vector2, r: float) -> float:
	if r < 0.001:
		return 0.0
	return clampf((q.x * 0.6216 + q.y * 0.7833) / r, 0.0, 1.0)

static func terrain_height_local(q: Vector2, with_pond := true) -> float:
	var r := q.length()
	# Irregular eroded coastline: the shoreline radius itself wobbles.
	var r_eff := r + coast_wobble(q) * 5.0

	var base: float
	if r_eff <= R_SHORE:
		# Raised-cosine dome: BEACH_H at the center -> 0 at the shore.
		base = BEACH_H * 0.5 * (1.0 + cos(PI * r_eff / R_SHORE))
	else:
		var d := clampf((r_eff - R_SHORE) / (R_OUTER - R_SHORE), 0.0, 1.0)
		base = -DEEP * (d * d * (3.0 - 2.0 * d)) # smooth seabed drop-off
	# East lagoon shelf: a wide shallow sand plateau (reference cove).
	# Only applied OFFSHORE (base < 0) so it never floods the beach, and
	# lerped (not maxf'd) so the seabed is untouched where the mask is 0.
	if base < 0.0:
		var floor_depth := -(0.4 + 2.6 * smoothstep(26.0, 48.0, r))
		base = lerpf(base, floor_depth, lagoon_mask(q, r))

	var h := base
	var land := smoothstep(-2.5, 0.0, base) # 1 inland, 0 offshore
	if land > 0.001:
		# Central rocky hill + two side hills.
		var hills := 7.5 * exp(-q.distance_squared_to(HILL1) / 324.0) \
			+ 3.6 * exp(-q.distance_squared_to(HILL2) / 121.0) \
			+ 3.2 * exp(-q.distance_squared_to(HILL3) / 81.0)
		var ridge_n := _fbm(q * 0.06 + Vector2(11.3, 5.2))
		var detail := (_fbm(q * 0.15) - 0.5) * 3.4 + (_fbm(q * 0.5) - 0.5) * 0.9
		h += (hills + ridge_n * 3.0 + detail) * land
		# Erosion channels: three s-curved ravines running off the hill.
		for i in 3:
			var a2 := 0.7 + float(i) * 2.1
			var dirv := Vector2(cos(a2), sin(a2))
			var s := q.dot(dirv)
			var perp2 := (q - dirv * s).length_squared()
			h -= 2.0 * exp(-perp2 / 14.0) * exp(-pow(s - 10.0 - 4.0 * float(i), 2.0) / 150.0) * land
		# LAND FLOOR: inland ground can never dip below the water table —
		# noise tails (detail/rock/channel) would otherwise carve underwater
		# trenches through the island interior. Fades out with `land` so the
		# real coastline and seabed are untouched.
		h = lerpf(h, maxf(h, 0.6), land)
	# Rocky headlands / low cliffs near the coast (ridged noise ridges).
	# ADDITIVE ONLY: a negative tail here carved underwater notches into the
	# beach band; ridges rise instead, which is what a headland is anyway.
	var rock_n := _ridged(q * 0.085 + Vector2(31.7, 17.9))
	var coast_band := exp(-pow(base - 1.2, 2.0) / 6.5)
	h += maxf(rock_n - 0.5, 0.0) * 12.0 * coast_band * clampf(1.0 - r / (R_OUTER * 0.8), 0.0, 1.0)
	if with_pond:
		# Freshwater pond: first flatten the area to the rim level, then
		# carve a steep-sided bowl — guarantees the water disc is contained.
		var pd := q.distance_to(POND_POS)
		var rim_k := 1.0 - smoothstep(POND_R * 0.85, POND_R * 1.7, pd)
		if rim_k > 0.0:
			var pond_base := terrain_height_local(POND_POS, false)
			h = lerpf(h, pond_base, rim_k)
		h -= 2.0 * (1.0 - smoothstep(POND_R * 0.6, POND_R, pd))
	return h

## Pond surface height (world Y) — the flattened rim level minus 0.8.
static func pond_water_height() -> float:
	return terrain_height_local(POND_POS, false) - 0.8

## Freshwater pond disc radius (smaller than the bowl mouth so the rim
## always rises above the water surface — no leaks at the shoreline).
static func pond_disc_radius() -> float:
	return POND_R - 1.8

## World-space helper (callers add the island node's world offset).
static func terrain_height_at_world(world_xz: Vector2, island_origin: Vector2) -> float:
	return terrain_height_local(world_xz - island_origin)

## Returns true if the terrain at world_xz is sand (not grass/rock).
## Used by footprints to only stamp on sandy areas.
static func is_sand_at(world_xz: Vector2, island_origin: Vector2) -> bool:
	var q := world_xz - island_origin
	var h := terrain_height_local(q)
	# Must be above water (land)
	if h < 0.3:
		return false
	# Recompute the same slope check used during terrain build
	var e := 0.6
	var hl := terrain_height_local(q - Vector2(e, 0.0))
	var hr := terrain_height_local(q + Vector2(e, 0.0))
	var hd := terrain_height_local(q - Vector2(0.0, e))
	var hu := terrain_height_local(q + Vector2(0.0, e))
	var slope_y := Vector3(hl - hr, 2.0 * e, hd - hu).normalized().y
	# Must be flat enough for walking
	if slope_y < 0.72:
		return false
	# Sand boundary: same logic as baked paint in _build_terrain
	var jitter := _fbm(q * 0.22 + Vector2(51.2, 17.3))
	var sand_h := 1.3 + (jitter - 0.5) * 1.4
	var grass_k := smoothstep(sand_h, sand_h + 1.4, h) * smoothstep(0.62, 0.86, slope_y)
	var rock_k := maxf(smoothstep(0.80, 0.58, slope_y), smoothstep(0.55, 0.25, slope_y) * 0.6)
	# Sand if grass and rock influence are both low
	return grass_k < 0.3 and rock_k < 0.3

# ---- noise (GDScript-only detail; mobile friendly) ----
static func _hash2(p: Vector2) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453, 1.0)

static func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash2(i)
	var b := _hash2(i + Vector2(1.0, 0.0))
	var c := _hash2(i + Vector2(0.0, 1.0))
	var d := _hash2(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

## Public shim: island_grass.gd reuses the same noise for its grass-line
## placement mask so the field matches the terrain paint 1:1.
static func fbm_public(p: Vector2) -> float:
	return _fbm(p)

static func _fbm(p: Vector2) -> float:
	return _vnoise(p) * 0.55 + _vnoise(p * 2.13 + Vector2(7.7, 3.9)) * 0.28 \
		+ _vnoise(p * 4.7 + Vector2(3.1, 8.2)) * 0.17

static func _ridged(p: Vector2) -> float:
	return 1.0 - absf(_vnoise(p) * 2.0 - 1.0)

# ============================================================
# TERRAIN MESH — square sheet with baked vertex paint
# (sand / grass / rock / wet bands) so one StandardMaterial suffices.
# ============================================================
## Vertex count along one edge of the terrain sheet (shared with tools that
## mirror the cache layout, e.g. check_terrain_parity.gd).
func _grid_n() -> int:
	return int(grid_half * 2.0 / grid_step) + 1

func _build_terrain() -> void:
	# HEIGHTS + PAINT CACHE: the height field AND the vertex paint are both
	# DETERMINISTIC (fixed seed), but the GDScript noise math over 26k
	# vertices took ~10 s EVERY boot — the measured 9-12 s frozen frame right
	# after Continue (the loading bar is scene-parse only; the island builds
	# in the first frames after). Cache both to user:// and every launch
	# after the first skips straight to mesh assembly.
	# v5 paint: summit stays grass green (bare rock only on steep faces);
	# golden-sand band + dithered turf edge from v4 unchanged.
	# Bump this suffix whenever _terrain_paint changes so every device
	# (including phones with an old cached paint) re-computes once.
	var cache_path := "user://terrain_cache_v5_%d_%s.cache" % [seed_value, str(grid_step).replace(".", "_")]
	var heights := PackedFloat32Array()
	var colors := PackedColorArray()
	var cached := false
	if FileAccess.file_exists(cache_path):
		var f := FileAccess.open(cache_path, FileAccess.READ)
		if f != null:
			var data: Array = f.get_var()
			f.close()
			if data.size() == 2:
				heights = data[0]
				colors = data[1]
				cached = true
	var n := int(grid_half * 2.0 / grid_step) + 1
	if not cached or heights.size() != n * n or colors.size() != n * n:
		# FIRST LAUNCH: the n² height+paint pass is ~10 s of GDScript. It used
		# to run in ONE frame — the biggest phone hang of the whole boot (the
		# loading bar sat still for 10-30 s, which reads as "the game froze").
		# Now chunked row-batches across frames (pass 31); the per-vertex math
		# is UNCHANGED, so the cache this writes is byte-identical to the old
		# single-pass result (verified: pre/post files identical).
		heights.resize(n * n)
		colors.resize(n * n)
		var rows_done := await _terrain_compute_async(heights, colors, n)
		var fw := FileAccess.open(cache_path, FileAccess.WRITE)
		if fw != null:
			fw.store_var([heights, colors])
			fw.close()
		print("[IslandGenerator] terrain heights+paint computed (%d rows, chunked) + cached (first launch only)" % rows_done)
	else:
		print("[IslandGenerator] terrain heights+paint loaded from cache")
	var min_h := 1e9
	for h in heights:
		min_h = minf(min_h, h)
	# Keep for _rendered_height(): props must sit on the surface the player
	# SEES (this grid), not on the analytic field between the samples.
	_terrain_heights = heights
	_terrain_n = n

	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	pos.resize(n * n)
	nor.resize(n * n)
	col.resize(n * n)

	for iz in n:
		for ix in n:
			var vi := iz * n + ix
			var h := heights[vi]
			# Grid-neighbor normal (no extra height evals).
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			var normal := Vector3(hl - hr, 2.0 * grid_step, hd - hu).normalized()
			var q := Vector2(-grid_half + ix * grid_step, -grid_half + iz * grid_step)
			pos[vi] = Vector3(q.x, h, q.y)
			nor[vi] = normal

			# ---- baked paint (from cache — see _terrain_paint) ----
			col[vi] = colors[vi]

	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c2 := a + n
			var d := a + n + 1
			# CLOCKWISE winding when viewed from above (Godot's front face):
			# reversed order keeps the top side front-facing so rendering is
			# not culled and the one-sided trimesh collider is solid on top.
			idx.append_array([b, c2, a, d, c2, b])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat: Material
	var shader_path := _terrain_shader_path()
	if ResourceLoader.exists(shader_path):
		var sm := ShaderMaterial.new()
		sm.shader = load(shader_path)
		# Set high_detail HERE, at creation — not only in _push_ocean_uniforms
		# (which runs last). If any later phase stalls, the material is still
		# correct from frame one.
		sm.set_shader_parameter("high_detail", 0.0 if MobilePerf.mobile_like() else 1.0)
		mat = sm
	else:
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		fallback.roughness = 0.92
		mat = fallback
	mesh.surface_set_material(0, mat)

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	add_child(terrain)

	var body := StaticBody3D.new()
	body.name = "Terrain_Body"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	terrain.add_child(body)
	print("[IslandGenerator] terrain sheet %dx%d verts (min y %.1f)" % [n, n, min_h])

## FIRST-LAUNCH height+paint pass, CHUNKED ACROSS FRAMES. Row-batches per
## frame sized by MobilePerf.terrain_rows_per_frame() (desktop: 161 = the
## old single-pass behavior in one batch).
## PARITY-CRITICAL (verified by tools/check_terrain_parity.gd): each vertex
## is computed+PAINTED in the old global row-major order against the
## PARTIALLY-FILLED heights array — _terrain_paint reads the right and
## below neighbors, which are still 0.0 at that instant in the original
## fused loop, so pre-computing all heights first (or any reorder) would
## silently repaint the island. Suspending between row batches changes
## nothing: the array persists and the vertex sequence is identical, so
## the cache written is byte-identical to the shipped one.
func _terrain_compute_async(heights: PackedFloat32Array, colors: PackedColorArray, n: int) -> int:
	var sand_col := Color(0.72, 0.63, 0.42)
	var wet_sand := Color(0.40, 0.34, 0.23)
	var grass_col := Color(0.24, 0.40, 0.14)
	var rock_col := Color(0.44, 0.40, 0.34)
	var rows := MobilePerf.terrain_rows_per_frame()
	var done_rows := 0
	while done_rows < n:
		var iz_end := mini(done_rows + rows, n)
		for iz in range(done_rows, iz_end):
			for ix in n:
				var vi := iz * n + ix
				var q := Vector2(-grid_half + ix * grid_step, -grid_half + iz * grid_step)
				var h := terrain_height_local(q)
				heights[vi] = h
				colors[vi] = _terrain_paint(q, h, Vector3.UP, n, heights, sand_col, wet_sand, grass_col, rock_col)
		done_rows = iz_end
		if done_rows < n:
			await get_tree().process_frame
	return done_rows

## One vertex's terrain paint color (called only during the first-launch
## cache computation — see _build_terrain). Same math as the original
## inline paint block; kept 1:1 so cached islands look identical.
func _terrain_paint(q: Vector2, h: float, normal_hint: Vector3, n: int, heights: PackedFloat32Array,
		sand_col: Color, wet_sand: Color, grass_col: Color, rock_col: Color) -> Color:
	var e := grid_step
	var iz := clampi(int(roundf((q.y + grid_half) / e)), 0, n - 1)
	var ix := clampi(int(roundf((q.x + grid_half) / e)), 0, n - 1)
	var hl := heights[iz * n + maxi(ix - 1, 0)]
	var hr := heights[iz * n + mini(ix + 1, n - 1)]
	var hd := heights[maxi(iz - 1, 0) * n + ix]
	var hu := heights[mini(iz + 1, n - 1) * n + ix]
	var slope := Vector3(hl - hr, 2.0 * e, hd - hu).normalized().y
	var jitter := _fbm(q * 0.22 + Vector2(51.2, 17.3))
	# GOLDEN-SAND BAND + DITHERED TURF EDGE. The old rule started grass at
	# ~1.3 m with a 1.4 m ramp, so the wide playable beach shelf (h 1.5-4 m)
	# sat inside the sand<->grass lerp and painted the whole beach uniform
	# DESATURATED OLIVE — the "gray sand" report. New rule: pure golden sand
	# holds up to ~2.2 m (jittered ±1), grass ramps in over 2.2 m, and a
	# second high-frequency noise DITHERS the mid-band into sand/green
	# patches (real dune edge: tufts on sand, never a uniform olive blend).
	# MIRRORED in terrain_sand.gdshader `grass_k` and island_grass.gd's
	# grass-line mask — keep all three in sync.
	var sand_h := 2.2 + (jitter - 0.5) * 2.0
	var jitter2 := _fbm(q * 0.9 + Vector2(11.7, 63.1))
	var gk_raw := smoothstep(sand_h, sand_h + 2.2, h) * smoothstep(0.62, 0.86, slope)
	var grass_k := smoothstep(0.3, 0.7, gk_raw + (jitter2 - 0.5) * 0.5)
	var rock_k := maxf(smoothstep(0.80, 0.58, slope), smoothstep(0.55, 0.25, slope) * 0.6)
	var c := sand_col
	c = c.lerp(grass_col * (0.8 + 0.5 * jitter), grass_k)
	c = c.lerp(rock_col * (0.8 + 0.45 * jitter), rock_k)
	# Pond floor: muddy spring bottom with algae patches.
	var pd := q.distance_to(POND_POS)
	if pd < POND_R * 1.1 and h < pond_water_height() + 0.6:
		var depth_k := clampf((pond_water_height() - h) / 2.0, 0.0, 1.0)
		var mud := Color(0.30, 0.24, 0.16).lerp(Color(0.20, 0.30, 0.16), jitter)
		c = mud.lerp(Color(0.10, 0.18, 0.10), depth_k * 0.7)
	# High-altitude soil: dirt-brown scree ONLY on STEEP faces. The old
	# blanket smoothstep(5.0, 9.5, h) painted the whole upper mountain brown,
	# and the v3 "bare summit above 10.5 m" term bleached the peak pale
	# gray-white under the warm sun (user: top of island = plain white).
	# New rule (MIRRORED in terrain_sand.gdshader `mountain` — keep in
	# sync): soil/rock ONLY where the ground is steep (cliff scree);
	# the whole summit and every gentle high meadow stay grass green.
	var steep := 1.0 - slope
	var alpine_k := smoothstep(7.0, 11.5, h) * smoothstep(0.35, 0.55, steep)
	var soil_col := Color(0.34, 0.25, 0.16).lerp(Color(0.42, 0.33, 0.20), jitter)
	c = c.lerp(soil_col, alpine_k * 0.85)
	# Wet band above + below the waterline; submerged algae tint.
	var wet := 1.0 - smoothstep(0.1, 0.9, h)
	c = c.lerp(wet_sand, wet * 0.6)
	if h < 0.0:
		c = c.lerp(Color(0.30, 0.42, 0.28), clampf(-h / 4.0, 0.0, 0.5))
	c = c.lerp(Color(0.35, 0.31, 0.24), rock_k * wet * 0.5)
	return c

# ============================================================
# PROPS — palms / rocks / bushes / driftwood. Every prop sits ON the
# RENDERED terrain surface (y from _ground, see below).
# ============================================================
func _ground(q: Vector2) -> float:
	return _rendered_height(q)

## Height of the RENDERED terrain sheet at island-local q. The visible mesh
## is the grid sheet: its triangles chord straight across the analytic field
## between the 1.75 m vertices, so on any slope the visible surface sits
## BELOW the analytic height — props placed on the analytic value floated
## with a visible gap under the trunk. This triangle-interpolates the SAME
## heights array the mesh was built from (same cell triangulation as
## _build_terrain: diagonal b<->c2), matching the visual surface exactly.
## Falls back to the analytic field if queried before the terrain exists.
func _rendered_height(q: Vector2) -> float:
	if _terrain_heights.is_empty() or _terrain_n < 2:
		return terrain_height_local(q)
	var n := _terrain_n
	var fx := (q.x + grid_half) / grid_step
	var fz := (q.y + grid_half) / grid_step
	var ix := clampi(int(floor(fx)), 0, n - 2)
	var iz := clampi(int(floor(fz)), 0, n - 2)
	var u := clampf(fx - float(ix), 0.0, 1.0)
	var w := clampf(fz - float(iz), 0.0, 1.0)
	var ha := _terrain_heights[iz * n + ix]       # a (i, j)
	var hb := _terrain_heights[iz * n + ix + 1]   # b (i+1, j)
	var hc := _terrain_heights[(iz + 1) * n + ix] # c (i, j+1)
	var hd := _terrain_heights[(iz + 1) * n + ix + 1] # d (i+1, j+1)
	# Same two triangles per cell as _build_terrain: (b,c,a) for u+w<=1,
	# (d,c,b) above the diagonal — the sampled surface IS the rendered one.
	if u + w <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * w
	return hd + (hb - hd) * (1.0 - w) + (hc - hd) * (1.0 - u)

func _slope_y(q: Vector2) -> float:
	var e := 0.6
	var hl := _ground(q - Vector2(e, 0.0))
	var hr := _ground(q + Vector2(e, 0.0))
	var hd := _ground(q - Vector2(0.0, e))
	var hu := _ground(q + Vector2(0.0, e))
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized().y

func _ground_normal(q: Vector2) -> Vector3:
	var e := 0.6
	return Vector3(
		_ground(q - Vector2(e, 0.0)) - _ground(q + Vector2(e, 0.0)),
		2.0 * e,
		_ground(q - Vector2(0.0, e)) - _ground(q + Vector2(0.0, e))).normalized()

func _scatter_props() -> void:
	var pond := POND_POS
	# PALMS moved to _place_palm_chunk() — called in per-frame chunks by
	# generate() so 41 PlantInstance trees never materialize in one frame.
	# Seed the palm-candidate state here (deterministic order preserved:
	# the RNG stream continues exactly as the old single-call version).
	_palm_ok = _palm_assets()
	_palm_tries = 0
	if not _palm_ok:
		print("[IslandGenerator] palm bake missing — run tools/bake_island_vegetation.gd")

	# ---- rocks: headland / inland boulders / beach stones / shoreline ----
	var rock_meshes: Array[Mesh] = []
	for i in 5:
		rock_meshes.append(_make_rock(0.8 + _rng.randf() * 0.6))
	for i in rock_counts[0]: # headland cliffs ring
		var a := _rng.randf() * TAU
		var r := R_SHORE * _rng.randf_range(0.78, 0.98)
		var q := Vector2(cos(a) * r, sin(a) * r)
		var h := _ground(q)
		if h < -1.5 or h > 5.0:
			continue
		add_child(_place_mesh(rock_meshes[i % rock_meshes.size()], q, h,
			_rng.randf_range(1.6, 3.4), true, "Rock_Head_%d" % i, true))
	for i in rock_counts[1]: # inland boulders around the hills
		var q := Vector2(_rng.randf_range(-24.0, 24.0), _rng.randf_range(-24.0, 24.0))
		var h := _ground(q)
		if h < 1.0 or h > 12.0 or q.distance_to(pond) < POND_R:
			continue
		add_child(_place_mesh(rock_meshes[(i + 2) % rock_meshes.size()], q, h,
			_rng.randf_range(0.7, 2.0), true, "Rock_Boulder_%d" % i, true))
	for i in rock_counts[2]: # small beach stones
		var a := _rng.randf() * TAU
		var r := R_SHORE * _rng.randf_range(0.92, 1.08)
		var q := Vector2(cos(a) * r, sin(a) * r)
		add_child(_place_mesh(rock_meshes[i % rock_meshes.size()], q, _ground(q),
			_rng.randf_range(0.25, 0.6), true, "Rock_Stone_%d" % i, true))
	for i in rock_counts[3]: # shoreline + half-submerged (waves foam around them)
		var a := _rng.randf() * TAU
		var r := R_SHORE * _rng.randf_range(0.98, 1.10)
		var q := Vector2(cos(a) * r, sin(a) * r)
		var h := _ground(q)
		if h < -1.2 or h > 1.2:
			continue
		add_child(_place_mesh(rock_meshes[(i + 1) % rock_meshes.size()], q, h - 0.15,
			_rng.randf_range(0.6, 1.5), true, "Rock_Shore_%d" % i, true))


	# ---- bushes / ferns on the vegetated ring: REAL scanned plants ----
	# (leafy ground cover + purple flowers + dandelions from the scan;
	# falls back to the procedural blob bush only if the bake is missing)
	var bush_meshes: Array[Mesh] = []
	for p in SCAN_BUSH_MESHES:
		var bp := _mobile_bake(p)
		if ResourceLoader.exists(bp):
			var bmesh: Mesh = load(bp)
			_strip_detail_maps(bmesh)
			bush_meshes.append(bmesh)
	if bush_meshes.is_empty():
		bush_meshes = [_make_bush(1.0), _make_bush(1.3), _make_bush(0.8)]
	var b_placed := 0
	var b_tries := 0
	while b_placed < bush_count and b_tries < bush_count * 30:
		b_tries += 1
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * (R_SHORE - 8.0) + 3.0
		var q := Vector2(cos(a) * r, sin(a) * r)
		var h := _ground(q)
		# bushes follow the GRASS line: only where terrain paint is grassy
		# (same grass_k rule as _build_terrain) — no more shrubs on bare
		# sand or dangling off cliffs
		var slope := _slope_y(q)
		if h < 1.3 or h > 10.0 or slope < 0.78:
			continue
		if q.distance_to(pond) < POND_R + 1.0:
			continue
		var gj := _fbm(q * 0.22 + Vector2(51.2, 17.3))
		var sand_h := 1.3 + (gj - 0.5) * 1.4
		var grass_k := smoothstep(sand_h, sand_h + 1.4, h) * smoothstep(0.62, 0.86, slope)
		if grass_k < 0.45:
			continue
		add_child(_place_mesh(bush_meshes[b_placed % 3], q, h,
			_rng.randf_range(0.7, 1.6), false, "Bush_%d" % b_placed))
		b_placed += 1

	# ---- driftwood + fallen log on the beach (survival-game flavor) ----
	var log_a := _rng.randf() * TAU
	var log_q := Vector2(cos(log_a), sin(log_a)) * R_SHORE * 0.88
	var log_prop := _place_mesh(_make_log(), log_q, _ground(log_q), 1.0, true, "Driftwood_Log")
	log_prop.rotation.y = _rng.randf() * TAU
	add_child(log_prop)
	for i in 2:
		var d_a := _rng.randf() * TAU
		var d_q := Vector2(cos(d_a), sin(d_a)) * R_SHORE * _rng.randf_range(0.85, 1.0)
		var d := _place_mesh(_make_driftwood(), d_q, _ground(d_q), 1.0, false, "Driftwood_%d" % i)
		d.rotation.y = _rng.randf() * TAU
		add_child(d)

	# ---- freshwater pond surface ----
	# NOTE: built ONLY by _build_pond_water() (fresh_water.gdshader disc).
	# A second flat StandardMaterial3D disc used to be added here too — the
	# two coplanar discs z-fought and the pond read as a fake flat sticker.

## ONE CHUNK of palm placement (called once per frame by generate()):
## instantiating 40+ PlantInstance trees in a single frame was the biggest
## remaining freeze. Per-frame size comes from the device tier (MobilePerf
## .palm_chunk: 3-5) so even weak phones keep every frame under ~0.3 s and
## the grove still "streams in" in small waves.
func _place_palm_chunk() -> void:
	if not _palm_ok:
		return
	var pond := POND_POS
	var placed_now := 0
	var palms_target := _palms_target()
	while _palms_placed < palms_target and placed_now < MobilePerf.palm_chunk() and _palm_tries < palms_target * 30:
		_palm_tries += 1
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * (R_SHORE - 6.0) + 4.0
		var q := Vector2(cos(a) * r, sin(a) * r)
		var h := _ground(q)
		if h < 0.9 or h > 9.5 or _slope_y(q) < 0.78:
			continue
		if q.distance_to(pond) < POND_R + 1.5:
			continue
		var ok := true
		for p in _palm_spots:
			# 4.2 m spacing (was 5.0): the denser grove must still keep the
			# ~3.6 m crowns from ever overlapping.
			if p.distance_to(q) < 4.2:
				ok = false
				break
		if not ok:
			continue
		_palm_spots.append(q)
		add_child(_make_palm_plant(q, h))
		_palms_placed += 1
		placed_now += 1
# ISLAND COCONUT PALM — a PlantInstance (the SAME system the island apple
# tree and all planted trees use): real baked mature model, per-tree VARIED
# nut crop (some full bunches, some 1-2 nuts, some bare — fruit_variation),
# ~one ripe coconut drops per day, emptied slot regrows over ~2 in-game
# days. Choppable for wood like any tree. The old static mesh instance
# shipped an identical baked-in bunch on every palm and no lifecycle.
# ============================================================
func _make_palm_plant(q: Vector2, ground_h: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Palm_%d" % get_child_count()
	root.position = Vector3(q.x, ground_h - 0.08, q.y)
	root.rotation.y = _rng.randf() * TAU
	# Bigger palms + NATURAL VARIETY (user: trees all looked like identical
	# straight sticks): every tree gets a random size, a 0-8° trunk lean in
	# a random direction (shore trees really lean seaward) and — on ~30% —
	# a gentle 4-9° crook partway up (a second, differently-aimed lean),
	# so no two silhouettes match. The sway shader is world-wind-keyed and
	# the aim/reach math uses local space, so lean/crook stay gameplay-safe.
	var s := _rng.randf_range(1.25, 1.75) # was 0.95-1.35 — taller, crown palms
	if OS.has_feature("mobile"):
		s *= 0.92
	root.scale = Vector3.ONE * s
	var lean_dir := _rng.randf() * TAU
	var lean_amt := deg_to_rad(_rng.randf_range(0.0, 8.0))
	root.rotation.z = cos(lean_dir) * lean_amt
	root.rotation.x = sin(lean_dir) * lean_amt
	var palm := PlantInstance.new()
	palm.plant_id = "Coconut"
	palm.start_stage = PlantInstance.Stage.MATURE
	if _rng.randf() < 0.3:
		# Gentle crook: a second lean on the tree node itself (the crown
		# swings off-axis with the trunk) — collision/aim stay in the
		# PlantInstance's local frame, so gameplay is unaffected.
		var crook_dir := _rng.randf() * TAU
		var crook := deg_to_rad(_rng.randf_range(4.0, 9.0))
		palm.rotation = Vector3(sin(crook_dir) * crook, 0.0, cos(crook_dir) * crook)
	root.add_child(palm)
	palm.position = Vector3.ZERO
	return root

# ============================================================
# ROCKS / BUSHES / DRIFTWOOD — displaced-sphere uniques.
# ============================================================
func _make_rock(variant: float) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.7 # slightly squashed
	sm.radial_segments = 14 # more rings/segments: the noise needs geometry
	sm.rings = 9
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var off := Vector2(_rng.randf() * 40.0, _rng.randf() * 40.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ii in indices:
		var v := verts[ii]
		# Broad lumps + fine chips give the noise; the FACET field quantizes
		# the surface into a handful of near-plane cuts so the silhouette
		# reads as a chiseled, broken stone (a pure noise ball still reads
		# as a potato).
		var lump := (_fbm(Vector2(v.x, v.z) * 1.1 + off + Vector2(v.y * 0.7, 0.0)) - 0.5) * 0.9 * variant
		var chip := (_fbm(Vector2(v.y, v.x) * 3.1 + off * 1.7) - 0.5) * 0.22 * variant
		var cut := _fbm(Vector2(v.x, v.z) * 0.9 + off * 2.3 + Vector2(v.y * 0.5, v.y * 1.3))
		var facet := 1.0 + (roundf(cut * 3.0) / 3.0 - 0.5) * 0.30 * variant
		var d := (1.0 + lump + chip) * facet
		st.add_vertex(Vector3(v.x * d, v.y * d * 0.8, v.z * d))
	st.generate_normals()
	var mesh := st.commit()
	# procedural triplanar granite (no textures needed, always night-safe)
	if ResourceLoader.exists(ROCK_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(ROCK_SHADER)
		mat.set_shader_parameter("tint", Color(0.9 + _rng.randf() * 0.2, 0.9 + _rng.randf() * 0.15, 0.85 + _rng.randf() * 0.2))
		mat.set_shader_parameter("seed", _rng.randf() * 100.0)
		mesh.surface_set_material(0, mat)
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.42, 0.40, 0.36)
		fallback.roughness = 1.0
		mesh.surface_set_material(0, fallback)
	return mesh

func _make_bush(scale_f: float) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 0.7 * scale_f
	sm.height = 1.1 * scale_f
	sm.radial_segments = 8
	sm.rings = 4
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var off := Vector2(_rng.randf() * 30.0, _rng.randf() * 30.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ii in indices:
		var v := verts[ii]
		var d := 1.0 + (_fbm(Vector2(v.x, v.z) * 2.2 + off) - 0.5) * 0.7
		st.add_vertex(Vector3(v.x * d, maxf(v.y * d, -0.05), v.z * d)) # never below ground
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.30, 0.09).lerp(Color(0.20, 0.40, 0.12), _rng.randf())
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	return mesh

func _make_log() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.16
	c.bottom_radius = 0.22
	c.height = 2.6
	c.radial_segments = 7
	var arrays := c.get_mesh_arrays()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
	arr[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	arr[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.28, 0.18)
	am.surface_set_material(0, mat)
	return am

func _make_driftwood() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.06
	c.height = 1.4
	c.radial_segments = 5
	var arrays := c.get_mesh_arrays()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
	arr[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	arr[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.45, 0.34)
	am.surface_set_material(0, mat)
	return am

func _place_mesh(mesh: Mesh, q: Vector2, ground_h: float, scale_f: float,
		with_collision: bool, pname: String, tilt_to_ground := false) -> Node3D:
	var root := Node3D.new()
	root.name = pname
	root.position = Vector3(q.x, ground_h - 0.06 * scale_f, q.y)
	root.rotation.y = _rng.randf() * TAU
	root.rotation.x = _rng.randf_range(-0.06, 0.06)
	root.scale = Vector3.ONE * scale_f
	# ROCKS ONLY (tilt_to_ground): embed the stone INTO the slope like a real
	# boulder — tilted with the ground and sunk deeper. A flat-placed ball on
	# a slope shows its sliding intersection line as you walk past, which
	# read as "the stone is moving".
	if tilt_to_ground:
		var n := _ground_normal(q)
		var axis := Vector3(n.z, 0.0, -n.x)
		if axis.length() > 0.01:
			var tilt := Basis(Quaternion(axis.normalized(), acos(clampf(n.y, -1.0, 1.0))))
			root.basis = tilt * root.basis # world-space tilt after the yaw
		root.position.y = ground_h - 0.22 * scale_f # bury deeper: hide the seam
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	if with_collision:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		root.add_child(body)
	# IMMOVABLE-STONE GUARD: the raft and loose debris must slide off rocks,
		# never drag or nudge them ("stones moving when I go past"). Static
		# bodies are already infinite-mass; max friction + zero bounce just
		# kills any sliding tug-of-war at the contact point.
		if with_collision:
			for child in root.get_children():
				if child is StaticBody3D:
					var pm := PhysicsMaterial.new()
					pm.friction = 1.0
					pm.bounce = 0.0
					(child as StaticBody3D).physics_material_override = pm
	return root

# ============================================================
# Existing scene children that care about the new terrain.
# ============================================================
func _place_beacon_and_grass() -> void:
	var beacon := get_node_or_null("IslandBeacon") as Node3D
	if beacon != null:
		beacon.position = Vector3(HILL1.x, _ground(HILL1) - 0.4, HILL1.y)
	var grass := get_node_or_null("IslandGrass") as Node3D
	if grass != null:
		# grass/baked/grass_clump.tres spans y 0..1: plant the field so the
		# ray window (raycast_up 8 / raycast_down 12) covers beach (-2 m)
		# through the grass line (~+9 m) without wasting rays on the hills.
		grass.position = Vector3(0, 6.0, 0)
