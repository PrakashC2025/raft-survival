extends RefCounted
## One cooperative budget shared by background setup across every island.
## Render frames, rather than physics ticks, prevent catch-up ticks from doing
## several setup batches before the phone can draw its next loading frame.
const MAX_UNITS := 64
const MAX_MICROSECONDS := 2000
static var _frame := -1
static var _lanes: Dictionary = {}

static func exhausted(units: int = 1, lane: StringName = &"setup",
		unit_limit: int = MAX_UNITS, time_limit: int = MAX_MICROSECONDS) -> bool:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_lanes.clear()
	if not _lanes.has(lane): _lanes[lane] = {"started":Time.get_ticks_usec(),"units":0}
	var work: Dictionary = _lanes[lane]
	work.units += units
	return int(work.units) >= unit_limit or Time.get_ticks_usec() - int(work.started) >= time_limit
