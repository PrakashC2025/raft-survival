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
#   deep (0.012, 0.10, 0.22)    -> blue navy foreground/troughs
#   night (0.022, 0.078, 0.17)  -> readable navy under the moon
# Compatibility converts these linear values to display space in the shader.
@export var day_color := Color(0.035, 0.28, 0.58)
@export var twilight_color := Color(0.035, 0.16, 0.33)
@export var night_color := Color(0.022, 0.078, 0.17)
@export var deep_color := Color(0.012, 0.10, 0.22)
@export var horizon_color := Color(0.04, 0.45, 0.72)
@export var crest_color := Color(0.10, 0.38, 0.54)
@export var foam_color := Color(1.15, 1.25, 1.42)
@export var haze_color := Color(0.45, 0.6, 0.75)
@export var sparkle_strength := 1.8

# Optional editor-only time shortcuts. F5 is reserved for the player's quick-save.
@export var dev_time_keys := false

# --- Underwater veil (display-space 2D colors) ---
@export_range(0.0, 1.2) var under_alpha_max := 0.34
@export var under_top_color := Color(0.05, 0.25, 0.40)
@export var under_bottom_color := Color(0.008, 0.045, 0.12)

var _under_layer: CanvasLayer = null
var _under_rect: ColorRect = null
var _under_mat: ShaderMaterial = null
var _dive_blend := 0.0
var _diving_background := false
var _surface_background := Environment.BG_SKY
var _surface_background_color := Color.BLACK

@export var wave_height := 0.68
@export var wave_speed := 0.52
var _time := 0.0

var _sky3d: Node = null
var _sky: Node = null
var _mat: ShaderMaterial = null
var _shore_zones := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
static var _wave_normals: NoiseTexture2D
var _raft_ref: Node3D
var _boat_ref: Node3D
var _deck_texture: ImageTexture
var _deck_coverage: Image
var _deck_refresh := 0.0
var _deck_signature := -1

func register_island_shore(island: Node3D, height_texture: Texture2D, extent: float) -> void:
	var index: int = ["Island","ReefIsle","DriftwoodCay","FarCove","VolcanoIsle","WinterIsle","SpringIsle"].find(str(island.name))
	if index < 0 or _mat == null: return
	_shore_zones[index] = Vector4(island.global_position.x, island.global_position.z, extent, extent)
	_mat.set_shader_parameter("island_shores", _shore_zones)
	_mat.set_shader_parameter("shore_height_" + str(index), height_texture)
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

const _UNDER_SHADER := preload("res://shaders/underwater_veil.gdshader")
var _veil_warm_frames := 2

func _ready() -> void:
	# Displaced water must never project a moving wave silhouette onto a deck.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Shader-displaced waves need bounds beyond the flat CPU mesh.
	extra_cull_margin = maxf(extra_cull_margin,absf(wave_height)*0.75+0.05)
	ignore_occlusion_culling = true
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
		# Keep the dense patch under the active camera, including distant islands.
		# A huge fixed grid undersamples the waves and exposes flat strip seams.
		_mat = (mesh as PlaneMesh).material as ShaderMaterial
		mesh = _ocean_patch()
		mesh.surface_set_material(0,_mat)
	if _mat != null:
		if _wave_normals == null:
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.seed = 8124
			noise.frequency = 0.05
			noise.fractal_octaves = 4
			_wave_normals = NoiseTexture2D.new()
			_wave_normals.width = 256
			_wave_normals.height = 256
			_wave_normals.seamless = true
			_wave_normals.as_normal_map = true
			_wave_normals.bump_strength = 8.0
			_wave_normals.noise = noise
		_mat.set_shader_parameter("wave_normals", _wave_normals)
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
	# Prepare the dive pipeline while the world is loading, before entering water.
	_ensure_underwater();_under_layer.show()

func _process(delta: float) -> void:
	var active_camera := get_viewport().get_camera_3d()
	if active_camera != null:
		global_position.x = active_camera.global_position.x
		global_position.z = active_camera.global_position.z
	_time += delta
	# The engine's shader TIME begins before scene loading. Use the same clock
	# as get_height so the rendered crests and raft never drift out of phase.
	if _mat!=null:_mat.set_shader_parameter("wave_time",_time)
	_update_deck_displacement(delta)
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
	_update_underwater(delta)

