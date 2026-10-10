extends SceneTree
## Actual game water/sky, without starting world generation or changing saves.
var checks := 0
var failures := 0
var camera: Camera3D
var ocean: MeshInstance3D
var clock: Node
var atmosphere: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)

func frames(count: int) -> void:
	for unused in count: await process_frame

func photo_sky(label: String, hour: float) -> void:
	clock.set("current_time", hour); clock.call("_update_celestial_coords")
	clock.get_node("Timer").emit_signal("timeout"); atmosphere.call("_process", 1.0)
	var dome := current_scene.get_node("Sky3D/SkyDome")
	var material: ShaderMaterial = dome.get("sky_material")
	var night := label == "night"
	var direction: Vector3 = (dome.get("_moon_transform" if night else "_sun_transform") as Transform3D).origin
	camera.global_position = Vector3(0, 3, 0)
	var aim_direction := direction
	aim_direction.y *= 0.65 if night else (1.0 if label == "afternoon" else 1.25)
	camera.look_at(camera.global_position + aim_direction * 100)
	camera.rotate_y(0.18)
	await frames(12)
	check(bool(material.get_shader_parameter("calm_night_enabled")) and material.get_shader_parameter("night_clouds") is Texture2D, "Simple night sky and moving clouds are enabled")
	check(float(material.get_shader_parameter("morning_panorama_blend")) > 0.1 if label == "morning" else float(material.get_shader_parameter("morning_panorama_blend")) < 0.001, "Morning clouds follow the existing time: " + label)
	if not "--preview" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	var prefix := "C:/GodotProjects/raft-survival/build/sky-reference-" + str(RenderingServer.get_current_rendering_method())
	if night: prefix = "C:/GodotProjects/raft-survival/build/sky-calm-" + str(RenderingServer.get_current_rendering_method())
	check(before.save_png(prefix + "-" + label + ".png") == OK, "Rendered reference " + label)
	if not night: return
	var moon_point := camera.unproject_position(camera.global_position + direction * 100)
	check(Rect2(Vector2(70, 70), Vector2(root.size) - Vector2(140, 140)).has_point(moon_point), "Detailed full moon stays inside the night view")
	var moon_pixel := Vector2i(moon_point)
	var moon_light := before.get_pixelv(moon_pixel)
	check(moon_light.r > 0.65 and moon_light.b > 0.75, "Reference moon has a bright readable centre")
	# Move only the existing wind/cloud animation, keeping the celestial time fixed.
	var cirrus_was_visible: bool = dome.get("cirrus_visible")
	var cumulus_was_visible: bool = dome.get("cumulus_visible")
	dome.set("cirrus_visible", false); dome.set("cumulus_visible", false)
	check(dome.is_physics_processing() or dome.is_processing(), "Photo clouds stay animated when both procedural layers are disabled")
	dome.set_process(false); dome.set_physics_process(false)
	var cloud_before: Vector2 = material.get_shader_parameter("panorama_cloud_position")
	dome.call("process_tick", 10.0)
	check((material.get_shader_parameter("panorama_cloud_position") as Vector2).distance_to(cloud_before) > 0.01, "Photographic clouds move even with mobile volumetric cumulus disabled")
	check((dome.get("_moon_transform") as Transform3D).origin.is_equal_approx(direction), "Cloud motion does not move or duplicate the moon")
	await frames(8); await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	var changed := 0
	for y in range(280, 570, 8):
		for x in range(200, 1050, 8):
			var a := before.get_pixel(x, y); var b := after.get_pixel(x, y)
			if absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b) > 0.02: changed += 1
	check(changed > 30, "Ten seconds of gentle cloud drift visibly changes the night sky")
	check(after.save_png(prefix + "-night-clouds-moved.png") == OK, "Rendered independent cloud movement")
	# Check the actual clear sky without clouds masking a dense star layer.
	var cloud_opacity: float = material.get_shader_parameter("night_cloud_opacity")
	material.set_shader_parameter("night_cloud_opacity", 0.0)
	await frames(4); await RenderingServer.frame_post_draw
	var clear_sky := root.get_texture().get_image()
	var bright_points := 0
	var cloud_pixels := 0
	var sky_pixels := 0
	for y in range(60, 500):
		for x in range(140, 1140):
			if Vector2(x, y).distance_squared_to(moon_point) < 150.0 * 150.0: continue
			var point_colour := clear_sky.get_pixel(x, y)
			if point_colour.r > 0.28 and point_colour.b > 0.40: bright_points += 1
			var cloudy_colour := after.get_pixel(x, y)
			if maxf(absf(point_colour.r-cloudy_colour.r), maxf(absf(point_colour.g-cloudy_colour.g), absf(point_colour.b-cloudy_colour.b))) > 0.04: cloud_pixels += 1
			sky_pixels += 1
	print("CALM NIGHT bright star pixels away from moon: ", bright_points)
	check(bright_points > 0 and bright_points < 400, "Night keeps a few faint stars without a luminous galaxy or crowded field")
	print("CALM NIGHT visible cloud coverage: ", float(cloud_pixels) / sky_pixels)
	check(cloud_pixels > 50 and float(cloud_pixels) / sky_pixels < 0.25, "Most night sky stays clear with only sparse soft clouds")
	material.set_shader_parameter("night_cloud_opacity", cloud_opacity)
	dome.set("cirrus_visible", cirrus_was_visible); dome.set("cumulus_visible", cumulus_was_visible)
	dome.call("_check_cloud_processing")

