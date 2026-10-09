extends RefCounted
## Original full-scale salvage equipment, shared material detail and restrained colours.
const SURFACE := preload("res://scripts/object_materials.gd")
const TIMBER := preload("res://scripts/construction_visual.gd")
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
static func beam(root: Node3D, a: Vector3, b: Vector3, width: float, material: Material) -> MeshInstance3D:
	var piece := box(root,(a+b)*0.5,Vector3(width,width,a.distance_to(b)),material)
	piece.look_at_from_position((a+b)*0.5,b,Vector3.RIGHT if absf((b-a).normalized().dot(Vector3.UP))>0.98 else Vector3.UP)
	return piece

static func component(kind: String) -> Node3D:
	var root:=Node3D.new();root.name=kind
	var metal:=SURFACE.worn(SURFACE.Kind.METAL,Color(.42,.48,.47),.44,.75)
	var rubber:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(.065,.075,.065),.82)
	match kind:
		"Screw":
			cylinder(root,Vector3.ZERO,.013,.17,metal)
			cylinder(root,Vector3(0,.087,0),.027,.017,metal)
			box(root,Vector3(0,.097,0),Vector3(.033,.003,.006),rubber)
			for index in 7: cylinder(root,Vector3(0,-.065+index*.019,0),.017,.006,metal)
		"Wire":
			var copper:=SURFACE.worn(SURFACE.Kind.METAL,Color(.55,.27,.09),.48,.65)
			for index in 18:
				var angle:=TAU*index/18.0
				var next:=TAU*(index+1)/18.0
				beam(root,Vector3(cos(angle)*.10,0,sin(angle)*.10),Vector3(cos(next)*.10,0,sin(next)*.10),.014,rubber)
			beam(root,Vector3(.10,0,0),Vector3(.16,0,.04),.01,copper)
		"Motor":
			var body:=cylinder(root,Vector3.ZERO,.074,.18,metal);body.rotation.z=PI/2.0
			var shaft:=cylinder(root,Vector3(.115,0,0),.012,.07,metal);shaft.rotation.z=PI/2.0
			box(root,Vector3(-.10,0,0),Vector3(.03,.12,.12),rubber)
			for offset in [-.045,0.0,.045]:box(root,Vector3(offset,.075,0),Vector3(.02,.004,.075),rubber)
		"Battery":
			box(root,Vector3.ZERO,Vector3(.12,.18,.10),rubber)
			for side in [-1.0,1.0]:cylinder(root,Vector3(side*.035,.102,0),.013,.025,metal)
	return root

static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	var steel := SURFACE.worn(SURFACE.Kind.METAL, Color(0.31, 0.34, 0.33), 0.48, 0.75)
	var rust := SURFACE.worn(SURFACE.Kind.METAL, Color(0.19, 0.24, 0.20), 0.75, 0.4)
	var dark := SURFACE.worn(SURFACE.Kind.PLASTIC, Color(0.045, 0.055, 0.05), 0.8)
	var wood := SURFACE.worn(SURFACE.Kind.WOOD, Color(0.26, 0.19, 0.12), 0.95)
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
			# Salvaged motor on a braced timber mast, carved wooden blades,
			# insulated leads and a visible battery, rather than a metal pinwheel.
			wood=SURFACE.worn(SURFACE.Kind.WOOD,Color(.43,.32,.20),.87)
			part(root,TIMBER.rounded_timber(Vector3(0.095,2.0,0.095)),Vector3(0,.72,0),null,"TimberMast")
			for side in [-1.0,1.0]:
				beam(root,Vector3(side*0.29,-0.23,0),Vector3(0,0.75,0),0.055,wood)
				beam(root,Vector3(0,-0.23,side*0.25),Vector3(0,0.64,0),0.045,wood)
				var bolt:=cylinder(root,Vector3(side*0.07,0.57,-0.055),0.018,0.025,steel)
				bolt.rotation.x=PI/2.0
			var battery:=box(root,Vector3(0.16,-0.11,0.1),Vector3(0.3,0.25,0.32),dark)
			battery.name="StorageBattery"
			box(root,Vector3(0.16,0.026,0.1),Vector3(0.31,0.025,0.33),rust)
			var red:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(0.35,0.045,0.025),0.65)
			for index in 2:
				cylinder(root,Vector3(0.09+index*0.14,0.055,0.03),0.016,0.04,red if index==0 else steel)
				var x:float=-0.055-index*0.017
				beam(root,Vector3(x,1.6,0.06),Vector3(x,0.13,0.06),0.012,red if index==0 else dark)
				beam(root,Vector3(x,0.13,0.06),Vector3(0.09+index*0.14,0.055,0.03),0.012,red if index==0 else dark)
			var head:=Node3D.new();head.name="WindHead";head.position=Vector3(0,1.7,0);root.add_child(head)
			var motor:=cylinder(head,Vector3(0,0,0.055),0.09,0.25,steel);motor.rotation.x=PI/2.0;motor.name="GeneratorMotor"
			for index in 4:
				box(head,Vector3(-0.06+index*0.04,0.092,0.06),Vector3(0.013,0.008,0.18),dark)
			beam(head,Vector3(0,0,0.17),Vector3(0,0,0.7),0.035,steel)
			box(head,Vector3(0,0.05,0.64),Vector3(0.022,0.30,0.29),wood)
			var rotor := Node3D.new()
			rotor.name = "Rotor"
			rotor.position = Vector3(0,0,-0.17)
			head.add_child(rotor)
			var hub := cylinder(rotor, Vector3.ZERO, 0.07, 0.18, steel)
			hub.rotation.x = PI / 2
			for index in range(3):
				var arm := Node3D.new()
				arm.rotation.z = index * TAU / 3
				rotor.add_child(arm)
				var blade := part(arm,TIMBER.rounded_timber(Vector3(.14,.69,.028)),Vector3(0,.40,0),null,"CarvedBlade")
				blade.rotation.y = 0.24
				var tip:=box(arm,Vector3(0.016,0.70,0),Vector3(0.08,0.16,0.018),wood);tip.rotation.y=0.24
				var bolt:=cylinder(arm,Vector3(0,0.14,-0.027),0.015,0.035,steel);bolt.rotation.x=PI/2.0
			box(root,Vector3(0.16,-0.10,-0.067),Vector3(0.20,0.10,0.012),steel)
			box(root,Vector3(0.16,-0.10,-0.077),Vector3(0.17,0.071,0.009),dark)
			var green:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(0.16,0.65,0.29),0.35)
			for index in 4:
				var bar:=box(root,Vector3(0.096+index*0.041,-0.10,-0.085),Vector3(0.027,0.049,0.007),green)
				bar.name="ChargeBar%d"%index
			var brake:=box(root,Vector3(-0.20,-0.09,-0.16),Vector3(0.045,0.11,0.03),steel);brake.name="BrakeSwitch"
		"ElectricLamp":
			cylinder(root, Vector3(0,0.0,0), 0.025, 0.58, steel)
			cylinder(root, Vector3(0,0.4,0), 0.13, 0.08, steel)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.75,0.65,0.38)
			glass.roughness = 0.22
			glass.emission_enabled=true;glass.emission=Color(1,.76,.41);glass.emission_energy_multiplier=0.0
			var lens:=cylinder(root, Vector3(0,0.3,0), 0.09, 0.17, glass);lens.name="LEDLens"
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
