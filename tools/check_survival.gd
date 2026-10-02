extends SceneTree
func _initialize() -> void:
	for path in ["res://scripts/survival_director.gd", "res://scripts/survival_wildlife.gd", "res://scripts/survival_arrow.gd", "res://scripts/player.gd", "res://scripts/survival_audio.gd", "res://scripts/survival_world.gd", "res://scripts/survival_intro.gd", "res://scripts/survival_bonfire.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			push_error("INVALID: " + path)
			quit(1)
			return
	print("SURVIVAL SCRIPTS VALID")
	quit()


