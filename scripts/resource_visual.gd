extends RefCounted
## Small recognizable salvage props; meshes/materials are reused after creation.
const MATERIALS := preload("res://scripts/object_materials.gd")
static var _meshes: Dictionary = {}
const WEATHER := preload("res://shaders/debris_weathered.gdshader")
const TIMBER_ATLAS := preload("res://textures/construction/timber_photographic_atlas.png")
static var _weather_materials: Dictionary = {}
static var _night_readability:=0.0

static func set_night_readability(value: float) -> void:
	var fill:=clampf(value,0.0,1.0)
	if is_equal_approx(fill,_night_readability):return
	_night_readability=fill
	for skin: ShaderMaterial in _weather_materials.values():skin.set_shader_parameter("night_readability",fill)

static func create(item: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Salvage" + item
	match item:
		"Solar Torch","Walkie Talkie","Binoculars":
			var equipment:=preload("res://scripts/electronics_visual.gd").create(item)
			equipment.name="RecoveredPortable";equipment.rotation.x=PI*.5;equipment.position.y=.06;root.add_child(equipment)
			_part(root,_box("electronics_float",Vector3(.35,.06,.28)),MATERIALS.worn(MATERIALS.Kind.PLASTIC,Color(.32,.33,.26)),Vector3(0,-.05,0))
		"Screw","Wire","Motor","Battery":
			root.add_child(preload("res://scripts/machine_visual.gd").component(item))
			# Small heavy electrical parts arrive on an actual scrap float.
			var float_material:=MATERIALS.make(MATERIALS.Kind.PLASTIC,Color(.36,.40,.37),.85)
			_part(root,_box("component_float",Vector3(.30,.045,.24)),float_material,Vector3(0,-.10,0))
		"WindGenerator","ElectricLamp":
			var equipment:=preload("res://scripts/machine_visual.gd").create(item)
			equipment.name="RecoveredEquipment";equipment.scale=Vector3.ONE*(.27 if item=="WindGenerator" else .65)
			equipment.position.y=.12;root.add_child(equipment)
			var timber:=MATERIALS.make(MATERIALS.Kind.WOOD,Color(.34,.26,.16),.90)
			for offset in [-.17,0.0,.17]:
				_part(root,_box("salvage_pallet",Vector3(.12,.08,.52)),timber,Vector3(offset,0,0))
		"Wood", "Barrel":
			var log := item=="Wood"
			var key := "drift_log" if log else "stave_barrel"
			if not _meshes.has(key):_meshes[key]=_timber_body(log)
			_part(root,_meshes[key],MATERIALS.make(MATERIALS.Kind.WOOD,Color(0.44,0.30,0.17),0.85),Vector3.ZERO)
			if not log:
				if not _meshes.has("barrel_hoop"):
					_meshes["barrel_hoop"]=_barrel_hoop()
				for y in [-0.16,0.16]:
					var hoop:=_part(root,_meshes["barrel_hoop"],MATERIALS.make(MATERIALS.Kind.METAL,Color(0.16,0.18,0.17),0.5,0.7),Vector3(0,y,0))
					hoop.name="MetalBand"
		"Stone":
			if not _meshes.has("worn_stone"):
				var sphere:=SphereMesh.new();sphere.radius=0.22;sphere.height=0.30;sphere.radial_segments=20;sphere.rings=12
				var arrays:=sphere.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				for index in vertices.size():
					var p:=vertices[index];vertices[index]*=1.0+0.10*sin(p.x*23.0+p.z*15.0)+0.06*cos(p.y*31.0-p.z*18.0)
				arrays[Mesh.ARRAY_VERTEX]=vertices
				var stone:=ArrayMesh.new();stone.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var surface:=SurfaceTool.new();surface.create_from(stone,0);surface.generate_normals();_meshes["worn_stone"]=surface.commit()
			_part(root,_meshes["worn_stone"],MATERIALS.make(MATERIALS.Kind.STONE,Color(0.32,0.34,0.32),0.93),Vector3.ZERO)
		"Soil":
			var cloth:=MATERIALS.make(MATERIALS.Kind.CLOTH,Color(0.36,0.28,0.16),0.95)
			if not _meshes.has("soil_sack"):
				var sack:=SphereMesh.new();sack.radius=0.22;sack.height=0.32;sack.radial_segments=20;sack.rings=10
				_meshes["soil_sack"]=sack
			_part(root,_meshes["soil_sack"],cloth,Vector3.ZERO)
			_part(root,_box("sack_neck",Vector3(0.10,0.10,0.08)),cloth,Vector3(0,0.17,0))
			var tie:=_part(root,_torus(),MATERIALS.make(MATERIALS.Kind.CLOTH,Color(0.16,0.12,0.065)),Vector3(0,0.18,0))
			tie.scale=Vector3(0.27,0.5,0.27)
		"Sponge":
			var mesh := SphereMesh.new()
			mesh.radius=0.16;mesh.height=0.23;mesh.radial_segments=16;mesh.rings=8
			var sponge := ShaderMaterial.new()
			sponge.shader=preload("res://shaders/sponge_surface.gdshader")
			_part(root,mesh,sponge,Vector3.ZERO)
			_part(root,mesh,sponge,Vector3(0.07,-0.035,0.04))
		"Rope":
			var rope := MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.53, 0.40, 0.23), 0.94)
			for layer in range(3):
				_part(root, _torus(), rope, Vector3(0, float(layer) * 0.035, 0))
			_part(root, _box("tie", Vector3(0.045, 0.13, 0.30)),
				MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.26, 0.20, 0.12)), Vector3(0, 0.025, 0))
		"Plastic":
			var plastic := MATERIALS.make(MATERIALS.Kind.PLASTIC, Color(0.19, 0.38, 0.43), 0.44)
			_part(root, _box("can", Vector3(0.30, 0.30, 0.17)), plastic, Vector3.ZERO)
			for sign_value in [-1.0, 1.0]:
				_part(root, _box("handle_post", Vector3(0.025, 0.07, 0.045)), plastic, Vector3(sign_value * 0.062, 0.18, 0))
			_part(root, _box("handle", Vector3(0.15, 0.025, 0.045)), plastic, Vector3(0, 0.215, 0))
			_part(root, _box("cap", Vector3(0.055, 0.035, 0.055)),
				MATERIALS.make(MATERIALS.Kind.PLASTIC, Color(0.11, 0.13, 0.12), 0.55), Vector3(-0.10, 0.17, 0))
			_part(root,_box("can_seam",Vector3(0.306,0.015,0.176)),plastic,Vector3(0,-0.115,0))
		"Metal":
			var metal := MATERIALS.make(MATERIALS.Kind.METAL, Color(0.40, 0.43, 0.42), 0.48, 0.78)
			_part(root, _box("plate", Vector3(0.37, 0.035, 0.28)), metal, Vector3.ZERO)
			var folded:=_part(root, _box("edge", Vector3(0.37, 0.14, 0.035)), metal, Vector3(0, 0.052, 0.12))
			folded.rotation.x=-0.22
			_part(root, _box("rib", Vector3(0.035, 0.035, 0.25)), metal, Vector3(-0.11, 0.025, 0))
		_:
			if item.ends_with(" Seed"):
				_part(root, _box("seed_packet", Vector3(0.20, 0.26, 0.05)),
					MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.67, 0.60, 0.42), 0.93), Vector3.ZERO)
				_part(root, _box("seed_label", Vector3(0.14, 0.10, 0.008)),
					MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.27, 0.35, 0.16), 0.9), Vector3(0, 0.01, -0.029))
	return root

