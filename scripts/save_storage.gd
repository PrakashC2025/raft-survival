extends RefCounted
## AES-256-CBC with authenticated ciphertext, atomic replacement and one backup.
## Legacy JSON remains readable; it migrates only on a successful save. Keep the
## local key alongside saves when transferring them to a different installation.
const KEY_PATH := "user://raft_save.key"
const FORMAT := "RAFT-AES256-1"
const MAX_BYTES := 16 * 1024 * 1024
const NUMBER_FIELDS := ["version","health","hunger","thirst","oxygen","game_time","game_day","active_slot","calendar_day","calendar_month","calendar_year","raft_upgrade_tier","island_layout","level","stamina","wetness","torch_fuel","torch_end_time","fuel","end_time","cook","water","seconds","transmissions","moisture","stage","timer","r","g","e","cycle","growth","wait","size","yaw","count","remaining","duration","saved_at","rain_remaining","dry_remaining","respawn","next_check"]
const OBJECT_FIELDS := ["progression","electronics","survival_services","wild_plants","island_groves","wildlife","events","cost","survival","station_job","plant","weather"]
const ARRAY_FIELDS := ["slots","built","ground_crops","drops","contents","records","fruits","p","at","x"]
static var last_error := ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<1.0e12

static func _valid_tree(value: Variant,depth: int=0) -> bool:
	if depth>16:return false
	if value is float:return _number(value)
	if value is String:return value.length()<=512
	if value is Array:
		if value.size()>8192:return false
		for entry in value:
			if not _valid_tree(entry,depth+1):return false
	elif value is Dictionary:
		if value.size()>8192:return false
		for key in value:
			if not key is String or key.length()>512:return false
			var child: Variant=value[key]
			if key in NUMBER_FIELDS and not _number(child):return false
			if key in OBJECT_FIELDS and not child is Dictionary:return false
			if key in ARRAY_FIELDS and not child is Array:return false
			if key=="kind" and not (child is String or _number(child)):return false
			if key=="charge" and not (_number(child) or (child is Dictionary and value.get("installed") is Dictionary)):return false
			if key in ["p","at","x"]:
				for coordinate in child:
					if not _number(coordinate):return false
			if key in ["cost","events"]:
				for amount in child.values():
					if not _number(amount):return false
			if not _valid_tree(child,depth+1):return false
	return true

static func _valid_save(data: Dictionary) -> bool:
	if not _valid_tree(data) or not data.get("slots") is Array:return false
	var air:Variant=data.get("progression",{}).get("air_tank_seconds",0)
	if not _number(air) or float(air)<0 or float(air)>180:return false
	if not data.get("underwater_creatures",{}) is Dictionary:return false
	for creature in data.get("underwater_creatures",{}).values():
		if not creature is Dictionary:return false
		if not _number(creature.get("health",0)) or not _number(creature.get("respawn",0)):return false
		if float(creature.get("health",0))<0 or float(creature.get("health",0))>30 or float(creature.get("respawn",0))<0 or float(creature.get("respawn",0))>600:return false
	if data.has("raft_anchored") and not data.raft_anchored is bool:return false
	if data.has("winter_exposure") and not _number(data.winter_exposure):return false
	if not data.get("biome_resources",{}) is Dictionary:return false
	for hits in data.get("biome_resources",{}).values():
		if not _number(hits) or float(hits)<0 or float(hits)>4:return false
	if not data.get("biome_tree_growth",{}) is Dictionary:return false
	for tree in data.get("biome_tree_growth",{}).values():
		if not tree is Dictionary:return false
		if not _number(tree.get("wait",0)) or not _number(tree.get("growth",1)):return false
		if float(tree.get("wait",0))<0 or float(tree.get("wait",0))>360 or float(tree.get("growth",1))<0 or float(tree.get("growth",1))>1:return false
	if data.get("version",1)!=1 or data.slots.size()>30:return false
	for field in ["calendar_year","calendar_month","calendar_day","game_day"]:
		var maximum:=9999 if field=="calendar_year" else (12 if field=="calendar_month" else (31 if field=="calendar_day" else 9999999))
		if data.has(field) and (float(data[field])<1 or float(data[field])>maximum):return false
	for field in ["island_groves","wild_plants"]:
		for island in data.get(field,{}).values():
			if not island is Dictionary:return false
			if field=="island_groves":
				for plant in island.values():
					if not plant is Dictionary:return false
	for animal in data.get("wildlife",{}).values():
		if not animal is Dictionary:return false
	var electronics: Dictionary=data.get("electronics",{})
	for field in ["charge","installed","enabled"]:
		if not electronics.get(field,{}) is Dictionary:return false
	for amount in electronics.get("charge",{}).values():
		if not _number(amount):return false
	return true

