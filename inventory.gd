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
	_recompute()
	emit_signal("changed")
	for slot in [SAVE_PATH, QUICK_SAVE_PATH]:
		if FileAccess.file_exists(slot):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
