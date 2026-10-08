extends "res://scripts/campfire.gd"
func _ready() -> void:
	super._ready()
	var pot := MeshInstance3D.new()
	var pot_mesh := SphereMesh.new()
	pot_mesh.radius = 0.25
	pot_mesh.height = 0.4
	pot_mesh.radial_segments = 16
	pot_mesh.rings = 8
	pot.mesh = pot_mesh
	pot.position.y = 0.85
	pot.material_override = preload("res://scripts/object_materials.gd").make(3, Color(0.64, 0.58, 0.46), 0.7, 0.1)
	add_child(pot)
	var stand := MeshInstance3D.new()
	var tripod_mesh := CylinderMesh.new()
	tripod_mesh.top_radius = 0.08
	tripod_mesh.bottom_radius = 0.08
	tripod_mesh.height = 0.9
	tripod_mesh.radial_segments = 12
	stand.mesh = tripod_mesh
	stand.position.y = 0.55
	stand.material_override = pot.material_override
	add_child(stand)
	for side in [-1, 1]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.03
		leg_mesh.bottom_radius = 0.03
		leg_mesh.height = 0.55
		leg_mesh.radial_segments = 8
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.22, 0.15, side * 0.12)
		leg.material_override = pot.material_override
		add_child(leg)
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.04
	handle_mesh.bottom_radius = 0.04
	handle_mesh.height = 0.35
	handle_mesh.radial_segments = 8
	handle.mesh = handle_mesh
	handle.position = Vector3(0, 0.88, 0)
	handle.material_override = preload("res://scripts/object_materials.gd").make(3, Color(0.64, 0.58, 0.46), 0.8, 0.1)
	add_child(handle)
