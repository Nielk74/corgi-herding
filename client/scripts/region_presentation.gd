extends RefCounted
## V7 camera and picking only. Navigation owns strict walkability; indexed
## rendered meshes own hit positions. Old diorama cameras are not involved.

const OFFSET := Vector3(6, 14, 50)
const BASE_FOV := 32.0
const QUIET_HALF_WIDTH := 3.0
const LOOK_AHEAD := 6.0
const MAX_CLEARANCE_LIFT := 18.0
const LIFT_RISE_SPEED := 8.0
const LIFT_FALL_SPEED := 2.0
var camera_focus := Vector3.ZERO
var desired_focus := Vector3.ZERO
var initialized := false
var following_walk := false
var navigation: RefCounted
var profile: RefCounted
var _bounds: Dictionary
var _ground_chunks := {}
var _occluders: Array[Dictionary] = []
var _minimum := Vector2(INF, INF)
var _maximum := Vector2(-INF, -INF)
var _cells_visited := 0
var _triangles_tested := 0
var _occluder_grid := {}
var _local_ground := Vector3.ZERO
var _local_walking := false
var camera_lift := 0.0
var required_lift := 0.0
var _clearance_probes := 0
var _clearance_activations := 0
var _peak_required_lift := 0.0

func _init(terrain: Node3D, terrain_profile: RefCounted, region_navigation: RefCounted) -> void:
	profile = terrain_profile
	navigation = region_navigation
	_bounds = navigation.region.bounds
	_index(terrain)

func reset() -> void:
	initialized = false
	stop()

func stop() -> void:
	following_walk = false
	_local_walking = false
	desired_focus = camera_focus

func follow(pos: Vector3, walking: bool) -> void:
	if not pos.is_finite() or not navigation.contains(Vector2(pos.x, pos.z)):
		stop()
		return
	var target := Vector3(clampf(pos.x, _bounds.min.x, _bounds.max.x), pos.y + 1.8,
		clampf(pos.z - LOOK_AHEAD, _bounds.min.y - LOOK_AHEAD, _bounds.max.y - LOOK_AHEAD))
	if not initialized:
		initialized = true
		camera_focus = target
		desired_focus = target
		_local_ground = Vector3(pos.x, surface_height(pos.x, pos.z), pos.z)
		required_lift = _clearance_required(camera_focus + OFFSET, _local_ground)
		camera_lift = minf(required_lift, MAX_CLEARANCE_LIFT)
	if not walking:
		stop()
		return
	_local_ground = Vector3(pos.x, surface_height(pos.x, pos.z), pos.z)
	_local_walking = true
	if absf(target.x - camera_focus.x) > QUIET_HALF_WIDTH or absf(target.z - camera_focus.z) > QUIET_HALF_WIDTH:
		following_walk = true
	if following_walk:
		desired_focus = target

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0 or not _local_walking:
		return
	if following_walk:
		camera_focus = camera_focus.lerp(desired_focus, 1.0 - exp(-minf(delta, 0.25) * 1.5))
	required_lift = _clearance_required(camera_focus + OFFSET, _local_ground)
	var goal := minf(required_lift, MAX_CLEARANCE_LIFT)
	camera_lift = move_toward(camera_lift, goal, minf(delta, 0.25) * (LIFT_RISE_SPEED if goal > camera_lift else LIFT_FALL_SPEED))

func apply_camera(camera: Camera3D, zoom: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_FOV * 0.5)) * clampf(zoom, 0.8, 1.18)))
	camera.near = 0.1
	camera.far = 600.0
	camera.position = camera_focus + OFFSET + Vector3.UP * camera_lift
	camera.look_at(camera_focus)

