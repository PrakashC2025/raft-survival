@tool
extends SceneTree
## ============================================================
## ONE-TIME ASSET BAKE for the island's real vegetation models.
## Produces small, fast resources under res://grass/baked/:
##
##   palm_island.tres — coconut_palm.glb flattened into ONE ArrayMesh
##     (all 5 Sketchfab sub-nodes merged, real-world scale applied),
##     origin at the trunk base. Metadata stores the measured trunk
##     base/top radius + height so island_generator.gd can build an
##     exact capsule collider and sway pivot with zero re-measuring.
##   grass_clump.tres — realistics_grass_10.glb re-pivoted to the
##     ground (bottom face at y=0) and decimated to ~35% of the source
##     triangles so it can be MultiMesh-scattered thousands of times
##     on mobile without frame hitches.
##   grass_clump_albedo.png / palm textures extracted next to them.
##
## Run once after adding/updating the source models:
##   godot --headless --path . --script tools/bake_island_vegetation.gd
## Outputs are committed; this tool is NOT run at game start.
## ============================================================

const OUT_DIR := "res://grass/baked"
const PALM_SRC := "res://models/coconut_palm.glb"
const GRASS_SRC := "res://models/realistics_grass_10.glb"
const SCAN_SRC := "res://models/scanned_plants_and_grass_free_download.glb"
const APPLE_SRC := "res://models/apple_tree.glb"
const KING_SRC := "res://models/king_coconut.glb"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ok := true
	ok = _bake_palm() and ok
	ok = _bake_grass() and ok
	ok = _bake_scan_plants() and ok
	ok = _bake_palm_growth() and ok
	ok = _bake_apple() and ok
	ok = _bake_king_coconut() and ok
	print("BAKE ", "DONE" if ok else "FAILED")
	quit(0 if ok else 1)

# ------------------------------------------------------------
# PALM — merge every MeshInstance3D (real-world scale already on the
# node chain) into one ArrayMesh. Records trunk measurements for the
# collider: Tree_0 is the trunk mesh, base ring at y≈0, top at ~4.65 m.
# ------------------------------------------------------------
func _bake_palm() -> bool:
	var ps: PackedScene = load(PALM_SRC)
	if ps == null:
		push_error("bake: cannot load " + PALM_SRC)
		return false
	var inst := ps.instantiate()
	var merged := ArrayMesh.new()
	# One SurfaceTool per source surface: append_from merges ALL geometry
	# passed to it into a single surface, which would fuse the palm's five
	# different materials/textures together. Per-surface tools keep each
	# material (and thus each texture) intact as its own surface.
	var frond_surface := -1
	var trunk_lo := Vector3(1e9, 1e9, 1e9)
	var trunk_hi := Vector3(-1e9, -1e9, -1e9)
	var trunk_r_base := 0.0
	var trunk_r_top := 0.0

	var stack: Array = [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.append_from(mesh, s, xf)
				var before := merged.get_surface_count()
				var committed: Mesh = st.commit(merged)
				var after := merged.get_surface_count()
				if after == before:
					# append_from can silently skip compressed imported surfaces;
					# fall back to a manual vertex pass (arrays are decompressed).
					_manual_append(merged, mesh, s, xf)
				after = merged.get_surface_count()
				if after == before:
					push_error("bake: surface append failed for %s surf %d" % [mi.name, s])
					return false
				var mat := mesh.surface_get_material(s)
				if mat != null:
					merged.surface_set_material(after - 1, mat)
					if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
						frond_surface = after - 1 # alpha-cut foliage = swaying fronds
				print("BAKE palm: + %s surf%d -> surface %d" % [mi.name, s, after - 1])
			# trunk measurements from the first (trunk) mesh "Tree_0..."
			if String(mi.name).begins_with("Tree_0"):
				var aabb := mi.mesh.get_aabb()
				# ring centroids from actual vertices (AABB centers are wrong
				# for a curved, leaning trunk). All thresholds in WORLD space —
				# the mesh aabb is local (cm), so transform it first.
				var faces := mesh.get_faces()
				var waabb := xf * aabb
				var top_y := waabb.position.y + waabb.size.y
				var b_sum := Vector3.ZERO
				var b_n := 0
				var t_sum := Vector3.ZERO
				var t_n := 0
				var base_max := 0.0
				var top_max := 0.0
				for v0 in faces:
					var v := xf * v0
					if v.y < waabb.position.y + 0.15:
						b_sum += v
						b_n += 1
						base_max = maxf(base_max, Vector2(v.x, v.z).length())
					elif v.y > top_y - 0.15:
						t_sum += v
						t_n += 1
						top_max = maxf(top_max, Vector2(v.x - (t_sum.x / maxf(t_n, 1)), v.z - (t_sum.z / maxf(t_n, 1))).length())
				if b_n > 0 and t_n > 0:
					trunk_lo = b_sum / float(b_n)
					trunk_hi = t_sum / float(t_n)
					trunk_r_base = maxf(base_max, 0.22)
					trunk_r_top = maxf(top_max, 0.12)
		for c in n.get_children():
			stack.append([c, xf])
	inst.free()

	if merged.get_surface_count() == 0:
		push_error("bake: palm merge produced no surfaces")
		return false
	merged.set_meta("trunk_height", trunk_hi.y - trunk_lo.y)
	merged.set_meta("trunk_base", trunk_lo) # ring centroid at the bottom
	merged.set_meta("trunk_top", trunk_hi)  # ring centroid at the top
	merged.set_meta("trunk_r_base", trunk_r_base)
	merged.set_meta("trunk_r_top", trunk_r_top)
	merged.set_meta("frond_surface", frond_surface) # alpha-cut foliage surface
	merged.set_meta("crown_center_y", 5.1) # measured: frond spread 2.0..6.3
	merged.set_meta("crown_radius", 3.6)
	merged.set_meta("src", PALM_SRC)

	# CUT THE BAKED-IN NUT CLUSTER (the alpha surface below crown_y): every
	# palm shipped an identical bunch of nuts, and the runtime fruit slots
	# hung MORE nuts on top. Island palms now carry NO baked fruit — each
	# gets its own varied crop of runtime nuts (fruit_variation in PlantDB).
	var nut_arrays := merged.surface_get_arrays(frond_surface)
	var nut_verts: PackedVector3Array = nut_arrays[Mesh.ARRAY_VERTEX]
	var nut_norms: PackedVector3Array = nut_arrays[Mesh.ARRAY_NORMAL] if nut_arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var nut_uvs: PackedVector2Array = nut_arrays[Mesh.ARRAY_TEX_UV] if nut_arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var nut_idx: PackedInt32Array = nut_arrays[Mesh.ARRAY_INDEX] if nut_arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var frond_st := SurfaceTool.new()
	frond_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept_nut_tris := 0
	for t in nut_idx.size() / 3:
		var ya := nut_verts[nut_idx[t * 3]].y
		var yb := nut_verts[nut_idx[t * 3 + 1]].y
		var yc := nut_verts[nut_idx[t * 3 + 2]].y
		# Same threshold family as the growth-variant cut (PALM_CROWN_CUT_Y 3.5):
		# keep only frond geometry, drop the hanging nut cluster below.
		if ya < 3.5 or yb < 3.5 or yc < 3.5:
			continue
		for vi in [nut_idx[t * 3], nut_idx[t * 3 + 1], nut_idx[t * 3 + 2]]:
			if nut_uvs.size() > vi:
				frond_st.set_uv(nut_uvs[vi])
			if nut_norms.size() > vi:
				frond_st.set_normal(nut_norms[vi])
			frond_st.add_vertex(nut_verts[vi])
		kept_nut_tris += 1
	if kept_nut_tris > 0 and kept_nut_tris < nut_idx.size() / 3:
		if not nut_uvs.is_empty() and not nut_norms.is_empty():
			frond_st.generate_tangents()
		frond_st.index()
		var frond_only := ArrayMesh.new()
		frond_st.commit(frond_only)
		var fmat := merged.surface_get_material(frond_surface)
		var base_arrs := merged.surface_get_arrays(0)
		var rebuilt := ArrayMesh.new()
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base_arrs)
		rebuilt.surface_set_material(0, merged.surface_get_material(0))
		for s in range(1, merged.get_surface_count()):
			if s == frond_surface:
				rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, frond_only.surface_get_arrays(0))
			else:
				rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.surface_get_arrays(s))
			rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, merged.surface_get_material(s))
		# Keep ALL meta (trunk measurements, crown center, frond surface index).
		for meta in merged.get_meta_list():
			rebuilt.set_meta(meta, merged.get_meta(meta))
		merged = rebuilt
		print("BAKE palm: nut cluster cut, frond surface %d -> %d/%d tris" % [frond_surface, kept_nut_tris, nut_idx.size() / 3])

	# Extract every used texture so the baked mesh is self-contained.
	var tex_paths := {}
	var stack2: Array = [[load(PALM_SRC).instantiate(), ""]]
	while not stack2.is_empty():
		var e: Array = stack2.pop_back()
		var n: Node = e[0]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			for s in (n as MeshInstance3D).mesh.get_surface_count():
				var mat := (n as MeshInstance3D).mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					if bm.albedo_texture != null:
						tex_paths[bm.albedo_texture] = _tex_name(bm.resource_name, s)
		for c in n.get_children():
			stack2.append([c, ""])
	var saved := 0
	for tex in tex_paths:
		var img: Image = tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var p: String = OUT_DIR + "/" + tex_paths[tex]
		if img.save_png(p) == OK:
			saved += 1
	print("BAKE palm: %d surfaces, trunk h=%.2f base_y=%.2f r_base=%.2f r_top=%.2f, %d textures" % [
		merged.get_surface_count(), trunk_hi.y - trunk_lo.y, trunk_lo.y, trunk_r_base, trunk_r_top, saved])
	var err := ResourceSaver.save(merged, OUT_DIR + "/palm_island.res")
	if err != OK:
		push_error("bake: saving palm failed (%d)" % err)
		return false
	return true

