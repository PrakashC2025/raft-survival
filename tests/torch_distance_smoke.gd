extends SceneTree
var checks := 0
var failures := 0
var preview := false
var camera: Camera3D
var torch: Node3D
var stage: Node3D

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("FAIL: torch distance timeout"); quit(1))
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)
func frames(count: int = 4) -> void:
	for unused in count: await process_frame
func capture(label: String) -> Image:
	await frames(); await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	check(result.save_png("C:/GodotProjects/raft-survival/build/torch-distance-" + label + ".png") == OK, "Rendered " + label)
	return result
func flame_pixels(picture: Image) -> int:
	var at := camera.unproject_position(torch.global_position + Vector3.UP * .47)
	var count := 0
	for y in range(maxi(0, int(at.y)-18), mini(picture.get_height(), int(at.y)+18)):
		for x in range(maxi(0, int(at.x)-12), mini(picture.get_width(), int(at.x)+12)):
			var color := picture.get_pixel(x,y)
			if color.r > .65 and color.g > .18 and color.b < .30: count += 1
	return count
func readability(value: float) -> void:
	for part in torch._visual.flames.get_children():
		(part.material_override as ShaderMaterial).set_shader_parameter("torch_readability",value)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280,720)
	root.get_node("Stats").enabled = false
	stage = Node3D.new(); root.add_child(stage); current_scene = stage
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(.11,.22,.32)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = .65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES; world.environment.tonemap_white = 6
	stage.add_child(world)
	var wood := preload("res://scripts/object_materials.gd").make(0,Color(.24,.12,.04),1)
	preload("res://scripts/machine_visual.gd").box(stage,Vector3(0,1,-.16),Vector3(4,3,.18),wood)
	camera = Camera3D.new(); stage.add_child(camera); camera.current = true; camera.far = 600
	camera.position = Vector3(0,1.36,4); camera.look_at(Vector3(0,1.34,0))
	torch = load("res://scenes/wall_torch.tscn").instantiate(); stage.add_child(torch)
	torch.position = Vector3(0,.9,.05); torch.set_process(false)
	torch.restore_survival_state({"burning":true,"fuel":120,"end_time":1000})
	var saved: Dictionary = torch.save_survival_state()
	torch.set_meta("light_allowed",false); torch._update_flame()
	check(torch._visual.flames.visible and not torch._light.visible,"A burning torch remains visible even when its room light is outside the light budget")
	check(torch._visual.flames.get_child_count() == 1,"One camera-facing shadow-free flame stays visible from every direction")
	if preview:
		await capture("near")
		camera.position.z = 24; await capture("raft-distance")
		camera.position.z = 72
		readability(0); var previous := flame_pixels(await capture("old-far"))
		readability(1); var current := flame_pixels(await capture("far"))
		print("TORCH DISTANCE PIXELS: old ",previous,"; improved ",current," at 72m")
		check(current > previous and current > 0,"The flame itself has more visible bright pixels at 72 metres with room lighting disabled")
		camera.position.z = 150
		check(flame_pixels(await capture("very-far")) >= 4,"The flame stays clearly bright at 150 metres with room lighting disabled")
		camera.position.z = 400
		check(flame_pixels(await capture("across-sea")) >= 12,"A lit torch keeps a bright flame across 400 metres with its room light disabled")
		camera.position = Vector3(400,1.36,0); camera.look_at(Vector3(0,1.34,0))
		check(flame_pixels(await capture("side-far")) >= 12,"Viewing the same flame from its side cannot make it disappear")
		camera.position = Vector3(0,1.36,150); camera.look_at(Vector3(0,1.34,0))
		var blocker := preload("res://scripts/machine_visual.gd").box(stage,Vector3(0,1,2),Vector3(4,3,.18),wood)
		check(flame_pixels(await capture("behind-wall")) == 0,"A solid wall still hides the distant flame")
		blocker.queue_free(); await frames()
		# Render a real surface outside the previous 12m light radius.
		var material := StandardMaterial3D.new(); material.albedo_color = Color(.72,.72,.72); material.roughness = 1
		var distant_surface := preload("res://scripts/machine_visual.gd").box(stage,Vector3(0,1.36,30),Vector3(3,3,.1),material)
		camera.position = Vector3(0,1.36,25); camera.look_at(Vector3(0,1.36,30))
		world.environment.ambient_light_energy = 0
		torch.set_meta("light_allowed",true); torch._update_flame()
		torch._light.omni_range = 12
		var old_light := (await capture("old-light-reach")).get_pixel(640,360)
		torch._light.omni_range = torch._visual.LIGHT_RANGE
		var new_light := (await capture("extended-light-reach")).get_pixel(640,360)
		print("TORCH LIGHT AT 30m: old ",old_light,"; increased ",new_light)
		check(new_light.r > old_light.r + .03,"Torch illumination reaches a real surface 30 metres away")
		distant_surface.queue_free(); await frames()
		world.environment.ambient_light_energy = .65
		camera.position = Vector3(0,1.36,150); camera.look_at(Vector3(0,1.34,0))
		torch.set_meta("light_allowed",false); torch._update_flame()
	torch.extinguish()
	check(not torch._visual.flames.visible and not torch._light.visible and torch.fuel == 120,"Putting out a torch hides its distant fire and preserves fuel")
	if preview: check(flame_pixels(await capture("off")) == 0,"An extinguished torch does not leave a distant glow")
	torch.restore_survival_state(saved)
	check(torch.burning and torch._visual.flames.visible and torch.fuel == 120,"Saved burning state restores the visible flame")
	torch.restore_survival_state({"burning":true,"fuel":0})
	check(not torch.burning and not torch._visual.flames.visible,"Spent fuel cannot show a distant flame")
	stage.queue_free(); await frames()
	print("TORCH DISTANCE SMOKE: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
