extends SceneTree
var raft: Node3D
var player: Node3D
var camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func piece(kind: String,pos: Vector3) -> void:
	var value: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	value.name=kind+"_Preview_"+str(value.get_instance_id());value.position=pos
	raft.get_node("BuiltPieces").add_child(value)
func shot(label: String) -> void:
	for unused in 20:await process_frame
	await RenderingServer.frame_post_draw
	var path:="C:/GodotProjects/raft-survival/build/"+label+".png"
	root.get_texture().get_image().save_png(path);print("PREVIEW ",path)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	root.size=Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	raft=get_first_node_in_group("raft");player=get_first_node_in_group("player")
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	for unused in 140:await process_frame
	for z in range(1,3):
		for x in range(0,3):piece("Foundation",Vector3(x*2,0,z*2))
	piece("Window",Vector3(2,1.4,3))
	piece("Wall",Vector3(4,1.4,3))
	raft.call("_refresh_deck_samples")
	player.camera.current=false
	camera=Camera3D.new();camera.fov=60;current_scene.add_child(camera);camera.current=true
	current_scene.get_node("Sky3D/TimeOfDay").current_time=16.3
	camera.position=raft.to_global(Vector3(2,1.8,5.9));camera.look_at(raft.to_global(Vector3(2,1.8,3)))
	await shot("smaller-open-timber-window")
	camera.position=raft.to_global(Vector3(6.9,3.5,8));camera.look_at(raft.to_global(Vector3(2,.3,2)))
	await shot("gentle-ocean-floating-raft")
	var start:=raft.global_transform
	for unused in 90:await process_frame
	print("ROCKING before=",start.origin," after=",raft.global_position," angles=",raft.rotation)
	await shot("gentle-ocean-raft-swell")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for unused in 25:await process_frame
	quit()
