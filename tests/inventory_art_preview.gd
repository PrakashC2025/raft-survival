extends SceneTree
## Isolated renderer preview of the actual HUD, without loading island meshes.
func _initialize() -> void:
	call_deferred("_run")

func _capture(label: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/inventory-art-" + label + ".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var inventory := root.get_node("Inventory")
	inventory.call("new_game_reset", false)
	for index in range(30):
		inventory.slots[index] = {}
	var art := load("res://scripts/item_art.gd")
	var names: Array = art.REGIONS.keys()
	for index in range(29):
		inventory.call("place_at", index, names[index], 2000 if index < 6 else 4)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.07, 0.12, 0.13)
	backdrop.size = Vector2(1280, 720)
	root.add_child(backdrop)
	var hud := (load("res://scripts/survival_hud.gd") as Script).new() as Control
	root.add_child(hud)
	hud.set_process(false)
	hud.visible = true
	hud.set("_bag_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await _capture("bag")
	hud.set("_bag_open", false)
	hud.set("_craft_open", true)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await _capture("craft")
	hud.set("_craft_open", false)
	hud.call("_compute_layout")
	hud.queue_redraw()
	await _capture("hotbar")
	quit()
