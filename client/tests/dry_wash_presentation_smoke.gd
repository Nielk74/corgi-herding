extends "res://tests/region_presentation_smoke.gd"
## V8-only extension of the independent stored-triangle reference harness.
## No altered Alpine assertions, live server, saved herd or authoring edits.
const Catalog = preload("res://scripts/region_catalog.gd")
const CAMP := Vector2(-44, 79)
const WALK_TARGETS := [Vector2(32, -76), Vector2(47, -5), Vector2(22, 57),
	Vector2(-51, -57), Vector2(-48, -18), Vector2(-51, 40), CAMP]
var clearing_views := 0
var walk_results := {}
var route_completions := 0
var stopped_frames := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 30:
			printerr("DRY_WASH_PRESENTATION_FAILED: " + message)

func _portrait(size: Vector2i) -> void:
	root.content_scale_size = size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = size
	await process_frame
	# Headless startup may reset the physical window once. Never test a claimed
	# portrait aspect using an inherited desktop framebuffer.
	root.size = size
	await process_frame
	_check(root.size == size and root.get_visible_rect().size == Vector2(size),
		"Both actual physical and logical viewport are " + str(size))

func _assert_pick(point: Vector2, context: String, moving := false) -> void:
	var ground := _ground(point)
	var screen: Vector2 = meadow.camera.unproject_position(ground)
	var viewport: Vector2 = root.get_visible_rect().size
	_check(ground.is_finite() and not meadow.camera.is_position_behind(ground)
		and screen.x > viewport.x * 0.02 and screen.x < viewport.x * 0.98
		and screen.y > viewport.y * 0.02 and screen.y < viewport.y * 0.98,
		"Local terrain feet stay inside the real portrait frame: " + context)
	var origin: Vector3 = meadow.camera.project_ray_origin(screen)
	var direction: Vector3 = meadow.camera.project_ray_normal(screen)
	var rendered := _nearest_rendered(origin, direction)
	var picked: Vector3 = meadow.ground_at(screen)
	var detail := "%s point%s camera%s lift%.4f required%.4f nearest%s picked%s" % [context,
		point, meadow.camera.position, meadow.region_presentation.camera_lift,
		meadow.region_presentation.required_lift, rendered, picked]
	_check(rendered.is_finite() and rendered.distance_to(ground) < 0.06,
		"Independent nearest stored terrain reaches the local feet: " + detail)
	_check(picked.is_finite() and picked.distance_to(ground) < 0.06
		and picked.distance_to(rendered) < 0.06,
		"Production picking agrees with the actual visible terrain: " + detail)
	if moving:
		moving_picks += 1

func _mesh_samples(region: Dictionary) -> void:
	var samples: Array[Vector2] = []
	for anchor: Dictionary in region.anchors:
		samples.append(_point(anchor))
	for edge: Dictionary in region.corridors:
		samples.append((_point(region.anchors[int(edge.a)]) + _point(region.anchors[int(edge.b)])) * 0.5)
	var low := INF
	var high := -INF
	for point in samples:
		var expected := _ground(point)
		low = minf(low, expected.y)
		high = maxf(high, expected.y)
		var origin := expected + Vector3.UP * 30
		var rendered := _nearest_rendered(origin, Vector3.DOWN, 60)
		var picked: Vector3 = meadow.region_presentation.ray_ground(origin, Vector3.DOWN, 60)
		_check(rendered.is_finite() and rendered.distance_to(expected) < 0.015,
			"Every dry anchor and corridor center sits on the real stored terrain")
		_check(picked.is_finite() and picked.distance_to(rendered) < 0.03,
			"Vertical route pick agrees with independent rendered triangles")
		var normal: Vector3 = meadow.surface_normal(point.x, point.y)
		_check(normal.is_finite() and absf(normal.length() - 1) < 0.00001 and normal.y > 0,
			"Dry route feet and markers receive finite upward terrain normals")
	# The immutable dry recipe grades0→15m; it is not Alpine's>20m ascent.
	_check(samples.size() == 27 and high - low > 13,
		"All14 anchors/13 corridors expose the dry recipe's substantial actual relief")
	print("DRY_WASH_PRESENTATION_RELIEF: %d route samples, %.4f..%.4fm" % [samples.size(), low, high])
	for point in [Vector2(-100, 64), Vector2(100, 0), Vector2(0, 120), Vector2(-180, -124), Vector2(100, -200)]:
		var origin := Vector3(point.x, 300, point.y)
		var rendered := _nearest_rendered(origin, Vector3.DOWN, 600)
		_check(rendered.is_finite(), "Negative-control ray actually hits apron/scenery")
		_check(not meadow.region_navigation.contains(point)
			and not meadow.region_presentation.ray_ground(origin, Vector3.DOWN, 600).is_finite(),
			"Rendered ground outside the canonical wash never becomes a walking tap")
		occlusion_cases += 1

