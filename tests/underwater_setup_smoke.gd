extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	root.get_node("Stats").enabled = false
	var stage := Node3D.new(); root.add_child(stage); current_scene = stage
	var sea := load("res://scripts/underwater_world.gd").new() as Node3D
	stage.add_child(sea)
	var deadline := Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline and not sea.get("prepared"): await process_frame
	checks += 1
	if not sea.get("prepared"):
		failures += 1
		push_error("FAIL: isolated sea setup: "+str(sea.get_children().map(func(node:Node):return str(node.name))))
	else: print("PASS: underwater terrain, ruins and creatures finish asynchronous setup")
	checks += 1
	if int(sea.get("_mesh_task")) != -1 or sea.get("_mesh_data") != null:
		failures += 1; push_error("FAIL: completed ocean task retains worker state")
	else: print("PASS: completed ocean geometry releases worker state")
	var cancelled := load("res://scripts/underwater_world.gd").new() as Node3D
	stage.add_child(cancelled)
	await process_frame
	cancelled.queue_free()
	for unused in 3: await process_frame
	checks += 1
	if is_instance_valid(cancelled):
		failures += 1; push_error("FAIL: interrupted ocean setup cannot exit")
	else: print("PASS: interrupted ocean setup exits safely")
	print("UNDERWATER SETUP SMOKE: %d checks, %d failures"%[checks,failures])
	stage.queue_free(); await process_frame
	quit(1 if failures else 0)
