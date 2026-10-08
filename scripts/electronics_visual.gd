extends RefCounted
const KIT := preload("res://models/portable_electronics.glb")
static var _meshes: Dictionary = {}
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
	if item=="Walkie Talkie":
		# Screen faces the player; the side key and removable back cover remain physical.
		var screen := Label3D.new()
		screen.name="RadioScreen"
		screen.position=Vector3(0,-0.025,0.057)
		screen.pixel_size=0.00052
		screen.font_size=24
		screen.outline_size=1
		screen.modulate=Color(0.58,1,0.64)
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
static func _part(root: Node3D,label: String,size: Vector3,at: Vector3,color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name=label
	var box := BoxMesh.new()
	box.size=size
	part.mesh=box
	part.position=at
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.6
	part.material_override=material
	root.add_child(part)
	return part
