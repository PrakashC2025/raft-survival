extends RefCounted
static var _bowl_mesh: CylinderMesh
static var _bowl_material: StandardMaterial3D
static var _pan_meshes: Dictionary={}
static func create(item: String) -> Node3D:
	if item=="Cooking Foil" or item.begins_with("Wrapped "):return foil(item)
	if preload("res://scripts/garden_items.gd").icon_cell(item).y>=0 and item!="Tomato" or not preload("res://scripts/garden_items.gd").box_crop(item).is_empty():return preload("res://scripts/garden_visual.gd").produce(item)
	if item=="Repair Kit":return preload("res://scripts/electronics_visual.gd").repair_kit()
	if item.ends_with("Tumbler"):return _tumbler(item)
	if item in ["Banana","Tomato","Potato","Baked Potato"]:
		return preload("res://scripts/produce_visual.gd").create(item)
	if item=="Carrot":
		var carrot_root:=Node3D.new();carrot_root.name="CarrotFood"
		var carrot:=CylinderMesh.new();carrot.top_radius=.034;carrot.bottom_radius=.004;carrot.height=.22;carrot.radial_segments=16
		var carrot_visual:=MeshInstance3D.new();carrot_visual.mesh=carrot
		var orange:=StandardMaterial3D.new();orange.albedo_color=Color(.82,.31,.05);orange.roughness=.8;carrot_visual.material_override=orange;carrot_root.add_child(carrot_visual)
		return carrot_root
	var models: Dictionary={"Coconut":"res://models/kenney_coconut.glb","Onion":"res://models/onion_bulb.glb","Fish":"res://models/coastal_fish.glb","Raw Meat":"res://models/raw_meat.glb","Raw Bird":"res://models/raw_meat.glb","Raw Crab":"res://models/shore_crab.glb"}
	if models.has(item) and ResourceLoader.exists(models[item]):
		var produce: Node3D=load(models[item]).instantiate()
		var bounds:=AABB();var found:=false
		for child in produce.find_children("*","MeshInstance3D",true,false):
			var part:=child as MeshInstance3D
			var transform:=part.transform;var ancestor:=part.get_parent()
			while ancestor!=produce:transform=(ancestor as Node3D).transform*transform;ancestor=ancestor.get_parent()
			var box:=transform*part.get_aabb()
			bounds=bounds.merge(box) if found else box;found=true
		var largest:=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		var fit:=(.30 if item=="Coconut" else (.36 if item=="Fish" else .23))/maxf(largest,.001)
		var container:=Node3D.new();container.name=item+"Food"
		produce.scale=Vector3.ONE*fit;produce.position=-bounds.get_center()*fit;container.add_child(produce)
		return container
	if item=="Water":item="Clean Water Can"
	var root:=Node3D.new();root.name="SurvivalItem"
	var material:=StandardMaterial3D.new();material.roughness=.7
	var mesh: Mesh
	if item=="Medkit":
		var box:=BoxMesh.new();box.size=Vector3(.23,.14,.08);mesh=box;material.albedo_color=Color(.82,.84,.77)
	elif item.ends_with("Can"):
		var can:=CylinderMesh.new();can.top_radius=.075;can.bottom_radius=.075;can.height=.19;can.radial_segments=16;mesh=can;material.albedo_color=Color(.50,.57,.59);material.metallic=.65
	else:
		if _bowl_mesh==null:
			_bowl_mesh=CylinderMesh.new();_bowl_mesh.top_radius=.12;_bowl_mesh.bottom_radius=.08;_bowl_mesh.height=.08;_bowl_mesh.radial_segments=16
			_bowl_material=StandardMaterial3D.new();_bowl_material.roughness=.7;_bowl_material.albedo_color=Color(.40,.25,.13)
		mesh=_bowl_mesh;material=_bowl_material
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;root.add_child(visual)
	if item=="Medkit":
		var red:=StandardMaterial3D.new();red.albedo_color=Color(.72,.12,.12)
		for size in [Vector3(.09,.024,.002),Vector3(.024,.09,.002)]:
			var cross:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;cross.mesh=box;cross.position.z=.041;cross.material_override=red;root.add_child(cross)
	elif preload("res://scripts/food_rules.gd").RECIPES.has(item):
		var food:=preload("res://scripts/meal_visual.gd").create(item);food.position.y=.042;root.add_child(food)
	elif item!="Can":
		var top:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=.068 if item.ends_with("Can") else .108;disc.bottom_radius=disc.top_radius;disc.height=.005;disc.radial_segments=16
		top.mesh=disc;top.position.y=.09 if item.ends_with("Can") else .042
		var fill:=StandardMaterial3D.new();fill.albedo_color=Color(.28,.50,.63) if item=="Clean Water Can" else (Color(.29,.25,.12) if item=="Dirty Water Can" else Color(.66,.34,.12));top.material_override=fill;root.add_child(top)
	return root

