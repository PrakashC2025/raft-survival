extends Node
## Register as an Autoload: Project Settings -> Globals -> Autoload
## Path: res://inventory.gd   Node Name: Inventory
##
## AUTHORITATIVE inventory: one array of 30 slots. The first six (0..5) are
## the hotbar (what the bottom bar shows in NORMAL mode); 6..29 is the bag.
## New pickups prefer the bag first so the hotbar stays the player's own
## arrangement (a fresh game starts with Rope in slot 0, per spec).
##
## `items` is a legacy convenience dict of TOTALS kept in sync for older code
## (crafting checks, debug HUD, resource pills). Everything mutates through
## the slot API below so the UI is never out of sync.

const SLOT_COUNT := 30
const HOTBAR_COUNT := 6
# Temporary default testing supplies. Set false to restore survival starts.
const TESTING_RESOURCES_ENABLED := true
const TESTING_RESOURCE_AMOUNT := 2000
const TESTING_RESOURCE_ITEMS := ["Wood", "Rope", "Plastic", "Barrel", "Stone", "Metal"]
const MAX_STACK := 2000 if TESTING_RESOURCES_ENABLED else 99
const BAG_START := HOTBAR_COUNT  # first bag-only slot index

signal changed
signal bag_full(amount: int)  # amount that could not be stored anywhere
signal pickup_received(item: String, amount: int)

const SAVE_PATH := "user://raft_save.json"        # autosave (written on change/quit)
const QUICK_SAVE_PATH := "user://raft_quicksave.json"  # manual quick-save slot
const SAVE_VERSION := 1
const SAVE_STORAGE := preload("res://scripts/save_storage.gd")
var last_save_error := ""
signal save_failed(message: String)

var slots: Array = []          # SLOT_COUNT entries: {} (empty) or {"item": String, "count": int}
var items := {"Wood": 0, "Rope": 0, "Plastic": 0, "Barrel": 0, "Stone": 0, "Metal": 0}
## Meta loaded by load_game() (active hotbar slot, day time, ...) so the game
## scene can restore state after a Continue — the menu applies it.
var loaded_meta: Dictionary = {}
## One-time island pickups are stored separately from inventory so a Continue
## cannot respawn the same resource pile every time the world is reloaded.
var collected_island_pickups: Dictionary = {}

# Test/debug toggle. When true, crafting never consumes resources (handy for
# trying out the building system). Flip it with the debug key in Player.
var infinite: bool = false
var testing_resources_granted: bool = false
var testing_soil_granted: bool = false
const TESTING_SOIL_REVISION := 2
var testing_soil_revision := 0

# What each craftable/placeable thing costs.
const RECIPES := {
	"SeedDryingTray":{"Wood":3,"Rope":1},
	"WallTorch": {"Wood": 2, "Rope": 1},
	"StorageBox": {"Wood":6,"Rope":2,"Metal":1},
	"CookingSetup": {"Wood":8,"Stone":4,"Metal":2},
	"HalfWall": {"Wood": 4, "Rope": 1},
	"CargoCrate": {"Wood": 6, "Rope": 2, "Metal": 1},
	"Foundation":      {"Wood": 5},
	"Wall":            {"Wood": 8, "Rope": 1},
	"Roof":            {"Wood": 8, "Rope": 1},
	"Stairs":          {"Wood": 6, "Rope": 1},
	"Door":            {"Wood": 4, "Rope": 1},
	"Window":          {"Wood": 3, "Plastic": 1},
	"Bonfire":         {"Wood": 8, "Stone": 4},
	"RainCollector":   {"Wood": 6, "Barrel": 1, "Rope": 2},
	"Raft Extension":  {"Wood": 10, "Plastic": 2},
	"PlanterPot":      {"Wood": 4, "Soil": 2},
	"PlanterBox":      {"Wood": 6, "Soil": 4},
	"TreePot":         {"Wood": 8, "Rope": 1, "Soil": 6},
	"SandFilter": {"Wood": 6, "Sand": 4, "Sponge": 2, "Plastic": 2},
	"WaterPurifier": {"Metal": 4, "Stone": 3, "Plastic": 2},
	"WindGenerator": {"Wood":8,"Metal":4,"Screw":4,"Wire":2,"Motor":1,"Battery":1},
	"FishingNet": {"Wood":4,"Rope":6,"Stone":2},
	"ElectricLamp": {"Metal": 2, "Plastic": 2},
	"ElectricPurifier": {"Metal": 8, "Plastic": 5, "Rope": 2},
	"RescueRadio": {"Metal": 10, "Plastic": 6, "Rope": 2},
}

