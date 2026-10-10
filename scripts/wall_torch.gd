extends StaticBody3D
## Portable torch transferred to a wall; fuel and lit state survive Continue.
var fuel := 0.0
var burning := false
var end_time := 0.0
const CYCLE := preload("res://scripts/torch_cycle.gd")
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
	_light.light_energy = 1.45
	_light.omni_range = 4.5
	_light.omni_attenuation = 2.0
	# Mobile: avoid a cubemap shadow pass for every additional torch.
	_light.shadow_enabled = false
	add_child(_light)
	_update_flame()
	if not _preview: add_to_group("wall_torch")

func _process(delta: float) -> void:
	if _preview: return
	_tick += delta
	if burning:
		var actor:=get_tree().get_first_node_in_group("player")
		if actor!=null:
			if end_time<=0:end_time=CYCLE.next_dawn(actor)
			fuel=CYCLE.seconds_left(actor,end_time)
		else:fuel=maxf(0.0,fuel-delta)
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
	if _light != null: _light.visible = burning and fuel > 0.0 and not _preview and get_meta("light_allowed",true)

func interact_survival(player: Node) -> void:
	if _preview: return
	var progress := player.get_node("SurvivalProgression")
	var selected := str(player.get("active_item"))
	if selected=="Stone":
		player.get_node("FireActions").start("snuff_fire" if burning else "ignite_fire",self);return
	if selected == "Wood":
		player.call("_hud_toast","TAKE THE TORCH TO A BONFIRE OR COOKING SETUP TO RELIGHT")
	else:
		if burning and float(progress.get("torch_fuel")) > 0.0:
			player.call("_hud_toast","PUT OUT YOUR HELD TORCH BEFORE TAKING ANOTHER")
			return
		var item:="Burning Torch" if burning else "Torch"
		if not Inventory.can_store_rewards({item:1}):
			player.call("_hud_toast","BAG FULL · TORCH STAYS ON WALL")
			return
		Inventory.add(item,1)
		player.call("play_action","grab",.8,global_position,item)
		if burning: progress.set("torch_fuel",fuel);progress.set("torch_end_time",end_time)
		player.get_node("SurvivalServices").equip_owned(item)
		fuel = 0.0
		burning = false
		get_parent().remove_child(self)
		queue_free()
		player.call("_hud_toast","TORCH TAKEN")
	_update_flame()
	player.call("_queue_save")

func save_survival_state() -> Dictionary:
	return {"fuel":fuel,"burning":burning,"end_time":end_time}

func exposed_to_rain() -> bool:
	var rain:=get_tree().get_first_node_in_group("rain_system")
	if rain==null or not rain.call("is_raining"):return false
	var at:=to_global(Vector3(0,.58,0))
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at,at+Vector3.UP*8,1,[get_rid()])).is_empty()
func extinguish() -> void:
	burning=false;_update_flame()
func interaction_caption() -> String:
	var player:=get_tree().get_first_node_in_group("player")
	if player!=null and player.active_item=="Stone":return "PUT OUT FIRE" if burning else "LIGHT FIRE"
	return "TAKE TORCH"

func restore_survival_state(data: Dictionary) -> void:
	fuel = clampf(float(data.get("fuel",0.0)),0.0,86400.0)
	end_time=clampf(float(data.get("end_time",0.0)),0.0,240000000.0)
	burning = bool(data.get("burning",false)) and fuel > 0.0
	_update_flame()
