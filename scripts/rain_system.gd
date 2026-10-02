extends Node3D
class_name RainSystem

# ============================================================
# RAIN SYSTEM v2 — random, timed rain events with:
#   - wind-driven, properly-oriented falling rain streaks
#   - impact splashes/sparks where rain hits the raft, roofs, walls,
#     foundations, stairs, doors, windows (raycast-based, pooled for perf)
#   - a softer ripple splash where rain lands on open ocean
#   - sky/ocean darkening + optional lightning + audio
# Attach as a child of Player (like RopeSystem) so the rain volume always
# follows the camera. Fully self-building at runtime — no manual scene
# setup beyond adding this one node and attaching this script.
# ============================================================

# --- Scheduling (real-world minutes; independent of the in-game day/night
# clock, which runs on its own 15-real-minutes-per-day cycle) ---
@export var min_interval_minutes: float = 6.0
@export var max_interval_minutes: float = 14.0
@export var rain_chance: float = 0.55
@export var min_duration_minutes: float = 1.5
@export var max_duration_minutes: float = 5.0

# --- Falling rain visuals ---
@export var particle_amount: int = 700
@export var rain_area_size: Vector3 = Vector3(24.0, 16.0, 24.0)
@export var fall_speed: float = 14.0
@export var fade_time: float = 4.0
## Horizontal drift while falling (x = east/west, y = north/south). Small
## values (0.2-0.6) read as believable wind-blown rain; 0,0 = dead vertical.
@export var wind_direction: Vector2 = Vector2(0.4, 0.15)
@export var toggle_fog_during_rain: bool = true

# --- Indoor cover ("rain must never fall inside a roof/wall/stairs") ---
## While it rains, a ray straight up from the camera detects a roof/deck
## covering the player. Probe rays then measure how far the cover extends;
## the rain emission volume switches from the full box around the camera to a
## RING just outside the covered footprint, so drops only exist outside the
## roof — rain is still visible at every open side, but never indoors.
const COVER_CHECK_INTERVAL := 0.15
const COVER_RAY_LENGTH := 14.0
const COVER_MARGIN := 0.45      ## wind can blow drops sideways under the rim
const COVER_PROBE_RADII := [1.2, 2.4, 3.6]
## Outdoor cap probes: while NOT under a roof, these find nearby building
## roofs/decks so the box top can be lowered below them (drops must never
## spawn above a nearby house and rain through it, visible from outside).
const NEARBY_PROBE_DIRS := [
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0),
	Vector2(0.707, 0.707), Vector2(-0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]
const NEARBY_PROBE_RADII := [2.4, 5.0, 8.0]
const RING_SPAWN_ABOVE_CAMERA := 6.0  ## ring spawns this high: drops fall onto/outside the roof, never under it
var _covered := false
var _cover_timer := 0.0
var _cover_check_interval := COVER_CHECK_INTERVAL
var _cover_ring_radius := 4.0
var _last_ring_radius := -1.0  ## last radius actually pushed into the material
## Rain box top (emitter-local Y). Lowered below nearby roof undersides when
## the camera is outdoors next to a building, so drops never spawn above a
## roof and fall through it into the walls.
var _box_top := rain_area_size.y * 0.5

# --- Submerged camera (rain must not render underwater) ---
var _camera_submerged := false

# --- Impact splashes ("sparks") where rain hits solid surfaces ---
@export var splash_enabled: bool = true
@export var splash_pool_size: int = 16
@export var splashes_per_second: float = 28.0   # scaled by current rain intensity
@export var splash_particle_count: int = 7
@export var splash_scan_radius: float = 11.0    # only spawn splashes reasonably close to camera
## Splashes are biased toward the camera's forward cone (where the raft,
## roof and deck are on screen) so rain visibly pounds the surfaces the
## player is looking at instead of scattering across empty ocean.
@export var forward_bias: float = 0.75
@export var forward_cone_radius: float = 4.5
## Also spawn (fainter, rarer) ripple splashes on open water, not just structures.
@export var water_splash_enabled: bool = true

# --- Audio (optional — assign your own .ogg/.wav in the Inspector) ---
@export var rain_sound: AudioStream = null
@export var thunder_sounds: Array[AudioStream] = []
@export var enable_lightning: bool = true
@export var lightning_chance_per_check: float = 0.12

