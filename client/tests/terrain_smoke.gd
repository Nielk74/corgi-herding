extends SceneTree
## Terrain mesh, picking and grounded-actor regressions. No network or GPU required.
## godot --headless --path client --script res://tests/terrain_smoke.gd

const FEET_CLEARANCE := 0.03
const PICK_TOLERANCE := 0.06
const CLOUD_SPINE: Array[Vector2] = [Vector2(-10, 0), Vector2(-2, -5), Vector2(5, 1), Vector2(11, 4)]
const CLOUD_SHELVES: Array[Vector2] = [Vector2(-10, 0), Vector2(-2, -5), Vector2(11, 4)]
const CLOUD_RADII: Array[float] = [6.2, 4.8, 5.2]
const ORCHARD_SURFACE_SAMPLES: Array[Vector2] = [
	Vector2(-7, -5), # Windfall forage clearing and its four radius edges.
	Vector2(-9.2, -5), Vector2(-4.8, -5), Vector2(-7, -7.2), Vector2(-7, -2.8),
	Vector2(-12, -7), Vector2(-12, 2), Vector2(11, 4), Vector2(14, 7),
]
var checked_roundtrips := 0
var checked_portrait_sizes: Dictionary = {}

func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	_run.call_deferred()

func _portrait_viewport(size: Vector2i) -> bool:
	# Headless startup may reset the physical window to 64x64 after _initialize.
	# Set the logical viewport explicitly after startup, and verify what camera
	# projection will actually use rather than trusting the requested window size.
	root.content_scale_size = size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = size
	await process_frame
	var actual: Vector2 = root.get_visible_rect().size
	if actual.distance_to(Vector2(size)) > 0.01:
		return _fail("Terrain camera viewport is not the requested real portrait size: %s vs %s" % [actual, size])
	if not checked_portrait_sizes.has(size):
		checked_portrait_sizes[size] = true
		print("TERRAIN_VIEWPORT: verified logical camera viewport %s" % actual)
	return true

func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_fail("main scene failed to load")
		return
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	if not await _portrait_viewport(Vector2i(720, 1280)):
		return
	if game.meadow == null or not game.meadow.has_method("surface_height"):
		_fail("terrain must expose its rendered surface height")
		return
	game.preview_mode = true
	game._show_preview()
	game.set_process(false)
	game.network.set_process(false)
	game.meadow.set_process(false)
	var dog: Node3D = game.actors["mochi"].node
	for biome in ["alpine", "cactus", "larch", "orchard"]:
		game._select_landscape(biome)
		await process_frame
		game._process(1.0 / 60.0)
		if game.meadow.landscape != biome:
			_fail(biome + " must select its own terrain, not fall back to another landscape")
			return
		var expected_bridge_y: float = {"larch": -4.0, "orchard": 3.0}.get(biome, 0.0)
		var expected_gate_y: float = {"larch": 4.0, "orchard": 2.0}.get(biome, 0.0)
		if not is_equal_approx(game.meadow.bridge_y, expected_bridge_y) or not is_equal_approx(game.meadow.gate_y, expected_gate_y):
			_fail(biome + " must expose the expected bridge and gate layout")
			return
		if game.meadow.layout.get("version") != (2 if biome == "orchard" else 1):
			_fail(biome + " must retain its authoritative layout version")
			return
		if biome == "orchard" and not _orchard_layout(game.meadow):
			return
		if biome == "orchard" and not _orchard_shore_normals(game.meadow):
			return
		if biome == "orchard" and not _orchard_mesh_seams(game.meadow):
			return
		if not _terrain_relief(game.meadow, biome):
			return
		if not _geometry_budget(game, biome):
			return
		if not _picking_roundtrips(game.meadow, biome):
			return
		if not _grounded_actors(game, biome + " landscape switch"):
			return
		for preview_actor in game.meadow.preview.get_children():
			var expected: float = game.meadow.surface_height(preview_actor.position.x, preview_actor.position.z) + FEET_CLEARANCE
			if absf(preview_actor.position.y - expected) > 0.015:
				_fail(biome + " welcome preview animals must follow the selected terrain")
				return
		if not _moving_actors(game, biome):
			return
		if biome == "orchard" and not _orchard_grounding(game):
			return
		if game.actors["mochi"].node != dog or game.actors.size() != 14:
			_fail("changing terrain must retain both players and all twelve animals")
			return
		if game.command_panel.visible or game.sit_button.visible or game.go_cancel.visible:
			_fail("terrain and movement must not reveal permanent controls")
			return
	if not await _oasis_smoke(game, dog):
		return
	if not await _cloud_smoke(game, dog):
		return
	print("TERRAIN_SMOKE_OK: six sculpted landscapes, unchanged five-landscape regressions, Cloud ridge geometry/picking/visibility, %d portrait ray roundtrips, grounded prediction/interpolation/biome changes, geometry budgets" % checked_roundtrips)
	quit(0)

func _cloud_layout() -> Dictionary:
	return {"version": 4, "bridge_y": 0.0, "gate_y": 0.0, "ridge": {
		"spine": [{"x": -10.0, "y": 0.0}, {"x": -2.0, "y": -5.0}, {"x": 5.0, "y": 1.0}, {"x": 11.0, "y": 4.0}],
		"half_width": 3.6,
		"shelves": [{"center": {"x": -10.0, "y": 0.0}, "radius": 6.2}, {"center": {"x": -2.0, "y": -5.0}, "radius": 4.8}, {"center": {"x": 11.0, "y": 4.0}, "radius": 5.2}],
		"rest": {"center": {"x": 11.0, "y": 4.0}, "radius": 4.6}}}

func _cloud_clearance(point: Vector2) -> float:
	# Independent test geometry: do not let production picking and collision
	# agree on an accidentally enlarged or rectangular replacement corridor.
	var clearance := -INF
	for index in CLOUD_SHELVES.size():
		clearance = maxf(clearance, CLOUD_RADII[index] - point.distance_to(CLOUD_SHELVES[index]))
	for index in range(CLOUD_SPINE.size() - 1):
		var segment := CLOUD_SPINE[index + 1] - CLOUD_SPINE[index]
		var fraction := clampf((point - CLOUD_SPINE[index]).dot(segment) / segment.length_squared(), 0.0, 1.0)
		clearance = maxf(clearance, 3.6 - point.distance_to(CLOUD_SPINE[index] + segment * fraction))
	return clearance

func _cloud_boundaries() -> Array[Dictionary]:
	var boundaries: Array[Dictionary] = []
	var origins: Array[Vector2] = CLOUD_SHELVES.duplicate()
	origins.append_array([Vector2(-6, -2.5), Vector2(1.5, -2)])
	for origin in origins:
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(index * TAU / 8.0)
			var distance := 0.25
			while distance < 40 and _cloud_clearance(origin + direction * distance) >= 0:
				distance += 0.25
			var inside := distance - 0.25
			var outside := distance
			for step in range(16):
				var middle := (inside + outside) * 0.5
				if _cloud_clearance(origin + direction * middle) >= 0:
					inside = middle
				else:
					outside = middle
			var edge := origin + direction * ((inside + outside) * 0.5)
			boundaries.append({"inside": edge - direction * 0.2, "outside": edge + direction * 0.2, "edge": edge, "far": edge + direction * 2.5})
	return boundaries