func _manual_append(target: ArrayMesh, mesh: Mesh, surf: int, xf: Transform3D) -> void:
	var arrays := mesh.surface_get_arrays(surf)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Emit triangles by index (deindexed) so indexed surfaces come through.
	var order := PackedInt32Array()
	if idx.is_empty():
		order.resize(verts.size())
		for i in verts.size():
			order[i] = i
	else:
		order = idx
	for i in order.size():
		var vi := order[i]
		if uvs.size() > vi:
			st.set_uv(uvs[vi])
		if norms.size() > vi:
			st.set_normal((xf.basis * norms[vi]).normalized())
		st.add_vertex(xf * verts[vi])
	# SurfaceTool cannot set tangents directly; regenerate from UV+normal.
	if not uvs.is_empty() and not norms.is_empty():
		st.generate_tangents()
	st.commit(target)

func _tex_name(mat_name: String, s: int) -> String:
	var clean := mat_name.to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "mat%d" % s
	return "tex_" + clean + ".png"

# ------------------------------------------------------------
# GRASS — scale cm->m, re-pivot to the ground and cut half the blades.
# Source pivot is the clump CENTER (half the blades underground); the
# bottom must sit at y=0. The source is authored in centimeters like the
# palm (Sketchfab FBX pipeline), so apply the same 0.01 scale.
# 7920 tris x thousands of MultiMesh instances is far too heavy, so the
# bake deterministically keeps only ~35% of the blade quads — overlapping
# clumps hide the cut, and a 3x lighter mesh keeps the field smooth.
# ------------------------------------------------------------
func _bake_grass() -> bool:
	var ps: PackedScene = load(GRASS_SRC)
	if ps == null:
		push_error("bake: cannot load " + GRASS_SRC)
		return false
	var inst := ps.instantiate()
	var mi := _find_mi(inst)
	if mi == null or mi.mesh == null:
		push_error("bake: no mesh in " + GRASS_SRC)
		return false
	var src_mesh := mi.mesh
	var aabb := src_mesh.get_aabb()
	# cm -> m, then lift the bottom face to y = 0.
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.01), Vector3.ZERO)
	var test_aabb := xf * aabb
	xf = Transform3D(Basis.from_scale(Vector3.ONE * 0.01), Vector3(0, -test_aabb.position.y, 0))

	var arrays := src_mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		push_error("bake: grass surface unreadable")
		return false
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept := 0
	var total := idx.size() / 3
	for t in total:
		# deterministic ~35% keep (hash of the triangle index) — clumps
		# overlap so heavily in the field that the visual difference is nil
		if _hash01(t) > 0.35:
			continue
		for k in 3:
			var vi := idx[t * 3 + k]
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			if norms.size() > vi:
				st.set_normal(norms[vi])
			st.add_vertex(xf * verts[vi])
		kept += 1
	st.generate_normals()
	if not uvs.is_empty():
		st.generate_tangents()
	st.index() # dedupe verts: deindexed quads triple the vertex count otherwise
	var out := ArrayMesh.new()
	st.commit(out)
	# keep the textured material (alpha scissor + double sided from import)
	var mat := src_mesh.surface_get_material(0)
	if mat != null:
		out.surface_set_material(0, mat)
	inst.free()

	out.set_meta("pivot_lift", -test_aabb.position.y)
	out.set_meta("tris_kept", kept)
	out.set_meta("tris_total", total)
	out.set_meta("src", GRASS_SRC)

	# Extract the albedo texture so the field material is self-contained.
	var saved := 0
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.albedo_texture != null:
			var img: Image = bm.albedo_texture.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				if img.save_png(OUT_DIR + "/grass_clump_albedo.png") == OK:
					saved += 1
	var baked_aabb := out.get_aabb()
	print("BAKE grass: kept %d/%d tris, aabb=%s..%s, %d textures" % [
		kept, total, baked_aabb.position, baked_aabb.position + baked_aabb.size, saved])
	var err := ResourceSaver.save(out, OUT_DIR + "/grass_clump.res")
	if err != OK:
		push_error("bake: saving grass failed (%d)" % err)
		return false
	return true

func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)

