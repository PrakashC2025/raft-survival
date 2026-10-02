extends RefCounted
## Shared CC0 scenes: one cached resource per model, normalized without changing physics.
static var cache: Dictionary = {}
static func make(asset: String, length: float, grounded := false) -> Node3D:
	var path := "res://assets/mobile/" + asset + ".glb"
	if not ResourceLoader.exists(path):
		return null
	if not cache.has(path):
		cache[path] = load(path)
	var wrapper := Node3D.new()
	var model: Node3D = cache[path].instantiate()
	wrapper.add_child(model)
	var bounds := _bounds(model, Transform3D.IDENTITY)
	if bounds.size.length() > 0.001:
		var extent := bounds.size.y if asset == "survivor" else maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var ratio := length / maxf(extent, 0.001)
		wrapper.scale = Vector3.ONE * ratio
		model.position -= bounds.get_center()
		if grounded:
			model.position.y += bounds.size.y * 0.5
	for mesh in wrapper.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 90.0
	if asset == "survivor":
		var correction := preload("res://scripts/mobile_rig_pose.gd").new()
		wrapper.add_child(correction)
	return wrapper

static func _bounds(node: Node3D, parent: Transform3D) -> AABB:
	var xf := parent * node.transform
	var result := AABB()
	if node is MeshInstance3D:
		result = xf * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := _bounds(child, xf)
			if box.size.length() > 0.0:
				result = box if result.size.length() == 0.0 else result.merge(box)
	return result

static func animate(model: Node, hints: Array) -> void:
	for node in model.find_children("*", "AnimationPlayer", true, false):
		for hint: String in hints:
			for clip: String in node.get_animation_list():
				if clip.to_lower().contains(hint.to_lower()):
					node.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					if node.current_animation != clip:
						node.play(clip, 0.2)
					return