static func _authentication_key(key: PackedByteArray) -> PackedByteArray:
	return ("raft-save-auth:" + Marshalls.raw_to_base64(key)).sha256_buffer()

static func _key(create: bool) -> PackedByteArray:
	if FileAccess.file_exists(KEY_PATH):
		var bytes := FileAccess.get_file_as_bytes(KEY_PATH)
		return bytes if bytes.size() == 32 else PackedByteArray()
	if not create:
		return PackedByteArray()
	var bytes := Crypto.new().generate_random_bytes(32)
	var file := FileAccess.open(KEY_PATH, FileAccess.WRITE)
	if file == null or bytes.size() != 32:
		return PackedByteArray()
	file.store_buffer(bytes)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return bytes if ok else PackedByteArray()

static func read_one(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	if parsed.get("format", "") == FORMAT:
		var key := _key(false)
		var iv := Marshalls.base64_to_raw(str(parsed.get("iv", "")))
		var cipher := Marshalls.base64_to_raw(str(parsed.get("cipher", "")))
		var mac := Marshalls.base64_to_raw(str(parsed.get("mac", "")))
		if key.size() != 32 or iv.size() != 16 or cipher.is_empty() or cipher.size() % 16 != 0:
			return {}
		var crypto := Crypto.new()
		# Authenticate before decrypting; invalid files never reach the AES decoder.
		var expected := crypto.hmac_digest(HashingContext.HASH_SHA256, _authentication_key(key), iv + cipher)
		if not crypto.constant_time_compare(expected, mac):
			return {}
		var aes := AESContext.new()
		if aes.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
			return {}
		var plain := aes.update(cipher)
		aes.finish()
		if plain.is_empty():
			return {}
		var padding: int = plain[-1]
		if padding < 1 or padding > 16 or padding > plain.size():
			return {}
		for index in range(plain.size() - padding, plain.size()):
			if plain[index] != padding:
				return {}
		plain.resize(plain.size() - padding)
		parsed = JSON.parse_string(plain.get_string_from_utf8())
	if not parsed is Dictionary or not _valid_save(parsed):
		return {}
	if parsed.has("built") and not parsed.built is Array:
		return {}
	for field in ["health","hunger","thirst","oxygen","game_time"]:
		if parsed.has(field) and (not (parsed[field] is int or parsed[field] is float) or not is_finite(float(parsed[field]))):
			return {}
	return parsed

static func read(path: String) -> Dictionary:
	last_error = ""
	var data := read_one(path)
	if data.is_empty():
		data = read_one(path + ".bak")
	if data.is_empty():
		last_error = "SAVE COULD NOT BE READ · KEEP ITS SAVE KEY AND BACKUP"
	return data

static func write(path: String, data: Dictionary) -> bool:
	last_error = ""
	var key := _key(true)
	if key.size() != 32:
		last_error = "SAVE KEY COULD NOT BE WRITTEN"
		return false
	# Refuse to overwrite an unreadable encrypted save, including a lost key.
	if FileAccess.file_exists(path) and read_one(path).is_empty() and read_one(path + ".bak").is_empty():
		last_error = "EXISTING SAVE IS UNREADABLE · RESTORE ITS KEY OR BACKUP"
		return false
	var iv := Crypto.new().generate_random_bytes(16)
	var plain := JSON.stringify(data).to_utf8_buffer()
	var padding := 16 - plain.size() % 16
	for unused in range(padding):
		plain.append(padding)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv) != OK:
		last_error = "SAVE ENCRYPTION COULD NOT START"
		return false
	var cipher := aes.update(plain)
	aes.finish()
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _authentication_key(key), iv + cipher)
	var envelope := {"format": FORMAT, "iv": Marshalls.raw_to_base64(iv),
		"cipher": Marshalls.raw_to_base64(cipher), "mac": Marshalls.raw_to_base64(mac)}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "SAVE COULD NOT BE WRITTEN · CHECK FREE STORAGE"
		return false
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	if not ok or read_one(temporary).is_empty():
		last_error = "SAVE VERIFICATION FAILED"
		return false
	var full_path := ProjectSettings.globalize_path(path)
	var backup := full_path + ".bak"
	if FileAccess.file_exists(path):
		# Never rotate a corrupt primary over the last valid backup.
		if not read_one(path).is_empty():
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				last_error = "SAVE BACKUP COULD NOT BE REPLACED"
				return false
			if DirAccess.rename_absolute(full_path, backup) != OK:
				last_error = "SAVE BACKUP COULD NOT BE CREATED"
				return false
		elif DirAccess.remove_absolute(full_path) != OK:
			last_error = "DAMAGED SAVE COULD NOT BE REPLACED"
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), full_path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.copy_absolute(backup, full_path)
		last_error = "SAVE COULD NOT BE COMMITTED · PREVIOUS SAVE RETAINED"
		return false
	return true
