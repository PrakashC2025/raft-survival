extends Node3D
## Extends Sky3D's existing celestial/sky/ocean system instead of running a second
## clock. Low-frequency palette updates and bounded GPU effects respect profiles.
var _sky: WorldEnvironment
var _clock: Node
var _fireflies: Array[GPUParticles3D] = []
var _sample := 0.0
static var _occluders: Dictionary = {}
const EVENING_PANORAMA: Texture2D = preload("res://textures/sky/golden_evening_v1.png")
const NIGHT_CLOUDS: Texture2D = preload("res://textures/sky/moonlit_clouds_v1.png")
const MORNING_PANORAMA: Texture2D = preload("res://textures/sky/peach_morning_v1.png")
const AFTERNOON_PANORAMA: Texture2D = preload("res://textures/sky/blue_afternoon_v1.png")

static func evening_strength(hour: float, sun_height: float) -> float:
	# Warm clouds approach sunset and disappear into the existing moonlit sky.
	# The astronomical sun controls the fade; dawn retains its current look.
	if hour < 12.0: return 0.0
	return (1.0 - smoothstep(0.06, 0.36, sun_height)) * smoothstep(-0.40, -0.16, sun_height)

const SKY_DAYS := [
	{"day":Color(.79,.91,1),"horizon":Color(1,.66,.44),"cirrus":.22,"cloud":.32,"size":.8},
	{"day":Color(.85,.94,1),"horizon":Color(1,.72,.53),"cirrus":.52,"cloud":.44,"size":1.35},
	{"day":Color(.76,.89,1),"horizon":Color(.98,.58,.41),"cirrus":.34,"cloud":.57,"size":1.05},
	{"day":Color(.92,.94,.98),"horizon":Color(.94,.76,.64),"cirrus":.63,"cloud":.68,"size":1.6},
	{"day":Color(.82,.91,.98),"horizon":Color(1,.76,.48),"cirrus":.41,"cloud":.38,"size":.95}]

static func sky_profile_for_day(date: int) -> Dictionary:
	# Adjacent dates always differ; longer seasons vary their order. No save RNG.
	var index:=posmod(date+floori(float(date)/5.0)*2,SKY_DAYS.size())
	return SKY_DAYS[index].duplicate()

func _daily_sky(hour: float) -> void:
	var date:=floori(Time.get_unix_time_from_datetime_dict({"year":int(_clock.get("year")),"month":int(_clock.get("month")),"day":int(_clock.get("day")),"hour":0,"minute":0,"second":0})/86400.0)
	var previous:=sky_profile_for_day(date-1);var today:=sky_profile_for_day(date)
	var blend:=smoothstep(0,2,hour)
	var dome:=_sky.get_node("SkyDome")
	dome.set("atm_day_tint",Color(previous.day).lerp(today.day,blend))
	dome.set("atm_horizon_light_tint",Color(previous.horizon).lerp(today.horizon,blend))
	dome.set("cirrus_coverage",lerpf(previous.cirrus,today.cirrus,blend))
	dome.set("cumulus_coverage",lerpf(previous.cloud,today.cloud,blend))
	dome.set("cirrus_size",lerpf(previous.size,today.size,blend))
	var clouds:=lerpf(previous.cloud,today.cloud,blend)
	dome.set("atm_night_tint",Color(.032,.047,.080,.23).lerp(Color(.044,.052,.076,.28),clouds))

