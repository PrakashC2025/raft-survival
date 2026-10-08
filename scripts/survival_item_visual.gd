extends RefCounted
static func create(item: String) -> Node3D:
	var root:=Node3D.new();root.name="SurvivalItem"
	var material:=StandardMaterial3D.new();material.roughness=.7
	var mesh: Mesh
	if item=="Medkit":
		var box:=BoxMesh.new();box.size=Vector3(.23,.14,.08);mesh=box;material.albedo_color=Color(.82,.84,.77)
	elif item.ends_with("Can"):
		var can:=CylinderMesh.new();can.top_radius=.075;can.bottom_radius=.075;can.height=.19;can.radial_segments=16;mesh=can;material.albedo_color=Color(.50,.57,.59);material.metallic=.65
	else:
		var bowl:=CylinderMesh.new();bowl.top_radius=.12;bowl.bottom_radius=.08;bowl.height=.08;bowl.radial_segments=16;mesh=bowl;material.albedo_color=Color(.40,.25,.13)
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;root.add_child(visual)
	if item=="Medkit":
		var red:=StandardMaterial3D.new();red.albedo_color=Color(.72,.12,.12)
		for size in [Vector3(.09,.024,.002),Vector3(.024,.09,.002)]:
			var cross:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;cross.mesh=box;cross.position.z=.041;cross.material_override=red;root.add_child(cross)
	elif item!="Can":
		var top:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=.068 if item.ends_with("Can") else .108;disc.bottom_radius=disc.top_radius;disc.height=.005;disc.radial_segments=16
		top.mesh=disc;top.position.y=.09 if item.ends_with("Can") else .042
		var fill:=StandardMaterial3D.new();fill.albedo_color=Color(.28,.50,.63) if item=="Clean Water Can" else (Color(.29,.25,.12) if item=="Dirty Water Can" else Color(.66,.34,.12));top.material_override=fill;root.add_child(top)
	return root
