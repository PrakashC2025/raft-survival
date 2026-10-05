extends Node3D
const SURFACES := preload("res://scripts/object_materials.gd")
const FLAME := preload("res://shaders/campfire.gdshader")
var flames: Node3D
func _ready() -> void:
	var stick := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.024
	shaft.bottom_radius = 0.018
	shaft.height = 0.58
	shaft.radial_segments = 10
	stick.mesh = shaft
	stick.material_override = SURFACES.make(SURFACES.Kind.WOOD,Color(0.26,0.15,0.06))
	add_child(stick)
	var head := MeshInstance3D.new()
	var wrap := CylinderMesh.new()
	wrap.top_radius = 0.041
	wrap.bottom_radius = 0.032
	wrap.height = 0.14
	wrap.radial_segments = 12
	head.mesh = wrap
	head.position.y = 0.29
	head.material_override = SURFACES.make(SURFACES.Kind.CLOTH,Color(0.31,0.24,0.13))
	add_child(head)
	flames = Node3D.new()
	flames.name = "TorchFlames"
	add_child(flames)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME
	for angle in [0.0,PI*0.5]:
		var visual := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.19,0.31)
		visual.mesh = quad
		visual.material_override = mat
		visual.position.y = 0.46
		visual.rotation.y = angle
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.add_child(visual)
func set_burning(lit: bool) -> void:
	if flames != null: flames.visible = lit
