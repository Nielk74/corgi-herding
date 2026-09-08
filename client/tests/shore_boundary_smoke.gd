extends SceneTree
## V5 exact-boundary regression: scalar Go/Godot parity before float32 presentation.

const Navigation = preload("res://scripts/shore_navigation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var file := ProjectSettings.globalize_path("res://").path_join("../protocol/shore-boundaries.json")
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not fixtures is Array or fixtures.size() != 14:
		_fail("14 boundary fixtures required")
		return
	for fixture in fixtures:
		var a: Dictionary = fixture.from
		var b: Dictionary = fixture.target
		# Do not round these reproductions into Vector2 before comparing scalar
		# geometry. The failing Linux point is on the exact double boundary.
		if Navigation._visible_coordinates(a.x, a.y, b.x, b.y, Navigation.CORRIDOR) != fixture.visible or Navigation._visible_coordinates(b.x, b.y, a.x, a.y, Navigation.CORRIDOR) != fixture.visible:
			_fail("scalar boundary parity: " + fixture.name)
			return
		if not fixture.visible:
			continue
		var raw_from := Vector2(a.x, a.y)
		var raw_target := Vector2(b.x, b.y)
		var point := Navigation.presentation_point(raw_from)
		var target := Navigation.presentation_point(raw_target)
		if point.distance_to(raw_from) > 0.00002 or target.distance_to(raw_target) > 0.00002 or not Navigation.contains(point) or not Navigation.contains(target):
			_fail("float32 presentation correction changed the footprint")
			return
		var route := Navigation.plan(point, target)
		for step in 1000:
			if point.distance_to(target) <= 0.04:
				break
			var next := point.move_toward(Navigation.next_waypoint(point, target, route), 0.08)
			if not Navigation.visible(point, next) or not Navigation.visible(next, point):
				_fail("boundary prediction lost symmetric containment")
				return
			point = next
		if point.distance_to(target) > 0.08:
			_fail("boundary prediction stalled: " + fixture.name)
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = 13130
	var checked := 0
	for trial in 4000:
		var a := Vector2(rng.randf_range(-17, 17), rng.randf_range(-11, 11))
		var b := Vector2(rng.randf_range(-17, 17), rng.randf_range(-11, 11))
		if Navigation.visible(a, b) != Navigation.visible(b, a):
			_fail("randomized visibility is asymmetric")
			return
		if not Navigation.contains(a) or not Navigation.contains(b):
			continue
		var p := a
		var route := Navigation.plan(a, b)
		for anchor in route:
			if not Navigation.visible(p, anchor):
				_fail("randomized route has an unsafe segment")
				return
			p = anchor
		if not Navigation.visible(p, b):
			_fail("randomized legal endpoints have no complete route")
			return
		checked += 1
	print("PASS: 14 exact shore boundary fixtures, float32 motion, 4000 symmetric pairs, %d connected legal routes" % checked)
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