# ------------------------------------------------------------
# APPLE TREE — models/apple_tree.glb is a single 783k-tri mesh (4 surfaces:
# bark / leaves / apples / apple-bark). Too heavy even once on mobile, so
# bake TWO light resources:
#
#   apple_tree.res    ONE tree ~5.7 m — DENSE canopy, NO apples, ~500k tris
#                     + meta "fruit_anchors": canopy points for runtime fruit
#   apple_single.tres one apple scaled to 16 cm — a few hundred tris
#
# Decimation strategy (v2 — the per-triangle hash SHREDDED the tree):
#  - Foliage is thousands of DISCONNECTED 10-tri leaf cards → drop whole
#    cards (never triangles inside one) until the budget is hit.
#  - Bark/twigs are one closed skin → Godot's meshopt LOD simplifier
#    (ImporterMesh.generate_lods), which preserves topology and cannot
#    punch holes the way random dropping did.
#  - Fruit surface is kept whole (apple_single isolates one apple itself).
# Textures are re-saved at max 2048 px so foliage stays crisp without
# blowing VRAM.
# ------------------------------------------------------------
const APPLE_MAX_TEX := 1536 # 2048 blew the file to 57 MB and froze loading on phones

func _bake_apple() -> bool:
	var ps: PackedScene = load(APPLE_SRC)
	if ps == null:
		push_error("bake: cannot load " + APPLE_SRC)
		return false
	var inst := ps.instantiate()
	var mi := _find_mi(inst)
	if mi == null or mi.mesh == null:
		push_error("bake: no mesh in " + APPLE_SRC)
		return false
	var src := mi.mesh
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()

	# Per-surface bake: transform, decimate, keep material. Returns arrays.
	var surf: Array = []   # [ [arrays, mat, tris_kept], ... ]
	var total_src := 0
	var total_kept := 0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var mat := src.surface_get_material(s)
		var nm := mat.resource_name if mat != null else ""
		# EXACT fruit match — containsn() is case-insensitive and would
		# swallow "apple.leaf" (foliage!) into the fruit group, baking a
		# leafless tree. Surfaces: ETG_BARK (trunk), apple.leaf (foliage),
		# Apple (fruit), ETG_BARK.apple (fruiting twigs).
		var is_leaves := nm.containsn("leaf")
		var is_apple := nm == "Apple"
		var is_twig := nm.containsn("bark") and nm.containsn("apple")
		var nb := xf.basis.inverse().transposed()
		var total := idx.size() / 3
		total_src += total
		# Per-kind decimation (see the file header): whole leaf cards for
		# foliage, meshopt skin simplification for bark, whole fruit.
		var kept_idx := PackedInt32Array()
		if is_leaves:
			# DENSE canopy: 500k of 1.22M leaf tris ≈ 41% of whole cards. The
			# cards overlap heavily, so 41% still reads as a full crown (the
			# old 80k/200k budgets left a sparse, twiggy shrub). 700k pushed
			# the .tres to 57 MB and froze the loading screen on phones.
			kept_idx = _cull_leaf_components(idx, 600000)
		elif is_apple:
			kept_idx = idx
		else:
			# Bark 0.25 shaved the trunk smooth/warpy; 0.45 keeps the trunk
			# silhouette (root flare, branches) close to the source model.
			kept_idx = _simplify_skin(idx, verts, norms, uvs, 0.60 if is_twig else 0.45)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in kept_idx.size():
			var vi := kept_idx[k]
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			if norms.size() > vi:
				st.set_normal((nb * norms[vi]).normalized())
			st.add_vertex(xf * verts[vi])
		var kept := kept_idx.size() / 3
		print("BAKE apple surf%d %s: kept %d/%d tris" % [s, nm, kept, total])
		total_kept += kept
		if not uvs.is_empty() and not norms.is_empty():
			st.generate_tangents()
		st.index()
		var out := ArrayMesh.new()
		st.commit(out)
		surf.append([out.surface_get_arrays(0), mat, kept])

	if surf.is_empty():
		push_error("bake: apple tree produced no surfaces")
		return false
	inst.free()

	# Bounds of the NO-APPLE geometry (surfaces 0 bark + 1 leaves): drives
	# the two tree sizes. The apple surfaces (Apple + apple-bark twigs) are
	# EXCLUDED from both tree variants — fruit is grown by the game.
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var apple_lo := Vector3(1e9, 1e9, 1e9)
	var apple_hi := Vector3(-1e9, -1e9, -1e9)
	var apple_parts: Array = [] # [arrays, mat] of the two apple surfaces
	for e in surf:
		var arrays: Array = e[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var m: Material = e[1]
		var is_apple_part := m != null and String(m.resource_name).containsn("apple")
		for v in verts:
			if is_apple_part:
				apple_lo = apple_lo.min(v)
				apple_hi = apple_hi.max(v)
			else:
				lo = lo.min(v)
				hi = hi.max(v)
	# Fruit = EXACTLY the "Apple" surface; bark + leaves + fruiting twigs
	# all belong to the tree.
	var twig_arrays: Array = []
	var apple_arrays: Array = []
	for e in surf:
		var m: Material = e[1]
		var nm := m.resource_name if m != null else ""
		if nm == "Apple":
			apple_arrays.append(e)
		else:
			twig_arrays.append(e)

	var ok := true
	# ONE tree mesh (5.7 m, no apple surfaces): planted trees reuse it at
	# smaller container scales (the growth system scales continuously),
	# which keeps a whole extra tree mesh out of memory. twig_arrays carries
	# meta "fruit_anchors" (canopy lattice points) for the runtime fruit slots.
	ok = _bake_apple_tree("apple_tree", twig_arrays, 5.7) and ok
	# MOBILE VARIANT (apple_tree_mobile.res): the full tree is ~37 MB — the
	# single heaviest asset in RAM and in the APK — and low-end phones load
	# it in seconds while barely fitting it in VRAM. Half-density leaves
	# (whole-card cull again, 250k tris) + a second meshopt pass on the
	# bark/twig skins + 768 px textures land at ~1/3 the size. Desktop keeps
	# the full bake; plant_instance + main_menu pick the mobile file via
	# OS.has_feature("mobile") with a graceful fallback to the full one.
	ok = _bake_apple_tree("apple_tree_mobile", _lighten_apple_parts(twig_arrays, 250000, 0.55), 5.7, true) and ok
	# Single apple from the Apple surface, scaled to ~16 cm, pivoted at its stem.
	ok = _bake_apple_single(apple_arrays) and ok
	print("BAKE apple: %d/%d tris kept across %d surfaces" % [total_kept, total_src, surf.size()])
	return ok

## Foliage decimation that keeps every leaf card WHOLE. The leaf surface is
## ~76k disconnected ~10-tri cards; union-find groups triangles into cards,
## then a deterministic hash keeps whole cards until the triangle budget is
## hit. Random per-triangle dropping (the old method) shredded every card
## from 10 tris to ~0.3 — the moth-eaten canopy.
func _cull_leaf_components(idx: PackedInt32Array, tri_budget: int) -> PackedInt32Array:
	if tri_budget >= idx.size() / 3:
		return idx
	var n_verts := 0
	for vi in idx:
		if vi >= n_verts:
			n_verts = vi + 1
	var parent := PackedInt32Array()
	parent.resize(n_verts)
	for i in n_verts:
		parent[i] = i
	for t in idx.size() / 3:
		var ra := _uf_find(parent, idx[t * 3])
		var rb := _uf_find(parent, idx[t * 3 + 1])
		if ra != rb:
			parent[mini(ra, rb)] = maxi(ra, rb)
		var rc := _uf_find(parent, idx[t * 3 + 2])
		var r := _uf_find(parent, ra)
		if r != rc:
			parent[mini(r, rc)] = maxi(r, rc)
	var keep_frac := clampf(float(tri_budget) / float(idx.size() / 3), 0.05, 1.0)
	var keep := {}
	for t in idx.size() / 3:
		var r := _uf_find(parent, idx[t * 3])
		if not keep.has(r):
			keep[r] = _hash01(float(r) * 0.6180339887) < keep_frac
	var out := PackedInt32Array()
	out.resize(idx.size())
	var w := 0
	for t in idx.size() / 3:
		if keep.get(_uf_find(parent, idx[t * 3]), false):
			out[w * 3] = idx[t * 3]
			out[w * 3 + 1] = idx[t * 3 + 1]
			out[w * 3 + 2] = idx[t * 3 + 2]
			w += 1
	out.resize(w * 3)
	return out

func _uf_find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

## Closed-skin decimation via Godot's meshopt LOD generator (the same tech
## the editor importer uses): simplifies while PRESERVING topology, so the
## trunk keeps a watertight surface — random triangle dropping punched
## holes straight through it.
func _simplify_skin(idx: PackedInt32Array, verts: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array, ratio: float) -> PackedInt32Array:
	var im := ImporterMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms if norms.size() > 0 else null
	arr[Mesh.ARRAY_TEX_UV] = uvs if uvs.size() > 0 else null
	arr[Mesh.ARRAY_INDEX] = idx
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "skin")
	im.generate_lods(30.0, false, [])
	var best := idx
	var target := int(float(idx.size() / 3) * ratio)
	for i in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, i)
		if li.size() / 3 <= target:
			best = li
			break
	return best

