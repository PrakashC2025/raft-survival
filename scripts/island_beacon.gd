extends Node3D
## Navigation anchor only. The HUD/map can still locate the island without
## an artificial pillar, glowing orb or coloured light in the landscape.
@export var beacon_height := 14.0
@export var beacon_color := Color(1.0, 0.62, 0.25)
@export var pulse_speed := 0.55
@export var light_range := 32.0

func _ready() -> void:
	add_to_group("island_beacon")
	set_process(false)