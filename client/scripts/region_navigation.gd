class_name RegionNavigation
extends RefCounted
## V7 only: immutable variable-width capsule graph with binary64 scalar math.
## Authoring validation is intentionally separate from this wire geometry schema.
## Old v1-v6 helpers, bounds and routing traces are never modified.

const MAX_ANCHORS := 32
const MAX_CORRIDORS := 64
const MAX_CLEARINGS := 32
const ARRIVAL := 0.08
const TIE := 0.000000001
var _region: Dictionary = {}
var _errors: Array[String] = []
var _anchors: Array = []
var _links: Array = []
var _cache_builds := 0
var _visibility_queries := 0
var region: Dictionary:
	get: return _region.duplicate(true)
var errors: Array[String]:
	get: return _errors.duplicate()
var valid: bool:
	get: return _errors.is_empty()

static func default_region() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/regions/alpine_valley_01.json"))
	return value.duplicate(true) if value is Dictionary else {}

func _init(value: Variant) -> void:
	_errors = validate_geometry(value)
	if not valid:
		return
	_region = value.duplicate(true)
	for anchor in _region.anchors:
		_anchors.append([float(anchor.x), float(anchor.y)])
	for i in _anchors.size():
		var row := PackedByteArray()
		row.resize(_anchors.size())
		_links.append(row)
	for i in _anchors.size():
		for j in range(i + 1, _anchors.size()):
			var linked := visible_xy(_anchors[i][0], _anchors[i][1], _anchors[j][0], _anchors[j][1])
			_links[i][j] = int(linked)
			_links[j][i] = int(linked)
	_cache_builds += 1

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _point(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and value.has_all(["x", "y"]) and _number(value.x) and _number(value.y)

static func _inside_bounds(x: float, y: float, bounds: Dictionary) -> bool:
	return is_finite(x) and is_finite(y) and x >= bounds.min.x and x <= bounds.max.x and y >= bounds.min.y and y <= bounds.max.y

static func validate_geometry(value: Variant) -> Array[String]:
	if not value is Dictionary or value.size() != 5 or not value.has_all(["recipe_id", "bounds", "anchors", "corridors", "clearings"]):
		return ["Region requires its exact five geometry fields"]
	if not value.recipe_id is String or value.recipe_id.is_empty() or value.recipe_id.length() > 64:
		return ["Invalid region recipe ID"]
	if not value.bounds is Dictionary or value.bounds.size() != 2 or not value.bounds.has_all(["min", "max"]) or not _point(value.bounds.min) or not _point(value.bounds.max):
		return ["Invalid region bounds"]
	var bounds: Dictionary = value.bounds
	if bounds.min.x >= bounds.max.x or bounds.min.y >= bounds.max.y or bounds.max.x - bounds.min.x > 256 or bounds.max.y - bounds.min.y > 256 or maxf(maxf(absf(bounds.min.x), absf(bounds.min.y)), maxf(absf(bounds.max.x), absf(bounds.max.y))) > 512:
		return ["Region bounds exceed the v7 limits"]
	if not value.anchors is Array or value.anchors.size() < 2 or value.anchors.size() > MAX_ANCHORS:
		return ["Region needs two to 32 unique anchors"]
	var seen: Array = []
	for anchor in value.anchors:
		if not _point(anchor) or not _inside_bounds(anchor.x, anchor.y, bounds):
			return ["Invalid region anchor"]
		var coordinates := [float(anchor.x), float(anchor.y)]
		if seen.has(coordinates):
			return ["Duplicate region anchor"]
		seen.append(coordinates)
	if not value.corridors is Array or value.corridors.is_empty() or value.corridors.size() > MAX_CORRIDORS:
		return ["Region needs one to 64 corridors"]
	var edges := {}
	for edge in value.corridors:
		if not edge is Dictionary or edge.size() != 3 or not edge.has_all(["a", "b", "half_width"]):
			return ["Invalid region corridor fields"]
		if not _number(edge.a) or not _number(edge.b) or edge.a < 0 or edge.b < 0 or edge.a >= seen.size() or edge.b >= seen.size():
			return ["Region corridor index outside anchor array"]
		if edge.a != int(edge.a) or edge.b != int(edge.b) or edge.a == edge.b or not _number(edge.half_width) or edge.half_width <= 0 or edge.half_width > 64:
			return ["Invalid region corridor index or width"]
		var dx: float = value.anchors[int(edge.b)].x - value.anchors[int(edge.a)].x
		var dy: float = value.anchors[int(edge.b)].y - value.anchors[int(edge.a)].y
		var length_squared := _dot(dx, dy, dx, dy)
		if length_squared == 0.0 or not is_finite(length_squared):
			return ["Region corridor has unrepresentable squared length"]
		var key := Vector2i(mini(edge.a, edge.b), maxi(edge.a, edge.b))
		if edges.has(key):
			return ["Duplicate or reversed region edge"]
		edges[key] = true
	if not value.clearings is Array or value.clearings.size() > MAX_CLEARINGS:
		return ["Region accepts at most 32 clearings"]
	for clearing in value.clearings:
		if not clearing is Dictionary or clearing.size() != 2 or not clearing.has_all(["center", "radius"]) or not _point(clearing.center):
			return ["Invalid region clearing fields"]
		if not _inside_bounds(clearing.center.x, clearing.center.y, bounds) or not seen.has([float(clearing.center.x), float(clearing.center.y)]) or not _number(clearing.radius) or clearing.radius <= 0 or clearing.radius > 64:
			return ["Region clearing needs a canonical anchor and bounded radius"]
	var connected := {0: true}
	for pass_index in seen.size():
		for edge in value.corridors:
			if connected.has(int(edge.a)) or connected.has(int(edge.b)):
				connected[int(edge.a)] = true
				connected[int(edge.b)] = true
	if connected.size() != seen.size():
		return ["Disconnected region graph"]
	return []

# GDScript float values are binary64. Keep each multiplication in its own
# assignment before any add/subtract, matching Go v7's explicit rounding
# barriers rather than architecture-dependent fused operations or Vector2 math.
static func _dot(ax: float, ay: float, bx: float, by: float) -> float:
	var x := ax * bx
	var y := ay * by
	return x + y

static func _cross(ax: float, ay: float, bx: float, by: float) -> float:
	var x := ax * by
	var y := ay * bx
	return x - y

static func _nearest(x: float, y: float, a: Dictionary, b: Dictionary) -> Array:
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	var u := clampf(_dot(x - a.x, y - a.y, dx, dy) / _dot(dx, dy, dx, dy), 0.0, 1.0)
	var ux := dx * u
	var uy := dy * u
	return [a.x + ux, a.y + uy]

static func _disk(x: float, y: float, center: Dictionary, radius: float) -> bool:
	return _dot(x - center.x, y - center.y, x - center.x, y - center.y) <= radius * radius

func _capsule(x: float, y: float, edge: Dictionary) -> bool:
	var p := _nearest(x, y, _region.anchors[int(edge.a)], _region.anchors[int(edge.b)])
	return _dot(x - p[0], y - p[1], x - p[0], y - p[1]) <= float(edge.half_width) * float(edge.half_width)

func contains(point: Vector2) -> bool:
	return contains_xy(point.x, point.y)

func contains_xy(x: float, y: float) -> bool:
	if not valid or not _inside_bounds(x, y, _region.bounds):
		return false
	for clearing in _region.clearings:
		if _disk(x, y, clearing.center, clearing.radius):
			return true
	for edge in _region.corridors:
		if _capsule(x, y, edge):
			return true
	return false

func visible(from: Vector2, target: Vector2) -> bool:
	return visible_xy(from.x, from.y, target.x, target.y)

func visible_xy(ax: float, ay: float, bx: float, by: float) -> bool:
	_visibility_queries += 1
	if not contains_xy(ax, ay) or not contains_xy(bx, by):
		return false
	if ax == bx and ay == by:
		return true
	for clearing in _region.clearings:
		if _disk(ax, ay, clearing.center, clearing.radius) and _disk(bx, by, clearing.center, clearing.radius):
			return true
	for edge in _region.corridors:
		if _capsule(ax, ay, edge) and _capsule(bx, by, edge):
			return true
	return _coverage(ax, ay, bx, by) and _coverage(bx, by, ax, ay)

static func _circle_interval(ax: float, ay: float, bx: float, by: float, center: Dictionary, radius: float) -> Array:
	var dx := bx - ax
	var dy := by - ay
	var ox: float = ax - center.x
	var oy: float = ay - center.y
	var a := _dot(dx, dy, dx, dy)
	if a == 0:
		return [0.0, 1.0] if _disk(ax, ay, center, radius) else []
	var b := _dot(ox, oy, dx, dy)
	var rr := radius * radius
	var c := _dot(ox, oy, ox, oy) - rr
	var bb := b * b
	var ac := a * c
	var discriminant := bb - ac
	if discriminant < 0:
		return []
	var root := sqrt(discriminant)
	var low := maxf(0, (-b - root) / a)
	var high := minf(1, (-b + root) / a)
	if _disk(ax, ay, center, radius):
		low = 0
	if _disk(bx, by, center, radius):
		high = 1
	return [low, high] if low <= high else []

static func _slab(interval: Array, origin: float, speed: float, low: float, high: float) -> Array:
	if interval.is_empty():
		return []
	if speed == 0:
		return interval if origin >= low and origin <= high else []
	var a := (low - origin) / speed
	var b := (high - origin) / speed
	var enter := maxf(interval[0], minf(a, b))
	var leave := minf(interval[1], maxf(a, b))
	return [enter, leave] if enter <= leave else []

func _coverage(ax: float, ay: float, bx: float, by: float) -> bool:
	var intervals: Array = []
	for clearing in _region.clearings:
		var span := _circle_interval(ax, ay, bx, by, clearing.center, clearing.radius)
		if not span.is_empty():
			intervals.append(span)
	for edge in _region.corridors:
		var a: Dictionary = _region.anchors[int(edge.a)]
		var b: Dictionary = _region.anchors[int(edge.b)]
		for center in [a, b]:
			var disk := _circle_interval(ax, ay, bx, by, center, edge.half_width)
			if not disk.is_empty():
				intervals.append(disk)
		var sx: float = b.x - a.x
		var sy: float = b.y - a.y
		var length_squared := _dot(sx, sy, sx, sy)
		var side: float = edge.half_width * sqrt(length_squared)
		var f := _dot(ax - a.x, ay - a.y, sx, sy)
		var g := _cross(ax - a.x, ay - a.y, sx, sy)
		var df := _dot(bx - ax, by - ay, sx, sy)
		var dg := _cross(bx - ax, by - ay, sx, sy)
		var span := _slab(_slab([0.0, 1.0], f, df, 0, length_squared), g, dg, -side, side)
		if not span.is_empty():
			if f >= 0 and f <= length_squared and g >= -side and g <= side:
				span[0] = 0.0
			f += df
			g += dg
			if f >= 0 and f <= length_squared and g >= -side and g <= side:
				span[1] = 1.0
			intervals.append(span)
	intervals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var covered := 0.0
	for span in intervals:
		if span[0] > covered:
			return false
		covered = maxf(covered, span[1])
		if covered >= 1:
			return true
	return false

func _clearance_xy(x: float, y: float) -> Array:
	var best := -INF
	var center := [x, y]
	for clearing in _region.clearings:
		var gap: float = clearing.radius - sqrt(_dot(x - clearing.center.x, y - clearing.center.y, x - clearing.center.x, y - clearing.center.y))
		if gap > best:
			best = gap
			center = [float(clearing.center.x), float(clearing.center.y)]
	for edge in _region.corridors:
		var p := _nearest(x, y, _region.anchors[int(edge.a)], _region.anchors[int(edge.b)])
		var gap: float = edge.half_width - sqrt(_dot(x - p[0], y - p[1], x - p[0], y - p[1]))
		if gap > best:
			best = gap
			center = p
	return [best, center]

func signed_clearance(point: Vector2) -> float:
	return _clearance_xy(point.x, point.y)[0] if valid and point.is_finite() else -INF

static func presentation_band(point: Vector2) -> float:
	return maxf(0.00001, maxf(absf(point.x), absf(point.y)) * pow(2.0, -22.0))

func presentation_point(point: Vector2) -> Vector2:
	if not valid or not point.is_finite():
		return point
	var result := _clearance_xy(point.x, point.y)
	var band := presentation_band(point)
	var corrected := point
	if absf(result[0]) < band:
		corrected = point.move_toward(Vector2(result[1][0], result[1][1]), band - result[0])
	# Bounds may clip a primitive. Nudge only their float32 rounding band too,
	# without making a genuinely outside endpoint valid or changing predicates.
	var bounds: Dictionary = _region.bounds
	if absf(point.x - bounds.min.x) < band:
		corrected.x = bounds.min.x + band
	elif absf(point.x - bounds.max.x) < band:
		corrected.x = bounds.max.x - band
	if absf(point.y - bounds.min.y) < band:
		corrected.y = bounds.min.y + band
	elif absf(point.y - bounds.max.y) < band:
		corrected.y = bounds.max.y - band
	return corrected if corrected.distance_to(point) <= band * 3.0 and contains(corrected) else point

static func _length(dx: float, dy: float) -> float:
	var p := maxf(absf(dx), absf(dy))
	var q := minf(absf(dx), absf(dy))
	if p == 0:
		return 0
	q /= p
	return p * sqrt(1 + q * q)

func plan(from: Vector2, target: Vector2) -> Array[Vector2]:
	return plan_xy(from.x, from.y, target.x, target.y)

func plan_xy(ax: float, ay: float, bx: float, by: float) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if not contains_xy(ax, ay) or not contains_xy(bx, by) or visible_xy(ax, ay, bx, by):
		return route
	var n := _anchors.size()
	var nodes := _anchors.duplicate(true)
	nodes.append([ax, ay])
	nodes.append([bx, by])
	var links: Array = []
	for i in n + 2:
		var row := PackedByteArray()
		row.resize(n + 2)
		links.append(row)
	for i in n:
		for j in n:
			links[i][j] = _links[i][j]
		links[n][i] = int(visible_xy(ax, ay, nodes[i][0], nodes[i][1]))
		links[i][n] = links[n][i]
		links[n + 1][i] = int(visible_xy(bx, by, nodes[i][0], nodes[i][1]))
		links[i][n + 1] = links[n + 1][i]
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for i in n + 2:
		distances.append(INF)
		previous.append(-1)
		visited.append(false)
	distances[n] = 0
	for step in n + 2:
		var current := -1
		for i in n + 2:
			if not visited[i] and (current < 0 or distances[i] < distances[current] - TIE):
				current = i
		if current < 0 or not is_finite(distances[current]):
			return []
		if current == n + 1:
			break
		visited[current] = true
		for next in n + 2:
			if visited[next] or not links[current][next]:
				continue
			var cost := distances[current] + _length(nodes[next][0] - nodes[current][0], nodes[next][1] - nodes[current][1])
			if cost < distances[next] - TIE:
				distances[next] = cost
				previous[next] = current
	var cursor := previous[n + 1]
	while cursor != n:
		if cursor < 0 or route.size() >= n:
			return []
		route.push_front(Vector2(nodes[cursor][0], nodes[cursor][1]))
		cursor = previous[cursor]
	return route

func next_waypoint(from: Vector2, target: Vector2, route: Array[Vector2]) -> Vector2:
	while not route.is_empty() and _length(from.x - route[0].x, from.y - route[0].y) <= ARRIVAL:
		route.pop_front()
	if visible(from, target):
		route.clear()
		return target
	if route.is_empty() or not visible(from, route[0]) or not visible(route[-1], target):
		route.assign(plan(from, target))
	return route[0] if not route.is_empty() else from

func decode_route(data: Variant, target: Vector2 = Vector2.INF) -> Array[Vector2]:
	# Convenience decoding only. Wire consumers MUST use validated_route(),
	# which distinguishes a malformed queue from a genuine empty direct route.
	var route: Array[Vector2] = []
	if not valid or not data is Array or data.size() > _anchors.size():
		return route
	for point in data:
		if not _point(point) or not _anchors.has([float(point.x), float(point.y)]):
			return []
		var decoded := Vector2(point.x, point.y)
		if decoded == target or route.has(decoded) or (not route.is_empty() and not visible(route[-1], decoded)):
			return []
		route.append(decoded)
	return route

func validated_route(data: Variant, from: Vector2, target: Vector2) -> Dictionary:
	var empty: Array[Vector2] = []
	if not data is Array:
		return {"ok": false, "route": empty}
	var route := decode_route(data, target)
	if route.size() != data.size() or not valid_route(from, target, route):
		return {"ok": false, "route": empty}
	return {"ok": true, "route": route}

func valid_route(from: Vector2, target: Vector2, route: Array[Vector2]) -> bool:
	if not valid or route.size() > _anchors.size():
		return false
	var seen: Array[Vector2] = []
	var previous := from
	for point in route:
		var canonical := false
		for anchor in _anchors:
			canonical = canonical or point == Vector2(anchor[0], anchor[1])
		if not canonical or point == target or seen.has(point) or not visible(previous, point):
			return false
		seen.append(point)
		previous = point
	return visible(previous, target)

func debug_state() -> Dictionary:
	return {"anchors": _anchors.size(), "cache_builds": _cache_builds, "visibility_queries": _visibility_queries}