var _player: Node3D = null
var _camera: Camera3D = null
var _sky3d: Node = null
var _sky: Node = null
var _env: Environment = null
var _ocean: Node = null

var _particles: GPUParticles3D = null
var _rain_mat: StandardMaterial3D = null
var _rain_process_mat: ParticleProcessMaterial = null
var _audio: AudioStreamPlayer = null
var _thunder_audio: AudioStreamPlayer = null
var _overlay: ColorRect = null
var _flash: ColorRect = null

var _splash_pool: Array[GPUParticles3D] = []
var _splash_index: int = 0
var _splash_accum: float = 0.0

var _schedule_timer: Timer = null
var _lightning_timer: Timer = null

var _is_raining: bool = false
var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _rain_end_time: float = 0.0

var _orig_fog_density: float = -1.0
var _orig_ambient_energy: float = -1.0
var _orig_wave_height: float = -1.0


func _ready() -> void:
	add_to_group("rain_system")
	# Rain is an occasional weather event, so keep its particle and ray-query
	# budget conservative on mobile without removing the effect.
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		particle_amount = mini(particle_amount, 420)
		splash_pool_size = mini(splash_pool_size, 8)
		splash_particle_count = mini(splash_particle_count, 5)
		splashes_per_second = minf(splashes_per_second, 10.0)
		_cover_check_interval = 0.4
	_find_refs()
	_build_particles()
	_build_splash_pool()
	_build_audio()
	_build_overlay()

	_schedule_timer = Timer.new()
	_schedule_timer.one_shot = true
	add_child(_schedule_timer)
	_schedule_timer.timeout.connect(_on_schedule_timeout)
	_queue_next_check()


func _find_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and (_camera == null or not is_instance_valid(_camera)):
		_camera = _player.get_node_or_null("CamPivot/SpringArm3D/Camera3D")
	if _sky3d == null:
		var scene := get_tree().current_scene
		if scene != null:
			_sky3d = scene.get_node_or_null("Sky3D")
			_ocean = scene.get_node_or_null("Ocean")
	if _ocean == null:
		_ocean = get_tree().get_first_node_in_group("ocean")
	if _sky3d != null:
		_sky = _sky3d.get("sky")
		_env = _sky3d.get("environment") as Environment


