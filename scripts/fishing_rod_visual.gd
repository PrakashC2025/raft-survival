extends Node3D
## Tapered, flexible wooden rod with line guides and a working reel handle.
const MAT := preload("res://scripts/object_materials.gd")
var _segments: Array[MeshInstance3D]=[]
var _guides: Array[MeshInstance3D]=[]
var _handle: Node3D
var _tip: Marker3D
var _player: Node3D
func _ready() -> void:
	_player=get_tree().get_first_node_in_group("player") as Node3D
	if get_child_count()>0:
		for index in 7:
			_segments.append(get_node("Rod%d"%index));_guides.append(get_node("Guide%d"%index))
		_handle=get_node("ReelHandle");_tip=get_node("FishingTip");return
	var wood:=MAT.make(MAT.Kind.WOOD,Color(0.37,0.26,0.13),0.85)
	var metal:=MAT.make(MAT.Kind.METAL,Color(0.32,0.36,0.34),0.38,0.6)
	for index in 7:
		var part:=MeshInstance3D.new();part.name="Rod%d"%index
		var shape:=CylinderMesh.new();shape.height=0.205;shape.bottom_radius=lerpf(0.017,0.004,float(index)/7);shape.top_radius=shape.bottom_radius-0.0016;shape.radial_segments=10
		part.mesh=shape;part.material_override=wood;add_child(part);_segments.append(part)
		var guide:=MeshInstance3D.new();guide.name="Guide%d"%index
		var ring:=TorusMesh.new();ring.inner_radius=0.009;ring.outer_radius=0.012;ring.rings=10;ring.ring_segments=4
		guide.mesh=ring;guide.material_override=metal;guide.rotation.x=PI/2;add_child(guide);_guides.append(guide)
	var art:=preload("res://scripts/machine_visual.gd")
	var spool:=art.cylinder(self,Vector3(0.06,-0.03,-0.15),0.047,0.055,metal);spool.rotation.z=PI/2
	_handle=Node3D.new();_handle.name="ReelHandle";_handle.position=Vector3(0.1,-0.03,-0.15);add_child(_handle)
	art.box(_handle,Vector3(0,0.028,0),Vector3(0.015,0.06,0.015),metal)
	art.cylinder(_handle,Vector3(0.018,0.056,0),0.012,0.045,wood).rotation.z=PI/2
	_tip=Marker3D.new();_tip.name="FishingTip";add_child(_tip)
func _process(delta: float) -> void:
	if _player==null:return
	var action:=_player.get_node_or_null("SurvivalAction")
	var reeling:=action!=null and str(action.get("kind"))=="reel"
	if reeling:_handle.rotation.x+=delta*15
	var waiting:=float(_player.get("_fishing_time_remaining"))>0
	var bend: float=0.08 if waiting else 0.025
	if reeling:bend=0.19
	var time:=float(_player.get("_hand_time"))
	var start:=Vector3(0,0.02,0.07)
	for index in 7:
		var t:=float(index+1)/7
		var end:=Vector3(0,0.02-bend*t*t+sin(time*4)*t*t*0.006,0.07-t*1.42)
		var part:=_segments[index];part.position=(start+end)*0.5
		part.basis=Basis(Quaternion(Vector3.UP,(end-start).normalized()))
		_guides[index].position=end+Vector3(0,-0.016,0)
		start=end
	_tip.position=start
