extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.13, 0.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 3, 7)
	camera.look_at(Vector3(0, 0.6, 0))
	camera.current = true
	var factory = load("res://scripts/mobile_assets.gd")
	var names := ["survivor", "boar", "bird", "shark", "fish", "campfire-pit"]
	for i in range(names.size()):
		var model: Node3D = factory.make(names[i], 1.6, true)
		stage.add_child(model)
		model.position = Vector3((i % 3 - 1) * 2.3, 0, -1.0 if i < 3 else 1.4)
		factory.animate(model, ["idle", "walk"])
		var label := Label3D.new()
		label.text = names[i]
		label.position = model.position + Vector3(0, -0.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(label)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/mobile_models_preview.png")
	print("MODEL PREVIEW SAVED")
	quit()