func _ready() -> void:
	_sky = get_parent().get_node("Sky3D")
	_clock = _sky.get_node("TimeOfDay")
	# Keep the existing astronomical sun/calendar, but give every dark night a
	# visible moon. A real lunar orbit can put it below the horizon/new moon.
	_clock.set("compute_moon_coords", false)
	_clock.get_node("Timer").timeout.connect(_update_night_moon)
	var dome := _sky.get_node("SkyDome")
	dome.set("moon_size", 0.045)
	dome.set("panorama_clouds_enabled", true)
	dome.set("star_field_color", Color(1.12, 1.20, 1.35))
	dome.set("starmap_color", Color(0.74, 0.80, 0.95, 0.92))
	dome.set("star_scintillation", 0.28)
	dome.set("star_scintillation_speed", 0.006)
	var material: ShaderMaterial = dome.get("sky_material")
	material.set_shader_parameter("evening_panorama", EVENING_PANORAMA)
	material.set_shader_parameter("night_clouds", NIGHT_CLOUDS)
	material.set_shader_parameter("night_cloud_opacity", 0.35)
	material.set_shader_parameter("night_cloud_coverage", 0.35)
	material.set_shader_parameter("morning_panorama", MORNING_PANORAMA)
	material.set_shader_parameter("afternoon_panorama", AFTERNOON_PANORAMA)
	material.set_shader_parameter("calm_night_enabled", true)
	material.set_shader_parameter("moon_intensity", 0.85)
	material.set_shader_parameter("moon_glow_intensity", 0.40)
	_update_night_moon()
	GameSettings.changed.connect(_quality_changed)
	_quality_changed()
	call_deferred("_setup_island_effects")

func _update_night_moon() -> void:
	var dome := _sky.get_node("SkyDome")
	var sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin.normalized()
	# A steady clock-based orbit avoids the rapid azimuth reversal caused by
	# projecting the sun near the nadir. The same interpolated clock drives both.
	# Keep the moon 14–46 degrees above the horizon and visible from the raft.
	var elevation := clampf(-sun.y, 0.24, 0.72)
	var hour: float = _clock.call("get_render_time")
	dome.set("moon_azimuth", hour / 24.0 * TAU - PI * 0.5)
	dome.set("moon_altitude", acos(elevation))
	var material: ShaderMaterial = dome.get("sky_material")
	material.set_shader_parameter("night_moon_visibility", 1.0 - smoothstep(-0.16, -0.025, sun.y))

static func particles(amount: int, extent: Vector3, color: Color, size: Vector2, emissive: bool) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = 8.0
	emitter.preprocess = 4.0
	emitter.emitting = false
	emitter.visibility_aabb = AABB(-extent-Vector3.ONE*10,(extent+Vector3.ONE*10)*2)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extent
	process.gravity = Vector3.ZERO
	process.direction = Vector3(1,0.15,0)
	process.spread = 30
	process.initial_velocity_min = 0.06
	process.initial_velocity_max = 0.25
	process.scale_min = 0.7
	process.scale_max = 1.3
	emitter.process_material = process
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		mat.emission_enabled = true
		mat.emission = Color(0.35,0.68,0.17)
		mat.emission_energy_multiplier = 1.2
	quad.material = mat
	emitter.draw_pass_1 = quad
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_range_end = 55
	return emitter

func _quality_changed() -> void:
	_clock.set("minutes_per_day", GameSettings.day_minutes)
	get_viewport().use_occlusion_culling = GameSettings.quality != 1
	var env := _sky.environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	_sky.set("sky_contribution",0.55)
	# Blend the sky with SkyDome's ambient tint for readable shaded timber.
	# A bounded environment map keeps this fill affordable on Mobile.
	var mobile_effects := GameSettings.mobile_effects_profile()
	env.sky.radiance_size = Sky.RADIANCE_SIZE_64 if mobile_effects else Sky.RADIANCE_SIZE_128
	var high_desktop := GameSettings.quality >= 3 and not mobile_effects
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	# These effects require Forward+. Mobile keeps shader AO/analytic reflections
	# without fog on phones. Sea-mist particles are removed on every platform.
	env.ssao_enabled = high_desktop and forward_plus
	env.ssr_enabled = high_desktop and forward_plus
	env.volumetric_fog_enabled = high_desktop and forward_plus
	if env.volumetric_fog_enabled: env.volumetric_fog_density = 0.004
	env.glow_enabled = high_desktop
	env.glow_intensity = 0.2
	env.fog_enabled = not mobile_effects
	if mobile_effects:
		env.fog_density = 0.0
		_sky.set("fog_enabled",false)
		_sky.get_node("SkyDome").set("fog_visible",false)
	env.fog_sky_affect = 0.15
	env.fog_sun_scatter = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	_sample = 1.0

