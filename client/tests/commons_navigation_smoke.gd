extends SceneTree
## Explicit-fork correspondence, shared scalar fixtures and retained dry routes.

const Navigation = preload("res://scripts/commons_navigation.gd")
const ANCHORS: Array[Vector2] = [Vector2(-5, 0), Vector2(0, 0), Vector2(4, -4), Vector2(10, -6), Vector2(4, 4), Vector2(10, 6)]
const EDGES := [[0, 1], [1, 2], [2, 3], [1, 4], [4, 5]]
const CLEARINGS: Array[Vector3] = [Vector3(-5, 0, 7.2), Vector3(10, -6, 4.8), Vector3(10, 6, 4.8)]
var checks := 0
var failures := 0
var motion_routes := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_contract()
	_geometry()
	_decoding()
	var shared_routes := _shared_routes()
	var boundary_fixtures := _boundaries()
	_motion()
	_randomized()
	print("COMMONS_NAVIGATION_SMOKE: %d checks, %d failures; declared fork correspondence, %d shared routes/%d scalar boundaries, %d full two-way/frequency walks, strict wedge rejection and retained queues" % [checks, failures, shared_routes, boundary_fixtures, motion_routes])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("COMMONS_NAVIGATION_FAILED: " + message)

func _edge(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func _corresponds(traversal: Array) -> bool:
	var declared: Dictionary = {}
	for edge: Array in EDGES:
		declared[_edge(edge[0], edge[1])] = true
	var seen: Dictionary = {}
	for index in range(traversal.size() - 1):
		var key := _edge(traversal[index], traversal[index + 1])
		if not declared.has(key):
			return false
		seen[key] = true
	return seen.size() == declared.size()

func _contract() -> void:
	var commons := Navigation.default_commons()
	_check(commons.keys().size() == 4 and commons.corridors == EDGES, "exact explicit corridor wire fields")
	_check(commons.anchors.size() == 6 and commons.clearings.size() == 3 and commons.half_width == 3.6, "six anchors/three clearings and canonical width")
	for index in ANCHORS.size():
		_check(Vector2(commons.anchors[index].x, commons.anchors[index].y) == ANCHORS[index], "exact anchor order")
	for index in CLEARINGS.size():
		var clearing: Dictionary = commons.clearings[index]
		_check(Vector3(clearing.center.x, clearing.center.y, clearing.radius) == CLEARINGS[index], "exact clearing order and radii")
	_check(Navigation.TRAVERSAL == [0, 1, 2, 3, 2, 1, 4, 5] and _corresponds(Navigation.TRAVERSAL), "ordered adapter traverses every and only declared edge")
	_check(not _corresponds([0, 1, 2, 3, 4, 5]), "negative control: sequential anchors invent a 3->4 capsule")
	_check(not _corresponds([0, 1, 2, 3, 2, 1]), "negative control: traversal cannot omit the other arm")
	var geometry := Navigation.corridor(commons)
	for index in Navigation.TRAVERSAL.size():
		_check(geometry.spine[index] == commons.anchors[Navigation.TRAVERSAL[index]], "adapter geometry follows exact declared traversal")
	var layout := Navigation.layout()
	_check(layout.size() == 4 and layout.version == 6 and layout.bridge_y == 0 and layout.gate_y == 0 and layout.commons == commons, "v6 has no invented legacy feature or objective")
	commons.anchors[0].x = 999.0
	commons.corridors[0][1] = 5
	commons.clearings[0].radius = 999.0
	_check(Navigation.default_commons().anchors[0].x == -5.0 and Navigation.default_commons().corridors == EDGES and Navigation.default_commons().clearings[0].radius == 7.2, "canonical defaults must deep-copy mutable wire arrays")
	_check(layout.commons.anchors[0].x == -5.0 and layout.commons.clearings[0].radius == 7.2, "returned layouts must not alias other defaults")

func _distance_squared(px: float, py: float, a: Vector2, b: Vector2) -> float:
	var dx := float(b.x) - float(a.x)
	var dy := float(b.y) - float(a.y)
	var fraction := clampf(((px - a.x) * dx + (py - a.y) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
	var x := px - (a.x + fraction * dx)
	var y := py - (a.y + fraction * dy)
	return x * x + y * y

func _independent_contains(point: Vector2) -> bool:
	if not point.is_finite() or absf(point.x) > 17 or absf(point.y) > 11:
		return false
	for clearing in CLEARINGS:
		var dx := float(point.x) - clearing.x
		var dy := float(point.y) - clearing.y
		if dx * dx + dy * dy <= float(clearing.z) * float(clearing.z):
			return true
	for edge: Array in EDGES:
		if _distance_squared(point.x, point.y, ANCHORS[edge[0]], ANCHORS[edge[1]]) <= 3.6 * 3.6:
			return true
	return false

func _geometry() -> void:
	for x in range(-34, 35):
		for y in range(-22, 23):
			var point := Vector2(x * 0.5, y * 0.5)
			_check(Navigation.contains(point) == _independent_contains(point), "adapter membership differs from independent declared-edge union at %s" % point)
	for point in [Vector2(-9, -1.5), Vector2(-9, 1.5), Vector2(-11, -2), Vector2(-11, 2), Vector2(-5, 0), Vector2(0, 0), Vector2(10, -6), Vector2(10, 6)]:
		_check(Navigation.contains(point) and Navigation.visible(point, point), "normal starting/clearing position is not walkable")
	for point in [Vector2(7, 0), Vector2(10, 0), Vector2(-13, 0), Vector2(17.01, 6), Vector2(10, 11.01), Vector2.INF, Vector2(NAN, 0)]:
		_check(not Navigation.contains(point) and not Navigation.visible(point, Vector2.ZERO) and Navigation.plan(point, Vector2.ZERO).is_empty(), "outside fork/world/nonfinite endpoint accepted")
	var false_spine: Array = Navigation.COMMONS.anchors.duplicate(true)
	var bad_geometry := {"spine": false_spine, "half_width": 3.6, "shelves": Navigation.COMMONS.clearings}
	_check(Navigation.Union.contains(Vector2(7, 0), bad_geometry) and not Navigation.contains(Vector2(7, 0)), "negative control must reveal phantom sequential-spine ground")
	_check(not Navigation.visible(ANCHORS[3], ANCHORS[4]) and not Navigation.visible(ANCHORS[3], ANCHORS[5]), "valid clearing endpoints cannot shortcut the gap between arms")
	var rounded := Vector2(14.8, -6)
	_check(not Navigation.contains(rounded), "float32 outside-boundary fixture must exercise actual rounding")
	var corrected := Navigation.presentation_point(rounded)
	_check(corrected.distance_to(rounded) <= 0.00002 and Navigation.contains(corrected), "narrow presentation-only boundary recovery")
	_check(Navigation.presentation_point(Vector2(15, -6)) == Vector2(15, -6) and Navigation.presentation_point(Vector2(7, 0)) == Vector2(7, 0), "presentation correction cannot teleport genuinely invalid taps")
	_check(Navigation.presentation_point(Vector2.INF) == Vector2.INF, "nonfinite presentation input remains rejected")

func _decoding() -> void:
	var data := [{"x": -5, "y": 0}, {"x": 0.0, "y": 0.0}, {"x": 4, "y": -4}, {"x": 10, "y": -6}]
	var decoded := Navigation.decode_route(data)
	_check(decoded == [ANCHORS[0], ANCHORS[1], ANCHORS[2], ANCHORS[3]], "canonical mixed integer/float JSON route decodes exactly")
	decoded.pop_front()
	_check(data.size() == 4 and data[0].x == -5, "route consumption cannot mutate snapshot JSON")
	for invalid: Variant in [null, {}, [{"x": "4", "y": -4}], [{"x": true, "y": 0}], [{"x": NAN, "y": 0}], [{"x": INF, "y": 0}], [{"x": 4.0000000000001, "y": -4}], [{"x": 7, "y": 0}], [{"x": 4}], [{"x": 4, "y": -4, "extra": 1}], [{"x": 0, "y": 0}, {"x": 0, "y": 0}], [{"x": 10, "y": -6}, {"x": 4, "y": 4}], [0], data + data]:
		_check(Navigation.decode_route(invalid).is_empty(), "malformed/noncanonical/duplicate/unsafe route must reject completely")
	var source := Vector2(10, -6)
	var target := Vector2(10, 6)
	var queue := Navigation.plan(source, target)
	var saved := queue.duplicate()
	_check(not saved.is_empty(), "retained route fixture must actually go around the branch gap")
	for repeat in 20:
		Navigation.next_waypoint(source, target, queue)
		_check(queue == saved, "duplicate observation cannot reshuffle a retained route")
	var invalid_queue: Array[Vector2] = [Vector2(7, 0)]
	Navigation.next_waypoint(source, target, invalid_queue)
	_check(invalid_queue == saved, "unusable queue must replan to a safe canonical route")
	var direct_queue: Array[Vector2] = [Vector2.ZERO]
	_check(Navigation.next_waypoint(Vector2(-5, 0), Vector2(-4, 0), direct_queue) == Vector2(-4, 0) and direct_queue.is_empty(), "direct safe chord consumes obsolete anchors")

func _fixture_file(name: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join("../protocol/" + name)
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func _shared_routes() -> int:
	var fixtures: Variant = _fixture_file("commons-routes.json")
	_check(fixtures is Array and fixtures.size() == 32, "all 32 shared Go/Godot route fixtures must be present")
	if not fixtures is Array:
		return 0
	for fixture: Dictionary in fixtures:
		var from := Vector2(fixture.from.x, fixture.from.y)
		var target := Vector2(fixture.target.x, fixture.target.y)
		var route := Navigation.plan(from, target)
		_check(Navigation.visible(from, target) == fixture.visible and route.size() == fixture.route.size(), "shared route/visibility mismatch: " + fixture.name)
		for index in mini(route.size(), fixture.route.size()):
			_check(route[index] == ANCHORS[int(fixture.route[index])], "shared canonical anchor choice mismatch: " + fixture.name)
	return fixtures.size()

func _boundaries() -> int:
	var fixtures: Variant = _fixture_file("commons-boundaries.json")
	_check(fixtures is Array and fixtures.size() == 20, "all 20 shared exact-boundary fixtures must be present")
	if not fixtures is Array:
		return 0
	_check(_decode_double("3ff0000000000000") == 1.0, "fixture IEEE754 byte order must decode exactly")
	var decimal_changes := 0
	for fixture: Dictionary in fixtures:
		var a: Dictionary = fixture.from
		var b: Dictionary = fixture.target
		# Godot4.6.3 decimal decoding can round a deliberate one-ULP-inside
		# value to its adjacent OUTSIDE double (e.g.10.799999999999999).
		# Go asserts original JSON numbers match these exact IEEE754 companions.
		# Use their unchanged bits for geometry-law parity, not a decimal golden
		# or a collision epsilon. Exercise the real JSON pipeline separately below.
		var exact_a := _exact_point(fixture.get("from_bits", {}))
		var exact_b := _exact_point(fixture.get("target_bits", {}))
		var forward := Navigation._visible_coordinates(exact_a.x, exact_a.y, exact_b.x, exact_b.y)
		var reverse := Navigation._visible_coordinates(exact_b.x, exact_b.y, exact_a.x, exact_a.y)
		_check(forward == fixture.visible and reverse == fixture.visible, "exact IEEE754 scalar boundary mismatch: " + fixture.name)
		if a.x != exact_a.x or a.y != exact_a.y or b.x != exact_b.x or b.y != exact_b.y:
			decimal_changes += 1
		if not fixture.visible:
			continue
		# These come from REAL JSON decoding, deliberately not exact_a/exact_b.
		# Convert to the actual float32 presentation type, correct only its old
		# narrow display band and complete normal strict movement to the target.
		var raw_from := Vector2(a.x, a.y)
		var raw_target := Vector2(b.x, b.y)
		var from := Navigation.presentation_point(raw_from)
		var target := Navigation.presentation_point(raw_target)
		_check(from.distance_to(raw_from) <= 0.00002 and target.distance_to(raw_target) <= 0.00002 and Navigation.contains(from) and Navigation.contains(target), "bounded boundary presentation recovery: " + fixture.name)
		_walk(from, target, 20.0)
	print("COMMONS_BOUNDARIES: 20 bit-exact scalar fixtures; %d decimal decoder differences, real JSON/float32 presentation walks remain strict" % decimal_changes)
	return fixtures.size()

func _decode_double(hex: String) -> float:
	var valid := RegEx.create_from_string("^[0-9a-fA-F]{16}$").search(hex) != null
	_check(valid, "exact fixture requires a 16-hex IEEE754 double")
	if not valid:
		return NAN
	var bytes := hex.hex_decode()
	bytes.reverse() # Companion bits are conventional big-endian; PackedByteArray is LE.
	return bytes.decode_double(0)

func _exact_point(bits: Dictionary) -> Dictionary:
	_check(bits.size() == 2 and bits.has("x") and bits.has("y"), "exact coordinate companions must include both x and y")
	return {"x": _decode_double(String(bits.get("x", ""))), "y": _decode_double(String(bits.get("y", "")))}

func _walk(from: Vector2, target: Vector2, frequency: float) -> void:
	var point := from
	var route := Navigation.plan(from, target)
	for frame in 1600:
		var remaining := 4.0 / frequency
		while remaining > 0.00001:
			var stride := minf(remaining, 0.08)
			var next := point.move_toward(Navigation.next_waypoint(point, target, route), stride)
			if not Navigation.visible(point, next) or not Navigation.visible(next, point) or point.distance_to(next) > stride + 0.000002:
				_check(false, "full motion crossed outside strict fork or exceeded speed")
				return
			point = next
			remaining -= stride
		if point.distance_to(target) <= 0.04:
			break
	_check(point.distance_to(target) <= 0.08, "full motion stalled: %s -> %s at %s (%sHz)" % [from, target, point, frequency])
	motion_routes += 1

func _motion() -> void:
	var pairs := [[Vector2(-9, 0), Vector2(10, -6)], [Vector2(-9, 0), Vector2(10, 6)], [Vector2(10, -6), Vector2(10, 6)], [Vector2(14, -7), Vector2(14, 7)], [Vector2(-9, 4), Vector2(12, -9)]]
	for pair: Array in pairs:
		for frequency in [4.0, 20.0, 60.0]:
			_walk(pair[0], pair[1], frequency)
			_walk(pair[1], pair[0], frequency)

func _randomized() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 140614
	var valid := 0
	for trial in 1200:
		var from := Vector2(rng.randf_range(-17, 17), rng.randf_range(-11, 11))
		var target := Vector2(rng.randf_range(-17, 17), rng.randf_range(-11, 11))
		_check(Navigation.visible(from, target) == Navigation.visible(target, from), "random complete-segment visibility must be symmetric")
		if not Navigation.contains(from) or not Navigation.contains(target):
			continue
		var previous := from
		var route := Navigation.plan(from, target)
		var seen: Array[Vector2] = []
		_check(route.size() <= 6, "random planner must retain at most six unique canonical anchors")
		for anchor in route:
			_check(ANCHORS.has(anchor) and not seen.has(anchor) and anchor != target and Navigation.visible(previous, anchor), "random route must have safe canonical unique anchors")
			seen.append(anchor)
			previous = anchor
		_check(Navigation.visible(previous, target), "random valid endpoints must have a complete connected route")
		valid += 1
	_check(valid >= 150, "randomized test needs enough complete legal fork routes")
	print("COMMONS_RANDOMIZED: 1200 symmetric pairs / %d complete legal routes" % valid)
