extends "res://tools/generate_survival_models.gd"
## Original anatomically proportioned mesh assets, authored offline and merged.


func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:

	var brown := mat(Color(0.22,0.16,0.11),0.95)
	brown.albedo_color = Color.WHITE
	brown.albedo_texture = natural_texture(Color(0.24,0.18,0.12),true)
	var black := mat(Color(0.025,0.023,0.018),0.8)
	var ivory := mat(Color(0.74,0.69,0.53),0.75)
	var boar := Node3D.new()
	boar.name = "WildBoar"
	oval(boar, Vector3(0,0.59,0.07), Vector3(0.23,0.29,0.60), brown, "Torso")
	oval(boar, Vector3(0,0.64,-0.40), Vector3(0.235,0.29,0.32), brown, "Shoulders")
	oval(boar, Vector3(0,0.49,-0.65), Vector3(0.15,0.19,0.28), brown, "Head")
	oval(boar, Vector3(0,0.42,-0.88), Vector3(0.095,0.065,0.085), black, "Snout")
	for side in [-1.0,1.0]:
		oval(boar, Vector3(side * 0.125,0.57,-0.71), Vector3(0.018,0.016,0.018),black,"Eye")
		membrane(boar, [Vector3(side * 0.12,0.68,-0.59),Vector3(side * 0.21,0.87,-0.56),Vector3(side * 0.19,0.65,-0.43)],brown,"Ear")
		tube(boar,Vector3(side * 0.12,0.38,-0.77),Vector3(side * 0.16,0.47,-0.82),0.015,ivory,"Tusk")
		for z in [-0.33,0.40]:
			var leg := Node3D.new()
			leg.name = "Leg_%s_%s" % [side,z]
			leg.position = Vector3(side * 0.18,0.4,z)
			boar.add_child(leg)
			tube(leg,Vector3.ZERO,Vector3(0,-0.27,0.025),0.05,brown,"Leg")
			oval(leg,Vector3(0,-0.34,-0.015),Vector3(0.045,0.055,0.075),black,"Hoof")
			batch_static(leg)
	tube(boar,Vector3(0,0.65,0.63),Vector3(0,0.43,0.75),0.015,brown,"Tail")
	for i in range(12):
		tube(boar,Vector3(0,0.87,-0.29+i*0.055),Vector3(0,0.97,-0.25+i*0.055),0.004,black,"Bristle")
	export_model(boar,"wild_boar")
	var shell := mat(Color(0.27,0.30,0.15),0.83)
	var skin := mat(Color(0.36,0.35,0.21),0.95)
	skin.albedo_color = Color.WHITE
	skin.albedo_texture = natural_texture(Color(0.36,0.35,0.21),false)
	var turtle := Node3D.new()
	turtle.name = "SeaTurtle"
	oval(turtle,Vector3(0,0.14,0),Vector3(0.33,0.16,0.46),shell,"Carapace")
	oval(turtle,Vector3(0,0.07,0),Vector3(0.29,0.045,0.42),ivory,"Plastron")
	oval(turtle,Vector3(0,0.11,-0.51),Vector3(0.085,0.07,0.15),skin,"Head")
	for side in [-1.0,1.0]:
		oval(turtle,Vector3(side * 0.075,0.13,-0.56),Vector3(0.01,0.012,0.012),black,"Eye")
		for z in [-0.20,0.28]:
			var flipper := Node3D.new()
			flipper.name = "Leg_%s_%s" % [side,z]
			flipper.position = Vector3(side*0.22,0.08,z)
			turtle.add_child(flipper)
			oval(flipper,Vector3(side*0.18,-0.01,0.035),Vector3(0.26,0.022,0.075),skin,"Flipper")
	# Flat hexagonal scutes follow the shell, replacing costly bubble-shaped plates.
	var scutes := SurfaceTool.new()
	scutes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(5):
		for x in range(3):
			var at := Vector2((x-1)*0.14,(z-2)*0.14+(0.022 if x % 2 else 0.0))
			for side in range(6):
				for p in [at,at+Vector2(cos((side+1)*TAU/6),sin((side+1)*TAU/6))*0.071,at+Vector2(cos(side*TAU/6),sin(side*TAU/6))*0.071]:
					var height := shell_height(p)
					scutes.set_normal(Vector3(p.x/0.1089,(height-0.14)/0.0256,p.y/0.2116).normalized())
					scutes.set_uv((p+Vector2(0.33,0.46))/Vector2(0.66,0.92))
					scutes.add_vertex(Vector3(p.x,height+0.006,p.y))
	var plate_mat := mat(Color.WHITE,0.87)
	plate_mat.albedo_texture = natural_texture(Color(0.27,0.29,0.15),false)
	part(turtle,scutes.commit(),plate_mat,Vector3.ZERO,Vector3.ONE,"ShellScutes")
	export_model(turtle,"sea_turtle")
	var crab := Node3D.new()
	crab.name = "ShoreCrab"
	var chitin := mat(Color(0.32,0.20,0.11),0.65)
	oval(crab,Vector3(0,0.08,0),Vector3(0.13,0.06,0.10),chitin,"Carapace")
	for side in [-1.0,1.0]:
		for i in range(4):
			var leg := Node3D.new()
			leg.name = "Leg_%s_%s" % [side,i]
			leg.position = Vector3(side*0.10,0.08,-0.065+i*0.045)
			crab.add_child(leg)
			tube(leg,Vector3.ZERO,Vector3(side*0.1,0.01,0.02),0.012,chitin,"Upper")
			tube(leg,Vector3(side*0.1,0.01,0.02),Vector3(side*0.14,-0.065,0.04),0.007,chitin,"Lower")
			batch_static(leg)
		tube(crab,Vector3(side*0.08,0.08,-0.08),Vector3(side*0.18,0.1,-0.17),0.017,chitin,"Arm")
		oval(crab,Vector3(side*0.17,0.1,-0.18),Vector3(0.038,0.023,0.055),chitin,"Claw")
		tube(crab,Vector3(side*0.045,0.1,-0.08),Vector3(side*0.05,0.15,-0.09),0.008,chitin,"EyeStalk")
		oval(crab,Vector3(side*0.05,0.15,-0.09),Vector3.ONE*0.01,black,"Eye")
	export_model(crab,"shore_crab")

	quit()

func shell_height(at: Vector2) -> float:
	return 0.14+0.16*sqrt(maxf(0,1-pow(at.x/0.33,2)-pow(at.y/0.46,2)))

func natural_texture(base: Color, fur: bool) -> ImageTexture:
	var texture := Image.create(128,128,false,Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 781
	noise.frequency = 0.14
	for y in range(128):
		for x in range(128):
			var grain := noise.get_noise_2d(float(x),float(y)*0.28 if fur else float(y))
			var strand := sin(float(x)*2.6+grain*2.0)*0.045 if fur else sin(float(x+y)*1.7)*0.012
			texture.set_pixel(x,y,base*(0.92+grain*0.35+strand))
	return ImageTexture.create_from_image(texture)
