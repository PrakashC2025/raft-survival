extends RefCounted
## Original weighted basket. The woven strands share one cached mesh.
const PARTS:=preload("res://scripts/machine_visual.gd")
const MAT:=preload("res://scripts/object_materials.gd")
static var _mesh: ImmediateMesh
static func strand(mesh: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	var along:=(b-a).normalized()
	var across:=along.cross(Vector3.RIGHT if absf(along.y)>.9 else Vector3.UP).normalized()*.006
	var other:=along.cross(across).normalized()*.006
	for side in 3:
		var angle:=TAU*side/3.0;var next:=TAU*(side+1)/3.0
		var p:=across*cos(angle)+other*sin(angle);var q:=across*cos(next)+other*sin(next)
		for vertex in [a+p,b+p,b+q,a+p,b+q,a+q]:
			mesh.surface_set_normal((p+q).normalized());mesh.surface_add_vertex(vertex)
static func create() -> Node3D:
	var root:=Node3D.new();root.name="WeightedFishNet"
	for side in [-1.0,1.0]:PARTS.timber_box(root,Vector3(side*.54,0,-.18),Vector3(.055,.065,1.22))
	PARTS.timber_box(root,Vector3(0,0,-.65),Vector3(1.13,.055,.055))
	if _mesh==null:
		_mesh=ImmediateMesh.new();_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in 9:
			var p:float=-.48+index*.12
			strand(_mesh,Vector3(p,-.03,-.45),Vector3(p*.72,-.85,-.32))
			strand(_mesh,Vector3(p,-.03,.45),Vector3(p*.72,-.85,.32))
			strand(_mesh,Vector3(-.51,-.03,p),Vector3(-.37,-.85,p*.72))
			strand(_mesh,Vector3(.51,-.03,p),Vector3(.37,-.85,p*.72))
			strand(_mesh,Vector3(p*.72,-.85,-.32),Vector3(p*.72,-.85,.32))
		for level in 8:
			var t:float=level/7.0;var x:float=lerpf(.51,.37,t);var z:float=lerpf(.45,.32,t);var y:float=lerpf(-.03,-.85,t)
			strand(_mesh,Vector3(-x,y,-z),Vector3(x,y,-z));strand(_mesh,Vector3(-x,y,z),Vector3(x,y,z))
			strand(_mesh,Vector3(-x,y,-z),Vector3(-x,y,z));strand(_mesh,Vector3(x,y,-z),Vector3(x,y,z))
		_mesh.surface_end()
	PARTS.part(root,_mesh,Vector3.ZERO,MAT.worn(MAT.Kind.CLOTH,Color(.30,.28,.18),1.0),"WovenRope")
	for side in [-1.0,1.0]:PARTS.box(root,Vector3(side*.34,-.85,0),Vector3(.08,.06,.13),MAT.worn(MAT.Kind.STONE,Color(.30,.32,.29),.98))
	return root
