extends SceneTree
## Terrain mesh, picking and grounded-actor regressions. No network or GPU required.
## godot --headless --path client --script res://tests/terrain_smoke.gd

const FEET_CLEARANCE := 0.03
const PICK_TOLERANCE := 0.06
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
	for biome in ["alpine", "cactus", "larch"]:
		game._select_landscape(biome)
		await process_frame
		game._process(1.0 / 60.0)
		if game.meadow.landscape != biome:
			_fail(biome + " must select its own terrain, not fall back to another landscape")
			return
		var expected_bridge_y := -4.0 if biome == "larch" else 0.0
		var expected_gate_y := 4.0 if biome == "larch" else 0.0
		if not is_equal_approx(game.meadow.bridge_y, expected_bridge_y) or not is_equal_approx(game.meadow.gate_y, expected_gate_y):
			_fail(biome + " must expose the expected bridge and gate layout")
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
		if game.actors["mochi"].node != dog or game.actors.size() != 14:
			_fail("changing terrain must retain both players and all twelve animals")
			return
		if game.command_panel.visible or game.sit_button.visible or game.go_cancel.visible:
			_fail("terrain and movement must not reveal permanent controls")
			return
	print("TERRAIN_SMOKE_OK: three sculpted landscapes, river banks and offset bridge/gate, %d portrait ray roundtrips, grounded prediction/interpolation/biome changes, geometry budgets" % checked_roundtrips)
	quit(0)

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
			return _fail("%s offset bridge, water or gate fixture was never visible for picking at %s" % [biome, sample])
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
	print("TERRAIN_BUDGET %s: %d nodes, %d mesh instances, %d triangles" % [biome, nodes.size(), instances, triangles])
	return true

func _fail(message: String) -> bool:
	push_error("TERRAIN_SMOKE_FAILED: " + message)
	quit(1)
	return false
