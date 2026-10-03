extends Node3D
## Reusable, fading sand-impression pool. One transparent quad per step keeps
## the effect inexpensive on mobile; the shader supplies a soft heel, arch,
## ball and toe silhouette with fine pressed-grain variation.

const FOOTPRINT_SHADER: Shader = preload("res://shaders/sand_footprint.gdshader")
const POOL_SIZE := 28
const FOOTPRINT_LIFETIME := 22.0

var _decals: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _ages := PackedFloat32Array()
var _next_index := 0
var _alternate_side := false


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.28, 0.48)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	for i in range(POOL_SIZE):
		var decal := MeshInstance3D.new()
		decal.name = "SandFootprint_%02d" % i
		decal.mesh = plane
		decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		decal.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		decal.visible = false
		var material := ShaderMaterial.new()
		material.shader = FOOTPRINT_SHADER
		material.set_shader_parameter("fade", 0.0)
		decal.material_override = material
		add_child(decal)
		_decals.append(decal)
		_materials.append(material)
		_ages.append(-1.0)


func stamp(world_position: Vector3, surface_normal: Vector3, travel_direction: Vector3) -> void:
	if _decals.is_empty():
		return
	var normal := surface_normal.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	var forward := travel_direction - normal * travel_direction.dot(normal)
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := normal.cross(forward).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	# Alternating foot spacing makes the path read like a walking gait.
	_alternate_side = not _alternate_side
	var side := 1.0 if _alternate_side else -1.0
	var decal := _decals[_next_index]
	var material := _materials[_next_index]
	_next_index = (_next_index + 1) % POOL_SIZE
	decal.global_transform = Transform3D(
		Basis(right, normal, forward),
		world_position + normal * 0.018 + right * side * 0.085
	)
	decal.visible = true
	_ages[_decals.find(decal)] = 0.0
	material.set_shader_parameter("fade", 1.0)


func _process(delta: float) -> void:
	for i in range(_decals.size()):
		if _ages[i] < 0.0:
			continue
		_ages[i] += delta
		var fade := 1.0 - clampf(_ages[i] / FOOTPRINT_LIFETIME, 0.0, 1.0)
		_materials[i].set_shader_parameter("fade", fade)
		if fade <= 0.0:
			_decals[i].visible = false
			_ages[i] = -1.0