static func _timber_body(log: bool) -> ArrayMesh:
	# Smooth shared salvage silhouettes, irregular end grain and a bulged barrel
	# with recessed stave seams. No separate physics bodies for visual details.
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides:=64;var rings:=8
	for ring in range(rings+1):
		var t:=float(ring)/rings
		for side in range(sides+1):
			var u:=float(side)/sides;var a:=u*TAU
			var radius:float=0.12*(1.0+0.045*sin(a*3.0+t*2.0)+0.025*cos(a*7.0)) if log else 0.21*(0.84+0.16*sin(t*PI))*(1.0-0.025*pow(absf(cos(a*8.0)),24.0))
			var along:float=(t-0.5)*(0.86 if log else 0.5)
			if log:along+=cos(a*5.0)*0.009*pow(absf(t-0.5)*2.0,8.0)
			surface.set_uv(Vector2(u,t))
			surface.add_vertex(Vector3(cos(a)*radius,sin(a)*radius,along) if log else Vector3(cos(a)*radius,along,sin(a)*radius))
	for ring in rings:
		for side in sides:
			var a:=ring*(sides+1)+side;var b:=a+sides+1
			for index in ([a,b,a+1,a+1,b,b+1] if log else [a,a+1,b,a+1,b+1,b]):surface.add_index(index)
	for end in 2:
		var start:=end*rings*(sides+1)
		for side in range(1,sides-1):
			var flip:bool=(end==1)==log
			for index in ([start,start+side+1,start+side] if flip else [start,start+side,start+side+1]):surface.add_index(index)
	surface.generate_normals();return surface.commit()

