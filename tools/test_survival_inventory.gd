extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var inventory := root.get_node("Inventory")
	inventory.slots.clear()
	inventory._ensure_slots()
	inventory.add("Wood", 5)
	assert(inventory.try_exchange({"Wood": 3}, {"Spear": 1}))
	assert(inventory.total("Wood") == 2 and inventory.total("Spear") == 1)
	var before: Array = inventory.slots.duplicate(true)
	assert(not inventory.try_exchange({"Wood": 3}, {"Spear": 1}))
	assert(inventory.slots == before)
	for i in range(inventory.SLOT_COUNT):
		inventory.slots[i] = {"item": "Stone", "count": 99}
	inventory.slots[0] = {"item": "Wood", "count": 99}
	before = inventory.slots.duplicate(true)
	assert(not inventory.try_exchange({"Wood": 1}, {"Bow": 1}))
	assert(inventory.slots == before)
	assert(inventory.try_exchange({"Wood": 99}, {"Bow": 1}))
	assert(inventory.total("Bow") == 1)
	print("PASS: exchange success, insufficient resources, full bag rollback, freed slot reuse")
	quit()
