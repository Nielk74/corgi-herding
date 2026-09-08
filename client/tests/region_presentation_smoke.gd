extends SceneTree
## V7 rendered-terrain/camera contract, independent of the network and live saves.

const Meadow = preload("res://scripts/meadow.gd")
const Navigation = preload("res://scripts/region_navigation.gd")
const Recipe = preload("res://scripts/landscape_recipe.gd")
var meadow: Node3D
var reference_profile: RefCounted
var records: Array[Dictionary] = []
var checks := 0
var failures := 0
var moving_picks := 0
var occlusion_cases := 0
var peak_pan := 0.0
var peak_lift := 0.0
var peak_lift_speed := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 30:
			printerr("REGION_PRESENTATION_FAILED: " + message)

func _point(value: Dictionary) -> Vector2:
	return Vector2(value.x, value.y)

func _ground(point: Vector2) -> Vector3:
	return Vector3(point.x, meadow.surface_height(point.x, point.y), point.y)

func _environment_state() -> Dictionary:
	var result := {}
	for field in ["background_mode", "ambient_light_source", "ambient_light_sky_contribution", "fog_depth_begin", "fog_depth_end", "fog_depth_curve", "fog_light_color", "sky"]:
		result[field] = meadow.world_environment.get(field)
	return result

func _cache_ground() -> void:
	records.clear()
	var vertices_by_grid := {}
	var ground_chunks := 0
	var scenic_chunks := 0
	var triangles := 0
	for instance: MeshInstance3D in meadow.terrain.find_children("*", "MeshInstance3D", true, false):
		var fine := String(instance.name).begins_with("Ground_")
		if not fine and not String(instance.name).begins_with("Scenic_"):
			continue
		ground_chunks += int(fine)
		scenic_chunks += int(not fine)
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vertices := PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for point in original:
				var world: Vector3 = instance.global_transform * point
				vertices.append(world)
				_check(world.is_finite(), "Rendered indexed terrain has finite world vertices")
				if fine:
					var key := Vector2(world.x, world.z)
					var sampled := Vector3(0, reference_profile.surface_height(world.x, world.z), 0).y
					_check(world.y == sampled, "Fine/apron vertices equal the actual shared one-unit terrain sampler")
					if vertices_by_grid.has(key):
						_check(vertices_by_grid[key] == world.y, "Neighboring chunks retain exactly matching edge heights")
					vertices_by_grid[key] = world.y
			records.append({"vertices": vertices, "indices": indices, "bounds": instance.global_transform * instance.mesh.get_aabb()})
			triangles += indices.size() / 3
	_check(ground_chunks >= 120 and ground_chunks <= 300 and scenic_chunks > 20 and scenic_chunks <= 200, "Full large-map terrain and real scenic occluders exist within bounded chunks")
	_check(triangles >= 120000 and triangles <= 400000, "Actual ray-reference triangle set has a bounded complete landscape")
	print("REGION_PRESENTATION_GEOMETRY: %d fine/apron chunks, %d scenic chunks, %d indexed triangles" % [ground_chunks, scenic_chunks, triangles])

func _box_hit(origin: Vector3, direction: Vector3, bounds: AABB, maximum: float) -> bool:
	var enter := 0.0
	var leave := maximum
	for axis in 3:
		if absf(direction[axis]) < 0.0000000001:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]:
				return false
		else:
			var a: float = (bounds.position[axis] - origin[axis]) / direction[axis]
			var b: float = (bounds.end[axis] - origin[axis]) / direction[axis]
			enter = maxf(enter, minf(a, b))
			leave = minf(leave, maxf(a, b))
			if enter > leave:
				return false
	return true

func _nearest_rendered(origin: Vector3, direction: Vector3, maximum := 600.0) -> Vector3:
	# Independent indexed-mesh reference, not the production height/DDA picker.
	var nearest := maximum
	var found := false
	for record in records:
		if not _box_hit(origin, direction, record.bounds, nearest):
			continue
		var vertices: PackedVector3Array = record.vertices
		var indices: PackedInt32Array = record.indices
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			var distance := _triangle_distance(origin, direction, a, b, c)
			if distance >= 0 and distance <= nearest:
				nearest = distance
				found = true
	return origin + direction * nearest if found else Vector3.INF

