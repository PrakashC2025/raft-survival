extends RefCounted
## Original cached crop/produce meshes, curled veined leaves and visible cut faces.
const ITEMS:=preload("res://scripts/garden_items.gd")
const PARTS:=preload("res://scripts/machine_visual.gd")
const SHADER:=preload("res://shaders/garden_skin.gdshader")
static var _meshes: Dictionary={}
static var _materials: Dictionary={}
const COLORS:=[Color(.77,.08,.025),Color(.09,.31,.065),Color(.86,.36,.035),Color(.75,.035,.035),Color(.91,.66,.14),Color(.85,.53,.09),Color(.82,.075,.028)]
static func material(crop: String, leaf: bool=false, pulp: bool=false, wet: bool=false) -> ShaderMaterial:
	var index:=ITEMS.NEW_CROPS.find(crop);if index<0:index=6
	var key:=crop+str(leaf)+str(pulp)+str(wet)
	if not _materials.has(key):
		var mat:=ShaderMaterial.new();mat.shader=SHADER
		mat.set_shader_parameter("skin_color",Color(.13,.35,.065) if leaf else COLORS[index])
		mat.set_shader_parameter("kind",index);mat.set_shader_parameter("leaf",leaf);mat.set_shader_parameter("pulp",pulp);mat.set_shader_parameter("wet",wet)
		_materials[key]=mat
	return _materials[key]
static func mesh(crop: String) -> ArrayMesh:
	if _meshes.has(crop):return _meshes[crop]
	var size: Vector3={"Bell Pepper":Vector3(.073,.089,.073),"Cucumber":Vector3(.044,.15,.044),"Pumpkin":Vector3(.13,.10,.13),"Strawberry":Vector3(.046,.055,.046),"Corn":Vector3(.042,.14,.042),"Papaya":Vector3(.08,.135,.08),"Tomato":Vector3(.084,.067,.084)}.get(crop,Vector3.ONE*.06)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 19:
		var v:=ring/18.0;var latitude:=v*PI
		for side in 25:
			var u:=side/24.0;var a:=u*TAU;var r:=sin(latitude)
			var lobes:=1.+(.12*cos(a*4.) if crop=="Bell Pepper" else .10*cos(a*10.) if crop=="Pumpkin" else .02*sin(a*17.+latitude*22.))
			if crop=="Strawberry":r*=.52+v*.85
			if crop=="Cucumber" or crop=="Corn":r=pow(r,.42)
			st.set_uv(Vector2(u,v));st.add_vertex(Vector3(cos(a)*r*lobes,cos(latitude),sin(a)*r*lobes)*size)
	for ring in 18:
		for side in 24:
			var a:=ring*25+side;var b:=a+25
			for vertex in [a,b,a+1,a+1,b,b+1]:st.add_index(vertex)
	st.generate_normals();st.generate_tangents();_meshes[crop]=st.commit();return _meshes[crop]
static func produce(item: String) -> Node3D:
	var crop:=ITEMS.sliced_crop(item)
	if not crop.is_empty():return sliced(crop)
	crop=ITEMS.seed_crop(item);if crop.is_empty():crop=ITEMS.seed_crop(item,true)
	if not crop.is_empty():return seeds(crop,not ITEMS.seed_crop(item,true).is_empty())
	if not ITEMS.box_crop(item).is_empty():return box(ITEMS.box_crop(item))
	var root:=Node3D.new();root.name=item+"Produce"
	PARTS.part(root,mesh(item),Vector3.ZERO,material(item),"TexturedFruit")
	if item!="Cucumber" and item!="Corn":
		var green:=material(item,true)
		PARTS.cylinder(root,Vector3(0,.095 if item in ["Bell Pepper","Pumpkin"] else .055,0),.005,.035,green)
	return root
static func seeds(crop: String, wet: bool=false) -> Node3D:
	var root:=Node3D.new();root.name="WetSeeds" if wet else "DrySeeds"
	var seed_mat:=preload("res://scripts/object_materials.gd").make(6,Color(.12,.075,.035) if crop in ["Papaya","Strawberry"] else Color(.63,.47,.23),.4 if wet else .95)
	if not _meshes.has("seed"):
		var seed_mesh:=SphereMesh.new();seed_mesh.radius=.009;seed_mesh.height=.007;seed_mesh.radial_segments=8;seed_mesh.rings=4;_meshes["seed"]=seed_mesh
	for index in 12:
		var angle:=index*2.399;var at:=Vector3(cos(angle),0,sin(angle))*.013*sqrt(index+1.)
		var kernel:=PARTS.part(root,_meshes.seed,at,seed_mat,"Kernel");kernel.scale=Vector3(.55,1,.55) if crop in ["Papaya","Strawberry"] else Vector3(1,1,1.7)
	return root