func _bake_apple_tree(out_name: String, parts: Array, target_h: float, light := false) -> bool:
	if parts.is_empty():
		push_error("bake: %s has no source surfaces" % out_name)
		return false
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for e in parts:
		var verts: PackedVector3Array = e[0][Mesh.ARRAY_VERTEX]
		for v in verts:
			lo = lo.min(v)
			hi = hi.max(v)
	var s := target_h / maxf(hi.y - lo.y, 0.001)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0, -lo.y * s, 0))
	var out := ArrayMesh.new()
	var kept_total := 0
	var canopy_verts := PackedVector3Array() # leaf + fruiting-twig verts for fruit anchors
	for e in parts:
		var arrays: Array = e[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var nb := xf.basis.inverse().transposed()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in idx.size() / 3:
			for k in 3:
				var vi := idx[t * 3 + k]
				if uvs.size() > vi:
					st.set_uv(uvs[vi])
				if norms.size() > vi:
					st.set_normal((nb * norms[vi]).normalized())
				st.add_vertex(xf * verts[vi])
		# Canopy-fruit anchors come from the FOLIAGE surfaces (alpha-scissor
		# leaves + the apple-bark twigs), never the trunk.
		var pm: Material = e[1]
		if pm != null and ((pm is BaseMaterial3D and (pm as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR) \
				or pm.resource_name.containsn("apple")):
			for i in range(0, idx.size(), 6): # sample every 2nd triangle
				canopy_verts.append(xf * verts[idx[i]])
		kept_total += idx.size() / 3
		# TANGENTS: only normal-mapped materials need them. The apple tree's
		# surfaces carry albedo only (probe_vram), so the MOBILE bake skips
		# the tangent array outright (~16 B/vertex of pure waste on phones).
		# Desktop keeps them for future detail-map work.
		if not light and not uvs.is_empty() and not norms.is_empty():
			st.generate_tangents()
		st.index()
		var before := out.get_surface_count()
		st.commit(out)
		var m: Material = e[1]
		if m != null:
			out.surface_set_material(before, _baked_apple_material(m, 768 if light else APPLE_MAX_TEX))
	out.set_meta("src", APPLE_SRC)
	out.set_meta("height", target_h)
	# FRUIT ANCHORS: quantize canopy verts to a 0.35 m lattice, rank cells by
	# leaf density, greedy-pick the 8 densest that are >= 0.45 m apart. The
	# runtime fruit slots hang apples from these points — real fruit sits IN
	# the leaf mass on branches (the old random sphere scatter floated apples
	# in empty air inside the crown).
	var cell := 0.35
	var counts := {}
	var cell_sum := {}
	for v in canopy_verts:
		var key := Vector3i(int(floor(v.x / cell)), int(floor(v.y / cell)), int(floor(v.z / cell)))
		counts[key] = int(counts.get(key, 0)) + 1
		cell_sum[key] = (cell_sum.get(key, Vector3.ZERO) as Vector3) + v
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a, b) -> bool: return int(counts[a]) > int(counts[b]))
	var anchors := PackedVector3Array()
	for key in ranked:
		if anchors.size() >= 8:
			break
		var center: Vector3 = (cell_sum[key] as Vector3) / float(counts[key])
		var spaced := true
		for a in anchors:
			if center.distance_to(a) < 0.45:
				spaced = false
				break
		if spaced:
			anchors.append(center)
	out.set_meta("fruit_anchors", anchors)
	print("BAKE apple %s: %d fruit anchors" % [out_name, anchors.size()])
	var aabb := out.get_aabb()
	print("BAKE apple %s: %d tris, %.2f m, %d surfaces" % [out_name, kept_total, aabb.position.y + aabb.size.y, out.get_surface_count()])
	return ResourceSaver.save(out, "%s/%s.res" % [OUT_DIR, out_name]) == OK

