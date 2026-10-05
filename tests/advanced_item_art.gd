extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var items := {"raw_meat":"raw_meat", "cooked_meat":"cooked_meat", "raw_crab":"shore_crab", "cooked_crab":"shore_crab", "diving_tank":"diving_tank", "bandage":"", "torch":"torch"}
	for label in items:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(256,256)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.6
		viewport.add_child(environment)
		var model: Node3D
		if label == "torch":
			model = load("res://scripts/torch_visual.gd").new()
		elif items[label] == "":
			model = Node3D.new()
			var roll := MeshInstance3D.new()
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.035
			mesh.outer_radius = 0.10
			mesh.rings = 24
			mesh.ring_segments = 12
			roll.mesh = mesh
			var cloth := StandardMaterial3D.new()
			cloth.albedo_color = Color(0.77,0.75,0.64)
			cloth.roughness = 0.95
			roll.material_override = cloth
			model.add_child(roll)
		else:
			model = (load("res://models/"+items[label]+".glb") as PackedScene).instantiate() as Node3D
		viewport.add_child(model)
		if label == "cooked_crab":
			for part in model.find_children("*","MeshInstance3D",true,false):
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.55,0.23,0.07)
				material.roughness = 0.65
				(part as MeshInstance3D).material_override = material
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45,-25,0)
		light.light_energy = 1.0
		viewport.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 0.90 if label == "torch" else (0.70 if label == "diving_tank" else (0.59 if label.ends_with("crab") else 0.38))
		camera.position = Vector3(0.4,0.33,0.6)
		viewport.add_child(camera)
		camera.look_at(Vector3(0,0.05 if label.ends_with("crab") else 0,0))
		for i in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.save_png("C:/GodotProjects/raft-survival/textures/ui/advanced_"+label+".png")
		print("ITEM ART "+label)
		viewport.queue_free()
		await process_frame
	quit()
