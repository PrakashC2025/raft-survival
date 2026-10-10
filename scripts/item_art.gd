extends RefCounted
## Original generated inventory artwork. Regions follow the rendered objects,
## rather than blindly slicing the sheet and clipping long weapons or leaves.
const ATLAS := preload("res://textures/ui/survival_items.png")
const ROPE_LAUNCHER := preload("res://textures/ui/rope_launcher.png")
const ADVANCED_IMAGES := {"Raw Meat":"raw_meat", "Cooked Meat":"cooked_meat", "Raw Crab":"raw_crab", "Cooked Crab":"cooked_crab", "Diving Tank":"diving_tank", "Bandage":"bandage", "Torch":"torch", "Onion":"onion", "Potato":"potato", "Tomato":"tomato", "Banana":"banana"}
static var _pictures: Dictionary = {}
static func garden_texture(item: String) -> Texture2D:
	if item=="Tomato":return null
	var cell:=preload("res://scripts/garden_items.gd").icon_cell(item)
	if cell.y<0:return null
	if not _pictures.has("garden_atlas"):
		if not ResourceLoader.exists("res://textures/ui/garden/garden_atlas.png"):return null
		_pictures["garden_atlas"]=load("res://textures/ui/garden/garden_atlas.png")
	var key:="garden:"+item
	if not _pictures.has(key):
		var atlas:=AtlasTexture.new();atlas.atlas=_pictures.garden_atlas;atlas.region=Rect2(cell*160,Vector2(160,160));atlas.filter_clip=true;_pictures[key]=atlas
	return _pictures[key]
# Bounds follow the original photographic cutouts, including the fish tails.
# All recipes share one cached GPU texture; each gets its own square thumbnail.
const MEAL_REGIONS := {
	"Cooked Potato":Rect2(0,.035,.168,.300), "Cooked Tomato":Rect2(.172,.063,.163,.266),
	"Cooked Fish":Rect2(.325,.030,.173,.305), "Potato Tomato Stew":Rect2(.500,.054,.170,.275),
	"Fish Potato Meal":Rect2(.667,.050,.167,.275), "Fish Potato Tomato Soup":Rect2(.835,.050,.165,.283),
	"Fish Tomato Curry":Rect2(0,.359,.177,.290), "Banana Mash":Rect2(.187,.380,.147,.268),
	"Roasted Carrot":Rect2(.326,.350,.184,.325), "Cooked Onion":Rect2(.515,.383,.156,.253),
	"Tropical Fruit Stew":Rect2(.669,.357,.166,.299), "Root Vegetable Soup":Rect2(.839,.388,.161,.254),
	"Roast Bird":Rect2(0,.659,.172,.300), "Cooked Meat":Rect2(.175,.680,.165,.290),
	"Cooked Crab":Rect2(.337,.666,.170,.294), "Grilled Fish and Onion":Rect2(.510,.650,.165,.309),
	"Coconut Fish Stew":Rect2(.668,.665,.170,.295), "Crab Tomato Broth":Rect2(.842,.675,.158,.280)
}
const STATION_IMAGES := {"Bonfire":"bonfire","RainCollector":"rain_collector","SandFilter":"sand_filter","CookingSetup":"cooking_setup","WindGenerator":"wind_generator","FishingNet":"fishing_net","ElectricLamp":"salvaged_led","Torch":"hand_torch","SeedDryingTray":"seed_drying_tray"}
static func station_texture(item: String) -> Texture2D:
	if not STATION_IMAGES.has(item):return null
	var key:="station:"+item
	if not _pictures.has(key):
		var path:="res://textures/ui/stations/"+str(STATION_IMAGES[item])+".png"
		if ResourceLoader.exists(path):_pictures[key]=load(path)
	return _pictures.get(key) as Texture2D
