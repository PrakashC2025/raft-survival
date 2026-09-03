extends MeshInstance3D
class_name Ocean

# ============================================================
# OCEAN — day/night driver
# Reads the Sky3D sun/moon state each frame and pushes
# time-of-day uniforms to the ocean shader (main.gdshader).
# get_height() (buoyancy/waves/collision) is unchanged.
# ============================================================

# --- Time-of-day water palette (tune in the inspector) ---
# TRUE LINEAR HDR colors — the shader uniforms are deliberately NOT
# source_color (that hint silently converts pushed colors sRGB->linear and
# darkens the water ~3x). The scene uses ACES tonemapping (mode 3). Tuned so
# the final displayed ocean is a bright Raft-style blue:
#   day (0.05, 0.18, 0.40) -> ~sRGB (0.23, 0.55, 0.76)
#   night (0.012, 0.04, 0.12) -> ~sRGB (0.06, 0.20, 0.44) navy
# (verified empirically against the real ACES+sRGB pipeline).
@export var day_color := Color(0.05, 0.22, 0.46)
@export var twilight_color := Color(0.06, 0.07, 0.22)
@export var night_color := Color(0.012, 0.04, 0.12)
@export var sparkle_strength := 1.0

# Dev-only time keys. F3 is the build overlay, so the debug keys use F5-F9.
@export var dev_time_keys := true

@export var wave_height := 0.4
@export var wave_speed := 1.2
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

func _ready() -> void:
	# Groups work across scene-file boundaries (unlike %UniqueName), so any
	# runtime-instanced node (debris, etc.) can always find this node.
	add_to_group("ocean")
	var scene := get_tree().current_scene
	if scene != null:
		_sky3d = scene.get_node_or_null("Sky3D")
	if _sky3d == null:
		_sky3d = get_node_or_null("../../Sky3D")
	if _sky3d != null:
		_sky = _sky3d.get("sky") as Node  # SkyDome node
		_sun_light = _sky3d.get_node_or_null("SunLight") as DirectionalLight3D
		_moon_light = _sky3d.get_node_or_null("MoonLight") as DirectionalLight3D
		_env = _sky3d.get("environment") as Environment
	if mesh is PlaneMesh:
		_mat = (mesh as PlaneMesh).material as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter("water_day_color", day_color)
		_mat.set_shader_parameter("water_twilight_color", twilight_color)
		_mat.set_shader_parameter("water_night_color", night_color)
		_mat.set_shader_parameter("sparkle_strength", sparkle_strength)
		# Keep the visual waves and the buoyancy sample (get_height below) on the
		# same amplitude so the raft rides the visible waves instead of shaking
		# against them.
		_mat.set_shader_parameter("wave_height", wave_height)
		_mat.set_shader_parameter("wave_speed", wave_speed)
		_push_factors(0.0, 0.0, 0.0)

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
			KEY_F5:
				_force_time(12.0)
			KEY_F6:
				_force_time(18.6)
			KEY_F7:
				_force_time(0.4)
			KEY_F8:
				_force_time(6.4)
			KEY_F9:
				_show_debug = not _show_debug
				_ensure_debug_label()
				if _label != null:
					_label.visible = _show_debug

# Dev shortcut: jump straight to a time of day (Sky3D -> TimeOfDay recomputes
# the sun/moon coords immediately).
func _force_time(hour: float) -> void:
	_sky3d.set("current_time", hour)

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

# Returns the exact water surface height (world Y) at any given world position.
func get_height(world_pos: Vector3) -> float:
	var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
		+ sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
		+ 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
	return global_position.y + h * wave_height * 0.33
