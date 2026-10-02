extends Node3D
## Island beacon: an unshaded, translucent light pillar rising from the island
## mound plus a glowing orb and a soft OmniLight — visible from the raft even
## at night (the game starts at 22:15). Registers itself in the
## "island_beacon" group so island_marker.gd (HUD hint) can find it.
##
## All generated meshes join the "no_collision" group, which
## island_setup.gd skips when generating trimesh colliders.

@export var beacon_height := 14.0
@export var beacon_color := Color(1.0, 0.62, 0.25)
@export var pulse_speed := 0.55 ## full pulse cycles per second
@export var light_range := 32.0

var _t := 0.0
var _pillar_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _glow: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	_t = randf() * TAU
	add_to_group("island_beacon")

	# --- translucent pillar ---
	var pillar := MeshInstance3D.new()
	pillar.name = "Pillar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.5
	cyl.height = beacon_height
	cyl.radial_segments = 10
	cyl.rings = 1
	pillar.mesh = cyl
	pillar.position = Vector3(0.0, beacon_height * 0.5 + 0.4, 0.0)
	_pillar_mat = StandardMaterial3D.new()
	_pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pillar_mat.albedo_color = Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.2)
	_pillar_mat.emission_enabled = true
	_pillar_mat.emission = beacon_color
	_pillar_mat.emission_energy_multiplier = 2.2
	_pillar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pillar.material_override = _pillar_mat
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.add_to_group("no_collision")
	add_child(pillar)

	# --- glowing orb at the base ---
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	var sph := SphereMesh.new()
	sph.radius = 0.7
	sph.height = 1.4
	sph.radial_segments = 16
	sph.rings = 8
	_glow.mesh = sph
	_glow.position = Vector3(0.0, 0.9, 0.0)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.9)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = beacon_color
	_glow_mat.emission_energy_multiplier = 3.0
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.add_to_group("no_collision")
	add_child(_glow)

	# --- soft real light so the sand around it glows at night ---
	_light = OmniLight3D.new()
	_light.name = "BeaconLight"
	_light.light_color = beacon_color
	_light.omni_range = light_range
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.2, 0.0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta * pulse_speed * TAU
	var pulse := 0.5 + 0.5 * sin(_t)
	_pillar_mat.albedo_color.a = 0.14 + 0.12 * pulse
	_glow_mat.albedo_color.a = lerpf(0.55, 0.95, pulse)
	_glow.scale = Vector3.ONE * lerpf(0.9, 1.15, pulse)
	if _light != null:
		_light.light_energy = lerpf(1.4, 3.2, pulse)
