extends StaticBody3D
## One lightweight interaction target; the island controller owns its lifecycle.
var garden: Node
var plant_index := 0
var required_tool: String:
	get:
		if not is_instance_valid(garden) or plant_index>=garden.records.size():return ""
		return "Axe" if int(garden.records[plant_index].kind)<2 else ""
var health: int:
	get:
		if not is_instance_valid(garden) or plant_index>=garden.records.size():return 0
		var record:Dictionary=garden.records[plant_index]
		return int(record.health) if float(record.growth)>0 else 0

func interact_survival(actor: Node3D) -> void:
	if required_tool=="Axe" and actor.get("active_item")=="Axe":
		actor.get_node("SurvivalTools").call("use");return
	if is_instance_valid(garden): garden.collect(plant_index, actor)

func tool_hit(actor: Node3D,item: String) -> bool:
	return item=="Axe" and required_tool=="Axe" and is_instance_valid(garden) and garden.collect(plant_index,actor,false)

func interaction_caption() -> String:
	if not is_instance_valid(garden): return "USE"
	return garden.caption(plant_index)