func _bake_apple_single(apple_parts: Array) -> bool:
	if apple_parts.is_empty():
		push_error("bake: no apple surface found")
		return false
	# Use the surface with the most triangles as the apple (the big Apple one).
	var best: Array = apple_parts[0]
	for e in apple_parts:
		if int(e[2]) > int(best[2]):
			best = e
	var arrays: Array = best[0]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	# ISOLATE ONE APPLE: the "Apple" surface holds every fruit on the tree
	# as disconnected components (like the leaves). Union-find them and take
	# the LARGEST — exactly one whole apple, never fragments of neighbors
	# (the old ±1-cell grid box caught pieces of adjacent cluster fruit and
	# then hash-dropped 65% of even those triangles → holey fruit).
	var n_verts := 0
	for vi in idx:
		if vi >= n_verts:
			n_verts = vi + 1
	var parent := PackedInt32Array()
	parent.resize(n_verts)
	for i in n_verts:
		parent[i] = i
	for t in idx.size() / 3:
		var ra := _uf_find(parent, idx[t * 3])
		var rb := _uf_find(parent, idx[t * 3 + 1])
		if ra != rb:
			parent[mini(ra, rb)] = maxi(ra, rb)
		var rc := _uf_find(parent, idx[t * 3 + 2])
		var r := _uf_find(parent, ra)
		if r != rc:
			parent[mini(r, rc)] = maxi(r, rc)
	var comp_size := {}
	for t in idx.size() / 3:
		var r := _uf_find(parent, idx[t * 3])
		comp_size[r] = int(comp_size.get(r, 0)) + 1
	var best_root := -1
	var best_tris := 0
	for r in comp_size:
		if int(comp_size[r]) > best_tris:
			best_tris = int(comp_size[r])
			best_root = r
	# The one apple's triangles (indices into the original index buffer).
	var comp_tri := PackedInt32Array()
	for t in idx.size() / 3:
		if _uf_find(parent, idx[t * 3]) == best_root:
			comp_tri.append(t)
	# Decimate the single apple topologically (skin-simplifier keeps the
	# fruit shell intact) and rebuild vertex bounds from the KEPT apple only.
	var comp_idx := PackedInt32Array()
	comp_idx.resize(comp_tri.size() * 3)
	for j in comp_tri.size():
		for k in 3:
			comp_idx[j * 3 + k] = idx[comp_tri[j] * 3 + k]
	# One fruit, instanced a handful of times — keep it WHOLE (~200 tris is
	# nothing; simplifying a 9-cm prop only blurs its normal-mapped skin).
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for k in comp_idx.size():
		var v := verts[comp_idx[k]]
		lo = lo.min(v)
		hi = hi.max(v)
	var s := 0.16 / maxf(hi.y - lo.y, 0.001) # a full-size apple ~16 cm tall
	# (the old 9 cm fruit vanished against the 5.7 m tree — the glb preview's
	# apples are chunky, ~1/35 of the tree height)
	# pivot at the TOP (stem) so hanging + falling rotate naturally
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-(lo.x + hi.x) * 0.5 * s, -hi.y * s, -(lo.z + hi.z) * 0.5 * s))
	var nb := xf.basis.inverse().transposed()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept_a := 0
	for k in comp_idx.size():
		var vi := comp_idx[k]
		if uvs.size() > vi:
			st.set_uv(uvs[vi])
		if norms.size() > vi:
			st.set_normal((nb * norms[vi]).normalized())
		st.add_vertex(xf * verts[vi])
	kept_a = comp_idx.size() / 3
	# Tangents need real normals + UVs (both flow through now that the
	# has()-vs-null trap above is fixed).
	if not uvs.is_empty() and not norms.is_empty():
		st.generate_tangents()
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)
	var m: Material = best[1]
	if m != null:
		out.surface_set_material(0, _baked_apple_material(m))
	var aabb := out.get_aabb()
	print("BAKE apple_single: %d tris, %.1f cm tall" % [kept_a, aabb.size.y * 100.0])
	return ResourceSaver.save(out, OUT_DIR + "/apple_single.res") == OK

