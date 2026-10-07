extends RefCounted
## AES-256-CBC with authenticated ciphertext, atomic replacement and one backup.
## Legacy JSON remains readable; it migrates only on a successful save. Keep the
## local key alongside saves when transferring them to a different installation.
const KEY_PATH := "user://raft_save.key"
const FORMAT := "RAFT-AES256-1"
const MAX_BYTES := 16 * 1024 * 1024
static var last_error := ""

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
	if not parsed is Dictionary or not parsed.get("slots", null) is Array:
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
