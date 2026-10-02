extends Node3D

@export_range(0, 8, 1) var shark_count := 3
@export var patrol_radius := 32.0

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
		var radius := rng.randf_range(patrol_radius * 0.55, patrol_radius)
		shark.position = Vector3(cos(angle) * radius, -0.6, sin(angle) * radius)
		add_child(shark)