func _setup_island_effects() -> void:
	for island_name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
		var island := get_parent().get_node_or_null(island_name) as Node3D
		if island == null: continue
		var flies := particles(32,Vector3(8,1.5,8),Color(0.55,0.8,0.18,0.7),Vector2(0.035,0.035),true)
		flies.name = "NightFireflies"
		flies.position.y = 2.8
		island.add_child(flies)
		_fireflies.append(flies)
		var ridge := island.get_node_or_null("IslandMountain/CraggyRockMesh") as MeshInstance3D
		if ridge == null or ridge.mesh == null: continue
		# Exact static ridge triangles: no unsafe oversized boxes and no moving
		# raft occluders that would continuously rebuild the occlusion BVH.
		var mesh := ridge.mesh
		if not _occluders.has(mesh):
			var faces := mesh.get_faces()
			var indices := PackedInt32Array()
			for index in faces.size(): indices.append(index)
			var occluder := ArrayOccluder3D.new()
			occluder.set_arrays(faces,indices)
			_occluders[mesh] = occluder
		var instance := OccluderInstance3D.new()
		instance.occluder = _occluders[mesh]
		ridge.add_child(instance)

func _process(delta: float) -> void:
	_update_night_moon()
	var dome := _sky.get_node("SkyDome")
	var sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
	var material: ShaderMaterial = dome.get("sky_material")
	material.set_shader_parameter("evening_blend", evening_strength(_clock.call("get_render_time"), sun.y))
	material.set_shader_parameter("evening_rotation", -atan2(sun.z, sun.x) / TAU)
	material.set_shader_parameter("daylight_panorama_blend", smoothstep(-0.22, 0.02, sun.y))
	material.set_shader_parameter("morning_panorama_blend", 1.0 - smoothstep(0.18, 0.65, sun.y) if _clock.call("get_render_time") < 12.0 else 0.0)
	_sample += delta
	if _sample < 0.5: return
	_sample = 0.0
	var hour: float = _clock.get("current_time")
	_daily_sky(hour)
	var sun_height: float = (_sky.get_node("SkyDome").get("_sun_transform") as Transform3D).origin.y
	var daylight := smoothstep(-0.12,0.25,sun_height)
	preload("res://scripts/resource_visual.gd").set_night_readability(1.0-daylight)
	var night := sun_height < -0.12
	var dawn := hour >= 5 and hour < 8
	var dusk := hour >= 17 and hour < 19
	var env := _sky.environment
	var mobile_effects := GameSettings.mobile_effects_profile()
	if mobile_effects:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		_sky.set("fog_enabled",false)
		_sky.get_node("SkyDome").set("fog_visible",false)
	env.fog_density = 0.0 if mobile_effects else (0.0015 if night else (0.001 if dawn else 0.00055))
	env.fog_light_color = Color("192b44") if night else (Color("a88672") if dawn or dusk else Color("91b9ca"))
	# Match the celestial light continuously, including restored calendar dates.
	# Hour thresholds caused a visible brightness jump before sunrise/sunset.
	env.ambient_light_energy = lerpf(0.52,0.62,daylight)
	var fill := _sky.get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		# Broad sky bounce: diffuse only, so sunlight still owns water/wood glints.
		# Shadowless moon/sky bounce keeps salvage readable from every direction.
		fill.light_energy = lerpf(0.35,0.32,daylight)
	var camera := get_viewport().get_camera_3d()
	for flies in _fireflies:
		var nearby := camera != null and flies.global_position.distance_squared_to(camera.global_position) < 55*55
		flies.emitting = night and nearby and GameSettings.quality != 1
		flies.visible = flies.emitting