## Portable survival and raft equipment. These recipes produce an inventory
## item; building recipes above are paid when their structure is placed.
const ITEM_RECIPES := {
	"Axe": {"Wood":3,"Metal":2,"Rope":1},
	"Pickaxe": {"Wood":3,"Metal":3,"Rope":1},
	"Shovel": {"Wood":2,"Metal":2,"Rope":1},
	"Paddle": {"Wood":4,"Plastic":2,"Rope":1},
	"Anchor": {"Metal":4,"Stone":4,"Rope":4},
	"Fishing Rod": {"Wood": 3, "Rope": 2, "Plastic": 1},
	"Barrel": {"Wood": 6, "Metal": 2, "Rope": 2},
	"Spear": {"Wood": 3, "Stone": 2, "Rope": 1},
	"Sail Kit": {"Wood": 8, "Rope": 4, "Plastic": 2},
	"Motor Kit": {"Wood": 10, "Rope": 2, "Plastic": 5, "Metal": 4},
	"Life Vest": {"Plastic": 5, "Rope": 2},
	"Bow": {"Wood": 5, "Rope": 3},
	"Arrow": {"Wood": 1, "Stone": 1},
	"Diving Tank": {"Plastic": 8, "Rope": 3, "Metal": 2},
	"Bandage": {"Rope": 2},
	"Torch": {"Wood": 2, "Rope": 1},
	"Solar Torch": {"Metal":2,"Plastic":2},
	"Binoculars": {"Metal":2,"Plastic":3},
	"Walkie Talkie": {"Metal":4,"Plastic":3,"Rope":1},
	"Battery": {"Metal":1,"Plastic":1},
	"Repair Kit": {"Metal":2,"Wood":1,"Rope":1},
	"Screw": {"Metal":1},
	"Wire": {"Metal":1,"Plastic":1},
	"Motor": {"Metal":3,"Wire":2,"Screw":2},
	"Medkit": {"Rope":4,"Plastic":2},
	"Can": {"Metal":1},
	"Tumbler": {"Metal":2},
}


func _ready() -> void:
	_ensure_slots()


func _ensure_slots() -> void:
	if slots.size() != SLOT_COUNT:
		slots.clear()
		for i in range(SLOT_COUNT):
			slots.append({})


## Grant test materials once per save, including an existing Continue save.
## Real crafting costs still apply; Continue does not refill spent materials.
func grant_testing_resources() -> void:
	if not TESTING_RESOURCES_ENABLED:
		return
	# Separate migration flag grants soil to existing saves without refilling wood etc.
	if testing_soil_revision < TESTING_SOIL_REVISION:
		var soil_needed := maxi(0,TESTING_RESOURCE_AMOUNT-total("Soil"))
		testing_soil_granted = soil_needed == 0 or add("Soil",soil_needed) == 0
		if testing_soil_granted: testing_soil_revision = TESTING_SOIL_REVISION
	if testing_resources_granted:return
	var complete := true
	for material in TESTING_RESOURCE_ITEMS:
		var needed: int = maxi(0, TESTING_RESOURCE_AMOUNT - total(material))
		if needed > 0 and add(material, needed) > 0:
			complete = false
	testing_resources_granted = complete


# ---------------------------------------------------------------
# Slot access helpers (UI + internal)
# ---------------------------------------------------------------
func slot_get(idx: int) -> Dictionary:
	if idx < 0 or idx >= slots.size():
		return {}
	return slots[idx]


func slot_empty(idx: int) -> bool:
	return idx < 0 or idx >= slots.size() or slots[idx].is_empty()


func slot_item(idx: int) -> String:
	var s: Dictionary = slot_get(idx)
	return str(s.get("item", "")) if not s.is_empty() else ""


func slot_count(idx: int) -> int:
	var s: Dictionary = slot_get(idx)
	return int(s.get("count", 0)) if not s.is_empty() else 0


func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true


func total_count() -> int:
	var t := 0
	for s in slots:
		if not s.is_empty():
			t += int(s.get("count", 0))
	return t


func canonical_item(item: String) -> String:
	var crop := item.trim_suffix(" Seed")
	return crop if crop in ["Potato","Coconut","Banana","Carrot","Tomato","Onion"] else item

