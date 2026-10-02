extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("Stats").set("enabled", false)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var player := Node3D.new()
	world.add_child(player)
	player.add_to_group("marker_test_player")
	var beacon := Node3D.new()
	world.add_child(beacon)
	beacon.add_to_group("marker_test_beacon")
	var marker := load("res://scripts/island_marker.gd").new() as Control
	marker.set("player_group", "marker_test_player")
	marker.set("beacon_group", "marker_test_beacon")
	root.add_child(marker)
	marker.set_process(false)
	await process_frame
	var cases := [
		{"label": "Centered island", "point": Vector3(0, 0, -100), "clamped": false},
		{"label": "Right outside frustum", "point": Vector3(1000, 0, -100), "clamped": true},
		{"label": "Left outside frustum", "point": Vector3(-1000, 0, -100), "clamped": true},
		{"label": "Above frustum", "point": Vector3(0, 1000, -100), "clamped": true},
		{"label": "Below frustum", "point": Vector3(0, -1000, -100), "clamped": true},
		{"label": "Directly behind", "point": Vector3(0, 0, 100), "clamped": true},
		{"label": "Behind on diagonal", "point": Vector3(100, 70, 100), "clamped": true},
		{"label": "Beside camera plane", "point": Vector3(100, 0, -0.00001), "clamped": true},
		{"label": "Huge projected coordinate", "point": Vector3(100000000, 0, -0.02), "clamped": true},
	]
	for scenario in cases:
		beacon.global_position = scenario["point"]
		marker.call("_process", 0.016)
		var position := marker.get("_screen_pos") as Vector2
		var rect := Rect2(Vector2.ZERO, Vector2(root.size))
		check(position.is_finite() and rect.has_point(position), scenario["label"] + " produces a finite visible marker")
		check(bool(marker.get("_clamped")) == bool(scenario["clamped"]), scenario["label"] + " uses the correct marker style")
		await process_frame
		await process_frame
	beacon.global_position = Vector3(0, 0, -100)
	marker.call("_process", 0.016)
	check((marker.get("_screen_pos") as Vector2).distance_to(Vector2(root.size) * 0.5) < 0.1, "Centered target stays at screen center")
	beacon.global_position = Vector3(0, 0, -10)
	marker.call("_process", 0.016)
	check(float(marker.get("_alpha")) == 0.0, "Arrived target hides its marker")
	var tiny_view := SubViewport.new()
	tiny_view.size = Vector2i(16, 16)
	tiny_view.own_world_3d = true
	root.add_child(tiny_view)
	world.reparent(tiny_view)
	marker.reparent(tiny_view)
	camera.make_current()
	await process_frame
	beacon.global_position = Vector3(100, 0, -100)
	marker.call("_process", 0.016)
	check(float(marker.get("_alpha")) == 0.0, "Collapsed viewport hides the hint instead of drawing invalid geometry")
	world.reparent(root)
	marker.reparent(root)
	camera.make_current()
	tiny_view.queue_free()
	await process_frame
	marker.set("_screen_pos", Vector2(INF, INF))
	marker.set("_alpha", 1.0)
	marker.queue_redraw()
	await process_frame
	await process_frame
	print("ISLAND MARKER SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
