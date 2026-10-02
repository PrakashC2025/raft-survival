extends Node3D
## A short skippable in-engine prologue; gameplay control returns on the raft.
var director: Node
var camera: Camera3D
var island: Node3D
var layer: CanvasLayer
var caption: Label
var time := 0.0
var quake_started := false
var finished := false

func _ready() -> void:
	island = director.world.make_island(Vector3(0, 0, 65), "HomeBeforeTheDeluge")
	for i in range(7):
		var tree := PlantInstance.new()
		tree.plant_id = "Coconut"
		tree.start_stage = 3
		tree.position = Vector3(-8 + i * 2.5, 2.5, -6)
		island.add_child(tree)
	camera = Camera3D.new()
	camera.far = 800
	add_child(camera)
	camera.current = true
	director.player.set_physics_process(false)
	director.player.set_process(false)
	director.player.set_process_unhandled_input(false)
	Stats.enabled = false
	layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	caption.position = Vector2(24, 60)
	caption.add_theme_font_size_override("font_size", 24)
	caption.text = "BEFORE THE DELUGE\nAnother morning on your home island..."
	layer.add_child(caption)
	var skip := Button.new()
	skip.text = "Skip opening"
	skip.position = Vector2(24, 150)
	skip.pressed.connect(finish)
	layer.add_child(skip)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if finished:
		return
	time += delta
	camera.global_position = Vector3(0, 4.2, 73.0 - minf(time, 7.0) * 1.1)
	camera.rotation = Vector3(-0.05, 0, 0)
	if time > 6.0:
		if not quake_started:
			quake_started = true
			director.audio.play("quake")
			caption.text = "The ground breaks. The sea rises.\nRun for the shore!"
		camera.position += Vector3(randf_range(-0.05, 0.05), randf_range(-0.06, 0.06), 0)
	if time > 10.0:
		island.position.y = -(time - 10.0) * 1.5
		camera.global_position = Vector3(0, 4.2 + (time - 10.0) * 0.3, 65 + (time - 10.0) * 6.0)
		camera.look_at(Vector3(0, -1, 65))
		caption.text = "Your island disappears beneath the waves.\nOne survivor. One raft. A chance to begin again."
	if time >= 18.0:
		finish()

func finish() -> void:
	if finished:
		return
	finished = true
	island.queue_free()
	director.player.camera.current = true
	director.player.set_physics_process(true)
	director.player.set_process(true)
	director.player.set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Stats.enabled = true
	director.intro_seen = true
	director.intro_running = false
	director.call("_checkpoint")
	director.call("_say", "Collect debris. Build shelter. Search the surviving islands.")
	queue_free()
