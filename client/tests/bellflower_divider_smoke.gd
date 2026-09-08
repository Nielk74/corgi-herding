extends SceneTree
## Regression for the thin dark fork-divider crest seen on Android.
## This changes no geometry. The unreleased v6 bank refinement changes rendered
## heights near the union boundary, but not its canonical walking footprint.

const Meadow = preload("res://scripts/meadow.gd")
const Navigation = preload("res://scripts/commons_navigation.gd")
const STEP := 0.75
const MIN_FACE_UP := 0.80
const MIN_NORMAL_ALIGNMENT := 0.85
var checks := 0
var failures := 0
var faces := PackedVector3Array()
var minimum_up := 1.0
var minimum_alignment := 1.0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("BELLFLOWER_DIVIDER_FAILED: " + message)

func _run() -> void:
	var meadow := Meadow.new()
	root.add_child(meadow)
	await process_frame
	meadow.set_process(false)
	meadow.set_landscape("bellflower")
	await process_frame
	var ground := meadow.terrain.get_node("ValleyGroundBellflower") as MeshInstance3D
	_check(ground.transform == Transform3D.IDENTITY, "Divider extraction assumes untransformed terrain")
	_check(meadow.commons == Navigation.default_commons(), "Art refinement cannot alter canonical walking union")
	var vertex_data := {}
	var edge_counts := {}
	var triangle_counts := {}
	var projected_area := 0.0
	for surface in ground.mesh.get_surface_count():
		var arrays := ground.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var triangle: Array[Vector3] = []
			var stored: Array[Vector3] = []
			for corner in 3:
				var index := indices[offset + corner] if not indices.is_empty() else offset + corner
				triangle.append(vertices[index])
				stored.append(normals[index])
			if not triangle.all(_inside_patch):
				continue
			faces.append_array(PackedVector3Array(triangle))
			var area_vector := (triangle[2] - triangle[0]).cross(triangle[1] - triangle[0])
			var front := area_vector.normalized()
			minimum_up = minf(minimum_up, front.y)
			_check(area_vector.y > 0.0 and front.y >= MIN_FACE_UP, "Divider needs upward, gently sloped actual triangle fronts")
			projected_area += area_vector.y * 0.5
			var triangle_key := _triangle_key(triangle)
			triangle_counts[triangle_key] = int(triangle_counts.get(triangle_key, 0)) + 1
			for corner in 3:
				var point := triangle[corner]
				var normal := stored[corner]
				var alignment := front.dot(normal)
				minimum_alignment = minf(minimum_alignment, alignment)
				_check(point.is_finite() and normal.is_finite() and absf(normal.length() - 1.0) < 0.0001, "Actual divider vertices/normals must be finite and unit")
				_check(alignment >= MIN_NORMAL_ALIGNMENT, "Stored normal disagrees with its actual triangle front")
				_check(absf(point.y - meadow.surface_height(point.x, point.z)) < 0.0001, "Rendered divider and ray-picked height source disagree")
				var key := _point_key(point)
				if vertex_data.has(key):
					_check(vertex_data[key].point == point and vertex_data[key].normal.distance_to(normal) < 0.00001, "Shared divider edge has split heights or shading normals")
				else:
					vertex_data[key] = {"point": point, "normal": normal}
				var edge := _edge_key(point, triangle[(corner + 1) % 3])
				edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
	_check(faces.size() == 128 * 3 and vertex_data.size() == 81, "Complete 8x8-cell divider patch must have exactly 128 triangles and 81 welded vertices")
	_check(absf(projected_area - 36.0) < 0.00001, "Divider projected area must cover the entire 6x6 patch")
	var paired := 0
	var perimeter := 0
	for count in edge_counts.values():
		_check(count in [1, 2], "Divider has a nonmanifold or duplicate edge")
		paired += 1 if count == 2 else 0
		perimeter += 1 if count == 1 else 0
	_check(paired == 176 and perimeter == 32, "Every interior edge must be paired, with only the 32 outer patch edges open")
	for ix in range(8, 16):
		for iz in range(-4, 4):
			var a := Vector3(ix * STEP, 0, iz * STEP)
			var b := a + Vector3(STEP, 0, 0)
			var c := a + Vector3(STEP, 0, STEP)
			var d := a + Vector3(0, 0, STEP)
			for expected in [[a, b, c], [a, c, d]]:
				_check(triangle_counts.get(_triangle_key(expected), 0) == 1, "Missing/overlapping divider cell or altered sampling diagonal")
	var ray_count := 0
	var maximum_ray_error := 0.0
	var old_faces := _old_crest()
	var negative_occlusions := 0
	var negative_slopes := 0
	for offset in range(0, old_faces.size(), 3):
		var front := (old_faces[offset + 2] - old_faces[offset]).cross(old_faces[offset + 1] - old_faces[offset]).normalized()
		negative_slopes += 1 if front.y < MIN_FACE_UP else 0
	_check(negative_slopes >= 4, "Frozen original crest must fail the same gentle-face predicate")
	# The old vertex normal at (7.5,-.75) poorly matched one adjacent surface.
	var old_front := (old_faces[8] - old_faces[6]).cross(old_faces[7] - old_faces[6]).normalized()
	var old_normal := Vector3(-0.273181642, 0.637152068, -0.720700376)
	_check(old_front.dot(old_normal) < MIN_NORMAL_ALIGNMENT, "Frozen old shading mismatch must fail the same normal predicate")
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = viewport_size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = viewport_size
		await process_frame
		_check(root.size == viewport_size and root.get_visible_rect().size == Vector2(viewport_size), "Require matching actual physical and logical portrait viewports")
		for pan in [-6.0, 6.0]:
			meadow.camera_focus.x = pan
			meadow.desired_focus.x = pan
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow._process(0.0)
				var before_rays := ray_count
				for offset in range(0, faces.size(), 3):
					var foot := (faces[offset] + faces[offset + 1] + faces[offset + 2]) / 3.0
					if foot.x < 6.75 or foot.x > 11.25 or absf(foot.z) > 1.5:
						continue
					var screen: Vector2 = meadow.camera.unproject_position(foot)
					if not Rect2(Vector2.ZERO, Vector2(viewport_size)).has_point(screen):
						continue
					_check(absf(foot.y - meadow.surface_height(foot.x, foot.z)) < 0.0001, "Triangle-interior sample differs from actual divider mesh")
					var origin: Vector3 = meadow.camera.project_ray_origin(screen)
					var direction: Vector3 = meadow.camera.project_ray_normal(screen)
					var hit := _first_hit(faces, origin, origin + direction * meadow.camera.far)
					var error := hit.distance_to(foot) if hit.is_finite() else INF
					maximum_ray_error = maxf(maximum_ray_error, error)
					_check(error < 0.002, "Actual camera ray encounters an earlier divider crest or hole")
					ray_count += 1
				if pan > 0.0:
					_check(ray_count - before_rays == 48, "All 48 crest probes must be visible at the requested right-follow extreme")
				for offset in range(0, old_faces.size(), 3):
					var foot := (old_faces[offset] + old_faces[offset + 1] + old_faces[offset + 2]) / 3.0
					var screen: Vector2 = meadow.camera.unproject_position(foot)
					var origin: Vector3 = meadow.camera.project_ray_origin(screen)
					var hit := _first_hit(old_faces, origin, foot.move_toward(origin, 0.025))
					negative_occlusions += 1 if hit.is_finite() else 0
	_check(ray_count >= 350, "Insufficient actual portrait crest-ray coverage")
	_check(negative_occlusions >= 12, "Frozen old mesh must reproduce local camera-direction self-occlusion")
	print("BELLFLOWER_DIVIDER: %d checks / %d failures; 128 actual triangles / 81 vertices / %d paired edges; front up >= %.4f, normal alignment >= %.4f; %d portrait rays, max error %.6f; old crest rejects %d slopes / %d self-occlusions; canonical union unchanged" % [checks, failures, paired, minimum_up, minimum_alignment, ray_count, maximum_ray_error, negative_slopes, negative_occlusions])
	meadow.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _inside_patch(point: Vector3) -> bool:
	return point.x >= 6.0 and point.x <= 12.0 and point.z >= -3.0 and point.z <= 3.0