## ------------------------------------------------------------
## KING COCONUT — models/king_coconut.glb is a Sketchfab scene of 12 nodes:
## 11 IDENTICAL bunch copies (1176 tris each, same AABB, material kc_HP1)
## + 1 stem. The nuts INTERPENETRATE (contact necks as tight as intra-nut
## triangle spacing — verified by centroid-distance probe: every cut ends
## in one fused component), so NO cut-based union-find can split them.
## TWO outputs:
##   coconut_bunch.res  — the WHOLE shell scaled to ~0.45 m, pivot at the
##                        top (kept as the fallback / future use).
##   coconut_single.res — ONE nut via GREEDY BALL-CARVE (_carve_kc_nut):
##                        grow balls from uncovered triangle centroids, the
##                        winning radius's largest ball ≈ one nut's share of
##                        tris (~134 incl. neck), then patch its far side
##                        with unclaimed tris inside the nut's bounding
##                        sphere. Scaled to 12 cm, pivot at the top.
## ------------------------------------------------------------
func _bake_king_coconut() -> bool:
	var ps: PackedScene = load(KING_SRC)
	if ps == null:
		push_error("bake: cannot load " + KING_SRC)
		return false
	var inst := ps.instantiate()
	# Merge the FIRST bunch copy's triangles with its world transform.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var mat: Material = null
	var found := false
	var stack: Array = [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty() and not found:
		var e: Array = stack.pop_front()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh := (n as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				var su: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				var si: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if si.is_empty():
					si.resize(sv.size())
					for i in sv.size():
						si[i] = i
				var base := verts.size()
				for v in sv:
					verts.append(xf * v)
				for nn in sn:
					norms.append((xf.basis.inverse().transposed() * nn).normalized())
				for uu in su:
					uvs.append(uu)
				for k in si:
					idx.append(base + si[k])
				if mat == null:
					mat = mesh.surface_get_material(s)
			found = true # one bunch is plenty: 11 more are identical copies
		for c in n.get_children():
			stack.append([c, xf])
	inst.free()
	if verts.is_empty() or idx.is_empty():
		push_error("bake king_coconut: no triangle data")
		return false
	# Weld by position (Sketchfab parts split shells), then union-find
	# triangle connectivity and take the LARGEST component = the bunch shell.
	var vmap := {}
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wu := PackedVector2Array()
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	for i in verts.size():
		var key := Vector3i(roundi(verts[i].x * 100.0), roundi(verts[i].y * 100.0), roundi(verts[i].z * 100.0))
		if vmap.has(key):
			remap[i] = int(vmap[key])
		else:
			remap[i] = wv.size()
			vmap[key] = wv.size()
			wv.append(verts[i])
			if i < norms.size():
				wn.append(norms[i])
			if i < uvs.size():
				wu.append(uvs[i])
	var widx := PackedInt32Array()
	widx.resize(idx.size())
	for i in idx.size():
		widx[i] = remap[idx[i]]
	var n_verts := wv.size()
	var parent := PackedInt32Array()
	parent.resize(n_verts)
	for i in n_verts:
		parent[i] = i
	for t in widx.size() / 3:
		var ra := _uf_find(parent, widx[t * 3])
		var rb := _uf_find(parent, widx[t * 3 + 1])
		if ra != rb:
			parent[mini(ra, rb)] = maxi(ra, rb)
		var rc := _uf_find(parent, widx[t * 3 + 2])
		var r := _uf_find(parent, ra)
		if r != rc:
			parent[mini(r, rc)] = maxi(r, rc)
	var comp_size := {}
	for t in widx.size() / 3:
		var r := _uf_find(parent, widx[t * 3])
		comp_size[r] = int(comp_size.get(r, 0)) + 1
	var best_root := -1
	var best_tris := 0
	for r in comp_size:
		if int(comp_size[r]) > best_tris:
			best_tris = int(comp_size[r])
			best_root = r
	if best_root < 0 or best_tris < 20:
		push_error("bake king_coconut: no coconut-sized component found")
		return false
	var bunch_tri := PackedInt32Array()
	for t in widx.size() / 3:
		if _uf_find(parent, widx[t * 3]) == best_root:
			bunch_tri.append(t)
	# Triangle centroids of the bunch (for the nut-splitting pass).
	var cent := PackedVector3Array()
	cent.resize(bunch_tri.size())
	for j in bunch_tri.size():
		var t2 := bunch_tri[j]
		cent[j] = (wv[widx[t2 * 3]] + wv[widx[t2 * 3 + 1]] + wv[widx[t2 * 3 + 2]]) / 3.0
	# --- CARVE ONE NUT OUT OF THE BUNCH (greedy ball-carve) ---
	# The nuts INTERPENETRATE: contact necks are as tight as intra-nut
	# triangle spacing, so NO centroid-distance cut can split them (probe:
	# cuts 0.5..30 all end in one component). Instead, grow balls from
	# uncovered triangles: each ball grabs every uncovered centroid within
	# radius r — one ball ≈ one nut interior. The best radius is the one
	# whose ball count is closest to a real king-coconut bunch (~9-11 nuts).
	var nut_tri := _carve_kc_nut(wv, widx, bunch_tri, cent)
	if nut_tri.is_empty():
		nut_tri = bunch_tri
		print("BAKE king_coconut: nut carve FAILED — single falls back to the whole bunch")
	# --- BUILD BOTH MESHES ---
	var bunch_mesh := _commit_kc_mesh(wv, wn, wu, widx, bunch_tri, mat, 0.45)
	var single_mesh := _commit_kc_mesh(wv, wn, wu, widx, nut_tri, mat, 0.12)
	var okb := ResourceSaver.save(bunch_mesh, OUT_DIR + "/coconut_bunch.res") == OK
	var oks := ResourceSaver.save(single_mesh, OUT_DIR + "/coconut_single.res") == OK
	print("BAKE king_coconut: bunch %d tris / single %d tris" % [bunch_tri.size(), nut_tri.size()])
	return okb and oks

## GREEDY BALL-CARVE: grow balls from uncovered triangle centroids; each
## ball claims every uncovered centroid within radius r — one ball ≈ one
## nut interior (a nut's own triangles cluster tightly around its center;
## neighbor nuts' interiors are a nut-diameter away). Probe data: a nut is
## ~108 of the bunch's 1176 tris (bunch ≈ 11 nuts), so the winning radius
## is the one whose ball count lands nearest 10-11. The LARGEST ball is
## the most complete single nut; we take exactly ITS CLAIMED triangles
## (never a sphere grab — that re-attaches neighbor fragments).
func _carve_kc_nut(wv: PackedVector3Array, widx: PackedInt32Array, bunch_tri: PackedInt32Array,
		cent: PackedVector3Array) -> PackedInt32Array:
	var best_tri := PackedInt32Array()
	var best_score := 1e9 # combined: ball-count fit + nut-size fit
	var nut_share := float(bunch_tri.size()) / 11.0 # ~107 tris per real nut
	for r in [4.5, 5.5, 6.5, 7.5, 8.5, 10.0, 12.0]:
		var covered := PackedByteArray()
		covered.resize(bunch_tri.size())
		var owner := PackedInt32Array() # tri idx -> ball idx
		owner.resize(bunch_tri.size())
		owner.fill(-1)
		var balls: Array = [] # [seed_tri_idx, count]
		for i in bunch_tri.size():
			if covered[i] == 1:
				continue
			var cnt := 0
			var c0 := cent[i]
			for j in range(i, bunch_tri.size()):
				if covered[j] == 0 and cent[j].distance_to(c0) < r:
					covered[j] = 1
					owner[j] = balls.size()
					cnt += 1
			balls.append([i, cnt])
		if balls.size() < 3:
			continue
		var big_id := 0
		for b in balls.size():
			if int(balls[b][1]) > int(balls[big_id][1]):
				big_id = b
		var big_n := int(balls[big_id][1])
		# NUT-SIZE fit rules (ball count only tiebreaks): the largest ball
		# must hold about ONE nut's share of the tris — at wide radii the
		# count can match a real bunch while each ball fuses 2-3 nuts.
		var score := absf(float(big_n) - nut_share) + absf(float(balls.size()) - 10.5) * 0.3
		print("BAKE king_coconut: carve r=%.1f -> %d balls, biggest %d tris (score %.1f)" % [r, balls.size(), big_n, score])
		if score < best_score:
			best_score = score
			var claimed := PackedInt32Array()
			for j in bunch_tri.size():
				if owner[j] == big_id:
					claimed.append(j)
			# PATCH THE FAR SIDE: the greedy pass may hand this nut's
			# back-shell tris to an earlier-seeded neighbor ball. Re-add every
			# UNCLAIMED tri inside this nut's own bounding sphere (grown 15%);
			# neighbor nuts start a nut-diameter away and stay excluded.
			var ctr := Vector3.ZERO
			for j in claimed:
				ctr += cent[j]
			ctr /= float(claimed.size())
			var rad := 0.0
			for j in claimed:
				rad = maxf(rad, cent[j].distance_to(ctr))
			var out := PackedInt32Array(claimed)
			for j in bunch_tri.size():
				if owner[j] < 0 and cent[j].distance_to(ctr) < rad * 1.15:
					out.append(bunch_tri[j])
			best_tri = out
	if best_tri.size() < 40:
		return PackedInt32Array()
	print("BAKE king_coconut: best nut ball = %d tris (patched)" % best_tri.size())
	return best_tri

## Shared SurfaceTool commit for a king-coconut part: scale to target height,
## pivot at the TOP (hang/fall rotate naturally), keep normals/UVs/tangents
## and the real kc_HP1 material (texture downscaled like the apple's).
func _commit_kc_mesh(wv: PackedVector3Array, wn: PackedVector3Array, wu: PackedVector2Array,
		widx: PackedInt32Array, tris: PackedInt32Array, mat: Material, target_h: float) -> ArrayMesh:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for j in tris.size():
		for k in 3:
			var v := wv[widx[tris[j] * 3 + k]]
			lo = lo.min(v)
			hi = hi.max(v)
	var s := target_h / maxf(maxf(hi.y - lo.y, hi.x - lo.x), hi.z - lo.z)
	var nxf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-(lo.x + hi.x) * 0.5 * s, -hi.y * s, -(lo.z + hi.z) * 0.5 * s))
	var nb := nxf.basis.inverse().transposed()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# WELDED arrays only: tri indices reference wv/wn/wu — indexing the raw
	# `verts` here scrambled the geometry (the pass-22 AABB lie).
	for j in tris.size():
		for k in 3:
			var vi := widx[tris[j] * 3 + k]
			if wu.size() > vi:
				st.set_uv(wu[vi])
			if wn.size() > vi:
				st.set_normal((nb * wn[vi]).normalized())
			st.add_vertex(nxf * wv[vi])
	if not wu.is_empty() and not wn.is_empty():
		st.generate_tangents()
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)
	if mat != null:
		out.surface_set_material(0, _baked_apple_material(mat))
	return out

