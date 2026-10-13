extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("FAIL: single coconut timeout"); quit(1))
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)
func frames() -> void:
	for unused in 4: await process_frame
func stem_count(mesh: Mesh) -> int:
	# Weld UV seams before counting connected triangle components: the old
	# asset hid two complete stems in a single MeshInstance, not two nodes.
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var graph: Dictionary = {}
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]].snapped(Vector3.ONE * .0001)
		var b := vertices[indices[i+1]].snapped(Vector3.ONE * .0001)
		var c := vertices[indices[i+2]].snapped(Vector3.ONE * .0001)
		for pair in [[a,b],[b,c],[c,a]]:
			if not graph.has(pair[0]): graph[pair[0]] = []
			if not graph.has(pair[1]): graph[pair[1]] = []
			graph[pair[0]].append(pair[1]); graph[pair[1]].append(pair[0])
	var seen: Dictionary = {}; var count := 0
	for vertex in graph:
		if seen.has(vertex): continue
		count += 1; var pending: Array = [vertex]
		while not pending.is_empty():
			var point: Vector3 = pending.pop_back()
			if seen.has(point): continue
			seen[point] = true
			pending.append_array(graph[point])
	return count
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.size = Vector2i(1280,720); root.get_node("Stats").enabled = false
	var stage := Node3D.new(); root.add_child(stage); current_scene = stage
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color(.22,.43,.66)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = .8
	stage.add_child(world)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-30,0); stage.add_child(sun)
	var camera := Camera3D.new(); stage.add_child(camera); camera.current = true
	var pot: Node3D = load("res://scenes/tree_pot.tscn").instantiate(); stage.add_child(pot)
	check(pot.plant_seed("Coconut"),"One coconut seeds the pot")
	check(not pot.plant_seed("Coconut"),"An occupied pot cannot create a second plant")
	var plant: Node3D = pot._plant; plant.set_process(false)
	for growth_stage in 4:
		plant.restore_state({"id":"Coconut","stage":growth_stage,"timer":0}); await frames()
		if growth_stage >= 2:
			var trunk := plant._container.find_child("Tree_0_Trunk",true,false) as MeshInstance3D
			check(trunk != null and stem_count(trunk.mesh)==1,"Coconut stage %d has exactly one connected palm stem" % growth_stage)
		check(growth_stage==3 or plant._fruits.is_empty(),"Stage %d keeps fruit until maturity" % growth_stage)
		camera.position = Vector3(1.8,1.1,2.4) if growth_stage<2 else Vector3(6,4,8)
		camera.look_at(Vector3.UP * (.3 if growth_stage<2 else 2.5))
		if "--preview" in OS.get_cmdline_user_args():
			await frames(); await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/single-coconut-stage-%d.png" % growth_stage)==OK,"Rendered coconut stage %d" % growth_stage)
	var saved: Dictionary = plant.save_state()
	pot.queue_free(); await frames()
	var restored: Node3D = load("res://scenes/tree_pot.tscn").instantiate(); stage.add_child(restored)
	restored.restore_plant_state(saved); restored._plant.set_process(false); await frames()
	var restored_trunk := restored._plant._container.find_child("Tree_0_Trunk",true,false) as MeshInstance3D
	check(stem_count(restored_trunk.mesh)==1 and restored._plant._stage==3,"Continue restores one mature palm without restarting growth")
	check(restored._plant._fruits.size()==saved.fruits.size(),"Single palm keeps saved fruit slots")
	if "--preview" in OS.get_cmdline_user_args():
		# Render the real touch control in its swimming appearance; actual
		# finger ownership, speeds and exhaustion are covered by mobile_smoke.
		var layer := CanvasLayer.new(); stage.add_child(layer)
		var controls: Control = load("res://scripts/mobile_controls.gd").new()
		controls.force_show = true; layer.add_child(controls); controls.set_process(false)
		controls._swimming = true
		for button in controls._all_buttons: button.hide()
		controls._btn_run.show(); controls.queue_redraw()
		await frames(); await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/fast-swim-control.png")==OK,"Rendered fast swim control")
	stage.queue_free(); await frames()
	print("SINGLE COCONUT SMOKE: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
