extends SceneTree
## Standalone v7 exact-scalar mirror. No main/network/camera/terrain integration.
const Navigation = preload("res://scripts/region_navigation.gd")
var checks := 0
var failures := 0
var fixture_directory := ""
var walks := 0
var failure_kinds := {}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if not failure_kinds.has(message):
			printerr("REGION_NAV_FAILED: " + message)
		failure_kinds[message] = true

func _read(name: String) -> Variant:
	var path := fixture_directory.path_join(name)
	_check(FileAccess.file_exists(path), "Required shared fixture exists: " + name)
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func _run() -> void:
	fixture_directory = ProjectSettings.globalize_path("res://").path_join("../protocol")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="):
			fixture_directory = argument.trim_prefix("--fixtures=")
	var data: Variant = _read("alpine-valley-region.json")
	var routes: Variant = _read("region-routes.json")
	var boundaries: Variant = _read("region-boundaries.json")
	var stress: Variant = _read("region-stress.json")
	if not data is Dictionary or not routes is Array or not boundaries is Array or not stress is Dictionary:
		quit(1)
		return
	var nav := Navigation.new(data)
	_check(nav.valid and nav.errors.is_empty(), "Canonical authoritative graph initializes")
	_check(routes.size() == 64 and boundaries.size() == 28 and stress.cases.size() == 2, "All64 routes/28 boundaries/two stress cases are present")
	_check(JSON.stringify(data) == JSON.stringify(Navigation.default_region()), "Authoring candidate and authoritative canonical region match exactly")
	_contract(nav, data)
	for fixture: Dictionary in routes:
		_route_fixture(nav, fixture)
	_boundaries(nav, boundaries)
	_geometry(nav, data)
	_validation(data)
	_retained(nav)
	var snake := Navigation.new(stress.region)
	_check(snake.valid and snake.region.anchors.size() == 32 and snake.region.clearings.is_empty(), "Generic32-anchor variable-width stress graph validates without clearings")
	for fixture: Dictionary in stress.cases:
		_route_fixture(snake, fixture)
		var route: Array[Vector2] = snake.plan(_point(fixture.from), _point(fixture.target))
		_check(route.size() == 30, "Stress route actually retains30 anchors, never an old4/6 cap")
		var wire := []
		for point in route:
			wire.append({"x": point.x, "y": point.y})
		var decoded: Dictionary = snake.validated_route(wire, _point(fixture.from), _point(fixture.target))
		_check(decoded.ok and decoded.route == route, "All30 retained anchors survive full wire validation")
		_check(not snake.validated_route(wire + wire, _point(fixture.from), _point(fixture.target)).ok, "Oversized stress wire queue cannot be silently truncated")
		_walk(snake, _point(fixture.from), _point(fixture.target), 1.0)
	for pair in [[Vector2(-48, 74), Vector2(44, -78)], [Vector2(-51, -10), Vector2(44, -36)], [Vector2(-7, 60), Vector2(34, 8)]]:
		for stride in [0.08, 0.2]:
			_walk(nav, pair[0], pair[1], stride)
			_walk(nav, pair[1], pair[0], stride)
	print("REGION_NAV_SMOKE: %d checks / %d failures;64 shared routes,28 binary64 boundaries, two30-anchor stress routes,%d complete walks; standalone only" % [checks, failures, walks])
	quit(1 if failures else 0)

func _point(value: Dictionary) -> Vector2:
	return Vector2(value.x, value.y)