func notify_pickup(item: String, amount: int) -> void:
	pickup_received.emit(canonical_item(item), amount)

func total(item: String) -> int:
	item = canonical_item(item)
	var t := 0
	for i in range(slots.size()):
		if not slot_empty(i) and slot_item(i) == item:
			t += slot_count(i)
	return t


## Place an item directly into a specific slot (used for the fresh-game Rope
## in slot 1). Overwrites nothing — only writes when the slot is empty.
func place_at(idx: int, item: String, count: int) -> bool:
	item = canonical_item(item)
	_ensure_slots()
	if idx < 0 or idx >= slots.size() or not slot_empty(idx) or count <= 0:
		return false
	slots[idx] = {"item": item, "count": int(count)}
	_recompute()
	emit_signal("changed")
	return true


## Move slot a -> slot b. Empty dest = move; same item = merge (remainder
## stays in a); different item = swap. Never duplicates or loses items.
func drop_into(from_idx: int, to_idx: int) -> void:
	_ensure_slots()
	if from_idx == to_idx or from_idx < 0 or from_idx >= slots.size() \
		or to_idx < 0 or to_idx >= slots.size() or slot_empty(from_idx):
		return
	var f: Dictionary = slots[from_idx]
	var t: Dictionary = slots[to_idx]
	if t.is_empty():
		slots[to_idx] = f
		slots[from_idx] = {}
	elif str(t.get("item", "")) == str(f.get("item", "")) and int(t.get("count", 0)) < MAX_STACK:
		var room: int = MAX_STACK - int(t.get("count", 0))
		var take: int = mini(int(f.get("count", 0)), room)
		t["count"] = int(t.get("count", 0)) + take
		f["count"] = int(f.get("count", 0)) - take
		if int(f.get("count", 0)) <= 0:
			slots[from_idx] = {}
	else:
		slots[to_idx] = f
		slots[from_idx] = t
	_recompute()
	emit_signal("changed")


func swap_slots(a: int, b: int) -> void:
	_ensure_slots()
	if a == b or a < 0 or a >= slots.size() or b < 0 or b >= slots.size():
		return
	var tmp: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	_recompute()
	emit_signal("changed")


# ---------------------------------------------------------------
# Legacy count API (used by debris, crafting, refunds, debug HUD)
# ---------------------------------------------------------------
## Add an item. Existing partial stacks are topped up first (bag stacks before
## hotbar stacks), then new stacks go into the bag, and only as a last resort
## into an empty hotbar slot. Whatever cannot be stored is reported via
## bag_full() and returned — nothing is ever silently deleted.
func add(item: String, amount: int = 1) -> int:
	item = canonical_item(item)
	_ensure_slots()
	if amount <= 0:
		return 0
	var remaining: int = amount
	# 1) Top up partial stacks of the same item anywhere (bag first).
	remaining = _fill_partial_stacks(item, remaining, BAG_START, SLOT_COUNT - 1)
	remaining = _fill_partial_stacks(item, remaining, 0, BAG_START - 1)
	# 2) New stacks into bag-only slots.
	remaining = _fill_empty_stacks(item, remaining, BAG_START, SLOT_COUNT - 1)
	# 3) Last resort: new stacks in free hotbar slots.
	remaining = _fill_empty_stacks(item, remaining, 0, BAG_START - 1)
	if remaining > 0:
		emit_signal("bag_full", remaining)
	_recompute()
	emit_signal("changed")
	return remaining


func _fill_partial_stacks(item: String, amount: int, from: int, to: int) -> int:
	var remaining: int = amount
	for i in range(from, to + 1):
		if remaining <= 0:
			break
		if slot_empty(i) or slot_item(i) != item:
			continue
		var room: int = MAX_STACK - slot_count(i)
		if room <= 0:
			continue
		var take: int = mini(remaining, room)
		slots[i]["count"] = slot_count(i) + take
		remaining -= take
	return remaining


func _fill_empty_stacks(item: String, amount: int, from: int, to: int) -> int:
	var remaining: int = amount
	for i in range(from, to + 1):
		if remaining <= 0:
			break
		if not slot_empty(i):
			continue
		var take: int = mini(remaining, MAX_STACK)
		slots[i] = {"item": item, "count": take}
		remaining -= take
	return remaining