static func foil(item: String) -> Node3D:
	var root:=Node3D.new();root.name="SilverFoilMeal" if item.begins_with("Wrapped ") else "CookingFoil"
	var silver:=StandardMaterial3D.new();silver.albedo_color=Color(.72,.79,.82);silver.metallic=.92;silver.roughness=.30
	var body:=BoxMesh.new();body.size=Vector3(.27,.08 if item.begins_with("Wrapped ") else .015,.19)
	var parcel:=MeshInstance3D.new();parcel.mesh=body;parcel.material_override=silver;root.add_child(parcel)
	for index in 9:
		var fold:=BoxMesh.new();fold.size=Vector3(.012,.006,.18);var ridge:=MeshInstance3D.new();ridge.mesh=fold;ridge.material_override=silver;ridge.position=Vector3(-.12+index*.03,body.size.y*.5,0);ridge.rotation.y=sin(index*1.7)*.22;root.add_child(ridge)
	return root

static func _tumbler(item: String) -> Node3D:
	var root:=Node3D.new();root.name="MetalTumbler"
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color(.51,.55,.57);metal.metallic=.92;metal.roughness=.26;metal.cull_mode=BaseMaterial3D.CULL_DISABLED
	var cup:=CylinderMesh.new();cup.top_radius=.070;cup.bottom_radius=.054;cup.height=.19;cup.radial_segments=32;cup.cap_top=false
	var shell:=MeshInstance3D.new();shell.mesh=cup;shell.material_override=metal;root.add_child(shell)
	var rim:=TorusMesh.new();rim.inner_radius=.066;rim.outer_radius=.072;rim.rings=32;rim.ring_segments=8
	var lip:=MeshInstance3D.new();lip.name="RolledRim";lip.mesh=rim;lip.material_override=metal;lip.position.y=.095;root.add_child(lip)
	if item!="Tumbler":
		var liquid:=MeshInstance3D.new();liquid.name="DrinkingWater";var disc:=CylinderMesh.new();disc.top_radius=.063;disc.bottom_radius=.063;disc.height=.003;disc.radial_segments=32
		liquid.mesh=disc;liquid.position.y=.065
		var water:=StandardMaterial3D.new();water.albedo_color=Color(.15,.36,.43) if item=="Ocean Water Tumbler" else Color(.32,.56,.64);water.roughness=.16;liquid.material_override=water;root.add_child(liquid)
	return root

static func create_pan() -> Node3D:
	var root:=Node3D.new();root.name="CookingPan"
	var steel:=preload("res://scripts/object_materials.gd").make(3,Color(.18,.20,.19),.53,.65)
	if _pan_meshes.is_empty():
		var shell_mesh:=CylinderMesh.new();shell_mesh.top_radius=.27;shell_mesh.bottom_radius=.23;shell_mesh.height=.15;shell_mesh.radial_segments=24;shell_mesh.cap_top=false
		var bottom_mesh:=CylinderMesh.new();bottom_mesh.top_radius=.237;bottom_mesh.bottom_radius=.237;bottom_mesh.height=.012;bottom_mesh.radial_segments=24
		var rim_mesh:=TorusMesh.new();rim_mesh.inner_radius=.255;rim_mesh.outer_radius=.277;rim_mesh.rings=24;rim_mesh.ring_segments=8
		var handle_mesh:=TorusMesh.new();handle_mesh.inner_radius=.045;handle_mesh.outer_radius=.06;handle_mesh.rings=12;handle_mesh.ring_segments=6
		_pan_meshes={"shell":shell_mesh,"bottom":bottom_mesh,"rim":rim_mesh,"handle":handle_mesh}
	var shell: CylinderMesh=_pan_meshes.shell
	var pan:=MeshInstance3D.new();pan.mesh=shell;pan.material_override=steel;root.add_child(pan)
	var inner:=MeshInstance3D.new();var bottom: CylinderMesh=_pan_meshes.bottom
	inner.mesh=bottom;inner.position.y=-.055;inner.material_override=steel;root.add_child(inner)
	var rim: TorusMesh=_pan_meshes.rim
	var lip:=MeshInstance3D.new();lip.mesh=rim;lip.position.y=.075;lip.material_override=steel;root.add_child(lip)
	for side in [-1,1]:
		var handle:=MeshInstance3D.new();var grip: TorusMesh=_pan_meshes.handle
		handle.mesh=grip;handle.position=Vector3(side*.28,.025,0);handle.rotation.z=PI/2;handle.material_override=steel;root.add_child(handle)
	return root