## Downscale the material's albedo/normal/roughness textures to <= max_tex px
## and return the same material (textures are resources; re-saving the smaller
## Image into the material keeps quality at a fraction of the VRAM).
## (max_tex parameter added for the mobile bake; normal/roughness are now
## capped too — the old albedo-only pass left full-size detail maps embedded.)
func _baked_apple_material(m: Material, max_tex: int = APPLE_MAX_TEX) -> Material:
	if not (m is BaseMaterial3D):
		return m
	var bm := m as BaseMaterial3D
	for prop in ["albedo_texture", "normal_texture", "roughness_texture"]:
		var t: Texture2D = bm.get(prop)
		if t is ImageTexture or t is CompressedTexture2D:
			var img: Image = t.get_image()
			if img != null and maxi(img.get_width(), img.get_height()) > max_tex:
				img.resize(max_tex, max_tex, Image.INTERPOLATE_LANCZOS)
				if img.is_compressed():
					img.decompress()
				bm.set(prop, ImageTexture.create_from_image(img))
	return bm

## Build the MOBILE apple variant from the already-decimated full surfaces:
## whole-card leaf cull down to `leaf_budget` tris + a second meshopt pass
## on the bark/twig skins (never random triangle drops — see the v2 notes).
## Returns parts shaped like `surf` entries: [arrays, material, tris_kept].
func _lighten_apple_parts(parts: Array, leaf_budget: int, bark_ratio: float) -> Array:
	var out: Array = []
	for e in parts:
		var arrays: Array = e[0]
		var m: Material = e[1]
		var nm := m.resource_name if m != null else ""
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i in idx.size():
				idx[i] = i
		var kept_idx := idx
		if nm.containsn("leaf"):
			kept_idx = _cull_leaf_components(idx, leaf_budget)
		else:
			kept_idx = _simplify_skin(idx, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_TEX_UV], bark_ratio)
		var a := arrays.duplicate()
		a[Mesh.ARRAY_INDEX] = kept_idx
		out.append([a, m, kept_idx.size() / 3])
		print("BAKE apple-mobile surf %s: kept %d/%d tris" % [nm, kept_idx.size() / 3, idx.size() / 3])
	return out

# ------------------------------------------------------------
# SCANNED PLANTS — models/scanned_plants_and_grass_free_download.glb is a
# photogrammetry LIBRARY (17 specimens, ~190k tris total). Bake the four
# best specimens into small, field-ready clumps:
#
#   scan_tuft.tres        Object_5  Grass_Blades tuft      (~120 tris)
#   scan_dandelion.tres   Object_7  dandelion weed        (~115 tris)
#   scan_groundcover.tres Object_8  leafy ground cover    (21k -> ~1.3k)
#   scan_flower.tres      Object_17 purple flower bush    (7k  -> ~1.1k)
#
# Each is scaled to a target height, re-pivoted (base at y=0, centered on
# XZ) and decimated. The specimen's IMPORTED material (albedo texture +
# alpha scissor) is embedded as-is: the MultiMesh grass field overrides it
# with grass_wind.gdshader at runtime, and props (bushes) render with the
# real scanned texture without needing MultiMesh custom data.
# ------------------------------------------------------------

func _bake_scan_plants() -> bool:
	var ps: PackedScene = load(SCAN_SRC)
	if ps == null:
		push_error("bake: cannot load " + SCAN_SRC)
		return false
	var inst := ps.instantiate()
	# Collect every mesh with its accumulated transform.
	var meshes := {} # name -> [mesh, xf]
	var stack: Array = [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes[String(n.name)] = [(n as MeshInstance3D).mesh, xf]
		for c in n.get_children():
			stack.append([c, xf])
	inst.free()

	# name, source node, target height (m), keep fraction of triangles
	var specs := [
		["scan_tuft", "Object_5", 0.35, 1.0],
		["scan_dandelion", "Object_7", 0.70, 1.0],
		["scan_groundcover", "Object_8", 0.45, 0.06],
		["scan_flower", "Object_17", 0.50, 0.15],
	]
	var ok_all := true
	for spec in specs:
		ok_all = _bake_one_scan(spec[0], spec[1], spec[2], spec[3], meshes) and ok_all
	return ok_all

func _bake_one_scan(out_name: String, node_name: String, target_h: float,
		keep: float, meshes: Dictionary) -> bool:
	if not meshes.has(node_name):
		push_error("bake: %s has no node %s" % [SCAN_SRC, node_name])
		return false
	var entry: Array = meshes[node_name]
	var src_mesh: Mesh = entry[0]
	var xf: Transform3D = entry[1]
	var arrays := src_mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		push_error("bake: %s surface unreadable" % node_name)
		return false
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i

	# 1) transform to world, 2) uniform-scale to target height,
	# 3) re-pivot: base at y=0, XZ centered.
	var wverts := PackedVector3Array()
	wverts.resize(verts.size())
	var wnorms := PackedVector3Array()
	wnorms.resize(norms.size())
	var nb := xf.basis.inverse().transposed() # normal matrix
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in verts.size():
		var v := xf * verts[i]
		wverts[i] = v
		lo = lo.min(v)
		hi = hi.max(v)
		if norms.size() > i:
			wnorms[i] = (nb * norms[i]).normalized()
	var s := target_h / maxf(hi.y - lo.y, 0.001)
	var ctr := (lo + hi) * 0.5
	var post := Transform3D(Basis.from_scale(Vector3.ONE * s),
		Vector3(-ctr.x * s, -lo.y * s, -ctr.z * s))
	for i in wverts.size():
		wverts[i] = post * wverts[i]

	# Decimate by deterministic triangle hash (scans have massive overlap).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept := 0
	var total := idx.size() / 3
	var seed_off := int(node_name.hash() & 0xffff)
	for t in total:
		if keep < 1.0 and _hash01(t + seed_off) > keep:
			continue
		for k in 3:
			var vi := idx[t * 3 + k]
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			if wnorms.size() > vi:
				st.set_normal(wnorms[vi])
			st.add_vertex(wverts[vi])
		kept += 1
	if not uvs.is_empty() and not wnorms.is_empty():
		st.generate_tangents()
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)

	# Keep the specimen's imported material (real scanned albedo + alpha
	# scissor). The grass field overrides it with the wind shader; props use it directly.
	var src_mat := src_mesh.surface_get_material(0)
	var tex_saved := 0
	if src_mat != null:
		out.surface_set_material(0, src_mat)
	if src_mat is BaseMaterial3D:
		var bm := src_mat as BaseMaterial3D
		if bm.albedo_texture != null:
			var img: Image = bm.albedo_texture.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				var p := "%s/%s_albedo.png" % [OUT_DIR, out_name]
				if img.save_png(p) == OK:
					tex_saved += 1

	out.set_meta("src", SCAN_SRC)
	out.set_meta("node", node_name)
	out.set_meta("tris_kept", kept)
	out.set_meta("tris_total", total)
	var aabb := out.get_aabb()
	print("BAKE scan %s: %d/%d tris, aabb=%s..%s, tex=%d" % [
		out_name, kept, total, aabb.position, aabb.position + aabb.size, tex_saved])
	var err := ResourceSaver.save(out, "%s/%s.res" % [OUT_DIR, out_name])
	if err != OK:
		push_error("bake: saving %s failed (%d)" % [out_name, err])
		return false
	return true