func _clearance_required(camera_base: Vector3, target: Vector3) -> float:
	# A triangulated heightfield is linear between x-grid, z-grid and diagonal
	# crossings. Checking those crossings finds the whole intervening ridge,
	# unlike sparse fixed-distance probes, without scanning every triangle.
	var crossing: Array[float] = [0.0]
	var target_height := surface_height(target.x, target.z)
	var start := Vector2(camera_base.x, camera_base.z)
	var end := Vector2(target.x, target.z)
	for pair in [[float(start.x), float(end.x)], [float(start.y), float(end.y)], [float(start.x) - float(start.y), float(end.x) - float(end.y)]]:
		var difference: float = pair[1] - pair[0]
		if difference == 0:
			continue
		for line in range(ceili(minf(pair[0], pair[1])), floori(maxf(pair[0], pair[1])) + 1):
			var t: float = (line - pair[0]) / difference
			if t > 0 and t < 1:
				crossing.append(t)
	var minimum_y := camera_base.y
	_clearance_probes = 0
	for t in crossing:
		var x := float(start.x) + (float(end.x) - float(start.x)) * t
		var z := float(start.y) + (float(end.y) - float(start.y)) * t
		var height := surface_height(x, z)
		_clearance_probes += 1
		if is_finite(height):
			minimum_y = maxf(minimum_y, (height - target_height * t) / (1.0 - t) + 0.6)
	# Only spatial buckets crossed by this short camera/herder rectangle. Bounds
	# conservatively cover solid foliage; grass is intentionally never indexed.
	var candidates := {}
	for x in range(floori(minf(start.x, end.x) / 16), floori(maxf(start.x, end.x) / 16) + 1):
		for z in range(floori(minf(start.y, end.y) / 16), floori(maxf(start.y, end.y) / 16) + 1):
			for id: int in _occluder_grid.get(Vector2i(x, z), []):
				candidates[id] = true
	for id: int in candidates:
		var record: Dictionary = _occluders[id]
		if record.end > 0 and camera_base.distance_to(record.center) > record.end:
			continue
		var bounds: AABB = record.bounds
		var span := _interval([0.0, 1.0], start.x, float(end.x) - float(start.x), bounds.position.x, bounds.end.x)
		span = _interval(span, start.y, float(end.y) - float(start.y), bounds.position.z, bounds.end.z)
		if span.is_empty():
			continue
		var t: float = span[1] if bounds.end.y > target_height else span[0]
		if t >= 1.0:
			if bounds.end.y > target_height:
				minimum_y = maxf(minimum_y, camera_base.y + MAX_CLEARANCE_LIFT + 1)
			continue
		minimum_y = maxf(minimum_y, (bounds.end.y - target_height * t) / (1.0 - t) + 0.6)
	var lift := maxf(0.0, minimum_y - camera_base.y)
	_peak_required_lift = maxf(_peak_required_lift, lift)
	_clearance_activations += int(lift > 0.001)
	return lift

func ground_at(camera: Camera3D, screen: Vector2) -> Vector3:
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if not screen.is_finite() or screen.x < 0 or screen.y < 0 or screen.x > viewport_size.x or screen.y > viewport_size.y:
		return Vector3.INF
	return ray_ground(camera.project_ray_origin(screen), camera.project_ray_normal(screen), camera.far)

func _surface_cell(x: float, z: float) -> Dictionary:
	if not is_finite(x) or not is_finite(z) or x < _minimum.x or x > _maximum.x or z < _minimum.y or z > _maximum.y:
		return {}
	var ix := mini(floori(x), ceili(_maximum.x) - 1)
	var iz := mini(floori(z), ceili(_maximum.y) - 1)
	var key := Vector2i(floori(ix / 16.0), floori(iz / 16.0))
	if not _ground_chunks.has(key):
		return {}
	var record: Dictionary = _ground_chunks[key]
	var cell := (iz - key.y * 16) * 16 + ix - key.x * 16
	return {"record": record, "cell": cell, "fx": x - ix, "fz": z - iz}

func surface_height(x: float, z: float) -> float:
	# Prepared vertices, including their float32 rounding, are the runtime truth.
	# Missing fine geometry fails closed; never regenerate a different height.
	var sample := _surface_cell(x, z)
	if sample.is_empty():
		return NAN
	var record: Dictionary = sample.record
	var index: int = sample.cell * 6
	var a: float = record.vertices[record.indices[index]].y
	var b: float = record.vertices[record.indices[index + 1]].y
	var c: float = record.vertices[record.indices[index + 2]].y
	var d: float = record.vertices[record.indices[index + 5]].y
	if sample.fz <= sample.fx:
		return a + (b - a) * sample.fx + (c - b) * sample.fz
	return a + (c - d) * sample.fx + (d - a) * sample.fz

func surface_normal(x: float, z: float) -> Vector3:
	var sample := _surface_cell(x, z)
	if sample.is_empty():
		return Vector3.INF
	var record: Dictionary = sample.record
	var index: int = sample.cell * 6
	if sample.fx == 0 and sample.fz == 0:
		return record.normals[record.indices[index]]
	if sample.fz > sample.fx:
		index += 3
	var a: Vector3 = record.vertices[record.indices[index]]
	var b: Vector3 = record.vertices[record.indices[index + 1]]
	var c: Vector3 = record.vertices[record.indices[index + 2]]
	return (c - a).cross(b - a).normalized()

