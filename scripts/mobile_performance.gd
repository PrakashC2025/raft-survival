extends Node
## Mobile quality profiles and adaptive resolution.
## Auto starts at a modest 3D resolution, reduces it under sustained slow frames,
## and recovers quality when there is headroom. The 30/60 FPS setting determines
## the frame budget. Canvas rendering remains clear at every quality level.

const MIN_RENDER_SCALE := 0.55
const MAX_RENDER_SCALE := 1.0
const SCALE_STEP_DOWN := 0.08
const SCALE_STEP_UP := 0.04
const SAMPLE_WINDOW_SECONDS := 1.25
const SLOW_WINDOWS_BEFORE_SCALE := 2
const FAST_WINDOWS_BEFORE_RECOVERY := 5

var _mobile := false
var _viewport: Viewport
var _can_scale_3d := false
var _render_scale := MAX_RENDER_SCALE
var _sky_material: ShaderMaterial
var _cumulus_reduced := false
var _sample_seconds := 0.0
var _frame_seconds := 0.0
var _frame_count := 0
var _slow_windows := 0
var _fast_windows := 0
var _last_quality := -1
var _last_fps := -1
var _foliage_reduced := false


func _ready() -> void:
	add_to_group("mobile_performance")
	_mobile = GameSettings.mobile_effects_profile()

	# A 60 FPS ceiling avoids running phones at 90/120 Hz when the game cannot
	# usefully present extra frames, reducing heat and performance throttling.
	Engine.max_fps = GameSettings.target_fps
	# A 30 FPS phone must not simulate the full world twice for every frame.
	# All movement/buoyancy use delta; 60 FPS and desktop retain 60 Hz physics.
	Engine.physics_ticks_per_second = 30 if _mobile and GameSettings.target_fps == 30 else 60
	_viewport = get_viewport()
	_can_scale_3d = _has_viewport_property("scaling_3d_scale")
	if _can_scale_3d:
		_render_scale = clampf(
			float(_viewport.get("scaling_3d_scale")), MIN_RENDER_SCALE, MAX_RENDER_SCALE)
		_viewport.set("scaling_3d_scale", _render_scale)

	# current_scene is assigned after the children enter the tree.
	call_deferred("_apply_profile")
	GameSettings.changed.connect(_apply_profile)
	set_process(_mobile and GameSettings.quality == 0)


func _apply_profile() -> void:
	_cache_sky_material()
	Engine.max_fps = GameSettings.target_fps
	Engine.physics_ticks_per_second = 30 if _mobile and GameSettings.target_fps == 30 else 60
	if _last_quality == GameSettings.quality and _last_fps == GameSettings.target_fps:
		return
	_last_quality = GameSettings.quality
	_last_fps = GameSettings.target_fps
	_foliage_reduced = false
	refresh_foliage()
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if GameSettings.quality == 1 or (_mobile and GameSettings.quality == 0) else Viewport.MSAA_2X
	_sample_seconds = 0.0
	_frame_seconds = 0.0
	_frame_count = 0
	_slow_windows = 0
	_fast_windows = 0
	set_process(_mobile and GameSettings.quality == 0)
	if not _mobile and GameSettings.quality == 0:
		_set_render_scale(1.0)
		_set_cumulus_visible(true)
		return
	var initial_scale: float = [0.72, 0.65, 0.82, 1.0][GameSettings.quality]
	_set_render_scale(initial_scale)
	_set_cumulus_visible(GameSettings.quality == 3)
	_limit_mobile_shadow_distance()
	var scene := get_tree().current_scene
	if scene != null:
		var ocean := get_tree().get_first_node_in_group("ocean") as MeshInstance3D
		if ocean != null:
			var water_material := ocean.get_active_material(0) as ShaderMaterial
			if water_material != null:
				water_material.set_shader_parameter("surface_detail", 0.45 if GameSettings.quality == 1 else 1.0)
		var environment_node := scene.get_node_or_null("Sky3D") as WorldEnvironment
		if environment_node != null and environment_node.environment != null and _mobile:
			environment_node.environment.glow_enabled = false


