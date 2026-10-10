extends RefCounted
## New seed items deliberately do not use the legacy edible '* Seed' aliases.
const CROPS := ["Tomato","Bell Pepper","Cucumber","Pumpkin","Strawberry","Corn","Papaya"]
const NEW_CROPS := ["Bell Pepper","Cucumber","Pumpkin","Strawberry","Corn","Papaya"]
static func seed_crop(item: String, wet: bool=false) -> String:
	var prefix:="Wet " if wet else "Dry "
	var crop:=item.trim_prefix(prefix).trim_suffix(" Seeds")
	return crop if item==prefix+crop+" Seeds" and crop in CROPS else ""
static func sliced_crop(item: String) -> String:
	var crop:=item.trim_prefix("Sliced ")
	return crop if item=="Sliced "+crop and crop in CROPS else ""
static func box_crop(item: String) -> String:
	var crop:=item.trim_suffix(" Garden Box")
	return crop if item==crop+" Garden Box" and crop in NEW_CROPS else ""
static func rewards(item: String) -> Dictionary:
	if item in CROPS:return {"Sliced "+item:1,"Wet "+item+" Seeds":2}
	var crop:=box_crop(item)
	if crop.is_empty():return {}
	var loot: Dictionary={"Dry "+crop+" Seeds":2,crop:1}
	loot[["Battery","Wire","Sponge","Screw","Motor","Wire"][NEW_CROPS.find(crop)]]=1
	return loot
static func icon_cell(item: String) -> Vector2i:
	var crop:=item;var column:=0
	if not box_crop(item).is_empty():crop=box_crop(item);column=4
	elif not sliced_crop(item).is_empty():crop=sliced_crop(item);column=1
	elif not seed_crop(item).is_empty():crop=seed_crop(item);column=2
	elif not seed_crop(item,true).is_empty():crop=seed_crop(item,true);column=3
	return Vector2i(column,CROPS.find(crop))
