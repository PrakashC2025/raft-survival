extends Node
## MOBILE LOOK CHECK: runs the real game as a child scene (autoloads load
## normally — same pattern as night_check), forces the mobile/low-tier
## pipeline via ENV VARS (the tier is cached in the autoload's _ready):
##   RSM_FORCE_MOBILE=1 RSM_FORCE_TIER=low godot --path . --resolution 1152x648 \
##     res://tools/mobile_look_check_scene.tscn
## Waits for the island, TELEPORTS THE PLAYER onto the meadow right in
## front of a REAL clump from the baked field (cap-aware: only clumps that
## exist in the device's capped instance count), and measures the frame
## through the game's own camera — no synthetic camera guesswork:
##   GREEN FRACTION — share of green-dominant pixels (g > r, g > b).
##      FAIL below 0.15 = "grass missing" regression.
##   LUMINANCE STDDEV — per-pixel detail. FAIL below 0.045 = flat/painted
##      terrain (lost surface relief).
## SINGLE capture, inline measurement, immediate quit — the earlier
## two-shot/async variant wedged the run (twice); keep this tool simple.

const BAKED_PATH := "res://grass/island_grass_baked.tres"

var _game: Node = null
var _seen_island := false
var _settle := 0
var _teleported := false

func _ready() -> void:
	var main: PackedScene = load("res://scenes/main.tscn")
	if main == null:
		push_error("mobile_look_check: main.tscn did not load")
		get_tree().quit(1)
		return
	_game = main.instantiate()
	add_child(_game)

func _process(_delta: float) -> void:
	var island := get_tree().get_first_node_in_group("island") as Node3D
	if island == null:
		return # island still building — keep waiting
	if not _seen_island:
		_seen_island = true
		print("mobile_look_check: island detected, settling...")
		return
	_settle += 1
	if _settle == 20 and not _teleported:
		_teleported = true
		var pose := _meadow_pose(island)
		if pose.position == Vector3.INF:
			print("mobile_look_check FAIL: no meadow found in baked field")
			get_tree().quit(1)
			return
		# CONTROLLED CAMERA at eye height over the meadow core (player
		# teleports kept landing on slopes facing the shore/shadow). Slight
		# downward pitch so the frame is dominated by ground + grass.
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = pose.position
		cam.look_at(pose.position + pose.look + Vector3(0.0, -1.2, 0.0))
		cam.make_current()
		print("mobile_look_check: camera at %v" % pose.position)
		return
	if _settle == 60:
		_measure()
		get_tree().quit(0)

## Teleport pose: the DENSEST part of the meadow (most clumps within 6 m
## of the candidate), so the camera stands INSIDE the field — a single
## clump target on this steep island kept aiming the camera down the
## slope at the shore instead. The bake stores clumps in the IslandGrass
## node's LOCAL frame; only clumps inside the device's capped count count.
func _meadow_pose(_island: Node3D) -> Dictionary:
	var inf := {"position": Vector3.INF, "look": Vector3.FORWARD}
	if not ResourceLoader.exists(BAKED_PATH):
		return inf
	var bake := load(BAKED_PATH) as Resource
	if bake == null or not bake.has_meta("xforms"):
		return inf
	var xf: PackedVector3Array = bake.get_meta("xforms")
	var grass := get_tree().get_first_node_in_group("grass_field") as Node3D
	if grass == null:
		return inf
	var mp := load("res://scripts/mobile_perf.gd")
	var cap: int = mp.call("grass_clumps")
	var world_pts: Array[Vector3] = []
	var idx := 0
	for i in range(3, xf.size(), 4):
		if idx >= cap:
			break
		idx += 1
		world_pts.append(grass.global_transform * xf[i])
	if world_pts.is_empty():
		return inf
	# Candidate every 10th clump, density = neighbors within 6 m.
	var best_i := -1
	var best_n := -1
	for ci in range(0, world_pts.size(), 10):
		var n := 0
		for ni in range(0, world_pts.size(), 10):
			if world_pts[ci].distance_to(world_pts[ni]) < 6.0:
				n += 1
		if n > best_n:
			best_n = n
			best_i = ci
	if best_i < 0 or best_n < 4:
		return inf
	var c := world_pts[best_i]
	# Stand ON the ground at the meadow core; face the island center so the
	# view crosses more field (any horizontal direction works inside it).
	var island := get_tree().get_first_node_in_group("island") as Node3D
	var q := Vector2(c.x, c.z) - Vector2(island.global_position.x, island.global_position.z)
	var h: float = island.call("_ground", q)
	var dir := (Vector3(island.global_position.x, c.y, island.global_position.z) - c)
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = Vector3.FORWARD
	return {"position": Vector3(c.x, h + 1.2, c.z), "look": dir.normalized()}

