extends RefCounted
## Bounded scenic ring beyond the authoring mesh, never authoritative walking.
## Coarse cells stitch every fine border vertex rather than exposing T-junctions.

const STEP := 4
var inner: Rect2
var outer: Rect2
var profile: RefCounted
var surface_material: ShaderMaterial
var samples: Dictionary = {}
var normal_sums: Dictionary = {}
var incident_fronts: Dictionary = {}
var shared_normals: Dictionary = {}

func _init(recipe: RefCounted) -> void:
	profile = recipe
	var keys: Array[Vector2i] = profile.chunk_keys()
	var start := Vector2(keys[0] - Vector2i(2, 2)) * 16.0
	var end := Vector2(keys[-1] + Vector2i(3, 3)) * 16.0
	inner = Rect2(start, end - start)
	var outside_start := (start / 64.0).floor() * 64.0 - Vector2.ONE * 192.0
	var outside_end := (end / 64.0).ceil() * 64.0 + Vector2.ONE * 192.0
	outer = Rect2(outside_start, outside_end - outside_start)
	surface_material = ShaderMaterial.new()
	surface_material.shader = load("res://shaders/landscape_surface.gdshader")
	var ground := "coast_sand_03" if profile.data.biome == "cactus" else "aerial_grass_rock"
	for role in ["ground", "rock"]:
		var id := ground if role == "ground" else "rock_01"
		var base := "res://assets/materials/%s/%s" % [id, id]
		surface_material.set_shader_parameter(role + "_albedo", load(base + "_diff_1k.jpg"))
		surface_material.set_shader_parameter(role + "_normal", load(base + "_nor_gl_1k.png"))
		surface_material.set_shader_parameter(role + "_roughness", load(base + "_rough_1k.jpg"))
	if profile.data.biome == "alpine":
		# Reviewed against the original in the Android studio: retain real surface
		# detail, but reduce the distracting patch contrast and yellow-green cast.
		surface_material.set_shader_parameter("ground_detail_contrast", 0.76)
		surface_material.set_shader_parameter("ground_saturation", 0.72)
	if profile.data.biome == "cactus":
		surface_material.set_shader_parameter("ground_tint", Color(1.0, 0.95, 0.84))
		surface_material.set_shader_parameter("stone_tint", Color(1.0, 0.79, 0.60))
		surface_material.set_shader_parameter("snow_enabled", false)

func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ScenicRing"
	root.set_meta("not_walkable_scenery", true)
	var triangle_count := 0
	var records: Array[Dictionary] = []
	normal_sums.clear()
	incident_fronts.clear()
	shared_normals.clear()
	for chunk_x in range(int(outer.position.x / 64), int(outer.end.x / 64)):
		for chunk_z in range(int(outer.position.y / 64), int(outer.end.y / 64)):
			var vertices := PackedVector3Array()
			var indices := PackedInt32Array()
			var lookup := {}
			var triangles := 0
			for z in range(chunk_z * 64, chunk_z * 64 + 64, STEP):
				for x in range(chunk_x * 64, chunk_x * 64 + 64, STEP):
					if x >= inner.position.x and x < inner.end.x and z >= inner.position.y and z < inner.end.y:
						continue
					var points: Array[Vector2] = []
					var corners := [Vector2(x, z), Vector2(x + STEP, z), Vector2(x + STEP, z + STEP), Vector2(x, z + STEP)]
					for i in range(4):
						var a: Vector2 = corners[i]
						var b: Vector2 = corners[(i + 1) % 4]
						var divisions := STEP if _on_inner_edge(a, b) else 1
						for j in divisions:
							points.append(a.lerp(b, float(j) / divisions))
					var center := _point(x + STEP * 0.5, z + STEP * 0.5)
					for i in points.size():
						var a := _point(points[i].x, points[i].y)
						var b := _point(points[(i + 1) % points.size()].x, points[(i + 1) % points.size()].y)
						var front := (b - center).cross(a - center)
						for vertex in [center, a, b]:
							if not lookup.has(vertex):
								lookup[vertex] = vertices.size()
								vertices.append(vertex)
							indices.append(lookup[vertex])
							normal_sums[vertex] = normal_sums.get(vertex, Vector3.ZERO) + front
							if not incident_fronts.has(vertex):
								incident_fronts[vertex] = []
							incident_fronts[vertex].append(front.normalized())
						triangles += 1
			if triangles == 0:
				continue
			records.append({"name": "Scenic_%d_%d" % [chunk_x, chunk_z], "vertices": vertices, "indices": indices})
			triangle_count += triangles
	# Accumulate real adjacent faces across chunk boundaries before assigning
	# smooth shared normals; material slope/snow masks no longer reveal triangles.
	for record in records:
		var normals := PackedVector3Array()
		for point: Vector3 in record.vertices:
			normals.append(_normal_for(point))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = record.vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = record.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, surface_material)
		var instance := MeshInstance3D.new()
		instance.name = record.name
		instance.mesh = mesh
		# Distant terrain does not add costly casters to the phone-focused sun map.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
		instance.owner = root
	root.set_meta("triangle_count", triangle_count)
	return root

