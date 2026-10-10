extends SceneTree

var checks := 0
var failures := 0
var preview := false
var hud: Control
var player: CharacterBody3D
var raft: Node3D
var rain: Node3D
var stats: Node

func _initialize() -> void:
	create_timer(160).timeout.connect(func(): push_error("FAIL: bag/rain timeout"); quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)

func frames(count: int = 5) -> void:
	for unused in count: await process_frame

func pointer(at: Vector2, index: int = 21, duplicate: bool = true) -> void:
	var finger := InputEventScreenTouch.new()
	finger.index = index; finger.position = at; finger.pressed = true
	root.push_input(finger, true)
	if duplicate:
		var mouse := InputEventMouseButton.new()
		mouse.device = -1; mouse.position = at; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = true
		root.push_input(mouse, true)
		mouse.pressed = false; root.push_input(mouse, true)
	finger.pressed = false; root.push_input(finger, true)

func shot(label: String) -> void:
	if not preview: return
	await frames(12); await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/mobile-fix-" + label + ".png") == OK, "Rendered " + label)

func fixture(kind: String, at: Vector3) -> Node3D:
	var result: Node3D = player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name = kind + "_TouchRainCheck"
	result.position = at; raft.get_node("BuiltPieces").add_child(result)
	result.add_to_group("build_surface")
	return result

func lit_pixels(picture: Image) -> int:
	var result := 0
	for y in picture.get_height():
		for x in picture.get_width():
			var color := picture.get_pixel(x, y)
			if color.r + color.g + color.b > 0.08: result += 1
	return result

func render_shelter_probe() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 240); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	current_scene.add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.current = true
	var centre := raft.to_global(Vector3(0, 1.5, 0))
	camera.global_position = raft.to_global(Vector3(0, 1.5, 3))
	camera.look_at(centre)
	var probe := MeshInstance3D.new(); viewport.add_child(probe)
	var quad := QuadMesh.new(); quad.size = Vector2(0.6, 0.6); probe.mesh = quad
	probe.global_position = centre
	for entry in [["rain", rain._rain_mat], ["splash", rain._splash_mat]]:
		var material: ShaderMaterial = entry[1]
		probe.material_override = material
		material.set_shader_parameter("intensity", 1.0)
		material.set_shader_parameter("cover_count", 0)
		material.set_shader_parameter("roof_map_enabled", false)
		await frames(10); await RenderingServer.frame_post_draw
		check(lit_pixels(viewport.get_texture().get_image()) > 25, "GPU " + entry[0] + " is visible without a ceiling mask")
		rain.call("_refresh_shelter_masks")
		await frames(10); await RenderingServer.frame_post_draw
		var covered := viewport.get_texture().get_image()
		check(lit_pixels(covered) == 0, "GPU " + entry[0] + " fragments are fully clipped beneath the moved/turned roof")
		covered.save_png("C:/GodotProjects/raft-survival/build/mobile-fix-clipped-" + entry[0] + ".png")
	probe.hide()
	# Exercise the actual world-space particle draw path, not just a CPU mirror.
	for entry in [["rain", rain._particles.draw_pass_1], ["splash", rain._splash_pool[0].draw_pass_1]]:
		var particles := GPUParticles3D.new(); viewport.add_child(particles)
		particles.amount = 24; particles.lifetime = 10; particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
		# Widen the test streak beyond a subpixel at this small viewport so the
		# open-air positive control is deterministic. Keep the real GPU material.
		var particle_mesh: QuadMesh = entry[1].duplicate()
		particle_mesh.size.x = maxf(particle_mesh.size.x,0.12)
		particles.draw_pass_1 = particle_mesh
		var process := ParticleProcessMaterial.new(); process.gravity = Vector3.ZERO
		process.initial_velocity_min = 0; process.initial_velocity_max = 0
		particles.process_material = process; particles.global_position = centre; particles.emitting = true
		var material: ShaderMaterial = particles.draw_pass_1.material
		material.set_shader_parameter("cover_count", 0)
		material.set_shader_parameter("roof_map_enabled", false)
		await frames(40); await RenderingServer.frame_post_draw
		check(lit_pixels(viewport.get_texture().get_image()) > 0, "Actual " + entry[0] + " particles render in open air")
		rain.call("_refresh_shelter_masks")
		await frames(10); await RenderingServer.frame_post_draw
		check(lit_pixels(viewport.get_texture().get_image()) == 0, "Actual " + entry[0] + " particles cannot show inside the roof")
		particles.queue_free(); await frames()
	viewport.queue_free(); await frames()

