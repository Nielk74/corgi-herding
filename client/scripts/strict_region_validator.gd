extends RefCounted
## Bounded offline authoring schema, not network layout validation.
## Limits intentionally match the prototype's shared one-unit float32 lattice.

const MAX_COORDINATE := 1024.0
const MAX_HEIGHT := 128.0
const MAX_CHUNKS := 140
const MAX_TERRAIN_TRIANGLES := 72000
const MAX_REGION_BYTES := 256 * 1024

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func point(value: Variant) -> bool:
	return value is Dictionary and value.has_all(["x", "y"]) and number(value.x) and number(value.y) and absf(value.x) <= MAX_COORDINATE and absf(value.y) <= MAX_COORDINATE

static func inside(value: Dictionary, bounds: Array) -> bool:
	return value.x >= bounds[0] and value.x <= bounds[2] and value.y >= bounds[1] and value.y <= bounds[3]

static func bounds_errors(bounds: Variant) -> Array[String]:
	if not bounds is Array or bounds.size() != 4 or not bounds.all(number):
		return ["Four finite bounds required"]
	for coordinate in bounds:
		if absf(coordinate) > MAX_COORDINATE:
			return ["Absolute landscape coordinates must be within 1024 units"]
	if bounds[0] >= bounds[2] or bounds[1] >= bounds[3] or maxf(bounds[2] - bounds[0], bounds[3] - bounds[1]) > 512.0:
		return ["Ordered landscape dimensions of at most 512 units required"]
	var columns := ceili(bounds[2] / 16.0) - floori(bounds[0] / 16.0)
	var rows := ceili(bounds[3] / 16.0) - floori(bounds[1] / 16.0)
	var chunks := columns * rows
	if chunks > MAX_CHUNKS or chunks * 512 > MAX_TERRAIN_TRIANGLES:
		return ["Landscape exceeds 140 chunks or 72000 terrain triangles"]
	return []

static func validate_file(path: Variant, expected_bounds: Array) -> Array[String]:
	if not path is String or not path.begins_with("res://worlds/regions/") or path.contains("..") or not FileAccess.file_exists(path):
		return ["Referenced visual region must be a reviewed local recipe"]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["Referenced visual region could not be read"]
	if file.get_length() > MAX_REGION_BYTES:
		file.close()
		return ["Referenced visual region exceeds 256 KiB"]
	var source := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(source) != OK:
		return ["Referenced visual region is not valid JSON"]
	return validate(json.data, expected_bounds)

static func validate(value: Variant, expected_bounds: Array) -> Array[String]:
	var errors := bounds_errors(expected_bounds)
	if not errors.is_empty():
		return errors
	if not value is Dictionary or not value.has_all(["anchors", "corridors", "clearings", "bounds"]):
		return ["Incomplete visual region"]
	if not value.bounds is Dictionary or not value.bounds.has_all(["min", "max"]) or not point(value.bounds.min) or not point(value.bounds.max):
		return ["Region bounds require finite min/max points"]
	var actual_bounds := [value.bounds.min.x, value.bounds.min.y, value.bounds.max.x, value.bounds.max.y]
	for i in range(4):
		if float(actual_bounds[i]) != float(expected_bounds[i]):
			return ["Visual recipe and region bounds disagree"]
	if not value.anchors is Array or value.anchors.size() < 2 or value.anchors.size() > 32:
		return ["Region needs two to 32 anchors"]
	for anchor in value.anchors:
		if not point(anchor) or not inside(anchor, expected_bounds):
			errors.append("Region anchors must be finite points inside authored bounds")
	if not value.corridors is Array or value.corridors.is_empty() or value.corridors.size() > 64:
		return ["Region needs one to 64 corridors"]
	var seen_edges := {}
	for edge in value.corridors:
		if not edge is Dictionary or not edge.has_all(["a", "b", "half_width"]):
			errors.append("Region corridor needs two indices and a half-width")
			continue
		if not number(edge.a) or not number(edge.b) or edge.a < 0 or edge.b < 0 or edge.a >= value.anchors.size() or edge.b >= value.anchors.size():
			errors.append("Region corridor index outside anchor array")
		elif edge.a != int(edge.a) or edge.b != int(edge.b) or edge.a == edge.b:
			errors.append("Region corridor requires distinct integer indices")
		else:
			var pair := Vector2i(mini(int(edge.a), int(edge.b)), maxi(int(edge.a), int(edge.b)))
			if seen_edges.has(pair):
				errors.append("Region corridor pairs must be unique, including reverse pairs")
			seen_edges[pair] = true
		if not number(edge.half_width) or edge.half_width < 4.0 or edge.half_width > 24.0:
			errors.append("Region corridor half-width must be within 4 to 24 units")
	if not value.clearings is Array or value.clearings.is_empty() or value.clearings.size() > 16:
		return ["Region needs one to 16 clearings"]
	for clearing in value.clearings:
		if not clearing is Dictionary or not clearing.has_all(["center", "radius"]):
			errors.append("Region clearing needs a center and radius")
			continue
		if not point(clearing.center) or not inside(clearing.center, expected_bounds):
			errors.append("Region clearing center must be inside authored bounds")
		if not number(clearing.radius) or clearing.radius < 4.0 or clearing.radius > 32.0:
			errors.append("Region clearing radius must be within 4 to 32 units")
	return errors
