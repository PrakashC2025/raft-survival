extends Node

signal stat_changed(stat_name: String, value: float)
signal player_died
signal stat_delta(stat_name: String, amount: float)

const MAX_VALUE := 100.0

@export_range(0.0, 1.0, 0.01) var hunger_drain_rate: float = 0.10
@export_range(0.0, 1.0, 0.01) var thirst_drain_rate: float = 0.16
@export var enabled := true

var health: float = MAX_VALUE
var hunger: float = MAX_VALUE
var thirst: float = MAX_VALUE
var _dead := false
var damage_revision := 0


func _process(delta: float) -> void:
	if not enabled or _dead:
		return
	# The autoload also exists in the title screen; only consume supplies while
	# the actual survival world is active.
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/main.tscn":
		return
	var previous_hunger := hunger
	var previous_thirst := thirst
	var player:=get_tree().get_first_node_in_group("player") as CharacterBody3D
	var effort:=1.0
	if player!=null:
		if player.get("is_swimming")==true:effort=2.0
		elif Vector2(player.velocity.x,player.velocity.z).length()>3.4:effort=1.6
	hunger = clampf(hunger - hunger_drain_rate * delta * effort, 0.0, MAX_VALUE)
	thirst = clampf(thirst - thirst_drain_rate * delta * effort, 0.0, MAX_VALUE)
	var previous_health:=health
	health=clampf(health-.003*delta*effort,0,MAX_VALUE)
	if int(previous_health)!=int(health):stat_changed.emit("health",health)
	if int(previous_hunger) != int(hunger):
		stat_changed.emit("hunger", hunger)
	if int(previous_thirst) != int(thirst):
		stat_changed.emit("thirst", thirst)
	if hunger <= 0.0 or thirst <= 0.0:
		change_health(-1.5 * delta)
	if health<=0.0 and not _dead:
		_dead=true
		player_died.emit()


func change_health(amount: float) -> void:
	if _dead or not is_finite(amount) or is_zero_approx(amount):
		return
	var before:=health
	health = clampf(health + amount, 0.0, MAX_VALUE)
	if amount<0:damage_revision+=1
	if absf(health-before)>=.5:stat_delta.emit("health",health-before)
	stat_changed.emit("health", health)
	if health <= 0.0:
		_dead = true
		player_died.emit()


func eat(food_value: float) -> void:
	if _dead or not is_finite(food_value):
		return
	var before:=hunger
	hunger = clampf(hunger + food_value, 0.0, MAX_VALUE)
	if absf(hunger-before)>=.5:stat_delta.emit("hunger",hunger-before)
	stat_changed.emit("hunger", hunger)


func drink(thirst_value: float, health_bonus: float = 0.0) -> void:
	if _dead or not is_finite(thirst_value):
		return
	var before:=thirst
	thirst = clampf(thirst + thirst_value, 0.0, MAX_VALUE)
	if absf(thirst-before)>=.5:stat_delta.emit("thirst",thirst-before)
	stat_changed.emit("thirst", thirst)
	if health_bonus != 0.0:
		change_health(health_bonus)


func reset() -> void:
	health = MAX_VALUE
	hunger = MAX_VALUE
	thirst = MAX_VALUE
	_dead = false
	stat_changed.emit("health", health)
	stat_changed.emit("hunger", hunger)
	stat_changed.emit("thirst", thirst)


func load_state(data: Dictionary) -> void:
	if not data.has("health") and not data.has("hunger") and not data.has("thirst"):
		reset()
		return
	health = _loaded_value(data.get("health", MAX_VALUE))
	hunger = _loaded_value(data.get("hunger", MAX_VALUE))
	thirst = _loaded_value(data.get("thirst", MAX_VALUE))
	_dead = health <= 0.0
	stat_changed.emit("health", health)
	stat_changed.emit("hunger", hunger)
	stat_changed.emit("thirst", thirst)


func save_state() -> Dictionary:
	return {"health": health, "hunger": hunger, "thirst": thirst}

func _loaded_value(value: Variant) -> float:
	return clampf(float(value),0,MAX_VALUE) if (value is int or value is float) and is_finite(float(value)) else MAX_VALUE