# ============================================================
# BUILD: falling rain — thin stretched streaks oriented along the actual
# fall direction (wind + gravity), not just camera-facing sprites. This is
# the single biggest visual upgrade: real rain reads as diagonal lines that
# match the wind, not vertical confetti.
# ============================================================
func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = particle_amount
	_particles.lifetime = maxf(rain_area_size.y / fall_speed, 0.5)
	_particles.emitting = false
	# World-space drops: streaks fall straight down in the world while the
	# emitter (this node) follows the camera — rain never slides with view
	# rotation and the cover ring below stays anchored in the world.
	_particles.local_coords = false
	_particles.visibility_aabb = AABB(-rain_area_size, rain_area_size * 2.0)

	var mat := ParticleProcessMaterial.new()
	var fall_dir := Vector3(wind_direction.x, -3.0, wind_direction.y).normalized()
	mat.direction = fall_dir
	mat.spread = 4.0
	mat.gravity = Vector3(0, -4.0, 0)
	mat.initial_velocity_min = fall_speed * 0.9
	mat.initial_velocity_max = fall_speed * 1.1
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = rain_area_size * 0.5
	mat.scale_min = 0.85
	mat.scale_max = 1.3
	# THE KEY LINE for a real "streak" look: orient each quad's long axis
	# along its actual velocity (wind + fall) instead of leaving it flat.
	mat.set("particle_flag_align_y_to_velocity", true)
	_particles.process_material = mat
	_rain_process_mat = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, clampf(fall_speed * 0.045, 0.35, 0.9))
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.albedo_color = Color(0.75, 0.82, 0.9, 0.0)
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Soft particles: drops fade out where they meet existing geometry (water
	# surface, roof slabs, decks) instead of visibly slicing through them.
	_rain_mat.proximity_fade_enabled = true
	_rain_mat.proximity_fade_distance = 0.25
	quad.material = _rain_mat
	_particles.draw_pass_1 = quad

	add_child(_particles)


# ============================================================
# BUILD: splash/spark impact pool — small one-shot bursts fired wherever a
# raycast finds a raindrop hitting the raft, a roof, a wall top, stairs,
# a door, or a window. Pooled and reused so performance stays flat no
# matter how long it rains (no growing node count).
# ============================================================
func _build_splash_pool() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.9, 0.95, 1.0, 0.95)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = smat

	for i in splash_pool_size:
		var p := GPUParticles3D.new()
		p.name = "Splash%d" % i
		p.amount = splash_particle_count
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		# World-space: once fired, these must NOT follow RainSystem's own
		# per-frame repositioning onto the camera.
		p.local_coords = false
		p.draw_pass_1 = quad

		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 55.0
		pm.gravity = Vector3(0, -9.0, 0)
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 2.2
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.damping_min = 1.0
		pm.damping_max = 2.2
		p.process_material = pm

		add_child(p)
		_splash_pool.append(p)


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "RainAudio"
	_audio.stream = rain_sound
	_audio.volume_db = -80.0
	add_child(_audio)

	_thunder_audio = AudioStreamPlayer.new()
	_thunder_audio.name = "ThunderAudio"
	add_child(_thunder_audio)

	if enable_lightning:
		_lightning_timer = Timer.new()
		_lightning_timer.wait_time = 6.0
		_lightning_timer.one_shot = false
		add_child(_lightning_timer)
		_lightning_timer.timeout.connect(_maybe_lightning)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RainOverlay"
	layer.layer = 15
	get_tree().current_scene.add_child.call_deferred(layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.55, 0.65, 0.75, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.call_deferred("add_child", _overlay)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.call_deferred("add_child", _flash)


# ============================================================
# SCHEDULING
# ============================================================
func _queue_next_check() -> void:
	var minutes := randf_range(min_interval_minutes, max_interval_minutes)
	_schedule_timer.start(minutes * 60.0)


func _on_schedule_timeout() -> void:
	if not _is_raining and randf() <= rain_chance:
		var duration := randf_range(min_duration_minutes, max_duration_minutes) * 60.0
		start_rain(duration)
	_queue_next_check()


# ============================================================
# PUBLIC CONTROL
# ============================================================
func start_rain(duration_seconds: float) -> void:
	_find_refs()
	if _is_raining:
		_rain_end_time = maxf(_rain_end_time, Time.get_ticks_msec() / 1000.0 + duration_seconds)
		return
	_is_raining = true
	_rain_end_time = Time.get_ticks_msec() / 1000.0 + duration_seconds
	_target_intensity = 1.0
	# Re-evaluate cover immediately so a rain that starts while the player is
	# already indoors begins in ring mode (no indoor spray on the first frames).
	_cover_timer = 0.0
	_update_cover_state(0.0)
	if not _camera_submerged:
		_particles.emitting = true
	if rain_sound != null:
		_audio.play()
	if _lightning_timer != null:
		_lightning_timer.start()
	_cache_environment_originals()
	if toggle_fog_during_rain and _sky != null:
		_sky.set("fog_visible", true)


func stop_rain() -> void:
	_is_raining = false
	_target_intensity = 0.0
	if _lightning_timer != null:
		_lightning_timer.stop()


func is_raining() -> bool:
	return _is_raining


func _cache_environment_originals() -> void:
	if _sky != null and _orig_fog_density < 0.0:
		_orig_fog_density = float(_sky.get("fog_density"))
	if _env != null and _orig_ambient_energy < 0.0:
		_orig_ambient_energy = _env.ambient_light_energy
	if _ocean != null and _orig_wave_height < 0.0:
		_orig_wave_height = float(_ocean.get("wave_height"))


func _process(delta: float) -> void:
	_follow_player()
	_update_cover_state(delta)
	_update_submerged_state()
	_update_intensity(delta)
	_process_splashes(delta)
	if _is_raining and Time.get_ticks_msec() / 1000.0 >= _rain_end_time:
		stop_rain()
	# Rain only renders while its alpha is visible and the camera is ABOVE
	# the water surface (no drops swirling around underwater). Gating on
	# _intensity (not _is_raining) preserves the smooth 4 s fade-out.
	var should_emit := _intensity > 0.01 and not _camera_submerged
	if _particles.emitting != should_emit:
		_particles.emitting = should_emit
	if not _is_raining and _intensity <= 0.001:
		if toggle_fog_during_rain and _sky != null and _orig_fog_density >= 0.0:
			_sky.set("fog_visible", false)
			_sky.set("fog_density", _orig_fog_density)

# ============================================================
# INDOOR COVER — the core "no rain inside the roof" logic.
# A vertical ray from the camera finds a roof/deck above the player; probe
# rays walking outward measure the covered extent; the rain emission becomes
# a ring hugging just outside that extent. When the cover disappears (player
# walks out or the ray misses) the full box volume is restored.
# ============================================================
func _update_cover_state(delta: float) -> void:
	_cover_timer -= delta
	if _cover_timer > 0.0:
		return
	_cover_timer = _cover_check_interval
	if not _is_raining:
		# No rain: skip the raycasts entirely, and make sure the emitter is
		# back in full-box mode for the next downpour.
		if _covered or absf(_box_top - rain_area_size.y * 0.5) > 0.01:
			_covered = false
			_box_top = rain_area_size.y * 0.5
			_apply_cover_mode()
		return
	var was := _covered
	var was_top := _box_top
	_covered = false
	_box_top = rain_area_size.y * 0.5
	if _camera != null and is_instance_valid(_camera):
		_covered = _measure_cover()
	if _covered != was or absf(_box_top - was_top) > 0.5 \
			or (_covered and absf(_cover_ring_radius - _last_ring_radius) > 0.5):
		_apply_cover_mode()

## True when the hit is a horizontal-ish face on a BUILDING piece (the
## "build_surface" group). Terrain/palms never count as shelter.
func _is_cover_hit(hit: Dictionary) -> bool:
	if hit.is_empty() or absf((hit["normal"] as Vector3).y) < 0.5:
		return false
	var col: Object = hit.get("collider")
	return col is Node and (col as Node).is_in_group("build_surface")

func _measure_cover() -> bool:
	var space := get_world_3d().direct_space_state
	var cam := _camera.global_position
	var exclude: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		exclude.append(_player.get_rid())

	# 1) Is the camera itself under a roof/deck? The ray hits the UNDERSIDE of
	#    the slab, whose reported face normal may point down (true geometric
	#    normal) or up (backend-flipped toward the ray) — accept either, and
	#    reject only near-vertical faces (wall sides, which can never shelter).
	var q := PhysicsRayQueryParameters3D.create(
		cam + Vector3(0.0, 0.3, 0.0),
		cam + Vector3(0.0, COVER_RAY_LENGTH, 0.0))
	q.collision_mask = 1
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if _is_cover_hit(hit):
		# How far does the cover extend? Walk 4 axis directions outward; stop
		# at the first radius whose upward ray misses (open sky = rim found).
		var inner := INF
		for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var extent := 0.0
			for r in COVER_PROBE_RADII:
				var p := cam + Vector3(dir.x * r, 0.3, dir.y * r)
				var pq := PhysicsRayQueryParameters3D.create(
					p, p + Vector3(0.0, COVER_RAY_LENGTH, 0.0))
				pq.collision_mask = 1
				pq.exclude = exclude
				if not _is_cover_hit(space.intersect_ray(pq)):
					break
				extent = r
			inner = minf(inner, extent)
		# Wind margin: gusts push drops sideways as they fall, so the ring starts
		# OUTSIDE the measured footprint (a larger radius = farther out), never
		# under the roof rim.
		_cover_ring_radius = clampf(inner + COVER_MARGIN, 2.0, 12.0)
		return true

	# 2) Outdoors but next to a building: find the LOWEST roof/deck above the
	#    camera and cap the rain box top just below it. Without this, drops
	#    spawning above a nearby house would fall through the roof into the
	#    walls — visible indoors through doors/windows from outside.
	var lowest := -1.0
	for dir in NEARBY_PROBE_DIRS:
		for r in NEARBY_PROBE_RADII:
			var p := cam + Vector3(dir.x * r, 0.3, dir.y * r)
			var pq := PhysicsRayQueryParameters3D.create(
				p, p + Vector3(0.0, COVER_RAY_LENGTH, 0.0))
			pq.collision_mask = 1
			pq.exclude = exclude
			var ph := space.intersect_ray(pq)
			if _is_cover_hit(ph):
				var hy := (ph["position"] as Vector3).y
				if hy > cam.y + 1.0 and (lowest < 0.0 or hy < lowest):
					lowest = hy
	if lowest > 0.0:
		# Spawn at least a little below the roof underside (wind slant + margin).
		_box_top = clampf(lowest - 0.35 - global_position.y, 1.2, rain_area_size.y * 0.5)
	return false

func _apply_cover_mode() -> void:
	if _rain_process_mat == null or _particles == null:
		return
	_last_ring_radius = _cover_ring_radius if _covered else -1.0
	if _covered:
		# Covered: emit ONLY in a ring outside the covered footprint, raised
		# above roof level — drops fall onto the roof top and around the
		# shelter (visible at every open side) but never spawn under the roof,
		# so nothing can appear indoors.
		_rain_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		_rain_process_mat.emission_ring_axis = Vector3.UP
		_rain_process_mat.emission_ring_height = 0.4
		_rain_process_mat.emission_ring_radius = _cover_ring_radius
		_rain_process_mat.emission_ring_inner_radius = _cover_ring_radius + 2.8
		var ring_particle_amount: int = mini(particle_amount + 500, particle_amount * 2)
		if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
			ring_particle_amount = particle_amount
		_particles.amount = ring_particle_amount
		_particles.position = Vector3(0.0, RING_SPAWN_ABOVE_CAMERA, 0.0)
	else:
		# Outdoors: full box around the camera, with the top capped just below
		# any nearby roof underside (_box_top == full height when no building
		# is close). Offsetting the node keeps the box's bottom at -8 m while
		# the top sits at _box_top, so rain under open sky is unchanged.
		_rain_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_rain_process_mat.emission_box_extents = Vector3(
			rain_area_size.x * 0.5,
			(_box_top + rain_area_size.y * 0.5) * 0.5,
			rain_area_size.z * 0.5)
		_particles.position = Vector3(0.0, (_box_top - rain_area_size.y * 0.5) * 0.5, 0.0)
		_particles.amount = particle_amount

# ============================================================
# SUBMERGED CAMERA — while the camera is below the wave surface, no rain is
# emitted at all (and splash raycasts are skipped). Hysteresis stops the
# state from flickering while bobbing at the surface.
# ============================================================
func _update_submerged_state() -> void:
	var was := _camera_submerged
	if _camera == null or not is_instance_valid(_camera) \
			or _ocean == null or not is_instance_valid(_ocean):
		_camera_submerged = false
	else:
		var water_y := float(_ocean.call("get_height", _camera.global_position))
		var depth := water_y - _camera.global_position.y
		if _camera_submerged:
			_camera_submerged = depth > -0.05
		else:
			_camera_submerged = depth > 0.12
	# Entering the water: clear already-falling drops so no streak lingers
	# underwater for the tail of their lifetime.
	if _camera_submerged and not was and _particles != null:
		_particles.restart()
		_particles.emitting = false


func _follow_player() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_find_refs()
		return
	global_position = _camera.global_position


func _update_intensity(delta: float) -> void:
	if fade_time <= 0.001:
		_intensity = _target_intensity
	else:
		_intensity = move_toward(_intensity, _target_intensity, delta / fade_time)

	if _rain_mat != null:
		_rain_mat.albedo_color.a = clampf(_intensity * 0.55, 0.0, 0.55)

	if rain_sound != null:
		_audio.volume_db = lerpf(-80.0, -6.0, _intensity)

	if _sky != null and _orig_fog_density >= 0.0:
		_sky.set("fog_density", lerpf(_orig_fog_density, _orig_fog_density + 0.01, _intensity))
	if _env != null and _orig_ambient_energy >= 0.0:
		_env.ambient_light_energy = lerpf(_orig_ambient_energy, _orig_ambient_energy * 0.7, _intensity)
	if _ocean != null and _orig_wave_height >= 0.0:
		_ocean.set("wave_height", lerpf(_orig_wave_height, _orig_wave_height * 1.35, _intensity))

	if _overlay != null:
		_overlay.color.a = clampf(_intensity * 0.08, 0.0, 0.08)

	if _flash != null and _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 2.0, 0.0)


