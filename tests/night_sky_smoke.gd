extends SceneTree

var checks := 0
var failures := 0
var preview := false
var camera: Camera3D
var clock: Node
var dome: Node
var atmosphere: Node
var sky: WorldEnvironment

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("FAIL: night sky timeout"); quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func set_hour(hour: float) -> void:
	clock.set("current_time", hour)
	atmosphere.call("_process", 1.0)

func luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func shot(label: String) -> void:
	if not preview: return
	var direction: Vector3 = (dome.get("_moon_transform") as Transform3D).origin
	camera.global_position = Vector3(0, 2.8, 0)
	camera.look_at(camera.global_position + Vector3(direction.x, direction.y * 0.45, direction.z) * 100.0)
	await frames(16)
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	check(picture.save_png("C:/GodotProjects/raft-survival/build/night-sky-" + label + ".png") == OK, "Rendered " + label)
	var centre := camera.unproject_position(camera.global_position + direction * 100.0)
	check(Rect2(Vector2(20, 20), Vector2(root.size) - Vector2(40, 40)).has_point(centre), "Moon is in the gameplay sky view: " + label)
	var pixel := Vector2i(centre)
	var moon_light := 0.0
	var sky_light := 0.0
	# Its lit side changes with the sun angle; a crescent's centre can be dark.
	# Sample within the disc so visibility checks the actual illuminated surface.
	var offsets := [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8)]
	for offset in offsets:
		moon_light = maxf(moon_light, luminance(picture.get_pixelv(pixel + offset)))
		sky_light += luminance(picture.get_pixelv(pixel + offset + Vector2i(45, 0))) / float(offsets.size())
	check(moon_light > sky_light + 0.12 and moon_light > 0.25, "Visible illuminated moon surface is brighter than surrounding sky: " + label)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	var settings := root.get_node("GameSettings")
	check(settings.day_minutes == 20.0, "Fresh settings use a slower twenty-minute full cycle")
	var inv := root.get_node("Inventory")
	inv.call("new_game_reset", true)
	root.get_node("Stats").enabled = false
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var player := get_first_node_in_group("player")
	player.set_process(false); player.set_physics_process(false)
	await frames(180)
	player.set_process(false); player.set_physics_process(false)
	player.get_node("RainSystem").call("stop_rain")
	get_first_node_in_group("raft").set_physics_process(false)
	sky = current_scene.get_node("Sky3D")
	clock = sky.get_node("TimeOfDay")
	dome = sky.get_node("SkyDome")
	atmosphere = current_scene.get_node("OceanAtmosphere")
	clock.call("pause"); atmosphere.set_process(false)
	check(clock.get("minutes_per_day") == 20.0, "Live scene uses the slower settings cycle")
	var saved_time: float = clock.get("current_time")
	var config := ConfigFile.new()
	config.set_value("game", "day_minutes", 8.0)
	config.save(settings.SETTINGS_PATH)
	settings.call("_ready")
	check(settings.day_minutes == 20.0, "Existing fast-cycle preferences migrate to twenty minutes")
	check(is_equal_approx(clock.get("current_time"), saved_time), "Preference migration does not reset game time")
	config.set_value("game", "day_minutes", 24.0); config.save(settings.SETTINGS_PATH)
	settings.call("_ready")
	check(settings.day_minutes == 24.0, "Saved slower twenty-four-minute choice is retained")
	for minutes in [12.0, 20.0, 30.0]:
		settings.call("update_setting", "day_minutes", minutes)
		clock.call("pause")
		clock.set("year", 2026); clock.set("month", 10); clock.set("day", 9); set_hour(9.5)
		clock.call("_progress_time", minutes * 60.0)
		check(is_equal_approx(clock.get("current_time"), 9.5) and clock.get("day") == 10, "Full cycle and calendar advance correctly at %d minutes" % minutes)
	settings.call("update_setting", "day_minutes", 2.0)
	check(clock.get("minutes_per_day") == 12.0, "Fastest selectable cycle is twelve minutes")
	settings.call("update_setting", "day_minutes", 96.0)
	check(clock.get("minutes_per_day") == 30.0, "Longest selectable cycle is thirty minutes")
	settings.call("update_setting", "day_minutes", 20.0)
	clock.call("pause"); set_hour(9.5)
	clock.call("_progress_time", 300.0)
	check(is_equal_approx(clock.get("current_time"), 15.5), "Five active minutes advance one quarter of the slower default cycle")
	check(not clock.get("compute_moon_coords") and clock.get("celestials_calculations") == 1, "Night moon presentation keeps the astronomical sun and single clock")
	var all_nights_visible := true
	var days_hide_moon := true
	var material: ShaderMaterial = dome.get("sky_material")
	for month in range(1, 13):
		clock.set("month", month); clock.set("day", 15)
		for hour in [0.0, 3.0, 20.0, 23.0]:
			set_hour(hour)
			var moon: Vector3 = (dome.get("_moon_transform") as Transform3D).origin
			all_nights_visible = all_nights_visible and moon.y >= 0.239 and moon.y <= 0.721 and float(material.get_shader_parameter("night_moon_visibility")) > 0.99
		set_hour(12.0)
		days_hide_moon = days_hide_moon and is_zero_approx(float(material.get_shader_parameter("night_moon_visibility")))
	check(all_nights_visible, "Moon remains above the horizon on every month's dark nights")
	check(days_hide_moon, "Moon fades out in daylight on every month")
	clock.set("month", 10); clock.set("day", 9); set_hour(0.0)
	var before := float(material.get_shader_parameter("night_moon_visibility"))
	clock.set("current_time", 12.0); clock.get_node("Timer").emit_signal("timeout")
	check(before > 0.99 and is_zero_approx(float(material.get_shader_parameter("night_moon_visibility"))), "Clock timer updates moon visibility without a second clock")
	check(dome.get("moon_texture") != null and dome.get("star_field_texture") != null and dome.get("starmap_texture") != null, "Moon surface and both star textures are available")
	check(dome.get("star_scintillation") < 0.4, "Stars twinkle gently")
	check(clock.get("smooth_celestial_motion"), "Live sky smooths movement between bounded orbital samples")
	# Predict between samples at both phone frame rates, then compare the end
	# with the true orbital update: no accumulated drift or 10 Hz position steps.
	clock.set_process(false)
	var max_sun_step := 0.0
	var max_moon_step := 0.0
	var max_sample_error := 0.0
	for fps in [30, 60]:
		var frames_per_sample := roundi(float(fps) / 10.0)
		for hour in [0.0, 5.5, 9.5, 12.0, 18.0, 23.99]:
			clock.call("pause"); set_hour(hour)
			clock.call("resume")
			var old_sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
			var old_moon: Vector3 = (dome.get("_moon_transform") as Transform3D).origin
			for frame in fps:
				clock.call("_process", 1.0 / float(fps))
				atmosphere.call("_update_night_moon")
				var sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
				var moon: Vector3 = (dome.get("_moon_transform") as Transform3D).origin
				max_sun_step = maxf(max_sun_step, old_sun.angle_to(sun))
				max_moon_step = maxf(max_moon_step, old_moon.angle_to(moon))
				old_sun = sun; old_moon = moon
				if frame % frames_per_sample == frames_per_sample - 1:
					clock.call("_on_timeout"); atmosphere.call("_update_night_moon")
					var actual: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
					max_sample_error = maxf(max_sample_error, sun.angle_to(actual))
	check(max_sun_step < deg_to_rad(0.02), "Sun moves less than 0.02 degrees per frame at 30/60 FPS")
	check(max_moon_step < deg_to_rad(0.02), "Moon follows a slow continuous arc at midnight, dawn and dusk")
	check(max_sample_error < deg_to_rad(0.005), "Smooth sky stays aligned with orbital samples and midnight rollover")
	clock.call("pause"); set_hour(9.5)
	var slow_sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
	clock.call("_progress_time", 60.0)
	check(slow_sun.angle_to((dome.get("_sun_transform") as Transform3D).origin) < deg_to_rad(19.0), "A real minute moves the sun under nineteen degrees instead of about forty-five")
	var frozen_time: float = clock.get("current_time")
	var frozen_sun: Vector3 = (dome.get("_sun_transform") as Transform3D).origin
	clock.call("_process", 30.0); atmosphere.call("_update_night_moon")
	check(clock.get("current_time") == frozen_time and (dome.get("_sun_transform") as Transform3D).origin.is_equal_approx(frozen_sun), "Paused clock keeps the smoothed sun stationary")
	if preview:
		for child in player.get_children():
			if child is CanvasLayer: child.visible = false
		player.get_node("SurvivalAction").set_process(false)
		player.get_node("SurvivalProgression").set_process(false)
		player.camera.get_node("HandPivot").visible = false
		camera = Camera3D.new(); current_scene.add_child(camera); camera.current = true; camera.fov = 75.0; camera.far = 4000.0
	for profile in [1, 2, 3]:
		settings.call("update_setting", "quality", profile)
		clock.call("pause"); set_hour(21.0)
		check(not sky.environment.fog_enabled and not sky.environment.volumetric_fog_enabled, "Mobile quality %d retains clear air" % profile)
		check(float(material.get_shader_parameter("night_moon_visibility")) > 0.99, "Moon is enabled on mobile quality %d" % profile)
		await shot("quality-%d" % profile)
	settings.call("update_setting", "quality", 1)
	clock.call("pause"); set_hour(5.4)
	await shot("before-dawn")
	if preview:
		set_hour(0.0)
		camera.look_at(camera.global_position + Vector3(-0.65, 0.70, -0.50) * 100.0)
		for event_time in [0.35, 0.85]:
			material.set_shader_parameter("shooting_star_preview_time", event_time)
			await frames(8); await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/night-sky-shooting-star-%d.png" % roundi(event_time * 100)) == OK, "Rendered moving shooting-star head and fading tail")
		material.set_shader_parameter("shooting_star_preview_time", -1.0)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free(); await frames(25)
	print("NIGHT SKY SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