## Remove `amount` of an item, consuming bag stacks before hotbar stacks.
func remove(item: String, amount: int) -> void:
	item = canonical_item(item)
	_ensure_slots()
	var remaining: int = amount
	for i in range(SLOT_COUNT - 1, -1, -1):
		if remaining <= 0:
			break
		if slot_empty(i) or slot_item(i) != item:
			continue
		var take: int = mini(remaining, slot_count(i))
		slots[i]["count"] = slot_count(i) - take
		if slot_count(i) <= 0:
			slots[i] = {}
		remaining -= take
	if remaining > 0:
		# Never let a total go negative (guards callers that forget has()).
		push_warning("[Inventory] remove(%s, %d) had only %d" % [item, amount, amount - remaining])
	_recompute()
	emit_signal("changed")


func has(item: String, amount: int) -> bool:
	return total(item) >= amount


func has_collected_island_pickup(pickup_id: String) -> bool:
	return pickup_id != "" and bool(collected_island_pickups.get(pickup_id, false))


func mark_island_pickup_collected(pickup_id: String) -> void:
	if pickup_id.is_empty() or has_collected_island_pickup(pickup_id):
		return
	collected_island_pickups[pickup_id] = true
	emit_signal("changed")


## The filter accepts a salvaged plastic can or a metal container.
func recipe_cost(recipe: String) -> Dictionary:
	if recipe in ["WindGenerator","ElectricLamp"] and has(recipe,1):return {recipe:1}
	var cost: Dictionary = RECIPES.get(recipe,{}).duplicate()
	if recipe=="SandFilter" and total("Plastic")<2 and total("Metal")>=2:
		cost.erase("Plastic")
		cost["Metal"]=2
	return cost

func can_afford(recipe: String) -> bool:
	# Recovered LED kits and old saved lamps remain placeable. New LEDs
	# wash up as salvage; their electronics are not manufactured from scraps.
	if recipe=="ElectricLamp" and not has(recipe,1):return false
	if not recipe_unlocked(recipe):
		return false
	if infinite:
		return true
	if not RECIPES.has(recipe):
		return false
	for item in recipe_cost(recipe):
		if total(item) < recipe_cost(recipe)[item]:
			return false
	return true


func craft(recipe: String) -> bool:
	if not RECIPES.has(recipe):
		return false
	# Re-check affordability here too — placement must never spend below zero.
	if not can_afford(recipe):
		return false
	if infinite:
		return true
	return try_exchange(recipe_cost(recipe),{})


func can_afford_item(item_name: String, quantity: int=1) -> bool:
	if not recipe_unlocked(item_name):
		return false
	if not ITEM_RECIPES.has(item_name):
		return false
	if infinite:
		return true
	for item in ITEM_RECIPES[item_name]:
		if total(item) < int(ITEM_RECIPES[item_name][item])*quantity:
			return false
	return true


func can_store(item_name: String, amount: int = 1) -> bool:
	_ensure_slots()
	var simulated := slots.duplicate(true)
	return _simulate_add(simulated, item_name, amount) == 0


## Tests whether the result fits after its recipe ingredients are consumed. This
## lets a full inventory craft a tool when the recipe itself frees a slot.
func can_store_craft_result(item_name: String, quantity: int=1) -> bool:
	if not ITEM_RECIPES.has(item_name):
		return false
	_ensure_slots()
	var simulated := slots.duplicate(true)
	if not infinite:
		for ingredient in ITEM_RECIPES[item_name]:
			var missing := _simulate_remove(simulated, str(ingredient), int(ITEM_RECIPES[item_name][ingredient])*quantity)
			if missing > 0:
				return false
	return _simulate_add(simulated, item_name, quantity) == 0


func can_craft_item(item_name: String, quantity: int=1) -> bool:
	return quantity>=1 and quantity<=99 and ITEM_RECIPES.has(item_name) and can_afford_item(item_name,quantity) \
			and can_store_craft_result(item_name,quantity)


## Tests several rewards together without mutating the live inventory.
func can_store_rewards(rewards: Dictionary) -> bool:
	_ensure_slots()
	var simulated := slots.duplicate(true)
	for item_name in rewards:
		if _simulate_add(simulated, str(item_name), maxi(0, int(rewards[item_name]))) > 0:
			return false
	return true


