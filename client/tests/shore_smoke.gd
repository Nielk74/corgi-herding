extends SceneTree
## Geometry and shared server route checks; real Android inspection is also required.

const Navigation = preload("res://scripts/shore_navigation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../protocol/shore-routes.json")))
	if not fixtures is Array or fixtures.size() != 32:
		_fail("32 shared fixtures are required")
		return
	for fixture in fixtures:
		var from := Vector2(fixture.from.x, fixture.from.y)
		var target := Vector2(fixture.target.x, fixture.target.y)
		var route := Navigation.plan(from, target)
		if Navigation.visible(from, target) != fixture.visible or route.size() != fixture.route.size():
			_fail("shared route differs: " + fixture.name)
			return
		for i in route.size():
			var anchor: Array = Navigation.PATH[int(fixture.route[i])]
			if route[i] != Vector2(anchor[0], anchor[1]):
				_fail("shared anchor differs: " + fixture.name)
				return
	var boundary := Vector2(-16.2, 2.0)
	if not Navigation.contains(Navigation.presentation_point(boundary)) or Navigation.presentation_point(boundary).distance_to(boundary) > 0.00002:
		_fail("float32 boundary correction failed")
		return
	for pair in [[Vector2(-14, 0), Vector2(11, 4)], [Vector2(11, 4), Vector2(-14, 0)], [Vector2(-14, 3), Vector2(12, 7)], [Vector2(12, 7), Vector2(-14, 3)]]:
		for frequency in [20.0, 60.0, 4.0]:
			var point: Vector2 = pair[0]
			var target: Vector2 = pair[1]
			var route := Navigation.plan(point, target)
			for frame in 2000:
				var remaining: float = 4.0 / frequency
				while remaining > 0.00001:
					var stride := minf(remaining, 0.08)
					var next := point.move_toward(Navigation.next_waypoint(point, target, route), stride)
					if not Navigation.visible(point, next):
						_fail("prediction crossed the bay")
						return
					point = next
					remaining -= stride
				if point.distance_to(target) < 0.04:
					break
			if point.distance_to(target) > 0.08:
				_fail("two-way route did not arrive")
				return
	root.content_scale_size = Vector2i(720, 1280)
	root.size = Vector2i(720, 1280)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.preview_mode = true
	var started := Time.get_ticks_msec()
	game._select_landscape("juniper")
	game._show_preview()
	await process_frame
	var build_ms := Time.get_ticks_msec() - started
	var meadow = game.meadow
	if meadow.gate != null or meadow.bridge != null or game.moment_label.text != "":
		_fail("shore must not inherit a gate, bridge or arrival message")
		return
	for actor in game.actors.values():
		var p: Vector3 = actor.node.position
		if not Navigation.contains(Vector2(p.x, p.z)) or absf(p.y - meadow.surface_height(p.x, p.z) - 0.03) > 0.001:
			_fail("preview actor is not grounded in the shore union")
			return
	var nodes := 0
	var triangles := 0
	var instances := 0
	var queue: Array[Node] = [game]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		nodes += 1
		queue.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			instances += 1
			for surface in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	if triangles > 100000 or nodes > 1400 or instances > 1000:
		_fail("prototype exceeds mobile budget: %d tris/%d nodes/%d meshes" % [triangles, nodes, instances])
		return
	var ground = meadow.terrain.get_node("ValleyGroundJuniper")
	var checked := 0
	var low := INF
	var high := -INF
	for surface in ground.mesh.get_surface_count():
		var arrays: Array = ground.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for p in vertices:
			if Navigation.contains(Vector2(p.x, p.z)):
				if absf(p.y - meadow.surface_height(p.x, p.z)) > 0.002 or p.y <= 0.05:
					_fail("actual dry mesh differs from walking height")
					return
				low = minf(low, p.y)
				high = maxf(high, p.y)
				checked += 1
	if high - low < 1.0 or checked < 2000:
		_fail("walking surface has insufficient checked relief")
		return
	var lake_arrays: Array = meadow.water.mesh.surface_get_arrays(0)
	var lake_vertices: PackedVector3Array = lake_arrays[Mesh.ARRAY_VERTEX]
	if not _water_overlaps_shore(PackedVector2Array([Vector2(-17, -11), Vector2(17, -11), Vector2(0, 11)])):
		_fail("water-footprint negative control must reject a spanning triangle")
		return
	for i in range(0, lake_vertices.size(), 3):
		var a := lake_vertices[i]
		var b := lake_vertices[i + 1]
		var c := lake_vertices[i + 2]
		if _water_overlaps_shore(PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])):
			_fail("complete water triangle overlaps the canonical dry union")
			return
		for p in [a, b, c, (a + b + c) / 3.0, (a + b) / 2.0, (b + c) / 2.0, (c + a) / 2.0]:
			if Navigation.contains(Vector2(p.x, p.z)):
				_fail("water triangle enters a walkable clearing/path")
				return
	var picks := 0
	var rejected := 0
	var frame_rays := 0
	var visible_faces: PackedVector3Array = ground.mesh.get_faces()
	visible_faces.append_array(meadow.water.mesh.get_faces())
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.size = size
		await process_frame
		if game.get_viewport().get_visible_rect().size != Vector2(size):
			_fail("actual logical portrait viewport differs from requested size")
			return
		for pan in [-6.0, 0.0, 6.0]:
			meadow.camera_focus.x = pan
			meadow.desired_focus.x = pan
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow._process(0.0)
				for p in [Vector2(-14, 0), Vector2(-11, 2), Vector2(-8, -3), Vector2(-3, -6), Vector2(4, -6), Vector2(9, -2), Vector2(11, 4), Vector2(12, 7)]:
					var real := Vector3(p.x, meadow.surface_height(p.x, p.y), p.y)
					var screen: Vector2 = meadow.camera.unproject_position(real)
					if not Rect2(Vector2.ZERO, Vector2(size)).has_point(screen):
						continue
					var hit: Vector3 = meadow.ground_at(screen)
					if not hit.is_finite() or hit.distance_to(real) > 0.06:
						_fail("shore pick mismatch %s => %s" % [real, hit])
						return
					picks += 1
				for p in [Vector2(0, 2), Vector2(0, 7), Vector2(-12, -9), Vector2(14, -7)]:
					if Navigation.contains(p):
						_fail("lake/shoulder rejection fixture must be outside the union")
						return
					var outside := Vector3(p.x, meadow.surface_height(p.x, p.y), p.y)
					var screen: Vector2 = meadow.camera.unproject_position(outside)
					if Rect2(Vector2.ZERO, Vector2(size)).has_point(screen):
						if meadow.ground_at(screen).is_finite():
							_fail("tapping lake/steep shoulder returned a walking shortcut")
							return
						rejected += 1
				if pan != 0.0:
					for row in [0.88, 0.98]:
						for column in [0.02, 0.5, 0.98]:
							var screen := Vector2(size) * Vector2(column, row)
							var origin: Vector3 = meadow.camera.project_ray_origin(screen)
							var endpoint: Vector3 = origin + meadow.camera.project_ray_normal(screen) * meadow.camera.far
							if not _has_mesh_hit(visible_faces, origin, endpoint):
								_fail("ground/water ends inside the lower portrait frame at %s pan%s zoom%s point%s" % [size, pan, zoom, screen])
								return
							frame_rays += 1
	if rejected < 30 or frame_rays != 72:
		_fail("insufficient shoreline rejection/frame coverage")
		return
	if not await _menu_with_sound(game):
		return
	print("SHORE_SMOKE_OK:32 shared routes,12 two-way frequency runs,%d checked dry vertices,%.2fm relief,%d portrait picks,%d rejected lake/shoulder taps,%d actual lower-frame rays,%d tris/%d nodes/%d meshes,build%dms" % [checked, high - low, picks, rejected, frame_rays, triangles, nodes, instances, build_ms])
	game.queue_free()
	await process_frame
	quit(0)