func _process(delta: float) -> void:
	_sample_seconds += delta
	_frame_seconds += delta
	_frame_count += 1
	if _sample_seconds < SAMPLE_WINDOW_SECONDS:
		return

	var avg_frame_seconds := _frame_seconds / float(maxi(_frame_count, 1))
	_sample_seconds = 0.0
	_frame_seconds = 0.0
	_frame_count = 0
	_update_quality(avg_frame_seconds)


func _update_quality(avg_frame_seconds: float) -> void:
	var frame_budget := 1.0 / float(GameSettings.target_fps)
	if avg_frame_seconds >= frame_budget * 1.58 \
			and _sky_material != null and not _cumulus_reduced:
		# A severe slowdown is usually fill-rate bound on a phone. Skip only the
		# 10-step volumetric cloud march; the atmospheric sky and cirrus remain.
		_set_cumulus_visible(false)
		_slow_windows = 0
		_fast_windows = 0
		return

	if avg_frame_seconds > frame_budget * 1.25:
		_slow_windows += 1
		_fast_windows = 0
		if _slow_windows >= SLOW_WINDOWS_BEFORE_SCALE:
			if _render_scale <= 0.66 and not _foliage_reduced:
				_foliage_reduced = true
				refresh_foliage()
			if _can_scale_3d and _render_scale > MIN_RENDER_SCALE:
				_set_render_scale(_render_scale - SCALE_STEP_DOWN)
			elif not _cumulus_reduced:
				_set_cumulus_visible(false)
			_slow_windows = 0
		return

	_slow_windows = 0
	if avg_frame_seconds < frame_budget * 1.035:
		_fast_windows += 1
		if _fast_windows >= FAST_WINDOWS_BEFORE_RECOVERY:
			if _foliage_reduced and _render_scale >= 0.78:
				_foliage_reduced = false
				refresh_foliage()
			# Restore resolution slowly. Mobile Auto keeps volumetric clouds off;
			# only the explicitly selected High profile enables that expensive pass.
			if _can_scale_3d and _render_scale < MAX_RENDER_SCALE:
				_set_render_scale(_render_scale + SCALE_STEP_UP)
			elif _cumulus_reduced and (not _mobile or GameSettings.quality == 3):
				_set_cumulus_visible(true)
			_fast_windows = 0
	else:
		_fast_windows = 0


func _has_viewport_property(property_name: String) -> bool:
	for property_info in _viewport.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func refresh_foliage() -> void:
	for node in get_tree().get_nodes_in_group("island_landscape_foliage"):
		var batch := node as MultiMeshInstance3D
		if batch == null or batch.multimesh == null: continue
		var fraction: float = [1.0, 0.50, 0.75, 1.0][GameSettings.quality]
		if _foliage_reduced: fraction *= 0.65
		# Harvestable plants must remain visible wherever their interaction bodies exist.
		if batch.get_meta("interactive_foliage",false): fraction = 1.0
		batch.multimesh.visible_instance_count = maxi(1, floori(batch.multimesh.instance_count * fraction))
		batch.visibility_range_end = 55.0 if GameSettings.quality == 1 else 110.0
	if not _mobile:
		return
	var quality := GameSettings.quality
	var budget: int = [1600, 800, 1600, 2400][quality]
	if _foliage_reduced:
		budget = int(budget * 0.65)
	for node in get_tree().get_nodes_in_group("island_grass_field"):
		var field := node as MultiMeshInstance3D
		if field == null or field.multimesh == null:
			continue
		field.multimesh.visible_instance_count = mini(field.multimesh.instance_count, budget)
		field.visibility_range_end = 55.0 if quality == 1 else 100.0


func _set_render_scale(value: float) -> void:
	if not _can_scale_3d:
		return
	_render_scale = clampf(value, MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	_viewport.set("scaling_3d_scale", _render_scale)


func _cache_sky_material() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var world_environment := scene.get_node_or_null("Sky3D") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var sky := world_environment.environment.sky
	if sky != null:
		_sky_material = sky.sky_material as ShaderMaterial


func _set_cumulus_visible(visible: bool) -> void:
	if _sky_material == null:
		return
	_sky_material.set_shader_parameter("cumulus_visible", visible)
	_cumulus_reduced = not visible


func _limit_mobile_shadow_distance() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light.shadow_enabled:
			light.directional_shadow_max_distance = [60.0, 35.0, 60.0, 90.0][GameSettings.quality]
