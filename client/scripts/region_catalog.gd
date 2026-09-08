extends RefCounted
## Only these bundled canonical worlds may use generic Region navigation.
## Authoring validation alone never authorizes geometry received over the wire.

const Navigation = preload("res://scripts/region_navigation.gd")
const ENTRIES := {
	"alpine_valley": {"version": 7, "region_id": "alpine_valley_01", "region_path": "res://worlds/regions/alpine_valley_01.json", "recipe_path": "res://worlds/long_valley.recipe.json", "recipe_id": "long_valley", "biome": "alpine", "herder": Vector2(-48, 74), "dogs": [Vector2(-47, 71.8), Vector2(-44, 71.8)], "sheep": Vector2(-44.7, 62.4)},
	"dry_wash": {"version": 8, "region_id": "dry_wash_01", "region_path": "res://worlds/regions/dry_wash_01.json", "recipe_path": "res://worlds/dry_wash.recipe.json", "recipe_id": "dry_wash", "biome": "cactus", "herder": Vector2(-44, 79), "dogs": [Vector2(-43, 76.8), Vector2(-40, 76.8)], "sheep": Vector2(-39.7, 66.4)}
}
static var _regions: Dictionary = {}

static func contains(landscape: String) -> bool:
	return ENTRIES.has(landscape)

static func entry(landscape: String) -> Dictionary:
	return ENTRIES[landscape].duplicate(true) if contains(landscape) else {}

static func canonical(landscape: String) -> Dictionary:
	if not contains(landscape):
		return {}
	if not _regions.has(landscape):
		var info: Dictionary = ENTRIES[landscape]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(info.region_path))
		if not parsed is Dictionary or parsed.get("recipe_id") != info.region_id or not Navigation.validate_geometry(parsed).is_empty():
			return {}
		_regions[landscape] = parsed.duplicate(true)
	return _regions[landscape].duplicate(true)

static func layout(landscape: String) -> Dictionary:
	var region := canonical(landscape)
	if region.is_empty():
		return {}
	return {"version": ENTRIES[landscape].version, "bridge_y": 0.0, "gate_y": 0.0, "region": region}

static func matches(value: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not value is Dictionary or value.size() != expected.size():
			return false
		for key in expected:
			if not value.has(key) or not matches(value[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not value is Array or value.size() != expected.size():
			return false
		for i in expected.size():
			if not matches(value[i], expected[i]):
				return false
		return true
	if typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return typeof(value) in [TYPE_INT, TYPE_FLOAT] and float(value) == float(expected)
	return typeof(value) == typeof(expected) and value == expected
