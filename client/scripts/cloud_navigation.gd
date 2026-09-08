class_name CloudRidgeNavigation
extends RefCounted
## Canonical v4 ridge geometry and bounded navigation, mirrored by the Go server.
## Every segment must remain in the union of broad shelf disks and spine capsules.

const SPINE := [[-10.0, 0.0], [-2.0, -5.0], [5.0, 1.0], [11.0, 4.0]]
const SHELVES := [[-10.0, 0.0, 6.2], [-2.0, -5.0, 4.8], [11.0, 4.0, 5.2]]
const HALF_WIDTH := 3.6
const ARRIVAL := 0.08
const TIE := 0.000000001
const PRESENTATION_CLEARANCE := 0.00001
const RIDGE := {
	"spine": [{"x": -10.0, "y": 0.0}, {"x": -2.0, "y": -5.0}, {"x": 5.0, "y": 1.0}, {"x": 11.0, "y": 4.0}],
	"half_width": HALF_WIDTH,
	"shelves": [{"center": {"x": -10.0, "y": 0.0}, "radius": 6.2}, {"center": {"x": -2.0, "y": -5.0}, "radius": 4.8}, {"center": {"x": 11.0, "y": 4.0}, "radius": 5.2}],
	"rest": {"center": {"x": 11.0, "y": 4.0}, "radius": 4.6}
}

static func default_ridge() -> Dictionary:
	return RIDGE.duplicate(true)

static func layout() -> Dictionary:
	return {"version": 4, "bridge_y": 0.0, "gate_y": 0.0, "ridge": default_ridge()}

static func _geometry(ridge: Dictionary) -> Dictionary:
	return RIDGE if ridge.is_empty() else ridge