func _contract(nav: RefCounted, data: Dictionary) -> void:
	var original: Dictionary = nav.region
	data.anchors[0].x = 999
	var exposed: Dictionary = nav.region
	exposed.corridors[0].half_width = 999
	var another: Dictionary = nav.region
	another.clearings.clear()
	_check(nav.region == original and nav.contains(Vector2(-48, 74)), "Caller input and returned dictionaries cannot mutate cached geometry")
	data.anchors[0].x = original.anchors[0].x
	var state: Dictionary = nav.debug_state()
	_check(state.cache_builds == 1 and state.visibility_queries == 16 * 15 / 2, "Immutable anchor visibility cache is compiled once")
	for repeat in 4:
		var before: Dictionary = nav.debug_state()
		var route: Array[Vector2] = nav.plan(Vector2(-48, 74), Vector2(30, -63))
		var after: Dictionary = nav.debug_state()
		_check(after.cache_builds == 1 and after.visibility_queries - before.visibility_queries == 33, "Indirect planning adds exactly2N endpoint links plus direct query, not anchor recomputation")
		_check(nav.valid_route(Vector2(-48, 74), Vector2(30, -63), route), "Cached route includes a valid final target chord")
	for point in [Vector2.INF, Vector2(NAN, 0), Vector2(-72.01, 0), Vector2(72.01, 0), Vector2(0, -96.01), Vector2(0, 96.01)]:
		_check(not nav.contains(point) and not nav.visible(point, Vector2(-48, 74)) and nav.plan(point, Vector2(-48, 74)).is_empty(), "Invalid/out-of-bounds endpoint fails without legacy-bound widening")
	_check(nav.contains(Vector2(-48, 74)) and absf(-48) > 17 and absf(74) > 11, "Large region genuinely permits positions beyond old layouts")

func _route_fixture(nav: RefCounted, fixture: Dictionary) -> void:
	var from := _point(fixture.from)
	var target := _point(fixture.target)
	var route: Array[Vector2] = nav.plan(from, target)
	_check(nav.visible(from, target) == fixture.visible and nav.visible(target, from) == fixture.visible, "Shared symmetric LOS: " + fixture.name)
	_check(route.size() == fixture.route.size(), "Shared retained anchor count: " + fixture.name)
	for i in mini(route.size(), fixture.route.size()):
		_check(route[i] == _point(nav.region.anchors[int(fixture.route[i])]), "Shared Dijkstra ordered/tied anchor choice: " + fixture.name)
	if nav.contains(from) and nav.contains(target):
		_check(nav.valid_route(from, target, route), "Shared route has complete dry coverage: " + fixture.name)

func _double(hex: String) -> float:
	_check(RegEx.create_from_string("^[0-9a-fA-F]{16}$").search(hex) != null, "Binary64 fixture has exactly16 hexadecimal digits")
	var bytes := hex.hex_decode()
	bytes.reverse()
	return bytes.decode_double(0)

func _boundaries(nav: RefCounted, fixtures: Array) -> void:
	_check(_double("3ff0000000000000") == 1.0, "Exact IEEE754 decoder byte order")
	var decimal_differences := 0
	for fixture: Dictionary in fixtures:
		var ax := _double(fixture.from_bits.x)
		var ay := _double(fixture.from_bits.y)
		var bx := _double(fixture.target_bits.x)
		var by := _double(fixture.target_bits.y)
		_check(nav.visible_xy(ax, ay, bx, by) == fixture.visible and nav.visible_xy(bx, by, ax, ay) == fixture.visible, "Exact scalar boundary: " + fixture.name)
		var route: Array[Vector2] = nav.plan_xy(ax, ay, bx, by)
		_check(route.size() == fixture.route.size(), "Exact scalar boundary route size: " + fixture.name)
		for i in mini(route.size(), fixture.route.size()):
			_check(route[i] == _point(nav.region.anchors[int(fixture.route[i])]), "Exact scalar boundary anchor choice: " + fixture.name)
		if fixture.from.x != ax or fixture.from.y != ay or fixture.target.x != bx or fixture.target.y != by:
			decimal_differences += 1
		if not fixture.visible:
			continue
		# Deliberately use REAL JSON decimal -> float32 presentation separately.
		var raw_from := _point(fixture.from)
		var raw_target := _point(fixture.target)
		var from: Vector2 = nav.presentation_point(raw_from)
		var target: Vector2 = nav.presentation_point(raw_target)
		_check(from.distance_to(raw_from) <= Navigation.presentation_band(raw_from) * 3 and target.distance_to(raw_target) <= Navigation.presentation_band(raw_target) * 3, "Float32 recovery stays within the explicit coordinate-scaled display band")
		_check(nav.contains(from) and nav.contains(target), "Display recovery never bypasses strict geometry predicates")
		_walk(nav, from, target, 0.08)
	print("REGION_BOUNDARIES:28 exact fixtures, %d JSON decimal-rounding differences; strict presentation walks checked separately" % decimal_differences)

