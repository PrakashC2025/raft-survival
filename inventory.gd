extends Node
# Register as an Autoload: Project Settings -> Globals -> Autoload
# Path: res://inventory.gd   Node Name: Inventory

var items := {"Wood": 0, "Rope": 0, "Plastic": 0, "Barrel": 0, "Stone": 0, "Metal": 0}

# Test/debug toggle. When true, crafting never consumes resources (handy for
# trying out the building system). Flip it with the debug key in Player.
var infinite: bool = false

# What each craftable/placeable thing costs.
const RECIPES := {
	"Foundation":      {"Wood": 5},
	"Wall":            {"Wood": 8, "Rope": 1},
	"Roof":            {"Wood": 8, "Rope": 1},
	"Stairs":          {"Wood": 6, "Rope": 1},
	"Door":            {"Wood": 4, "Rope": 1},
	"Window":          {"Wood": 3, "Plastic": 1},
	"Bonfire":         {"Wood": 8, "Rope": 2},
	"Raft Extension":  {"Wood": 10, "Plastic": 2},
}

func add(item: String, amount: int = 1) -> void:
	items[item] = items.get(item, 0) + amount
	print("Inventory:", items)

func has(item: String, amount: int) -> bool:
	return items.get(item, 0) >= amount

func remove(item: String, amount: int) -> void:
	# .get(item, 0) instead of items[item] — a brand-new item name (e.g. from
	# a future recipe) must default to 0 instead of crashing on a missing key.
	items[item] = items.get(item, 0) - amount

func can_afford(recipe: String) -> bool:
	if infinite:
		return true
	if not RECIPES.has(recipe):
		return false
	for item in RECIPES[recipe]:
		if items.get(item, 0) < RECIPES[recipe][item]:
			return false
	return true

func craft(recipe: String) -> bool:
	if not RECIPES.has(recipe):
		return false
	# Re-check affordability here too, not just in the caller — craft() must
	# never be the thing that lets an item count go negative, even if some
	# future caller forgets to check can_afford() first.
	if not can_afford(recipe):
		return false
	if infinite:
		return true
	for item in RECIPES[recipe]:
		remove(item, RECIPES[recipe][item])
	return true
