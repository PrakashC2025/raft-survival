extends StaticBody3D
## Compact weathered-wood cradle and repair bench for assembling the raft rowboat.
const TIMBER:=preload("res://scripts/construction_visual.gd")

func _ready() -> void:
	add_to_group("build_surface")
	add_to_group("boat_workshop")
	add_child((load("res://models/hunting_workbench.glb") as PackedScene).instantiate())
	var label:=Label3D.new();label.text="BOAT WORKSHOP\nUSE TO BUILD";label.position.y=1.1;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=28;label.pixel_size=.002;label.outline_size=5;label.visibility_range_end=12;add_child(label)

func _original_visual() -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(preload("res://scripts/hunting_materials.gd").wood())
	var plank:=TIMBER.rounded_timber(Vector3(1.65,.12,.13),1)
	for x in [-.54,.54]:
		for z in [-.42,.42]:
			var leg:=TIMBER.rounded_timber(Vector3(.12,.62,.12),1)
			surface.append_from(leg,0,Transform3D(Basis.IDENTITY,Vector3(x,-.18,z)))
	for y in [-.43,-.12,.18]:surface.append_from(plank,0,Transform3D(Basis.IDENTITY,Vector3(0,y,0)))
	var keel:=TIMBER.rounded_timber(Vector3(1.35,.1,.18),1)
	surface.append_from(keel,0,Transform3D(Basis.IDENTITY,Vector3(0,.34,0)))
	var visual:=MeshInstance3D.new();visual.name="WeatheredBoatBuildingCradle";visual.mesh=surface.commit();add_child(visual)
	visual.material_override=preload("res://scripts/hunting_materials.gd").wood()
	var art:=preload("res://scripts/machine_visual.gd")
	var detail:=Node3D.new();detail.name="BoatwrightTools";add_child(detail)
	var iron:=art.aged(1,Color(.19,.21,.20),.65,.65)
	var wood:=preload("res://scripts/hunting_materials.gd").wood()
	# Rounded timber saddles, iron straps, a mallet and a hand plane make the work visible.
	for plank_index in 5:
		art.box(detail,Vector3(0,.19,-.36+plank_index*.18),Vector3(1.68,.055,.173),wood)
	for x in [-.57,.57]:
		for side in [-1,1]:
			art.beam(detail,Vector3(x,.22,side*.10),Vector3(x,.65,side*.37),.065,wood)
		art.box(detail,Vector3(x,.53,0),Vector3(.09,.10,.38),wood)
	for x in [-.57,.57]:
		for z in [-.38,.38]:
			art.beam(detail,Vector3(x,-.36,z),Vector3(x*.55,.15,z),.065,wood)
			art.box(detail,Vector3(x,.20,z),Vector3(.16,.028,.28),iron)
	art.beam(detail,Vector3(.30,.27,.05),Vector3(.70,.27,.05),.035,wood)
	var mallet:=art.cylinder(detail,Vector3(.67,.29,.05),.063,.18,wood);mallet.rotation.x=PI/2
	art.box(detail,Vector3(-.42,.27,.02),Vector3(.20,.06,.08),iron)
	art.beam(detail,Vector3(-.49,.29,.02),Vector3(-.45,.37,.02),.035,wood)
	preload("res://scripts/hunting_visual.gd").merge_parts(detail)
	var label:=Label3D.new();label.text="BOAT WORKSHOP\nUSE TO BUILD";label.position.y=1.45;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=28;label.pixel_size=.002;label.outline_size=5;label.visibility_range_end=12;add_child(label)

func interaction_caption() -> String:return "BUILD BOAT"
func interact_survival(actor: Node3D) -> void:
	actor.get_node("BoatBuilding").call("open",self)
