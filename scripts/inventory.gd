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
const MAX_STACK := 99
const BAG_START := HOTBAR_COUNT  # first bag-only slot index

signal changed
signal bag_full(amount: int)  # amount that could not be stored anywhere

const SAVE_PATH := "user://raft_save.json"        # autosave (written on change/quit)
const QUICK_SAVE_PATH := "user://raft_quicksave.json"  # manual quick-save slot
const SAVE_VERSION := 1

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
	"PlanterPot":      {"Wood": 4},
	"PlanterBox":      {"Wood": 6},
	"TreePot":         {"Wood": 8, "Rope": 1},
}

## Portable survival and raft equipment. These recipes produce an inventory
## item; building recipes above are paid when their structure is placed.
const ITEM_RECIPES := {
	"Fishing Rod": {"Wood": 3, "Rope": 2, "Plastic": 1},
	"Spear": {"Wood": 3, "Stone": 2, "Rope": 1},
	"Sail Kit": {"Wood": 8, "Rope": 4, "Plastic": 2},
	"Motor Kit": {"Wood": 10, "Rope": 2, "Plastic": 5, "Metal": 4},
	"Life Vest": {"Plastic": 5, "Rope": 2},
}


func _ready() -> void:
	_ensure_slots()


func _ensure_slots() -> void:
	if slots.size() != SLOT_COUNT:
		slots.clear()
		for i in range(SLOT_COUNT):
			slots.append({})


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


func total(item: String) -> int:
	var t := 0
	for i in range(slots.size()):
		if not slot_empty(i) and slot_item(i) == item:
			t += slot_count(i)
	return t


## Place an item directly into a specific slot (used for the fresh-game Rope
## in slot 1). Overwrites nothing — only writes when the slot is empty.
func place_at(idx: int, item: String, count: int) -> bool:
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


func can_afford(recipe: String) -> bool:
	if infinite:
		return true
	if not RECIPES.has(recipe):
		return false
	for item in RECIPES[recipe]:
		if total(item) < RECIPES[recipe][item]:
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
	for item in RECIPES[recipe]:
		remove(item, RECIPES[recipe][item])
	return true


func can_afford_item(item_name: String) -> bool:
	if not ITEM_RECIPES.has(item_name):
		return false
	if infinite:
		return true
	for item in ITEM_RECIPES[item_name]:
		if total(item) < int(ITEM_RECIPES[item_name][item]):
			return false
	return true


func can_store(item_name: String, amount: int = 1) -> bool:
	_ensure_slots()
	var simulated := slots.duplicate(true)
	return _simulate_add(simulated, item_name, amount) == 0


## Tests whether the result fits after its recipe ingredients are consumed. This
## lets a full inventory craft a tool when the recipe itself frees a slot.
func can_store_craft_result(item_name: String) -> bool:
	if not ITEM_RECIPES.has(item_name):
		return false
	_ensure_slots()
	var simulated := slots.duplicate(true)
	if not infinite:
		for ingredient in ITEM_RECIPES[item_name]:
			var missing := _simulate_remove(simulated, str(ingredient), int(ITEM_RECIPES[item_name][ingredient]))
			if missing > 0:
				return false
	return _simulate_add(simulated, item_name, 1) == 0


func can_craft_item(item_name: String) -> bool:
	return ITEM_RECIPES.has(item_name) and can_afford_item(item_name) \
			and can_store_craft_result(item_name)


## Tests several rewards together without mutating the live inventory.
func can_store_rewards(rewards: Dictionary) -> bool:
	_ensure_slots()
	var simulated := slots.duplicate(true)
	for item_name in rewards:
		if _simulate_add(simulated, str(item_name), maxi(0, int(rewards[item_name]))) > 0:
			return false
	return true


func _simulate_add(simulated: Array, item_name: String, amount: int) -> int:
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


func craft_item(item_name: String) -> bool:
	if not ITEM_RECIPES.has(item_name) or not can_afford_item(item_name):
		return false
	# Never consume ingredients if the finished tool would be lost to a full bag.
	if not can_store_craft_result(item_name):
		emit_signal("bag_full", 1)
		return false
	if not infinite:
		for ingredient in ITEM_RECIPES[item_name]:
			remove(str(ingredient), int(ITEM_RECIPES[item_name][ingredient]))
	return add(item_name, 1) == 0


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
	return FileAccess.file_exists(_save_path_for(slot))


func save_game(extra: Dictionary = {}, slot: String = "main") -> void:
	_ensure_slots()
	var slot_data: Array = []
	for i in range(slots.size()):
		if slot_empty(i):
			slot_data.append([])
		else:
			slot_data.append([slot_item(i), slot_count(i)])
	var data := {
		"version": SAVE_VERSION,
		"slots": slot_data,
		"saved_at": Time.get_unix_time_from_system(),
		"collected_island_pickups": collected_island_pickups.keys(),
	}
	for k in extra:
		data[str(k)] = extra[k]
	var f := FileAccess.open(_save_path_for(slot), FileAccess.WRITE)
	if f == null:
		push_warning("[Inventory] Could not open save file for writing.")
		return
	f.store_string(JSON.stringify(data))
	f.close()


## Reads just the meta of a slot without touching the live inventory
## (used by the menu to label Continue buttons, e.g. "DAY 2 · 15:30").
func save_info(slot: String = "main") -> Dictionary:
	var path := _save_path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	return parsed


## Loads a slot's save into the inventory (replacing current contents) and
## returns the meta it carried. Returns {} when there is no save.
func load_game(slot: String = "main") -> Dictionary:
	loaded_meta = {}
	collected_island_pickups.clear()
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_save_path_for(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
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
		if entry is Array and entry.size() >= 2 and (str(entry[0]) != "") and int(entry[1]) > 0:
			slots[i] = {"item": str(entry[0]), "count": int(entry[1])}
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
func new_game_reset() -> void:
	_ensure_slots()
	for i in range(slots.size()):
		slots[i] = {}
	loaded_meta = {}
	collected_island_pickups.clear()
	_recompute()
	emit_signal("changed")
	for slot in [SAVE_PATH, QUICK_SAVE_PATH]:
		if FileAccess.file_exists(slot):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
