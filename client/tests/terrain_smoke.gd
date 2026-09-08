extends SceneTree
## Terrain mesh, picking and grounded-actor regressions. No network or GPU required.
## godot --headless --path client --script res://tests/terrain_smoke.gd

const FEET_CLEARANCE := 0.03
const PICK_TOLERANCE := 0.06
const ORCHARD_SURFACE_SAMPLES: Array[Vector2] = [
	Vector2(-7, -5), # Windfall forage clearing and its four radius edges.
	Vector2(-9.2, -5), Vector2(-4.8, -5), Vector2(-7, -7.2), Vector2(-7, -2.8),
	Vector2(-12, -7), Vector2(-12, 2), Vector2(11, 4), Vector2(14, 7),
]
var checked_roundtrips := 0

func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_fail("main scene failed to load")
		return
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
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
	print("TERRAIN_SMOKE_OK: five sculpted landscapes, existing river/gate and Orchard regressions, dry Oasis rock routes and visibility, %d portrait ray roundtrips, grounded prediction/interpolation/biome changes, geometry budgets" % checked_roundtrips)
	quit(0)

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
	if not await _oasis_frame_ground_coverage(meadow):
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

func _oasis_frame_ground_coverage(meadow: Node) -> bool:
	# The analytic heightfield extends beyond its finite rendered mesh. Picking
	# roundtrips cannot detect a visible mesh cutoff at the portrait frame edge.
	# Cast only against the actual Oasis ground, not scenery or profile samples.
	var meshes: Array[Node] = meadow.terrain.find_children("ValleyGroundOasis", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		return _fail("Oasis frame coverage needs its actual continuous ground mesh")
	var ground := meshes[0] as MeshInstance3D
	var faces: PackedVector3Array = ground.mesh.get_faces()
	if faces.is_empty() or faces.size() % 3 != 0:
		return _fail("Oasis frame coverage needs complete rendered ground triangles")
	for index in faces.size():
		faces[index] = ground.global_transform * faces[index]
	var original_size: Vector2i = root.size
	var checked := 0
	# The actual Android cutoff appeared on a 1080x2400 phone. Its 20:9 frame
	# sees farther down the ground than the standard 720x1280 test viewport.
	for portrait_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.size = portrait_size
		await process_frame
		var viewport: Rect2 = root.get_visible_rect()
		if viewport.size.y <= 0 or absf(viewport.size.x / viewport.size.y - float(portrait_size.x) / portrait_size.y) > 0.0001:
			return _fail("Oasis frame coverage did not exercise the requested portrait aspect: %s vs %s" % [viewport.size, portrait_size])
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
							return _fail("Oasis rendered ground ends inside the lower portrait frame (size %s, pan %.1f, zoom %.2f, column %.2f, row %.2f, ray origin %s, direction %s)" % [portrait_size, pan, zoom, column, row, origin, direction])
						checked += 1
	root.size = original_size
	await process_frame
	meadow.fit_camera()
	if checked != 72:
		return _fail("Oasis lower-frame coverage must exercise both follow extremes and all zooms")
	print("OASIS_FRAME_GROUND: %d lower-portrait rays hit actual ground triangles at both follow extremes, all zooms, and 16:9/20:9 phone aspects" % checked)
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