func _rest(point: Vector2, delta: float, context: String) -> void:
	meadow.follow_player(_ground(point) + Vector3.UP * 0.03, false)
	var stopped: Vector3 = meadow.camera_focus
	var pose: Transform3D = meadow.camera.transform
	var lift: float = meadow.region_presentation.camera_lift
	for i in 90:
		meadow.follow_player(_ground(point) + Vector3(sin(i) * 0.03, cos(i) * 0.2, cos(i) * 0.03), false)
		meadow._process(delta)
		_check(meadow.camera_focus == stopped and meadow.desired_focus == stopped
			and meadow.camera.transform == pose and meadow.region_presentation.camera_lift == lift,
			"Rest freezes full camera pose without settling/oscillation: " + context)
		stopped_frames += 1

func _nearest_occlusion(region: Dictionary) -> void:
	# Alpine's46–55m ray origins see over these deliberately low dry banks.
	# Start above actual outer-bank terrain instead, never inside it, and require
	# the independent triangle reference to prove a real nearer illegal surface.
	var probes := 0
	for point in [Vector2(-90, 75), Vector2(85, 65), Vector2(-85, 10),
		Vector2(80, -25), Vector2(-82, -65), Vector2(75, -100),
		Vector2(0, 115), Vector2(0, -115), Vector2(-100, 40), Vector2(100, -70)]:
		var floor_hit := _nearest_rendered(Vector3(point.x, 300, point.y), Vector3.DOWN)
		_check(floor_hit.is_finite(), "Oblique negative fixture starts above actual dry terrain")
		if not floor_hit.is_finite():
			continue
		var origin := floor_hit + Vector3.UP * 1.5
		for anchor: Dictionary in region.anchors:
			var target := _ground(_point(anchor))
			var direction := (target - origin).normalized()
			var rendered := _nearest_rendered(origin, direction)
			if not rendered.is_finite() or rendered.distance_to(target) < 0.25:
				continue
			if meadow.region_navigation.contains(Vector2(rendered.x, rendered.z)):
				continue
			_check(not meadow.region_presentation.ray_ground(origin, direction).is_finite(),
				"Actual nearer dry bank rejects a legal target behind it")
			probes += 1
			if probes >= 4:
				break
		if probes >= 4:
			break
	_check(probes >= 2, "Exercise real dry scenery-first rays, not only empty-sky rejection")
	occlusion_cases += probes
	_check(not meadow.region_presentation.ray_ground(Vector3.INF, Vector3.DOWN).is_finite(),
		"Nonfinite ray origin fails closed")
	_check(not meadow.region_presentation.ray_ground(Vector3.ZERO, Vector3.ZERO).is_finite(),
		"Zero ray direction fails closed")

