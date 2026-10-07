extends RefCounted
const ART := preload("res://scripts/machine_visual.gd")
const MAT := preload("res://scripts/object_materials.gd")
const TIMBER := preload("res://scripts/construction_visual.gd")
static func _cylinder(radius: float,height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=24
	return mesh
static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new();mesh.size=size
	return mesh
static func create(metal_container: bool=false) -> Node3D:
	var root := Node3D.new()
	root.name="SandFilterLayers"
	var steel := MAT.make(MAT.Kind.METAL,Color(0.44,0.47,0.43),0.48,0.65)
	var can := MAT.make(MAT.Kind.PLASTIC,Color(0.28,0.38,0.33),0.65)
	if metal_container:can=steel
	for x in [-0.40,0.40]:
		for z in [-0.36,0.36]:
			var leg := ART.part(root,TIMBER.rounded_timber(Vector3(0.075,1.48,0.075),1.0),Vector3(x,0,z),null,"TimberLeg")
			leg.rotation.z=-x*0.1
	for y in [-0.4,0.36]:
		for z in [-0.36,0.36]:
			ART.part(root,TIMBER.rounded_timber(Vector3(0.89,0.07,0.07),1.0),Vector3(0,y,z),null,"CrossBrace")
	for y in [-0.4,0.36]:
		for x in [-0.40,0.40]:
			for z in [-0.36,0.36]:
				ART.part(root,TIMBER.rope_knot(),Vector3(x,y,z),null,"RopeLashing")
	# Open inspection side: the can has real layered fill, not a tiny bottle.
	var shell := CylinderMesh.new()
	shell.top_radius=0.31;shell.bottom_radius=0.27;shell.height=0.75;shell.radial_segments=32
	shell.cap_top=false;shell.cap_bottom=false
	var arrays := shell.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for i in range(0,indices.size(),3):
		var mid := (vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
		if not (mid.z>0.05 and absf(mid.x)<0.22):
			kept.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
	arrays[Mesh.ARRAY_INDEX]=kept
	var cut := ArrayMesh.new();cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ART.part(root,cut,Vector3(0,0.23,0),can,"CutawayCan")
	var sponge := ShaderMaterial.new();sponge.shader=preload("res://shaders/sponge_surface.gdshader")
	ART.part(root,_cylinder(0.258,0.17),Vector3(0,-0.065,0),sponge,"SpongeLayer")
	var sand := ShaderMaterial.new();sand.shader=preload("res://shaders/sand_surface.gdshader")
	sand.set_shader_parameter("sand_color",Color(0.63,0.49,0.28));sand.set_shader_parameter("grain_scale",44.0)
	ART.part(root,_cylinder(0.275,0.38),Vector3(0,0.21,0),sand,"SandBed")
	var top := preload("res://scripts/soil_visual.gd").create(Vector2(0.56,0.56),true,Color(0.62,0.48,0.28))
	top.name="LooseSandTop";top.position.y=0.414;root.add_child(top)
	ART.part(root,_cylinder(0.065,0.10),Vector3(0,-0.20,0),steel,"Outlet")
	var tank := ART.part(root,_cylinder(0.25,0.34),Vector3(0,-0.535,0),can,"CatchCan")
	var handle := ART.part(root,_box(Vector3(0.34,0.035,0.035)),Vector3(0,-0.33,0.22),steel,"TankHandle")
	handle.rotation.z=0.1
	var liquid := StandardMaterial3D.new();liquid.albedo_color=Color(0.15,0.37,0.39);liquid.roughness=0.16
	ART.part(root,_cylinder(0.21,0.015),Vector3(0,-0.365,0),liquid,"CollectedWater")
	ART.part(root,_cylinder(0.009,0.12),Vector3(0,-0.30,0),liquid,"FilterDrip")
	tank.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root
