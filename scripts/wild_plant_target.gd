extends StaticBody3D
## One lightweight interaction target; the island controller owns its lifecycle.
var garden: Node
var plant_index := 0

func interact_survival(actor: Node3D) -> void:
	if is_instance_valid(garden): garden.collect(plant_index, actor)

func interaction_caption() -> String:
	if not is_instance_valid(garden): return "USE"
	return garden.caption(plant_index)
