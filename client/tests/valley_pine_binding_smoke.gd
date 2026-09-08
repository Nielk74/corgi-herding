extends SceneTree
## Two live Meadows, one shared PackedScene cache, no GPU or save mutations.
const Meadow = preload("res://scripts/meadow.gd")
const Binding = preload("res://scripts/valley_pine_binding.gd")
var checks := 0
var failures := 0
var envelope_vertices := 0
var crown_records := 0
var bound_corners_inside := 0
var minimum_box_clearance := INF

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 30:
			printerr("VALLEY_PINE_FAILED: " + message)

func _world() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var meadow := Meadow.new()
	viewport.add_child(meadow)
	meadow.set_process(false)
	return {"viewport": viewport, "meadow": meadow}

func _private_weakrefs(scene: Node) -> Array[WeakRef]:
	var weak: Array[WeakRef] = []
	var seen := {}
	for node: Node in scene.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.name).begins_with("Tree"):
			for resource: Resource in [node.multimesh, node.multimesh.mesh, node.multimesh.mesh.surface_get_material(1)]:
				var id := resource.get_instance_id()
				if not seen.has(id):
					seen[id] = true
					weak.append(weakref(resource))
	return weak

func _records(scene: Node) -> Dictionary:
	var records := {}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D and not node is MultiMeshInstance3D:
			continue
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var surfaces := []
		for i in mesh.get_surface_count():
			surfaces.append({"arrays": mesh.surface_get_arrays(i), "material": mesh.surface_get_material(i)})
		var record := {"mesh": mesh, "surfaces": surfaces, "bounds": mesh.get_aabb(),
			"transform": node.transform, "margin": node.extra_cull_margin, "cast_shadow": node.cast_shadow,
			"range": node.visibility_range_end, "override": node.material_override, "gi": node.gi_mode,
			"pine": node is MultiMeshInstance3D and String(node.name).begins_with("Tree")}
		if node is MultiMeshInstance3D:
			record["multi"] = node.multimesh
			record["buffer"] = node.multimesh.buffer
			record["custom_aabb"] = node.multimesh.custom_aabb
			record["instance_count"] = node.multimesh.instance_count
		records[String(scene.get_path_to(node))] = record
	return records

func _compare(base: Dictionary, current: Dictionary, other: Dictionary) -> void:
	check(base.keys() == current.keys() and base.keys() == other.keys(), "No render nodes/batches added, removed or reordered")
	var meshes := {}
	var multis := {}
	var materials := {}
	var buffer_bytes := 0
	for path: String in base:
		var before: Dictionary = base[path]
		var after: Dictionary = current[path]
		var second: Dictionary = other[path]
		for field in ["bounds", "transform", "margin", "cast_shadow", "range", "override", "gi"]:
			check(after[field] == before[field] and second[field] == before[field], "Original render/culling state unchanged: " + field)
		check(after.surfaces.size() == before.surfaces.size(), "Exact old draw-surface count")
		for i in before.surfaces.size():
			check(after.surfaces[i].arrays == before.surfaces[i].arrays and second.surfaces[i].arrays == before.surfaces[i].arrays, "All actual vertices/normals/colors/UVs/indices preserved")
			if not before.pine or i == 0:
				check(after.surfaces[i].material == before.surfaces[i].material and second.surfaces[i].material == before.surfaces[i].material, "Trunk and every non-pine material remain shared originals")
		if before.has("multi"):
			for field in ["buffer", "custom_aabb", "instance_count"]:
				check(before[field] == after[field] and before[field] == second[field], "Full CPU instance data stays exact: " + field)
		if before.pine:
			check(before.mesh != after.mesh and before.mesh != second.mesh and after.mesh != second.mesh, "Pine Mesh is private to each Meadow, never the cached source")
			check(before.multi != after.multi and before.multi != second.multi and after.multi != second.multi, "Only affected MultiMeshes are cloned privately")
			check(after.surfaces[1].material is ShaderMaterial and second.surfaces[1].material is ShaderMaterial and after.surfaces[1].material != second.surfaces[1].material, "Each world has independent shader uniform state")
			check(before.surfaces[1].material is StandardMaterial3D and not before.mesh.has_meta("pine_wind_reach"), "Cached source material and metadata remain untouched")
			check(after.mesh.get_meta("pine_wind_reach") == 0.08 and after.mesh.get_meta("pine_wind_surface") == 1, "Only private crowns carry bounded scenic-motion metadata")
			meshes[after.mesh] = true
			materials[after.surfaces[1].material] = true
			if not multis.has(after.multi):
				buffer_bytes += after.buffer.size() * 4
			multis[after.multi] = true
		else:
			check(after.mesh == before.mesh and second.mesh == before.mesh, "No terrain, ground, cactus, grass or stone mesh copied")
			if before.has("multi"):
				check(after.multi == before.multi and second.multi == before.multi, "No unrelated MultiMesh copied")
	check(meshes.size() == 3 and materials.size() == 1, "Exactly three private pine meshes and one material per world")
	print("VALLEY_PINE_RESOURCES: per world3 Mesh +%d MultiMesh +1 ShaderMaterial +1 clock; %d byte exposed instance-buffer payload, not measured RSS/GPU memory" % [multis.size(), buffer_bytes])

