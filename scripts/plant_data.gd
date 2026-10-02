extends Node
## Autoload registered in Project Settings as: Path: res://plant_data.gd  Node Name: PlantDB
## Central registry of every plant type in the game.
## TO ADD A NEW PLANT: copy one block inside _build_defs() and edit the
## values. Nothing else in the codebase needs to change for a normal
## ROOT or FRUIT_TREE plant.

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
		"fruit_count": 5,
		# REAL-PALM CROP: every palm rolls a different number of nuts (some
		# full bunches, some 1-2, some bare). Ripe nuts drop ~one per DAY;
		# an emptied slot grows a NEW nut over ~2 in-game days.
		"fruit_variation": true,
		"fruit_fall_item": "Coconut",
		"fruit_fall_days": 2.0,
		"trunk_height": 2.6,
		"trunk_radius": 0.14,
		"canopy_radius": 1.1,
		"trunk_color": Color(0.5, 0.36, 0.2),
		"canopy_color": Color(0.16, 0.5, 0.22),
		"fruit_color": Color(0.17, 0.09, 0.028),   # ripe husk brown — LINEAR space (matches CoconutPickup)
		"fruit_green_color": Color(0.33, 0.62, 0.16), # young coconuts are bright green
		"fruit_radius": 0.042,                      # fallback spheres only (real mesh below is used when present)
		# REAL NUT FRUIT: every slot carries ONE real king_coconut.glb nut
		# (coconut_single.res, ball-carved from the interpenetrated bunch) —
		# the previous whole-BUNCH-per-slot made 5 overlapping shells read as
		# one giant blob floating under the crown. 5 clustered single nuts =
		# a natural bunch. Scaled to ~12-13 cm ripe (fruit_scale × the 12 cm
		# bake); unripe slots are smaller + green.
		"fruit_mesh": "res://grass/baked/coconut_single.res",
		"fruit_scale": 1.05,
		"fruit_unlit": true,                       # husks shade like the pickups, not glowing brown balls
		"chop_hits_required": 5,
		"wood_yield": 8,
		# Fell: wood only — the tree's nuts scatter PHYSICALLY onto the ground
		# at the moment of the cut (_scatter_all_fruits), not into inventory.
		"fell_drops": [["Wood", 6, 9]],
		"planter_categories": ["tree_pot"],
	})

	# ---------------- APPLE TREE (rare fruit tree, real glb model) -------
	_add({
		"id": "Apple",
		"display_name": "Apple Tree",
		"category": Category.FRUIT_TREE,
		"harvest_type": HarvestType.PICK,
		"seed_item": "Apple Seed",
		"yield_item": "Apple",
		"yield_min": 1,
		"yield_max": 1,
		"grow_stage_time": [8.0, 12.0, 10.0],    # small tree -> big tree -> fruiting (~30 s total: fast orchard loop)
		"fruit_regrow_time": 25.0,               # new apples ripen quickly so the pick/eat/replant loop stays snappy
		"fruit_count": 8,                        # dense canopy bake carries 8 anchor points
		"fruit_layout": "canopy",                # apples sit IN the crown (coconuts hang)
		"fruit_mesh": "res://grass/baked/apple_single.res", # real scanned apple
		"fruit_falls": true,                     # ripe apples drop on their own
		"fruit_fall_delay": 45.0,                # ...this long after ripening — real apples hang a good while (12 s left the tree bare before the player even reached it)
		"fruit_scale": 1.0,                      # the baked apple is 16 cm — REAL apple size (1.8 made 29 cm beach balls)
		"food_value": 30.0,
		"trunk_height": 2.4,
		"trunk_radius": 0.16,
		"canopy_radius": 1.2,
		"trunk_color": Color(0.42, 0.30, 0.18),
		"canopy_color": Color(0.22, 0.48, 0.18),
		"fruit_color": Color(0.78, 0.12, 0.1),
		"fruit_radius": 0.045,
		"chop_hits_required": 6,
		"wood_yield": 8,
		"fell_drops": [["Wood", 5, 8], ["Apple Seed", 1, 2]],
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
	defs[d["id"]] = d


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
