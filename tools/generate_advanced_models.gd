extends "res://tools/generate_survival_models.gd"
## Original modeled salvage equipment, meat and streamlined shark.
func _run() -> void:
	for cooked in [false,true]:
		var root_node := Node3D.new()
		root_node.name = "CookedMeat" if cooked else "RawMeat"
		oval(root_node,Vector3.ZERO,Vector3(0.16,0.045,0.11),mat(Color(0.26,0.13,0.065) if cooked else Color(0.44,0.10,0.07),0.7),"Meat")
		oval(root_node,Vector3(0.1,0.004,0.005),Vector3(0.065,0.042,0.09),mat(Color(0.60,0.45,0.28) if cooked else Color(0.71,0.62,0.49),0.85),"FatEdge")
		export_model(root_node,"cooked_meat" if cooked else "raw_meat")
	var tank := Node3D.new()
	tank.name = "DivingTank"
	var alloy := mat(Color(0.36,0.43,0.41),0.43,0.72)
	var rubber := mat(Color(0.025,0.03,0.026),0.9)
	tube(tank,Vector3(0,-0.2,0),Vector3(0,0.18,0),0.11,alloy,"Cylinder")
	tube(tank,Vector3(0,0.2,0),Vector3(0,0.28,0),0.025,alloy,"Valve")
	tube(tank,Vector3(-0.045,0.29,0),Vector3(0.045,0.29,0),0.012,rubber,"Tap")
	for i in range(12):
		var a := float(i)/12.0*PI
		var b := float(i+1)/12.0*PI
		tube(tank,Vector3(0.15*sin(a),0.28-0.4*(1-cos(a))/2,0.025),Vector3(0.15*sin(b),0.28-0.4*(1-cos(b))/2,0.025),0.008,rubber,"AirHose")
	export_model(tank,"diving_tank")
	var shark := Node3D.new()
	shark.name = "ReefShark"
	var sea_skin := mat(Color.WHITE,0.48)
	sea_skin.vertex_color_use_as_albedo = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var sections := [Vector3(-1.65,0.015,0.015),Vector3(-1.45,0.17,0.12),Vector3(-1.1,0.32,0.25),Vector3(-0.55,0.40,0.33),Vector3(0.05,0.38,0.32),Vector3(0.65,0.25,0.22),Vector3(1.15,0.10,0.11),Vector3(1.55,0.045,0.045)]
	for ring in range(sections.size()-1):
		for side in range(32):
			for pair in [Vector2i(ring,side),Vector2i(ring+1,side),Vector2i(ring,side+1),Vector2i(ring,side+1),Vector2i(ring+1,side),Vector2i(ring+1,side+1)]:
				var section: Vector3 = sections[pair.x]
				var angle: float = TAU*float(pair.y)/32.0
				var belly := smoothstep(0.25,0.75,-sin(angle))
				surface.set_color(Color(0.23,0.30,0.31).lerp(Color(0.73,0.76,0.71),belly))
				surface.set_uv(Vector2(float(pair.x)/(sections.size()-1),float(pair.y)/32))
				surface.add_vertex(Vector3(cos(angle)*section.y,sin(angle)*section.z,section.x))
	surface.generate_normals()
	surface.index()
	part(shark,surface.commit(),sea_skin,Vector3.ZERO,Vector3.ONE,"StreamlinedBody")
	var fin_skin := mat(Color(0.24,0.30,0.31),0.65)
	membrane(shark,[Vector3(0,0.29,-0.35),Vector3(0,0.83,0.05),Vector3(0,0.23,0.37)],fin_skin,"DorsalFin")
	for side in [-1.0,1.0]:
		membrane(shark,[Vector3(side*0.25,-0.13,-0.5),Vector3(side*0.99,-0.30,0.15),Vector3(side*0.24,-0.2,0.20)],fin_skin,"Pectoral")
		oval(shark,Vector3(side*0.22,0.05,-1.28),Vector3.ONE*0.018,mat(Color(0.013,0.016,0.012),0.15),"Eye")
		for i in range(4):
			tube(shark,Vector3(side*(0.34+i*0.01),0.1,-0.78+i*0.05),Vector3(side*(0.32+i*0.01),-0.12,-0.72+i*0.05),0.003,mat(Color(0.12,0.17,0.17)),"Gill")
	var tail := Node3D.new()
	tail.name = "TailFin"
	tail.position.z = 1.50
	shark.add_child(tail)
	membrane(tail,[Vector3(0,0,0),Vector3(0,0.65,0.29),Vector3(0,0.1,0.14),Vector3(0,-0.39,0.31),Vector3(0,-0.07,-0.06)],fin_skin,"CaudalFin")
	export_model(shark,"reef_shark")
	quit()
