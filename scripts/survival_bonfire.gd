extends StaticBody3D
var flame: MeshInstance3D
var light: OmniLight3D
var clock := 0.0

func _ready() -> void:
	add_to_group("build_surface")
	for i in range(8):
		var stone := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.11
		mesh.height = 0.17
		stone.mesh = mesh
		stone.position = Vector3(cos(i * TAU / 8) * 0.34, -0.07, sin(i * TAU / 8) * 0.34)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.17, 0.16, 0.14)
		stone.material_override = mat
		add_child(stone)
	for i in range(3):
		var log_mesh := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.07
		mesh.height = 0.65
		log_mesh.mesh = mesh
		log_mesh.rotation = Vector3(PI / 2, i * PI / 3, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.1, 0.04)
		log_mesh.material_override = mat
		add_child(log_mesh)
	var imported := preload("res://scripts/mobile_assets.gd").make("campfire-pit", 0.8, true)
	if imported != null:
		for part in get_children():
			if part is MeshInstance3D:
				part.hide()
		add_child(imported)
		imported.position.y = -0.175
	flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2
	cone.height = 0.55
	flame.mesh = cone
	flame.position.y = 0.27
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1, 0.35, 0.03)
	fire.emission_enabled = true
	fire.emission = Color(1, 0.2, 0.01)
	fire.emission_energy_multiplier = 2.0
	flame.material_override = fire
	add_child(flame)
	light = OmniLight3D.new()
	light.position.y = 0.5
	light.light_color = Color(1, 0.55, 0.22)
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)

func _process(delta: float) -> void:
	clock += delta
	flame.scale = Vector3(1.0 + sin(clock * 9) * 0.1, 1.0 + sin(clock * 13) * 0.18, 1.0)
	light.light_energy = 1.3 + sin(clock * 12) * 0.2

