extends MeshInstance3D
class_name Ocean

# ============================================================
# OCEAN — day/night driver
# Reads the Sky3D SkyDome's sun/moon state each frame and pushes
# time-of-day uniforms to the ocean shader (main.gdshader).
# get_height() MUST mirror the shader's vertex wave formula exactly
# (see _WAVES below) so buoyancy matches the visible waves.
# ============================================================

# --- Time-of-day water palette (tune in the inspector) ---
# TRUE LINEAR HDR colors — the shader uniforms are deliberately NOT
# source_color (that hint silently converts pushed colors sRGB->linear and
# darkens the water ~3x). The scene uses ACES tonemapping (mode 3, white 6.0).
# Calibrated for a VIVID realistic blue: rich cobalt body at the horizon,
# deep navy in the foreground/troughs, saturated blue-cyan crests:
#   day (0.035, 0.28, 0.58)     -> deep cobalt mid sea
#   horizon (0.04, 0.45, 0.72)  -> bright azure toward the horizon
#   deep (0.012, 0.10, 0.22)    -> near-black navy foreground/troughs
#   night (0.018, 0.07, 0.17)   -> blue navy, alive under the moon
@export var day_color := Color(0.016, 0.13, 0.24)
@export var twilight_color := Color(0.04, 0.11, 0.22)
@export var night_color := Color(0.012, 0.05, 0.12)
@export var deep_color := Color(0.006, 0.05, 0.11)
@export var horizon_color := Color(0.02, 0.22, 0.34)
@export var crest_color := Color(0.10, 0.34, 0.46)
@export var foam_color := Color(1.15, 1.25, 1.42)
@export var haze_color := Color(0.45, 0.6, 0.75)
@export var sparkle_strength := 0.6

# Optional editor-only time shortcuts. F5 is reserved for the player's quick-save.
@export var dev_time_keys := false

# --- Underwater veil (display-space 2D colors) ---
@export_range(0.0, 1.2) var under_alpha_max := 0.78
@export var under_top_color := Color(0.05, 0.25, 0.40)
@export var under_bottom_color := Color(0.008, 0.045, 0.12)

var _under_layer: CanvasLayer = null
var _under_rect: ColorRect = null
var _under_mat: ShaderMaterial = null

@export var wave_height := 0.42
@export var wave_speed := 0.45
var _time := 0.0

var _sky3d: Node = null
var _sky: Node = null
var _mat: ShaderMaterial = null
var _sun_light: DirectionalLight3D = null
var _moon_light: DirectionalLight3D = null
var _env: Environment = null

# Debug HUD
var _label: Label = null
var _show_debug := false
var _last_night := 0.0
var _last_twilight := 0.0
var _last_moon := 0.0
var _sun_elev := 1.0
var _moon_elev := -1.0

const _UNDER_SHADER := """
shader_type canvas_item;
uniform vec4 top_col : source_color;
uniform vec4 bottom_col : source_color;
void fragment() {
	COLOR = mix(bottom_col, top_col, UV.y);
}
"""