func ray_ground(origin: Vector3, direction: Vector3, max_distance := 600.0) -> Vector3:
	_cells_visited = 0
	_triangles_tested = 0
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001 or not is_finite(max_distance) or max_distance <= 0:
		return Vector3.INF
	var ray := direction.normalized()
	var point := _ground_hit(origin, ray, max_distance)
	var limit := origin.distance_to(point) if point.is_finite() else max_distance
	# Scenic ring and solid off-route props can conceal walking ground. Never
	# skip them to accept a target behind the visible foreground surface.
	for record in _occluders:
		if record.end > 0 and origin.distance_to(record.center) > record.end:
			continue
		if _box_interval(origin, ray, record.bounds, limit).is_empty():
			continue
		var hit := _mesh_hit(record, origin, ray, limit)
		if hit.is_finite():
			return Vector3.INF
	if not point.is_finite() or not navigation.contains(Vector2(point.x, point.z)):
		return Vector3.INF
	point.y = surface_height(point.x, point.z)
	return point

func _index(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if String(instance.name).begins_with("Ground_"):
			var arrays := instance.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if vertices.size() == 289 and indices.size() == 1536:
				var transformed := PackedVector3Array()
				var transformed_normals := PackedVector3Array()
				var normal_basis := instance.global_basis.inverse().transposed()
				for vertex in vertices:
					transformed.append(instance.global_transform * vertex)
				for normal in normals:
					transformed_normals.append((normal_basis * normal).normalized())
				var corner := transformed[0]
				var key := Vector2i(floori(corner.x / 16), floori(corner.z / 16))
				_ground_chunks[key] = {"vertices": transformed, "normals": transformed_normals, "indices": indices}
				_minimum = _minimum.min(Vector2(corner.x, corner.z))
				_maximum = _maximum.max(Vector2(corner.x + 16, corner.z + 16))
		else:
			_add_occluder(instance.mesh, instance.global_transform, instance.visibility_range_end, instance.global_transform * instance.mesh.get_aabb().get_center())
	elif node is MultiMeshInstance3D and not String(node.name).begins_with("WindGrass_"):
		var instance := node as MultiMeshInstance3D
		var multi := instance.multimesh
		var buffer := multi.buffer
		var stride := 12 + (4 if multi.use_colors else 0) + (4 if multi.use_custom_data else 0)
		if multi.transform_format == MultiMesh.TRANSFORM_3D and buffer.size() == multi.instance_count * stride:
			var center: Vector3 = instance.global_transform * multi.custom_aabb.get_center()
			for i in multi.instance_count:
				var offset := i * stride
				var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]), Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]), Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
				var transform := Transform3D(basis, Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11]))
				_add_occluder(multi.mesh, instance.global_transform * transform, instance.visibility_range_end, center)
	for child in node.get_children():
		_index(child)

func _add_occluder(mesh: Mesh, transform: Transform3D, end: float, center: Vector3) -> void:
	if mesh == null:
		return
	var surfaces: Array = []
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		surfaces.append({"vertices": arrays[Mesh.ARRAY_VERTEX], "indices": arrays[Mesh.ARRAY_INDEX]})
	var bounds: AABB = transform * mesh.get_aabb()
	var id := _occluders.size()
	_occluders.append({"surfaces": surfaces, "transform": transform, "inverse": transform.affine_inverse(), "bounds": bounds, "end": end, "center": center})
	for x in range(floori(bounds.position.x / 16), floori(bounds.end.x / 16) + 1):
		for z in range(floori(bounds.position.z / 16), floori(bounds.end.z / 16) + 1):
			var key := Vector2i(x, z)
			if not _occluder_grid.has(key):
				_occluder_grid[key] = []
			_occluder_grid[key].append(id)