func _has_mesh_hit(faces: PackedVector3Array, origin: Vector3, endpoint: Vector3) -> bool:
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(origin, endpoint, faces[i], faces[i + 1], faces[i + 2])
		if hit is Vector3 and hit.is_finite():
			return true
	return false

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var edge := b - a
	var fraction := clampf((point - a).dot(edge) / edge.length_squared(), 0.0, 1.0) if edge.length_squared() > 0 else 0.0
	return point.distance_to(a + edge * fraction)

func _water_overlaps_shore(triangle: PackedVector2Array) -> bool:
	# Independent full closed-triangle intersection, not just vertex sampling.
	for disk in [Vector3(-11, 2, 5.2), Vector3(-1, -6, 4.5), Vector3(11, 4, 4.8)]:
		var center := Vector2(disk.x, disk.y)
		if Geometry2D.is_point_in_polygon(center, triangle):
			return true
		for edge in range(3):
			if _point_segment_distance(center, triangle[edge], triangle[(edge + 1) % 3]) <= disk.z:
				return true
	var path := [Vector2(-11, 2), Vector2(-8, -3), Vector2(-3, -6), Vector2(4, -6), Vector2(9, -2), Vector2(11, 4)]
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		if Geometry2D.is_point_in_polygon(a, triangle) or Geometry2D.is_point_in_polygon(b, triangle):
			return true
		for edge in range(3):
			var c := triangle[edge]
			var d := triangle[(edge + 1) % 3]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
			if minf(minf(_point_segment_distance(a, c, d), _point_segment_distance(b, c, d)), minf(_point_segment_distance(c, a, b), _point_segment_distance(d, a, b))) <= 3.6:
				return true
	return false

func _menu_with_sound(game: Node) -> bool:
	root.content_scale_size = Vector2i(720, 1280)
	root.size = Vector2i(720, 1280)
	game._open_settings()
	game.resume_button.show()
	game.endpoint_input.show()
	# Inspect the real merged settings row; never fabricate a passing control.
	var server: Button
	var sound: Button
	for node in game.welcome.find_children("*", "Button", true, false):
		if node.text == "Server address":
			server = node
		elif node.text.begins_with("Sound ·"):
			sound = node
	if server == null or sound == null or sound != game.sound_button or server.get_parent() != sound.get_parent():
		_fail("real Sound/Server settings row missing")
		return false
	await process_frame
	await process_frame
	var viewport := Rect2(Vector2.ZERO, Vector2(720, 1280))
	if root.get_visible_rect().size != viewport.size:
		_fail("menu fixture must use actual720x1280 logical viewport")
		return false
	var card: Control = game.welcome.get_child(0).get_child(0)
	if not viewport.encloses(card.get_global_rect()):
		_fail("seven-landscape menu with saved Return/expanded endpoint/64px sound row overflows720x1280: " + str(card.get_global_rect()))
		return false
	for control in [game.juniper_button, game.resume_button, game.endpoint_input, server, sound]:
		if not control.is_visible_in_tree() or not viewport.encloses(control.get_global_rect()):
			_fail("merged settings control is clipped")
			return false
	if minf(server.size.y, sound.size.y) < 64.0:
		_fail("merged settings targets are smaller than64px")
		return false
	print("JUNIPER_MENU:7choices + saved Return + expanded endpoint + real64px Sound/Server row fit actual720x1280; card" + str(card.get_global_rect()))
	return true

func _fail(message: String) -> void:
	push_error("SHORE_SMOKE_FAILED: " + message)
	quit(1)
