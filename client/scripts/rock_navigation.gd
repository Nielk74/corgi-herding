class_name RockPassNavigation
extends RefCounted
## Bounded v3 navigation, mirrored from the authoritative Oasis planner.
## These anchors are immutable layout geometry, not a general-purpose navmesh.

const RADIUS := 3.4
const ARRIVAL := 0.08
const TIE := 0.000000001
const PRESENTATION_CLEARANCE := 0.00001
const ANCHOR_COORDINATES := [
	[5.2, 0.0], [3.676955262170047, 3.676955262170047],
	[0.0, 5.2], [-3.676955262170047, 3.676955262170047],
	[-5.2, 0.0], [-3.676955262170047, -3.676955262170047],
	[0.0, -5.2], [3.676955262170047, -3.676955262170047]
]
const ANCHORS: Array[Vector2] = [
	Vector2(5.2, 0), Vector2(3.676955262170047, 3.676955262170047),
	Vector2(0, 5.2), Vector2(-3.676955262170047, 3.676955262170047),
	Vector2(-5.2, 0), Vector2(-3.676955262170047, -3.676955262170047),
	Vector2(0, -5.2), Vector2(3.676955262170047, -3.676955262170047)
]

static func presentation_point(point: Vector2) -> Vector2:
	# Go positions are doubles, but Godot Vector2 stores single-precision values.
	# A valid point exactly outside rock can round inward by a fraction of a
	# micron. Project only that rounding band outward; NEVER shrink collision.
	var radius := point.length()
	if radius > RADIUS - PRESENTATION_CLEARANCE and radius < RADIUS + PRESENTATION_CLEARANCE:
		return point.normalized() * (RADIUS + PRESENTATION_CLEARANCE)
	return point

static func visible(from: Vector2, to: Vector2) -> bool:
	return _visible_coordinates(from.x, from.y, to.x, to.y)

static func _visible_coordinates(ax: float, ay: float, bx: float, by: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var length_squared := dx * dx + dy * dy
	var fraction := 0.0
	if length_squared > 0.0:
		fraction = clampf(-(ax * dx + ay * dy) / length_squared, 0.0, 1.0)
	var x := ax + dx * fraction
	var y := ay + dy * fraction
	return x * x + y * y >= RADIUS * RADIUS

static func plan(from: Vector2, to: Vector2) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if visible(from, to):
		return route
	# Vector2 arithmetic is float32. Keep graph geometry and costs as double
	# scalars like Go so symmetric routes use the same deterministic tie break.
	var nodes: Array = ANCHOR_COORDINATES.duplicate()
	nodes.append([float(from.x), float(from.y)])
	nodes.append([float(to.x), float(to.y)])
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for index in nodes.size():
		distances.append(INF)
		previous.append(-1)
		visited.append(false)
	distances[8] = 0.0
	for iteration in nodes.size():
		var nearest := -1
		for index in nodes.size():
			if not visited[index] and (nearest < 0 or distances[index] < distances[nearest] - TIE):
				nearest = index
		if nearest < 0 or not is_finite(distances[nearest]):
			break
		if nearest == 9:
			break
		visited[nearest] = true
		for index in nodes.size():
			if visited[index] or index == nearest or not _visible_coordinates(nodes[nearest][0], nodes[nearest][1], nodes[index][0], nodes[index][1]):
				continue
			var dx: float = nodes[nearest][0] - nodes[index][0]
			var dy: float = nodes[nearest][1] - nodes[index][1]
			var candidate := distances[nearest] + sqrt(dx * dx + dy * dy)
			if candidate < distances[index] - TIE:
				distances[index] = candidate
				previous[index] = nearest
	var cursor := previous[9]
	if cursor < 0:
		return route
	while cursor != 8 and cursor >= 0:
		route.push_front(Vector2(nodes[cursor][0], nodes[cursor][1]))
		cursor = previous[cursor]
	return route

static func next_waypoint(from: Vector2, to: Vector2, route: Array[Vector2]) -> Vector2:
	if visible(from, to):
		route.clear()
		return to
	while not route.is_empty() and from.distance_to(route[0]) <= ARRIVAL:
		route.pop_front()
	if route.is_empty() or not visible(from, route[0]) or not visible(route[-1], to):
		route.assign(plan(from, to))
	return route[0] if not route.is_empty() else from

static func decode_route(data: Variant) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not data is Array or data.size() > ANCHORS.size():
		return result
	for point: Variant in data:
		if point is Dictionary and point.has("x") and point.has("y"):
			result.append(Vector2(float(point.x), float(point.y)))
	return result