func _normal_for(point: Vector3) -> Vector3:
	if shared_normals.has(point):
		return shared_normals[point]
	var result: Vector3 = normal_sums[point].normalized()
	var border := (point.x in [inner.position.x, inner.end.x] and point.z >= inner.position.y and point.z <= inner.end.y) or (point.z in [inner.position.y, inner.end.y] and point.x >= inner.position.x and point.x <= inner.end.x)
	if border:
		result = profile.normal(point.x, point.z)
	var blend := 0.0
	for front: Vector3 in incident_fronts[point]:
		var dot := result.dot(front)
		var minimum_dot := front.y * 0.01
		if dot < minimum_dot:
			blend = maxf(blend, (minimum_dot - dot) / (front.y - dot))
	result = result.lerp(Vector3.UP, blend).normalized()
	shared_normals[point] = result
	return result

func _on_inner_edge(a: Vector2, b: Vector2) -> bool:
	return (a.x == b.x and a.x in [inner.position.x, inner.end.x] and minf(a.y, b.y) >= inner.position.y and maxf(a.y, b.y) <= inner.end.y) or (a.y == b.y and a.y in [inner.position.y, inner.end.y] and minf(a.x, b.x) >= inner.position.x and maxf(a.x, b.x) <= inner.end.x)

func _point(x: float, z: float) -> Vector3:
	var key := Vector2(x, z)
	if not samples.has(key):
		var distance := maxf(maxf(inner.position.x - x, x - inner.end.x), maxf(inner.position.y - z, z - inner.end.y))
		var blend := smoothstep(0.0, 56.0, distance)
		var height: float = profile.node_height(x, z) if blend < 1.0 else 0.0
		if blend > 0.0:
			var macro: float = profile.noise.get_noise_2d(x * 0.34 + 50, z * 0.34 - 39)
			var mountains := -18.0 + macro * 13.0
			for ridge: Vector4 in [Vector4(-158, -124, 88, 49), Vector4(-40, -242, 132, 62), Vector4(91, -170, 108, 44), Vector4(185, -214, 149, 63), Vector4(-230, 33, 83, 56)]:
				var dx := (x - ridge.x) / ridge.w
				var dz := (z - ridge.y) / (ridge.w * 0.8)
				var crest := exp(-(dx * dx + dz * dz) * 0.72)
				mountains += ridge.z * crest * (0.93 + macro * 0.18)
			var cuts := absf(sin(x * 0.095 + z * 0.047) + sin(z * 0.081 - x * 0.038) * 0.46)
			mountains -= cuts * smoothstep(20.0, 100.0, mountains) * 7.0
			height = lerpf(height, mountains, blend)
		samples[key] = Vector3(x, height, z)
	return samples[key]