static func _barrel_hoop() -> ArrayMesh:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile: Array[Vector2]=[Vector2(0.190,0.0175),Vector2(0.205,0.0175),Vector2(0.205,-0.0175),Vector2(0.190,-0.0175)]
	for side in 33:
		var a:=float(side)/32.0*TAU
		for point in profile:
			surface.set_uv(Vector2(float(side)/32.0,point.y/0.035+0.5))
			surface.add_vertex(Vector3(cos(a)*point.x,point.y,sin(a)*point.x))
	for side in 32:
		for edge in 4:
			var a:=side*4+edge;var b:=side*4+(edge+1)%4;var c:=a+4;var d:=b+4
			for index in [a,b,c,b,d,c]:surface.add_index(index)
	surface.generate_normals();return surface.commit()

static func _torus() -> Mesh:
	if not _meshes.has("coil"):
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var path: Array[Vector3]=[]
		for index in 33:
			var angle:=TAU*float(index)/32.0
			path.append(Vector3(cos(angle)*0.13,0,sin(angle)*0.13))
		preload("res://scripts/construction_visual.gd")._add_braided_rope(surface,path,Vector3.UP)
		surface.generate_tangents();_meshes["coil"]=surface.commit()
	return _meshes["coil"]

static func _box(key: String, size: Vector3) -> Mesh:
	if not _meshes.has(key):
		var box:=BoxMesh.new();box.size=size
		box.subdivide_width=2;box.subdivide_height=2;box.subdivide_depth=2
		var arrays:=box.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var radius:=minf(size.x,minf(size.y,size.z))*0.16
		var inner:=size*0.5-Vector3.ONE*radius
		for index in vertices.size():
			var clamped:=vertices[index].clamp(-inner,inner)
			var normal:=(vertices[index]-clamped).normalized()
			vertices[index]=clamped+normal*radius;normals[index]=normal
			# Light dents and bowed sheet metal catch highlights without extra bodies.
			if key=="can":vertices[index].z-=sin(vertices[index].x*16.0)*sin(vertices[index].y*15.0)*.009
			if key=="plate":vertices[index].y+=sin(vertices[index].x*10.0)*cos(vertices[index].z*13.0)*.018
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_meshes[key] = mesh
	return _meshes[key]

static func _part(root: Node3D, mesh: Mesh, material: Material, position: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)
	return part

static func weather(root: Node3D,item: String) -> void:
	if item in ["Solar Torch","Walkie Talkie","Binoculars"]:return # Preserved imported texture plus dedicated aged electronics skin.
	if item=="Sponge":return # Its existing porous surface already supplies detail.
	if item in ["Potato Seed","Tomato Seed","Banana Seed"]:return # Detailed produce skin.
	var kind:=MATERIALS.kind_for_item(item)
	if item=="Soil" or item.ends_with(" Seed"):kind=MATERIALS.Kind.CLOTH
	for part: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if part.name=="LEDLens":continue
		if part.mesh==null:continue
		for surface in part.mesh.get_surface_count():
			var original:=part.get_active_material(surface)
			var detail_scale:=part.global_basis.get_scale().length()/sqrt(3.0)
			var color:=Color(0.5,0.4,0.3)
			var texture: Texture2D
			var material_kind:=kind
			if original is BaseMaterial3D:
				color=original.albedo_color;texture=original.albedo_texture
				if original.metallic>0.3:material_kind=MATERIALS.Kind.METAL
			elif original is ShaderMaterial and original.shader==MATERIALS.SURFACE:
				color=original.get_shader_parameter("base_color")
				material_kind=int(original.get_shader_parameter("surface_kind"))
			var label:=(str(part.name)+str(original.resource_name if original!=null else "")).to_lower()
			if item=="Barrel" and (label.contains("metal") or label.contains("band")):material_kind=MATERIALS.Kind.METAL
			var key:="%d:%d:%s:%.4f"%[original.get_instance_id() if original!=null else 0,material_kind,color.to_html(),detail_scale]
			if not _weather_materials.has(key):
				var skin:=ShaderMaterial.new();skin.shader=WEATHER
				skin.set_shader_parameter("night_readability",_night_readability)
				skin.set_shader_parameter("base_color",color);skin.set_shader_parameter("surface_kind",material_kind)
				skin.set_shader_parameter("detail_scale",detail_scale)
				skin.set_shader_parameter("horizontal_wood",item=="Wood")
				skin.set_shader_parameter("barrel",item=="Barrel")
				if texture!=null:skin.set_shader_parameter("source_texture",texture);skin.set_shader_parameter("has_texture",true)
				if material_kind==MATERIALS.Kind.WOOD:
					skin.set_shader_parameter("timber_texture",TIMBER_ATLAS)
					skin.set_shader_parameter("timber_atlas",true)
				_weather_materials[key]=skin
			part.set_surface_override_material(surface,_weather_materials[key])
		# Godot's whole-mesh override wins over every surface override. Clear it
		# only after translating all source surfaces, otherwise custom salvage
		# keeps the plain object material and hides its weathered texture.
		part.material_override=null
