class_name BellflowerCommonsNavigation
extends RefCounted
## V6 explicit fork: repeated traversal edges are the SAME declared capsules,
## never a new 3->4 connection between the two branches. Older helpers are read-only.

const Union = preload("res://scripts/cloud_navigation.gd")
const Shore = preload("res://scripts/shore_navigation.gd")
const ANCHORS := [[-5.0, 0.0], [0.0, 0.0], [4.0, -4.0], [10.0, -6.0], [4.0, 4.0], [10.0, 6.0]]
const TRAVERSAL := [0, 1, 2, 3, 2, 1, 4, 5]
const COMMONS := {
	"anchors": [{"x": -5.0, "y": 0.0}, {"x": 0.0, "y": 0.0}, {"x": 4.0, "y": -4.0}, {"x": 10.0, "y": -6.0}, {"x": 4.0, "y": 4.0}, {"x": 10.0, "y": 6.0}],
	"corridors": [[0, 1], [1, 2], [2, 3], [1, 4], [4, 5]],
	"half_width": 3.6,
	"clearings": [{"center": {"x": -5.0, "y": 0.0}, "radius": 7.2}, {"center": {"x": 10.0, "y": -6.0}, "radius": 4.8}, {"center": {"x": 10.0, "y": 6.0}, "radius": 4.8}],
}
const CORRIDOR := {
	"spine": [COMMONS.anchors[0], COMMONS.anchors[1], COMMONS.anchors[2], COMMONS.anchors[3], COMMONS.anchors[2], COMMONS.anchors[1], COMMONS.anchors[4], COMMONS.anchors[5]],
	"half_width": COMMONS.half_width,
	"shelves": COMMONS.clearings,
}

static func default_commons() -> Dictionary:
	return COMMONS.duplicate(true)

static func layout() -> Dictionary:
	return {"version": 6, "bridge_y": 0.0, "gate_y": 0.0, "commons": default_commons()}

static func corridor(commons: Dictionary = {}) -> Dictionary:
	if commons.is_empty():
		return CORRIDOR
	# The immutable wire layout is validated by the receiving world before use.
	# Its declared edge set and this exact traversal have a shared regression.
	var path: Array = []
	for index in TRAVERSAL:
		path.append(commons.anchors[index])
	return {"spine": path, "half_width": commons.half_width, "shelves": commons.clearings}

static func signed_clearance(point: Vector2, commons: Dictionary = {}) -> float:
	return Union.signed_clearance(point, corridor(commons))

static func contains(point: Vector2, commons: Dictionary = {}) -> bool:
	return Union.contains(point, corridor(commons))

static func visible(from: Vector2, to: Vector2, commons: Dictionary = {}) -> bool:
	return _visible_coordinates(from.x, from.y, to.x, to.y, corridor(commons))

static func _visible_coordinates(ax: float, ay: float, bx: float, by: float, geometry: Dictionary = CORRIDOR) -> bool:
	# Exact same ordered predicates as Go: common-primitive convexity first,
	# then full analytical union coverage in BOTH directions. No geometry epsilon.
	return Shore._visible_coordinates(ax, ay, bx, by, geometry)

static func presentation_point(point: Vector2) -> Vector2:
	if not point.is_finite():
		return point
	var result := Union._clearance(point.x, point.y, CORRIDOR)
	if absf(result[0]) < Union.PRESENTATION_CLEARANCE:
		return point.move_toward(Vector2(result[1][0], result[1][1]), Union.PRESENTATION_CLEARANCE - result[0])
	return point

static func plan(from: Vector2, to: Vector2) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if visible(from, to):
		return route
	# Unique graph nodes, not the repeated union traversal: anchors0..5,
	# source6, target7. Fixed order and double scalar costs mirror the Go planner.
	var nodes := ANCHORS.duplicate()
	nodes.append([float(from.x), float(from.y)])
	nodes.append([float(to.x), float(to.y)])
	var distances: Array[float] = [INF, INF, INF, INF, INF, INF, 0.0, INF]
	var previous: Array[int] = [-1, -1, -1, -1, -1, -1, -1, -1]
	var visited: Array[bool] = [false, false, false, false, false, false, false, false]
	for iteration in nodes.size():
		var nearest := -1
		for index in nodes.size():
			if not visited[index] and (nearest < 0 or distances[index] < distances[nearest] - Union.TIE):
				nearest = index
		if nearest < 0 or not is_finite(distances[nearest]) or nearest == 7:
			break
		visited[nearest] = true
		for index in nodes.size():
			if visited[index] or not _visible_coordinates(nodes[nearest][0], nodes[nearest][1], nodes[index][0], nodes[index][1]):
				continue
			var dx: float = nodes[nearest][0] - nodes[index][0]
			var dy: float = nodes[nearest][1] - nodes[index][1]
			var candidate := distances[nearest] + sqrt(dx * dx + dy * dy)
			if candidate < distances[index] - Union.TIE:
				distances[index] = candidate
				previous[index] = nearest
	var cursor := previous[7]
	if cursor < 0:
		return route
	while cursor != 6:
		if cursor < 0 or route.size() >= 6:
			return []
		route.push_front(Vector2(nodes[cursor][0], nodes[cursor][1]))
		cursor = previous[cursor]
	return route

static func next_waypoint(from: Vector2, to: Vector2, route: Array[Vector2]) -> Vector2:
	while not route.is_empty() and from.distance_to(route[0]) <= Union.ARRIVAL:
		route.pop_front()
	if visible(from, to):
		route.clear()
		return to
	if route.is_empty() or not visible(from, route[0]) or not visible(route[-1], to):
		route.assign(plan(from, to))
	return route[0] if not route.is_empty() else from

static func decode_route(data: Variant) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if not data is Array or data.size() > 6:
		return route
	for point: Variant in data:
		if not point is Dictionary or point.size() != 2 or not point.has("x") or not point.has("y"):
			return []
		if typeof(point.x) not in [TYPE_INT, TYPE_FLOAT] or typeof(point.y) not in [TYPE_INT, TYPE_FLOAT]:
			return []
		var canonical := false
		for anchor: Array in ANCHORS:
			if float(point.x) == anchor[0] and float(point.y) == anchor[1]:
				canonical = true
				break
		if not canonical:
			return []
		var decoded := Vector2(float(point.x), float(point.y))
		if route.has(decoded) or (not route.is_empty() and not visible(route[-1], decoded)):
			return []
		route.append(decoded)
	return route