func _triangle_distance(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	# Scalar binary64 reference against exact stored float32 vertices. Using
	# Vector3 cross/dot here can itself miss a shared edge after ray projection,
	# which would hide the very production picking regression being measured.
	var ex := float(b.x) - float(a.x)
	var ey := float(b.y) - float(a.y)
	var ez := float(b.z) - float(a.z)
	var fx := float(c.x) - float(a.x)
	var fy := float(c.y) - float(a.y)
	var fz := float(c.z) - float(a.z)
	var px := float(direction.y) * fz - float(direction.z) * fy
	var py := float(direction.z) * fx - float(direction.x) * fz
	var pz := float(direction.x) * fy - float(direction.y) * fx
	var determinant := ex * px + ey * py + ez * pz
	if determinant == 0:
		return INF
	var rx := float(origin.x) - float(a.x)
	var ry := float(origin.y) - float(a.y)
	var rz := float(origin.z) - float(a.z)
	var u := (rx * px + ry * py + rz * pz) / determinant
	if u < 0 or u > 1:
		return INF
	var qx := ry * ez - rz * ey
	var qy := rz * ex - rx * ez
	var qz := rx * ey - ry * ex
	var v := (float(direction.x) * qx + float(direction.y) * qy + float(direction.z) * qz) / determinant
	if v < 0 or u + v > 1:
		return INF
	return (fx * qx + fy * qy + fz * qz) / determinant

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
		_check(rendered.is_finite() and rendered.distance_to(expected) < 0.015, "All route anchors and corridor centers lie on the rendered indexed ground")
		_check(picked.is_finite() and picked.distance_to(rendered) < 0.03, "Ground picker agrees with independent nearest rendered triangle")
		var normal: Vector3 = meadow.surface_normal(point.x, point.y)
		_check(normal.is_finite() and absf(normal.length() - 1) < 0.00001 and normal.y > 0, "Grounded markers have finite upward terrain normals")
	_check(high - low > 20, "The large walking region has real continuous elevation, not a flat floor")
	# Vertical apron/scenic hits are visibly present but must not become taps.
	for point in [Vector2(-100, 64), Vector2(100, 0), Vector2(0, 120), Vector2(-180, -124), Vector2(100, -200)]:
		var origin := Vector3(point.x, 300, point.y)
		var rendered := _nearest_rendered(origin, Vector3.DOWN, 600)
		_check(rendered.is_finite(), "Negative-control ray really hits rendered scenery")
		var picked: Vector3 = meadow.region_presentation.ray_ground(origin, Vector3.DOWN, 600)
		_check(not picked.is_finite(), "Visible apron/scenery outside the dry union cannot receive movement")
		occlusion_cases += 1

func _nearest_occlusion(region: Dictionary) -> void:
	# Find actual oblique cases with dry ground behind a nearer unwalkable hill.
	# A picker that skips the first scenery hit would incorrectly select the herd.
	var probes := 0
	for origin in [Vector3(-85, 46, 100), Vector3(85, 50, 65), Vector3(-95, 48, -35), Vector3(75, 55, -105)]:
		for anchor: Dictionary in region.anchors:
			var target := _ground(_point(anchor))
			var direction: Vector3 = (target - origin).normalized()
			var rendered := _nearest_rendered(origin, direction)
			if not rendered.is_finite() or rendered.distance_to(target) < 0.25:
				continue
			if meadow.region_navigation.contains(Vector2(rendered.x, rendered.z)):
				continue
			var picked: Vector3 = meadow.region_presentation.ray_ground(origin, direction)
			_check(not picked.is_finite(), "Nearest visible nonwalking hill occludes a valid target behind it")
			probes += 1
			if probes >= 4:
				break
		if probes >= 4:
			break
	_check(probes >= 2, "Exercise real scenery-first rays, not only empty-sky rejection")
	occlusion_cases += probes
	_check(not meadow.region_presentation.ray_ground(Vector3.INF, Vector3.DOWN).is_finite(), "Nonfinite ray origins fail closed")
	_check(not meadow.region_presentation.ray_ground(Vector3.ZERO, Vector3.ZERO).is_finite(), "Zero direction fails closed")

func _place(point: Vector2) -> void:
	meadow.reset_player_follow()
	meadow.follow_player(_ground(point) + Vector3.UP * 0.03, false)
	meadow._process(0)
	_check(absf(meadow.camera_focus.x - point.x) < 0.001 and absf(meadow.camera_focus.z - (point.y - 6)) < 0.001, "First idle placement frames both world axes exactly once")

func _camera_walk(frequency: float) -> void:
	var point := Vector2(-48, 74)
	_place(point)
	var initial_basis: Basis = meadow.camera.basis
	var yaw := Vector2(initial_basis.z.x, initial_basis.z.z).normalized()
	var lens: float = meadow.camera.fov
	var initial: Vector3 = meadow.camera_focus
	var minimum := Vector2(initial.x, initial.z)
	var maximum := minimum
	var delta := 1.0 / frequency
	var frames := 0
	for target in [Vector2(44, -78), Vector2(-50, 40), Vector2(-48, 74)]:
		var route: Array[Vector2] = meadow.region_navigation.plan(point, target)
		var leg := 0
		while point.distance_to(target) > 0.08 and leg < int(160 * frequency):
			var old_point := point
			var waypoint: Vector2 = meadow.region_navigation.next_waypoint(point, target, route)
			point = point.move_toward(waypoint, 4.0 * delta)
			_check(meadow.region_navigation.visible(old_point, point), "Camera walk follows complete dry route segments")
			var before: Vector3 = meadow.camera_focus
			var old_lift: float = meadow.camera.position.y - before.y - 14.0
			var old_control_lift: float = meadow.region_presentation.camera_lift
			meadow.follow_player(_ground(point) + Vector3.UP * 0.03, true)
			meadow._process(delta)
			var focus: Vector3 = meadow.camera_focus
			var plane := Vector2(focus.x, focus.z)
			peak_pan = maxf(peak_pan, plane.distance_to(Vector2(before.x, before.z)) / delta)
			minimum = minimum.min(plane)
			maximum = maximum.max(plane)
			_check(focus.is_finite() and focus.x >= -72 and focus.x <= 72 and focus.z >= -102 and focus.z <= 90, "World-aware camera respects only new v7 focus bounds")
			var offset: Vector3 = meadow.camera.position - focus
			var lift := offset.y - 14.0
			peak_lift = maxf(peak_lift, lift)
			peak_lift_speed = maxf(peak_lift_speed, absf(lift - old_lift) / delta)
			var control_change: float = meadow.region_presentation.camera_lift - old_control_lift
			_check(control_change <= 8.0 * delta + 0.000000001 and control_change >= -2.0 * delta - 0.000000001, "Visibility assist respects its explicit8-up/2-down units-per-second controls")
			var actual_basis: Basis = meadow.camera.basis
			_check(Vector2(actual_basis.z.x, actual_basis.z.z).normalized().distance_to(yaw) < 0.00001 and meadow.camera.fov == lens, "Visibility lift cannot rotate yaw or change the lens")
			_check(Vector2(offset.x, offset.z).distance_to(Vector2(6, 50)) < 0.0001 and lift >= -0.0001 and lift <= 18.0001, "Only the bounded18-unit vertical visibility assist changes camera offset")
			if frames % int(frequency * 1.5) == 0:
				var ground := _ground(point)
				var screen: Vector2 = meadow.camera.unproject_position(ground)
				var viewport: Vector2 = root.get_visible_rect().size
				_check(screen.x > viewport.x * 0.02 and screen.x < viewport.x * 0.98 and screen.y > viewport.y * 0.02 and screen.y < viewport.y * 0.98, "Walking herder ground remains inside the real portrait frame")
				var picked: Vector3 = meadow.ground_at(screen)
				_check(picked.is_finite() and picked.distance_to(ground) < 0.06, "Moving two-axis camera picks the local rendered ground, not a nearer hill")
				moving_picks += 1
			frames += 1
			leg += 1
		_check(point.distance_to(target) <= 0.08, "Full outward/return camera route arrives without a teleport")
		meadow.follow_player(_ground(point), false)
		var stopped: Vector3 = meadow.camera_focus
		var stopped_pose: Transform3D = meadow.camera.transform
		for i in 90:
			meadow.follow_player(_ground(point) + Vector3(sin(i) * 0.03, cos(i) * 0.2, cos(i) * 0.03), false)
			meadow._process(delta)
			_check(meadow.camera_focus == stopped and meadow.desired_focus == stopped and meadow.camera.transform == stopped_pose, "Rest/reconciliation jitter freezes all camera axes, lift and pitch exactly")
	_check(maximum.x - minimum.x > 80 and maximum.y - minimum.y > 140, "Walking reveals the actual large region in both axes, not old ±6 panning")
	print("REGION_PRESENTATION_WALK: %.0fHz %s, %d frames, x/z span %s" % [frequency, root.get_visible_rect().size, frames, maximum - minimum])

func _camera_quiet() -> void:
	var point := Vector2(-42, 64)
	_place(point)
	var initial: Vector3 = meadow.camera_focus
	for i in 120:
		var nearby := point + Vector2(sin(i * 0.1), cos(i * 0.1)) * 2.5
		meadow.follow_player(_ground(nearby), true)
		meadow._process(1.0 / 60)
		_check(meadow.camera_focus == initial, "Short movement inside the two-axis quiet area does not pan")
	meadow.follow_player(Vector3.INF, true)
	meadow._process(0.1)
	_check(meadow.camera_focus == initial, "Invalid actor positions cannot poison camera focus")
	meadow.follow_player(_ground(point + Vector2(6, -6)), true)
	meadow._process(0.1)
	meadow.stop_player_follow()
	var stopped: Vector3 = meadow.camera_focus
	var stopped_pose: Transform3D = meadow.camera.transform
	meadow._process(3)
	_check(meadow.camera_focus == stopped and meadow.camera.transform == stopped_pose, "Explicit menu/disconnect stop freezes pending follow and visibility lift")

func _original_shared_edge_camera() -> void:
	# Freeze the pre-visibility-assist lens/offset that exposed a real native
	# float32 shared-edge miss. A higher new camera must not mask that regression.
	var camera := Camera3D.new()
	root.add_child(camera)
	var target := _ground(Vector2(-32, 16))
	var local := target + Vector3.UP * 0.03
	var focus := Vector3(local.x, local.y + 1.8, local.z - 6)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = rad_to_deg(2 * atan(tan(deg_to_rad(16)) * 0.8))
	camera.near = 0.1
	camera.far = 600
	camera.position = focus + Vector3(6, 14, 50)
	camera.look_at(focus)
	var screen := camera.unproject_position(target)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var expected := _nearest_rendered(origin, direction)
	var picked: Vector3 = meadow.region_presentation.ray_ground(origin, direction)
	_check(expected.is_finite() and expected.distance_to(target) < 0.03, "Original shared-edge ray has an actual rendered ground hit")
	_check(picked.is_finite() and picked.distance_to(expected) < 0.03, "Original shared-edge ray is accepted without moving its screen pixel")
	camera.free()

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
	var region := Navigation.default_region()
	meadow.set_landscape("alpine_valley", {"version": 7, "bridge_y": 0.0, "gate_y": 0.0, "region": region})
	await process_frame
	if meadow.get("region_presentation") == null or meadow.get("region_profile") == null:
		_check(false, "V7 presentation helper and actual landscape profile must exist")
		quit(1)
		return
	_check(meadow.landscape == "alpine_valley" and meadow.region_navigation.valid, "V7 selection owns its canonical world-aware navigation")
	_check(meadow.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and meadow.camera.keep_aspect == Camera3D.KEEP_WIDTH and meadow.camera.far >= 600, "Large region uses its own fixed perspective lens and scenic range")
	reference_profile = Recipe.new(meadow.region_profile.data)
	var original_lattice_size: int = meadow.region_profile.lattice.size()
	_cache_ground()
	_mesh_samples(region)
	_nearest_occlusion(region)
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = size
		await process_frame
		_check(root.size == size and root.get_visible_rect().size == Vector2(size), "Actual camera viewport matches the requested portrait dimensions")
		if size == Vector2i(720, 1280):
			_original_shared_edge_camera()
		for zoom in [0.8, 1.0, 1.18]:
			meadow.zoom = zoom
			meadow.fit_camera()
			for anchor: Dictionary in region.anchors:
				var point := _point(anchor)
				_place(point)
				var ground := _ground(point)
				var screen: Vector2 = meadow.camera.unproject_position(ground)
				var picked: Vector3 = meadow.ground_at(screen)
				var correct := picked.is_finite() and picked.distance_to(ground) < 0.06
				_check(correct, "Clearing %s supports a grounded portrait view at zoom%s viewport%s" % [point, zoom, size])
		meadow.zoom = 1
		meadow.fit_camera()
		_camera_quiet()
		for frequency in [20.0, 60.0]:
			_camera_walk(frequency)
	_check(moving_picks >= 200 and peak_pan < 7.0, "Substantial moving pick coverage and bounded ordinary two-axis pan speed")
	var stats: Dictionary = meadow.region_presentation.debug_state()
	_check(meadow.region_profile.lattice.size() == original_lattice_size, "Runtime grounding and picking use stored terrain without regenerating procedural lattice samples")
	print("REGION_PRESENTATION_PICKER: %s; %d moving picks, %d real scenery negatives, peak pan %.3f units/s, peak lift %.3f at %.3f units/s; runtime lattice unchanged at%d samples" % [stats, moving_picks, occlusion_cases, peak_pan, peak_lift, peak_lift_speed, original_lattice_size])
	meadow.set_landscape("alpine")
	await process_frame
	_check(meadow.get("region_presentation") == null and meadow.get("region_navigation") == null and meadow.get("region_profile") == null, "Leaving v7 releases its cache/profile/camera helper")
	_check(meadow.camera.projection == old_projection and meadow.camera.keep_aspect == old_aspect and meadow.camera.far == old_far, "Old landscape projection/aspect/range restore exactly")
	_check(_environment_state() == old_environment, "Old environment/fog/sky restore exactly")
	_check(meadow.surface_height(-10, 3) == old_height, "Old terrain surface is byte-stable after leaving the large world")
	meadow.reset_player_follow()
	meadow.follow_player(Vector3(14, 0, 0), false)
	meadow._process(0)
	_check(meadow.camera_focus == Vector3(6, 1.8, -6), "Old herder framing returns to exact legacy bounds and height")
	meadow.queue_free()
	await process_frame
	print("REGION_PRESENTATION_SMOKE: %d checks / %d failures; no network or saved-herd mutation" % [checks, failures])
	quit(1 if failures else 0)
