extends SceneTree
## Headless VRAM probe: loads every baked vegetation mesh and reports the
## textures embedded in their materials (dimensions, format, actual byte
## size from the Image data — includes mipmaps and compression), per bake
## file and total. Run before/after any texture-memory change:
##   godot --headless --path . --script tools/probe_vram.gd

const BAKES := [
	"res://grass/baked/palm_island.res",
	"res://grass/baked/coconut_sprout.res",
	"res://grass/baked/coconut_young.res",
	"res://grass/baked/coconut_mature.res",
	"res://grass/baked/coconut_bunch.res",
	"res://grass/baked/coconut_single.res",
	"res://grass/baked/grass_clump.res",
	"res://grass/baked/scan_tuft.res",
	"res://grass/baked/scan_dandelion.res",
	"res://grass/baked/scan_groundcover.res",
	"res://grass/baked/scan_flower.res",
	"res://grass/baked/apple_tree.res",
	"res://grass/baked/apple_tree_mobile.res",
	"res://grass/baked/apple_single.res",
]

var _seen := {} # texture -> bytes (dedupe shared textures)

func _initialize() -> void:
	var grand := 0
	for p in BAKES:
		if not ResourceLoader.exists(p):
			print("PROBE missing: %s" % p)
			continue
		var before := _seen.size()
		var mesh := load(p) as Mesh
		if mesh == null:
			print("PROBE not a mesh: %s" % p)
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m is BaseMaterial3D:
				_scan_mat(m)
		var file_bytes := 0
		for k in _seen:
			file_bytes += int(_seen[k])
		print("PROBE %s: %d textures, %d textures new, ~%.1f MB cumulative" % [
			p.get_file(), _count_new(before), _seen.size() - before, file_bytes / 1048576.0])
	for k in _seen:
		grand += int(_seen[k])
	print("PROBE TOTAL ~%.1f MB across %d unique textures" % [grand / 1048576.0, _seen.size()])
	# Per-texture top list
	var list := []
	for k in _seen:
		list.append([k, int(_seen[k])])
	list.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for i in mini(20, list.size()):
		print("PROBE TEX %8.2f MB  %s" % [int(list[i][1]) / 1048576.0, list[i][0]])
	print("PROBE_DONE")
	quit(0)

func _count_new(before: int) -> int:
	return _seen.size() - before

func _scan_mat(m: BaseMaterial3D) -> void:
	for tex_prop in ["albedo_texture", "normal_texture", "roughness_texture",
			"ao_texture", "emission_texture", "metallic_texture",
			"clearcoat_texture", "heightmap_texture"]:
		if tex_prop in m and m.get(tex_prop) is Texture2D:
			_scan_tex(m.get(tex_prop), tex_prop)

func _scan_tex(t: Texture2D, prop: String) -> void:
	if t == null or _seen.has(t):
		return
	var img := t.get_image()
	if img == null:
		_seen[t] = 0
		return
	var bytes := img.get_data().size()
	_seen[t] = bytes
	print("PROBE   %-16s %4dx%-4d fmt=%d mips %8.2f MB  %s" % [
		prop, img.get_width(), img.get_height(),
		img.get_format(), bytes / 1048576.0,
		t.resource_path.get_file() if t.resource_path != "" else "<embedded>"])
