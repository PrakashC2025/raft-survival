extends Node
## Night render check: runs the REAL game as a child scene (autoloads load
## normally because this is a scene, not a --script run), jumps to deep
## night, screenshots, and measures blown-out (near-white) pixels in the
## scene band where the island/trees render. The old palm shader lit whole
## fronds white under the moon; this guards against regressions.
## Run (windowed, real autoloads):
##   godot --path . --resolution 1152x648 res://tools/night_check_scene.tscn

var _frames := 0
var _done := false
var _game: Node = null

func _ready() -> void:
	var main: PackedScene = load("res://scenes/main.tscn")
	if main == null:
		push_error("night_check: main.tscn did not load")
		get_tree().quit(1)
		return
	_game = main.instantiate()
	add_child(_game)

func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames == 5:
		# Force deep night: 00:24 — moon up, sun far below the horizon.
		var sky3d := _game.get_node_or_null("Sky3D")
		if sky3d != null:
			sky3d.set("current_time", 0.4)
			print("night_check: time forced to 00:24")
		else:
			push_warning("night_check: Sky3D not found")
	if _frames == 100:
		_done = true
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("night_check FAIL: no viewport image")
			get_tree().quit(1)
			return
		img.flip_y()
		var path := OS.get_user_data_dir() + "/night_check.png"
		img.save_png(path)
		var w := img.get_width()
		var h := img.get_height()
		var blown := 0
		var total := 0
		for y in range(int(h * 0.25), int(h * 0.75), 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				total += 1
				# near-white AND near-gray: moon-blown pixels lose their hue
				if c.r > 0.85 and c.g > 0.85 and c.b > 0.85 \
						and absf(c.r - c.g) < 0.06 and absf(c.g - c.b) < 0.06:
					blown += 1
		var pct := 100.0 * float(blown) / float(maxi(total, 1))
		print("night_check: blown-out white pixels %.2f%% (%d/%d)" % [pct, blown, total])
		print("night_check screenshot: %s" % path)
		if pct > 3.0:
			print("night_check FAIL: scene has blown-out whites at night")
			get_tree().quit(1)
		else:
			print("night_check OK: night rendering within bounds")
			get_tree().quit(0)
