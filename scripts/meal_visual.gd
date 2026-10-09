extends RefCounted
## Original sliced ingredients, shared between the pan, hand bowl and menu art.
const RULES := preload("res://scripts/food_rules.gd")
const SKIN := preload("res://shaders/meal_surface.gdshader")
const COLORS := {"Potato":Color(.80,.65,.37),"Tomato":Color(.72,.075,.025),"Carrot":Color(.94,.31,.035),
	"Onion":Color(.84,.78,.57),"Banana":Color(.91,.77,.43),"Coconut":Color(.91,.86,.73),
	"Fish":Color(.75,.67,.49),"Raw Meat":Color(.49,.14,.065),"Raw Bird":Color(.71,.44,.24),"Raw Crab":Color(.83,.27,.095)}
static var _meshes: Dictionary={}
static var _materials: Dictionary={}

static func create(dish: String,radius: float=.108,progress: float=1.0,unique_material: bool=false) -> Node3D:
	if dish=="Baked Potato":dish="Cooked Potato"
	var root:=Node3D.new();root.name="SlicedMeal"
	if not RULES.RECIPES.has(dish):return root
	if not _meshes.has(dish):_meshes[dish]=_ingredients(dish)
	var mesh:=MeshInstance3D.new();mesh.name="SlicedIngredients";mesh.mesh=_meshes[dish]
	var key:=dish+str(progress)
	var material:=_materials.get(key) as ShaderMaterial
	if material==null or unique_material:
		material=ShaderMaterial.new();material.shader=SKIN;material.set_shader_parameter("cooked",progress)
		if not unique_material:_materials[key]=material
	mesh.material_override=material;mesh.scale=Vector3.ONE*(radius/.23);root.add_child(mesh)
	if RULES.RECIPES[dish].ingredients.has("Clean Water Can"):
		var broth:=MeshInstance3D.new();broth.name="Broth";var disc:=CylinderMesh.new()
		disc.top_radius=radius;disc.bottom_radius=radius;disc.height=.008;disc.radial_segments=32;broth.mesh=disc
		var liquid:=StandardMaterial3D.new();liquid.roughness=.23;liquid.albedo_color=Color(.62,.22,.055) if RULES.RECIPES[dish].ingredients.has("Tomato") else Color(.58,.39,.15)
		if dish=="Tropical Fruit Stew":liquid.albedo_color=Color(.73,.62,.36)
		broth.material_override=liquid;root.add_child(broth)
	return root

static func _append(surface: SurfaceTool,mesh: Mesh,transform: Transform3D,color: Color) -> void:
	var arrays:=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(color);surface.set_normal((transform.basis*normals[index]).normalized())
		surface.set_uv(uvs[index]);surface.add_vertex(transform*vertices[index])

static func _ingredients(dish: String) -> ArrayMesh:
	var types: Array=RULES.RECIPES[dish].ingredients.keys();types.erase("Clean Water Can")
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 18:
		var kind: String=types[index%types.size()]
		var angle:=index*2.39996;var distance_value:=sqrt((index+.5)/18.0)*.19
		var at:=Vector3(cos(angle)*distance_value,.012+float(index%3)*.004,sin(angle)*distance_value)
		var basis:=Basis(Vector3.UP,angle)*Basis(Vector3.RIGHT,float(index%3-1)*.10)
		var mesh: Mesh
		if kind=="Onion":
			var ring:=TorusMesh.new();ring.inner_radius=.015;ring.outer_radius=.025;ring.rings=16;ring.ring_segments=6;mesh=ring
		elif kind in ["Potato","Coconut","Fish","Raw Meat","Raw Bird","Raw Crab"]:
			mesh=preload("res://scripts/resource_visual.gd")._box("diced_food",Vector3(.045,.017,.032))
		else:
			var slice:=CylinderMesh.new();slice.top_radius=.026;slice.bottom_radius=.028;slice.height=.012;slice.radial_segments=20;mesh=slice
		_append(surface,mesh,Transform3D(basis,at),COLORS.get(kind,Color(.7,.5,.2)))
		if kind in ["Tomato","Carrot"]:
			var centre:=CylinderMesh.new();centre.top_radius=.009;centre.bottom_radius=.009;centre.height=.001;centre.radial_segments=10
			_append(surface,centre,Transform3D(basis,at+Vector3.UP*.007),Color(.94,.57,.12) if kind=="Carrot" else Color(.80,.20,.035))
		if kind=="Tomato":
			var seed:=SphereMesh.new();seed.radius=.0023;seed.height=.0017;seed.radial_segments=6;seed.rings=3
			for side in 5:
				var seed_angle:=side*TAU/5+angle
				_append(surface,seed,Transform3D(Basis.IDENTITY,at+Vector3(cos(seed_angle)*.016,.007,sin(seed_angle)*.016)),Color(.93,.75,.33))
	surface.index();return surface.commit()
