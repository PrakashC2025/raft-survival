extends "res://scripts/main_menu.gd"
## Controlled pending/completed loader for menu_loading_smoke.gd only.

var entered: Array[String] = []

func _request_game_load() -> void:
	_load_requested = true

func _poll_game_load() -> void:
	pass

func _swap_scene(_scene: PackedScene) -> void:
	entered.append(_selected_id)
	_waiting_to_enter = false
	_busy = false
