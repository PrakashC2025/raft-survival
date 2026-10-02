extends Node
## Mobile runtime quality governor.
## Keeps the native render scale and full sky quality whenever the device has
## headroom; if sustained frame times fall behind, it gradually lowers only
## the 3D render scale and then skips the expensive volumetric cumulus pass.
## HUD/canvas rendering remains native resolution throughout.

const MOBILE_TARGET_FPS := 60
const MIN_RENDER_SCALE := 0.70
const MAX_RENDER_SCALE := 1.0
const SCALE_STEP_DOWN := 0.08
const SCALE_STEP_UP := 0.04
const SAMPLE_WINDOW_SECONDS := 1.25
const SLOW_FRAME_SECONDS := 1.0 / 48.0
const VERY_SLOW_FRAME_SECONDS := 1.0 / 38.0
const FAST_FRAME_SECONDS := 1.0 / 58.0
const SLOW_WINDOWS_BEFORE_SCALE := 2
const FAST_WINDOWS_BEFORE_RECOVERY := 5
const MOBILE_SHADOW_DISTANCE := 90.0

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


func _ready() -> void:
	_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	if not _mobile:
		set_process(false)
		return

	# A 60 FPS ceiling avoids running phones at 90/120 Hz when the game cannot
	# usefully present extra frames, reducing heat and performance throttling.
	Engine.max_fps = MOBILE_TARGET_FPS
	_viewport = get_viewport()
	_can_scale_3d = _has_viewport_property("scaling_3d_scale")
	if _can_scale_3d:
		_render_scale = clampf(
			float(_viewport.get("scaling_3d_scale")), MIN_RENDER_SCALE, MAX_RENDER_SCALE)
		_viewport.set("scaling_3d_scale", _render_scale)

	_cache_sky_material()
	_limit_mobile_shadow_distance()


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
	if avg_frame_seconds >= VERY_SLOW_FRAME_SECONDS \
			and _sky_material != null and not _cumulus_reduced:
		# A severe slowdown is usually fill-rate bound on a phone. Skip only the
		# 10-step volumetric cloud march; the atmospheric sky and cirrus remain.
		_set_cumulus_visible(false)
		_slow_windows = 0
		_fast_windows = 0
		return

	if avg_frame_seconds > SLOW_FRAME_SECONDS:
		_slow_windows += 1
		_fast_windows = 0
		if _slow_windows >= SLOW_WINDOWS_BEFORE_SCALE:
			if _can_scale_3d and _render_scale > MIN_RENDER_SCALE:
				_set_render_scale(_render_scale - SCALE_STEP_DOWN)
			elif not _cumulus_reduced:
				_set_cumulus_visible(false)
			_slow_windows = 0
		return

	_slow_windows = 0
	if avg_frame_seconds < FAST_FRAME_SECONDS:
		_fast_windows += 1
		if _fast_windows >= FAST_WINDOWS_BEFORE_RECOVERY:
			# Restore visual quality slowly to avoid oscillating on borderline
			# hardware. High-end phones keep the full clouds and native scale.
			if _cumulus_reduced:
				_set_cumulus_visible(true)
			elif _can_scale_3d and _render_scale < MAX_RENDER_SCALE:
				_set_render_scale(_render_scale + SCALE_STEP_UP)
			_fast_windows = 0
	else:
		_fast_windows = 0


func _has_viewport_property(property_name: String) -> bool:
	for property_info in _viewport.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


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
			light.directional_shadow_max_distance = minf(
				light.directional_shadow_max_distance,
				MOBILE_SHADOW_DISTANCE)
