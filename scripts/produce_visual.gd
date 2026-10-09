extends RefCounted
## Original shared produce geometry and procedural skin; no runtime textures or downloads.
const SKIN := preload("res://shaders/produce_skin.gdshader")
static var meshes: Dictionary = {}
static var materials: Dictionary = {}

static func create(item: String) -> Node3D:
	var kind := "Potato" if item == "Baked Potato" else item
	var root := Node3D.new();root.name=kind+"Produce"
	var mesh := MeshInstance3D.new()
	if not meshes.has(kind): meshes[kind] = _banana() if kind == "Banana" else _round(kind == "Tomato")
	if not materials.has(kind):
		var skin := ShaderMaterial.new();skin.shader=SKIN
		skin.set_shader_parameter("produce_kind",2 if kind=="Banana" else (1 if kind=="Tomato" else 0))
		materials[kind]=skin
	mesh.mesh=meshes[kind];mesh.material_override=materials[kind];root.add_child(mesh)
	if kind == "Tomato":
		var green := StandardMaterial3D.new();green.albedo_color=Color(0.12,0.24,0.025);green.roughness=0.85
		var stem := MeshInstance3D.new();var cylinder := CylinderMesh.new()
		cylinder.top_radius=0.003;cylinder.bottom_radius=0.006;cylinder.height=0.035;cylinder.radial_segments=8
		stem.mesh=cylinder;stem.position.y=0.077;stem.rotation.z=0.24;stem.material_override=green;root.add_child(stem)
		for i in 5:
			var leaf := MeshInstance3D.new();var blade:=PrismMesh.new();blade.size=Vector3(0.015,0.003,0.06)
			leaf.mesh=blade;leaf.material_override=green;leaf.rotation.y=float(i)*TAU/5
			leaf.position=Vector3(sin(leaf.rotation.y)*0.016,0.063,cos(leaf.rotation.y)*0.016)
			root.add_child(leaf)
	return root

static func _round(tomato: bool) -> ArrayMesh:
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 16;var sides:=32
	for ring in range(rings+1):
		var v:=float(ring)/rings;var latitude:=v*PI
		for side in range(sides+1):
			var u:=float(side)/sides;var angle:=u*TAU
			var radius:=sin(latitude)
			var ripple:=1.0+0.045*cos(angle*7.0)*radius if tomato else 1.0+0.055*sin(angle*3.0+latitude*4.0)+0.035*cos(angle*5.0-latitude*3.0)
			var size:=Vector3(0.084,0.067,0.084) if tomato else Vector3(0.08,0.055,0.115)
			st.set_uv(Vector2(u,v))
			var y := cos(latitude)
			if tomato: y *= 1.0-0.12*pow(absf(y),12.0)
			else: y += sin(angle*2.0+latitude)*radius*0.055
			st.add_vertex(Vector3(cos(angle)*radius*ripple,y,sin(angle)*radius*ripple)*size)
	for ring in rings:
		for side in sides:
			var a:=ring*(sides+1)+side;var b:=a+sides+1
			for index in [a,b,a+1,a+1,b,b+1]:st.add_index(index)
	st.generate_normals();return st.commit()

static func _banana() -> ArrayMesh:
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections:=28;var sides:=12
	for section in range(sections+1):
		var t:=float(section)/sections;var angle:=lerpf(-1.1,1.1,t)
		var center:=Vector3(sin(angle)*0.16,(1.0-cos(angle))*0.16,0)
		var normal:=Vector3(-sin(angle),cos(angle),0)
		var radius:=0.023*pow(maxf(sin(t*PI),0.02),0.35)
		for side in range(sides+1):
			var u:=float(side)/sides;var turn:=u*TAU
			st.set_uv(Vector2(u,t))
			st.add_vertex(center+normal*cos(turn)*radius+Vector3.BACK*sin(turn)*radius*0.85)
	for section in sections:
		for side in sides:
			var a:=section*(sides+1)+side;var b:=a+sides+1
			for index in [a,a+1,b,a+1,b+1,b]:st.add_index(index)
	st.generate_normals();return st.commit()
