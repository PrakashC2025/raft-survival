extends RefCounted
const ART:=preload("res://scripts/machine_visual.gd")
static func ray() -> Node3D:
	var root:=Node3D.new();root.name="MantaRay"
	var skin:=StandardMaterial3D.new();skin.albedo_color=Color(.14,.21,.23);skin.roughness=.65
	var body:=SphereMesh.new();body.radius=.38;body.height=.20;body.radial_segments=24;body.rings=12
	var torso:=ART.part(root,body,Vector3.ZERO,skin,"RayBody");torso.scale.z=1.5
	for side in [-1,1]:
		var wing:=Node3D.new();wing.name="Leg_WingLeft" if side<0 else "Leg_WingRight";root.add_child(wing)
		var mesh:=SurfaceTool.new();mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in 16:
			var a:=float(index)/16*PI;var b:=float(index+1)/16*PI
			var p:=Vector3(side*(.20+sin(a)*.95),sin(a)*.025,-cos(a)*.56)
			var q:=Vector3(side*(.20+sin(b)*.95),sin(b)*.025,-cos(b)*.56)
			for vertex in ([Vector3.ZERO,p,q] if side>0 else [Vector3.ZERO,q,p]):mesh.add_vertex(vertex)
		mesh.generate_normals();var material:=skin.duplicate() as StandardMaterial3D;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		ART.part(wing,mesh.commit(),Vector3.ZERO,material,"FlexibleWing")
	var tail:=ART.cylinder(root,Vector3(0,0,.84),.018,.84,skin);tail.rotation.x=PI/2
	for side in [-1,1]:
		var eye:=SphereMesh.new();eye.radius=.025;eye.height=.05;eye.radial_segments=12;eye.rings=6
		var black:=StandardMaterial3D.new();black.albedo_color=Color(.008,.015,.02)
		ART.part(root,eye,Vector3(side*.19,.09,-.32),black,"RayEye")
	return root
