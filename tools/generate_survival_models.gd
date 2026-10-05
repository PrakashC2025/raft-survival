extends SceneTree
## Original CC0 assets. Author once offline; no modelling work runs in gameplay.

func _initialize() -> void:
	call_deferred("_run")

func mat(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result

func part(parent: Node3D, mesh: Mesh, material: Material, position: Vector3, dimensions: Vector3, label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.scale = dimensions
	parent.add_child(node)
	return node

func oval(parent: Node3D, position: Vector3, dimensions: Vector3, material: Material, label: String) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	part(parent, sphere, material, position, dimensions, label)

func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, label: String) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = a.distance_to(b) + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 5
	var node := part(parent, mesh, material, (a + b) * 0.5, Vector3.ONE, label)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func membrane(parent: Node3D, vertices: Array[Vector3], material: Material, label: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, vertices.size() - 1):
		for vertex in [vertices[0], vertices[index], vertices[index + 1]]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var two_sided := material.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	part(parent, surface.commit(), two_sided, Vector3.ZERO, Vector3.ONE, label)

func batch_static(root_node: Node3D) -> void:
	if root_node.get_child_count() <= 1:
		return
	# Offline merging keeps individual wing pivots but combines static parts.
	var batches: Dictionary = {}
	for child in root_node.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var source_material := instance.material_override as StandardMaterial3D
		var key := source_material.albedo_color.to_html() + str(source_material.roughness) + str(source_material.metallic) + str(source_material.cull_mode)
		key += str(source_material.vertex_color_use_as_albedo)
		if source_material.albedo_texture != null:
			key += str(source_material.albedo_texture.get_instance_id())
		if not batches.has(key):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = {"surface": surface, "material": source_material}
		(batches[key]["surface"] as SurfaceTool).append_from(instance.mesh, 0, instance.transform)
		root_node.remove_child(instance)
		instance.free()
	for key in batches:
		var surface := batches[key]["surface"] as SurfaceTool
		surface.index()
		part(root_node, surface.commit(), batches[key]["material"], Vector3.ZERO, Vector3.ONE, "BatchedSurface")

func export_model(root_node: Node3D, file: String) -> void:
	batch_static(root_node)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(root_node, state)
	if error == OK:
		error = document.write_to_filesystem(state, "C:/GodotProjects/raft-survival/models/" + file + ".glb")
	print("MODEL " + file + ": " + error_string(error))
	root_node.free()
	if error != OK:
		quit(1)

func _run() -> void:
	var fish := Node3D.new()
	fish.name = "CoastalFish"
	var silver := mat(Color(0.48, 0.62, 0.65), 0.34, 0.32)
	var dark := mat(Color(0.05, 0.11, 0.13), 0.45)
	oval(fish, Vector3(0.02, 0, 0), Vector3(0.23, 0.052, 0.039), silver, "FishBody")
	oval(fish, Vector3(0.21, 0, 0), Vector3(0.055, 0.039, 0.033), silver, "Head")
	for side in [-1.0, 1.0]:
		oval(fish, Vector3(0.23, 0.011, side * 0.031), Vector3(0.004, 0.004, 0.002), dark, "Eye" + str(side))
		membrane(fish, [Vector3(0.08, -0.01, side * 0.033), Vector3(-0.02, -0.07, side * 0.08), Vector3(-0.065, -0.025, side * 0.03)], silver, "Pectoral" + str(side))
	membrane(fish, [Vector3(0.07, 0.036, 0), Vector3(0.02, 0.073, 0), Vector3(-0.055, 0.060, 0), Vector3(-0.15, 0.025, 0)], silver, "DorsalFin")
	membrane(fish, [Vector3(-0.18, 0, 0), Vector3(-0.31, 0.065, 0), Vector3(-0.29, 0.015, 0), Vector3(-0.265, 0, 0), Vector3(-0.29, -0.015, 0), Vector3(-0.31, -0.065, 0)], silver, "TailFin")
	for ray_index in range(6):
		var end_y := lerpf(-0.059, 0.059, float(ray_index) / 5.0)
		tube(fish, Vector3(-0.19, 0, 0.001), Vector3(-0.305, end_y, 0.001), 0.0009, mat(Color(0.36, 0.44, 0.43)), "FinRay%d" % ray_index)
	oval(fish, Vector3(0.256, -0.012, 0), Vector3(0.012, 0.007, 0.024), dark, "Mouth")
	export_model(fish, "coastal_fish")
	var gull := Node3D.new()
	gull.name = "CoastalGull"
	var feather := mat(Color(0.76, 0.79, 0.76), 0.92)
	var white := mat(Color(0.87, 0.88, 0.82), 0.9)
	oval(gull, Vector3.ZERO, Vector3(0.10, 0.13, 0.25), white, "GullBody")
	oval(gull, Vector3(0, 0.085, -0.235), Vector3(0.075, 0.09, 0.12), white, "GullHead")
	oval(gull, Vector3(0, 0.065, -0.355), Vector3(0.022, 0.020, 0.085), mat(Color(0.61, 0.46, 0.17)), "Beak")
	for side in [-1.0, 1.0]:
		oval(gull, Vector3(side * 0.068, 0.11, -0.28), Vector3(0.006, 0.006, 0.006), dark, "GullEye" + str(side))
		var wing := Node3D.new()
		wing.name = "WingLeft" if side < 0 else "WingRight"
		gull.add_child(wing)
		membrane(wing, [Vector3(side * 0.07, 0.03, -0.09), Vector3(side * 0.35, 0.04, -0.11), Vector3(side * 0.69, -0.015, 0.02), Vector3(side * 0.61, -0.01, 0.17), Vector3(side * 0.47, 0.01, 0.11), Vector3(side * 0.28, 0.03, 0.15), Vector3(side * 0.07, 0.03, 0.15)], feather, "FlightFeathers")
		membrane(wing, [Vector3(side * 0.50, 0.001, 0.045), Vector3(side * 0.70, -0.017, 0.02), Vector3(side * 0.61, -0.012, 0.17)], dark, "WingTip")
	membrane(gull, [Vector3(-0.06, 0, 0.18), Vector3(-0.10, 0, 0.37), Vector3(0.10, 0, 0.37), Vector3(0.06, 0, 0.18)], white, "Tail")
	export_model(gull, "coastal_gull")
	var hand := Node3D.new()
	hand.name = "HumanHand"
	var skin := mat(Color(0.56, 0.34, 0.22), 0.7)
	oval(hand, Vector3(0, 0, -0.04), Vector3(0.052, 0.027, 0.087), skin, "Palm")
	tube(hand, Vector3(0, 0, 0.04), Vector3(0.012, -0.03, 0.34), 0.041, skin, "Forearm")
	for finger in range(4):
		var x := -0.038 + float(finger) * 0.025
		var length := [0.085, 0.10, 0.095, 0.073][finger] as float
		tube(hand, Vector3(x, 0, -0.093), Vector3(x, -0.012, -0.093 - length * 0.55), 0.011, skin, "FingerBase%d" % finger)
		tube(hand, Vector3(x, -0.012, -0.093 - length * 0.55), Vector3(x, -0.039, -0.093 - length), 0.009, skin, "FingerTip%d" % finger)
		oval(hand, Vector3(x, -0.031, -0.082 - length), Vector3(0.007, 0.002, 0.011), skin, "Nail%d" % finger)
	tube(hand, Vector3(0.046, 0, -0.015), Vector3(0.073, -0.021, -0.065), 0.014, skin, "ThumbBase")
	tube(hand, Vector3(0.073, -0.021, -0.065), Vector3(0.055, -0.045, -0.10), 0.011, skin, "ThumbTip")
	export_model(hand, "human_hand")
	var bow := Node3D.new()
	bow.name = "SurvivalBow"
	var wood := mat(Color(0.30, 0.18, 0.085))
	for index in range(24):
		var y1 := -0.5 + float(index) / 24.0
		var y2 := -0.5 + float(index + 1) / 24.0
		tube(bow, Vector3(0, y1, 0.17 * cos(y1 * PI)), Vector3(0, y2, 0.17 * cos(y2 * PI)), 0.013, wood, "Limb%d" % index)
	tube(bow, Vector3(0, -0.5, 0), Vector3(0, 0, -0.16), 0.0017, mat(Color(0.64, 0.55, 0.40)), "LowerString")
	tube(bow, Vector3(0, 0, -0.16), Vector3(0, 0.5, 0), 0.0017, mat(Color(0.64, 0.55, 0.40)), "UpperString")
	export_model(bow, "survival_bow")
	var ridge := Node3D.new()
	ridge.name = "CoastalRidge"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(40):
		for x in range(48):
			var a := Vector2(float(x) / 48.0 * 10 - 5, float(z) / 40.0 * 8 - 4)
			var b := a + Vector2(10.0 / 48.0, 0)
			var c := a + Vector2(0, 8.0 / 40.0)
			var d := b + Vector2(0, 8.0 / 40.0)
			for p in [a, b, c, b, d, c]:
				var h := ridge_height(p)
				var normal := Vector3(ridge_height(p - Vector2(0.02, 0)) - ridge_height(p + Vector2(0.02, 0)), 0.04, ridge_height(p - Vector2(0, 0.02)) - ridge_height(p + Vector2(0, 0.02))).normalized()
				surface.set_normal(normal)
				surface.set_color(Color(0.34, 0.36, 0.33).lerp(Color(0.51, 0.48, 0.40), clampf(h / 4.0, 0, 1)))
				surface.add_vertex(Vector3(p.x, h, p.y))
	part(ridge, surface.commit(), mat(Color.WHITE), Vector3.ZERO, Vector3.ONE, "CraggyRockMesh")
	export_model(ridge, "coastal_ridge")
	quit()

func ridge_height(p: Vector2) -> float:
	var envelope := pow(maxf(0, 1.0 - pow(p.x / 5.0, 2) - pow(p.y / 4.0, 2)), 1.1)
	return -0.12 + envelope * (1.5 + 2.6 * exp(-pow((p.x + 1.2) / 1.9, 2) - pow((p.y - 0.3) / 2.0, 2)) + 0.30 * sin(p.x * 3.1 + sin(p.y * 2.4)) + 0.14 * sin(p.y * 7 + p.x * 3))
