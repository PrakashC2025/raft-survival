extends Node
signal stat_changed(stat_name: String, value: float)
signal player_died

const MAX_VALUE := 100.0
@export var hunger_drain_rate: float = 0.06
@export var thirst_drain_rate: float = 0.09
## The survival director enables drain during gameplay and disables it in menus.
@export var enabled := false

var health: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0

func _process(delta: float) -> void:
	if not enabled:
		return
	hunger = clampf(hunger - hunger_drain_rate * delta, 0.0, MAX_VALUE)
	thirst = clampf(thirst - thirst_drain_rate * delta, 0.0, MAX_VALUE)
	stat_changed.emit("hunger", hunger)
	stat_changed.emit("thirst", thirst)
	if hunger <= 0.0 or thirst <= 0.0:
		change_health(-2.0 * delta)

func change_health(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_VALUE)
	stat_changed.emit("health", health)
	if health <= 0.0:
		player_died.emit()

func eat(food_value: float) -> void:
	hunger = clampf(hunger + food_value, 0.0, MAX_VALUE)

func drink(thirst_value: float, health_bonus: float = 0.0) -> void:
	thirst = clampf(thirst + thirst_value, 0.0, MAX_VALUE)
	if health_bonus != 0.0:
		change_health(health_bonus)