func _envelopes(meadow: Node3D) -> void:
	var region: Dictionary = meadow.region_navigation.region
	for record: Dictionary in meadow.region_presentation._occluders:
		if record.moving_surface < 0:
			check(record.moving_surface == -1 and record.moving_crown == AABB(), "Every non-pine occluder keeps exact triangle path")
			continue
		crown_records += 1
		check(record.moving_surface == 1 and record.surfaces.size() == 2, "Only needles use the conservative motion envelope")
		var points: PackedVector3Array = record.surfaces[1].vertices
		var box: AABB = record.moving_crown
		var rectangle := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		for clearing: Dictionary in region.clearings:
			var center := [float(clearing.center.x), float(clearing.center.y)]
			var distance := sqrt(_point_rect_squared(center, rectangle)) - float(clearing.radius)
			minimum_box_clearance = minf(minimum_box_clearance, distance)
			check(distance > 0, "Entire conservative crown rectangle stays outside every canonical clearing, not only its corners")
		for edge: Dictionary in region.corridors:
			var a: Dictionary = region.anchors[int(edge.a)]
			var b: Dictionary = region.anchors[int(edge.b)]
			var distance := sqrt(_segment_rect_squared([float(a.x), float(a.y)], [float(b.x), float(b.y)], rectangle)) - float(edge.half_width)
			minimum_box_clearance = minf(minimum_box_clearance, distance)
			check(distance > 0, "Entire conservative crown rectangle stays outside every canonical swept corridor")
		for point: Vector3 in points:
			var base: Vector3 = record.transform * point
			# All-time displacement sphere, independent of the CPU shader mirror.
			# Tolerance is only float32 AABB addition at stored world magnitude.
			for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				check(box.grow(0.00003).has_point(base + axis * 0.08) and box.grow(0.00003).has_point(base - axis * 0.08), "World crown box covers full analytical displacement bound")
			envelope_vertices += 1
		for x in [box.position.x, box.end.x]:
			for z in [box.position.z, box.end.z]:
				bound_corners_inside += int(meadow.region_navigation.contains(Vector2(x, z)))
		var origin := box.get_center() + Vector3.RIGHT * (box.size.x + 1)
		var hit: Vector3 = meadow.region_presentation._mesh_hit(record, origin, Vector3.LEFT, box.size.x * 2 + 2)
		check(hit.is_finite() and box.grow(0.0001).has_point(hit), "Animated crown ray is conservatively blocked, never skipped")
		# Root/bark rays below the crown still use original trunk triangles.
		var point: Vector3 = record.transform * Vector3(0, 0.25, 0)
		if point.y < box.position.y - 0.01:
			var trunk_origin := point + Vector3.RIGHT * 3
			var original: Dictionary = record.duplicate()
			original.moving_surface = -1
			original.moving_crown = AABB()
			var exact: Vector3 = meadow.region_presentation._mesh_hit(original, trunk_origin, Vector3.LEFT, 6)
			check(meadow.region_presentation._mesh_hit(record, trunk_origin, Vector3.LEFT, 6) == exact, "Trunk retains previous exact triangle intersection")
	check(crown_records == 265, "Exactly existing265 crowns indexed; no scenic/ground widening")
	print("VALLEY_PINE_ENVELOPES: %d actual crown vertices, %d boxes, full rectangle-union minimum clearance %.6fm" % [envelope_vertices, crown_records, minimum_box_clearance])

func _point_rect_squared(p: Array, rect: Rect2) -> float:
	var x: float = maxf(maxf(float(rect.position.x) - p[0], 0), p[0] - float(rect.end.x))
	var y: float = maxf(maxf(float(rect.position.y) - p[1], 0), p[1] - float(rect.end.y))
	return x * x + y * y

func _point_segment_squared(p: Array, a: Array, b: Array) -> float:
	var dx: float = b[0] - a[0]
	var dy: float = b[1] - a[1]
	var t := clampf(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy), 0, 1)
	var x: float = p[0] - a[0] - dx * t
	var y: float = p[1] - a[1] - dy * t
	return x * x + y * y

func _segment_rect_squared(a: Array, b: Array, rect: Rect2) -> float:
	# Independent convex feature distance: intersecting segment, segment
	# endpoints vs rectangle, or rectangle corners vs segment. This catches
	# a capsule crossing the box even when none of its corners is inside.
	var enter := 0.0
	var leave := 1.0
	var intersects := true
	for axis in 2:
		var low: float = rect.position[axis]
		var high: float = rect.end[axis]
		var delta: float = b[axis] - a[axis]
		if delta == 0:
			if a[axis] < low or a[axis] > high:
				intersects = false
				break
		else:
			var t0: float = (low - a[axis]) / delta
			var t1: float = (high - a[axis]) / delta
			enter = maxf(enter, minf(t0, t1))
			leave = minf(leave, maxf(t0, t1))
			if enter > leave:
				intersects = false
				break
	if intersects:
		return 0
	var closest := minf(_point_rect_squared(a, rect), _point_rect_squared(b, rect))
	for x in [float(rect.position.x), float(rect.end.x)]:
		for y in [float(rect.position.y), float(rect.end.y)]:
			closest = minf(closest, _point_segment_squared([x, y], a, b))
	return closest

