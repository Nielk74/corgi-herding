extends RefCounted
## Local practice-guide choices only. Never reads or rewrites herd.cfg/audio.cfg.
## No lesson/action replay: an unfinished guide starts afresh after app restart.

const CONFIG_PATH := "user://guide.cfg"
const MAX_HERDS := 128
var config_path := CONFIG_PATH
var persist_config := true
var _loaded_path := ""
var _records: Dictionary = {}

static func herd_key(endpoint: String, code: String, player_id: String) -> String:
	if endpoint.is_empty() or code.is_empty() or player_id.is_empty():
		return ""
	# Length-delimited JSON avoids ambiguous separators. Tokens are never used.
	return JSON.stringify([endpoint.strip_edges().trim_suffix("/"), code, player_id]).sha256_text()

func known(key: String) -> bool:
	_load()
	return _records.has(key)

func choice(key: String) -> Dictionary:
	_load()
	return _records.get(key, {"hidden": false, "completed": false}).duplicate(true)

func remember(key: String, hidden: bool, completed: bool) -> void:
	if not _valid_key(key):
		return
	_load()
	var value := {"hidden": hidden, "completed": completed}
	if _records.get(key) == value:
		return
	if not _records.has(key) and _records.size() >= MAX_HERDS:
		_records.erase(_records.keys()[0])
	_records[key] = value
	if persist_config:
		var config := ConfigFile.new()
		for record_key: String in _records:
			config.set_value("practice", record_key, _records[record_key])
		config.save(config_path)

func _load() -> void:
	if _loaded_path == config_path:
		return
	_loaded_path = config_path
	_records.clear()
	if not persist_config or not FileAccess.file_exists(config_path):
		return
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return
	file.close()
	var config := ConfigFile.new()
	if config.load(config_path) != OK or not config.has_section("practice"):
		return
	for key: String in config.get_section_keys("practice"):
		var value: Variant = config.get_value("practice", key)
		if _valid_key(key) and value is Dictionary and value.size() == 2 and value.get("hidden") is bool and value.get("completed") is bool:
			_records[key] = value.duplicate(true)
		if _records.size() >= MAX_HERDS:
			break

static func _valid_key(key: String) -> bool:
	if key.length() != 64:
		return false
	for character in key:
		if character not in "0123456789abcdef":
			return false
	return true
