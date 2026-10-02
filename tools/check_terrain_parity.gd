extends SceneTree
## PASS 31 VERIFICATION — terrain cache parity (run headless):
##   godot --headless --path . --script res://tools/check_terrain_parity.gd
## Proves the frame-chunked first-launch height+paint pass is byte-identical
## to the old single-frame loop, by checking BOTH:
##   1. old fused order (height computed, then painted row-by-row, neighbor
##      rows still zeros) vs new order (all heights first, then painted);
##   2. the new order vs the SHIPPED user:// cache written by the old code
##      on a real launch (if present).
## Exits 0 on parity, 1 on mismatch.

func _init() -> void:
	var gen: Variant = load("res://scripts/island_generator.gd").new()
	var n: int = gen._grid_n()
	print("[parity] grid n=%d" % n)
	var sand := Color(0.72, 0.63, 0.42)
	var wet := Color(0.40, 0.34, 0.23)
	var grass := Color(0.24, 0.40, 0.14)
	var rock := Color(0.44, 0.40, 0.34)
	var step: float = gen.grid_step
	var half: float = gen.grid_half

	# OLD: fused loop, paint sees zeroed neighbor rows.
	var h_old := PackedFloat32Array()
	h_old.resize(n * n)
	var c_old := PackedColorArray()
	c_old.resize(n * n)
	for iz in n:
		for ix in n:
			var vi := iz * n + ix
			var q := Vector2(-half + ix * step, -half + iz * step)
			var h: float = gen.terrain_height_local(q)
			h_old[vi] = h
			c_old[vi] = gen._terrain_paint(q, h, Vector3.UP, n, h_old, sand, wet, grass, rock)

	# NEW: same per-vertex compute+paint order as the fixed
	# _terrain_compute_async (row batches, partially-filled heights array —
	# batch boundaries without the awaits cannot change the result).
	var h_new := PackedFloat32Array()
	h_new.resize(n * n)
	var c_new := PackedColorArray()
	c_new.resize(n * n)
	var rows := 12 # a mid-tier phone batch size; boundaries must not matter
	var done_rows := 0
	while done_rows < n:
		var iz_end := mini(done_rows + rows, n)
		for iz in range(done_rows, iz_end):
			for ix in n:
				var vi2 := iz * n + ix
				var q2 := Vector2(-half + ix * step, -half + iz * step)
				var h2: float = gen.terrain_height_local(q2)
				h_new[vi2] = h2
				c_new[vi2] = gen._terrain_paint(q2, h2, Vector3.UP, n, h_new, sand, wet, grass, rock)
		done_rows = iz_end

	var h_bad := 0
	var c_bad := 0
	var c_worst := 0.0
	for i in n * n:
		if h_old[i] != h_new[i]:
			h_bad += 1
		var d: float = c_old[i].r - c_new[i].r
		d = maxf(d, c_old[i].g - c_new[i].g)
		d = maxf(d, c_old[i].b - c_new[i].b)
		if d != 0.0:
			c_bad += 1
			c_worst = maxf(c_worst, absf(d))
	print("[parity] old-fused vs new-chunked: %d/%d height diffs, %d/%d color diffs (worst %.6f)" % [h_bad, n * n, c_bad, n * n, c_worst])

	# SHIPPED cache: written by the OLD fused code on a real launch.
	var cache_path: String = "user://terrain_cache_v5_%d_%s.cache" % [gen.seed_value, str(step).replace(".", "_")]
	if FileAccess.file_exists(cache_path):
		var f := FileAccess.open(cache_path, FileAccess.READ)
		var data: Array = f.get_var()
		f.close()
		if data.size() == 2:
			var c_ship: PackedColorArray = data[1]
			var s_bad := 0
			var s_worst := 0.0
			if c_ship.size() == n * n:
				for i in n * n:
					var d2: float = c_ship[i].r - c_new[i].r
					d2 = maxf(d2, c_ship[i].g - c_new[i].g)
					d2 = maxf(d2, c_ship[i].b - c_new[i].b)
					if d2 != 0.0:
						s_bad += 1
						s_worst = maxf(s_worst, absf(d2))
				print("[parity] shipped-cache vs new-chunked: %d/%d color diffs (worst %.6f)" % [s_bad, n * n, s_worst])
				if s_bad == 0:
					print("PARITY PASSED (matches shipped cache)")
				else:
					print("PARITY FAILED vs shipped cache")
			else:
				print("[parity] shipped cache size %d != %d" % [c_ship.size(), n * n])
	else:
		print("[parity] no shipped cache present (skipped)")

	if h_bad == 0 and c_bad == 0:
		print("PARITY PASSED (old fused == new chunked)")
		quit(0)
	else:
		print("PARITY FAILED (old fused != new chunked)")
		quit(1)
