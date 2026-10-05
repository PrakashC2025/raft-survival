extends RefCounted
## Original full-scale salvage equipment, shared material detail and restrained colours.
const SURFACE := preload("res://scripts/object_materials.gd")
static var _meshes: Dictionary = {}
static func part(root: Node3D, mesh: Mesh, at: Vector3, material: Material, label: String = "Part") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance
static func box(root: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var key := "box:"+str(size)
	var mesh := _meshes.get(key) as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return part(root, mesh, at, material)
static func cylinder(root: Node3D, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var key := "cyl:%.4f:%.4f" % [radius,height]
	var mesh := _meshes.get(key) as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 20
		_meshes[key] = mesh
	return part(root, mesh, at, material)
static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	var steel := SURFACE.make(SURFACE.Kind.METAL, Color(0.31, 0.34, 0.33), 0.48, 0.75)
	var rust := SURFACE.make(SURFACE.Kind.METAL, Color(0.19, 0.24, 0.20), 0.75, 0.4)
	var dark := SURFACE.make(SURFACE.Kind.PLASTIC, Color(0.045, 0.055, 0.05), 0.8)
	var wood := SURFACE.make(SURFACE.Kind.WOOD, Color(0.26, 0.19, 0.12), 0.95)
	box(root, Vector3(0,-0.29,0), Vector3(0.7,0.12,0.65), wood)
	match kind:
		"WaterPurifier", "ElectricPurifier":
			cylinder(root, Vector3(-0.13,0.12,0), 0.23, 0.62, steel)
			cylinder(root, Vector3(-0.13,0.445,0), 0.245, 0.045, steel)
			cylinder(root, Vector3(-0.13,0.51,0), 0.035, 0.1, dark)
			var condenser := cylinder(root, Vector3(0.19,0.39,0), 0.045, 0.38, steel)
			condenser.rotation.z = PI / 2
			for index in range(8):
				cylinder(root, Vector3(0.23,-0.05 + index * 0.037,0), 0.09, 0.018, steel)
			box(root, Vector3(0.24,-0.08,0.19), Vector3(0.14,0.24,0.14), dark)
			if kind == "ElectricPurifier":
				box(root, Vector3(-0.12,-0.20,0.22), Vector3(0.3,0.12,0.16), rust)
			else:
				cylinder(root, Vector3(-0.13,-0.20,0), 0.19, 0.13, dark)
		"WindGenerator":
			cylinder(root, Vector3(0,0.7,0), 0.035, 2.0, steel)
			box(root, Vector3(0,-0.12,0.12), Vector3(0.4,0.24,0.3), rust)
			var rotor := Node3D.new()
			rotor.name = "Rotor"
			rotor.position = Vector3(0,1.7,-0.13)
			root.add_child(rotor)
			var hub := cylinder(rotor, Vector3.ZERO, 0.07, 0.18, steel)
			hub.rotation.x = PI / 2
			for index in range(3):
				var arm := Node3D.new()
				arm.rotation.z = index * TAU / 3
				rotor.add_child(arm)
				var blade := box(arm, Vector3(0,0.38,0), Vector3(0.08,0.66,0.025), steel)
				blade.rotation.y = 0.2
		"ElectricLamp":
			cylinder(root, Vector3(0,0.0,0), 0.025, 0.58, steel)
			cylinder(root, Vector3(0,0.4,0), 0.13, 0.08, steel)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.75,0.65,0.38)
			glass.roughness = 0.22
			cylinder(root, Vector3(0,0.3,0), 0.09, 0.17, glass)
			for side in [-1,1]:
				cylinder(root, Vector3(side * 0.1,0.3,0), 0.012, 0.22, steel)
		"RescueRadio":
			box(root, Vector3(0,0.02,0), Vector3(0.55,0.34,0.28), rust)
			box(root, Vector3(-0.1,0.06,-0.15), Vector3(0.24,0.17,0.01), dark)
			for index in range(6):
				box(root, Vector3(-0.1,0.0+index * 0.025,-0.16), Vector3(0.22,0.004,0.008), steel)
			for index in range(2):
				var dial := cylinder(root, Vector3(0.17,-0.06+index * 0.14,-0.16),0.035,0.025,dark)
				dial.rotation.x = PI / 2
			cylinder(root, Vector3(0.21,0.61,0),0.008,1.0,steel)
	return root
