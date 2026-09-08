extends SceneTree
## Standalone shared corridor mathematics; no renderer or running server required.

const Navigation = preload("res://scripts/cloud_navigation.gd")

func _initialize() -> void:
	var ridge := Navigation.default_ridge()
	var fresh := Navigation.default_ridge()
	ridge.spine[0].x = 999.0
	if fresh.spine[0].x != -10.0 or Navigation.default_ridge().spine[0].x != -10.0:
		_fail("canonical layout objects must not share mutable arrays")
		return
	for point in [Vector2(-13, -1.5), Vector2(-13, 1.5), Vector2(-11, -2), Vector2(-11, 2), Vector2(-7, -2), Vector2(-4.7, 1.45), Vector2(-2, -5), Vector2(5, 1), Vector2(11, 4)]:
		if not Navigation.contains(point) or not Navigation.visible(point, point):
			_fail("normal spawn or shelf is outside the corridor: %s" % point)
			return
	for point in [Vector2(-17, 10), Vector2(0, 9), Vector2(6, -10), Vector2(17.01, 4), Vector2.INF]:
		if Navigation.contains(point):
			_fail("outside ridge or world bounds accepted: %s" % point)
			return
	var from := Vector2(-12, 5)
	var target := Vector2(12, 8)
	if not Navigation.contains(from) or not Navigation.contains(target) or Navigation.visible(from, target):
		_fail("valid-endpoint shortcut must leave the ridge between shelves")
		return
	# A valid Go coordinate can round outside the shelf in Vector2. Correct only
	# the display band inward; do not enlarge the strict gameplay predicate.
	var rounded := Vector2(-16.2, 0)
	if Navigation.contains(rounded):
		_fail("float32 boundary fixture no longer exercises rounding")
		return
	var corrected := Navigation.presentation_point(rounded)
	if not Navigation.contains(corrected) or corrected.distance_to(rounded) > 0.00002:
		_fail("boundary presentation correction is not narrowly bounded and inside")
		return
	if Navigation.presentation_point(Vector2(-16.3, 0)) != Vector2(-16.3, 0):
		_fail("invalid positions outside the rounding band must not be teleported")
		return
	var fixture_path := ProjectSettings.globalize_path("res://").path_join("../protocol/cloud-routes.json")
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not fixtures is Array or fixtures.size() != 32:
		_fail("the 32 shared Go/Godot planner fixtures are missing")
		return
	for fixture in fixtures:
		var origin := Vector2(fixture.from.x, fixture.from.y)
		var destination := Vector2(fixture.target.x, fixture.target.y)
		var route := Navigation.plan(origin, destination)
		if Navigation.visible(origin, destination) != fixture.visible or route.size() != fixture.route.size():
			_fail("shared visibility or route length differs: " + str(fixture.name))
			return
		for i in route.size():
			var anchor: Array = Navigation.SPINE[int(fixture.route[i])]
			if route[i] != Vector2(anchor[0], anchor[1]):
				_fail("shared route choice differs: " + str(fixture.name))
				return
	var route_checks := 0
	var routes := [
		[from, target], [target, from],
		[Vector2(-13, -1.5), Vector2(11, 4)], [Vector2(11, 4), Vector2(-13, -1.5)],
		[Vector2(-13, 1.5), Vector2(14, 6)], [Vector2(14, 6), Vector2(-13, 1.5)],
		[Vector2(-4, -8), Vector2(15, 5)], [Vector2(15, 5), Vector2(-4, -8)],
		[corrected, Vector2(11, 4)], [Vector2(11, 4), corrected]
	]
	for pair in routes:
		for frequency in [20.0, 60.0, 4.0]:
			var point: Vector2 = pair[0]
			var destination: Vector2 = pair[1]
			var route := Navigation.plan(point, destination)
			for step in 1600:
				var remaining: float = 4.0 / frequency
				while remaining > 0.00001:
					var distance := minf(remaining, 0.08)
					var next := point.move_toward(Navigation.next_waypoint(point, destination, route), distance)
					if not Navigation.visible(point, next) or point.distance_to(next) > distance + 0.000002:
						_fail("predicted route leaves the corridor or exceeds walking speed")
						return
					point = next
					remaining -= distance
				if point.distance_to(destination) < 0.04:
					break
			if point.distance_to(destination) > 0.08:
				_fail("route stuck: %s -> %s at %s" % [pair[0], destination, point])
				return
			route_checks += 1
	print("CLOUD_NAVIGATION_SMOKE_OK: 32 shared Go/Godot fixtures, strict union geometry, rejected outside shortcut, bounded float32 correction, %d two-way/frequency routes" % route_checks)
	quit(0)

func _fail(message: String) -> void:
	push_error("CLOUD_NAVIGATION_SMOKE_FAILED: " + message)
	quit(1)