const REGIONS := {
	"Wood": Rect2(0.000, 0.002, 0.207, 0.176),
	"Rope": Rect2(0.210, 0.014, 0.190, 0.163),
	"Plastic": Rect2(0.424, 0.000, 0.160, 0.178),
	"Metal": Rect2(0.604, 0.014, 0.201, 0.162),
	"Barrel": Rect2(0.843, 0.005, 0.142, 0.175),
	"Stone": Rect2(0.003, 0.183, 0.191, 0.143),
	"Sand": Rect2(0.197, 0.187, 0.208, 0.150),
	"Coconut": Rect2(0.415, 0.183, 0.178, 0.155),
	"Banana": Rect2(0.606, 0.178, 0.187, 0.154),
	"Fish": Rect2(0.805, 0.193, 0.195, 0.135),
	"Cooked Fish": Rect2(0.004, 0.364, 0.219, 0.125),
	"Bow": Rect2(0.214, 0.331, 0.193, 0.185),
	"Arrow": Rect2(0.405, 0.340, 0.205, 0.173),
	"Water": Rect2(0.668, 0.331, 0.092, 0.183),
	"Carrot": Rect2(0.796, 0.307, 0.204, 0.208),
	"Tomato": Rect2(0.014, 0.507, 0.177, 0.145),
	"Potato": Rect2(0.217, 0.513, 0.170, 0.139),
	"Baked Potato": Rect2(0.418, 0.515, 0.175, 0.136),
	"Raw Bird": Rect2(0.601, 0.512, 0.190, 0.142),
	"Roast Bird": Rect2(0.802, 0.520, 0.196, 0.133),
	"Spear": Rect2(0.010, 0.643, 0.205, 0.174),
	"Fishing Rod": Rect2(0.199, 0.640, 0.231, 0.177),
	"Sail Kit": Rect2(0.403, 0.641, 0.202, 0.178),
	"Motor Kit": Rect2(0.626, 0.644, 0.158, 0.176),
	"Life Vest": Rect2(0.827, 0.642, 0.154, 0.171),
	"Carrot Seed": Rect2(0.035, 0.819, 0.140, 0.179),
	"Tomato Seed": Rect2(0.235, 0.819, 0.131, 0.179),
	"Potato Seed": Rect2(0.432, 0.819, 0.137, 0.179),
	"Coconut Seed": Rect2(0.630, 0.819, 0.137, 0.179),
	"Backpack": Rect2(0.808, 0.816, 0.164, 0.182),
}
# A diagonal rod and rolled sail occupy neighboring sheet cells. Tight UV
# silhouettes keep their extremities without sampling the adjacent object.
static var _outlines := {
	"Spear": PackedVector2Array([Vector2(0.010, 0.805), Vector2(0.151, 0.679), Vector2(0.159, 0.660), Vector2(0.204, 0.643), Vector2(0.215, 0.649), Vector2(0.191, 0.687), Vector2(0.050, 0.808), Vector2(0.022, 0.817)]),
	"Fishing Rod": PackedVector2Array([Vector2(0.199, 0.796), Vector2(0.384, 0.665), Vector2(0.430, 0.638), Vector2(0.431, 0.651), Vector2(0.375, 0.697), Vector2(0.362, 0.752), Vector2(0.337, 0.783), Vector2(0.298, 0.807), Vector2(0.264, 0.794), Vector2(0.210, 0.817)]),
	"Sail Kit": PackedVector2Array([Vector2(0.403, 0.796), Vector2(0.419, 0.725), Vector2(0.576, 0.643), Vector2(0.599, 0.638), Vector2(0.609, 0.819), Vector2(0.403, 0.819)]),
}

