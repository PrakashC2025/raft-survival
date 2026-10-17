extends RefCounted
## Shared player-facing names and practical instructions; inventory IDs stay unchanged.
const FOOD := preload("res://scripts/food_rules.gd")
const HINTS := preload("res://scripts/equipment_hints.gd")
const NAMES := {"Rope Gun":"Rope Launcher", "Torch":"Fire Torch", "Diving Tank":"Air Tank",
	"PlanterPot":"Plant Pot", "PlanterBox":"Plant Bed", "TreePot":"Tree Pot", "RainCollector":"Rain Collector",
	"SandFilter":"Sand Filter", "HalfWall":"Half Wall", "CargoCrate":"Cargo Crate", "WallTorch":"Wall Torch",
	"WaterPurifier":"Water Purifier", "WindGenerator":"Wind Generator", "ElectricLamp":"LED Lamp",
	"ElectricPurifier":"Electric Purifier", "RescueRadio":"Rescue Radio", "SeedDryingTray":"Seed Drying Tray",
	"BoatWorkshop":"Boat Workshop", "StorageBox":"Storage Box", "CookingSetup":"Cooking Setup", "FishingNet":"Fishing Net"}
const PURPOSES := {
	"Wood":"Build your raft, make tools, or fuel a cooking fire.",
	"Rope":"Tie tools and structures together. ROPE on the right equips your permanent launcher.",
	"Plastic":"Make water containers, fishing equipment and floating gear.",
	"Metal":"Craft screws, tools, cooking foil and machinery.",
	"Stone":"Make a spear, build a fire, or craft an anchor.",
	"Soil":"Fill a plant pot or bed before planting food.",
	"Sand":"Fill planters or combine with sponge to make a sand filter.",
	"Screw":"Fasten storage boxes, boats and machines. Craft from Metal.",
	"Battery":"Power portable electronics or build a wind generator.",
	"Motor":"A component for your wind generator. Craft it from Metal, Wire and Screw.",
	"Barrel":"Use this wooden barrel to build a rain collector.",
	"Arrow":"Ammunition for a Bow. Hold the Bow action, aim, then release.",
	"Foundation":"Extend your raft from a supported deck edge. Green preview means it can be placed.",
	"Wall":"Build a sheltered room on a supported foundation or floor.",
	"Roof":"Cover your room to keep rain off your cooking fire and seed tray.",
	"Stairs":"Connect a supported deck to the next floor. Keep the landing clear.",
	"Door":"Close an entrance to shelter your camp. Aim at the fitted door to open it.",
	"Window":"Fit a timber wall with an opening to see outside your camp.",
	"HalfWall":"Add a low timber wall around a supported deck.",
	"CargoCrate":"Build a timber crate on your raft as a camp furnishing.",
	"WallTorch":"Mount a fire torch for light near your camp. Keep it sheltered and burning.",
	"Bonfire":"Cook raw food and boil water. Add wood, light it, then open the cooking menu.",
	"CookingSetup":"Prepare meals, boil water and wrap cooked food for your next trip.",
	"WaterPurifier":"Place on your raft to turn ocean water into safe drinking water.",
	"RainCollector":"Collect rain in a barrel, then filter or boil it before drinking.",
	"SandFilter":"Filter collected water using sand and sponge.",
	"ElectricPurifier":"Connect wind power to make safe drinking water.",
	"RescueRadio":"Connect power and transmit an SOS to complete your rescue mission.",
	"BoatWorkshop":"Place on your raft, assemble the boat, then launch it into clear water.",
	"StorageBox":"Keep spare supplies in a box. Aim at the placed box to open it.",
	"FishingNet":"Place at a clear raft edge. Return later to collect fish.",
	"SeedDryingTray":"Dry wet fruit seeds for two minutes. Keep the tray sheltered from rain.",
	"PlanterPot":"Place on a deck or roof, fill with soil, then plant a root crop.",
	"PlanterBox":"Place a garden bed, fill with soil, then plant and water crops.",
	"TreePot":"Place a large pot for a fruit tree on your deck or roof."}

static func label(item: String) -> String:
	return str(NAMES.get(item,item))

static func category(item: String) -> String:
	if item in ["PlanterPot","PlanterBox","TreePot","SeedDryingTray"]:return "Garden"
	if FOOD.edible(item) or item in ["Can","Tumbler","Cooking Foil","Bandage","Medkit","Life Vest","Diving Tank"]:return "Survival"
	if Inventory.RECIPES.has(item) or item in ["Sail Kit","Motor Kit","Rowboat Kit","Paddle","Anchor"]:return "Camp & travel"
	if item in ["Axe","Pickaxe","Shovel","Spear","Bow","Arrow","Fishing Rod","Torch","Burning Torch","Solar Torch","Binoculars","Walkie Talkie","Rope Gun","Repair Kit"]:return "Tools"
	if PlantDB.crop_for_item(item)!="" or item.contains("Seed"):return "Garden"
	return "Materials"

static func purpose(item: String) -> String:
	if PURPOSES.has(item):return str(PURPOSES[item])
	return HINTS.for_item(item)

static func nutrition(item: String) -> String:
	var effects:=FOOD.effects(item)
	if effects.is_empty():return ""
	var parts:=PackedStringArray()
	for index in 3:
		var amount:=int(effects[index])
		if amount!=0:parts.append("%s %+d"%[["Food","Water","Health"][index],amount])
	return "  ·  ".join(parts)

static func quick_action(item: String) -> String:
	if item in ["Rope","Rope Gun"]:return "On your raft: hold CAST, aim, release · RETURN recalls"
	if item=="Spear":return "Tap to stab · Hold, aim, release to throw"
	if item=="Bow":return "Hold to draw · Aim and release to shoot"
	if item=="Fishing Rod":return "Aim down at water · FISH · Tap TAKE FISH after reeling"
	if item=="Axe":return "Aim at a tree · Use to chop"
	if item=="Pickaxe":return "Aim at rock or metal · Use to mine"
	if item=="Shovel":return "Aim at soil or sand · Use to dig"
	if item in ["Can","Tumbler"]:return "Aim at ocean water to fill · Boil at a fire"
	if FOOD.edible(item):
		var effects:=FOOD.effects(item)
		if int(effects[2])<0:return "Cook or boil first · Using this now costs health"
		return "Use to drink" if FOOD.is_drink(item) else "Use to eat · "+nutrition(item)
	if PlantDB.crop_for_item(item)!="":return "Aim at empty soil · Use to plant"
	if item in ["Bandage","Medkit"]:return "Use to heal · Stand still until finished"
	if item=="Diving Tank":return "Use to equip · Refill at the surface"
	if item=="Life Vest":return "Use to equip before swimming"
	return purpose(item)