func _run() -> void:
	var negative := Rect2(-1, -1, 2, 2)
	check(_point_rect_squared([0.0, 0.0], negative) == 0, "Negative control: disk inside box cannot pass merely because four corners are outside")
	check(_segment_rect_squared([-2.0, 0.0], [2.0, 0.0], negative) == 0, "Negative control: corridor crossing between corners is detected")
	var packed := load("res://generated/long_valley.scn") as PackedScene
	var cached := packed.instantiate() as Node3D
	root.add_child(cached)
	cached.hide()
	var baseline := _records(cached)
	var a := _world()
	var b := _world()
	var legacy_lens: Dictionary = {"projection": a.meadow.camera.projection, "fov": a.meadow.camera.fov, "size": a.meadow.camera.size}
	a.meadow.set_landscape("alpine_valley")
	b.meadow.set_landscape("alpine_valley")
	check(a.meadow.valley_pines != null and b.meadow.valley_pines != null, "Both v7 worlds bind independently")
	if a.meadow.valley_pines == null or b.meadow.valley_pines == null:
		quit(1)
		return
	var first: Node = a.meadow.valley_pines
	var second: Node = b.meadow.valley_pines
	first.clock.set_process(false)
	second.clock.set_process(false)
	_compare(baseline, _records(a.meadow.terrain), _records(b.meadow.terrain))
	check(_records(cached) == baseline, "Prepared source unchanged while both worlds active")
	_envelopes(a.meadow)
	var second_material: Material = second.clock.selected_material()
	first.clock.advance(1.0 / 60)
	first.clock.advance(1.0 / 60)
	check(first.clock.debug_state().elapsed > 0 and second.clock.debug_state().elapsed == 0, "Advancing worldA cannot advance worldB")
	var first_time: float = first.clock.debug_state().elapsed
	first.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	first.clock.advance(10)
	second.clock.advance(1.0 / 60)
	second.clock.advance(1.0 / 60)
	check(first.clock.debug_state().elapsed == first_time and second.clock.debug_state().elapsed > 0, "One world freezes without changing the other's gates")
	first.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	first.clock.set_process(false)
	first.clock.advance(10)
	check(first.clock.debug_state().elapsed == first_time, "Resume never replays missed wind")
	a.meadow.terrain.hide()
	check(not first.clock.debug_state().active, "Hidden terrain freezes its clock")
	a.meadow.terrain.show()
	first.clock.set_process(false)
	check(first.clock.debug_state().active, "Visible terrain resumes without a second clock")
	var terrain_before: Node3D = a.meadow.terrain
	var stats: Dictionary = first.debug_state()
	a.meadow.set_landscape("alpine")
	check(a.meadow.valley_pines == null and a.meadow.region_presentation == null, "Leaving v7 removes binding and motion index")
	check(_records(terrain_before) == baseline, "Detach restores exact source references before queued terrain deletion")
	check(second.clock.selected_material() == second_material and second_material.get_shader_parameter("wind_strength") == 1.0, "Leaving worldA cannot disable worldB's private material")
	for field: String in legacy_lens:
		check(a.meadow.camera.get(field) == legacy_lens[field], "Legacy camera restored: " + field)
	check(_records(cached) == baseline, "Cache stays original after first world leaves")
	a.meadow.set_landscape("alpine_valley")
	check(a.meadow.valley_pines != null and a.meadow.valley_pines != first and a.meadow.valley_pines.clock.debug_state().elapsed == 0, "Reentry has one fresh clock")
	a.meadow.valley_pines.clock.set_process(false)
	for id in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper", "bellflower"]:
		a.meadow.set_landscape(id)
		check(a.meadow.valley_pines == null and a.meadow.region_presentation == null, "No binding/motion index in legacy landscape " + id)
	var third := packed.instantiate() as Node3D
	root.add_child(third)
	check(_records(third) == baseline, "Fresh cache instance still yields original resources")
	third.free()
	var weak_driver: WeakRef = weakref(second.clock)
	var weak_resources := _private_weakrefs(b.meadow.terrain)
	second_material = null
	b.viewport.queue_free()
	a.viewport.queue_free()
	await process_frame
	await process_frame
	check(weak_driver.get_ref() == null, "Clock does not survive world teardown")
	for resource: WeakRef in weak_resources:
		check(resource.get_ref() == null, "Private mesh/MultiMesh/material is released when its world leaves")
	check(_records(cached) == baseline, "Final cache unchanged after both worlds leave")
	print("VALLEY_PINE_BINDING: %d checks / %d failures; %s" % [checks, failures, stats])
	cached.free()
	await process_frame
	quit(1 if failures else 0)
