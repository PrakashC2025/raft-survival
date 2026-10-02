extends Node
## HSV/hue-census of the spawn lagoon view, DESKTOP reference run.
## Saves the screenshot + prints a hue histogram of the frame's mid band
## plus a per-tile hue map. Evidence for calibrating the grass-visible
## classifier (warm sun + olive grass defeat naive g>r rules).
## Run (DESKTOP, no env vars):
##   godot --path . --resolution 1152x648 res://tools/hsv_probe_scene.tscn

var _game: Node = null
var _settle := 0

func _ready() -> void:
	var main: PackedScene = load("res://scenes/main.tscn")
	if main == null:
		push_error("hsv_probe: main.tscn did not load")
		get_tree().quit(1)
		return
	_game = main.instantiate()
	add_child(_game)

func _process(_delta: float) -> void:
	if get_tree().get_first_node_in_group("island") == null:
		return
	_settle += 1
	if _settle == 90:
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("hsv_probe FAIL: no viewport image")
			get_tree().quit(1)
			return
		img.flip_y()
		var path := OS.get_user_data_dir() + "/hsv_probe.png"
		img.save_png(path)
		var w := img.get_width()
		var h := img.get_height()
		# Hue census of the mid band (where terrain usually is).
		var bins := []
		for i in 12:
			bins.append(0)
		var gray := 0
		var dark := 0
		var n := 0
		for y in range(int(h * 0.30), int(h * 0.85), 2):
			for x in range(int(w * 0.10), int(w * 0.90), 2):
				var c := img.get_pixel(x, y)
				n += 1
				if c.v < 0.10:
					dark += 1
				elif c.s < 0.12:
					gray += 1
				else:
					var deg := int(c.h * 360.0) % 360
					bins[deg / 30] += 1
		var names := ["RED 0-30", "ORG 30-60", "YEL 60-90", "YGR 90-120", "GRN 120-150", "GRN2 150-180", "CYN 180-210", "AZU 210-240", "BLU 240-270", "PUR 270-300", "MAG 300-330", "PNK 330-360"]
		print("hsv_probe mid-band census (%d px, saved %s):" % [n, path])
		for i in 12:
			print("  %s: %d (%.1f%%)" % [names[i], bins[i], 100.0 * bins[i] / max(n, 1)])
		print("  low-sat(gray/white): %d (%.1f%%), dark: %d (%.1f%%)" % [gray, 100.0 * gray / max(n, 1), dark, 100.0 * dark / max(n, 1)])
		# Per-tile dominant hue name for a 8x5 grid.
		var grid := ""
		for ty in 5:
			var row := ""
			for tx in 8:
				var hh2 := 0.0
				var s2 := 0.0
				var v2 := 0.0
				var c2 := img.get_pixel(int(w * (tx + 0.5) / 8.0), int(h * (ty + 0.5) / 5.0))
				var deg := int(c2.h * 360.0) % 360
				var tag := "%03d" % deg
				if c2.v < 0.10:
					tag = "Drk"
				elif c2.s < 0.12:
					tag = "Gry"
				row += " " + tag
			grid += "\n  " + row
		print("hsv_probe tile hues (deg, top->bottom):" + grid)
		get_tree().quit(0)
