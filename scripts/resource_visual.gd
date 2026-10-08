extends RefCounted
## Small recognizable salvage props; meshes/materials are reused after creation.
const MATERIALS := preload("res://scripts/object_materials.gd")
static var _meshes: Dictionary = {}
const WEATHER := preload("res://shaders/debris_weathered.gdshader")
const TIMBER_ATLAS := preload("res://textures/construction/timber_photographic_atlas.png")
static var _weather_materials: Dictionary = {}

static func create(item: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Salvage" + item
	match item:
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
	if item=="Sponge":return # Its existing porous surface already supplies detail.
	if item in ["Potato Seed","Tomato Seed","Banana Seed"]:return # Detailed produce skin.
	var kind:=MATERIALS.kind_for_item(item)
	if item=="Soil" or item.ends_with(" Seed"):kind=MATERIALS.Kind.CLOTH
	for part: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
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