func _simulate_add(simulated: Array, item_name: String, amount: int) -> int:
	item_name = canonical_item(item_name)
	var remaining := maxi(0, amount)
	remaining = _simulate_fill_partial(simulated, item_name, remaining, BAG_START, SLOT_COUNT - 1)
	remaining = _simulate_fill_partial(simulated, item_name, remaining, 0, BAG_START - 1)
	remaining = _simulate_fill_empty(simulated, item_name, remaining, BAG_START, SLOT_COUNT - 1)
	remaining = _simulate_fill_empty(simulated, item_name, remaining, 0, BAG_START - 1)
	return remaining


func _simulate_fill_partial(simulated: Array, item_name: String, amount: int,
		from_slot: int, to_slot: int) -> int:
	var remaining := amount
	for i in range(from_slot, to_slot + 1):
		if remaining <= 0:
			break
		var entry: Dictionary = simulated[i]
		if entry.is_empty() or str(entry.get("item", "")) != item_name:
			continue
		var room := MAX_STACK - int(entry.get("count", 0))
		if room <= 0:
			continue
		var take := mini(remaining, room)
		entry["count"] = int(entry.get("count", 0)) + take
		simulated[i] = entry
		remaining -= take
	return remaining


func _simulate_fill_empty(simulated: Array, item_name: String, amount: int,
		from_slot: int, to_slot: int) -> int:
	var remaining := amount
	for i in range(from_slot, to_slot + 1):
		if remaining <= 0:
			break
		var entry: Dictionary = simulated[i]
		if not entry.is_empty():
			continue
		var take := mini(remaining, MAX_STACK)
		simulated[i] = {"item": item_name, "count": take}
		remaining -= take
	return remaining


