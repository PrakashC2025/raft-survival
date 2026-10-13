extends SceneTree
## Actual game water and timber, isolated from normal saves and world generation.
var checks:=0
var failures:=0
var camera: Camera3D
var ocean: MeshInstance3D
var raft: Node3D
var clock: Node
var atmosphere: Node

func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int) -> void:
	for unused in count:await process_frame

func view_series(label: String,hour: float) -> void:
	clock.set("current_time",hour);clock.call("_update_celestial_coords")
	clock.get_node("Timer").emit_signal("timeout");atmosphere.call("_process",1.0)
	camera.position=Vector3(0,3,4.8);camera.look_at(Vector3(0,.25,-3))
	await frames(20)
	var water_stable:=true
	var raft_stable:=true
	var maximum_change:=0.0
	var previous_blue:=-1.0
	var minimum_timber:=100000
	for index in 24:
		camera.position=Vector3(sin(index*.35)*.65,3+sin(index*.27)*.12,4.8)
		camera.look_at(Vector3(0,.25,-3))
		await process_frame;await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image()
		var water:=Color(0,0,0,0)
		var samples:=0
		for y in range(550,680,8):
			for x in range(60,260,8):
				water+=picture.get_pixel(x,y);samples+=1
		water/=float(samples)
		water_stable=water_stable and water.b>.16 and water.b>water.r*1.25
		if previous_blue>=0:maximum_change=maxf(maximum_change,absf(water.b-previous_blue))
		previous_blue=water.b
		var timber:=0
		for y in range(280,620,6):
			for x in range(350,930,6):
				var colour:=picture.get_pixel(x,y)
				if colour.r>.02 and colour.r>colour.g*1.08 and colour.r>colour.b*1.1:timber+=1
		minimum_timber=mini(minimum_timber,timber)
		raft_stable=raft_stable and timber>40
		if index==23:check(picture.save_png("C:/GodotProjects/raft-survival/build/render-stability-"+label+".png")==OK,"Captured moving-camera "+label)
	print("STABILITY ",label," maximum water change ",maximum_change," minimum timber samples ",minimum_timber)
	check(water_stable and maximum_change<.12,"Water stays blue without a sudden frame brightness drop: "+label)
	check(raft_stable,"Timber remains rendered throughout camera movement: "+label)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(50).timeout.connect(func():push_error("FAIL: render stability timeout");quit(1))
	root.size=Vector2i(1280,720)
	root.get_node("Stats").set("enabled",false)
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	for child in scene.get_children():
		if str(child.name) not in ["Ocean","Sky3D","OceanAtmosphere","Raft"]:
			scene.remove_child(child);child.free()
	var packed:=PackedScene.new()
	check(packed.pack(scene)==OK,"Isolated fixture keeps actual ocean, sky and raft")
	scene.free();change_scene_to_packed(packed);await scene_changed
	ocean=current_scene.get_node("Ocean");raft=current_scene.get_node("Raft")
	clock=current_scene.get_node("Sky3D/TimeOfDay");clock.call("pause")
	atmosphere=current_scene.get_node("OceanAtmosphere");atmosphere.set_process(false)
	camera=Camera3D.new();camera.far=4000;current_scene.add_child(camera);camera.current=true
	check(ocean.extra_cull_margin>=absf(ocean.get("wave_height"))*.75,"Ocean visibility bounds contain shader wave displacement")
	check(ocean.ignore_occlusion_culling and ocean.get_node("FarWater").ignore_occlusion_culling,"Near and far moving water avoid static occluder rejection")
	var starter:=raft.get_node("StarterRaftVisual")
	var protected:=true
	for visual in starter.find_children("*","GeometryInstance3D",true,false):protected=protected and visual.ignore_occlusion_culling
	check(protected,"All starter raft timber and ropes remain visible around static occluders")
	var container:=raft.get_node("BuiltPieces")
	for kind in ["foundation","wall","roof"]:
		var piece: Node3D=load("res://scenes/"+kind+".tscn").instantiate()
		container.add_child(piece)
		piece.position=Vector3(3.35,2.6 if kind=="roof" else 0.0,0)
	var batch:=raft.get_node("ConstructionBatch");batch.call("refresh")
	var enclosed:=true
	var draws: Dictionary=batch.get("_draws")
	for instance in draws.values():
		enclosed=enclosed and instance.ignore_occlusion_culling
	# The dummy headless renderer cannot read back uploaded instance transforms.
	# Compare bounds to original scene geometry; native also checks GPU transforms.
	for piece in container.get_children():
		for visual in piece.find_children("*","MeshInstance3D",true,false):
			if visual.has_meta("structural_proxy"):continue
			var key: int=visual.mesh.get_instance_id()
			var expected: AABB=(raft.global_transform.affine_inverse()*visual.global_transform)*visual.mesh.get_aabb()
			enclosed=enclosed and draws.has(key) and draws[key].multimesh.custom_aabb.encloses(expected)
	if "--preview" in OS.get_cmdline_user_args():
		for instance in draws.values():
			for index in instance.multimesh.instance_count:
				var expected: AABB=instance.multimesh.get_instance_transform(index)*instance.multimesh.mesh.get_aabb()
				enclosed=enclosed and instance.multimesh.custom_aabb.encloses(expected)
	check(not draws.is_empty() and enclosed,"Batched walls, roofs and foundations have complete transformed visibility bounds")
	var initial_bounds: Dictionary={}
	for key in draws:initial_bounds[key]=draws[key].multimesh.custom_aabb
	batch.call("refresh")
	var retained:=true
	for key in draws:retained=retained and draws[key].multimesh.custom_aabb==initial_bounds[key]
	check(retained,"Unchanged construction keeps its existing batch bounds")
	if "--preview" in OS.get_cmdline_user_args():
		await view_series("day",12.0)
		await view_series("night",0.0)
	current_scene.queue_free();await frames(8)
	print("RENDER STABILITY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