func _cloud_smoke(game: Node, retained_dog: Node3D) -> bool:
	game._select_landscape("cloud")
	await process_frame
	game._process(1.0 / 60.0)
	var meadow: Node = game.meadow
	var expected := _cloud_layout()
	if meadow.landscape != "cloud" or meadow.layout != expected or meadow.ridge != expected.ridge or meadow.profile.ridge != expected.ridge:
		return _fail("Cloud mesh, height profile and immutable ridge layout must agree")
	if meadow.ridge_spine != CLOUD_SPINE or meadow.ridge_half_width != 3.6 or meadow.rest_center != Vector2(11, 4) or meadow.rest_radius != 4.6:
		return _fail("Cloud public terrain anchors differ from the canonical corridor")
	if is_instance_valid(meadow.bridge) or is_instance_valid(meadow.gate):
		return _fail("Cloud must have neither a bridge nor a gate")
	for pattern in ["RiverSurface*", "Footbridge*", "RockPassOutcrop*"]:
		if not meadow.terrain.find_children(pattern, "", true, false).is_empty():
			return _fail("Cloud retained a previous landscape obstacle: " + pattern)
	if not _geometry_budget(game, "cloud") or not _cloud_mesh_geometry(meadow) or not _cloud_tarn_geometry(meadow):
		return false
	if not await _frame_ground_coverage(meadow, "cloud", "ValleyGroundCloud"):
		return false
	if not await _cloud_picking_and_visibility(game):
		return false
	game.moving = false
	var local: Node3D = game.actors[game.local_id].node
	var dog: Node3D = game.actors["mochi"].node
	for point in CLOUD_SPINE:
		local.position = game._surface_position(point)
		dog.position = game._surface_position(point + Vector2(0.6, 0.3))
		game.actors["mochi"].target = game._surface_position(point)
		for frame in range(20):
			game._process(1.0 / 60.0)
			if not _grounded_actors(game, "Cloud shelf/connector interpolation"):
				return false
		if Vector2(dog.position.x, dog.position.z).distance_to(point) > 0.1:
			return _fail("Cloud corgi grounding did not exercise interpolation")
		meadow.mark_destination(game._surface_position(point) - Vector3(0, FEET_CLEARANCE, 0))
		var clearance: float = meadow.destination.position.y - meadow.surface_height(point.x, point.y)
		if clearance <= 0 or clearance > 0.25:
			return _fail("Cloud destination marker must follow its raised shelf")
	for segment in range(CLOUD_SPINE.size() - 1):
		local.position = game._surface_position(CLOUD_SPINE[segment])
		game.movement_target = CLOUD_SPINE[segment + 1]
		game.moving = true
		for frame in range(240):
			game._process(1.0 / 60.0)
			if _cloud_clearance(Vector2(local.position.x, local.position.z)) < -0.00001 or not _grounded_actors(game, "Cloud predicted connector walk"):
				return _fail("Cloud predicted herder left the corridor or its rendered surface")
			if not game.moving:
				break
		if Vector2(local.position.x, local.position.z).distance_to(CLOUD_SPINE[segment + 1]) > 0.1:
			return _fail("Cloud predicted walk did not reach the next shelf")
	game.moving = false
	if game.actors["mochi"].node != retained_dog or game.actors.size() != 14:
		return _fail("Cloud switch must retain both herders and all twelve animals")
	if game.command_panel.visible or game.sit_button.visible or game.go_cancel.visible:
		return _fail("Cloud must not add permanent controls")
	return true

