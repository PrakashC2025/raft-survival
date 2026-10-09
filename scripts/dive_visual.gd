extends RefCounted
const ART := preload("res://scripts/machine_visual.gd")
const MAT := preload("res://scripts/object_materials.gd")
static var _plastic: ShaderMaterial
static var _hose: StandardMaterial3D

static func tank() -> Node3D:
	var root := Node3D.new(); root.name="HandmadeAirTank"
	if _plastic == null: _plastic=MAT.make(MAT.Kind.PLASTIC,Color(.55,.62,.44),.82)
	if _hose == null: _hose=StandardMaterial3D.new();_hose.albedo_color=Color(.055,.06,.055);_hose.roughness=.94
	var can := CylinderMesh.new();can.top_radius=.145;can.bottom_radius=.13;can.height=.52;can.radial_segments=16
	ART.part(root,can,Vector3.ZERO,_plastic,"SalvagedPlasticCan")
	ART.cylinder(root,Vector3(0,.28,0),.055,.075,_hose).name="ScrewCap"
	for y in [-.15,.15]:
		var band:=TorusMesh.new();band.inner_radius=.144;band.outer_radius=.158;band.rings=16;band.ring_segments=6
		ART.part(root,band,Vector3(0,y,0),MAT.make(MAT.Kind.CLOTH,Color(.23,.19,.12),.95),"RopeBand")
	for x in [-.11,.11]: ART.box(root,Vector3(x,0,-.12),Vector3(.045,.57,.026),_hose).name="HandmadeStrap"
	var handle:=TorusMesh.new();handle.inner_radius=.063;handle.outer_radius=.077;handle.rings=16;handle.ring_segments=6
	var grip:=ART.part(root,handle,Vector3(.06,.245,0),_plastic,"CanHandle");grip.rotation.x=PI/2
	for index in 12:
		var t:=float(index)/11
		var segment:=ART.cylinder(root,Vector3(.16+sin(t*PI)*.11,.23-t*.33,-.04-t*.16),.009,.04,_hose)
		segment.rotation.z=.45+t*.7
	return root

static func swim_hand(left: bool) -> Node3D:
	var root := Node3D.new();root.name="LeftSwimHand" if left else "RightSwimHand"
	var model:=preload("res://models/human_hand.glb").instantiate() as Node3D
	for node in model.find_children("*","MeshInstance3D",true,false):
		var part:=node as MeshInstance3D
		part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The supplied original model already includes a correctly sized forearm.
	model.scale=Vector3(-1 if left else 1,1,1)
	root.add_child(model)
	return root
