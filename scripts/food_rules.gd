extends RefCounted
## One editable configuration: effects are [hunger, thirst, health].
const RAW := {
	"Potato":[5,-1,-3],"Tomato":[6,3,-2],"Banana":[8,1,-1],"Coconut":[7,12,-1],
	"Carrot":[5,1,-2],"Onion":[4,-1,-2],"Fish":[7,-2,-8],"Raw Bird":[7,-2,-10],
	"Raw Meat":[8,-2,-10],"Raw Crab":[6,-2,-7],"Water":[0,40,0],
	"Dirty Water Can":[0,12,-8],"Clean Water Can":[0,100,0]
}
const RECIPES := {
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
	"Cooked Crab":{"ingredients":{"Raw Crab":1},"seconds":12,"effects":[27,6,7]}
}
static func effects(item: String) -> Array:
	if item=="Baked Potato":item="Cooked Potato" # legacy meals remain usable
	if RAW.has(item):return RAW[item]
	return RECIPES[item].effects if RECIPES.has(item) else []
static func edible(item: String) -> bool:return not effects(item).is_empty()
