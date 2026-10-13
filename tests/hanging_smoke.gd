extends SceneTree
const DATA:=preload("res://scripts/biome_mesh_data.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	root.get_node("Stats").enabled=false
	for biome in ["volcano","winter","spring"]:
		var builder:=DATA.new()
		var task:=WorkerThreadPool.add_task(builder.build.bind(biome,52,44.0))
		while not WorkerThreadPool.is_task_completed(task):await process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var vertices: PackedVector3Array=builder.arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=builder.arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array=builder.arrays[Mesh.ARRAY_NORMAL]
		check(vertices.size()==2809 and indices.size()==16224 and normals.size()==vertices.size(),biome+" retains the complete indexed terrain")
		var geometry:=true
		for index in [0,52,1404,2187,2808]:
			var point:=Vector2(vertices[index].x,vertices[index].z)
			geometry=geometry and absf(vertices[index].y-DATA.height_at(point,biome,44.0))<.00001 and normals[index].is_finite() and absf(normals[index].length()-1)<.00001
		check(geometry,biome+" worker publishes finite geometry with the existing surface heights")
		var image:=Image.create_from_data(32,32,false,Image.FORMAT_RF,builder.shore_bytes)
		check(absf(image.get_pixel(13,17).r-DATA.height_at(Vector2(13.5/32*88-44,17.5/32*88-44),biome,44.0))<.00001,biome+" shoreline mask preserves the same terrain data")
	var stage:=Node3D.new();root.add_child(stage);current_scene=stage
	var island:=load("res://scripts/biome_island.gd").new() as Node3D;stage.add_child(island)
	await process_frame;await process_frame
	island.queue_free()
	for unused in 4:await process_frame
	check(not is_instance_valid(island),"Closing while island data is preparing joins and releases the worker safely")
	stage.queue_free();await process_frame
	print("HANGING SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
