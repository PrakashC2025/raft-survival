extends Node
const Assets = preload("res://scripts/mobile_assets.gd")
var model: Node3D
var player: CharacterBody3D
func _ready() -> void:
	player = get_parent()
	model = Assets.make("survivor", 1.75, true)
	if model == null:
		return
	var body := player.get_node("Body") as Node3D
	for child in body.get_children():
		if child is GeometryInstance3D:
			child.hide()
	body.scale = Vector3.ONE
	body.position = Vector3.ZERO
	body.add_child(model)
	model.position.y = -0.9
	model.rotation.y = PI
	Assets.animate(model, ["idle"])
func _process(_delta: float) -> void:
	if is_instance_valid(model) and model.is_visible_in_tree():
		Assets.animate(model, ["run"] if player.velocity.length() > 0.6 else ["idle"])
