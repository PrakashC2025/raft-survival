extends SceneTree
## One-off verification: dumps the imported rs_grass.glb scene tree and
## texture sizes, then confirms main.tscn still loads. Run headless:
##   godot --headless --path . --script tools/verify_scn.gd

func _init() -> void:
	var ps: PackedScene = load("res://grass/rs_grass.glb")
	if ps == null:
		push_error("FAIL: rs_grass.glb did not load")
		quit(1)
		return
	var inst := ps.instantiate()
	_dump(inst, 0)
	inst.free()

	var main: PackedScene = load("res://scenes/main.tscn")
	if main == null:
		push_error("FAIL: main.tscn did not load")
		quit(1)
		return
	print("OK: main.tscn loads")
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var info := "%s- %s (%s)" % [" ".repeat(depth * 2), n.name, n.get_class()]
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			info += " [verts=%d surfaces=%d]" % [mesh.get_faces().size() / 3, mesh.get_surface_count()]
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var t := (mat as BaseMaterial3D).albedo_texture
					var nt := (mat as BaseMaterial3D).normal_texture
					for tt in [t, nt]:
						if tt != null:
							var img: Image = tt.get_image()
							info += " | %s %dx%d fmt=%d compressed=%s" % [tt.resource_name, tt.get_width(), tt.get_height(), img.get_format(), img.is_compressed()] if img != null else " | null img"
	print(info)
	for c in n.get_children():
		_dump(c, depth + 1)
