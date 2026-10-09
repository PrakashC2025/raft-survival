extends StaticBody3D
## One compact flight; old stacked flights retain their saved landing.
const RUN := 2.4
const LANDING := 0.2
const RISE := 2.65
const TOP := 2.55
var run := RUN

func save_survival_state() -> Dictionary:
	return {"run":run}

func restore_survival_state(data: Dictionary) -> void:
	var value := float(data.get("run",RUN))
	var restored := 2.8 if data.is_empty() else clampf(value if is_finite(value) else RUN,RUN,2.8)
	if is_equal_approx(run,restored): return
	var ratio := restored/run
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("Step"):
			child.position.z*=ratio
			child.scale.z*=ratio
	var ramp := get_node("WalkableRamp") as CollisionShape3D
	var shape := ramp.shape.duplicate() as ConvexPolygonShape3D
	var points := shape.points
	for i in points.size(): points[i].z*=ratio
	shape.points=points; ramp.shape=shape
	get_node("Landing").position.z=restored+LANDING/2.0
	get_node("CollisionLanding").position.z=restored+LANDING/2.0
	get_node("BuildSockets/Socket_Top").position.z=restored+LANDING
	run=restored