# ------------------------------------------------------------
# COCONUT GROWTH VARIANTS — planted palms (plant_instance.gd) grow through
# three REAL-model stages baked from the same coconut_palm.glb scan:
#
#   coconut_sprout.tres  a few fronds only, ~0.8 m  (seed/sprout stage)
#   coconut_young.tres   short trunk + young crown, ~2.6 m (growing stage)
#   coconut_mature.tres  full palm ~4.5 m, NO coconuts (mature stage; fruits
#                        are grown separately by plant_instance fruit slots)
#   (also: the same variants get the palm sway shader on fronds at runtime,
#   so young trees already sway gently in the wind)
#
# The hanging nut cluster in the alpha surface (y < 3.5) is dropped in every
# variant so planted trees only show fruit via the ripening slots.
# ------------------------------------------------------------
const PALM_BAKED := "res://grass/baked/palm_island.res"
const PALM_CROWN_CUT_Y := 3.5 # below this the alpha surface is the nut cluster

func _bake_palm_growth() -> bool:
	if not ResourceLoader.exists(PALM_BAKED):
		push_error("bake: %s missing (palm bake must run first)" % PALM_BAKED)
		return false
	var full := load(PALM_BAKED) as ArrayMesh
	if full == null or full.get_surface_count() < 5:
		push_error("bake: palm_island.tres unreadable")
		return false
	# Surface order from the palm bake log: 0=Tree_4, 1=Tree_3, 2=Tree_2
	# (alpha fronds+nuts), 3=Tree_1, 4=Tree_0 (trunk).
	var surf_arrays: Array = []
	var surf_mats: Array = []
	for s in full.get_surface_count():
		surf_arrays.append(full.surface_get_arrays(s))
		surf_mats.append(full.surface_get_material(s))

	var fronds_cut: Variant = _cut_above(surf_arrays[2], surf_mats[2], PALM_CROWN_CUT_Y)
	if fronds_cut == null:
		push_error("bake: frond cut produced nothing")
		return false
	var crown_parts: Array = [[surf_arrays[0], surf_mats[0]], [surf_arrays[1], surf_mats[1]],
		[fronds_cut, surf_mats[2]], [surf_arrays[3], surf_mats[3]]]
	var trunk_part: Array = [surf_arrays[4], surf_mats[4]]

	var ok := true
	# SPROUT: only 3-4 fronds (a ~140° sector of the crown), 0.8 m tall.
	var sprout_cut: Variant = _cut_above(surf_arrays[2], surf_mats[2], PALM_CROWN_CUT_Y, 0.9, 2.4)
	if sprout_cut == null:
		push_error("bake: sprout frond subset produced nothing")
		return false
	ok = _bake_growth_variant("coconut_sprout", [[sprout_cut, surf_mats[2]]], 0.8) and ok
	# YOUNG: trunk scaled to 2.6 m, crown riding on its top.
	ok = _bake_growth_variant("coconut_young", [trunk_part] + crown_parts, 2.6) and ok
	# MATURE: everything at 72% (6.3 m scan -> 4.5 m, raft-scale).
	ok = _bake_growth_variant("coconut_mature", [trunk_part] + crown_parts, 4.5) and ok
	return ok

## Keeps only the triangles of a surface whose THREE vertices are all above
## y_cut. With sector_start/sector_len > 0, additionally keeps only triangles
## whose centroid angle (atan2(z, x)) falls inside that radial sector — used
## to slice 3-4 individual fronds out of the crown for the sprout variant.
## Returns arrays (or null when nothing survives).
func _cut_above(arrays: Array, mat: Material, y_cut: float,
		sector_start := -1.0, sector_len := 0.0) -> Variant:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return null
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept := 0
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		if verts[a].y < y_cut or verts[b].y < y_cut or verts[c].y < y_cut:
			continue
		if sector_len > 0.0:
			var ctr := (verts[a] + verts[b] + verts[c]) / 3.0
			var ang := fposmod(atan2(ctr.z, ctr.x) - sector_start, TAU)
			if ang > sector_len:
				continue
		for vi in [a, b, c]:
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			if norms.size() > vi:
				st.set_normal(norms[vi])
			st.add_vertex(verts[vi])
		kept += 1
	if kept == 0:
		return null
	if not uvs.is_empty() and not norms.is_empty():
		st.generate_tangents()
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)
	if mat != null:
		out.surface_set_material(0, mat)
	if sector_len > 0.0:
		print("BAKE palm growth: frond sector cut kept %d tris (y > %.1f, sector %.1f+%.1f)" % [kept, y_cut, sector_start, sector_len])
	else:
		print("BAKE palm growth: frond cut kept %d tris (y > %.1f)" % [kept, y_cut])
	return out.surface_get_arrays(0)

## Compose one growth variant. parts = [ [arrays, material], ... ] in source
## palm world space; the whole set is uniformly scaled so the total height
## becomes target_h, with the trunk base at y=0. Crown parts (anything that
## was above the trunk) are lifted so they sit on the SCALED trunk top.
func _bake_growth_variant(out_name: String, parts: Array, target_h: float) -> bool:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for part in parts:
		var verts: PackedVector3Array = part[0][Mesh.ARRAY_VERTEX]
		for v in verts:
			lo = lo.min(v)
			hi = hi.max(v)
	var src_h := maxf(hi.y - lo.y, 0.001)
	var s := target_h / src_h
	# Full-model scale: everything shrinks toward the trunk base, then the
	# lowest surviving vertex is dropped onto y = 0 (frond-only variants have
	# their base up at crown height in source space).
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0.0, -lo.y * s, 0.0))
	var out := ArrayMesh.new()
	var total_kept := 0
	for part in parts:
		var arrays: Array = part[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var nb := xf.basis.inverse().transposed()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in idx.size() / 3:
			for k in 3:
				var vi := idx[t * 3 + k]
				if uvs.size() > vi:
					st.set_uv(uvs[vi])
				if norms.size() > vi:
					st.set_normal((nb * norms[vi]).normalized())
				st.add_vertex(xf * verts[vi])
		total_kept += idx.size() / 3
		if not uvs.is_empty() and not norms.is_empty():
			st.generate_tangents()
		st.index()
		var before := out.get_surface_count()
		st.commit(out)
		var mat: Material = part[1]
		if mat != null:
			out.surface_set_material(before, mat)
	out.set_meta("src", PALM_BAKED)
	out.set_meta("height", target_h)
	var aabb := out.get_aabb()
	print("BAKE palm growth %s: %d tris, %.2f m tall, %d surfaces" % [
		out_name, total_kept, aabb.position.y + aabb.size.y, out.get_surface_count()])
	var err := ResourceSaver.save(out, "%s/%s.res" % [OUT_DIR, out_name])
	if err != OK:
		push_error("bake: saving %s failed (%d)" % [out_name, err])
		return false
	return true

func _find_mi(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _find_mi(c)
		if r != null:
			return r
	return null
