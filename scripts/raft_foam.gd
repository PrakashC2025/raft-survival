extends MeshInstance3D
## Subtle foam ring around the raft hull / water contact line.
## Builds a small procedural mesh (vertical skirt around the hull perimeter
## plus a thin top collar) and drives a shader that churns foam whenever the
## ocean wave field laps the hull bottom. Kept tiny + unshaded for mobile.

# Hull is a 2x2 box centered on the raft origin -> half-extent 1.0, bottom -0.15.
const INNER := 1.0
const OUTER := 1.55
const Y_TOP := -0.13    # just under the hull bottom (no seam/z-fight)
const Y_BOT := -0.55
const PERIM := 8.0      # 4 sides of length 2

# Corners in perimeter order: SE, NE, NW, SW.
const CORNERS := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]

var _mat: ShaderMaterial = null
var _ocean_mat: ShaderMaterial = null

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _build_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/raft_foam.gdshader")
	# Transparency is inferred from the shader writing ALPHA (with blend_mix).
	_mat.render_priority = 6
	material_override = _mat
	var ocean: Node = get_tree().get_first_node_in_group("ocean")
	if ocean != null and ocean.mesh is PlaneMesh:
		_ocean_mat = (ocean.mesh as PlaneMesh).material as ShaderMaterial
	_sync_uniforms()

func _process(_delta: float) -> void:
	if _mat == null:
		return
	_sync_uniforms()

func _sync_uniforms() -> void:
	# Contact line follows the raft (the ring is a child of the raft root).
	_mat.set_shader_parameter("plane_y", global_position.y + Y_TOP)
	if _ocean_mat != null:
		_mat.set_shader_parameter("night_factor",
			_ocean_mat.get_shader_parameter("night_factor"))
		_mat.set_shader_parameter("twilight_factor",
			_ocean_mat.get_shader_parameter("twilight_factor"))
		_mat.set_shader_parameter("wave_height",
			_ocean_mat.get_shader_parameter("wave_height"))
		_mat.set_shader_parameter("wave_speed",
			_ocean_mat.get_shader_parameter("wave_speed"))

func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	# u along the perimeter: corner i sits at cumulative length / PERIM.
	var u_at: Array = []
	var acc := 0.0
	for i in CORNERS.size():
		u_at.append(acc / PERIM)
		acc += 2.0  # side length

	var vi := 0

	# --- Vertical skirt: for each side, an inner wall and an outer wall ---
	for i in CORNERS.size():
		var c: Vector2 = CORNERS[i]
		var n: Vector2 = CORNERS[(i + 1) % CORNERS.size()]
		var u0: float = u_at[i]
		var u1: float = u_at[(i + 1) % CORNERS.size()]
		var side := (n - c).normalized()
		var outward := Vector3(side.x, 0, side.y)

		# Inner wall (faces the hull)
		var i0 := vi
		verts.append(Vector3(c.x * INNER, Y_BOT, c.y * INNER))
		verts.append(Vector3(c.x * INNER, Y_TOP, c.y * INNER))
		verts.append(Vector3(n.x * INNER, Y_TOP, n.y * INNER))
		verts.append(Vector3(n.x * INNER, Y_BOT, n.y * INNER))
		uvs.append(Vector2(u0, 0.0))
		uvs.append(Vector2(u0, 1.0))
		uvs.append(Vector2(u1, 1.0))
		uvs.append(Vector2(u1, 0.0))
		for k in 4:
			normals.append(-outward)
		idx.append_array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3])
		vi += 4

		# Outer wall (faces the open water)
		var o0 := vi
		verts.append(Vector3(c.x * OUTER, Y_BOT, c.y * OUTER))
		verts.append(Vector3(c.x * OUTER, Y_TOP, c.y * OUTER))
		verts.append(Vector3(n.x * OUTER, Y_TOP, n.y * OUTER))
		verts.append(Vector3(n.x * OUTER, Y_BOT, n.y * OUTER))
		uvs.append(Vector2(u0, 0.0))
		uvs.append(Vector2(u0, 1.0))
		uvs.append(Vector2(u1, 1.0))
		uvs.append(Vector2(u1, 0.0))
		for k in 4:
			normals.append(outward)
		idx.append_array([o0, o0 + 2, o0 + 1, o0, o0 + 3, o0 + 2])
		vi += 4

	# --- Top collar: thin flat ring at Y_TOP, from the hull edge outward ---
	for i in CORNERS.size():
		var c: Vector2 = CORNERS[i]
		var n: Vector2 = CORNERS[(i + 1) % CORNERS.size()]
		var u0: float = u_at[i]
		var u1: float = u_at[(i + 1) % CORNERS.size()]
		var t0 := vi
		verts.append(Vector3(c.x * INNER, Y_TOP, c.y * INNER))
		verts.append(Vector3(c.x * OUTER, Y_TOP, c.y * OUTER))
		verts.append(Vector3(n.x * OUTER, Y_TOP, n.y * OUTER))
		verts.append(Vector3(n.x * INNER, Y_TOP, n.y * INNER))
		uvs.append(Vector2(u0, 1.0))
		uvs.append(Vector2(u0, 1.0))
		uvs.append(Vector2(u1, 1.0))
		uvs.append(Vector2(u1, 1.0))
		for k in 4:
			normals.append(Vector3.UP)
		idx.append_array([t0, t0 + 1, t0 + 2, t0, t0 + 2, t0 + 3])
		vi += 4

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m