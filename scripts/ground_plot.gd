extends Planter
## A small soil patch uses the same growth, moisture and harvest lifecycle.
func _ready() -> void:
	box_size=Vector3(0.65,0.04,0.65)
	super._ready()
	remove_from_group("build_surface")
	add_to_group("ground_plot")

func category_name() -> String:return "ground"

func _build_visual() -> void:
	_soil=preload("res://scripts/soil_visual.gd").create(Vector2(0.65,0.65),true,soil_color)
	_soil.position.y=0.012;add_child(_soil)
	_slot=Node3D.new();_slot.name="PlantSlot";_slot.position.y=0.025;add_child(_slot)
	var col:=CollisionShape3D.new()
	var shape:=CylinderShape3D.new();shape.radius=0.34;shape.height=0.06
	col.shape=shape;col.position.y=0.025;add_child(col)

func clear_plant() -> void:
	super.clear_plant()
	var actor:=get_tree().get_first_node_in_group("player")
	if actor!=null:actor.call("_queue_save")
	queue_free()
