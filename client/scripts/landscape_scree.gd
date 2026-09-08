extends RefCounted
## Optional offline material mask for a few exposed Alpine shoulders.
## No geometry, normal, collision, trail or shader changes happen here.
## The canonical union matters: overlapping clearings are NOT false boundaries.

const MIN_OUTSIDE := 2.0
const MAX_OUTSIDE := 7.25
const MAX_MASK := 0.82
const PATCHES := [
	{"center": Vector2(-52, 84), "radius": Vector2(5.6, 3.3), "angle": -0.25, "weight": 1.0},
	{"center": Vector2(-42, 85.5), "radius": Vector2(3.0, 2.2), "angle": 0.15, "weight": 0.70},
	{"center": Vector2(-64, 66), "radius": Vector2(2.8, 5.6), "angle": -0.12, "weight": 0.88},
	{"center": Vector2(-67, 53), "radius": Vector2(2.2, 3.7), "angle": -0.25, "weight": 0.62},
	{"center": Vector2(-63, 22), "radius": Vector2(4.6, 2.8), "angle": -0.55, "weight": 0.92},
	{"center": Vector2(-56, 19), "radius": Vector2(3.3, 2.4), "angle": -0.35, "weight": 0.65}
]
var _source: RefCounted
var _calls := 0
var _source_queries := 0

func _init(canonical_source: RefCounted = null) -> void:
	if canonical_source != null and canonical_source.has_method("contains") and canonical_source.has_method("signed_clearance"):
		_source = canonical_source

func mask(point: Vector2) -> float:
	_calls += 1
	if _source == null or not point.is_finite():
		return 0.0
	var shape := 0.0
	for patch: Dictionary in PATCHES:
		var offset := point - Vector2(patch.center)
		# Most world vertices fail this cheap check without any union/noise work.
		if offset.length_squared() > Vector2(patch.radius).length_squared():
			continue
		var local := offset.rotated(-float(patch.angle)) / Vector2(patch.radius)
		var radius := local.length()
		if radius < 1:
			shape = maxf(shape, (1.0 - smoothstep(0.42, 1.0, radius)) * float(patch.weight))
	if shape == 0:
		return 0.0
	_source_queries += 1
	if _source.contains(point):
		return 0.0
	_source_queries += 1
	var clearance: float = _source.signed_clearance(point)
	if not is_finite(clearance):
		return 0.0
	var outside := -clearance
	if outside <= MIN_OUTSIDE or outside >= MAX_OUTSIDE:
		return 0.0
	# The two-unit clean gap also keeps linearly interpolated one-unit triangles
	# off legal ground; a triangle's diameter is only sqrt(2) world units.
	var band := smoothstep(MIN_OUTSIDE, 3.3, outside) * (1.0 - smoothstep(5.5, MAX_OUTSIDE, outside))
	var weather := _noise(point * 0.24) * 0.65 + _noise(point * 0.072 + Vector2(37, -19)) * 0.35
	var breakup := smoothstep(0.23, 0.47, weather) * lerpf(0.56, 1.0, weather)
	return clampf(shape * band * breakup * MAX_MASK, 0.0, MAX_MASK)

static func encode(existing: Color, value: float) -> Color:
	# Default white COLOR on distant meshes decodes to zero. Alpha remains the
	# independent trail mask. Caller must enable a full-scene-only shader flag.
	if not is_finite(value):
		value = 0.0
	return Color(1.0 - clampf(value, 0.0, 1.0), existing.g, existing.b, existing.a)

static func _hash(x: int, y: int) -> float:
	# Bounded integer operations, no RNG/global state or platform FastNoise.
	var value := (x * 374761393 + y * 668265263 + 73451 * 144269) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float((value ^ (value >> 16)) & 0x7fffffff) / 2147483647.0

static func _noise(point: Vector2) -> float:
	var x := floori(point.x)
	var y := floori(point.y)
	var fx := smoothstep(0, 1, point.x - x)
	var fy := smoothstep(0, 1, point.y - y)
	return lerpf(lerpf(_hash(x, y), _hash(x + 1, y), fx), lerpf(_hash(x, y + 1), _hash(x + 1, y + 1), fx), fy)

func debug_state() -> Dictionary:
	return {"enabled": _source != null, "patches": PATCHES.size(), "calls": _calls,
		"source_queries": _source_queries, "outside_band": Vector2(MIN_OUTSIDE, MAX_OUTSIDE),
		"maximum": MAX_MASK, "added_vertices": 0, "added_draw_batches": 0}