func _ready() -> void:
	# The broad, slow ocean swells do not need a 160x160 grid on a phone.
	# Keep enough tessellation for a smooth silhouette while cutting roughly
	# a third of the per-vertex wave work and triangle count.
	if (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")) \
			and mesh is PlaneMesh:
		var plane := mesh as PlaneMesh
		plane.subdivide_width = mini(plane.subdivide_width, 128)
		plane.subdivide_depth = mini(plane.subdivide_depth, 128)
	# Groups work across scene-file boundaries (unlike %UniqueName), so any
	# runtime-instanced node (debris, etc.) can always find this node.
	add_to_group("ocean")
	var scene := get_tree().current_scene
	if scene != null:
		_sky3d = scene.get_node_or_null("Sky3D")
	if _sky3d == null:
		_sky3d = get_node_or_null("../../Sky3D")
	if _sky3d != null:
		# The SkyDome child carries the live sun/moon transforms the addon
		# recomputes each time tick. (Reading it by node path, not the "sky"
		# property — that property is not bound in this scene and was silently
		# null, which froze the water at day colors forever.)
		_sky = _sky3d.get_node_or_null("SkyDome") as Node
		if _sky == null:
			_sky = _sky3d.get("sky") as Node
		_sun_light = _sky3d.get_node_or_null("SunLight") as DirectionalLight3D
		_moon_light = _sky3d.get_node_or_null("MoonLight") as DirectionalLight3D
		_env = _sky3d.get("environment") as Environment
	if mesh is PlaneMesh:
		_mat = (mesh as PlaneMesh).material as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter("water_day_color", day_color)
		_mat.set_shader_parameter("water_twilight_color", twilight_color)
		_mat.set_shader_parameter("water_night_color", night_color)
		_mat.set_shader_parameter("water_deep_color", deep_color)
		_mat.set_shader_parameter("water_horizon_color", horizon_color)
		_mat.set_shader_parameter("water_crest_color", crest_color)
		_mat.set_shader_parameter("water_foam_color", foam_color)
		_mat.set_shader_parameter("water_haze_color", haze_color)
		_mat.set_shader_parameter("sparkle_strength", sparkle_strength)
		# Keep the visual waves and the buoyancy sample (get_height below) on the
		# same amplitude so the raft rides the visible waves instead of shaking
		# against them.
		_mat.set_shader_parameter("wave_height", wave_height)
		_mat.set_shader_parameter("wave_speed", wave_speed)
		_push_factors(0.0, 0.0, 0.0)
	_create_far_water()

func _process(delta: float) -> void:
	_time += delta
	if _mat == null or _sky == null:
		return
	# Smooth factors from the SkyDome's own sun/moon directions (origin.y is
	# +1 at zenith / -1 at nadir in world space — the same value the addon uses
	# to fade its lights). Continuous curves, no hard day/night switch.
	var sun_y := 1.0
	var moon_y := -1.0
	var st := _sky.get("_sun_transform") as Transform3D
	if st != null:
		sun_y = st.origin.y
	var mt := _sky.get("_moon_transform") as Transform3D
	if mt != null:
		moon_y = mt.origin.y
	_sun_elev = sun_y
	_moon_elev = moon_y
	var night := clampf((-sun_y - 0.02) / 0.25, 0.0, 1.0)
	var twilight := clampf(1.0 - absf(sun_y) / 0.22, 0.0, 1.0)
	var moon_up := clampf(moon_y / 0.1, 0.0, 1.0)
	var moon_factor := night * moon_up
	_push_factors(night, twilight, moon_factor)
	_update_debug_hud(night, twilight, moon_factor)
	_update_underwater()

func _create_far_water() -> void:
	if _mat == null or not (mesh is PlaneMesh):
		return
	# Four broad strips fill the horizon beyond the playable, detailed plane.
	# They have a hole in the center: no full-screen overlapping water pass.
	var inner := (mesh as PlaneMesh).size * 0.5
	var extent := 12000.0
	var corners: Array[Vector3] = [Vector3(-inner.x, 0, -inner.y), Vector3(inner.x, 0, -inner.y),
		Vector3(inner.x, 0, inner.y), Vector3(-inner.x, 0, inner.y)]
	var outer: Array[Vector3] = [Vector3(-extent, 0, -extent), Vector3(extent, 0, -extent),
		Vector3(extent, 0, extent), Vector3(-extent, 0, extent)]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(4):
		var next := (edge + 1) % 4
		var points: Array[Vector3] = [corners[edge], outer[edge], outer[next], corners[edge], outer[next], corners[next]]
		for point in points:
			builder.set_normal(Vector3.UP)
			builder.add_vertex(point)
	var far_water := MeshInstance3D.new()
	far_water.name = "FarWater"
	far_water.mesh = builder.commit()
	far_water.material_override = _mat
	far_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_water)

func _push_factors(night: float, twilight: float, moon_factor: float) -> void:
	_last_night = night
	_last_twilight = twilight
	_last_moon = moon_factor
	_mat.set_shader_parameter("night_factor", night)
	_mat.set_shader_parameter("twilight_factor", twilight)
	_mat.set_shader_parameter("moon_factor", moon_factor)
	if _sun_light != null and is_instance_valid(_sun_light):
		_mat.set_shader_parameter("sun_dir", _sun_light.global_transform.origin.normalized())
		_mat.set_shader_parameter("sun_glint_color", _sun_light.light_color)
	if _moon_light != null and is_instance_valid(_moon_light):
		_mat.set_shader_parameter("moon_dir", _moon_light.global_transform.origin.normalized())
		_mat.set_shader_parameter("moon_glint_color", _moon_light.light_color)

func _unhandled_input(event: InputEvent) -> void:
	if not dev_time_keys or _sky3d == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F6:
				_force_time(12.0)
			KEY_F7:
				_force_time(18.6)
			KEY_F8:
				_force_time(0.4)
			KEY_F9:
				_force_time(6.4)
			KEY_F4:
				_show_debug = not _show_debug
				_ensure_debug_label()
				if _label != null:
					_label.visible = _show_debug

# Dev shortcut: jump straight to a time of day (Sky3D -> TimeOfDay recomputes
# the sun/moon coords immediately).
func _force_time(hour: float) -> void:
	_sky3d.set("current_time", hour)

# ---------------------------------------------------------------- underwater
# Lightweight camera-underwater look: when the view dips below the wave
# surface a blue veil fades in (darker with depth). Pure 2D overlay — no
# gameplay rendering changes — with a smooth cross-fade at the surface.
func _update_underwater() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		if _under_layer != null:
			_under_layer.visible = false
		return
	var water_level := get_height(cam.global_position)
	var depth := water_level - cam.global_position.y
	var amt := clampf(depth / 1.4, 0.0, 1.0)
	amt = amt * amt * (3.0 - 2.0 * amt)  # smoothstep-like ramp
	if amt <= 0.001:
		if _under_layer != null:
			_under_layer.visible = false
		return
	_ensure_underwater()
	_under_layer.visible = true
	var alpha := under_alpha_max * (0.35 + 0.65 * amt)
	var top := Color(under_top_color.r, under_top_color.g, under_top_color.b, alpha)
	var bottom := Color(under_bottom_color.r, under_bottom_color.g, under_bottom_color.b, alpha * 1.15)
	_under_mat.set_shader_parameter("top_col", top)
	_under_mat.set_shader_parameter("bottom_col", bottom)

