extends RefCounted
## Flatten the supplied asset's FBX unit/axis transforms when fitting a prop.
## Flying arrows duplicate the prepared prototype rather than refitting it.
## The original scene is already in metres; another .025 scale made arrows tiny.
const SOURCE: PackedScene=preload("res://3d models/Wooded_arrow/cc0_-_wooden_arrow.glb")
static func create(length_metres: float=.72) -> Node3D:
	var parts: Array[Dictionary]=[]
	var combined_bounds:=AABB()
	var source:=SOURCE.instantiate() as Node3D
	var alignment:=Basis.IDENTITY
	var first:=true
	for candidate in source.find_children("*","MeshInstance3D",true,false):
		var part:=candidate as MeshInstance3D
		if part.mesh==null:continue
		var tf:=part.transform
		var ancestor:=part.get_parent()
		while ancestor is Node3D:
			tf=(ancestor as Node3D).transform*tf
			if ancestor==source:break
			ancestor=ancestor.get_parent()
		# The imported shaft points toward its local -Z tip, with the nock at +Z.
		if first:alignment=Basis(Quaternion(-tf.basis.z.normalized(),Vector3.FORWARD))
		tf=Transform3D(alignment,Vector3.ZERO)*tf
		var bounds: AABB=tf*part.mesh.get_aabb()
		combined_bounds=bounds if first else combined_bounds.merge(bounds)
		first=false
		parts.append({"mesh":part.mesh,"transform":tf,"material":part.get_active_material(0)})
	source.free()
	var root:=Node3D.new();root.name="WoodenArrow"
	var fit:=length_metres/maxf(combined_bounds.size.z,.001)
	var centered:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*fit),-combined_bounds.get_center()*fit)
	for data in parts:
		var mesh:=MeshInstance3D.new();mesh.mesh=data.mesh;mesh.transform=centered*data.transform
		mesh.material_override=data.material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(mesh)
	return root
