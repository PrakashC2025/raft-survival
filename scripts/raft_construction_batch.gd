extends Node3D
## Merge repeated timber into shared MultiMesh draws while individual scene roots
## retain collisions, sockets and save identity. Rebuild only after topology or
## transforms change. Edited pieces render separately with their highlight.
var _elapsed := 0.0
var _signature := -1
var _draws: Dictionary = {}

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	refresh()

func refresh() -> void:
	var container := get_parent().get_node_or_null("BuiltPieces")
	if container == null: return
	if container.get_meta("restoring",false): return
	var player := get_tree().get_first_node_in_group("player")
	var editing: Node = player.get("_editing") if player != null else null
	var signature := hash(editing)
	var pieces: Array[Node3D] = []
	for child in container.get_children():
		if not child is Node3D or child.is_queued_for_deletion(): continue
		# Torches have animated transparent flames and instance overrides;
		# prefix matching WallTorch as a static Wall strips these materials.
		if child.name.begins_with("WallTorch"): continue
		if not (child.name.begins_with("Foundation") or child.name.begins_with("Wall") or child.name.begins_with("HalfWall") or child.name.begins_with("Roof")): continue
		pieces.append(child)
		signature = hash([signature,child.get_instance_id(),child.transform,child.get_meta("geometry_revision",0)])
	if signature == _signature: return
	_signature = signature
	var groups := {}
	for piece in pieces:
		var highlighted := piece == editing
		for node in piece.find_children("*", "GeometryInstance3D", true, false):
			var hidden := false
			var ancestor: Node = node
			while ancestor != piece:
				if ancestor.get_meta("stair_hidden",false): hidden=true;break
				ancestor=ancestor.get_parent()
			if hidden:node.visible=false;continue
			if node.has_meta("structural_proxy"):
				node.visible = false
				continue
			if not (node is MeshInstance3D or node is MultiMeshInstance3D): continue
			node.visible = highlighted
			if highlighted: continue
			var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
			var key := mesh.get_instance_id()
			if not groups.has(key): groups[key] = {"mesh":mesh,"transforms":[],"range":node.visibility_range_end}
			var relative: Transform3D = get_parent().global_transform.affine_inverse() * node.global_transform
			if node is MeshInstance3D:
				groups[key].transforms.append(relative)
			else:
				for index in node.multimesh.instance_count:
					groups[key].transforms.append(relative * node.multimesh.get_instance_transform(index))
	for key in _draws.keys():
		if not groups.has(key):
			_draws[key].queue_free()
			_draws.erase(key)
	for key in groups:
		var group: Dictionary = groups[key]
		var instance: MultiMeshInstance3D
		if not _draws.has(key):
			instance = MultiMeshInstance3D.new()
			instance.multimesh = MultiMesh.new()
			instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			instance.multimesh.use_custom_data = true
			instance.multimesh.mesh = group.mesh
			instance.visibility_range_end = group.range
			add_child(instance)
			_draws[key] = instance
		else: instance = _draws[key]
		instance.multimesh.instance_count = group.transforms.size()
		for index in group.transforms.size():
			var transform: Transform3D = group.transforms[index]
			instance.multimesh.set_instance_transform(index,transform)
			var seed_value := fposmod(sin(transform.origin.x*17.31+transform.origin.z*9.17)*43758.5,1.0)
			instance.multimesh.set_instance_custom_data(index,Color(seed_value,0,0,1))