func shot(label: String, hour: float, steep: bool = false) -> void:
	clock.set("current_time", hour)
	clock.call("_update_celestial_coords")
	clock.get_node("Timer").emit_signal("timeout")
	atmosphere.call("_process", 1.0)
	camera.global_position = Vector3(0, 3, 0)
	camera.look_at(Vector3(-20, -35 if steep else -3, -90))
	if label == "evening":
		var sun: Vector3 = (current_scene.get_node("Sky3D/SkyDome").get("_sun_transform") as Transform3D).origin
		camera.look_at(camera.global_position + Vector3(sun.x, 0.25, sun.z) * 80)
	await frames(18)
	check(not ocean.get("_diving_background"), "Surface view keeps the sky: " + label)
	var sky_material: ShaderMaterial = current_scene.get_node("Sky3D/SkyDome").get("sky_material")
	check(float(sky_material.get_shader_parameter("evening_blend")) > 0.90 if label == "evening" else float(sky_material.get_shader_parameter("evening_blend")) < 0.001,
		"Evening panorama follows the existing time of day: " + label)
	if not "--preview" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var prefix := "C:/GodotProjects/raft-survival/build/ocean-blue-" + str(RenderingServer.get_current_rendering_method())
	check(picture.save_png(prefix + "-" + label + ".png") == OK, "Rendered " + label)
	if label == "evening":
		var warm := 0
		var blue := 0
		for y in range(60, 420, 6):
			for x in range(160, 1120, 6):
				var pixel := picture.get_pixel(x, y)
				if pixel.r > 0.35 and pixel.r > pixel.g * 1.1 and pixel.g > pixel.b * 1.3: warm += 1
				if pixel.b > pixel.r * 1.2 and pixel.b > pixel.g * 1.05: blue += 1
		check(warm > 800 and blue > 500, "Evening sky has glowing gold/orange clouds and a blue upper sky")
		return
	# The lower central rectangle contains open water, away from the horizon/glints.
	var average := Color(0, 0, 0, 0)
	var dark_pixels := 0
	var count := 0
	for y in range(500, 680, 6):
		for x in range(400, 880, 6):
			var colour := picture.get_pixel(x, y)
			average += colour
			if maxf(colour.r, maxf(colour.g, colour.b)) < 0.12: dark_pixels += 1
			count += 1
	average /= float(count)
	print("WATER DISPLAY ", label, " RGB ", average, " near-black ", dark_pixels, "/", count)
	check(average.b > average.r * 1.35 and average.b > average.g * 1.05, "Surface reads blue: " + label)
	check(average.b > (0.24 if hour == 0 else 0.40) and float(dark_pixels) / count < 0.05, "Surface remains readable instead of black: " + label)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	create_timer(80).timeout.connect(func(): push_error("FAIL: ocean surface timeout"); quit(1))
	root.size = Vector2i(1280, 720)
	root.get_node("Stats").set("enabled", false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	# Keep the game's exact serialized water, sky and atmosphere settings.
	for child in scene.get_children():
		if str(child.name) not in ["Ocean", "Sky3D", "OceanAtmosphere"]:
			scene.remove_child(child); child.free()
	var surface_scene := PackedScene.new()
	check(surface_scene.pack(scene) == OK, "Isolated surface scene retains game water and sky")
	scene.free()
	change_scene_to_packed(surface_scene)
	await scene_changed
	scene = current_scene
	ocean = scene.get_node("Ocean")
	clock = scene.get_node("Sky3D/TimeOfDay")
	atmosphere = scene.get_node("OceanAtmosphere")
	check(is_equal_approx(atmosphere.call("evening_strength", 6.0, 0.0), 0.0), "Golden panorama stays out of dawn")
	check(is_equal_approx(atmosphere.call("evening_strength", 12.0, 0.8), 0.0), "Golden panorama stays out of full daylight")
	check(is_equal_approx(atmosphere.call("evening_strength", 18.0, -0.05), 1.0), "Golden panorama peaks around sunset")
	check(is_equal_approx(atmosphere.call("evening_strength", 20.0, -0.6), 0.0), "Golden panorama gives way to the night sky")
	clock.call("pause"); atmosphere.set_process(false)
	camera = Camera3D.new(); camera.fov = 68
	scene.add_child(camera); camera.current = true
	await frames(20)
	await shot("day", 12.0)
	await shot("near-water", 12.0, true)
	await shot("evening", 18.0)
	await shot("night", 0.0)
	await photo_sky("morning", 7.0)
	await photo_sky("afternoon", 15.0)
	await photo_sky("night", 20.0)
	scene.queue_free(); await frames(8)
	print("OCEAN SURFACE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
