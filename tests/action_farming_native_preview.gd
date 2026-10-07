extends SceneTree
var player: Node3D
var raft: Node3D
var built: Node3D
var camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func piece(kind: String,pos: Vector3) -> Node3D:
	var result: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name=kind+"_Visual_%d"%result.get_instance_id();result.position=pos;built.add_child(result)
	return result
func shot(label: String) -> void:
	for unused in 12:await process_frame
	await RenderingServer.frame_post_draw
	var path:="C:/GodotProjects/raft-survival/build/action-"+label+".png"
	root.get_texture().get_image().save_png(path);print("PREVIEW ",path)
func pose(kind: String,progress: float=.5) -> void:
	var action:=player.get_node("SurvivalAction")
	player.call("play_action",kind,2.0,player.global_position+Vector3(0,-.5,-.7))
	action.elapsed=progress*2.0;action.call("_process",0.0);action.set_process(false)
	player.call("_update_hand_sway",0.0)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	root.size=Vector2i(1280,720)
	root.get_node("Inventory").call("new_game_reset",true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	for unused in 140:await process_frame
	for z in range(1,4):
		for x in range(1,4):piece("Foundation",Vector3(x*2,0,z*2))
	raft.call("_refresh_deck_samples");raft.call("_physics_process",1.0)
	for unused in 3:await physics_frame
	var pot:=piece("PlanterBox",Vector3(4,.35,4))
	pot.plant_seed("Potato");pot._plant.restore_state({"id":"Potato","stage":2});pot._plant.set_process(false)
	piece("TreePot",Vector3(5.5,.45,4))
	var filter:=piece("SandFilter",Vector3(3,.9,4));filter.water=3
	player.camera.current=false
	camera=Camera3D.new();camera.fov=46;current_scene.add_child(camera);camera.current=true
	current_scene.get_node("Sky3D/TimeOfDay").current_time=16.3
	camera.position=raft.to_global(Vector3(4.1,1.5,5.8));camera.look_at(raft.to_global(Vector3(4.1,.36,4)))
	await shot("wood-soil-pots")
	camera.position=raft.to_global(Vector3(3.9,1.6,6.1));camera.look_at(raft.to_global(Vector3(3,.8,4)))
	await shot("large-sand-sponge-filter")
	player.cam_mode=1;player.call("_apply_camera_mode")
	player.position=raft.to_global(Vector3(5,1.06,6));player.rotation.y=0
	player.active_item="Fishing Rod";player.call("_update_hand_item")
	player.camera.current=false;camera.current=true
	camera.position=raft.to_global(Vector3(6.8,2.1,4.8));camera.look_at(player.global_position+Vector3(0,.1,0))
	pose("cast",.55);await shot("fishing-cast-hand")
	pose("reel");await shot("fishing-reel-hand")
	player.get_node("SurvivalAction").call("stop")
	player.active_item="Tomato";player.call("_update_hand_item")
	player.get_node("SurvivalAction").call("_process",0.0)
	await shot("tomato-palm-grip")
	player.call("equip_rope_gun");pose("chop",.25);await shot("tree-chop-windup")
	pose("harvest",.30);await shot("crop-pull-hands")
	player.cam_mode=0;player.call("_apply_camera_mode");camera.current=false;player.camera.current=true
	player.camera.global_position=raft.to_global(Vector3(4,1.55,5.6));player.camera.look_at(raft.to_global(Vector3(4,.4,4)))
	pose("build",.35);await shot("first-person-build-progress")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for unused in 25:await process_frame
	quit()