static func food_texture(item: String) -> Texture2D:
	if item=="Baked Potato":item="Cooked Potato"
	if not preload("res://scripts/food_rules.gd").RECIPES.has(item) and not item.ends_with("Tumbler") and item!="Diving Tank":return null
	var key:="dish:"+item
	if _pictures.has(key):return _pictures[key]
	if MEAL_REGIONS.has(item) and ResourceLoader.exists("res://textures/ui/food/recipe_atlas.png"):
		if not _pictures.has("meal_atlas"):_pictures["meal_atlas"]=load("res://textures/ui/food/recipe_atlas.png")
		var atlas:=_pictures["meal_atlas"] as Texture2D
		var region: Rect2=MEAL_REGIONS[item]
		var thumbnail:=AtlasTexture.new()
		thumbnail.atlas=atlas
		thumbnail.region=Rect2((region.position*atlas.get_size()).floor(),(region.size*atlas.get_size()).ceil())
		var size:=thumbnail.region.size
		var square:=Vector2.ONE*maxf(size.x,size.y)*1.08
		thumbnail.margin=Rect2((square-size)*.5,square-size)
		thumbnail.filter_clip=true
		_pictures[key]=thumbnail
		return thumbnail
	var path:="res://textures/ui/food/"+item.to_lower().replace(" ","_")+".png"
	if not ResourceLoader.exists(path):return null
	var texture:=load(path) as Texture2D
	_pictures[key]=texture
	return texture

static func draw(canvas: CanvasItem, item: String, center: Vector2, radius: float) -> bool:
	var garden:=garden_texture(item)
	if garden!=null:canvas.draw_texture_rect(garden,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false);return true
	if item in ["Solar Torch","Walkie Talkie","Binoculars","Repair Kit"]:
		var key:="electronics:"+item
		if not _pictures.has(key):
			var path:="res://textures/ui/tools/"+item.to_lower().replace(" ","_")+".png"
			if ResourceLoader.exists(path):_pictures[key]=load(path)
		var picture:=_pictures.get(key) as Texture2D
		if picture!=null:canvas.draw_texture_rect(picture,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false);return true
	var station:=station_texture(item)
	if station!=null:canvas.draw_texture_rect(station,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false);return true
	if item in preload("res://scripts/survival_tool_visual.gd").ITEMS:
		var key:="tool:"+item
		if not _pictures.has(key):
			var path:="res://textures/ui/tools/"+item.to_lower()+".png"
			if ResourceLoader.exists(path):_pictures[key]=load(path)
		var texture:=_pictures.get(key) as Texture2D
		if texture!=null:canvas.draw_texture_rect(texture,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false);return true
	if item.ends_with(" Seed"): item = item.trim_suffix(" Seed")
	var meal:=food_texture(item)
	if meal!=null:
		canvas.draw_texture_rect(meal,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false)
		return true
	if ADVANCED_IMAGES.has(item):
		var texture := _pictures.get(item) as Texture2D
		var path := "res://textures/ui/advanced_"+str(ADVANCED_IMAGES[item])+".png"
		if texture == null and ResourceLoader.exists(path):
			texture = load(path) as Texture2D
			_pictures[item] = texture
		if texture != null:
			canvas.draw_texture_rect(texture,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false)
			return true
	if item in ["Raw Meat", "Cooked Meat"]:
		return draw(canvas,"Roast Bird" if item == "Cooked Meat" else "Raw Bird",center,radius)
	if item == "Rope Gun":
		var size := ROPE_LAUNCHER.get_size()
		var launcher_extent := size * (radius * 2.0 / maxf(size.x, size.y))
		canvas.draw_texture_rect(ROPE_LAUNCHER, Rect2(center - launcher_extent * 0.5, launcher_extent), false)
		return true
	if not REGIONS.has(item):
		return false
	var normalized: Rect2 = REGIONS[item]
	var pixels := Rect2(normalized.position * ATLAS.get_size(), normalized.size * ATLAS.get_size())
	var extent := pixels.size * (radius * 2.0 / maxf(pixels.size.x, pixels.size.y))
	if _outlines.has(item):
		var uvs: PackedVector2Array = _outlines[item]
		var points := PackedVector2Array()
		for uv in uvs:
			points.append(center - extent * 0.5 + ((uv - normalized.position) / normalized.size) * extent)
		canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, ATLAS)
		return true
	canvas.draw_texture_rect_region(ATLAS, Rect2(center - extent * 0.5, extent), pixels)
	return true

static func slot_icon(item: String, _slot: int) -> String:
	# Inventory Rope is a material. The permanent launcher has its own control.
	return item
