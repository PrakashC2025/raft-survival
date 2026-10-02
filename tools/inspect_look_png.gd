extends SceneTree
## Inspect the saved mobile_look_check.png: what did the camera actually see?
##   godot --headless --path . --script res://tools/inspect_look_png.gd

func _init() -> void:
	var path := OS.get_user_data_dir() + "/mobile_look_check.png"
	var img := Image.load_from_file(path)
	if img == null:
		print("inspect: could not load %s" % path)
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	print("inspect: %dx%d" % [w, h])
	# 8x5 tile classification: what dominates each region?
	var classes := ["SKY", "WATER", "SAND", "GREEN", "DARK", "GRAY"]
	var grid := ""
	for ty in 5:
		var row := ""
		for tx in 8:
			var counts := {"SKY": 0, "WATER": 0, "SAND": 0, "GREEN": 0, "DARK": 0, "GRAY": 0}
			for y in range(int(h * ty / 5.0), int(h * (ty + 1) / 5.0), 3):
				for x in range(int(w * tx / 8.0), int(w * (tx + 1) / 8.0), 3):
					var c := img.get_pixel(x, y)
					var l := c.get_luminance()
					if l < 0.07:
						counts["DARK"] += 1
					elif c.b > 0.45 and c.b >= c.g and c.b > c.r:
						counts["SKY" if l > 0.5 else "WATER"] += 1
					elif c.g > c.r * 1.06 and c.g > c.b * 1.08:
						counts["GREEN"] += 1
					elif c.r > c.g * 1.12 and l > 0.25:
						counts["SAND"] += 1
					else:
						counts["GRAY"] += 1
			var best := "GRAY"
			var bv := -1
			for k in counts:
				if counts[k] > bv:
					bv = counts[k]
					best = k
			var tag: String = best.substr(0, 2)
			row += " %s" % tag
		grid += "\n  " + row
	print("tile classes (top->bottom):" + grid)
	# Overall means
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	var n := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c2 := img.get_pixel(x, y)
			rs += c2.r
			gs += c2.g
			bs += c2.b
			n += 1
	print("mean RGB: %.3f %.3f %.3f" % [rs / n, gs / n, bs / n])
	quit(0)