func _create_far_water() -> void:
	if _mat == null:
		return
	# Four broad strips fill the horizon beyond the playable, detailed plane.
	# They have a hole in the center: no full-screen overlapping water pass.
	var inner := Vector2(400,400)
	var extent := 12000.0
	var corners: Array[Vector3] = [Vector3(-inner.x, 0, -inner.y), Vector3(inner.x, 0, -inner.y),
		Vector3(inner.x, 0, inner.y), Vector3(-inner.x, 0, inner.y)]
	var outer: Array[Vector3] = [Vector3(-extent, 0, -extent), Vector3(extent, 0, -extent),
		Vector3(extent, 0, extent), Vector3(-extent, 0, extent)]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(4):
		var next := (edge + 1) % 4
		# Match every near-patch edge vertex. A four-corner strip left slivers
		# between its straight edge and the near mesh's animated wave heights.
		for segment in 128:
			var t0:=(_patch_axis(float(segment-64))+400.0)/800.0
			var t1:=(_patch_axis(float(segment+1-64))+400.0)/800.0
			var a:=corners[edge].lerp(corners[next],t0);var b:=corners[edge].lerp(corners[next],t1)
			var c:=outer[edge].lerp(outer[next],t0);var d:=outer[edge].lerp(outer[next],t1)
			for point in [a,c,d,a,d,b]:
				builder.set_normal(Vector3.UP)
				builder.add_vertex(point)
	var far_water := MeshInstance3D.new()
	far_water.name = "FarWater"
	far_water.mesh = builder.commit()
	far_water.material_override = _mat
	far_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_water.extra_cull_margin = extra_cull_margin
	far_water.ignore_occlusion_culling = true
	add_child(far_water)

func _push_factors(night: float, twilight: float, moon_factor: float) -> void:
	_last_night = night
	_last_twilight = twilight
	_last_moon = moon_factor
	_mat.set_shader_parameter("night_factor", night)
	_mat.set_shader_parameter("twilight_factor", twilight)
	_mat.set_shader_parameter("moon_factor", moon_factor)
	var rain := get_tree().get_first_node_in_group("rain_system")
	_mat.set_shader_parameter("storm_amount",float(rain.call("sky_storm_strength")) if rain!=null else 0.0)
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
func _update_underwater(delta: float=0.0) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		if _under_layer != null:
			_under_layer.visible = false
		return
	var water_level := get_height(cam.global_position)
	var depth := water_level - cam.global_position.y
	var diving:=depth>.3
	if _env!=null and diving!=_diving_background:
		_diving_background=diving
		if diving:
			_surface_background=_env.background_mode;_surface_background_color=_env.background_color
			_env.background_mode=Environment.BG_COLOR;_env.background_color=Color(.012,.055,.085)
		else:
			_env.background_mode=_surface_background;_env.background_color=_surface_background_color
	var amt := clampf(depth / 1.4, 0.0, 1.0)
	amt = amt * amt * (3.0 - 2.0 * amt)  # smoothstep-like ramp
	_dive_blend=lerpf(_dive_blend,amt,1.0-exp(-delta*6.0)) if delta>0 else amt
	amt=_dive_blend
	if amt <= 0.001:
		if _under_layer != null:
			_under_layer.visible = _veil_warm_frames>0
		_veil_warm_frames=maxi(0,_veil_warm_frames-1)
		return
	_ensure_underwater()
	_under_layer.visible = true
	var deep:=smoothstep(8.0,65.0,maxf(0,depth))
	var daylight:=1.0-_last_night
	if _env!=null and diving:_env.background_color=Color(.045,.24,.29).lerp(Color(.007,.028,.065),deep)*(.25+.75*daylight)
	var alpha := under_alpha_max * amt * (.34+.66*deep)
	var tint:=Color(.075,.34,.38).lerp(under_top_color.darkened(.35),deep)
	var top := Color(tint.r,tint.g,tint.b,alpha)
	var bottom_tint:=Color(.025,.14,.20).lerp(under_bottom_color,deep)
	var bottom := Color(bottom_tint.r,bottom_tint.g,bottom_tint.b,alpha*1.10)
	_under_mat.set_shader_parameter("top_col", top)
	_under_mat.set_shader_parameter("bottom_col", bottom)

func _ensure_underwater() -> void:
	if _under_layer != null:
		return
	_under_layer = CanvasLayer.new()
	_under_layer.name = "_OceanUnderwaterVei"
	_under_layer.layer = 0 # Water tint stays behind readable health/air/touch HUD.
	_under_layer.visible = false
	add_child(_under_layer)
	_under_mat = ShaderMaterial.new()
	_under_mat.shader = _UNDER_SHADER
	_under_mat.set_shader_parameter("top_col",Color(0,0,0,0))
	_under_mat.set_shader_parameter("bottom_col",Color(0,0,0,0))
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
	[Vector2(1.0, 0.15), 0.18, 1.0, 0.80],
	[Vector2(-0.4, 0.92), 0.33, 0.75, 1.10],
	[Vector2(0.8, -0.5), 0.59, 0.38, 1.55],
	[Vector2(-0.75, -0.65), 0.95, 0.13, 1.90],
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
	return global_position.y + _sample_wave(Vector2(world_pos.x,world_pos.z),_time*wave_speed)*wave_height*0.33

