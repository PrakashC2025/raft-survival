extends SceneTree
## Headless shader sanity check: loads the terrain shaders exactly like the
## game does and FAILS (exit 1) if either fails to compile.
## Run: godot --headless --path . --script tools/check_mobile_shader.gd

func _initialize() -> void:
	var fail := false
	for p in [
		"res://shaders/terrain_sand.gdshader",
		"res://shaders/terrain_sand_mobile.gdshader",
	]:
		if not ResourceLoader.exists(p):
			print("SHADER_FAIL missing: %s" % p)
			fail = true
			continue
		var s: Resource = null
		# load() with a parse/compile error can push a script error and abort
		# this function BEFORE quit() runs — the SceneTree then idles forever
		# and the headless run hangs. Catch it so we ALWAYS reach quit().
		var ok := true
		var res: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			ok = false
		elif not (res is Shader):
			ok = false
		else:
			s = res
		if not ok:
			print("SHADER_FAIL failed to load/compile: %s" % p)
			fail = true
			continue
		print("SHADER_OK %s (%d uniforms)" % [p, (s as Shader).get_shader_uniform_list().size()])
	print("SHADER_CHECK %s" % ("FAILED" if fail else "PASSED"))
	quit(1 if fail else 0)