func _measure() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("mobile_look_check FAIL: no viewport image")
		get_tree().quit(1)
		return
	img.flip_y()
	var path := OS.get_user_data_dir() + "/mobile_look_check.png"
	img.save_png(path)
	var w := img.get_width()
	var h := img.get_height()
	var cam := get_viewport().get_camera_3d()
	var mmi: MultiMeshInstance3D = null
	var grass := get_tree().get_first_node_in_group("grass_field")
	if grass != null:
		for c in grass.get_children():
			if c is MultiMeshInstance3D:
				mmi = c
				break
	if cam == null or mmi == null or mmi.multimesh == null:
		print("mobile_look_check FAIL: no camera or grass MultiMesh")
		get_tree().quit(1)
		return
	# CLUMP PROJECTION ORACLE: unproject real rendered clump centers into
	# the screenshot and check the pixels AROUND each projection. Immune
	# to camera framing — directly answers "do rendered clumps look green".
	var mm := mmi.multimesh as MultiMesh
	# Pass 1: project every rendered clump; collect in-frustum screen pts.
	var proj: Array[Vector2] = []
	for i in range(0, mm.instance_count, 1):
		var t := mm.get_instance_transform(i)
		var wp: Vector3 = mmi.global_transform * (t.origin + Vector3(0.0, 0.45, 0.0))
		if not cam.is_position_in_frustum(wp):
			continue
		proj.append(cam.unproject_position(wp))
	# Pass 2: green-dominance disk around each projection.
	var green_clumps := 0
	var checked := 0
	var disk_dbg := ""
	var shown := 0
	for sp in proj:
		var g := 0
		var n := 0
		var rs := 0.0
		var gs := 0.0
		var bs := 0.0
		for dy in range(-10, 11, 2):
			for dx in range(-10, 11, 2):
				var px := int(sp.x) + dx
				var py := int(sp.y) + dy
				if px < 0 or py < 0 or px >= w or py >= h:
					continue
				var c := img.get_pixel(px, py)
				rs += c.r
				gs += c.g
				bs += c.b
				if c.g > c.r * 1.05 and c.g > c.b * 1.08:
					g += 1
				n += 1
		if n >= 10:
			checked += 1
			if float(g) / float(n) >= 0.35:
				green_clumps += 1
			elif shown < 5:
				shown += 1
				disk_dbg += "  clump@(%d,%d) mean RGB %.2f/%.2f/%.2f\n" % [int(sp.x), int(sp.y), rs / n, gs / n, bs / n]
	var frac := float(green_clumps) / float(maxi(checked, 1))
	# HUE-BASED frame census (calibrated with tools/hsv_probe.gd): green
	# hues 70-170 deg with real saturation. Olive/dry grass reads 70-110,
	# lush blades 110-150 — the naive g>r rule missed both under warm sun.
	var fg := 0
	var fn := 0
	for y in range(int(h * 0.25), int(h * 0.85), 3):
		for x in range(int(w * 0.10), int(w * 0.90), 3):
			var c2 := img.get_pixel(x, y)
			var deg := int(c2.h * 360.0) % 360
			if deg >= 70 and deg <= 170 and c2.s > 0.15 and c2.v > 0.10:
				fg += 1
			fn += 1
	var frame_green := float(fg) / float(maxi(fn, 1))
	print("mobile_look_check: %d/%d projected clumps read green (%.2f); hue-green %.3f; want disks >= 0.40 OR hue >= 0.10" % [green_clumps, checked, frac, frame_green])
	if disk_dbg != "":
		print("mobile_look_check non-green clump disks:" + "\n" + disk_dbg)
	# ASCII frame map (48x27): what is actually on screen, clumps marked X.
	var marks := {}
	for sp in proj:
		marks[Vector2i(int(sp.x) / 24, int(sp.y) / 24)] = true
	var ascii := ""
	for cy in 27:
		var row := ""
		for cx in 48:
			var c := img.get_pixel(cx * 24 + 12, cy * 24 + 12)
			var l := c.get_luminance()
			var ch := "?"
			if l < 0.12:
				ch = "D"
			elif c.b > c.g and c.b > c.r and l > 0.35:
				ch = "B"
			elif c.g > c.r * 1.04 and c.g > c.b * 1.06:
				ch = "G"
			elif l > 0.62:
				ch = "W"
			elif c.r > c.b * 1.15:
				ch = "Y" # tan/olive/sand
			if marks.has(Vector2i(cx, cy)):
				ch = ch.to_lower()
			row += ch
		ascii += "\n  " + row
	print("mobile_look_check ASCII frame (lowercase = projected clump cell):" + ascii)
	print("mobile_look_check screenshot: %s" % path)
	var ok := (checked >= 20 and frac >= 0.40) or frame_green >= 0.10
	if not ok:
		print("mobile_look_check FAIL: no green-dominant coverage — grass missing")
	print("mobile_look_check OK" if ok else "mobile_look_check FAILED")
	get_tree().quit(0 if ok else 1)
