extends RefCounted
## Small in-session scoop marks deepen when sand is collected nearby.
static var _holes: Array[Dictionary] = []

static func dig(world_position: Vector3) -> void:
	var tree:=Engine.get_main_loop() as SceneTree
	var root:=tree.current_scene as Node3D if tree!=null else null
	if root==null:return
	var mark: MeshInstance3D
	var record: Dictionary
	for candidate in _holes:
		var node:=candidate.get("node") as MeshInstance3D
		if is_instance_valid(node) and Vector2(candidate.position.x-world_position.x,candidate.position.z-world_position.z).length()<.42:
			record=candidate;mark=node;break
	if mark==null:
		if _holes.size()>=24:
			var oldest: Dictionary = _holes.pop_front()
			var old_node:=oldest.get("node") as Node3D
			if is_instance_valid(old_node):old_node.queue_free()
		mark=MeshInstance3D.new();mark.name="FreshSandScoop"
		var material:=StandardMaterial3D.new();material.albedo_color=Color(.24,.17,.105);material.roughness=1.0
		mark.material_override=material;mark.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mark);mark.global_position=world_position+Vector3.UP*.003
		record={"node":mark,"position":world_position,"radius":.18,"depth":.035};_holes.append(record)
	else:
		record.radius=minf(float(record.radius)+.055,.52);record.depth=minf(float(record.depth)+.01,.08)
		mark.global_position.y=world_position.y+.003
	mark.mesh=_bowl(float(record.radius),float(record.depth))

static func _bowl(radius: float,depth: float) -> ArrayMesh:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS:=28
	var radial: Array[float]=[.04,.34,.66,1.0];var heights: Array[float]=[0.0,.04,.3,1.0]
	for ring in range(radial.size()-1):
		for segment in SEGMENTS:
			var a:=TAU*float(segment)/SEGMENTS;var b:=TAU*float(segment+1)/SEGMENTS
			for point in [Vector3(cos(a)*radial[ring],depth*heights[ring],sin(a)*radial[ring]),Vector3(cos(b)*radial[ring],depth*heights[ring],sin(b)*radial[ring]),Vector3(cos(a)*radial[ring+1],depth*heights[ring+1],sin(a)*radial[ring+1]),Vector3(cos(b)*radial[ring],depth*heights[ring],sin(b)*radial[ring]),Vector3(cos(b)*radial[ring+1],depth*heights[ring+1],sin(b)*radial[ring+1]),Vector3(cos(a)*radial[ring+1],depth*heights[ring+1],sin(a)*radial[ring+1])]:surface.add_vertex(point*radius)
	surface.generate_normals();return surface.commit()