static func sliced(crop: String) -> Node3D:
	var root:=Node3D.new();root.name="Sliced"+crop
	for index in 3:
		var slice:=Node3D.new();root.add_child(slice);slice.position=Vector3((index-1)*.08,.01*index,0);slice.rotation.z=(index-1)*.12
		var skin:=PARTS.cylinder(slice,Vector3.ZERO,.049,.035,material(crop));skin.rotation.x=PI/2
		var flesh: Color=Color(.82,.64,.35) if crop=="Pumpkin" else Color(.63,.82,.46) if crop=="Cucumber" else COLORS[mini(6,maxi(0,ITEMS.NEW_CROPS.find(crop)))].lightened(.2)
		for side in [-1,1]:
			var face:=PARTS.cylinder(slice,Vector3(0,0,side*.019),.044,.002,preload("res://scripts/object_materials.gd").make(6,flesh,.46));face.rotation.x=PI/2
			if crop in ["Bell Pepper","Papaya"]:
				var hollow:=PARTS.cylinder(slice,Vector3(0,0,side*.021),.023,.003,preload("res://scripts/object_materials.gd").make(6,Color(.21,.12,.025),.75));hollow.rotation.x=PI/2
			elif crop in ["Cucumber","Tomato"]:
				for pit in 3:
					var angle:=pit*TAU/3;var center:=PARTS.cylinder(slice,Vector3(cos(angle)*.015,sin(angle)*.015,side*.021),.010,.002,preload("res://scripts/object_materials.gd").make(6,flesh.darkened(.17),.38));center.rotation.x=PI/2
	return root
static func box(crop: String) -> Node3D:
	var root:=Node3D.new();root.name="RareGardenSupply"
	for x in [-.21,.21]:PARTS.timber_box(root,Vector3(x,0,0),Vector3(.045,.25,.35))
	for y in [-.12,.12]:PARTS.timber_box(root,Vector3(0,y,0),Vector3(.43,.035,.35))
	for z in [-.17,.17]:PARTS.timber_box(root,Vector3(0,0,z),Vector3(.43,.25,.025))
	var patch:=produce(crop);patch.scale=Vector3.ONE*.65;patch.position=Vector3(0,.16,-.035);root.add_child(patch)
	PARTS.box(root,Vector3(0,0,-.19),Vector3(.12,.25,.015),preload("res://scripts/object_materials.gd").make(3,Color(.31,.28,.19),1))
	return root
static func leaf_mesh(crop: String="Bell Pepper") -> ArrayMesh:
	var key:="leaf:"+crop
	if _meshes.has(key):return _meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in 17:
		var t:=section/16.0;var width:=sin(t*PI)*.12
		if crop=="Corn":width*=.44
		elif crop=="Papaya":width*=1.7*(.50+.50*pow(absf(sin(t*PI*5)),.35))
		elif crop in ["Pumpkin","Cucumber"]:width*=1.3*(1.-.16*absf(sin(t*PI*3)))
		elif crop=="Strawberry":width*=1.+.08*sin(t*PI*15)
		for side in 3:
			st.set_uv(Vector2(side/2.0,t));st.add_vertex(Vector3((side-1)*width,sin(t*PI)*.06-absf(side-1)*.025,t*.48))
	for section in 16:
		for side in 2:
			var a:=section*3+side;var b:=a+3
			for vertex in [a,b,a+1,a+1,b,b+1]:st.add_index(vertex)
	st.generate_normals();st.generate_tangents();_meshes[key]=st.commit();return _meshes[key]
static func plant(crop: String, mature: bool) -> Node3D:
	var root:=Node3D.new();root.name=crop+"GardenPlant"
	var tree:=crop=="Papaya";var height: float=2.6 if tree else 1.55 if crop=="Corn" else .65 if crop=="Bell Pepper" else .32
	var stem:=material(crop,true)
	PARTS.cylinder(root,Vector3(0,height*.5,0),.065 if tree else .012,height,preload("res://scripts/object_materials.gd").make(6,Color(.37,.43,.22),.92) if tree else stem)
	for index in (11 if tree or crop=="Corn" else 9):
		var angle:=index*2.399;var at:=Vector3(0,height*(.8+index*.016) if tree else height*(.25+index*.07),0)
		var leaf:=PARTS.part(root,leaf_mesh(crop),at,stem,"VeinedLeaf");leaf.rotation=Vector3(.26 if tree else -.35,angle,.16*sin(angle))
		leaf.scale=Vector3.ONE*(1.6 if tree else 1.4 if crop=="Corn" else .65 if crop=="Strawberry" else 1.0)
		if crop=="Pumpkin":leaf.scale.x=1.8;leaf.position.x=cos(angle)*.21;leaf.position.z=sin(angle)*.21
	if tree:
		var canopy:=Node3D.new();canopy.name="Canopy";canopy.position.y=height*.78;root.add_child(canopy)
	elif mature:
		for index in 3:
			var fruit:=produce(crop);var angle:=index*TAU/3
			fruit.position=Vector3(cos(angle)*.13,height*.55,sin(angle)*.13);fruit.scale=Vector3.ONE*.8;root.add_child(fruit)
			if crop=="Corn":fruit.position.y=height*.65;fruit.rotation.z=.22*(index-1)
			if crop=="Pumpkin":fruit.position.y=.11;fruit.scale=Vector3.ONE*1.25
	else:
		var flower:=preload("res://scripts/object_materials.gd").make(6,Color(.95,.78,.32) if crop!="Strawberry" else Color(.91,.89,.78),.85)
		for index in 3:PARTS.part(root,mesh("Strawberry"),Vector3(sin(index*2.1)*.1,height*.7,cos(index*2.1)*.1),flower,"Bloom").scale=Vector3.ONE*.18
	return root