func _cloud_mesh_geometry(meadow: Node) -> bool:
	var meshes: Array[Node] = meadow.terrain.find_children("ValleyGroundCloud", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		return _fail("Cloud requires one continuous actual ridge ground mesh")
	var ground := meshes[0] as MeshInstance3D
	var normal_basis := ground.global_transform.basis.inverse().transposed()
	var edges: Dictionary = {}
	var checked := 0
	var checked_slopes := 0
	var minimum := INF
	var maximum := -INF
	var minimum_up := 1.0
	for surface in range(ground.mesh.get_surface_count()):
		var arrays: Array = ground.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count := vertices.size() if indices.is_empty() else indices.size()
		if count == 0 or count % 3 != 0 or normals.size() != vertices.size():
			return _fail("Cloud ground needs complete triangles and stored vertex normals")
		for index in range(0, count, 3):
			var points: Array[Vector3] = []
			var stored: Array[Vector3] = []
			for corner in range(3):
				var vertex_index := index + corner if indices.is_empty() else indices[index + corner]
				if vertex_index < 0 or vertex_index >= vertices.size():
					return _fail("Cloud ground contains an invalid index")
				var point: Vector3 = ground.global_transform * vertices[vertex_index]
				var normal: Vector3 = normal_basis * normals[vertex_index]
				if not point.is_finite() or not normal.is_finite() or absf(normal.length() - 1.0) > 0.001:
					return _fail("Cloud contains non-finite ground or non-unit stored normals")
				points.append(point)
				stored.append(normal.normalized())
			var center := (points[0] + points[1] + points[2]) / 3.0
			var clearance := _cloud_clearance(Vector2(center.x, center.z))
			if clearance < -4.0:
				continue
			# Godot's clockwise front must agree with the actual stored normals.
			# A two-sided visibility ray alone would miss a backwards dark surface.
			var front := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
			if not front.is_finite() or front.y <= 0.0:
				return _fail("Cloud ridge/flank triangle is degenerate or wound downwards at %s" % center)
			for normal in stored:
				if normal.y <= 0.0 or front.dot(normal) < 0.5:
					return _fail("Cloud ridge/flank stored normal opposes its real front at %s" % center)
			if absf(float(meadow.surface_height(center.x, center.z)) - center.y) > 0.035:
				return _fail("Cloud sampled height misses an actual triangle interior at %s" % center)
			if clearance >= 0.0:
				for point in points:
					if absf(point.y - float(meadow.surface_height(point.x, point.z))) > 0.035:
						return _fail("Cloud feet height differs from a rendered ridge vertex at %s" % point)
				minimum = minf(minimum, center.y)
				maximum = maxf(maximum, center.y)
				checked += 1
			if clearance > 0.8:
				minimum_up = minf(minimum_up, front.y)
				if front.y < 0.8:
					return _fail("Cloud playable shelf/connector has an unsafe steep mesh face at %s (up %.3f)" % [center, front.y])
				checked_slopes += 1
			for edge_index in range(3):
				var a := points[edge_index]
				var b := points[(edge_index + 1) % 3]
				if _cloud_clearance(Vector2(a.x, a.z)) <= 0.1 or _cloud_clearance(Vector2(b.x, b.z)) <= 0.1:
					continue
				var a_key := _mesh_vertex_key(a)
				var b_key := _mesh_vertex_key(b)
				var key := a_key + "/" + b_key if a_key < b_key else b_key + "/" + a_key
				edges[key] = int(edges.get(key, 0)) + 1
	for edge in edges:
		if edges[edge] != 2:
			return _fail("Cloud interior ground has an unpaired seam/T-junction or duplicate face at " + edge)
	if checked < 500 or checked_slopes < 300 or edges.size() < 500 or maximum - minimum < 2.0:
		return _fail("Cloud actual ground did not exercise three sculpted shelves and connected interior seams")
	var shelf_heights: Array[float] = []
	for point in CLOUD_SHELVES:
		shelf_heights.append(float(meadow.surface_height(point.x, point.y)))
	if shelf_heights[1] - shelf_heights[0] < 0.5 or shelf_heights[2] - shelf_heights[1] < 0.5:
		return _fail("Cloud needs three genuinely ascending resting shelves: %s" % str(shelf_heights))
	var flanks := 0
	for boundary in _cloud_boundaries():
		var edge: Vector2 = boundary.edge
		var outside: Vector2 = boundary.far
		if _cloud_clearance(outside) > -1.0:
			continue
		var drop: float = meadow.surface_height(edge.x, edge.y) - meadow.surface_height(outside.x, outside.y)
		if drop > 0.5:
			flanks += 1
	if flanks < 24:
		return _fail("Cloud corridor needs visible downhill flanks, not an invisible boundary on flat ground")
	print("CLOUD_GROUND: %d ridge triangles, %d paired interior edges, %.2f relief, shelf heights %s, minimum safe-face up %.3f, %d downhill flank probes" % [checked, edges.size(), maximum - minimum, shelf_heights, minimum_up, flanks])
	return true

func _world_mesh_faces(mesh: MeshInstance3D) -> PackedVector3Array:
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	for index in faces.size():
		faces[index] = mesh.global_transform * faces[index]
	return faces

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var fraction := clampf((point - a).dot(segment) / segment.length_squared(), 0.0, 1.0) if segment.length_squared() > 0 else 0.0
	return point.distance_to(a + segment * fraction)

func _cloud_triangle_overlaps_ridge(triangle: PackedVector2Array) -> bool:
	# Vertex-only tests miss a large water triangle covering the corridor while
	# all three corners sit outside. Test the whole closed triangle against the
	# independent shelf disks and all spine capsules, including edge crossings.
	for index in CLOUD_SHELVES.size():
		var center := CLOUD_SHELVES[index]
		if Geometry2D.is_point_in_polygon(center, triangle):
			return true
		for edge in range(3):
			if _point_segment_distance(center, triangle[edge], triangle[(edge + 1) % 3]) <= CLOUD_RADII[index]:
				return true
	for index in range(CLOUD_SPINE.size() - 1):
		var a := CLOUD_SPINE[index]
		var b := CLOUD_SPINE[index + 1]
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

func _cloud_tarn_geometry(meadow: Node) -> bool:
	var spanning := PackedVector2Array([Vector2(-17, -10), Vector2(17, -10), Vector2(0, 10)])
	for point in spanning:
		if _cloud_clearance(point) >= 0:
			return _fail("Cloud water overlap negative control must have three illegal corners")
	if not _cloud_triangle_overlaps_ridge(spanning):
		return _fail("Cloud water exclusion must reject triangle interiors, not only their vertices")
	var waters: Array[Node] = meadow.terrain.find_children("CloudDistantTarn*", "MeshInstance3D", true, false)
	if waters.is_empty():
		return _fail("Cloud distant tarn must have actual inspectable water geometry")
	var triangles := 0
	var edges: Dictionary = {}
	for node in waters:
		var water := node as MeshInstance3D
		var faces := _world_mesh_faces(water)
		if faces.is_empty() or faces.size() % 3 != 0:
			return _fail("Cloud distant tarn contains incomplete triangles")
		for index in range(0, faces.size(), 3):
			var triangle := PackedVector2Array()
			for corner in range(3):
				var point := faces[index + corner]
				if not point.is_finite():
					return _fail("Cloud water contains a non-finite vertex")
				triangle.append(Vector2(point.x, point.z))
			if _cloud_triangle_overlaps_ridge(triangle):
				return _fail("Cloud distant water overlaps the authoritative dry ridge: %s" % str(triangle))
			triangles += 1
			# The base water plane must end beneath the surrounding ground. Extra
			# reflections may sit over open water; their footprints are still tested.
			if water.name != "CloudDistantTarn":
				continue
			for edge in range(3):
				var a := faces[index + edge]
				var b := faces[index + (edge + 1) % 3]
				var a_key := _mesh_vertex_key(a)
				var b_key := _mesh_vertex_key(b)
				var key := a_key + "/" + b_key if a_key < b_key else b_key + "/" + a_key
				if not edges.has(key):
					edges[key] = {"count": 0, "a": a, "b": b}
				edges[key].count += 1
	var shore_samples := 0
	var actual_bank_rays := 0
	var minimum_cover := INF
	var ground: MeshInstance3D = meadow.terrain.find_children("ValleyGroundCloud", "MeshInstance3D", true, false)[0]
	var ground_faces := _world_mesh_faces(ground)
	for key in edges:
		var edge: Dictionary = edges[key]
		if edge.count != 1:
			continue
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var point: Vector3 = edge.a.lerp(edge.b, fraction)
			var cover: float = meadow.surface_height(point.x, point.z) - point.y
			if not is_finite(cover) or cover < 0.005:
				return _fail("Cloud tarn polygon edge is exposed instead of covered by real banks at %s (cover %.4f)" % [point, cover])
			minimum_cover = minf(minimum_cover, cover)
			if shore_samples % 10 == 0:
				# The far heightfield must really be rendered here. A finite profile
				# alone would falsely approve a truncated bank or missing terrain.
				var hit := _mesh_ray_hit(ground_faces, point + Vector3(0, 30, 0), point - Vector3(0, 30, 0))
				if not hit.is_finite() or hit.y - point.y < 0.005 or absf(hit.y - float(meadow.surface_height(point.x, point.z))) > 0.035:
					return _fail("Cloud tarn bank has no matching actual rendered ground above its edge at %s" % point)
				actual_bank_rays += 1
			shore_samples += 1
	if triangles < 8 or shore_samples < 40 or actual_bank_rays < 4:
		return _fail("Cloud distant water test did not exercise complete geometry and its shore perimeter")
	print("CLOUD_TARN: %d complete triangles outside the dry ridge, %d covered perimeter samples and %d actual bank triangle rays (minimum cover %.3f); spanning-triangle negative control rejected" % [triangles, shore_samples, actual_bank_rays, minimum_cover])
	return true

func _mesh_ray_hit(faces: PackedVector3Array, origin: Vector3, endpoint: Vector3) -> Vector3:
	var nearest := Vector3.INF
	var distance := INF
	for index in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(origin, endpoint, faces[index], faces[index + 1], faces[index + 2])
		if hit is Vector3 and hit.is_finite() and hit.distance_squared_to(origin) < distance:
			nearest = hit
			distance = hit.distance_squared_to(origin)
	return nearest

func _cloud_picking_and_visibility(game: Node) -> bool:
	var meadow: Node = game.meadow
	var samples: Array[Vector2] = []
	for shelf in CLOUD_SHELVES:
		for offset in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			samples.append(shelf + offset)
	for index in range(CLOUD_SPINE.size() - 1):
		for fraction in [0.25, 0.5, 0.75]:
			samples.append(CLOUD_SPINE[index].lerp(CLOUD_SPINE[index + 1], fraction))
	var faces := PackedVector3Array()
	var ground_faces := PackedVector3Array()
	# Include every real terrain/scenery surface, not only the profile or one
	# known obstacle. An unexpected foreground crown or custom crag can hide sheep.
	for node in meadow.terrain.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var transformed := _world_mesh_faces(mesh)
		faces.append_array(transformed)
		if mesh.name == "ValleyGroundCloud":
			ground_faces = transformed
	if ground_faces.is_empty():
		return _fail("Cloud picking and visibility require actual ground triangles")
	for point in samples:
		var expected := Vector3(point.x, float(meadow.surface_height(point.x, point.y)), point.y)
		var hit := _mesh_ray_hit(ground_faces, expected + Vector3(0, 10, 0), expected - Vector3(0, 10, 0))
		if not hit.is_finite() or hit.distance_to(expected) > 0.035:
			return _fail("Cloud shelf/connector profile has no matching actual triangle at %s" % point)
	var boundaries := _cloud_boundaries()
	for boundary in boundaries:
		if not game._walkable(boundary.inside) or game._walkable(boundary.outside):
			return _fail("Cloud collision disagrees with independently sampled corridor limits")
	var original_size: Vector2i = root.size
	var coverage: Dictionary = {}
	var boundary_coverage: Dictionary = {}
	var visible_animals := 0
	var rejected := 0
	for portrait_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		if not await _portrait_viewport(portrait_size):
			return false
		var viewport: Rect2 = root.get_visible_rect().grow(-4)
		for pan in [-6.0, 0.0, 6.0]:
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow.camera_focus = Vector3(pan, 1.8, -6)
				meadow.desired_focus = meadow.camera_focus
				meadow._process(0.0)
				for point in samples:
					var expected := Vector3(point.x, float(meadow.surface_height(point.x, point.y)), point.y)
					var screen: Vector2 = meadow.camera.unproject_position(expected)
					if not viewport.has_point(screen):
						continue
					var picked: Vector3 = meadow.ground_at(screen)
					if not picked.is_finite() or picked.distance_to(expected) > PICK_TOLERANCE:
						return _fail("Cloud shelf/connector touch missed its rendered surface at %s (size %s pan %.1f zoom %.2f): %s" % [point, portrait_size, pan, zoom, picked])
					checked_roundtrips += 1
					coverage[str(portrait_size) + "/" + str(point)] = true
					# Check center and connector bodies at both follow extremes. The
					# remaining offset samples exercise the full width through picking.
					if not point in CLOUD_SHELVES and not point in [Vector2(-6, -2.5), Vector2(1.5, -2), Vector2(8, 2.5)]:
						continue
					var probe := expected + Vector3(0, 0.6, 0)
					var probe_screen: Vector2 = meadow.camera.unproject_position(probe)
					if not viewport.has_point(probe_screen):
						continue
					var origin: Vector3 = meadow.camera.project_ray_origin(probe_screen)
					var hit := _mesh_ray_hit(faces, origin, probe)
					if hit.is_finite() and hit.distance_to(probe) > 0.02:
						return _fail("Cloud real terrain/scenery hides a shelf animal at %s (size %s pan %.1f zoom %.2f), hit %s" % [point, portrait_size, pan, zoom, hit])
					coverage["animal/" + str(portrait_size) + "/" + str(pan) + "/" + str(point)] = true
					visible_animals += 1
				# Boundary rays need only the two follow extremes at normal zoom.
				# A hidden far flank may correctly project onto nearer legal ground;
				# test rejection only when the actual frontmost triangle is outside.
				if pan == 0 or zoom != 1.0:
					continue
				for index in boundaries.size():
					var point: Vector2 = boundaries[index].outside
					var expected := Vector3(point.x, float(meadow.surface_height(point.x, point.y)), point.y)
					var screen: Vector2 = meadow.camera.unproject_position(expected)
					if not viewport.has_point(screen):
						continue
					var origin: Vector3 = meadow.camera.project_ray_origin(screen)
					var hit := _mesh_ray_hit(ground_faces, origin, origin + meadow.camera.project_ray_normal(screen) * float(meadow.camera.far))
					if not hit.is_finite():
						return _fail("Cloud visible boundary has no actual ground beneath its profile")
					if hit.distance_to(expected) > PICK_TOLERANCE:
						continue
					if meadow.ground_at(screen).is_finite():
						return _fail("Cloud visible steep flank accepts a tap outside the authoritative corridor at %s" % point)
					boundary_coverage[index] = true
					rejected += 1
		for point in samples:
			if not coverage.has(str(portrait_size) + "/" + str(point)):
				return _fail("Cloud mandatory shelf/connector picking sample was never exercised at %s, size %s" % [point, portrait_size])
		for point in CLOUD_SHELVES:
			# Following one end need not frame the opposite distant shelf. Each
			# shelf must be exercised in the central view and at its own follow end.
			for pan in [0.0, -6.0 if point.x < 0 else 6.0]:
				if not coverage.has("animal/" + str(portrait_size) + "/" + str(pan) + "/" + str(point)):
					return _fail("Cloud shelf animal was never visible at a required phone/follow extreme: %s size %s pan %.1f" % [point, portrait_size, pan])
	if not await _portrait_viewport(original_size):
		return false
	meadow.fit_camera()
	if boundary_coverage.size() < 24 or visible_animals < 36:
		return _fail("Cloud did not exercise enough distinct visible corridor boundaries and shelf animals")
	print("CLOUD_VISIBILITY: %d clear actual-mesh animal probes, %d rejected flank taps at %d distinct boundaries, 16:9/20:9 portraits" % [visible_animals, rejected, boundary_coverage.size()])
	return true

func _oasis_ring() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index in range(8):
		points.append(Vector2.RIGHT.rotated(index * TAU / 8.0) * 5.2)
	return points

func _oasis_smoke(game: Node, retained_dog: Node3D) -> bool:
	game._select_landscape("oasis")
	await process_frame
	game._process(1.0 / 60.0)
	var meadow: Node = game.meadow
	var layout: Dictionary = meadow.layout
	var rock: Variant = layout.get("rock_pass")
	if meadow.landscape != "oasis" or layout.get("version") != 3 or layout.size() != 4 or layout.get("bridge_y") != 0 or layout.get("gate_y") != 0:
		return _fail("Oasis must use its own canonical version-three dry layout")
	if not rock is Dictionary or rock.size() != 2 or rock.get("radius") != 3.4 or not rock.get("center") is Dictionary:
		return _fail("Oasis must retain the canonical rock footprint")
	if rock.center.size() != 2 or rock.center.get("x") != 0 or rock.center.get("y") != 0 or meadow.rock_center != Vector2.ZERO or not is_equal_approx(meadow.rock_radius, 3.4):
		return _fail("Oasis rendered rock center/radius must agree with the authoritative layout")
	if is_instance_valid(meadow.bridge) or is_instance_valid(meadow.gate) or not meadow.terrain.find_children("Footbridge*", "", true, false).is_empty():
		return _fail("Oasis must not retain an invisible bridge or gate")
	if not meadow.terrain.find_children("RiverSurface*", "", true, false).is_empty():
		return _fail("Oasis must not retain the previous playable river")
	if not _oasis_ground_mesh(meadow) or not _geometry_budget(game, "oasis"):
		return false
	if not await _frame_ground_coverage(meadow, "oasis", "ValleyGroundOasis"):
		return false
	if not _oasis_apron_orientation(meadow):
		return false
	if not _picking_roundtrips(meadow, "oasis") or not _oasis_rock_visibility(meadow):
		return false
	if not _grounded_actors(game, "Oasis landscape switch") or not _moving_actors(game, "oasis"):
		return false
	for preview_actor in meadow.preview.get_children():
		var expected: float = meadow.surface_height(preview_actor.position.x, preview_actor.position.z) + FEET_CLEARANCE
		if absf(preview_actor.position.y - expected) > 0.015:
			return _fail("Oasis welcome animals must follow the dry terrain")
	var local: Node3D = game.actors[game.local_id].node
	var dog: Node3D = game.actors["mochi"].node
	game.moving = false
	for point in _oasis_ring():
		local.position = game._surface_position(point)
		dog.position = game._surface_position(point * 1.1)
		game.actors["mochi"].target = game._surface_position(point)
		for frame in range(20):
			game._process(1.0 / 60.0)
			if not _grounded_actors(game, "Oasis bypass %s frame %d" % [point, frame]):
				return false
		if Vector2(dog.position.x, dog.position.z).distance_to(point) > 0.1:
			return _fail("Oasis route grounding must exercise corgi interpolation")
	if game.actors["mochi"].node != retained_dog or game.actors.size() != 14:
		return _fail("Oasis switch must retain the existing two herders and twelve animals")
	if game.command_panel.visible or game.sit_button.visible or game.go_cancel.visible:
		return _fail("Oasis must not add permanent controls")
	return true

func _oasis_ground_mesh(meadow: Node) -> bool:
	var meshes: Array[Node] = meadow.terrain.find_children("ValleyGround*", "MeshInstance3D", true, false)
	var checked_vertices := 0
	var former_channel_vertices := 0
	var minimum := INF
	var maximum := -INF
	for node in meshes:
		var ground := node as MeshInstance3D
		var faces: PackedVector3Array = ground.mesh.get_faces()
		for vertex in faces:
			var point: Vector3 = ground.global_transform * vertex
			if absf(point.x) > 17 or absf(point.z) > 11:
				continue
			var height: float = meadow.surface_height(point.x, point.z)
			if not point.is_finite() or not is_finite(height) or absf(point.y - height) > 0.035:
				return _fail("Oasis rendered ground and feet height disagree at %s" % point)
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
			checked_vertices += 1
			if absf(point.x) < 1.5 and absf(point.z) > 4:
				former_channel_vertices += 1
		for index in range(0, faces.size(), 9):
			var center: Vector3 = ground.global_transform * ((faces[index] + faces[index + 1] + faces[index + 2]) / 3.0)
			if absf(center.x) <= 17 and absf(center.z) <= 11:
				if absf(float(meadow.surface_height(center.x, center.z)) - center.y) > 0.035:
					return _fail("Oasis height misses a rendered triangle interior at %s" % center)
	if checked_vertices < 100 or former_channel_vertices < 20 or maximum - minimum <= 1.0:
		return _fail("Oasis needs a genuinely sculpted, continuous dry mesh across the former river")
	print("OASIS_GROUND: %d rendered vertices, %d across the former channel, height span %.2f" % [checked_vertices, former_channel_vertices, maximum - minimum])
	return true

func _frame_ground_coverage(meadow: Node, biome: String, mesh_name: String) -> bool:
	# The analytic heightfield extends beyond its finite rendered mesh. Picking
	# roundtrips cannot detect a visible mesh cutoff at the portrait frame edge.
	# Cast only against the actual ground, not scenery or profile samples.
	var meshes: Array[Node] = meadow.terrain.find_children(mesh_name, "MeshInstance3D", true, false)
	if meshes.size() != 1:
		return _fail(biome + " frame coverage needs its actual continuous ground mesh")
	var ground := meshes[0] as MeshInstance3D
	var faces: PackedVector3Array = ground.mesh.get_faces()
	if faces.is_empty() or faces.size() % 3 != 0:
		return _fail(biome + " frame coverage needs complete rendered ground triangles")
	for index in faces.size():
		faces[index] = ground.global_transform * faces[index]
	var original_size: Vector2i = root.size
	var checked := 0
	# The actual Android cutoff appeared on a 1080x2400 phone. Its 20:9 frame
	# sees farther down the ground than the standard 720x1280 test viewport.
	for portrait_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		if not await _portrait_viewport(portrait_size):
			return false
		var viewport: Rect2 = root.get_visible_rect()
		if viewport.size.y <= 0 or absf(viewport.size.x / viewport.size.y - float(portrait_size.x) / portrait_size.y) > 0.0001:
			return _fail("%s frame coverage did not exercise the requested portrait aspect: %s vs %s" % [biome, viewport.size, portrait_size])
		for pan in [-6.0, 6.0]:
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow.camera_focus = Vector3(pan, 1.8, -6)
				meadow.desired_focus = meadow.camera_focus
				meadow._process(0.0)
				for row in [0.88, 0.98]:
					for column in [0.02, 0.5, 0.98]:
						var screen := viewport.position + viewport.size * Vector2(column, row)
						var origin: Vector3 = meadow.camera.project_ray_origin(screen)
						var direction: Vector3 = meadow.camera.project_ray_normal(screen)
						var endpoint := origin + direction * float(meadow.camera.far)
						var covered := false
						for index in range(0, faces.size(), 3):
							var hit: Variant = Geometry3D.segment_intersects_triangle(origin, endpoint, faces[index], faces[index + 1], faces[index + 2])
							if hit is Vector3 and hit.is_finite():
								covered = true
								break
						if not covered:
							return _fail("%s rendered ground ends inside the lower portrait frame (size %s, pan %.1f, zoom %.2f, column %.2f, row %.2f, ray origin %s, direction %s)" % [biome, portrait_size, pan, zoom, column, row, origin, direction])
						checked += 1
	if not await _portrait_viewport(original_size):
		return false
	meadow.fit_camera()
	if checked != 72:
		return _fail(biome + " lower-frame coverage must exercise both follow extremes and all zooms")
	print("%s_FRAME_GROUND: %d lower-portrait rays hit actual ground triangles at both follow extremes, all zooms, and 16:9/20:9 phone aspects" % [biome.to_upper(), checked])
	return true

func _oasis_apron_orientation(meadow: Node) -> bool:
	# Two-sided raster materials still flip lighting on a backwards front face.
	# Visibility rays can hit either side, so inspect real vertex order and stored
	# normals separately. Low clearance selects the apron, not the lobe walls.
	var rocks: Array[Node] = meadow.terrain.find_children("RockPassOutcrop*", "MeshInstance3D", true, false)
	var checked := 0
	var minimum_alignment := 1.0
	for node in rocks:
		var rock := node as MeshInstance3D
		var normal_basis := rock.global_transform.basis.inverse().transposed()
		for surface in range(rock.mesh.get_surface_count()):
			var arrays: Array = rock.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			if normals.size() != vertices.size():
				return _fail("Oasis apron must retain a stored normal for each rendered vertex")
			var count := vertices.size() if indices.is_empty() else indices.size()
			if count == 0 or count % 3 != 0:
				return _fail("Oasis apron orientation needs complete rendered triangles")
			for index in range(0, count, 3):
				var points: Array[Vector3] = []
				var stored: Array[Vector3] = []
				var low_apron := true
				for corner in range(3):
					var vertex_index := index + corner if indices.is_empty() else indices[index + corner]
					if vertex_index < 0 or vertex_index >= vertices.size():
						return _fail("Oasis outcrop contains an invalid triangle index")
					var point: Vector3 = rock.global_transform * vertices[vertex_index]
					var normal: Vector3 = normal_basis * normals[vertex_index]
					if not point.is_finite() or not normal.is_finite() or normal.length_squared() < 0.5:
						return _fail("Oasis outcrop contains invalid geometry or stored normals")
					points.append(point)
					stored.append(normal.normalized())
					var clearance: float = point.y - meadow.surface_height(point.x, point.z)
					if clearance < -0.02 or clearance > 0.35:
						low_apron = false
				if not low_apron:
					continue
				var alignment := _apron_front_alignment(points[0], points[1], points[2], stored)
				if alignment < 0.5:
					return _fail("Oasis low apron front-face winding opposes its upward stored normals at %s (alignment %.3f)" % [points[0], alignment])
				# Reversing an actual apron triangle reproduces the exported black-disc
				# mistake and must fail this same predicate, not merely a count check.
				if _apron_front_alignment(points[0], points[2], points[1], stored) >= 0.5:
					return _fail("Oasis winding regression failed to reject a reversed actual apron triangle")
				minimum_alignment = minf(minimum_alignment, alignment)
				checked += 1
	if checked < 100:
		return _fail("Oasis winding regression did not exercise enough low apron triangles")
	print("OASIS_APRON_NORMALS: %d actual low triangles face upward and agree with stored normals, minimum alignment %.3f; reversed winding rejected" % [checked, minimum_alignment])
	return true

func _apron_front_alignment(a: Vector3, b: Vector3, c: Vector3, normals: Array[Vector3]) -> float:
	# Godot's clockwise front face is (c-a) cross (b-a), not the reverse.
	var front := (c - a).cross(b - a)
	if front.length_squared() < 0.0000000001 or front.y <= 0.0:
		return -1.0
	front = front.normalized()
	var alignment := 1.0
	for normal in normals:
		alignment = minf(alignment, front.dot(normal))
	return alignment

func _oasis_rock_visibility(meadow: Node) -> bool:
	var rocks: Array[Node] = meadow.terrain.find_children("RockPassOutcrop*", "MeshInstance3D", true, false)
	if rocks.is_empty():
		return _fail("Oasis collision rock must have actual visible geometry")
	var faces := PackedVector3Array()
	var sectors: Dictionary = {}
	var maximum_radius := 0.0
	var maximum_height := 0.0
	for node in rocks:
		var rock := node as MeshInstance3D
		for vertex in rock.mesh.get_faces():
			var point: Vector3 = rock.global_transform * vertex
			if not point.is_finite():
				return _fail("Oasis outcrop contains non-finite geometry")
			faces.append(point)
			var plan := Vector2(point.x, point.z)
			var radius := plan.length()
			maximum_radius = maxf(maximum_radius, radius)
			maximum_height = maxf(maximum_height, point.y - float(meadow.surface_height(point.x, point.z)))
			var sector := posmod(int(roundf(plan.angle() / (TAU / 8.0))), 8)
			sectors[sector] = maxf(float(sectors.get(sector, 0.0)), radius)
	if maximum_radius > 3.43 or maximum_height > 2.15:
		return _fail("Oasis outcrop extends beyond its collision footprint or obscures the route: radius %.3f, added height %.3f" % [maximum_radius, maximum_height])
	for sector in range(8):
		if float(sectors.get(sector, 0.0)) < 3.25:
			return _fail("Oasis rock silhouette must explain the blocked footprint in every direction")
	var viewport: Rect2 = root.get_visible_rect().grow(-4)
	var coverage: Dictionary = {}
	var checked := 0
	for pan in [-6.0, 6.0]:
		for zoom in [0.8, 1.0, 1.18]:
			meadow.zoom = zoom
			meadow.fit_camera()
			meadow.camera_focus = Vector3(pan, 1.8, -6)
			meadow.desired_focus = meadow.camera_focus
			meadow._process(0.0)
			for point in _oasis_ring():
				# A small animal's upper body must remain visible on either bypass.
				var probe := Vector3(point.x, float(meadow.surface_height(point.x, point.y)) + 0.6, point.y)
				var screen: Vector2 = meadow.camera.unproject_position(probe)
				if not viewport.has_point(screen):
					continue
				var origin: Vector3 = meadow.camera.project_ray_origin(screen)
				for index in range(0, faces.size(), 3):
					var hit: Variant = Geometry3D.segment_intersects_triangle(origin, probe, faces[index], faces[index + 1], faces[index + 2])
					if hit is Vector3 and hit.distance_to(probe) > 0.02:
						return _fail("Oasis rock hides a bypass animal at %s (pan %.1f, zoom %.2f)" % [point, pan, zoom])
				coverage[str(pan) + "/" + str(point)] = true
				checked += 1
		for point in _oasis_ring():
			if not coverage.has(str(pan) + "/" + str(point)):
				return _fail("Oasis bypass visibility fixture was never exercised at a portrait follow extreme")
	for point in [Vector2.ZERO, Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		var ground := Vector3(point.x, float(meadow.surface_height(point.x, point.y)), point.y)
		if not ground.is_finite():
			return _fail("Oasis must retain finite underlying ground inside the rock")
		if meadow.ground_at(meadow.camera.unproject_position(ground)).is_finite():
			return _fail("Oasis rock footprint must reject terrain taps")
	print("OASIS_VISIBILITY: %d clear portrait animal probes, radius %.3f, added height %.3f, rejected rock taps" % [checked, maximum_radius, maximum_height])
	return true

func _orchard_layout(meadow: Node) -> bool:
	var forage: Variant = meadow.layout.get("forage")
	if not forage is Dictionary or forage.get("id") != "windfall" or forage.get("radius") != 2.2:
		return _fail("Orchard must retain the windfall forage area and radius")
	var center: Variant = forage.get("center")
	if not center is Dictionary or center.get("x") != -7 or center.get("y") != -5:
		return _fail("Orchard forage clearing must match its authoritative center")
	if meadow.forage_center != Vector2(-7, -5) or not is_equal_approx(meadow.forage_radius, 2.2):
		return _fail("rendered Orchard forage anchors must agree with the saved layout")
	return true

func _orchard_shore_normals(meadow: Node) -> bool:
	if not meadow.terrain.find_children("DistantPasturePatch*", "", true, false).is_empty():
		return _fail("Orchard fields must color the real ground, not floating overlay polygons")
	var checked := 0
	var minimum_up := 1.0
	var largest_change := 0.0
	for segment in [Vector2(-35, -13), Vector2(13, 40)]:
		for side in [-1.0, 1.0]:
			# Cover the actual mesh edge and two nearby grass strips. Fixed-X
			# tangent samples here can accidentally cross into the submerged bed.
			for offset in [0.0, 0.0001, 0.05]:
				var previous := Vector3.ZERO
				for index in range(int(roundf((segment.y - segment.x) / 0.25)) + 1):
					var z: float = segment.x + index * 0.25
					var x: float = meadow.profile.river_center(z) + side * (meadow.profile.river_width(z) + offset)
					var normal: Vector3 = meadow.profile.normal_at(x, z)
					if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001:
						return _fail("Orchard curved-bank normal must be finite and unit length at (%f, %f)" % [x, z])
					if normal.y < 0.9:
						return _fail("Orchard grass normal samples a steep submerged-bank face at (%f, %f): %s" % [x, z, normal])
					if previous != Vector3.ZERO:
						var change := normal.distance_to(previous)
						if change > 0.15:
							return _fail("Orchard adjacent curved-bank normals flip sharply at (%f, %f): %.3f" % [x, z, change])
						largest_change = maxf(largest_change, change)
					minimum_up = minf(minimum_up, normal.y)
					previous = normal
					checked += 1
	print("ORCHARD_SHORE_NORMALS: %d edge/grass samples, minimum upward component %.3f, largest adjacent change %.4f" % [checked, minimum_up, largest_change])
	return true

func _orchard_mesh_seams(meadow: Node) -> bool:
	var meshes: Array[Node] = meadow.terrain.find_children("ValleyGround*", "MeshInstance3D", true, false)
	if meshes.size() != 2:
		return _fail("Orchard stitching needs both actual ground meshes")
	var checked := 0
	for node in meshes:
		var ground := node as MeshInstance3D
		var edges: Dictionary = {}
		var coverage: Dictionary = {}
		var faces: PackedVector3Array = ground.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var vertices: Array[Vector3] = [ground.global_transform * faces[index], ground.global_transform * faces[index + 1], ground.global_transform * faces[index + 2]]
			for corner in range(3):
				var a := vertices[corner]
				var b := vertices[(corner + 1) % 3]
				var offset_a: float = absf(a.x - meadow.profile.river_center(a.z)) - meadow.profile.river_width(a.z)
				var offset_b: float = absf(b.x - meadow.profile.river_center(b.z)) - meadow.profile.river_width(b.z)
				var seam := ""
				# Stay inside the clipped horizon and outer mesh boundary. Here a
				# half-step near-shore column must meet an equally split outer edge.
				if absf(offset_a - 4.0) < 0.0001 and absf(offset_b - 4.0) < 0.0001:
					if minf(a.z, b.z) >= 13 and maxf(a.z, b.z) <= 40:
						seam = "front fine/coarse"
					elif minf(a.z, b.z) >= -28 and maxf(a.z, b.z) <= -13:
						seam = "back fine/coarse"
				if absf(a.z - b.z) < 0.0001 and minf(offset_a, offset_b) >= -0.0001:
					if absf(absf(a.z) - 12.0) < 0.0001 and maxf(offset_a, offset_b) <= 8.0001:
						seam = "front inner stitch" if a.z > 0 else "back inner stitch"
					elif absf(absf(a.z) - 12.5) < 0.0001 and maxf(offset_a, offset_b) <= 4.0001:
						seam = "front outer stitch" if a.z > 0 else "back outer stitch"
				if seam.is_empty():
					continue
				var first := _mesh_vertex_key(a)
				var second := _mesh_vertex_key(b)
				var key := first + "/" + second if first < second else second + "/" + first
				if not edges.has(key):
					edges[key] = {"count": 0, "seam": seam, "a": a, "b": b}
				edges[key].count += 1
		for edge: Dictionary in edges.values():
			if edge.count != 2:
				return _fail("Orchard %s has an unshared or nonmanifold edge %s -> %s (%d triangles)" % [edge.seam, edge.a, edge.b, edge.count])
			coverage[edge.seam] = int(coverage.get(edge.seam, 0)) + 1
			checked += 1
		for seam in ["front fine/coarse", "back fine/coarse", "front inner stitch", "back inner stitch", "front outer stitch", "back outer stitch"]:
			if int(coverage.get(seam, 0)) < 4:
				return _fail("Orchard %s lacks enough actual shared mesh edges on %s" % [seam, ground.name])
	print("ORCHARD_MESH_SEAMS: %d actual edges shared by exactly two triangles across both bank joins and inner/outer stitches" % checked)
	return true

func _mesh_vertex_key(point: Vector3) -> String:
	# Weld only normal float-rounding noise; include height so coincident X/Z
	# edges with a visible vertical crack cannot be mistaken for shared edges.
	return str(Vector3i(roundi(point.x * 10000.0), roundi(point.y * 10000.0), roundi(point.z * 10000.0)))

func _terrain_relief(meadow: Node, biome: String) -> bool:
	var minimum := INF
	var maximum := -INF
	for x in [-16.0, -12.0, -8.0, -4.0, 4.0, 8.0, 12.0, 16.0]:
		for z in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
			var height: float = meadow.surface_height(x, z)
			if not is_finite(height):
				return _fail(biome + " has non-finite playable terrain")
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	if maximum - minimum <= 1.0:
		return _fail("%s playable ground must have real relief above one unit, got %.3f" % [biome, maximum - minimum])
	for z in [meadow.bridge_y - 6.0, meadow.bridge_y + 6.0]:
		var water_height: float = meadow.surface_height(0, z)
		var left_bank: float = meadow.surface_height(-2.5, z)
		var right_bank: float = meadow.surface_height(2.5, z)
		if minf(left_bank, right_bank) - water_height < 0.25:
			return _fail(biome + " river must be visibly lower than both banks")
		if float(meadow.surface_height(0, meadow.bridge_y)) - water_height < 0.4:
			return _fail(biome + " bridge must span above the water")
	# Inspect the actual rendered ground vertices too: a nonflat helper over a
	# flat mesh would pass height tests but still leave the landscape looking flat.
	var meshes: Array[Node] = meadow.terrain.find_children("ValleyGround*", "MeshInstance3D", true, false)
	if meshes.size() < 2:
		return _fail(biome + " needs real ground geometry on both river banks")
	var mesh_min := INF
	var mesh_max := -INF
	var checked_vertices := 0
	for node in meshes:
		var ground := node as MeshInstance3D
		for surface in range(ground.mesh.get_surface_count()):
			var arrays: Array = ground.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world_vertex: Vector3 = ground.global_transform * vertex
				if absf(world_vertex.x) > 17 or absf(world_vertex.z) > 11 or absf(world_vertex.x) < 1.5:
					continue
				if absf(world_vertex.x) < 2.0 and absf(world_vertex.z - meadow.bridge_y) < 2.1:
					continue # The bridge deck legitimately covers the riverbank mesh.
				mesh_min = minf(mesh_min, world_vertex.y)
				mesh_max = maxf(mesh_max, world_vertex.y)
				var height: float = meadow.surface_height(world_vertex.x, world_vertex.z)
				if absf(height - world_vertex.y) > 0.035:
					return _fail("%s rendered ground and height disagree at %s: mesh %.3f vs height %.3f" % [biome, world_vertex, world_vertex.y, height])
				checked_vertices += 1
		# Face centroids also expose a height helper that matches grid vertices
		# but interpolates a different surface between them.
		var faces: PackedVector3Array = ground.mesh.get_faces()
		for index in range(0, faces.size(), 9):
			var center: Vector3 = ground.global_transform * ((faces[index] + faces[index + 1] + faces[index + 2]) / 3.0)
			if absf(center.x) > 17 or absf(center.z) > 11 or absf(center.x) < 1.5:
				continue
			if absf(center.x) < 2.0 and absf(center.z - meadow.bridge_y) < 2.1:
				continue
			if absf(float(meadow.surface_height(center.x, center.z)) - center.y) > 0.035:
				return _fail("%s surface height misses a rendered triangle interior at %s" % [biome, center])
	if checked_vertices < 100 or mesh_max - mesh_min <= 1.0:
		return _fail(biome + " playable mesh is flat or lacks sufficient real geometry")
	print("TERRAIN_RELIEF %s: playable height span %.2f, rendered vertex span %.2f, %d checked vertices" % [biome, maximum - minimum, mesh_max - mesh_min, checked_vertices])
	return true

func _picking_roundtrips(meadow: Node, biome: String) -> bool:
	var samples: Array[Vector2] = [Vector2(-12, -6), Vector2(-9, 3), Vector2(-5, -4), Vector2(-3, 6), Vector2(-2.4, -5), Vector2(4, -5), Vector2(8, 5), Vector2(12, -6), Vector2(15, 7)]
	var fixture_samples: Array[Vector2] = [
		Vector2(-2.4, meadow.bridge_y), Vector2(2.4, meadow.bridge_y),
		Vector2(0, meadow.bridge_y), Vector2(0, meadow.bridge_y - 1.25), Vector2(0, meadow.bridge_y + 1.25),
		Vector2(0, meadow.bridge_y - 6.0), Vector2(0, meadow.bridge_y + 6.0),
		Vector2(5, meadow.gate_y), Vector2(6, meadow.gate_y), Vector2(7, meadow.gate_y),
		Vector2(6, meadow.gate_y - 1.25), Vector2(6, meadow.gate_y + 1.25),
	]
	if biome == "orchard":
		fixture_samples.append_array(ORCHARD_SURFACE_SAMPLES)
	elif biome == "oasis":
		fixture_samples = _oasis_ring()
		fixture_samples.append_array([Vector2(0, -8), Vector2(0, 8), Vector2(6, -8), Vector2(6, 0), Vector2(6, 8), Vector2(-12, 0), Vector2(12, -7), Vector2(12, 6)])
	samples.append_array(fixture_samples)
	var checked_fixtures: Dictionary = {}
	var viewport: Rect2 = root.get_visible_rect().grow(-4)
	for zoom in [0.8, 1.0, 1.18]:
		for pan in [-6.0, 0.0, 6.0]:
			meadow.zoom = zoom
			meadow.fit_camera()
			meadow.camera_focus = Vector3(pan, 1.8, -6)
			meadow.desired_focus = meadow.camera_focus
			meadow._process(0.0)
			var checks := 0
			for sample in samples:
				var expected := Vector3(sample.x, float(meadow.surface_height(sample.x, sample.y)), sample.y)
				var screen: Vector2 = meadow.camera.unproject_position(expected)
				if not viewport.has_point(screen):
					continue
				var picked: Vector3 = meadow.ground_at(screen)
				if not picked.is_finite() or picked.distance_to(expected) > PICK_TOLERANCE:
					return _fail("%s picking missed rendered terrain at %s (zoom %.2f pan %.1f): got %s" % [biome, expected, zoom, pan, picked])
				checks += 1
				checked_roundtrips += 1
				if sample in fixture_samples:
					checked_fixtures[sample] = true
			if checks < 4:
				return _fail("%s portrait picking case had too few visible samples: zoom %.2f pan %.1f" % [biome, zoom, pan])
	for sample in fixture_samples:
		if not checked_fixtures.has(sample):
			return _fail("%s required terrain fixture was never visible for picking at %s" % [biome, sample])
	return true

func _grounded_actors(game: Node, context: String) -> bool:
	for id in game.actors:
		var actor: Node3D = game.actors[id].node
		var expected: float = game.meadow.surface_height(actor.position.x, actor.position.z) + FEET_CLEARANCE
		if not actor.position.is_finite() or absf(actor.position.y - expected) > 0.015:
			return _fail("%s: %s floats or sinks at %s; expected feet %.3f" % [context, id, actor.position, expected])
	return true

func _moving_actors(game: Node, biome: String) -> bool:
	var local: Node3D = game.actors[game.local_id].node
	local.position = game._surface_position(Vector2(-14, -4))
	game.movement_target = Vector2(-7, 3)
	game.moving = true
	var start := local.position
	# Remote interpolation must ground the intermediate x/z, not interpolate y
	# through a raised slope between two snapshots.
	var dog: Node3D = game.actors["mochi"].node
	dog.position = game._surface_position(Vector2(3, -6))
	game.actors["mochi"].target = game._surface_position(Vector2(12, 6))
	for frame in range(150):
		game._process(1.0 / 60.0)
		if not _grounded_actors(game, "%s movement frame %d" % [biome, frame]):
			return false
	if Vector2(local.position.x - start.x, local.position.z - start.z).length() < 4:
		return _fail(biome + " grounding test did not exercise local movement")
	game.moving = false
	var marker_ground := Vector3(11, float(game.meadow.surface_height(11, 5)), 5)
	game.meadow.mark_destination(marker_ground)
	var marker: Node3D = game.meadow.destination
	if marker.position.y <= marker_ground.y or marker.position.y - marker_ground.y > 0.25:
		return _fail(biome + " destination marker must sit just above its terrain")
	game._select_dog("mochi")
	game._process(1.0 / 60.0)
	var selection: Node3D = game.meadow.selection
	var selection_ground: float = game.meadow.surface_height(selection.position.x, selection.position.z)
	if not selection.visible or selection.position.y <= selection_ground or selection.position.y - selection_ground > 0.25:
		return _fail(biome + " selected corgi marker must follow the ground")
	game._command("stay")
	return true

func _orchard_grounding(game: Node) -> bool:
	var local: Node3D = game.actors[game.local_id].node
	var dog: Node3D = game.actors["mochi"].node
	game.moving = false
	for sample in ORCHARD_SURFACE_SAMPLES:
		var expected: Vector3 = game._surface_position(sample)
		local.position = expected
		dog.position = game._surface_position(sample + Vector2(-0.6, 0.4))
		game.actors["mochi"].target = expected
		for frame in range(20):
			game._process(1.0 / 60.0)
			if not _grounded_actors(game, "Orchard clearing/terrace %s frame %d" % [sample, frame]):
				return false
		if Vector2(dog.position.x, dog.position.z).distance_to(sample) > 0.1:
			return _fail("Orchard forage and terrace checks must exercise corgi interpolation")
		var ground := expected - Vector3(0, FEET_CLEARANCE, 0)
		game.meadow.mark_destination(ground)
		var clearance: float = game.meadow.destination.position.y - ground.y
		if clearance <= 0 or clearance > 0.25:
			return _fail("Orchard forage and terrace destination markers must remain above the ground")
	return true

func _geometry_budget(game: Node, biome: String) -> bool:
	var nodes: Array[Node] = game.find_children("*", "", true, false)
	var instances := 0
	var triangles := 0
	for node in nodes:
		if node is MeshInstance3D:
			instances += 1
			var mesh: Mesh = node.mesh
			if mesh != null:
				triangles += mesh.get_faces().size() / 3
		elif node is MultiMeshInstance3D and node.multimesh != null:
			instances += 1
			if node.multimesh.mesh != null:
				triangles += node.multimesh.mesh.get_faces().size() / 3 * node.multimesh.instance_count
	if nodes.size() > 1400 or instances > 1000 or triangles > 150000:
		return _fail("%s exceeds prototype geometry budget: %d nodes, %d instances, %d triangles" % [biome, nodes.size(), instances, triangles])
	if biome == "orchard" and triangles > 100000:
		return _fail("Orchard exceeds its tighter 100000-triangle mobile budget: %d triangles" % triangles)
	print("TERRAIN_BUDGET %s: %d nodes, %d mesh instances, %d triangles" % [biome, nodes.size(), instances, triangles])
	return true

func _fail(message: String) -> bool:
	push_error("TERRAIN_SMOKE_FAILED: " + message)
	quit(1)
	return false
