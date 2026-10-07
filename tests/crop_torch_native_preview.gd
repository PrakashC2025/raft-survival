extends SceneTree
var player: Node3D
var raft: Node3D
var built: Node3D
var camera: Camera3D
func _initialize() -> void: call_deferred("_run")
func piece(kind: String,pos: Vector3) -> Node3D:
	var result: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name=kind+"_Preview_%d"%result.get_instance_id()
	result.position=pos
	built.add_child(result)
	return result
func shot(label: String) -> void:
	for unused in range(20):await process_frame
	await RenderingServer.frame_post_draw
	var path:="C:/GodotProjects/raft-survival/build/crop-"+label+".png"
	root.get_texture().get_image().save_png(path)
	print("PREVIEW ",path)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	root.size=Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_physics_process(false);player.set_process(false);raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	player.cam_mode=1;player.call("_apply_camera_mode")
	player._third_person_launcher.hide()
	for unused in range(180):await process_frame
	for z in range(1,4):
		for x in range(1,4):piece("Foundation",Vector3(x*2,0,z*2))
	var tomato:=piece("PlanterPot",Vector3(3.5,0.33,4)) as Node3D
	tomato.plant_seed("Tomato");tomato._plant.restore_state({"id":"Tomato","stage":3});tomato._plant.set_process(false)
	var potato:=piece("PlanterPot",Vector3(4.4,0.33,4)) as Node3D
	potato.plant_seed("Potato");potato._plant.restore_state({"id":"Potato","stage":3});potato._plant.set_process(false)
	var growing:=piece("PlanterPot",Vector3(5.3,0.33,4)) as Node3D
	growing.plant_seed("Potato");growing._plant.restore_state({"id":"Potato","stage":2,"timer":5});growing._plant.set_process(false)
	player.camera.current=false
	camera=Camera3D.new();camera.fov=48;current_scene.add_child(camera);camera.current=true
	current_scene.get_node("Sky3D/TimeOfDay").current_time=16.3
	camera.global_position=raft.to_global(Vector3(4.35,1.55,6.1));camera.look_at(raft.to_global(Vector3(4.35,.85,4)))
	await shot("mature-plants")
	potato._plant.call("_do_dig")
	await create_timer(.48).timeout
	await shot("potato-roots-harvest")
	await create_timer(1.5).timeout
	piece("Wall",Vector3(4,1.4,3));piece("Roof",Vector3(4,2.725,4))
	var mounted:=piece("WallTorch",Vector3(4,1.4,3.31))
	mounted.call("restore_survival_state",{"fuel":180,"burning":true})
	current_scene.get_node("Sky3D/TimeOfDay").current_time=22.0
	camera.global_position=raft.to_global(Vector3(4.5,1.6,6.4));camera.look_at(raft.to_global(Vector3(4,1.25,3.4)))
	await shot("wall-torch-night")
	current_scene.get_node("Sky3D/TimeOfDay").current_time=16.3
	player.position=raft.to_global(Vector3(5.6,1.0,5.2))
	player.rotation.y=0
	player.cam_mode=1;player.call("equip_rope_gun");player.call("_apply_camera_mode")
	player._survivor_animator.play("Idle")
	player.camera.current=false
	player.camera.global_rotation=Vector3(-.1,0,0)
	camera.global_position=raft.to_global(Vector3(6.9,1.9,3.0));camera.look_at(player.global_position+Vector3(0,.1,0))
	await shot("launcher-hand-facing")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for unused in range(25):await process_frame
	quit()
