extends RefCounted
## Brief equipment instructions, shown on deliberate selection only.
const FOOD := preload("res://scripts/food_rules.gd")
const TIPS := {
	"Rope":"Aim at floating salvage. Hold and release to cast; it reels back automatically.",
	"Torch":"Aim at a burning bonfire to light. Aim at a wall to mount.",
	"Burning Torch":"Use to put out the flame. Aim at a wall to mount.",
	"Solar Torch":"Use to switch the light. Direct sunlight charges its solar panel.",
	"Binoculars":"Use to look farther. Use again to lower.",
	"Walkie Talkie":"Use to send a signal. Switch off to save power; sunlight charges it.",
	"Axe":"Aim at a tree and use to chop.",
	"Pickaxe":"Aim at a rock or metal deposit and use to mine.",
	"Shovel":"Aim at soil or sand to dig. Aim at a mature root crop to harvest.",
	"Paddle":"Use while aboard the raft to paddle.",
	"Anchor":"Use aboard the raft to lower or raise the anchor.",
	"Fishing Rod":"Aim at open water and use to cast. Pull when a fish bites.",
	"Spear":"Aim at a fish or creature and use to hunt.",
	"Bow":"Hold to draw, aim, then release to shoot.",
	"Can":"Aim at reachable ocean water to fill. Boil before drinking.",
	"Tumbler":"Aim at reachable ocean water to fill. Boil at a cooking fire.",
	"Medkit":"Use while standing still to heal.",
	"Bandage":"Use to heal an injury.",
	"Diving Tank":"Use to equip. Watch your air timer; refill with a pump at the surface.",
	"Life Vest":"Use to equip before swimming.",
	"Water":"Aim at a planted pot to water it, or use to drink.",
	"Sail Kit":"Use aboard the raft to install a sail.",
	"Motor Kit":"Use aboard the raft to install a motor.",
	"WindGenerator":"Aim at a supported deck to place your wind generator.",
	"Wire":"Aim at a generator and use to start a cable. Aim at a light, pump or radio and use to connect it.",
	"ElectricLamp":"Use to switch the LED. Mount/Place fits it to a wall or deck. Replace its battery when empty.",
	"Repair Kit":"Aim at damaged equipment and choose Repair to see the required parts."
}

static func for_item(item: String) -> String:
	if item.is_empty():return ""
	if TIPS.has(item):return str(TIPS[item])
	if not preload("res://scripts/garden_items.gd").box_crop(item).is_empty():return "Use to open the rare garden box. Its seeds, fruit and parts are saved in your bag."
	if not preload("res://scripts/garden_items.gd").seed_crop(item,true).is_empty():return "Aim at an empty wooden seed tray to dry these seeds for two minutes."
	if item in preload("res://scripts/garden_items.gd").CROPS:return "Use to eat or cut and save seeds. Dry the seeds on a tray; cook the sliced food."
	if PlantDB.crop_for_item(item)!="":
		return "Aim at empty soil or a filled pot to plant. Use to eat." if FOOD.edible(item) else "Aim at empty soil or a filled pot to plant."
	if FOOD.edible(item):return "Use to drink." if FOOD.is_drink(item) else "Use to eat. Cook ingredients at a cooking fire."
	return "Open your bag and Craft to see recipes using %s."%item
