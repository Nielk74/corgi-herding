class_name JuniperShoreNavigation
extends RefCounted
## V5 shore uses the proven capsule-union predicates without changing Cloud.
## Navigation has six fixed anchors, source index6, target7, at most six retained.

const Union = preload("res://scripts/cloud_navigation.gd")
const PATH := [[-11.0, 2.0], [-8.0, -3.0], [-3.0, -6.0], [4.0, -6.0], [9.0, -2.0], [11.0, 4.0]]
const SHORE := {
	"path": [{"x": -11.0, "y": 2.0}, {"x": -8.0, "y": -3.0}, {"x": -3.0, "y": -6.0}, {"x": 4.0, "y": -6.0}, {"x": 9.0, "y": -2.0}, {"x": 11.0, "y": 4.0}],
	"half_width": 3.6,
	"clearings": [{"center": {"x": -11.0, "y": 2.0}, "radius": 5.2}, {"center": {"x": -1.0, "y": -6.0}, "radius": 4.5}, {"center": {"x": 11.0, "y": 4.0}, "radius": 4.8}],
	"lake_side": "left"
}
const CORRIDOR := {"spine": SHORE.path, "half_width": SHORE.half_width, "shelves": SHORE.clearings}

static func default_shore() -> Dictionary:
	return SHORE.duplicate(true)

static func layout() -> Dictionary:
	return {"version": 5, "bridge_y": 0.0, "gate_y": 0.0, "shore": default_shore()}

static func corridor(shore: Dictionary = {}) -> Dictionary:
	return CORRIDOR if shore.is_empty() else {"spine": shore.path, "half_width": shore.half_width, "shelves": shore.clearings}

static func signed_clearance(point: Vector2, shore: Dictionary = {}) -> float:
	return Union.signed_clearance(point, corridor(shore))

static func contains(point: Vector2, shore: Dictionary = {}) -> bool:
	return Union.contains(point, corridor(shore))

static func visible(from: Vector2, to: Vector2, shore: Dictionary = {}) -> bool:
	return _visible_coordinates(from.x, from.y, to.x, to.y, corridor(shore))

static func _in_disk(x: float, y: float, center: Dictionary, radius: float) -> bool:
	var dx: float = x - center.x
	var dy: float = y - center.y
	return dx * dx + dy * dy <= radius * radius

static func _in_capsule(x: float, y: float, a: Dictionary, b: Dictionary, radius: float) -> bool:
	var nearest := Union._nearest(x, y, a.x, a.y, b.x, b.y)
	var dx: float = x - nearest[0]
	var dy: float = y - nearest[1]
	return dx * dx + dy * dy <= radius * radius

static func _visible_coordinates(ax: float, ay: float, bx: float, by: float, geometry: Dictionary) -> bool:
	if not Union._contains_xy(ax, ay, geometry) or not Union._contains_xy(bx, by, geometry):
		return false
	if ax == bx and ay == by:
		return true
	# The same closed primitive contains the entire chord by convexity. Keep
	# the exact walkability arithmetic; do not add a boundary epsilon.
	for clearing in geometry.shelves:
		if _in_disk(ax, ay, clearing.center, clearing.radius) and _in_disk(bx, by, clearing.center, clearing.radius):
			return true
	for i in geometry.spine.size() - 1:
		var a: Dictionary = geometry.spine[i]
		var b: Dictionary = geometry.spine[i + 1]
		if _in_capsule(ax, ay, a, b, geometry.half_width) and _in_capsule(bx, by, a, b, geometry.half_width):
			return true
	# A multi-primitive chord must pass the original analytic union check in
	# both directions. Cloud's implementation and v4 behavior are unchanged.
	return Union._visible_coordinates(ax, ay, bx, by, geometry) and Union._visible_coordinates(bx, by, ax, ay, geometry)

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
	var nodes := PATH.duplicate()
	nodes.append([float(from.x), float(from.y)])
	nodes.append([float(to.x), float(to.y)])
	var distances: Array[float] = [INF, INF, INF, INF, INF, INF, 0.0, INF]
	var previous: Array[int] = [-1, -1, -1, -1, -1, -1, -1, -1]
	var visited: Array[bool] = [false, false, false, false, false, false, false, false]
	for iteration in nodes.size():
		var nearest := -1
		for i in nodes.size():
			if not visited[i] and (nearest < 0 or distances[i] < distances[nearest] - Union.TIE):
				nearest = i
		if nearest < 0 or not is_finite(distances[nearest]) or nearest == 7:
			break
		visited[nearest] = true
		for i in nodes.size():
			if visited[i] or not _visible_coordinates(nodes[nearest][0], nodes[nearest][1], nodes[i][0], nodes[i][1], CORRIDOR):
				continue
			var dx: float = nodes[nearest][0] - nodes[i][0]
			var dy: float = nodes[nearest][1] - nodes[i][1]
			var candidate := distances[nearest] + sqrt(dx * dx + dy * dy)
			if candidate < distances[i] - Union.TIE:
				distances[i] = candidate
				previous[i] = nearest
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
		if point is Dictionary and point.has("x") and point.has("y"):
			route.append(Vector2(float(point.x), float(point.y)))
	return route
