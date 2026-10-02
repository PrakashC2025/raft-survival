extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var assets = load("res://scripts/mobile_assets.gd")
	for name in ["survivor", "bird", "shark", "boar", "fish", "bottle", "resource-stone"]:
		var model: Node3D = assets.make(name, 1.0)
		assert(model != null)
		root.add_child(model)
		var triangles := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			for surface in range(node.mesh.get_surface_count()):
				triangles += node.mesh.surface_get_array_index_len(surface) / 3
		var clips: Array = []
		for animator in model.find_children("*", "AnimationPlayer", true, false):
			clips.append_array(animator.get_animation_list())
		print(name, " triangles=", triangles, " scale=", model.scale, " clips=", clips)
		assert(triangles < 20000)
		if name == "survivor":
			assert(clips.has("idle") and clips.has("run"))
		model.queue_free()
	print("MOBILE MODELS VALID")
	quit()