# Evaluate a whole deck without repeated Node transform lookups or Variant
# wave-array iteration for every corner. Keep every probe and its tilted Y.
func get_deck_crest(origin: Vector3, deck_basis: Basis, points: PackedVector3Array) -> float:
	var tt := _time*wave_speed
	var water_y := global_position.y
	var amplitude := wave_height*0.33
	var crest := -INF
	for point in points:
		var offset := deck_basis*point
		var p := Vector2(origin.x+offset.x,origin.z+offset.z)
		crest=maxf(crest,water_y+_sample_wave(p,tt)*amplitude-offset.y)
	return crest

func get_wave_slope_bound() -> float:
	# Four wave gradients sum below .764; envelope adds < .022, and
	# the meander Jacobian magnifies by < 1.39. After the .33 amplitude
	# factor, .5*height safely bounds world-space slope for this formula.
	return absf(wave_height)*0.5

func _sample_wave(p: Vector2, tt: float) -> float:
	var phase1 := p.dot(_M1_DIR)*_M1_F+tt*_M1_S
	var phase2 := p.dot(_M2_DIR)*_M2_F+tt*_M2_S
	var pw := p+Vector2(_M_AMP*sin(phase1)+_M_AMP2*sin(phase2),
			_M_AMP*sin(phase1+2.1)+_M_AMP2*sin(phase2+4.2))
	var env := 0.75 + 0.25 * sin(pw.dot(_E1_DIR) * _E1_F + tt * _E1_S) * sin(pw.dot(_E2_DIR) * _E2_F + tt * _E2_S)
	# The four fixed shader waves, explicitly typed instead of unpacking four
	# untyped arrays in this hot path. _WAVES remains the reference constants.
	var h := sin(pw.dot(Vector2(1.0,0.15))*0.18+tt*0.80)
	h += 0.75*sin(pw.dot(Vector2(-0.4,0.92))*0.33+tt*1.10)
	h += 0.38*sin(pw.dot(Vector2(0.8,-0.5))*0.59+tt*1.55)
	h += 0.13*sin(pw.dot(Vector2(-0.75,-0.65))*0.95+tt*1.90)
	return h*env

func _update_deck_displacement(delta: float) -> void:
	if _mat == null: return
	if not is_instance_valid(_boat_ref):_boat_ref=get_tree().get_first_node_in_group("player_boat") as Node3D
	_mat.set_shader_parameter("boat_displacement",is_instance_valid(_boat_ref))
	if is_instance_valid(_boat_ref):
		_mat.set_shader_parameter("boat_cut",Vector4(_boat_ref.global_position.x,_boat_ref.global_position.z,cos(_boat_ref.rotation.y),sin(_boat_ref.rotation.y)))
		_mat.set_shader_parameter("boat_waterline",_boat_ref.global_position.y)
	if not is_instance_valid(_raft_ref):
		_raft_ref = get_tree().get_first_node_in_group("raft") as Node3D
	if _raft_ref == null: return
	_mat.set_shader_parameter("world_to_raft",_raft_ref.global_transform.affine_inverse())
	_deck_refresh -= delta
	if _deck_refresh > 0: return
	_deck_refresh = 0.4
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var pieces := _raft_ref.get_node_or_null("BuiltPieces")
	if pieces != null:
		for piece in pieces.get_children():
			if piece is Node3D and piece.name.begins_with("Foundation") and not piece.is_queued_for_deletion() and absf(piece.position.y)<0.2:
				cells.append(Vector2i(roundi(piece.position.x/2),roundi(piece.position.z/2)))
	var signature := hash(cells)
	if signature == _deck_signature: return
	_deck_signature = signature
	var field := Image.create(128,128,false,Image.FORMAT_R8)
	for cell in cells:
		var pixel := cell+Vector2i(64,64)
		if pixel.x>=0 and pixel.x<128 and pixel.y>=0 and pixel.y<128: field.set_pixelv(pixel,Color.WHITE)
	_deck_coverage=field
	if _deck_texture == null: _deck_texture=ImageTexture.create_from_image(field)
	else: _deck_texture.update(field)
	_mat.set_shader_parameter("raft_deck",_deck_texture)
	_mat.set_shader_parameter("raft_displacement",true)

static func _ocean_patch() -> ArrayMesh:
	# Same 128-square budget, concentrated within 80m of the camera. Uniform
	# 800m grids had 6m spacing and flattened all the visible medium waves.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(129):
		var tz := float(z-64)
		var pz := _patch_axis(tz)
		for x in range(129):
			var tx := float(x-64)
			var px := _patch_axis(tx)
			vertices.append(Vector3(px,0,pz))
			normals.append(Vector3.UP)
			uvs.append(Vector2(px,pz)/800.0+Vector2.ONE*0.5)
	for z in range(128):
		for x in range(128):
			var i := z*129+x
			indices.append_array(PackedInt32Array([i,i+1,i+129,i+1,i+130,i+129]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func _patch_axis(value: float) -> float:
	return value*(80.0/48.0) if absf(value)<=48 else signf(value)*(80+(absf(value)-48)*20)
