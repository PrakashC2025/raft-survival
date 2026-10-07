extends SceneTree
## Runs a real renderer with isolated data; writes views and bounded frame metrics.
var raft: Node3D
var player: Node3D
var built: Node3D

func _initialize() -> void: call_deferred("_run")

func add_piece(kind: String, position: Vector3, yaw: float = 0.0) -> Node3D:
	if kind != "Foundation": position += Vector3(5,0,7)
	var index: int = player.BUILD_RECIPE_NAMES.find(kind)
	var piece: Node3D = player.build_pieces[index].instantiate()
	piece.name = "%s_Preview_%d" % [kind,piece.get_instance_id()]
	piece.transform = Transform3D(Basis(Vector3.UP,yaw),position)
	built.add_child(piece)
	return piece

func shot(label: String) -> void:
	for unused in range(30): await process_frame
	await RenderingServer.frame_post_draw
	var path := "C:/GodotProjects/raft-survival/build/overhaul-"+label+".png"
	root.get_texture().get_image().save_png(path)
	print("PREVIEW ",path)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.size = Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true)
	root.get_node("GameSettings").call("update_setting","quality",3)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player = get_first_node_in_group("player") as Node3D
	raft = get_first_node_in_group("raft") as Node3D
	built = raft.get_node("BuiltPieces")
	player.set_physics_process(false); player.set_process(false); raft.set_physics_process(false)
	root.get_node("Stats").enabled = false
	for unused in range(900):
		await process_frame
		var ready := true
		for setup in current_scene.find_children("IslandSetup","",true,false): ready = ready and setup.setup_complete
		if ready and unused > 90: break
	for z in range(8):
		for x in range(8):
			if x != 0 or z != 0: add_piece("Foundation",Vector3(x*2,0,z*2))
	for position in [Vector3(2,1.4,1),Vector3(2,1.4,3)]: add_piece("Wall",position)
	var window := add_piece("Window",Vector3(4,1.4,1))
	add_piece("Door",Vector3(4,1.4,3))
	add_piece("Wall",Vector3(1,1.4,2),PI/2)
	add_piece("Wall",Vector3(5,1.4,2),PI/2)
	add_piece("Roof",Vector3(2,2.725,2)); add_piece("Roof",Vector3(4,2.725,2))
	add_piece("HalfWall",Vector3(6.1,0.775,3))
	add_piece("CargoCrate",Vector3(4.7,0.50,4))
	player.position = raft.to_global(Vector3(6.6,1.1,11.4))
	player.set("cam_mode",1); player.call("_apply_camera_mode")
	player._survivor_animator.play("Idle")
	player.camera.current = false
	var camera := Camera3D.new()
	camera.fov = 60
	current_scene.add_child(camera)
	camera.current = true
	current_scene.get_node("Sky3D/TimeOfDay").current_time = 16.6
	camera.position = raft.to_global(Vector3(6,4.7,17))
	camera.look_at(raft.to_global(Vector3(8,1.4,9)))
	raft.get_node("ConstructionBatch").call("refresh")
	await shot("timber-room")
	camera.position = raft.to_global(Vector3(5,2.5,14))
	camera.look_at(raft.to_global(Vector3(8,0,11)))
	await shot("joined-timbers")
	if "--material-diagnostic" in OS.get_cmdline_user_args():
		var photo := StandardMaterial3D.new()
		photo.albedo_texture = preload("res://textures/construction/timber_photographic_atlas.png")
		photo.uv1_scale = Vector3(0.45,0.20,1)
		photo.uv1_offset = Vector3(0,0.02,0)
		photo.roughness = 0.9
		for draw in raft.get_node("ConstructionBatch").get_children(): draw.material_override = photo
		await shot("wood-standard-diagnostic")
		photo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		await shot("wood-unlit-diagnostic")
		var shader := Shader.new()
		shader.code = preload("res://shaders/wood_planks.gdshader").code.replace("shader_type spatial;","shader_type spatial;\nrender_mode unshaded;")
		var custom := ShaderMaterial.new()
		custom.shader = shader
		custom.set_shader_parameter("photographic_wood",true)
		custom.set_shader_parameter("authored_timber_uv",true)
		custom.set_shader_parameter("solid_timber",true)
		custom.set_shader_parameter("wood_texture",photo.albedo_texture)
		for draw in raft.get_node("ConstructionBatch").get_children(): draw.material_override = custom
		await shot("wood-custom-unlit-diagnostic")
		for draw in raft.get_node("ConstructionBatch").get_children(): draw.material_override = null
	camera.position = raft.to_global(Vector3(5,2.2,13.4))
	camera.look_at(player.global_position+Vector3(0,0.1,0))
	await shot("survivalist")
	window.call("toggle")
	camera.position = raft.to_global(Vector3(9,1.7,5.7))
	camera.look_at(raft.to_global(Vector3(9,1.5,8)))
	await shot("window-open")
	var lamp := add_piece("ElectricLamp",Vector3(4,0.8,4))
	var generator := add_piece("WindGenerator",Vector3(6,0.8,3))
	generator.charge = 120
	current_scene.get_node("Sky3D/TimeOfDay").current_time = 22
	camera.position = raft.to_global(Vector3(6,4.7,17))
	camera.look_at(raft.to_global(Vector3(8,1.4,9)))
	await create_timer(1.0).timeout
	await shot("night-camp")
	var timings: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in range(240):
		await process_frame
		var now := Time.get_ticks_usec()
		if index > 30: timings.append(float(now-previous)/1000.0)
		previous = now
	timings.sort()
	print("NATIVE BUILD METRICS: adapter=",RenderingServer.get_video_adapter_name()," renderer=",RenderingServer.get_current_rendering_method()," pieces=",built.get_child_count()," timber_draws=",raft.get_node("ConstructionBatch").get_child_count()," median_ms=",timings[floori(float(timings.size())/2.0)]," p95_ms=",timings[int(timings.size()*0.95)]," max_ms=",timings[-1]," total_draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for unused in range(20): await process_frame
	quit()