func _point_key(point: Vector3) -> String:
	return "%d:%d" % [roundi(point.x / STEP), roundi(point.z / STEP)]

func _edge_key(a: Vector3, b: Vector3) -> String:
	var keys := [_point_key(a), _point_key(b)]
	keys.sort()
	return "|".join(keys)

func _triangle_key(triangle: Array) -> String:
	var keys: Array[String] = []
	for point: Vector3 in triangle:
		keys.append(_point_key(point))
	keys.sort()
	return "|".join(keys)

func _first_hit(triangles: PackedVector3Array, origin: Vector3, endpoint: Vector3) -> Vector3:
	var result := Vector3.INF
	var nearest := INF
	for offset in range(0, triangles.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(origin, endpoint, triangles[offset], triangles[offset + 1], triangles[offset + 2])
		if hit != null and origin.distance_squared_to(hit) < nearest:
			nearest = origin.distance_squared_to(hit)
			result = hit
	return result

func _old_crest() -> PackedVector3Array:
	# Frozen original 2.1*hill*smoothstep(0,.8,outside) cells, x7.5..9/z-1.5..1.5.
	# Literal values keep the negative control independent of future profile edits.
	var heights := [
		[2.119760036, 2.904014594, 2.680330466, 2.569184504, 1.622052145],
		[2.153743498, 3.055079775, 2.645410995, 2.654230552, 1.607670421],
		[2.177149852, 2.958750727, 2.861988620, 2.595887499, 1.598269989]]
	var result := PackedVector3Array()
	for ix in 2:
		for iz in 4:
			var x := 7.5 + ix * STEP
			var z := -1.5 + iz * STEP
			var a := Vector3(x, heights[ix][iz], z)
			var b := Vector3(x + STEP, heights[ix + 1][iz], z)
			var c := Vector3(x + STEP, heights[ix + 1][iz + 1], z + STEP)
			var d := Vector3(x, heights[ix][iz + 1], z + STEP)
			result.append_array(PackedVector3Array([a, b, c, a, c, d]))
	return result