func _camera_walk(frequency: float) -> void:
	var point := CAMP
	_place(point)
	var yaw := Vector2(meadow.camera.basis.z.x, meadow.camera.basis.z.z).normalized()
	var lens: float = meadow.camera.fov
	var initial: Vector3 = meadow.camera_focus
	var minimum := Vector2(initial.x, initial.z)
	var maximum := minimum
	var bounds: Dictionary = meadow.region_navigation.region.bounds
	var delta := 1.0 / frequency
	var frames := 0
	var results: Array[Dictionary] = []
	for target in WALK_TARGETS:
		_check(meadow.region_navigation.contains(target), "Every camera destination is canonical dry ground")
		var route: Array[Vector2] = meadow.region_navigation.plan(point, target)
		var leg := 0
		while point.distance_to(target) > 0.08 and leg < int(160 * frequency):
			var old_point := point
			var waypoint: Vector2 = meadow.region_navigation.next_waypoint(point, target, route)
			point = point.move_toward(waypoint, 4.0 * delta)
			_check(meadow.region_navigation.contains(point) and meadow.region_navigation.visible(old_point, point),
				"Ordinary4m/s camera approaches follow complete legal segments")
			var before: Vector3 = meadow.camera_focus
			var old_lift: float = meadow.region_presentation.camera_lift
			meadow.follow_player(_ground(point) + Vector3.UP * 0.03, true)
			meadow._process(delta)
			var focus: Vector3 = meadow.camera_focus
			var plane := Vector2(focus.x, focus.z)
			peak_pan = maxf(peak_pan, plane.distance_to(Vector2(before.x, before.z)) / delta)
			minimum = minimum.min(plane)
			maximum = maximum.max(plane)
			_check(focus.is_finite() and focus.x >= bounds.min.x and focus.x <= bounds.max.x
				and focus.z >= bounds.min.y - 6 and focus.z <= bounds.max.y - 6,
				"Both camera axes stay within the unchanged canonical finite bounds")
			var offset: Vector3 = meadow.camera.position - focus
			var lift: float = meadow.region_presentation.camera_lift
			var lift_change := lift - old_lift
			peak_lift = maxf(peak_lift, lift)
			peak_lift_speed = maxf(peak_lift_speed, absf(lift_change) / delta)
			_check(lift_change <= 8.0 * delta + 0.000000001 and lift_change >= -2.0 * delta - 0.000000001,
				"Every step respects the explicit8-up/2-down lift rates")
			_check(lift >= 0 and lift <= 18 and absf(offset.y - 14 - lift) < 0.0001
				and Vector2(offset.x, offset.z).distance_to(Vector2(6, 50)) < 0.0001,
				"Only the bounded18m vertical assist changes the fixed camera offset")
			_check(Vector2(meadow.camera.basis.z.x, meadow.camera.basis.z.z).normalized().distance_to(yaw) < 0.00001
				and meadow.camera.fov == lens and meadow.camera.keep_aspect == Camera3D.KEEP_WIDTH
				and meadow.camera.far == 600,
				"Walking never rotates yaw, zooms the lens or changes scenic range")
			if frames % int(frequency * 2) == 0:
				_assert_pick(point, "walk %.0fHz zoom%.2f viewport%s" % [frequency, meadow.zoom, root.get_visible_rect().size], true)
			frames += 1
			leg += 1
		_check(point.distance_to(target) <= 0.08, "Complete ordinary branch approach/return arrives without teleport")
		_assert_pick(point, "stopped at%s %.0fHz zoom%.2f" % [target, frequency, meadow.zoom], true)
		results.append({"point": point, "focus": meadow.camera_focus, "lift": meadow.region_presentation.camera_lift})
		_rest(point, delta, "destination%s at%.0fHz" % [target, frequency])
		route_completions += 1
	_check(maximum.x - minimum.x > 90 and maximum.y - minimum.y > 145,
		"Real camera loop reveals both wash branches and the long outward/return axis")
	var key := "%s/%.2f" % [root.get_visible_rect().size, meadow.zoom]
	if walk_results.has(key):
		var previous: Array = walk_results[key]
		for i in results.size():
			_check(results[i].point.distance_to(previous[i].point) < 0.09
				and results[i].focus.distance_to(previous[i].focus) < 0.35
				and absf(results[i].lift - previous[i].lift) < 0.4,
				"20/60Hz ordinary walks finish with consistent feet/focus/lift at " + str(WALK_TARGETS[i]))
	else:
		walk_results[key] = results
	print("DRY_WASH_PRESENTATION_WALK: %.0fHz zoom%.2f %s, %d frames, span%s" % [frequency, meadow.zoom, root.get_visible_rect().size, frames, maximum - minimum])