# ============================================================
# IMPACT SPLASHES — periodically raycast down at random points near the
# camera; wherever a drop would land, fire a pooled splash burst. Hits on
# structures (raft/foundation/wall/roof/stairs/door/window, physics layer
# "Structures") get a brighter, faster burst; open water gets a softer one.
# ============================================================
func _process_splashes(delta: float) -> void:
	if not splash_enabled or _splash_pool.is_empty() or not _is_raining \
			or _intensity <= 0.05 or _camera == null:
		return
	if _camera_submerged:
		return  # no splashes while the camera is underwater
	# Never catch up a backlog of raycasts after a slow frame or app resume.
	# A single splash per rendered frame is visually enough and puts a hard cap
	# on the worst-case work this cosmetic effect can trigger.
	_splash_accum = minf(_splash_accum + delta * splashes_per_second * _intensity, 1.0)
	if _splash_accum >= 1.0:
		_splash_accum -= 1.0
		_spawn_one_splash()


func _spawn_one_splash() -> void:
	var cam_pos := _camera.global_position
	# Bias sample points into the camera's forward cone — the raft/roof/surface
	# fill the middle of the screen, so most rain should visibly pound those
	# surfaces; the remaining samples scatter wider for ambient rain everywhere.
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	var fwd_n := fwd.normalized()
	var right := Vector3(-fwd_n.z, 0.0, fwd_n.x)
	var x: float
	var z: float
	if fwd_n.length() > 0.01 and randf() < forward_bias:
		var f_dist := sqrt(randf()) * forward_cone_radius
		var f_angle := randf_range(-1.0, 1.0)  # ~ +-57 degrees wide
		x = cam_pos.x + fwd_n.x * f_dist + right.x * f_angle * f_dist
		z = cam_pos.z + fwd_n.z * f_dist + right.z * f_angle * f_dist
	else:
		var angle := randf() * TAU
		var dist := sqrt(randf()) * splash_scan_radius
		x = cam_pos.x + cos(angle) * dist
		z = cam_pos.z + sin(angle) * dist

	var space_state := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, cam_pos.y + 14.0, z),
		Vector3(x, cam_pos.y - 20.0, z))
	# Layer 1 = Structures (raft, foundations, walls, roofs, stairs, doors,
	# windows) per the project's physics layer map — never debris (layer 2).
	q.collision_mask = 1
	var hit := space_state.intersect_ray(q)

	if hit:
		_fire_splash(hit.position, true)
		return

	if water_splash_enabled and _ocean != null:
		var water_y := float(_ocean.call("get_height", Vector3(x, 0.0, z)))
		_fire_splash(Vector3(x, water_y, z), false)


