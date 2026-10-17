extends RefCounted
## One editable configuration: effects are [hunger, thirst, health].
const RAW := {
	"Bell Pepper":[7,4,0],"Cucumber":[5,10,0],"Pumpkin":[6,1,0],"Strawberry":[6,4,0],"Corn":[9,1,0],"Papaya":[11,8,0],
	"Potato":[5,-1,-3],"Tomato":[6,3,-2],"Banana":[8,1,-1],"Coconut":[7,12,-1],
	"Carrot":[5,1,-2],"Onion":[4,-1,-2],"Fish":[7,-2,-8],"Raw Bird":[7,-2,-10],
	"Raw Meat":[8,-2,-10],"Raw Crab":[6,-2,-7],"Water":[0,40,0],
	"Dirty Water Can":[0,12,-8],"Clean Water Can":[0,100,0],
	# The requested simplified game rule: boiling prepares a drinking tumbler.
	"Ocean Water Tumbler":[0,12,-8],"Boiled Water Tumbler":[0,65,0]
}
static func is_drink(item: String) -> bool:return item in ["Water","Dirty Water Can","Clean Water Can","Ocean Water Tumbler","Boiled Water Tumbler"]
const RECIPES := {
	"Roasted Pumpkin":{"ingredients":{"Sliced Pumpkin":1},"seconds":10,"effects":[25,5,6]},
	"Roasted Corn":{"ingredients":{"Sliced Corn":1},"seconds":10,"effects":[26,4,6]},
	"Garden Vegetable Stew":{"ingredients":{"Sliced Bell Pepper":1,"Sliced Tomato":1,"Clean Water Can":1},"seconds":18,"effects":[37,28,11]},
	"Cucumber Tomato Soup":{"ingredients":{"Sliced Cucumber":1,"Sliced Tomato":1,"Clean Water Can":1},"seconds":16,"effects":[31,32,9]},
	"Papaya Banana Mash":{"ingredients":{"Sliced Papaya":1,"Banana":1,"Clean Water Can":1},"seconds":12,"effects":[35,22,8]},
	"Strawberry Compote":{"ingredients":{"Sliced Strawberry":1,"Clean Water Can":1},"seconds":9,"effects":[23,20,6]},
	"Pepper Fish Skillet":{"ingredients":{"Sliced Bell Pepper":1,"Fish":1},"seconds":17,"effects":[39,9,12]},
	"Pumpkin Corn Soup":{"ingredients":{"Sliced Pumpkin":1,"Sliced Corn":1,"Clean Water Can":1},"seconds":20,"effects":[43,28,12]},
	"Cooked Potato":{"ingredients":{"Potato":1},"seconds":8,"effects":[20,3,5]},
	"Cooked Tomato":{"ingredients":{"Tomato":1},"seconds":7,"effects":[18,8,5]},
	"Cooked Fish":{"ingredients":{"Fish":1},"seconds":12,"effects":[28,4,8]},
	"Potato Tomato Stew":{"ingredients":{"Potato":1,"Tomato":1,"Clean Water Can":1},"seconds":16,"effects":[35,25,10]},
	"Fish Potato Meal":{"ingredients":{"Fish":1,"Potato":1},"seconds":16,"effects":[38,8,12]},
	"Fish Potato Tomato Soup":{"ingredients":{"Fish":1,"Potato":1,"Tomato":1,"Clean Water Can":1},"seconds":20,"effects":[45,30,15]},
	"Fish Tomato Curry":{"ingredients":{"Fish":1,"Tomato":1,"Clean Water Can":1},"seconds":18,"effects":[36,22,12]},
	"Banana Mash":{"ingredients":{"Banana":1,"Clean Water Can":1},"seconds":10,"effects":[24,18,6]},
	"Roasted Carrot":{"ingredients":{"Carrot":1},"seconds":8,"effects":[19,4,5]},
	"Cooked Onion":{"ingredients":{"Onion":1},"seconds":8,"effects":[17,3,5]},
	"Tropical Fruit Stew":{"ingredients":{"Banana":1,"Coconut":1,"Clean Water Can":1},"seconds":15,"effects":[34,28,10]},
	"Root Vegetable Soup":{"ingredients":{"Potato":1,"Carrot":1,"Onion":1,"Clean Water Can":1},"seconds":18,"effects":[40,30,12]},
	"Roast Bird":{"ingredients":{"Raw Bird":1},"seconds":14,"effects":[32,5,8]},
	"Cooked Meat":{"ingredients":{"Raw Meat":1},"seconds":14,"effects":[34,5,9]},
	"Cooked Crab":{"ingredients":{"Raw Crab":1},"seconds":12,"effects":[27,6,7]},
	"Grilled Fish and Onion":{"ingredients":{"Fish":1,"Onion":1},"seconds":16,"effects":[36,5,10]},
	"Coconut Fish Stew":{"ingredients":{"Fish":1,"Coconut":1,"Onion":1,"Clean Water Can":1},"seconds":22,"effects":[46,30,14]},
	"Crab Tomato Broth":{"ingredients":{"Raw Crab":1,"Tomato":1,"Onion":1,"Clean Water Can":1},"seconds":20,"effects":[42,28,12]}
}
static func category(dish: String) -> String:
	if dish in ["Banana Mash","Tropical Fruit Stew","Papaya Banana Mash","Strawberry Compote"]:return "FRUIT"
	return "SOUPS & STEWS" if RECIPES[dish].ingredients.has("Clean Water Can") else "GRILL"
static func method(dish: String) -> String:
	if dish=="Grilled Fish and Onion":return "Grill fish over embers with sliced onion."
	if dish=="Coconut Fish Stew":return "Simmer fish and onion in coconut and clean water."
	if dish=="Crab Tomato Broth":return "Simmer crab with diced tomato, onion and clean water."
	if category(dish)=="FRUIT":return "Mash fruit, add clean water and warm gently."
	if category(dish)=="SOUPS & STEWS":return "Slice ingredients, add clean water and simmer."
	return "Prepare and turn over the embers until cooked."
static func effects(item: String) -> Array:
	if item.begins_with("Wrapped "):
		item=item.trim_prefix("Wrapped ")
		if not RECIPES.has(item):return []
	if not preload("res://scripts/garden_items.gd").sliced_crop(item).is_empty():item=preload("res://scripts/garden_items.gd").sliced_crop(item)
	if item=="Baked Potato":item="Cooked Potato" # legacy meals remain usable
	if RAW.has(item):return RAW[item]
	return RECIPES[item].effects if RECIPES.has(item) else []
static func edible(item: String) -> bool:return not effects(item).is_empty()