func large_house_probe() -> void:
	var roofs: Array[Node3D]=[]
	for z in range(-4,5):
		for x in range(-4,5):
			if x==0 and z==0:continue
			roofs.append(fixture("Roof",Vector3(x*2,2.725,z*2)))
	await frames(8);rain.call("_refresh_shelter_masks")
	var far:=raft.to_global(Vector3(8,1.5,8))
	check(rain._mask_boxes.size()==64 and not rain.call("rain_visible_at",far),"The 81-panel house stays dry beyond the old 64-shape limit")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(10,1.5,8))),"Overflow protection does not hide outdoor rain beside the large house")
	var splash_color: Color=rain._splash_mat.get_shader_parameter("drop_color")
	check(splash_color.b>splash_color.r*2.0 and splash_color.r<.4,"Rain impacts use restrained blue instead of near-white")
	var rotated:=roofs.back() as Node3D
	rotated.rotation.y=.4;rain.call("_refresh_shelter_masks")
	var leaks:=0
	for z in range(-4,5):
		for x in range(-4,5):
			if rain.call("rain_visible_at",rotated.to_global(Vector3(x*.23,-1.225,z*.23))):leaks+=1
	check(leaks==0,"Rotated overflow roof stays dry across its full interior, including the rim")
	if preview:
		var viewport:=SubViewport.new();viewport.size=Vector2i(360,240);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;current_scene.add_child(viewport)
		var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;viewport.add_child(env)
		var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.global_position=far+raft.global_basis.z*3;camera.look_at(far)
		var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.6,.6);mesh.mesh=quad;viewport.add_child(mesh);mesh.global_position=far
		for material: ShaderMaterial in [rain._rain_mat,rain._splash_mat]:
			mesh.material_override=material;material.set_shader_parameter("intensity",1.0);material.set_shader_parameter("roof_map_enabled",false)
			await frames(10);await RenderingServer.frame_post_draw
			check(lit_pixels(viewport.get_texture().get_image())>25,"GPU positive control reproduces the former roof overflow leak")
			material.set_shader_parameter("roof_map_enabled",true)
			await frames(10);await RenderingServer.frame_post_draw
			check(lit_pixels(viewport.get_texture().get_image())==0,"GPU roof-height protection clips overflow rain and splashes")
		viewport.queue_free();await frames()
	for roof in roofs:roof.queue_free()
	await frames(8);rain.call("_refresh_shelter_masks")
	var stair:=fixture("Stairs",Vector3(0,.25,0))
	await frames(12);rain.call("_refresh_shelter_masks")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(0,1.5,.7))),"Real stairwell remains open to rain and sky")
	check(not rain.call("rain_visible_at",raft.to_global(Vector3(.9,1.5,.7))),"The solid ceiling beside the same stairwell remains dry")
	stair.queue_free();await frames(8)

