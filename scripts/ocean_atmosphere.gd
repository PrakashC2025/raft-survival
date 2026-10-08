extends Node3D
## Extends Sky3D's existing celestial/sky/ocean system instead of running a second
## clock. Low-frequency palette updates and bounded GPU effects respect profiles.
var _sky: WorldEnvironment
var _clock: Node
var _mist: GPUParticles3D
var _fireflies: Array[GPUParticles3D] = []
var _sample := 0.0
static var _occluders: Dictionary = {}

func _ready() -> void:
	_sky = get_parent().get_node("Sky3D")
	_clock = _sky.get_node("TimeOfDay")
	if not GameSettings.mobile_effects_profile():
		_mist = particles(12, Vector3(14,0.1,14), Color(0.72,0.81,0.84,0.035), Vector2(8,1.2), false)
		_mist.name = "MorningSeaMist"
		add_child(_mist)
	GameSettings.changed.connect(_quality_changed)
	_quality_changed()
	call_deferred("_setup_island_effects")

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
	var high_desktop := GameSettings.quality == 3 and not mobile_effects
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	# These effects require Forward+. Mobile keeps shader AO/analytic reflections
	# without fog or the rectangular sea-mist particles on phones.
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
	for name in ["Island","ReefIsle","DriftwoodCay","FarCove"]:
		var island := get_parent().get_node_or_null(name) as Node3D
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
	_sample += delta
	if _sample < 0.5: return
	_sample = 0.0
	var hour: float = _clock.get("current_time")
	var night := hour < 5.5 or hour > 18.5
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
	env.ambient_light_energy = 0.35 if night else (0.48 if dawn or dusk else 0.62)
	var fill := _sky.get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		# Broad sky bounce: diffuse only, so sunlight still owns water/wood glints.
		fill.light_energy = 0.035 if night else (0.20 if dawn or dusk else 0.40)
	var camera := get_viewport().get_camera_3d()
	if _mist != null:
		if camera != null: _mist.global_position = Vector3(camera.global_position.x,0.9,camera.global_position.z)
		_mist.emitting = dawn and GameSettings.quality != 1 and not mobile_effects
		_mist.visible = _mist.emitting
	for flies in _fireflies:
		var nearby := camera != null and flies.global_position.distance_squared_to(camera.global_position) < 55*55
		flies.emitting = night and nearby and GameSettings.quality != 1
		flies.visible = flies.emitting
