extends "res://scripts/storage_box.gd"
## One persistent hunted body owns its meat until preparation succeeds.
var species:="Boar"
var carried:=false
var floating:=false
var visual: Node3D
var _sea: Node3D
var _clock:=0.0
const MODELS:={"Boar":"hunting_boar","Crocodile":"hunting_crocodile","Crab":"shore_crab","Turtle":"sea_turtle","Bird":"coastal_gull","Fish":"coastal_fish","Grouper":"coastal_fish","Ray":"coastal_fish","Octopus":"shore_crab","Shark":"reef_shark"}

func _ready() -> void:
	loot_bag=true;capacity=30;contents.resize(capacity)
	for index in capacity:contents[index]={}
	add_to_group("storage_box");add_to_group("animal_carcass");collision_layer=2;collision_mask=0
	var collision:=CollisionShape3D.new();collision.name="CarcassCollision"
	var box:=BoxShape3D.new();box.size=Vector3(.65,.4,1.6) if species in ["Boar","Crocodile","Shark"] else Vector3(.5,.25,.65);collision.shape=box;collision.position.y=.2;add_child(collision)
	visual=make_visual(species);add_child(visual)
	_sea=get_tree().get_first_node_in_group("ocean") as Node3D
	var caption:=Label3D.new();caption.name="CarcassCaption";caption.text=species.to_upper()+" · CARRY / PREPARE";caption.position.y=.7;caption.font_size=26;caption.pixel_size=.003;caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED;caption.visibility_range_end=8;add_child(caption)

static func make_visual(kind: String) -> Node3D:
	var root:=Node3D.new();root.name="Hunted"+kind
	var path: String="res://models/"+str(MODELS.get(kind,"raw_meat"))+".glb"
	var model: Node3D=(load(path) as PackedScene).instantiate();root.add_child(model)
	if kind in ["Ray","Octopus"]:
		root.remove_child(model);model.free();model=preload("res://scripts/sea_fauna_visual.gd").ray() if kind=="Ray" else preload("res://scripts/hunting_visual.gd").octopus();root.add_child(model)
	for animation in model.find_children("*","AnimationPlayer",true,false):
		animation.stop();animation.active=false
	if kind=="Boar":model.rotation.z=PI/2;model.position.y=.27
	elif kind=="Crocodile":
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			var skin:=ShaderMaterial.new();skin.shader=preload("res://shaders/hunting_real_croc.gdshader");skin.set_shader_parameter("skin_photo",preload("res://models/hunting_crocodile_Image_7.png"));skin.set_shader_parameter("source_details",preload("res://models/hunting_crocodile_croc_diffuse.png"));mesh.material_override=skin
	else:
		# Fit small game to a carryable body without changing its source resource.
		var bounds:=AABB();var found:=false
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			var mesh_transform: Transform3D=mesh.transform;var ancestor:=mesh.get_parent()
			while ancestor!=model:mesh_transform=(ancestor as Node3D).transform*mesh_transform;ancestor=ancestor.get_parent()
			var box: AABB=mesh_transform*mesh.get_aabb();bounds=bounds.merge(box) if found else box;found=true
		var display_length: float={"Shark":2.2,"Grouper":1.1,"Ray":.9,"Turtle":.75}.get(kind,.65)
		var fit:=display_length/maxf(bounds.size.length(),.01);model.scale=Vector3.ONE*fit;model.position=-bounds.get_center()*fit+Vector3.UP*.18;model.rotation.z=.6
	return root

func interaction_caption() -> String:return "HUNTED "+species.to_upper()
func interact_survival(actor: Node) -> void:actor.get_node("HuntingCargo").open(self)

func _process(delta: float) -> void:
	if carried or not floating or not is_instance_valid(_sea):return
	_clock+=delta;global_position.y=float(_sea.call("get_height",global_position))+.12+sin(_clock*1.5)*.025
	visual.rotation.z=sin(_clock)*.035

func support_record() -> Dictionary:
	var parent:=get_parent()
	if parent!=null and (parent.is_in_group("player_boat") or parent.is_in_group("raft")):
		return {"support":"boat" if parent.is_in_group("player_boat") else "raft","local_p":[position.x,position.y,position.z],"yaw":rotation.y}
	return {}
