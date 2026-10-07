extends StaticBody3D
## Portable torch transferred to a wall; fuel and lit state survive Continue.
var fuel := 0.0
var burning := false
var _visual: Node3D
var _light: OmniLight3D
var _tick := 0.0
var _preview := false

func _ready() -> void:
	_preview = get_parent() != null and get_parent().name == "BuildPreviewRoot"
	_visual = preload("res://scripts/torch_visual.gd").new()
	add_child(_visual)
	var bracket := MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.07, 0.09, 0.27)
	bracket.mesh = beam
	bracket.position = Vector3(0,-0.15,-0.10)
	bracket.material_override = preload("res://scripts/object_materials.gd").make(1,Color(0.12,0.11,0.095),0.85)
	add_child(bracket)
	_light = OmniLight3D.new()
	_light.position.y = 0.46
	_light.light_color = Color(1.0,0.56,0.23)
	_light.light_energy = 1.8
	_light.omni_range = 5.5
	# Mobile: avoid a cubemap shadow pass for every additional torch.
	_light.shadow_enabled = false
	add_child(_light)
	_update_flame()
	if not _preview: add_to_group("wall_torch")

func _process(delta: float) -> void:
	if _preview: return
	_tick += delta
	if burning:
		fuel = maxf(0.0,fuel-delta)
		if fuel <= 0.0: burning = false
	if _tick >= 0.4:
		_tick = 0.0
		var rain := get_tree().get_first_node_in_group("rain_system")
		if burning and rain != null and bool(rain.call("is_raining")):
			var start := to_global(Vector3(0,0.58,0))
			var ray := PhysicsRayQueryParameters3D.create(start,start+Vector3.UP*8.0,1,[get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): burning = false
	_update_flame()

func _update_flame() -> void:
	if _visual != null: _visual.call("set_burning",burning and fuel > 0.0 and not _preview)
	if _light != null: _light.visible = burning and fuel > 0.0 and not _preview

func interact_survival(player: Node) -> void:
	if _preview: return
	var progress := player.get_node("SurvivalProgression")
	var selected := str(player.get("active_item"))
	if selected == "Wood":
		if fuel > 720.0 or not Inventory.has("Wood",1): return
		Inventory.remove("Wood",1)
		fuel = minf(900.0,fuel+180.0)
		player.call("_hud_toast","TORCH FUEL ADDED · LIGHT WITH A BURNING TORCH")
	elif selected == "Torch" and not burning and float(progress.get("torch_fuel")) > 0.0:
		burning = fuel > 0.0
		player.call("_hud_toast","WALL TORCH LIT" if burning else "ADD WOOD FIRST")
	else:
		if burning and float(progress.get("torch_fuel")) > 0.0:
			player.call("_hud_toast","PUT OUT YOUR HELD TORCH BEFORE TAKING ANOTHER")
			return
		if not Inventory.can_store_rewards({"Torch":1}):
			player.call("_hud_toast","BAG FULL · TORCH STAYS ON WALL")
			return
		Inventory.add("Torch",1)
		if burning: progress.set("torch_fuel",fuel)
		fuel = 0.0
		burning = false
		get_parent().remove_child(self)
		queue_free()
		player.call("_hud_toast","TORCH TAKEN")
	_update_flame()
	player.call("_queue_save")

func save_survival_state() -> Dictionary:
	return {"fuel":fuel,"burning":burning}

func restore_survival_state(data: Dictionary) -> void:
	fuel = clampf(float(data.get("fuel",0.0)),0.0,900.0)
	burning = bool(data.get("burning",false)) and fuel > 0.0
	_update_flame()
