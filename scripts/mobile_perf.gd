extends Node
## ============================================================
## MOBILE AUTO-QUALITY — two halves, one autoload:
##
##   1. BOOT TIERING: one-time device classification into
##      LOW / MID / HIGH (RAM, CPU cores; GPU name logged for reports).
##      Subsystems ask the tier for their budget instead of hardcoding
##      "mobile" cuts (static funcs, callable via preload so --check-only
##      parsers don't need the autoload registered):
##        grass_clumps()            island_grass baked-field cap
##        palm_chunk()              island_generator palms placed per frame
##        palms_scale()             island_generator palm count scale
##        terrain_rows_per_frame()  first-launch height-field chunking
##        prewarm_window()/stall_window()  main_menu loading guards
##        scaling_base()            starting 3D resolution scale
##      Desktop returns untouched values for every one of them.
##
##   2. RUNTIME FPS GOVERNOR (mobile only): a ring buffer of frame times
##      steers a quality LADDER while playing. One bad window (mean frame
##      time over the 60 fps budget) drops one rung: render scale first,
##      then rain, then grass visibility/density. Three GOOD windows in a
##      row give one rung back. Degrade fast, restore slow — no ping-pong,
##      and the ladder never climbs above the boot-tier settings. This is
##      what makes "any kind of phone" work: a mis-tiered device corrects
##      itself within seconds of gameplay.
##
## Desktop verification of the whole mobile path (no phone needed):
##   RSM_FORCE_MOBILE=1 RSM_FORCE_TIER=low godot --headless --path . ...
## ============================================================

const TARGET_FPS := 60.0
const HIST_N := 90          # ~1.5 s of frames per measurement window
const RESTORE_WINDOWS := 3  # consecutive good windows before +1 rung
const STEP_COOLDOWN := 3.0  # minimum seconds between ladder moves
# BAD/OK frame-time thresholds now derive from fps_budget() per tier
# (weak phones must not be judged against a 60 fps bar they never had).

# Quality ladder. Each rung: [render-scale delta, rain delta,
# grass visibility multiplier, grass instance multiplier]. Rung 0 is the
# boot-tier setting; each drop is individually small enough to be nearly
# invisible but together they climb down to very weak phones.
# PASS 32 FLOORS: the old bottom rungs (vis x0.40 / count x0.50 / scale
# 0.50) ERASED the meadow on weak phones — the field's per-instance
# visibility culling at <60 m removed grass from every view the player
# actually looks at (spawn is offshore), which read as "grass missing".
# Grass is ONE draw call; the real GPU levers are render scale + rain.
# New floors: grass never below x0.75, render scale never below 0.60.
const LADDER := [
	[0.00, 0, 1.00, 1.00],
	[-0.05, 0, 1.00, 1.00],
	[-0.05, -100, 1.00, 1.00],
	[-0.05, -100, 1.00, 1.00],
	[-0.05, -150, 0.90, 0.85],
	[-0.10, -150, 0.75, 0.75],
]

static var _tier := -1
static var _forced_mobile := false
static var _forced_checked := false

# ---- boot classification -------------------------------------------------

## Debug override: treat this desktop run as a phone (see file header).
static func debug_mobile() -> bool:
	if not _forced_checked:
		_forced_checked = true
		_forced_mobile = OS.get_environment("RSM_FORCE_MOBILE") != ""
	return _forced_mobile

## Force mobile-mode + tier from code (verification tools call this BEFORE
## anything touches device_tier()/mobile_like()).
static func set_forced_mobile(v: bool) -> void:
	_forced_mobile = v
	_forced_checked = true

## Freeze the runtime ladder (look checks / screenshots / benchmarks that
## must measure BOOT quality, not the governor's reaction to test-harness
## frame times). The instance reads this every step.
static var governor_enabled := true
static func set_governor_enabled(v: bool) -> void:
	governor_enabled = v

