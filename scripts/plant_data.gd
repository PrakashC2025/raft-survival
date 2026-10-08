extends Node
## Autoload registered in Project Settings as: Path: res://plant_data.gd  Node Name: PlantDB
## Central registry of every plant type in the game.
## TO ADD A NEW PLANT: copy one block inside _build_defs() and edit the
## values. Register edible item aliases/nutrition and any supplied model
## alongside the other produce when adding a new crop.

const Category = {
	ROOT = "ROOT",
	FRUIT_TREE = "FRUIT_TREE",
}

const HarvestType = {
	DIG = "DIG",
	PICK = "PICK",
}

var defs: Dictionary = {}


func _ready() -> void:
	_build_defs()


func _build_defs() -> void:
	defs.clear()
	for crop in ["Carrot", "Tomato", "Onion"]:
		_add({"id": crop, "display_name": crop, "category": Category.ROOT,
			"harvest_type": HarvestType.DIG, "seed_item": crop + " Seed", "yield_item": crop,
			"yield_min": 2, "yield_max": 4, "grow_stage_time": [20.0, 35.0, 25.0],
			"dig_time": 1.2, "leaf_color": Color(0.18, 0.37, 0.12), "planter_categories": ["pot", "box"]})

	# ---------------- POTATO (root crop, dig to harvest) ----------------
	_add({
		"id": "Potato",
		"display_name": "Potato",
		"category": Category.ROOT,
		"harvest_type": HarvestType.DIG,
		"seed_item": "Potato Seed",
		"yield_item": "Potato",
		"yield_min": 2,
		"yield_max": 4,
		"grow_stage_time": [15.0, 25.0, 20.0],   # seed->sprout, sprout->growing, growing->mature
		"dig_time": 1.4,
		"leaf_color": Color(0.25, 0.55, 0.18),
		"planter_categories": ["pot", "box"],
	})

	# ---------------- COCONUT TREE (fruit tree) --------------------------
	_add({
		"id": "Coconut",
		"display_name": "Coconut Tree",
		"category": Category.FRUIT_TREE,
		"harvest_type": HarvestType.PICK,
		"seed_item": "Coconut Seed",
		"yield_item": "Coconut",
		"yield_min": 1,
		"yield_max": 1,
		"grow_stage_time": [30.0, 50.0, 40.0],
		"fruit_regrow_time": 70.0,
		"fruit_count": 4,
		"trunk_height": 5.8,
		"trunk_radius": 0.22,
		"canopy_radius": 2.0,
		"trunk_color": Color(0.5, 0.36, 0.2),
		"canopy_color": Color(0.16, 0.5, 0.22),
		"fruit_color": Color(0.42, 0.3, 0.16),
		"fruit_radius": 0.13,
		"chop_hits_required": 5,
		"wood_yield": 8,
		"fell_drops": [["Wood", 6, 9], ["Coconut", 1, 2]],
		"planter_categories": ["tree_pot"],
	})

	# ---------------- BANANA TREE (fruit tree) ---------------------------
	_add({
		"id": "Banana",
		"display_name": "Banana Tree",
		"category": Category.FRUIT_TREE,
		"harvest_type": HarvestType.PICK,
		"seed_item": "Banana Seed",
		"yield_item": "Banana",
		"yield_min": 2,
		"yield_max": 3,
		"grow_stage_time": [20.0, 35.0, 25.0],
		"fruit_regrow_time": 45.0,
		"fruit_count": 5,
		"trunk_height": 2.1,
		"trunk_radius": 0.11,
		"canopy_radius": 0.85,
		"trunk_color": Color(0.42, 0.55, 0.24),
		"canopy_color": Color(0.24, 0.58, 0.22),
		"fruit_color": Color(0.85, 0.78, 0.25),
		"fruit_radius": 0.09,
		"chop_hits_required": 4,
		"wood_yield": 5,
		"fell_drops": [["Wood", 4, 6], ["Banana", 1, 3]],
		"planter_categories": ["tree_pot"],
	})


func _add(d: Dictionary) -> void:
	d["planter_categories"].append("ground")
	defs[d["id"]] = d

func crop_for_item(item: String) -> String:
	var id := item.trim_suffix(" Seed")
	return id if defs.has(id) else ""


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func all_ids() -> Array:
	return defs.keys()


func ids_for_planter(planter_category: String) -> Array:
	var out: Array = []
	for id in defs:
		var d: Dictionary = defs[id]
		if d.get("planter_categories", []).has(planter_category):
			out.append(id)
	return out
