extends Node3D

@export_range(0, 8, 1) var shark_count := 2
@export var patrol_radius := 110.0
var _cooldown := 0.0
var _tick := 0.0

func allow_encounter(_shark: Node) -> bool:
	if _cooldown > 0: return false
	_cooldown = 180.0
	return true

func _process(delta: float) -> void:
	_cooldown = maxf(0,_cooldown-delta)
	_tick += delta
	if _tick < 0.5: return
	_tick = 0.0
	var raft := get_tree().get_first_node_in_group("raft") as Node3D
	if raft == null: return
	for index in get_child_count():
		var shark := get_child(index) as Node3D
		var angle := float(index)*TAU/maxi(1,get_child_count()) + float(shark.get("_time"))*0.025
		var home := raft.global_position + Vector3(cos(angle)*patrol_radius,-2.0,sin(angle)*patrol_radius)
		shark.set("_home",home)
		if shark.global_position.distance_squared_to(home)>350.0*350.0: shark.global_position=home

const SHARK_SCENE: PackedScene = preload("res://scenes/shark.tscn")


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70391
	for i in range(shark_count):
		var shark := SHARK_SCENE.instantiate() as Node3D
		if shark == null:
			continue
		shark.name = "Shark_%02d" % i
		var angle := TAU * float(i) / float(maxi(shark_count, 1)) + rng.randf_range(-0.3, 0.3)
		var radius := rng.randf_range(patrol_radius * 0.85, patrol_radius)
		shark.position = Vector3(cos(angle) * radius, -0.6, sin(angle) * radius)
		add_child(shark)