static func _nearest(x: float, y: float, ax: float, ay: float, bx: float, by: float) -> Array:
	var dx := bx - ax
	var dy := by - ay
	var length_squared := dx * dx + dy * dy
	var t := clampf(((x - ax) * dx + (y - ay) * dy) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
	return [ax + dx * t, ay + dy * t]

static func signed_clearance(point: Vector2, ridge: Dictionary = {}) -> float:
	return _clearance(point.x, point.y, _geometry(ridge))[0]

static func _clearance(x: float, y: float, ridge: Dictionary) -> Array:
	var best := -INF
	var center: Array = [x, y]
	for shelf in ridge.shelves:
		var dx: float = x - shelf.center.x
		var dy: float = y - shelf.center.y
		var gap: float = shelf.radius - sqrt(dx * dx + dy * dy)
		if gap > best:
			best = gap
			center = [float(shelf.center.x), float(shelf.center.y)]
	for i in ridge.spine.size() - 1:
		var a: Dictionary = ridge.spine[i]
		var b: Dictionary = ridge.spine[i + 1]
		var nearest := _nearest(x, y, a.x, a.y, b.x, b.y)
		var dx: float = x - nearest[0]
		var dy: float = y - nearest[1]
		var gap: float = ridge.half_width - sqrt(dx * dx + dy * dy)
		if gap > best:
			best = gap
			center = nearest
	return [best, center]

static func contains(point: Vector2, ridge: Dictionary = {}) -> bool:
	return _contains_xy(point.x, point.y, _geometry(ridge))

static func _contains_xy(x: float, y: float, ridge: Dictionary) -> bool:
	if not is_finite(x) or not is_finite(y) or absf(x) > 17.0 or absf(y) > 11.0:
		return false
	for shelf in ridge.shelves:
		var dx: float = x - shelf.center.x
		var dy: float = y - shelf.center.y
		if dx * dx + dy * dy <= float(shelf.radius) * float(shelf.radius):
			return true
	for i in ridge.spine.size() - 1:
		var a: Dictionary = ridge.spine[i]
		var b: Dictionary = ridge.spine[i + 1]
		var nearest := _nearest(x, y, a.x, a.y, b.x, b.y)
		var dx: float = x - nearest[0]
		var dy: float = y - nearest[1]
		if dx * dx + dy * dy <= float(ridge.half_width) * float(ridge.half_width):
			return true
	return false

static func presentation_point(point: Vector2) -> Vector2:
	# Project only the float32 rounding band inward. The authoritative corridor
	# and its collision predicate are never enlarged, including for prediction.
	if not point.is_finite():
		return point
	var result := _clearance(point.x, point.y, RIDGE)
	if absf(result[0]) < PRESENTATION_CLEARANCE:
		var center := Vector2(result[1][0], result[1][1])
		return point.move_toward(center, PRESENTATION_CLEARANCE - result[0])
	return point

static func _circle_interval(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, radius: float) -> Array:
	var dx := bx - ax
	var dy := by - ay
	var x := ax - cx
	var y := ay - cy
	var aa := dx * dx + dy * dy
	var cc := x * x + y * y - radius * radius
	if aa == 0.0:
		return [0.0, 1.0] if cc <= 0.0 else []
	var bb := x * dx + y * dy
	var discriminant := bb * bb - aa * cc
	if discriminant < 0.0:
		return []
	var root := sqrt(discriminant)
	var low := maxf(0.0, (-bb - root) / aa)
	var high := minf(1.0, (-bb + root) / aa)
	# Preserve exact endpoint membership rather than widening any interval.
	if cc <= 0.0:
		low = 0.0
	if (bx - cx) * (bx - cx) + (by - cy) * (by - cy) <= radius * radius:
		high = 1.0
	return [low, high] if low <= high else []

static func _slab(interval: Array, origin: float, speed: float, low: float, high: float) -> Array:
	if interval.is_empty():
		return []
	if speed == 0.0:
		return interval if origin >= low and origin <= high else []
	var a := (low - origin) / speed
	var b := (high - origin) / speed
	var enter := maxf(interval[0], minf(a, b))
	var leave := minf(interval[1], maxf(a, b))
	return [enter, leave] if enter <= leave else []

static func visible(from: Vector2, to: Vector2, ridge: Dictionary = {}) -> bool:
	return _visible_coordinates(from.x, from.y, to.x, to.y, _geometry(ridge))

static func _visible_coordinates(ax: float, ay: float, bx: float, by: float, ridge: Dictionary) -> bool:
	if not _contains_xy(ax, ay, ridge) or not _contains_xy(bx, by, ridge):
		return false
	if ax == bx and ay == by:
		return true
	var dx := bx - ax
	var dy := by - ay
	var intervals: Array = []
	for shelf in ridge.shelves:
		var span := _circle_interval(ax, ay, bx, by, shelf.center.x, shelf.center.y, shelf.radius)
		if not span.is_empty():
			intervals.append(span)
	for point in ridge.spine:
		var span := _circle_interval(ax, ay, bx, by, point.x, point.y, ridge.half_width)
		if not span.is_empty():
			intervals.append(span)
	for i in ridge.spine.size() - 1:
		var a: Dictionary = ridge.spine[i]
		var b: Dictionary = ridge.spine[i + 1]
		var sx: float = b.x - a.x
		var sy: float = b.y - a.y
		var length_squared := sx * sx + sy * sy
		var f: float = (ax - a.x) * sx + (ay - a.y) * sy
		var g: float = (ax - a.x) * sy - (ay - a.y) * sx
		var df := dx * sx + dy * sy
		var dg := dx * sy - dy * sx
		var span := _slab([0.0, 1.0], f, df, 0.0, length_squared)
		var width: float = ridge.half_width * sqrt(length_squared)
		span = _slab(span, g, dg, -width, width)
		if not span.is_empty():
			if f >= 0.0 and f <= length_squared and g >= -width and g <= width:
				span[0] = 0.0
			if f + df >= 0.0 and f + df <= length_squared and g + dg >= -width and g + dg <= width:
				span[1] = 1.0
			intervals.append(span)
	intervals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var covered := 0.0
	for span in intervals:
		if span[0] > covered:
			return false
		covered = maxf(covered, span[1])
		if covered >= 1.0:
			return true
	return false

static func plan(from: Vector2, to: Vector2) -> Array[Vector2]:
	var route: Array[Vector2] = []
	var ridge := RIDGE
	if visible(from, to, ridge):
		return route
	var nodes := SPINE.duplicate()
	nodes.append([float(from.x), float(from.y)])
	nodes.append([float(to.x), float(to.y)])
	var distances: Array[float] = [INF, INF, INF, INF, 0.0, INF]
	var previous: Array[int] = [-1, -1, -1, -1, -1, -1]
	var visited: Array[bool] = [false, false, false, false, false, false]
	for iteration in nodes.size():
		var nearest := -1
		for i in nodes.size():
			if not visited[i] and (nearest < 0 or distances[i] < distances[nearest] - TIE):
				nearest = i
		if nearest < 0 or not is_finite(distances[nearest]) or nearest == 5:
			break
		visited[nearest] = true
		for i in nodes.size():
			if visited[i] or not _visible_coordinates(nodes[nearest][0], nodes[nearest][1], nodes[i][0], nodes[i][1], ridge):
				continue
			var dx: float = nodes[nearest][0] - nodes[i][0]
			var dy: float = nodes[nearest][1] - nodes[i][1]
			var candidate := distances[nearest] + sqrt(dx * dx + dy * dy)
			if candidate < distances[i] - TIE:
				distances[i] = candidate
				previous[i] = nearest
	var cursor := previous[5]
	if cursor < 0:
		return route
	while cursor != 4 and cursor >= 0 and route.size() <= 4:
		route.push_front(Vector2(nodes[cursor][0], nodes[cursor][1]))
		cursor = previous[cursor]
	return route

static func next_waypoint(from: Vector2, to: Vector2, route: Array[Vector2]) -> Vector2:
	while not route.is_empty() and from.distance_to(route[0]) <= ARRIVAL:
		route.pop_front()
	if visible(from, to):
		route.clear()
		return to
	if route.is_empty() or not visible(from, route[0]) or not visible(route[-1], to):
		route.assign(plan(from, to))
	return route[0] if not route.is_empty() else from

static func decode_route(data: Variant) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if not data is Array or data.size() > 4:
		return route
	for point: Variant in data:
		if point is Dictionary and point.has("x") and point.has("y"):
			route.append(Vector2(float(point.x), float(point.y)))
	return route