func _ensure_underwater() -> void:
	if _under_layer != null:
		return
	_under_layer = CanvasLayer.new()
	_under_layer.name = "_OceanUnderwaterVei"
	_under_layer.layer = 90
	_under_layer.visible = false
	add_child(_under_layer)
	_under_mat = ShaderMaterial.new()
	_under_mat.shader = Shader.new()
	_under_mat.shader.code = _UNDER_SHADER
	_under_rect = ColorRect.new()
	_under_rect.material = _under_mat
	_under_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_under_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under_layer.add_child(_under_rect)

func _ensure_debug_label() -> void:
	if _label != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "_OceanDebugUI"
	layer.layer = 20
	add_child(layer)
	_label = Label.new()
	layer.add_child(_label)
	_label.position = Vector2(12.0, 90.0)
	_label.add_theme_font_size_override("font_size", 12)
	_label.modulate = Color(1.0, 1.0, 0.8, 0.95)

func _update_debug_hud(night: float, twilight: float, moon_factor: float) -> void:
	if not _show_debug or _label == null:
		return
	var lines: PackedStringArray = []
	lines.append("Time: %s" % str(_sky3d.get("game_time") if _sky3d else "?"))
	if _sun_light != null:
		lines.append("Sun:   elev=%+.2f  energy=%.2f" % [_sun_elev, _sun_light.light_energy])
	if _moon_light != null:
		lines.append("Moon:  elev=%+.2f  energy=%.2f" % [_moon_elev, _moon_light.light_energy])
	if _env != null:
		lines.append("Ambient: energy=%.2f color=%s" % [_env.ambient_light_energy, _env.ambient_light_color.to_html(false)])
	if _sky != null:
		lines.append("Sky:   exposure=%.2f  fog=%.5f" % [float(_sky.get("exposure")), float(_sky.get("fog_density"))])
	lines.append("Ocean: night=%.2f twilight=%.2f moon=%.2f" % [night, twilight, moon_factor])
	var text := "\n".join(lines)
	if text != _label.text:
		_label.text = text

# Wave-field constants. MUST stay identical to main.gdshader's vertex wave
# formula (same dirs/freqs/amps/speeds) so buoyancy matches the visible waves.
# Tuned for a SMOOTH sea: two long rolling swells dominate, fine chop is tiny.
const _WAVES := [
	[Vector2(1.0, 0.15), 0.055, 1.0, 0.45],
	[Vector2(-0.4, 0.92), 0.115, 0.75, 0.7],
	[Vector2(0.8, -0.5), 0.24, 0.38, 1.05],
	[Vector2(-0.75, -0.65), 0.50, 0.13, 1.45],
]  # [dir, freq, amp, time_speed]

# Organic-field constants. MUST stay identical to main.gdshader's meander and
# swell-envelope so buoyancy follows the same warped surface (see vertex()).
# Low frequencies = huge slow bending crests; the gentler envelope floor
# (0.75 + 0.25) keeps wave sets arriving evenly — calm, never choppy.
const _M1_DIR := Vector2(0.21, 0.98)
const _M2_DIR := Vector2(0.85, -0.53)
const _M1_F := 0.020
const _M2_F := 0.048
const _M1_S := 0.10
const _M2_S := 0.16
const _M_AMP := 6.0
const _M_AMP2 := 3.2
const _E1_DIR := Vector2(-0.31, 0.95)
const _E2_DIR := Vector2(0.90, -0.44)
const _E1_F := 0.011
const _E2_F := 0.026
const _E1_S := 0.06
const _E2_S := 0.10

# Returns the exact water surface height (world Y) at any given world position.
func get_height(world_pos: Vector3) -> float:
	var p := Vector2(world_pos.x, world_pos.z)
	var tt := _time * wave_speed
	var warp := Vector2(
		_M_AMP * sin(p.dot(_M1_DIR) * _M1_F + tt * _M1_S) + _M_AMP2 * sin(p.dot(_M2_DIR) * _M2_F + tt * _M2_S),
		_M_AMP * sin(p.dot(_M1_DIR) * _M1_F + tt * _M1_S + 2.1) + _M_AMP2 * sin(p.dot(_M2_DIR) * _M2_F + tt * _M2_S + 4.2))
	var pw := p + warp
	var env := 0.75 + 0.25 * sin(pw.dot(_E1_DIR) * _E1_F + tt * _E1_S) * sin(pw.dot(_E2_DIR) * _E2_F + tt * _E2_S)
	var h := 0.0
	for w in _WAVES:
		var d: Vector2 = w[0]
		var f: float = w[1]
		var a: float = w[2]
		var s: float = w[3]
		h += a * sin(pw.dot(d) * f + tt * s)
	h *= env
	return global_position.y + h * wave_height * 0.33
