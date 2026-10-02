extends SceneTree
## One-shot inspection of the mobile apple bake.

func _initialize() -> void:
	var m := load("res://grass/baked/apple_tree_mobile.res") as Mesh
	if m == null:
		print("MOBILECHECK: not a mesh")
		quit(1)
		return
	print("MOBILECHECK surfaces=%d" % m.get_surface_count())
	print("MOBILECHECK has_anchors=%s src=%s" % [m.has_meta("fruit_anchors"), m.get_meta("src", "<none>")])
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var arrays := m.surface_get_arrays(s)
		var ntex := 0
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			if bm.albedo_texture != null:
				ntex += 1
		print("MOBILECHECK surf%d mat=%s albedo_tex=%d has_tangent=%s verts=%d" % [
			s, mat.resource_name if mat != null else "<null>", ntex,
			arrays[Mesh.ARRAY_TANGENT] != null, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
	quit(0)
