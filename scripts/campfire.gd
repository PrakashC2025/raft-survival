extends StaticBody3D
const SURFACES := preload("res://scripts/object_materials.gd")
const FLAME: Shader = preload("res://shaders/campfire.gdshader")
const COOKED := {"Fish": "Cooked Fish", "Raw Bird": "Roast Bird", "Potato": "Baked Potato"}
var fuel := 180.0
var burning := true
var cook_remaining := 0.0
var cook_item := ""
var _flames: Node3D
var _light: OmniLight3D
var _preview := false
var _seconds := 0.0

func _ready() -> void:
	_preview = get_parent() != null and get_parent().name == "BuildPreviewRoot"
	if not _preview:
		add_to_group("campfire")
		add_to_group("build_surface")
	var rock_mat := SURFACES.make(SURFACES.Kind.STONE, Color(0.27, 0.29, 0.28))
	for index in range(9):
		var stone := SphereMesh.new()
		stone.radius = 0.13
		stone.height = 0.20
		stone.radial_segments = 16
		stone.rings = 8
		var visual := MeshInstance3D.new()
		visual.mesh = stone
		visual.material_override = rock_mat
		visual.position = Vector3(cos(index * TAU / 9) * 0.38, 0.08, sin(index * TAU / 9) * 0.38)
		visual.scale = Vector3(1.1, 0.9, 0.8)
		add_child(visual)
	for index in range(3):
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.045
		log_mesh.bottom_radius = 0.06
		log_mesh.height = 0.58
		log_mesh.radial_segments = 12
		var log_visual := MeshInstance3D.new()
		log_visual.mesh = log_mesh
		log_visual.material_override = SURFACES.make(SURFACES.Kind.WOOD, Color(0.20, 0.12, 0.06))
		log_visual.rotation = Vector3(PI / 2.0, float(index) * PI / 3.0, 0)
		log_visual.position.y = 0.14 + float(index) * 0.022
		add_child(log_visual)
	_flames = Node3D.new()
	_flames.name = "Flames"
	add_child(_flames)
	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = FLAME
	for index in range(3):
		var quad := QuadMesh.new()
		quad.size = Vector2(0.48, 0.65)
		var visual := MeshInstance3D.new()
		visual.mesh = quad
		visual.material_override = flame_mat
		visual.rotation.y = float(index) * PI / 3.0
		visual.position.y = 0.47
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.add_child(visual)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.48, 0.13)
	_light.omni_range = 5.0
	_light.light_energy = 1.3
	_light.shadow_enabled = false
	add_child(_light)
	_flames.visible = not _preview
	_light.visible = not _preview

func exposed_to_rain() -> bool:
	var rain := get_tree().get_first_node_in_group("rain_system")
	if rain == null or not rain.call("is_raining"):
		return false
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func interact_survival(player: Node) -> void:
	if _preview:
		return
	var item := str(player.get("active_item"))
	if exposed_to_rain():
		player.call("_hud_toast", "FIRE IS WET · BUILD A ROOF")
	elif not burning or item == "Wood":
		if Inventory.has("Wood", 1):
			Inventory.remove("Wood", 1)
			fuel = minf(fuel + 90.0, 900.0)
			burning = true
			player.call("_hud_toast", "FIRE FUELLED · +90 SECONDS")
	elif cook_remaining > 0.0:
		player.call("_hud_toast", "COOKING · %d SECONDS" % ceili(cook_remaining))
	elif COOKED.has(item) and Inventory.has(item, 1):
		cook_item = item
		cook_remaining = 12.0
		player.call("_hud_toast", "COOKING " + item.to_upper())
	else:
		player.call("_hud_toast", "SELECT FISH, BIRD OR POTATO TO COOK · WOOD TO REFUEL")
	player.call("_queue_save")

func _process(delta: float) -> void:
	if _preview:
		return
	_seconds += delta
	if _seconds >= 1.0:
		_seconds = 0.0
		if exposed_to_rain():
			burning = false
	if burning and fuel > 0.0:
		fuel = maxf(0, fuel - delta)
		if cook_remaining > 0.0:
			cook_remaining = maxf(0, cook_remaining - delta)
			if cook_remaining <= 0.0:
				if not Inventory.has(cook_item, 1):
					cook_item = ""
				elif Inventory.try_exchange({cook_item: 1}, {COOKED[cook_item]: 1}):
					var player := get_tree().get_first_node_in_group("player")
					if player != null:
						player.call("_hud_toast", "MEAL COOKED · " + str(COOKED[cook_item]).to_upper())
					cook_item = ""
				else:
					cook_remaining = 1.0 # full bag: retry without losing the raw food
	if fuel <= 0.0:
		burning = false
	_flames.visible = burning
	_light.visible = burning
	_light.light_energy = 1.15 + sin(Time.get_ticks_msec() * 0.008) * 0.13

func save_survival_state() -> Dictionary:
	return {"fuel": fuel, "burning": burning, "cook": cook_remaining, "item": cook_item}

func restore_survival_state(data: Dictionary) -> void:
	fuel = clampf(float(data.get("fuel", 180)), 0, 900)
	burning = bool(data.get("burning", true)) and fuel > 0
	cook_item = str(data.get("item", ""))
	cook_remaining = clampf(float(data.get("cook", 0)), 0, 12) if COOKED.has(cook_item) else 0.0