func _camera_quiet() -> void:
	_place(CAMP)
	var initial: Vector3 = meadow.camera_focus
	for i in 120:
		var nearby := CAMP + Vector2(sin(i * 0.1), cos(i * 0.1)) * 2.5
		_check(meadow.region_navigation.contains(nearby), "Quiet corrections remain actual legal ground")
		meadow.follow_player(_ground(nearby), true)
		meadow._process(1.0 / 60)
		_check(meadow.camera_focus == initial, "Tiny walking corrections inside the quiet area do not pan")
	meadow.follow_player(Vector3.INF, true)
	meadow._process(0.1)
	_check(meadow.camera_focus == initial, "Nonfinite actor position cannot poison the camera")
	var nearby := CAMP + Vector2(6, -6)
	meadow.follow_player(_ground(nearby), true)
	meadow._process(0.1)
	meadow.stop_player_follow()
	var stopped: Transform3D = meadow.camera.transform
	var stopped_focus: Vector3 = meadow.camera_focus
	for i in 60:
		meadow._process(0.1)
		_check(meadow.camera.transform == stopped and meadow.camera_focus == stopped_focus,
			"Menu/disconnect stop freezes pending pan, pitch and lift without catch-up")

func _run() -> void:
	meadow = Meadow.new()
	root.add_child(meadow)
	await process_frame
	meadow.set_process(false)
	var old_environment := _environment_state()
	var old_projection: int = meadow.camera.projection
	var old_aspect: int = meadow.camera.keep_aspect
	var old_far: float = meadow.camera.far
	var old_height: float = meadow.surface_height(-10, 3)
	var region := Catalog.canonical("dry_wash")
	meadow.set_landscape("dry_wash", Catalog.layout("dry_wash"))
	await process_frame
	if meadow.region_presentation == null or meadow.region_profile == null:
		_check(false, "Canonical v8 must load its actual prepared scene and presentation helper")
		quit(1)
		return
	_check(meadow.landscape == "dry_wash" and meadow.region_navigation.valid
		and meadow.layout.version == 8 and region.anchors.size() == 14,
		"Test uses only the immutable registered14-anchor v8 wash")
	_check(meadow.region_profile.data.terrain_style == "wash_terraces"
		and meadow.region_profile.data.backdrop_style == "low_mesas"
		and meadow.region_profile.lattice.is_empty(), "Actual cooked dry art, no runtime terrain regeneration")
	reference_profile = Recipe.new(meadow.region_profile.data)
	_cache_ground()
	_mesh_samples(region)
	_nearest_occlusion(region)
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _portrait(size)
		for zoom in [0.8, 1.0, 1.18]:
			meadow.zoom = zoom
			meadow.fit_camera()
			for anchor: Dictionary in region.anchors:
				var point := _point(anchor)
				_place(point)
				_assert_pick(point, "clearing zoom%.2f viewport%s" % [zoom, size])
				_check(meadow.region_presentation.camera_lift >= 0 and meadow.region_presentation.camera_lift <= 18,
					"Initial clearing placement respects the same maximum lift")
				clearing_views += 1
			_camera_quiet()
			for frequency in [20.0, 60.0]:
				_camera_walk(frequency)
	_check(clearing_views == 84 and route_completions == 84 and moving_picks >= 1200,
		"Complete14-clearings×2aspects×3zooms plus both-rate ordinary branch returns")
	_check(peak_pan < 7 and peak_lift <= 18 and peak_lift_speed <= 8.00000001,
		"Actual camera motion remains within existing pan/lift limits")
	_check(meadow.region_profile.lattice.is_empty(), "All runtime feet/picks/camera clearance use saved triangles, never the authoring lattice")
	print("DRY_WASH_PRESENTATION_METRICS: %d clearing views, %d moving picks, %d route arrivals, %d stopped frames, %d real scenery negatives; peak pan%.4f lift%.4f lift-rate%.4f" % [clearing_views, moving_picks, route_completions, stopped_frames, occlusion_cases, peak_pan, peak_lift, peak_lift_speed])
	meadow.set_landscape("alpine")
	await process_frame
	_check(meadow.region_presentation == null and meadow.region_navigation == null and meadow.region_profile == null,
		"Leaving DryWash releases its region-only presentation state")
	_check(meadow.camera.projection == old_projection and meadow.camera.keep_aspect == old_aspect
		and meadow.camera.far == old_far and _environment_state() == old_environment,
		"Legacy projection/range/environment restore exactly")
	_check(meadow.surface_height(-10, 3) == old_height, "Legacy terrain stays unchanged")
	meadow.queue_free()
	await process_frame
	print("DRY_WASH_PRESENTATION_SMOKE: %d checks / %d failures; actual meshes, no network or saved-herd mutation" % [checks, failures])
	quit(1 if failures else 0)
