extends "res://tests/region_nav_smoke.gd"

const Catalog = preload("res://scripts/region_catalog.gd")
const CANONICAL_SHA256 := "a17b3f8734cf8aed2377986077bf6104fcb96d9535fdf6b7725dc08725b25f54"

func _run() -> void:
	fixture_directory = ProjectSettings.globalize_path("res://").path_join("../protocol")
	var nav := Navigation.new(_read("dry-wash-region.json"))
	_check(nav.valid, "Dry-wash generic region validates")
	_catalog(nav)
	var routes: Array = _read("dry-wash-routes.json")
	var boundaries: Array = _read("dry-wash-boundaries.json")
	_check(routes.size() == 64 and boundaries.size() == 36, "All v8 fixtures present")
	for fixture: Dictionary in routes:
		_route_fixture(nav, fixture)
		if nav.contains(_point(fixture.from)) and nav.contains(_point(fixture.target)):
			_walk(nav, _point(fixture.from), _point(fixture.target), 0.08)
	for fixture: Dictionary in boundaries:
		var ax := _double(fixture.from_bits.x)
		var ay := _double(fixture.from_bits.y)
		var bx := _double(fixture.target_bits.x)
		var by := _double(fixture.target_bits.y)
		_check(nav.visible_xy(ax, ay, bx, by) == fixture.visible and nav.visible_xy(bx, by, ax, ay) == fixture.visible, "Exact boundary LOS " + fixture.name)
		var route: Array[Vector2] = nav.plan_xy(ax, ay, bx, by)
		_check(route.size() == fixture.route.size(), "Exact boundary route count " + fixture.name)
		for i in mini(route.size(), fixture.route.size()):
			_check(route[i] == _point(nav.region.anchors[int(fixture.route[i])]), "Exact boundary anchor " + fixture.name)
		if fixture.visible:
			var raw_from := _point(fixture.from)
			var raw_target := _point(fixture.target)
			var from: Vector2 = nav.presentation_point(raw_from)
			var target: Vector2 = nav.presentation_point(raw_target)
			_check(nav.contains(from) and nav.contains(target), "Real JSON/Vector2 correction stays strictly dry")
			_check(from.distance_to(raw_from) <= Navigation.presentation_band(raw_from) * 3 and target.distance_to(raw_target) <= Navigation.presentation_band(raw_target) * 3, "Correction remains bounded")
			_walk(nav, from, target, 0.08)
	print("DRY_WASH_NAV_SMOKE: %d checks / %d failures; 64 routes, 36 IEEE boundaries, %d complete real-Vector2 walks; immutable registered graph and unchanged scalar math" % [checks, failures, walks])
	quit(1 if failures else 0)

func _catalog(nav: RefCounted) -> void:
	var bundled := "res://worlds/regions/dry_wash_01.json"
	_check(FileAccess.get_sha256(bundled) == CANONICAL_SHA256 and FileAccess.get_sha256(fixture_directory.path_join("dry-wash-region.json")) == CANONICAL_SHA256, "Bundled canonical graph is byte-identical to approved authoritative fixture")
	var canonical: Dictionary = Catalog.canonical("dry_wash")
	_check(Catalog.matches(canonical, nav.region) and canonical.anchors.size() == 14, "Registered v8 graph is the exact fourteen-anchor canonical world")
	var alpine: Dictionary = Catalog.canonical("alpine_valley")
	_check(Catalog.matches(alpine, Navigation.default_region()) and alpine.anchors.size() == 16, "Existing v7 canonical graph remains exactly unchanged")
	canonical.anchors[0].x = 500
	var exposed := Catalog.entry("dry_wash")
	exposed.dogs.clear()
	var layout := Catalog.layout("dry_wash")
	layout.region.bounds.min.x = -1000
	_check(Catalog.matches(Catalog.canonical("dry_wash"), nav.region) and Catalog.entry("dry_wash").dogs.size() == 2 and Catalog.matches(alpine, Catalog.canonical("alpine_valley")), "Caller mutation cannot cross either recipe cache or its spawn metadata")
	_check(Catalog.canonical("future_region").is_empty() and Catalog.layout("future_region").is_empty(), "Generic valid geometry is not permission to register an unknown wire world")
	var state: Dictionary = nav.debug_state()
	_check(state.cache_builds == 1 and state.visibility_queries == 14 * 13 / 2, "DryWash compiles its own immutable fourteen-anchor cache exactly once")
	for repeat in 4:
		var before: Dictionary = nav.debug_state()
		var route: Array[Vector2] = nav.plan(Vector2(-44, 79), Vector2(32, -76))
		var after: Dictionary = nav.debug_state()
		_check(after.cache_builds == 1 and after.visibility_queries - before.visibility_queries == 29 and nav.valid_route(Vector2(-44, 79), Vector2(32, -76), route), "Indirect v8 plan adds2N+1 endpoint links with no Alpine cache reuse")
	var far := Vector2(32, -76)
	var camp := Vector2(-44, 79)
	var queue: Array[Vector2] = nav.plan(camp, far)
	var encoded: Array = []
	for point: Vector2 in queue: encoded.append({"x": point.x, "y": point.y})
	_check(not queue.is_empty() and nav.validated_route(encoded, camp, far).ok, "Whole retained v8 queue includes valid source and final chords")
	var too_long: Array = []
	for i in 15: too_long.append({"x": nav.region.anchors[i % 14].x, "y": nav.region.anchors[i % 14].y})
	_check(not nav.validated_route(too_long, camp, far).ok, "V8 route length is bounded by its own14 anchors, not v7's16")
	_check(not nav.validated_route([], camp, far).ok and not nav.validated_route([{"x": -25, "y": 43}], camp, far).ok, "Blocked final chord and an old v7-only anchor are rejected")