func _geometry(nav: RefCounted, data: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 708016
	var legal := 0
	for trial in 600:
		var point := Vector2(rng.randf_range(-74, 74), rng.randf_range(-98, 98))
		_check(nav.contains(point) == _independent_contains(point, data), "Independent explicit-edge union membership")
		var target := Vector2(rng.randf_range(-74, 74), rng.randf_range(-98, 98))
		_check(nav.visible(point, target) == nav.visible(target, point), "Randomized full-segment visibility is symmetric")
		if not nav.contains(point) or not nav.contains(target):
			continue
		legal += 1
		var route: Array[Vector2] = nav.plan(point, target)
		_check(nav.valid_route(point, target, route), "Randomized legal pair has a complete unique-anchor route")
		if nav.visible(point, target):
			for i in 21:
				_check(_independent_contains(point.lerp(target, i / 20.0), data), "A reported visible chord does not cross sampled dry-union gaps")
	_check(legal >= 100, "Randomized coverage includes enough valid long-region pairs")

func _independent_contains(point: Vector2, data: Dictionary) -> bool:
	if not point.is_finite() or point.x < data.bounds.min.x or point.x > data.bounds.max.x or point.y < data.bounds.min.y or point.y > data.bounds.max.y:
		return false
	for c in data.clearings:
		var dx: float = point.x - c.center.x
		var dy: float = point.y - c.center.y
		if dx * dx + dy * dy <= float(c.radius) * float(c.radius):
			return true
	for edge in data.corridors:
		var a: Dictionary = data.anchors[int(edge.a)]
		var b: Dictionary = data.anchors[int(edge.b)]
		var dx: float = b.x - a.x
		var dy: float = b.y - a.y
		var t := clampf(((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy), 0, 1)
		var ex: float = point.x - (a.x + dx * t)
		var ey: float = point.y - (a.y + dy * t)
		if ex * ex + ey * ey <= float(edge.half_width) * float(edge.half_width):
			return true
	return false

func _validation(data: Dictionary) -> void:
	var tiny := {"recipe_id": "small_squared_length", "bounds": {"min": {"x": -1.0, "y": -1.0}, "max": {"x": 1.0, "y": 1.0}}, "anchors": [{"x": 0.0, "y": 0.0}, {"x": 1e-200, "y": 0.0}], "corridors": [{"a": 0, "b": 1, "half_width": 0.25}], "clearings": []}
	_check(tiny.anchors[0].x != tiny.anchors[1].x and Navigation._dot(1e-200, 0, 1e-200, 0) == 0, "Underflow fixture has distinct anchors but exactly zero computed length squared")
	var rejected := Navigation.new(tiny)
	_check(not rejected.valid and rejected.debug_state().cache_builds == 0, "Exact-zero squared length is rejected before nearest-point division/cache construction")
	tiny.anchors[1].x = 1e-150
	_check(Navigation.validate_geometry(tiny).is_empty(), "Positive representable tiny squared length is accepted; no geometric epsilon")
	for value in [null, [], {}, {"recipe_id": "broken"}]:
		_check(not Navigation.validate_geometry(value).is_empty() and not Navigation.new(value).valid, "Incomplete/non-object region rejected without falling back to default geometry")
	for path in [["bounds"], ["bounds", "min"], ["anchors"], ["anchors", 0], ["anchors", 0, "x"], ["corridors"], ["corridors", 0], ["corridors", 0, "a"], ["corridors", 0, "half_width"], ["clearings"], ["clearings", 0], ["clearings", 0, "center"], ["clearings", 0, "radius"]]:
		for replacement in [null, true, "bad", INF]:
			var bad: Dictionary = data.duplicate(true)
			var cursor: Variant = bad
			for i in range(path.size() - 1):
				cursor = cursor[path[i]]
			cursor[path[-1]] = replacement
			var invalid := Navigation.new(bad)
			_check(not invalid.valid and not invalid.contains(Vector2.ZERO) and invalid.plan(Vector2.ZERO, Vector2.ONE).is_empty(), "Malformed geometry fails closed before cache allocation")
	var disconnected: Dictionary = data.duplicate(true)
	disconnected.corridors = [{"a": 0, "b": 1, "half_width": 10}]
	_check(not Navigation.new(disconnected).valid, "Disconnected graph rejected")
	var duplicate: Dictionary = data.duplicate(true)
	duplicate.corridors.append({"a": 1, "b": 0, "half_width": 10})
	_check(not Navigation.new(duplicate).valid, "Reversed duplicate edge rejected")
	var off_anchor: Dictionary = data.duplicate(true)
	off_anchor.clearings[0].center.x += 0.1
	_check(not Navigation.new(off_anchor).valid, "Clearing must sit at an exact canonical anchor")

func _retained(nav: RefCounted) -> void:
	var from := Vector2(-48, 74)
	var target := Vector2(30, -63)
	var route: Array[Vector2] = nav.plan(from, target)
	var saved := route.duplicate()
	_check(not route.is_empty(), "Retention fixture actually needs routed navigation")
	if route.is_empty():
		return
	for repeat in 20:
		nav.next_waypoint(from, target, route)
		_check(route == saved, "Repeated identical target observation preserves accepted queue")
	var encoded := []
	for point in route:
		encoded.append({"x": point.x, "y": point.y})
	_check(nav.decode_route(encoded, target) == route and nav.valid_route(from, target, route), "Exact snapshot route decodes and validates every leg")
	for bad in [null, {}, [1], [{"x": true, "y": 0}], [{"x": "10", "y": -40}], [{"x": INF, "y": 0}], [{"x": 10.00000000001, "y": -40}], encoded + encoded, [{"x": target.x, "y": target.y}]]:
		_check(nav.decode_route(bad, target).is_empty(), "Malformed/noncanonical/repeated/target-retaining queue rejected")
	var empty: Array[Vector2] = []
	_check(not nav.valid_route(from, target, empty), "Empty route is invalid when final chord crosses dry-union gaps")
	var broken: Array[Vector2] = [Vector2(500, 500)]
	_check(nav.next_waypoint(from, target, broken) == saved[0] and broken == saved, "Invalid pending route replans once to canonical queue")
	_check(nav.next_waypoint(from, from + Vector2.ONE, route) == from + Vector2.ONE and route.is_empty(), "New direct chord clears obsolete anchors")
	var direct_target := from + Vector2.ONE
	var direct: Dictionary = nav.validated_route([], from, direct_target)
	_check(direct.ok and direct.route.is_empty(), "Genuine empty wire queue is accepted for a legal direct chord")
	_check(not nav.validated_route([], from, target).ok, "Genuine empty wire queue is rejected for an occluded target")
	for bad in [null, {}, "bad", [1], [{"x": true, "y": 0}], [{"x": "10", "y": -40}], [{"x": 0, "y": 0}], [{"x": -25, "y": 43, "extra": 1}], [{"x": -25, "y": 43}, {"x": -25, "y": 43}], [{"x": direct_target.x, "y": direct_target.y}]]:
		var result: Dictionary = nav.validated_route(bad, from, direct_target)
		_check(not result.ok and result.route.is_empty(), "Malformed nonempty wire queue cannot masquerade as an empty direct route")
	_check(nav.validated_route(encoded, from, target).ok, "Valid encoded indirect route remains accepted by explicit wire API")
	_check(not nav.validated_route([], Vector2.INF, direct_target).ok and not nav.validated_route([], from, Vector2.INF).ok, "Wire route validates both endpoint domains")
	var invalid_point := Vector2(72.1, 96.1)
	_check(nav.presentation_point(invalid_point) == invalid_point, "Display correction never rescues genuinely invalid taps")

func _walk(nav: RefCounted, from: Vector2, target: Vector2, stride: float) -> void:
	var point := from
	var route: Array[Vector2] = nav.plan(point, target)
	for step in 6000:
		var waypoint: Vector2 = nav.next_waypoint(point, target, route)
		var next := point.move_toward(waypoint, stride)
		if not nav.visible(point, next) or not nav.visible(next, point) or next.distance_to(point) > stride + 0.00003:
			_check(false, "Complete walk crosses strict geometry or exceeds step bound")
			return
		if next == point and point.distance_to(target) > 0.08:
			_check(false, "Complete walk stalls at %s from %s to %s" % [point, from, target])
			return
		point = next
		if point.distance_to(target) <= 0.04:
			break
	_check(point.distance_to(target) <= 0.08, "Complete bounded walk reaches target")
	walks += 1