func _fire_splash(pos: Vector3, on_structure: bool) -> void:
	if _splash_pool.is_empty():
		return
	var p: GPUParticles3D = _splash_pool[_splash_index]
	_splash_index = (_splash_index + 1) % _splash_pool.size()
	p.global_position = pos + Vector3(0, 0.02, 0)
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		if on_structure:
			# Rain pounding wood/roof reads better with a slightly stronger,
			# denser burst — this is the "drop hitting the surface" moment.
			pm.initial_velocity_min = 1.4
			pm.initial_velocity_max = 2.8
			p.amount = splash_particle_count + 2
		else:
			# Softer, sparser ripple on open water — rain already animates
			# the ocean surface, this is just a subtle accent.
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 1.0
			p.amount = maxi(splash_particle_count >> 1, 3)
	p.restart()
	p.emitting = true


func _maybe_lightning() -> void:
	if not _is_raining or not enable_lightning:
		return
	if randf() > lightning_chance_per_check:
		return
	if _flash != null:
		_flash.color.a = 0.5
	if thunder_sounds.size() > 0:
		_thunder_audio.stream = thunder_sounds.pick_random()
		_thunder_audio.volume_db = randf_range(-6.0, 2.0)
		await get_tree().create_timer(randf_range(0.3, 1.4)).timeout
		_thunder_audio.play()


# ============================================================
# DEV DEBUG KEY — F11 instantly toggles rain on/off for testing.
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		if _is_raining:
			stop_rain()
		else:
			start_rain(120.0)
