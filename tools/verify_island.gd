extends SceneTree
## Headless island verification:
##   godot --headless --path . --script tools/verify_island.gd
## Checks: terrain field continuity (no NaN/holes), coastline radius,
## water/beach band sanity, pond containment, and that main.tscn
## still loads after the rewiring.

func _init() -> void:
	var failures := 0
	var gen_script := load("res://scripts/island_generator.gd")
	if gen_script == null:
		push_error("FAIL: island_generator.gd did not load")
		quit(1)
		return

	# 1. Terrain field: finite everywhere, land above water, deep seabed.
	var island_origin := Vector2(60.0, 40.0)
	var max_h := -1e9
	var min_h := 1e9
	var nan_count := 0
	var samples := 0
	for x in range(-130, 131, 2):
		for z in range(-130, 131, 2):
			var h: float = gen_script.terrain_height_local(Vector2(x, z))
			samples += 1
			if is_nan(h) or is_inf(h):
				nan_count += 1
				continue
			max_h = maxf(max_h, h)
			min_h = minf(min_h, h)
	if nan_count > 0:
		print("FAIL: %d NaN/Inf height samples" % nan_count)
		failures += 1
	else:
		print("OK: height field finite over %d samples (h %.2f .. %.2f)" % [samples, min_h, max_h])
	if max_h < 8.0:
		print("FAIL: central hill too low (max %.2f)" % max_h)
		failures += 1
	else:
		print("OK: central hill reaches %.2f m" % max_h)

	# 2. Coastline: height crosses y=0 near R_SHORE along many rays.
	var r_shore: float = gen_script.R_SHORE
	var worst := 0.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dirv := Vector2(cos(a), sin(a))
		var found := -1.0
		for rr in range(10, 61):
			var q := dirv * float(rr)
			var h0: float = gen_script.terrain_height_local(q)
			var h1: float = gen_script.terrain_height_local(dirv * float(rr + 1))
			if h0 > 0.0 and h1 <= 0.0:
				found = float(rr)
				break
			elif h0 <= 0.0:
				break
		if found < 0.0:
			print("FAIL: no coastline found on ray %d" % i)
			failures += 1
			continue
		worst = maxf(worst, absf(found - r_shore))
	if worst > 12.0:
		print("FAIL: coastline deviates %.1f m from R_SHORE" % worst)
		failures += 1
	else:
		print("OK: coastline crosses y=0 within %.1f m of r=%d on all rays (irregular by design)" % [worst, int(r_shore)])

	# 3. Beach band: at r = R_SHORE - 4 terrain should be walkable (0 < h < 6).
	var beach_ok := true
	for i in 8:
		var a := TAU * float(i) / 8.0
		var q := Vector2(cos(a), sin(a)) * (r_shore - 4.0)
		var h: float = gen_script.terrain_height_local(q)
		if h <= 0.05 or h > 6.0:
			beach_ok = false
			print("  beach band bad at angle %d: h=%.2f" % [i, h])
	if beach_ok:
		print("OK: beach band walkable (0 < h < 6) on all sampled angles")
	else:
		print("FAIL: beach band issues above")
		failures += 1

	# 4. Pond: bowl must sit below its rim all around (contained water).
	# Sample only within the water disc radius (pond_disc_radius); beyond it
	# is the pond's own bank, which is correctly above the water surface.
	var pond_pos: Vector2 = gen_script.POND_POS
	var water_y: float = gen_script.pond_water_height()
	var disc_r: float = gen_script.pond_disc_radius()
	var leaks := 0
	for i in 24:
		var a := TAU * float(i) / 24.0
		for step in 10:
			var rr := (float(step) + 0.5) / 10.0 * disc_r
			var q := pond_pos + Vector2(cos(a), sin(a)) * rr
			if gen_script.terrain_height_local(q) > water_y:
				leaks += 1
				break
	if leaks > 0:
		print("FAIL: pond leaks on %d/24 rays (bowl above water surface)" % leaks)
		failures += 1
	else:
		print("OK: pond contained (water y=%.2f, disc r=%.1f, all 24 rays below rim)" % [water_y, disc_r])

	# 5. main.tscn still loads + has the new wiring.
	var main: PackedScene = load("res://scenes/main.tscn")
	if main == null:
		print("FAIL: main.tscn did not load")
		failures += 1
	else:
		var inst := main.instantiate()
		var island := inst.get_node_or_null("Island")
		var grass := inst.get_node_or_null("Island/IslandGrass")
		var setup := inst.get_node_or_null("IslandSetup")
		if island == null or island.get_script() != gen_script:
			print("FAIL: Island node missing or wrong script")
			failures += 1
		else:
			print("OK: Island node uses island_generator.gd at %s" % str((island as Node3D).position))
		if grass == null:
			print("FAIL: IslandGrass missing")
			failures += 1
		else:
			print("OK: IslandGrass present (y=%.0f)" % (grass as Node3D).position.y)
		if setup != null:
			print("FAIL: old IslandSetup node still present")
			failures += 1
		else:
			print("OK: IslandSetup removed")
		inst.free()

	# 6. Shader compiles and carries the island uniforms.
	var sh := load("res://shaders/main.gdshader") as Shader
	if sh == null:
		print("FAIL: main.gdshader did not load")
		failures += 1
	else:
		var ok_uniforms := true
		for u in ["island_center", "shore_radius", "outer_radius", "deep_depth",
				"beach_height", "island_active", "foam_rocks", "foam_rock_count"]:
			if not sh.get_shader_uniform_list().any(func(p): return p.name == u):
				print("  missing uniform: %s" % u)
				ok_uniforms = false
		if ok_uniforms:
			print("OK: ocean shader compiles with all island uniforms")
		else:
			failures += 1

	if failures > 0:
		print("RESULT: %d FAILURES" % failures)
		quit(1)
	else:
		print("RESULT: ALL ISLAND CHECKS PASSED")
		quit(0)
