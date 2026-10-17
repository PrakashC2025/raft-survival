extends Node3D
const SURFACES := preload("res://scripts/object_materials.gd")
const FLAME := preload("res://shaders/campfire.gdshader")
const PARTS := preload("res://scripts/machine_visual.gd")
const TIMBER := preload("res://scripts/construction_visual.gd")
const LIGHT_RANGE := 6.0
const LIGHT_ENERGY := 1.1
const LIGHT_ATTENUATION := 1.6
var flames: Node3D
var _burning := false
func _ready() -> void:
	var stick := MeshInstance3D.new()
	stick.mesh = TIMBER.rounded_timber(Vector3(.043,.58,.043))
	stick.rotation.z=.025
	add_child(stick)
	var charred:=SURFACES.make(SURFACES.Kind.WOOD,Color(.035,.026,.016),1.0)
	PARTS.beam(self,Vector3(.009,-.18,.009),Vector3(.025,.18,-.012),.009,charred)
	PARTS.beam(self,Vector3(-.014,-.09,.01),Vector3(-.026,.08,-.003),.006,charred)
	var head := MeshInstance3D.new()
	var cloth_wrap := CylinderMesh.new()
	cloth_wrap.top_radius = 0.041
	cloth_wrap.bottom_radius = 0.032
	cloth_wrap.height = 0.14
	cloth_wrap.radial_segments = 12
	head.mesh = cloth_wrap
	head.position.y = 0.29
	head.material_override = SURFACES.make(SURFACES.Kind.CLOTH,Color(0.12,0.08,0.04),1.0)
	add_child(head)
	var fibre:=SURFACES.make(SURFACES.Kind.CLOTH,Color(.27,.20,.115),1.0)
	# Uneven charred rag winding and rope bindings give the burning head volume.
	for index in 8:
		var angle:=index*2.399
		var strip:=PARTS.box(self,Vector3(cos(angle)*.024,.24+index*.014,sin(angle)*.024),Vector3(.059,.018,.041),fibre if index<5 else charred)
		strip.rotation=Vector3(.08*sin(angle),angle,.17*cos(angle))
	for index in 3:
		PARTS.cylinder(self,Vector3(0,.20+index*.013,0),.032,.008,fibre)
	flames = Node3D.new()
	flames.name = "TorchFlames"
	flames.visible = _burning
	add_child(flames)
	for index in 1:
		var mat := ShaderMaterial.new();mat.shader=FLAME
		mat.set_shader_parameter("flame_phase",index*2.17)
		var visual := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(.145,.27-index*.026)
		mat.set_shader_parameter("torch_readability",1.0)
		mat.set_shader_parameter("torch_flame_size",quad.size)
		visual.mesh = quad
		visual.material_override = mat
		visual.position=Vector3(sin(index*2.17)*.012,.46-index*.013,cos(index*2.17)*.012)
		visual.rotation.y = index*PI/3.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shader expansion must still be rendered at the edge of the camera view.
		visual.extra_cull_margin = 4.0
		flames.add_child(visual)
func set_burning(lit: bool) -> void:
	_burning = lit
	if flames != null: flames.visible = lit

static func light_energy_at(seconds: float) -> float:
	return LIGHT_ENERGY * (1.0 + .045 * sin(seconds * 13.0) + .025 * sin(seconds * 21.0 + 1.7))