func _ground_hit(origin: Vector3, direction: Vector3, limit: float) -> Vector3:
	if _ground_chunks.is_empty():
		return Vector3.INF
	# Clip in x/z, then traverse every crossed one-unit cell in ray order.
	# Y is tested against actual stored triangles, not an analytical height probe.
	var span := _interval([0.0, limit], origin.x, direction.x, _minimum.x, _maximum.x)
	span = _interval(span, origin.z, direction.z, _minimum.y, _maximum.y)
	if span.is_empty():
		return Vector3.INF
	var entry: Vector3 = origin + direction * float(span[0])
	var x := clampi(floori(entry.x), floori(_minimum.x), ceili(_maximum.x) - 1)
	var z := clampi(floori(entry.z), floori(_minimum.y), ceili(_maximum.y) - 1)
	var step_x := 1 if direction.x > 0 else -1
	var step_z := 1 if direction.z > 0 else -1
	var next_x := INF if direction.x == 0 else ((x + 1.0 if step_x > 0 else float(x)) - origin.x) / direction.x
	var next_z := INF if direction.z == 0 else ((z + 1.0 if step_z > 0 else float(z)) - origin.z) / direction.z
	var delta_x := INF if direction.x == 0 else absf(1.0 / direction.x)
	var delta_z := INF if direction.z == 0 else absf(1.0 / direction.z)
	for iteration in 2048:
		_cells_visited += 1
		var key := Vector2i(floori(x / 16.0), floori(z / 16.0))
		if _ground_chunks.has(key):
			var record: Dictionary = _ground_chunks[key]
			var cell := (z - key.y * 16) * 16 + x - key.x * 16
			var closest := Vector3.INF
			var closest_t := INF
			for triangle in 2:
				var index := cell * 6 + triangle * 3
				var hit: Vector3 = _triangle_hit(origin, direction, record.vertices[record.indices[index]], record.vertices[record.indices[index + 1]], record.vertices[record.indices[index + 2]])
				_triangles_tested += 1
				if hit.is_finite():
					var distance: float = origin.distance_to(hit)
					if distance <= limit and distance < closest_t:
						closest_t = distance
						closest = hit
			if closest.is_finite():
				return closest
		var next := minf(next_x, next_z)
		if not is_finite(next) or next > float(span[1]):
			break
		if next_x <= next_z:
			x += step_x
			next_x += delta_x
		else:
			z += step_z
			next_z += delta_z
		if x < _minimum.x or x >= _maximum.x or z < _minimum.y or z >= _maximum.y:
			break
	return Vector3.INF

func _mesh_hit(record: Dictionary, origin: Vector3, direction: Vector3, limit: float) -> Vector3:
	var inverse: Transform3D = record.inverse
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	for surface in record.surfaces:
		var vertices: PackedVector3Array = surface.vertices
		var indices: Variant = surface.indices
		var indexed: bool = indices is PackedInt32Array and not indices.is_empty()
		var count: int = indices.size() if indexed else vertices.size()
		for i in range(0, count, 3):
			var hit := _triangle_hit(local_origin, local_direction, vertices[indices[i] if indexed else i], vertices[indices[i + 1] if indexed else i + 1], vertices[indices[i + 2] if indexed else i + 2])
			_triangles_tested += 1
			if hit.is_finite():
				var world: Vector3 = record.transform * hit
				if origin.distance_to(world) < limit - 0.0001:
					return world
	return Vector3.INF

static func _triangle_hit(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Scalar binary64 arithmetic over the unchanged float32 mesh/ray. Native
	# float32 barycentrics can miss both faces at a shared grid corner. No
	# geometric epsilon, widened triangle or relaxed walkability is used here.
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
		return Vector3.INF
	var tx := float(origin.x) - float(a.x)
	var ty := float(origin.y) - float(a.y)
	var tz := float(origin.z) - float(a.z)
	var u := (tx * px + ty * py + tz * pz) / determinant
	if u < 0 or u > 1:
		return Vector3.INF
	var qx := ty * ez - tz * ey
	var qy := tz * ex - tx * ez
	var qz := tx * ey - ty * ex
	var v := (float(direction.x) * qx + float(direction.y) * qy + float(direction.z) * qz) / determinant
	if v < 0 or u + v > 1:
		return Vector3.INF
	var distance := (fx * qx + fy * qy + fz * qz) / determinant
	if distance < 0:
		return Vector3.INF
	return Vector3(float(origin.x) + float(direction.x) * distance, float(origin.y) + float(direction.y) * distance, float(origin.z) + float(direction.z) * distance)

static func _interval(span: Array, origin: float, direction: float, low: float, high: float) -> Array:
	if span.is_empty():
		return []
	if direction == 0:
		return span if origin >= low and origin <= high else []
	var a := (low - origin) / direction
	var b := (high - origin) / direction
	var enter := maxf(span[0], minf(a, b))
	var leave := minf(span[1], maxf(a, b))
	return [enter, leave] if enter <= leave else []

static func _box_interval(origin: Vector3, direction: Vector3, bounds: AABB, limit: float) -> Array:
	var span := _interval([0.0, limit], origin.x, direction.x, bounds.position.x, bounds.end.x)
	span = _interval(span, origin.y, direction.y, bounds.position.y, bounds.end.y)
	return _interval(span, origin.z, direction.z, bounds.position.z, bounds.end.z)

func debug_state() -> Dictionary:
	return {"ground_chunks": _ground_chunks.size(), "occluders": _occluders.size(), "cells_visited": _cells_visited, "triangles_tested": _triangles_tested, "minimum": _minimum, "maximum": _maximum,
		"camera_lift": camera_lift, "required_lift": required_lift, "peak_required_lift": _peak_required_lift, "clearance_probes": _clearance_probes, "clearance_activations": _clearance_activations}
