extends RefCounted
static func now(actor: Node) -> float:
	var sky:=actor.get_tree().current_scene.get_node_or_null("Sky3D")
	return float(actor.call("get_survival_day"))*24.0+(float(sky.get("current_time")) if sky!=null else 12.0)
static func next_dawn(actor: Node) -> float:
	var current:=now(actor);var day:=floorf(current/24.0)
	return day*24.0+6.0 if fmod(current,24.0)<6.0 else (day+1.0)*24.0+6.0
static func seconds_left(actor: Node,end: float) -> float:
	var sky:=actor.get_tree().current_scene.get_node_or_null("Sky3D")
	var day_seconds:=absf(float(sky.get("minutes_per_day")))*60.0 if sky!=null else 1440.0
	if day_seconds<1:day_seconds=1440.0
	return maxf(0,end-now(actor))*day_seconds/24.0
