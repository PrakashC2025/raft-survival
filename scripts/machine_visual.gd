extends RefCounted
## Original full-scale salvage equipment, shared material detail and restrained colours.
const SURFACE := preload("res://scripts/object_materials.gd")
const TIMBER := preload("res://scripts/construction_visual.gd")
static var _meshes: Dictionary = {}
static var _aged_materials: Dictionary = {}
static func aged(kind: int, color: Color, roughness: float, metallic: float=0.0) -> ShaderMaterial:
	var key:="%d:%s:%.2f:%.2f"%[kind,color.to_html(),roughness,metallic]
	if not _aged_materials.has(key):
		var material:=SURFACE.make(kind,color,roughness,metallic).duplicate() as ShaderMaterial
		material.set_shader_parameter("surface_wear",.28)
		_aged_materials[key]=material
	return _aged_materials[key]
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
static func timber_box(root: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	return part(root,TIMBER.box(size,Color.WHITE),at,null)
static func timber_beam(root: Node3D, a: Vector3, b: Vector3, width: float) -> MeshInstance3D:
	var piece := part(root,TIMBER.rounded_timber(Vector3(width,width,a.distance_to(b))),(a+b)*0.5,null)
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
			var atlas_tex: Texture2D = load("res://textures/salvage/motor_machinery_atlas.jpg") if ResourceLoader.exists("res://textures/salvage/motor_machinery_atlas.jpg") else null
			var iron_mat := StandardMaterial3D.new()
			iron_mat.albedo_color = Color(0.28, 0.30, 0.32)
			iron_mat.roughness = 0.55
			iron_mat.metallic = 0.78
			if atlas_tex != null: iron_mat.albedo_texture = atlas_tex
			var copper_mat := StandardMaterial3D.new()
			copper_mat.albedo_color = Color(0.72, 0.38, 0.15)
			copper_mat.roughness = 0.35
			copper_mat.metallic = 0.82
			if atlas_tex != null: copper_mat.albedo_texture = atlas_tex

			var body := cylinder(root, Vector3.ZERO, .076, .19, iron_mat)
			body.rotation.z = PI / 2.0
			# Cooling fins along motor stator
			for fin_i in range(5):
				var fin := cylinder(root, Vector3(-0.06 + fin_i * 0.03, 0, 0), 0.086, 0.008, iron_mat)
				fin.rotation.z = PI / 2.0
			# Drive shaft with keyway
			var shaft := cylinder(root, Vector3(.12, 0, 0), .014, .08, metal)
			shaft.rotation.z = PI / 2.0
			# Rear terminal box with visible copper coil winding
			box(root, Vector3(-.10, 0, 0), Vector3(.036, .13, .13), rubber)
			var coil := cylinder(root, Vector3(-.085, 0.04, 0), 0.024, 0.03, copper_mat)
			coil.rotation.z = PI / 2.0
			for offset in [-.045, 0.0, .045]:
				box(root, Vector3(offset, .078, 0), Vector3(.022, .005, .08), rubber)
		"Battery":
			var atlas_tex: Texture2D = load("res://textures/salvage/motor_machinery_atlas.jpg") if ResourceLoader.exists("res://textures/salvage/motor_machinery_atlas.jpg") else null
			var case_mat := StandardMaterial3D.new()
			case_mat.albedo_color = Color(0.12, 0.14, 0.14)
			case_mat.roughness = 0.85
			if atlas_tex != null: case_mat.albedo_texture = atlas_tex
			var brass_mat := StandardMaterial3D.new()
			brass_mat.albedo_color = Color(0.85, 0.72, 0.38)
			brass_mat.roughness = 0.32
			brass_mat.metallic = 0.85

			# Rugged ribbed battery casing
			box(root, Vector3.ZERO, Vector3(.125, .185, .105), case_mat)
			# Top reinforcement lid
			box(root, Vector3(0, .095, 0), Vector3(.13, .015, .11), rubber)
			# Positive and negative terminal posts
			cylinder(root, Vector3(-.036, .115, 0), .014, .028, brass_mat)
			cylinder(root, Vector3(.036, .115, 0), .014, .028, metal)
			# Red and black insulator rings
			cylinder(root, Vector3(-.036, .102, 0), .018, .008, SURFACE.worn(SURFACE.Kind.PLASTIC, Color(0.75, 0.12, 0.10), 0.6))
			cylinder(root, Vector3(.036, .102, 0), .018, .008, rubber)
	return root


static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	var steel := SURFACE.worn(SURFACE.Kind.METAL, Color(0.31, 0.34, 0.33), 0.48, 0.75)
	var rust := SURFACE.worn(SURFACE.Kind.METAL, Color(0.19, 0.24, 0.20), 0.75, 0.4)
	var dark := SURFACE.worn(SURFACE.Kind.PLASTIC, Color(0.045, 0.055, 0.05), 0.8)
	var wood := SURFACE.worn(SURFACE.Kind.WOOD, Color(0.26, 0.19, 0.12), 0.95)
	if kind == "WindGenerator":
		timber_box(root,Vector3(0,-.29,0),Vector3(.7,.12,.65))
	else:
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
			part(root,TIMBER.rounded_timber(Vector3(0.095,2.0,0.095)),Vector3(0,.72,0),null,"TimberMast")
			var binding:=SURFACE.make(SURFACE.Kind.CLOTH,Color(.24,.22,.15),1.0)
			for index in 5:
				var mast_binding:=box(root,Vector3(0,.42+index*.027,0),Vector3(.112,.016,.11),binding)
				mast_binding.rotation.y=.11*index
			for side in [-1.0,1.0]:
				timber_beam(root,Vector3(side*0.29,-0.23,0),Vector3(0,0.75,0),0.055)
				timber_beam(root,Vector3(0,-0.23,side*0.25),Vector3(0,0.64,0),0.045)
				var bolt:=cylinder(root,Vector3(side*0.07,0.57,-0.055),0.018,0.025,steel)
				bolt.rotation.x=PI/2.0
			var battery:=box(root,Vector3(0.16,-0.11,0.1),Vector3(0.3,0.25,0.32),aged(SURFACE.Kind.PLASTIC,Color(.045,.055,.05),.9))
			battery.name="StorageBattery"
			box(root,Vector3(0.16,0.026,0.1),Vector3(0.31,0.025,0.33),rust)
			var red:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(0.35,0.045,0.025),0.65)
			for index in 2:
				cylinder(root,Vector3(0.09+index*0.14,0.055,0.03),0.016,0.04,red if index==0 else steel)
				var x:float=-0.055-index*0.017
				beam(root,Vector3(x,1.6,0.06),Vector3(x,0.13,0.06),0.012,red if index==0 else dark)
				beam(root,Vector3(x,0.13,0.06),Vector3(0.09+index*0.14,0.055,0.03),0.012,red if index==0 else dark)
			var head:=Node3D.new();head.name="WindHead";head.position=Vector3(0,1.7,0);root.add_child(head)
			var atlas_tex: Texture2D = load("res://textures/salvage/motor_machinery_atlas.jpg") if ResourceLoader.exists("res://textures/salvage/motor_machinery_atlas.jpg") else null
			var gen_mat := StandardMaterial3D.new()
			gen_mat.albedo_color = Color(0.28, 0.32, 0.34)
			gen_mat.roughness = 0.50
			gen_mat.metallic = 0.75
			if atlas_tex != null: gen_mat.albedo_texture = atlas_tex
			var motor:=cylinder(head,Vector3(0,0,0.055),0.092,0.25,gen_mat);motor.rotation.x=PI/2.0;motor.name="GeneratorMotor"
			# Cooling ribbing around the generator
			for fin_i in range(4):
				var gfin := cylinder(head, Vector3(0, 0, -0.02 + fin_i * 0.045), 0.102, 0.008, gen_mat)
				gfin.rotation.x = PI / 2.0
			var patch:=box(head,Vector3(.075,.023,.045),Vector3(.022,.085,.18),SURFACE.worn(SURFACE.Kind.METAL,Color(.30,.13,.045),.96,.12))
			patch.rotation.z=.18
			beam(head,Vector3(-.04,-.07,.07),Vector3(-.13,-.16,.17),.014,dark)
			for index in 4:
				box(head,Vector3(-0.06+index*0.04,0.092,0.06),Vector3(0.013,0.008,0.18),dark)
			beam(head,Vector3(0,0,0.17),Vector3(0,0,0.7),0.035,steel)
			timber_box(head,Vector3(0,0.05,0.64),Vector3(0.022,0.30,0.29))

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
				var blade := part(arm,TIMBER.rounded_timber(Vector3(.14,.69-index*.009,.028)),Vector3(0,.40,0),null,"CarvedBlade")
				blade.rotation.y = 0.24
				for band in 2:
					var tape:=box(arm,Vector3(0,.25+band*.035,0),Vector3(.148,.023,.037),binding)
					tape.rotation.y=.24;tape.rotation.z=.06*(index-1)
				var tip:=timber_box(arm,Vector3(0.016,0.70,0),Vector3(0.08,0.16,0.018));tip.rotation.y=0.24
				var bolt:=cylinder(arm,Vector3(0,0.14,-0.027),0.015,0.035,steel);bolt.rotation.x=PI/2.0
			box(root,Vector3(0.16,-0.10,-0.067),Vector3(0.20,0.10,0.012),steel)
			box(root,Vector3(0.16,-0.10,-0.077),Vector3(0.17,0.071,0.009),dark)
			var green:=SURFACE.worn(SURFACE.Kind.PLASTIC,Color(0.16,0.65,0.29),0.35)
			for index in 4:
				var bar:=box(root,Vector3(0.096+index*0.041,-0.10,-0.085),Vector3(0.027,0.049,0.007),green)
				bar.name="ChargeBar%d"%index
			var brake:=box(root,Vector3(-0.20,-0.09,-0.16),Vector3(0.045,0.11,0.03),steel);brake.name="BrakeSwitch"
		"ElectricLamp":
			# Recovered cracked work-light: exposed board, missing corner,
			# dirty casing, taped repairs and a bent stand, no pristine lantern.
			dark=aged(SURFACE.Kind.PLASTIC,Color(.045,.05,.043),.95)
			box(root,Vector3(0,.02,0),Vector3(.43,.30,.19),aged(SURFACE.Kind.METAL,Color(.19,.20,.17),.88,.2))
			box(root,Vector3(0,.04,-.105),Vector3(.34,.22,.018),dark)
			var board:=aged(SURFACE.Kind.PLASTIC,Color(.12,.25,.16),.95)
			box(root,Vector3(.02,.04,-.12),Vector3(.27,.16,.012),board)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.56,0.50,0.31)
			glass.roughness = 0.78
			glass.emission_enabled=true;glass.emission=Color(1,.76,.41);glass.emission_energy_multiplier=0.0
			var lens:=box(root,Vector3(.02,.04,-.135),Vector3(.19,.09,.008),glass);lens.name="LEDLens"
			for index in 4:
				box(root,Vector3(-.055+index*.05,.04,-.142),Vector3(.015,.055,.006),glass)
			beam(root,Vector3(-.07,-.004,-.15),Vector3(.01,.075,-.15),.006,dark)
			beam(root,Vector3(.01,.075,-.15),Vector3(.073,.055,-.15),.006,dark)
			var tape:=box(root,Vector3(-.15,-.03,-.12),Vector3(.045,.30,.025),SURFACE.make(SURFACE.Kind.CLOTH,Color(.25,.22,.15),1.0));tape.rotation.z=-.21
			beam(root,Vector3(.11,-.10,.09),Vector3(.22,-.25,.22),.016,steel)
			beam(root,Vector3(-.08,-.12,.09),Vector3(-.19,-.25,.19),.016,steel)
			beam(root,Vector3(.20,-.07,.08),Vector3(.25,-.17,.06),.012,dark)
			var cover:=box(root,Vector3(0,0,.105),Vector3(.25,.15,.02),dark);cover.name="BatteryCover"
			var cell:=component("Battery");cell.name="AnimatedBattery";cell.scale=Vector3.ONE*.6;cell.position=Vector3(0,0,.09);cell.hide();root.add_child(cell)
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