func recipe_swipe_probe() -> void:
	var kitchen: Node3D = load("res://scenes/cooking_setup.tscn").instantiate()
	current_scene.add_child(kitchen); kitchen.global_position = player.global_position + Vector3(0, -.7, -1.3)
	kitchen.set_process(false); kitchen.burning = true; kitchen.fuel = 100
	var service := player.get_node("SurvivalServices")
	service.call("open_cooking", kitchen); await frames(8)
	var ui: CanvasLayer = service.get("ui")
	var scroll: ScrollContainer = ui.get("_body").get_node("RecipeScroll")
	var ingredients: RichTextLabel = ui.get("_rows")[0].ingredients
	var start := ingredients.get_global_rect().get_center()
	check(scroll.get_global_rect().has_point(start), "Recipe ingredients are visible inside the scroll area")
	var finger := InputEventScreenTouch.new(); finger.index = 71; finger.position = start; finger.pressed = true
	root.push_input(finger, true)
	var mouse := InputEventMouseButton.new(); mouse.device = -1; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.position = start; mouse.pressed = true
	root.push_input(mouse, true)
	var position := start
	for unused in 6:
		position += Vector2(0, -24)
		var drag := InputEventScreenDrag.new(); drag.index = 71; drag.position = position; drag.relative = Vector2(0, -24)
		root.push_input(drag, true)
		var motion := InputEventMouseMotion.new(); motion.device = -1; motion.button_mask = MOUSE_BUTTON_MASK_LEFT; motion.position = position; motion.relative = drag.relative
		root.push_input(motion, true); await frames(1)
	mouse.position = position; mouse.pressed = false; root.push_input(mouse, true)
	finger.position = position; finger.pressed = false; root.push_input(finger, true); await frames(6)
	check(scroll.scroll_vertical > 40, "Swiping directly over recipe ingredients scrolls the cards")
	check(not service.call("busy"), "Swiping does not accidentally start a cooking job")
	await shot("recipe-scroll")
	service.call("close_menu"); kitchen.queue_free(); await frames()

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	var inventory := root.get_node("Inventory")
	stats = root.get_node("Stats"); stats.enabled = false
	inventory.call("new_game_reset", true)
	change_scene_to_file("res://scenes/main.tscn"); await scene_changed
	player = get_first_node_in_group("player"); raft = get_first_node_in_group("raft")
	player.set_process(false); player.set_physics_process(false)
	await frames(160)
	player.set_process(false); player.set_physics_process(false); raft.set_physics_process(false)
	player.build_mode = false; player.is_swimming = false
	hud = player.get_node("CanvasLayer/SurvivalHUD")
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.force_show = true; controls.call("_update_visibility"); controls.call("_sync_mode")
	hud.visible = true; hud.call("_compute_layout")
	pointer(hud._bag_rect.get_center())
	check(hud._bag_open, "One Android finger tap plus its emulated mouse opens and retains the bag")
	check(hud._bag_slot_rects.size() == 30 and hud._craft_button_rect.has_area(), "Items and crafting hit targets exist immediately on the first tap")
	check(controls._move_id == -1 and controls._look_id == -1, "Opening the bag releases movement and camera fingers")
	check(not Input.is_action_pressed("interact") and not Input.is_action_pressed("rope_throw"), "Bag tap fires no world action")
	var occupied := -1
	for index in range(hud.HOTBAR_COUNT, inventory.SLOT_COUNT):
		if not inventory.call("slot_empty", index): occupied = index; break
	pointer(hud._bag_slot_rects[occupied].get_center(), 22)
	check(hud._bag_open and hud._inspect_slot == occupied, "Touch item inspection survives the matching Android mouse event")
	await shot("backpack")
	if preview:
		var border_rect: Rect2 = hud._bag_slot_rects[occupied]
		var border_image := root.get_texture().get_image()
		var gold_pixels := 0
		for y in range(1, 8):
			for x in range(-4, 5):
				var border := border_image.get_pixelv(Vector2i(border_rect.position + Vector2(border_rect.size.x * .5 + x, y)))
				if border.r > .65 and border.g > .55 and border.b < .65: gold_pixels += 1
		check(gold_pixels > 5, "Inspected backpack item has a visible gold selection border")
	pointer(hud._craft_button_rect.get_center(), 23)
	check(hud._craft_open and not hud._bag_open and paused, "Bag CRAFT opens the visible crafting panel exactly once")
	await frames()
	var spear_before: int = inventory.call("total", "Spear")
	pointer(hud._craft_menu.cards.Spear.get_global_rect().get_center(), 24)
	await frames()
	check(hud._craft_menu.selected == "Spear" and inventory.call("total", "Spear") == spear_before, "Recipe selection only shows requirements and does not spend")
	await shot("crafting")
	pointer(hud._craft_menu._build.get_global_rect().get_center(), 25)
	check(inventory.call("total", "Spear") == spear_before + 1, "One touch confirmation crafts one spear despite emulated mouse replay")
	hud.call("_close_crafting")
	var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = hud._bag_rect.get_center(); mouse.pressed = true
	root.push_input(mouse, true); mouse.pressed = false; root.push_input(mouse, true)
	check(hud._bag_open, "A physical desktop mouse still opens the Bag")
	stats.enabled = true; stats.call("load_state", {"health":80,"hunger":80,"thirst":80})
	stats.call("_process", 300.0)
	check(stats.health == 80 and stats.thirst == 80 and stats.hunger == 80, "Reading the bag causes no survival drain")
	pointer(hud._close_rect.get_center(), 26)
	check(not hud._bag_open and not paused, "Close touch leaves the bag closed without reopening")
	await recipe_swipe_probe()
	stats.call("load_state", {"health":80,"hunger":80,"thirst":80})
	player.velocity = Vector3.ZERO; player.is_swimming = false
	stats.call("_process", 60.0)
	check(is_equal_approx(stats.thirst, 77.0) and is_equal_approx(stats.hunger, 78.2), "A normal minute costs only three water and 1.8 food")
	check(stats.health == 80, "Healthy fed/hydrated players have no passive health loss")
	stats.call("load_state", {"health":80,"hunger":80,"thirst":80}); player.velocity = Vector3(5,0,0)
	stats.call("_process", 60.0)
	check(is_equal_approx(stats.thirst,75.2) and stats.health == 80, "Sprinting retains its bounded effort multiplier without health drain")
	stats.call("load_state", {"health":80,"hunger":80,"thirst":80}); player.is_swimming = true
	stats.call("_process", 60.0)
	check(is_equal_approx(stats.thirst,74.0) and stats.health == 80, "Swimming costs six water per active minute without passive health drain")
	player.is_swimming = false; player.velocity = Vector3.ZERO
	stats.call("load_state", {"health":80,"hunger":0,"thirst":0}); stats.call("_process", 10.0)
	check(is_equal_approx(stats.health,78.0), "Empty food/water damage health slowly at 0.2 per second")
	stats.call("change_health", -10.0)
	check(stats.health == 68, "Actual combat/environment damage still applies")
	paused = true; var before: Dictionary = stats.call("save_state"); stats.call("_process",120.0)
	check(stats.call("save_state") == before, "Paused survival values remain unchanged")
	paused = false; stats.enabled = false
	raft.global_position = Vector3(80,0.6,80); raft.rotation.y = 0.7
	fixture("Roof", Vector3(0,2.725,0)); fixture("Wall", Vector3(0,1.4,-1))
	await frames(8)
	rain = player.get_node("RainSystem"); rain.set_process(false)
	var shelter_camera := Camera3D.new(); current_scene.add_child(shelter_camera)
	shelter_camera.global_position = raft.to_global(Vector3(0,1.5,0))
	rain._camera = shelter_camera
	rain.call("start_rain",120.0); rain.call("_refresh_shelter_masks")
	check(not rain.call("rain_visible_at", raft.to_global(Vector3(0,1.5,0))), "Real roof blocks its indoor column")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(0,3.0,0))), "Rain remains above the roof")
	check(rain.call("rain_visible_at",raft.to_global(Vector3(2,1.5,0))), "Open air beside the shelter still rains")
	check(rain._splash_mat.get_shader_parameter("cover_count") == rain._rain_mat.get_shader_parameter("cover_count"), "Rain streaks and bouncing splashes share the same ceiling masks")
	check(rain._splash_mat.get_shader_parameter("world_to_raft") == raft.global_transform.affine_inverse(), "Splash masks follow moved and turned raft coordinates")
	rain.call("stop_rain"); rain._intensity = 0.8
	rain.call("_update_cover_state",1.0)
	check(int(rain._splash_mat.get_shader_parameter("cover_count")) > 0, "Shelter masks remain active during rain fade-out")
	if preview: await render_shelter_probe()
	await large_house_probe()
	var release:=str(ProjectSettings.get_setting("application/config/version"))
	check(not release.is_empty(), "The project displays its release for APK identification")
	var preset := ConfigFile.new(); preset.load("C:/GodotProjects/raft-survival/export_presets.cfg")
	check(int(preset.get_value("preset.0.options","version/code",0)) >= 13 and str(preset.get_value("preset.0.options","version/name","")) == release, "Android version code/name distinguish the upcoming update from old APKs")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free(); await frames(25)
	print("MOBILE BAG RAIN SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