func _simulate_remove(simulated: Array, item_name: String, amount: int) -> int:
	item_name = canonical_item(item_name)
	var remaining := maxi(0, amount)
	for i in range(simulated.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var entry: Dictionary = simulated[i]
		if entry.is_empty() or str(entry.get("item", "")) != item_name:
			continue
		var take := mini(remaining, int(entry.get("count", 0)))
		var left := int(entry.get("count", 0)) - take
		if left <= 0:
			simulated[i] = {}
		else:
			entry["count"] = left
			simulated[i] = entry
		remaining -= take
	return remaining


func craft_cost(item_name: String, quantity: int=1) -> Dictionary:
	var costs: Dictionary=ITEM_RECIPES.get(item_name,{}).duplicate()
	for ingredient in costs:costs[ingredient]=int(costs[ingredient])*quantity
	return costs

func craft_item(item_name: String, quantity: int=1) -> bool:
	if not can_craft_item(item_name,quantity):return false
	if not try_exchange({} if infinite else craft_cost(item_name,quantity),{item_name:quantity}):return false
	var progress:=get_tree().get_first_node_in_group("survival_progression")
	if progress!=null:progress.call("record","craft:"+item_name,quantity)
	return true

func recipe_unlocked(recipe: String) -> bool:
	if recipe in ["WindGenerator","ElectricLamp"] and has(recipe,1):return true
	var progress := get_tree().get_first_node_in_group("survival_progression")
	return progress == null or bool(progress.call("unlocked", recipe))

## Commit costs and rewards together; a full inventory never loses ingredients.
func can_exchange(costs: Dictionary, rewards: Dictionary) -> bool:
	_ensure_slots()
	var proposed:=slots.duplicate(true)
	for item in costs:
		if _simulate_remove(proposed,str(item),maxi(0,int(costs[item])))>0:return false
	for item in rewards:
		if _simulate_add(proposed,str(item),maxi(0,int(rewards[item])))>0:return false
	return true

func try_exchange(costs: Dictionary, rewards: Dictionary) -> bool:
	_ensure_slots()
	var proposed := slots.duplicate(true)
	for item in costs:
		if _simulate_remove(proposed, str(item), maxi(0, int(costs[item]))) > 0:
			return false
	for item in rewards:
		if _simulate_add(proposed, str(item), maxi(0, int(rewards[item]))) > 0:
			return false
	slots = proposed
	_recompute()
	changed.emit()
	return true


func _recompute() -> void:
	for k in items:
		items[k] = 0
	for i in range(slots.size()):
		if slot_empty(i):
			continue
		var item_name: String = slot_item(i)
		if not items.has(item_name):
			items[item_name] = 0
		items[item_name] = int(items[item_name]) + slot_count(i)


# ================================================================
# Save / Load — two slots under user://:
#   "main"  = autosave  (debounced on change + on quit) — Continue loads this
#   "quick" = manual quick-save snapshot (F5 on desktop, SAVE chip in the bag
#             panel on mobile) — the menu offers it as a second Continue option
# ================================================================
func _save_path_for(slot: String) -> String:
	return QUICK_SAVE_PATH if slot == "quick" else SAVE_PATH


func has_save(slot: String = "main") -> bool:
	return FileAccess.file_exists(_save_path_for(slot)) or FileAccess.file_exists(_save_path_for(slot) + ".bak")

func has_cost(cost: Dictionary) -> bool:
	for item in cost:
		if total(str(item)) < int(cost[item]): return false
	return true


func save_game(extra: Dictionary = {}, slot: String = "main") -> bool:
	_ensure_slots()
	var slot_data: Array = []
	for i in range(slots.size()):
		if slot_empty(i):
			slot_data.append([])
		else:
			slot_data.append([slot_item(i), slot_count(i)])
	var data := {
		"version": SAVE_VERSION,
		"testing_resources_granted": testing_resources_granted,
		"testing_soil_granted": testing_soil_granted,
		"testing_soil_revision": testing_soil_revision,
		"slots": slot_data,
		"saved_at": Time.get_unix_time_from_system(),
		"collected_island_pickups": collected_island_pickups.keys(),
	}
	for k in extra:
		data[str(k)] = extra[k]
	var ok := SAVE_STORAGE.write(_save_path_for(slot), data)
	last_save_error = SAVE_STORAGE.last_error
	if not ok:
		save_failed.emit(last_save_error)
	return ok


## Reads just the meta of a slot without touching the live inventory
## (used by the menu to label Continue buttons, e.g. "DAY 2 · 15:30").
func save_info(slot: String = "main") -> Dictionary:
	return SAVE_STORAGE.read(_save_path_for(slot))


## Loads a slot's save into the inventory (replacing current contents) and
## returns the meta it carried. Returns {} when there is no save.
func load_game(slot: String = "main") -> Dictionary:
	if not has_save(slot):
		return {}
	var data: Dictionary = SAVE_STORAGE.read(_save_path_for(slot))
	last_save_error = SAVE_STORAGE.last_error
	if data.is_empty():
		return {}
	# Only replace the live inventory after the complete file was validated.
	loaded_meta = {}
	collected_island_pickups.clear()
	testing_resources_granted = bool(data.get("testing_resources_granted", false))
	testing_soil_granted = bool(data.get("testing_soil_granted", false))
	testing_soil_revision = int(data.get("testing_soil_revision",0))
	var saved_pickups: Variant = data.get("collected_island_pickups", [])
	if saved_pickups is Array:
		for pickup_id in saved_pickups:
			collected_island_pickups[str(pickup_id)] = true
	elif saved_pickups is Dictionary:
		for pickup_id in saved_pickups:
			if bool(saved_pickups[pickup_id]):
				collected_island_pickups[str(pickup_id)] = true
	_ensure_slots()
	for i in range(slots.size()):
		slots[i] = {}
	var stored: Array = data.get("slots", [])
	for i in range(mini(stored.size(), SLOT_COUNT)):
		var entry = stored[i]
		if entry is Array and entry.size() >= 2 and entry[0] is String and entry[0] != "" and (entry[1] is int or entry[1] is float) and is_finite(float(entry[1])) and float(entry[1]) > 0:
			slots[i] = {"item": canonical_item(str(entry[0])), "count": clampi(int(entry[1]),1,MAX_STACK)}
	loaded_meta = data.duplicate()
	loaded_meta.erase("version")
	loaded_meta.erase("slots")
	loaded_meta.erase("saved_at")
	loaded_meta.erase("collected_island_pickups")
	_recompute()
	emit_signal("changed")
	return loaded_meta


## Wipe everything (used by "New Game"). Also removes BOTH save files so the
## next boot offers only New Game until something is collected/saved again.
func new_game_reset(clear_save_files: bool = true) -> void:
	_ensure_slots()
	testing_resources_granted = false
	testing_soil_granted = false
	testing_soil_revision = 0
	for i in range(slots.size()):
		slots[i] = {}
	loaded_meta = {}
	collected_island_pickups.clear()
	_recompute()
	emit_signal("changed")
	if not clear_save_files:
		return
	for slot in [SAVE_PATH, QUICK_SAVE_PATH]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(slot + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(slot + suffix))
