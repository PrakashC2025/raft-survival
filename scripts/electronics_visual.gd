extends RefCounted
const KIT := preload("res://models/portable_electronics.glb")
const ART := preload("res://scripts/machine_visual.gd")
const SURFACE := preload("res://scripts/object_materials.gd")
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static func create(item: String) -> Node3D:
	if _meshes.is_empty():
		var source := KIT.instantiate()
		for label in ["SolarTorch","Binoculars","WalkieTalkie"]:
			var part := source.find_child(label,true,false) as MeshInstance3D
			if part != null: _meshes[label]=part.mesh
		source.free()
	var root := Node3D.new()
	root.name="PortableTool"
	var label := {"Solar Torch":"SolarTorch","Binoculars":"Binoculars","Walkie Talkie":"WalkieTalkie"}.get(item,"") as String
	var model := MeshInstance3D.new()
	model.name=label
	model.mesh=_meshes.get(label)
	root.add_child(model)
	for index in model.mesh.get_surface_count():
		var original:=model.mesh.surface_get_material(index) as BaseMaterial3D
		if original==null:continue
		var key:=str(original.get_instance_id())
		if not _materials.has(key):
			var worn:=ShaderMaterial.new();worn.shader=preload("res://shaders/salvaged_electronics.gdshader")
			worn.set_shader_parameter("original_color",original.albedo_color)
			worn.set_shader_parameter("original_metallic",original.metallic)
			worn.set_shader_parameter("textured",original.albedo_texture!=null)
			if original.albedo_texture!=null:worn.set_shader_parameter("original_texture",original.albedo_texture)
			_materials[key]=worn
		model.set_surface_override_material(index,_materials[key])
	# Physical tape, a chipped edge and off-centre repair screws make the
	# silhouette imperfect; authored electronics textures remain underneath.
	var bounds:=model.get_aabb()
	var centre:=bounds.get_center();var size:=bounds.size
	var tape:=_part(root,"OldClothTape",Vector3(size.x*1.025,size.y*.065,size.z*1.025),centre+Vector3(0,-size.y*.20,0),Color(.24,.22,.16))
	tape.rotation.z=.045
	_part(root,"ChippedCasing",Vector3(size.x*.22,.007,.003),centre+Vector3(size.x*.22,size.y*.29,size.z*.51),Color(.34,.31,.23))
	if item=="Walkie Talkie":
		# Screen faces the player; the side key and removable back cover remain physical.
		var screen := Label3D.new()
		screen.name="RadioScreen"
		screen.position=Vector3(0,-0.025,0.057)
		screen.pixel_size=0.00052
		screen.font_size=24
		screen.outline_size=1
		screen.modulate=Color(0.43,0.72,0.46)
		screen.no_depth_test=false
		screen.text="OFF\n100%"
		root.add_child(screen)
		_part(root,"SidePowerButton",Vector3(0.014,0.035,0.022),Vector3(0.060,0.003,0),Color(0.22,0.37,0.19))
	if item in ["Solar Torch","Walkie Talkie"]:
		_part(root,"SolarPanel",Vector3(0.055,0.080,0.004),Vector3(0,-0.028,-0.052) if item=="Walkie Talkie" else Vector3(0,0.033,0.045),Color(0.08,0.16,0.25))
		_part(root,"BatteryCover",Vector3(0.065,0.07,0.006),Vector3(0,-0.085,0.049),Color(0.065,0.075,0.08))
		var cell := _part(root,"AnimatedBattery",Vector3(0.025,0.06,0.025),Vector3(0,-0.085,0.045),Color(0.18,0.55,0.26))
		cell.hide()
	return root
static func repair_kit() -> Node3D:
	var root:=Node3D.new();root.name="RepairKit"
	var cloth:=SURFACE.worn(SURFACE.Kind.CLOTH,Color(.27,.24,.15))
	var steel:=SURFACE.worn(SURFACE.Kind.METAL,Color(.35,.38,.33),.85,.5)
	ART.box(root,Vector3.ZERO,Vector3(.23,.035,.16),cloth)
	for offset in [-.09,.09]:ART.box(root,Vector3(offset,.022,0),Vector3(.018,.008,.162),SURFACE.worn(SURFACE.Kind.CLOTH,Color(.15,.14,.10)))
	var driver:=screwdriver();driver.position=Vector3(-.047,.037,.076);driver.scale=Vector3.ONE*.65;root.add_child(driver)
	for side in [-1.0,1.0]:
		ART.beam(root,Vector3(.045+side*.025,.035,.068),Vector3(.045,.035,-.016),.012,cloth)
		ART.beam(root,Vector3(.045,.035,-.016),Vector3(.045+side*.015,.035,-.066),.010,steel)
	ART.cylinder(root,Vector3(.045,.043,-.016),.012,.009,steel)
	return root
static func screwdriver() -> Node3D:
	var root:=Node3D.new();root.name="SalvagedScrewdriver"
	var handle:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(.28,.15,.075))
	var steel:=SURFACE.worn(SURFACE.Kind.METAL,Color(.38,.39,.35),.8,.5)
	ART.beam(root,Vector3.ZERO,Vector3(0,0,-.105),.022,handle)
	ART.beam(root,Vector3(0,0,-.105),Vector3(0,0,-.22),.008,steel)
	ART.box(root,Vector3(0,0,-.224),Vector3(.012,.004,.018),steel)
	return root
static func _part(root: Node3D,label: String,size: Vector3,at: Vector3,color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name=label
	var box := BoxMesh.new()
	box.size=size
	part.mesh=box
	part.position=at
	part.material_override=SURFACE.worn(SURFACE.Kind.PLASTIC,color,.88)
	root.add_child(part)
	return part