## True on real phone builds AND forced-mobile verification runs.
static func mobile_like() -> bool:
	return OS.has_feature("mobile") or debug_mobile()

## 0 = low, 1 = mid, 2 = high. Desktop is always high; the runtime
## governor corrects any real-world mis-tier within seconds.
static func device_tier() -> int:
	if _tier >= 0:
		return _tier
	if not mobile_like():
		_tier = 2
		return _tier
	var forced := OS.get_environment("RSM_FORCE_TIER").to_lower()
	if forced == "low" or forced == "mid" or forced == "high":
		_tier = {"low": 0, "mid": 1, "high": 2}[forced]
		return _tier
	var ram_gb := 0.0
	var mi := OS.get_memory_info()
	if mi.has("physical"):
		ram_gb = float(mi["physical"]) / 1073741824.0
	var cores := OS.get_processor_count()
	if ram_gb <= 4.5 or cores <= 6:
		_tier = 0
	elif ram_gb >= 6.0 and cores >= 8:
		_tier = 2
	else:
		_tier = 1
	return _tier

static func tier_name() -> String:
	return ["low", "mid", "high"][clampi(device_tier(), 0, 2)]

# ---- per-subsystem budgets (desktop = untouched values) -------------------

## Baked grass field cap. Order inside the bake is scatter-random, so a cap
## thins the island uniformly. Kept high — heavy thinning read bald.
static func grass_clumps() -> int:
	if not mobile_like():
		return 999999
	return [5000, 6000, 7000][device_tier()]

## Palms instantiated per frame while the grove streams in.
static func palm_chunk() -> int:
	if not mobile_like():
		return 5
	return [3, 4, 5][device_tier()]

## Palm count scale vs the desktop grove (was a flat 0.7 on all phones).
static func palms_scale() -> float:
	if not mobile_like():
		return 1.0
	return [0.55, 0.7, 0.8][device_tier()]

## First-launch terrain height+paint rows computed per frame (161 rows
## total). Desktop = 161 = the old single-pass behavior; phones spread the
## ~10 s GDScript pass over many frames so nothing freezes.
static func terrain_rows_per_frame() -> int:
	if not mobile_like():
		return 161
	return [8, 12, 18][device_tier()]

## How long the menu waits for the prewarm chain AFTER the scene is parsed
## (the 16 MB mobile apple bake needs longer than desktop).
static func prewarm_window() -> float:
	if not mobile_like():
		return 8.0
	return [14.0, 11.0, 9.0][device_tier()]

## No-real-progress seconds before the menu falls back to a sync load.
static func stall_window() -> float:
	if not mobile_like():
		return 15.0
	return [22.0, 20.0, 18.0][device_tier()]

## Boot 3D resolution scale (bilinear upscale; free, invisible on phones).
static func scaling_base() -> float:
	if not mobile_like():
		return 1.0
	return [0.70, 0.80, 0.90][device_tier()]

## FPS the governor aims to PROTECT. NOT the phone's real refresh cap —
## the bar a device of this tier can be expected to HOLD. A weak phone
## idling at 30-45 fps used to sit pinned at the bottom ladder rung
## (grass erased + minimum render scale); now it holds a rung that fits
## its class and only keeps dropping if it fails THAT bar too.
static func fps_budget() -> float:
	if not mobile_like():
		return 60.0
	return [30.0, 40.0, 55.0][device_tier()]

# ---- instance: boot cuts + the FPS governor -------------------------------

var _base_scale := 1.0
var _rain_boot := 700
var _rain_now := 700
var _hist := PackedFloat32Array()
var _hist_i := 0
var _hist_filled := 0
var _good_windows := 0
var _cooldown := 0.0
var _step := 0
var _last_gv := 1.0 # last grass multipliers pushed (avoid re-push spam)
var _last_gc := 1.0

