extends RefCounted
## Original curved beach flowers. One shared mesh in the existing foliage batch.
static var _mesh: ArrayMesh
static func meadow_mesh() -> ArrayMesh:
	if _mesh!=null:return _mesh
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for flower in 3:
		var offset:=Vector3((flower-1)*.12,0,sin(flower*2.4)*.095)
		var height:=.30+flower*.075
		var stem:=CylinderMesh.new();stem.top_radius=.003;stem.bottom_radius=.005;stem.height=height;stem.radial_segments=6
		preload("res://scripts/meal_visual.gd")._append(surface,stem,Transform3D(Basis.IDENTITY,offset+Vector3.UP*height*.5),Color(.17,.32,.065))
		var petals:=9 if flower==0 else 7
		for petal in petals:
			var angle:=petal*TAU/petals+flower*.8
			var at:=offset+Vector3(.025,height,0)
			var basis:=Basis(Vector3.UP,angle)*Basis(Vector3.FORWARD,float(flower-1)*.10)
			var tint:=Color(.96,.90,.71) if flower==0 else (Color(.91,.37,.36) if flower==1 else Color(.75,.60,.93))
			_leaf(surface,Transform3D(basis,at),.075,.025,tint,true)
		var centre:=SphereMesh.new();centre.radius=.017;centre.height=.018;centre.radial_segments=12;centre.rings=6
		preload("res://scripts/meal_visual.gd")._append(surface,centre,Transform3D(Basis.IDENTITY,offset+Vector3(0,height+.009,0)),Color(.91,.59,.045))
		for side in 2:
			_leaf(surface,Transform3D(Basis(Vector3.UP,side*PI+flower)*Basis(Vector3.FORWARD,-.35),offset+Vector3.UP*height*(.30+side*.23)),.105,.019,Color(.18,.38,.075),false)
	surface.index();surface.generate_normals();_mesh=surface.commit()
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/flower_petals.gdshader");_mesh.surface_set_material(0,material)
	return _mesh

static func _leaf(surface: SurfaceTool,transform: Transform3D,length_value: float,width: float,tint: Color,petal: bool) -> void:
	for row in 6:
		for column in 4:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var u:=float(row+corner.x)/6;var v:=float(column+corner.y)/4
				var across:=(v-.5)*2
				var edge:=pow(sin(u*PI),.62)
				var curve:=(-.012*sin(u*PI)+.027*u*u+across*across*.009) if petal else sin(u*PI)*.018
				surface.set_color(Color(tint.r,tint.g,tint.b,1.0 if petal else .0));surface.set_uv(Vector2(u,v))
				surface.add_vertex(transform*Vector3(u*length_value,curve,across*edge*width))
