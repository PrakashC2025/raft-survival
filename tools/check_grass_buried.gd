extends SceneTree
## GRASS BURIAL CHECK: compares every baked clump's y against the CURRENT
## rendered terrain surface at its XZ. If clumps sit systematically BELOW
## the surface, the grass field is buried underground (bake predates a
## terrain change) — the real "grass missing" bug.
##   godot --headless --path . --script res://tools/check_grass_buried.gd

func _init() -> void:
	var bake := load("res://grass/island_grass_baked.tres") as Resource
	if bake == null or not bake.has_meta("xforms"):
		print("buried_check FAIL: no baked field")
		quit(1)
		return
	var xf: PackedVector3Array = bake.get_meta("xforms")
	var IslandGen := load("res://scripts/island_generator.gd")
	# IslandGrass node transform: island sits at (60, 0, 40) in main.tscn;
	# the bake was saved through world_to_local of THAT node. Reconstruct
	# world positions with the same offset.
	var island_pos := Vector3(60.0, 0.0, 40.0)
	var gen: Variant = IslandGen.new()
	var below := 0
	var above := 0
	var total := 0
	var worst := 0.0
	var sum_d := 0.0
	var samples := ""
	for i in range(3, xf.size(), 4):
		var local_o: Vector3 = xf[i]
		var world := island_pos + local_o # grass node has identity rotation/scale
		var q := Vector2(local_o.x, local_o.y) # NOTE: bake local x,y = island-local x,z
		# The bake stores Transform3D origins in the NODE's local space:
		# x = local x, y = local HEIGHT, z = local z.
		q = Vector2(local_o.x, local_o.z)
		var ground: float = gen._rendered_height(q)
		var d: float = ground - local_o.y # >0 = clump is BELOW the surface
		total += 1
		sum_d += d
		if d > 0.05:
			below += 1
			worst = maxf(worst, d)
		elif local_o.y > ground + 0.05:
			above += 1
		if total <= 8:
			samples += "  clump local(%0.1f, %0.2f, %0.1f) ground=%.2f delta=%+.2f\n" % [local_o.x, local_o.y, local_o.z, ground, local_o.y - ground]
	print("buried_check: %d clumps, mean delta %+.2f m, %d below surface (%.1f%%), %d above, worst burial %.2f m" % [total, sum_d / max(total, 1), below, 100.0 * below / max(total, 1), above, worst])
	print(samples)
	if float(below) / max(total, 1) > 0.5:
		print("BURIED CONFIRMED: majority of clumps are under the current terrain — re-bake the grass field")
	elif above > total / 2:
		print("FLOATING: majority of clumps hang above the current terrain — re-bake the grass field")
	else:
		print("FIELD OK: clumps sit on the current surface")
	quit(0)