func _ready() -> void:
	var tier := device_tier()
	if not mobile_like():
		set_process(false)
		print("[MobilePerf] desktop: auto-quality idle (settings untouched)")
		return
	_base_scale = scaling_base()
	Engine.max_fps = 30 if tier == 0 else 60
	_rain_boot = [250, 350, 500][tier]
	_rain_now = _rain_boot
	# Shadows: high tier keeps the full 2048 atlas (16-bit depth halves its
	# memory and fill); low/mid drop to 1024 — the single biggest hang
	# source with alpha-cut foliage.
	RenderingServer.directional_shadow_atlas_set_size(2048 if tier >= 2 else 1024, true)
	# 3D render scale per tier (bilinear upscale; phones hide 10-30% fewer
	# pixels completely at arm's length).
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = _base_scale
	# Rain budget applies whenever the particle node enters the tree (it
	# lives in the game scene, not the menu, so it is not here at _ready —
	# the old one-shot lookup silently missed it every boot).
	get_tree().node_added.connect(_on_node_added)
	_hist.resize(HIST_N)
	print("[MobilePerf] tier %s (ram %.1f GB, %d cores, gpu '%s'): shadow %d, scale %.2f, rain %d" % [
		tier_name(), float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
		OS.get_processor_count(), RenderingServer.get_video_adapter_name(),
		2048 if tier >= 2 else 1024, _base_scale, _rain_now])

func _on_node_added(n: Node) -> void:
	if n.is_in_group("rain") and "particle_amount" in n:
		n.set("particle_amount", _rain_now)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.25) # keep the odd 1 s hitch out of the mean
	_hist[_hist_i] = dt * 1000.0
	_hist_i = (_hist_i + 1) % HIST_N
	if _hist_filled < HIST_N:
		_hist_filled += 1
		return
	# Only judge GAMEPLAY frames: scene-change/loading spikes must never
	# buy permanent downgrades.
	if get_tree().get_first_node_in_group("island") == null:
		_hist_filled = 0
		_good_windows = 0
		return
	if not governor_enabled:
		return
	_cooldown -= dt
	if _cooldown > 0.0:
		return
	var mean := 0.0
	for ms in _hist:
		mean += ms
	mean /= float(HIST_N)
	var bad_ms := 1050.0 / fps_budget()  # tier bar + one dropped frame
	var ok_ms := 1000.0 / fps_budget()
	if mean > bad_ms:
		_good_windows = 0
		_move_step(_step + 1)
	elif mean <= ok_ms:
		_good_windows += 1
		if _good_windows >= RESTORE_WINDOWS and _step > 0:
			_good_windows = 0
			_move_step(_step - 1)

## Move the quality ladder and apply the rung (idempotent per rung).
func _move_step(s: int) -> void:
	s = clampi(s, 0, LADDER.size() - 1)
	if s == _step:
		return
	_step = s
	_cooldown = STEP_COOLDOWN
	var cfg: Array = LADDER[s]
	var scale := clampf(_base_scale + float(cfg[0]), 0.5, 1.0)
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = scale
	_rain_now = maxi(150, _rain_boot + int(cfg[1]))
	var rain := get_tree().get_first_node_in_group("rain")
	if rain != null and "particle_amount" in rain:
		rain.set("particle_amount", _rain_now)
	var gv := float(cfg[2])
	var gc := float(cfg[3])
	# Restoring rung 0 must RESTORE, not just stop degrading — otherwise a
	# device that dips once keeps the downgrade forever.
	if s == 0:
		gv = 1.0
		gc = 1.0
	if gv != _last_gv or gc != _last_gc or s == 0:
		for g in get_tree().get_nodes_in_group("grass_field"):
			if g.has_method("governor_quality"):
				g.call("governor_quality", gv, gc)
	_last_gv = gv
	_last_gc = gc
	print("[MobilePerf] governor rung %d: scale %.2f, rain %d, grass vis x%.2f count x%.2f" % [
		s, scale, _rain_now, gv, gc])

