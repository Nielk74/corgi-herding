extends RefCounted
## Offline landscape authoring, not an accepted network layout or collision API.
## Routes are authored; only visual surface detail and scatter are seeded.

const RECIPE_VERSION := 1
const RegionValidator = preload("res://scripts/strict_region_validator.gd")
const DryLandforms = preload("res://scripts/dry_wash_landforms.gd")
const CACTUS_STYLES := {"terrain_style": "wash_terraces", "backdrop_style": "low_mesas", "trail_style": "wash_fans"}
var data: Dictionary
var noise := FastNoiseLite.new()
var route: Array[Vector3] = []
var clearings: Array[Vector3] = []
var half_width := 10.0
var lattice: Dictionary = {}
var lattice_normals: Dictionary = {}
var edges: Array[Dictionary] = []

func _init(recipe: Dictionary) -> void:
	data = recipe.duplicate(true)
	noise.seed = int(data.seed)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	for point: Array in data.route:
		route.append(Vector3(float(point[0]), float(point[2]), float(point[1])))
	for clearing: Array in data.clearings:
		clearings.append(Vector3(float(clearing[0]), float(clearing[1]), float(clearing[2])))
	half_width = float(data.half_width)
	if data.has("region_file"):
		var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.region_file))
		for edge: Dictionary in region.corridors:
			var a: Dictionary = region.anchors[int(edge.a)]
			var b: Dictionary = region.anchors[int(edge.b)]
			edges.append({"a": Vector2(a.x, a.y), "b": Vector2(b.x, b.y), "width": float(edge.half_width)})
		clearings.clear()
		for clearing: Dictionary in region.clearings:
			clearings.append(Vector3(clearing.center.x, clearing.center.y, clearing.radius))
	else:
		for i in range(route.size() - 1):
			edges.append({"a": Vector2(route[i].x, route[i].z), "b": Vector2(route[i + 1].x, route[i + 1].z), "width": half_width})

static func validate(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Recipe must be an object"]
	for key in ["recipe_version", "id", "seed", "biome", "bounds", "route", "half_width", "clearings", "chunk_size", "cell_size"]:
		if not value.has(key):
			errors.append("Missing " + key)
	if not errors.is_empty():
		return errors
	if not _number(value.recipe_version) or value.recipe_version != RECIPE_VERSION or not value.id is String or value.id.is_empty() or value.id.length() > 64:
		errors.append("Unsupported recipe version or empty id")
	if value.biome not in ["alpine", "cactus"] or not _number(value.seed) or value.seed < -2147483648.0 or value.seed > 2147483647.0 or value.seed != int(value.seed):
		errors.append("Known biome and signed 32-bit integer seed required")
	var bounds_errors: Array[String] = RegionValidator.bounds_errors(value.bounds)
	if not bounds_errors.is_empty():
		errors.append_array(bounds_errors)
		return errors
	var bounds: Array = value.bounds
	if not _number(value.half_width) or value.half_width < 4.0 or value.half_width > 24.0:
		errors.append("Author a generous but bounded route half-width")
	if not _number(value.chunk_size) or value.chunk_size != 16 or not _number(value.cell_size) or value.cell_size != 1:
		errors.append("Prototype uses 16-unit chunks and a shared 1-unit lattice")
	if not value.route is Array or value.route.size() < 2 or value.route.size() > 32:
		return ["Route needs two to 32 authored anchors"]
	for point in value.route:
		if not _tuple(point, 3):
			errors.append("Route anchors need x, z, height")
		elif point[0] < bounds[0] or point[0] > bounds[2] or point[1] < bounds[1] or point[1] > bounds[3]:
			errors.append("Route anchor outside authored bounds")
		elif absf(point[2]) > RegionValidator.MAX_HEIGHT:
			errors.append("Authored route heights must be within -128 to 128 units")
	if not value.clearings is Array or value.clearings.is_empty() or value.clearings.size() > 16:
		return ["One to 16 authored resting places required"]
	for point in value.clearings:
		if not _tuple(point, 3) or point[2] < 4.0 or point[2] > 32.0:
			errors.append("Resting places need x, z and a bounded radius")
		elif point[0] < bounds[0] or point[0] > bounds[2] or point[1] < bounds[1] or point[1] > bounds[3]:
			errors.append("Resting place center outside authored bounds")
	if value.has("region_file"):
		errors.append_array(RegionValidator.validate_file(value.region_file, bounds))
	for style in CACTUS_STYLES:
		if value.has(style) and (not value[style] is String or value[style] != CACTUS_STYLES[style] or value.biome != "cactus" or not value.has("region_file")):
			errors.append("Unsupported or unbounded " + style)
	return errors

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _tuple(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(_number)

func route_clearance(point: Vector2) -> float:
	var result := -INF
	for edge in edges:
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var delta := b - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		result = maxf(result, float(edge.width) - point.distance_to(a + delta * t))
	for clearing in clearings:
		result = maxf(result, clearing.z - point.distance_to(Vector2(clearing.x, clearing.y)))
	return result

func height(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var weighted := 0.0
	var weights := 0.0
	# Blend grades across the route's turns; choosing only the nearest segment
	# would create height discontinuities at its Voronoi boundaries.
	for i in range(route.size() - 1):
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i + 1].x, route[i + 1].z)
		var delta := b - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		var distance_squared := point.distance_squared_to(a + delta * t)
		var weight := 1.0 / pow(1.0 + distance_squared / 64.0, 3.0)
		weighted += lerpf(route[i].y, route[i + 1].y, t) * weight
		weights += weight
	var grade := weighted / maxf(weights, 0.000000000001)
	if data.get("terrain_style", "") == "wash_terraces":
		return DryLandforms.height(point, grade, route_clearance(point), noise)
	var outside := maxf(-route_clearance(point), 0.0)
	var small := noise.get_noise_2d(x, z)
	var ridged := 1.0 - absf(noise.get_noise_2d(x * 0.40 + 167.0, z * 0.65 - 53.0))
	var flank := pow(outside, 1.14) * (0.30 + ridged * 0.30)
	# One flank descends into the valley while the opposite flank rises. A
	# distance-to-route bowl would hide every distant view behind a grass wall.
	# This remains presentation-only; zero clearance keeps the authored grade.
	flank *= lerpf(-0.8, 1.0, smoothstep(-36.0, 18.0, x + sin(z * 0.023) * 15.0))
	return grade + small * (0.45 + minf(outside * 0.11, 4.0)) + flank

func trail_wear(point: Vector2) -> float:
	if data.get("trail_style", "") == "wash_fans":
		return DryLandforms.fan_wear(point, edges, noise)
	var distance := INF
	for i in range(route.size() - 1):
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i + 1].x, route[i + 1].z)
		var delta := b - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		distance = minf(distance, point.distance_to(a + delta * t))
	# A narrow worn line suggests travel; broad grassy clearings remain open to
	# wandering and herding. This visual mask is never a navigation boundary.
	var width := 1.65 + sin(point.x * 0.43 + point.y * 0.31) * 0.16
	return (1.0 - smoothstep(0.45, width, distance)) * (0.80 + sin(point.x * 0.19 - point.y * 0.23) * 0.06)

func normal(x: float, z: float) -> Vector3:
	# Shading must describe the triangulated one-unit heightfield, not a finer
	# analytical slope that can face away from a steep stored triangle.
	if x != floorf(x) or z != floorf(z):
		var corners := _cell_points(floorf(x), floorf(z))
		return ((corners[2] - corners[0]).cross(corners[1] - corners[0]) if z - floorf(z) <= x - floorf(x) else (corners[3] - corners[0]).cross(corners[2] - corners[0])).normalized()
	var key := Vector2(x, z)
	if lattice_normals.has(key):
		return lattice_normals[key]
	var sum := Vector3.ZERO
	var fronts: Array[Vector3] = []
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			var corners := _cell_points(x + dx, z + dz)
			for ids in [[0, 1, 2], [0, 2, 3]]:
				var touches := false
				for id: int in ids:
					touches = touches or (corners[id].x == x and corners[id].z == z)
				if touches:
					var front: Vector3 = (corners[ids[2]] - corners[ids[0]]).cross(corners[ids[1]] - corners[ids[0]])
					sum += front
					fronts.append(front.normalized())
	var result := sum.normalized()
	# At a sharp off-route fold, one smooth normal can oppose a neighboring
	# front. Blend toward UP only as far as all incident fronts require. Every
	# heightfield face points upward, so this cannot change terrain/collision.
	var up_blend := 0.0
	for front in fronts:
		var dot := result.dot(front)
		var minimum_dot := front.y * 0.01
		if dot < minimum_dot:
			up_blend = maxf(up_blend, (minimum_dot - dot) / (front.y - dot))
	result = result.lerp(Vector3.UP, up_blend).normalized()
	lattice_normals[key] = result
	return result

func _cell_points(x: float, z: float) -> Array[Vector3]:
	return [Vector3(x, node_height(x, z), z), Vector3(x + 1, node_height(x + 1, z), z), Vector3(x + 1, node_height(x + 1, z + 1), z + 1), Vector3(x, node_height(x, z + 1), z + 1)]

func node_height(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if not lattice.has(key):
		# Match the actual mesh's float32 vertex before interpolating its face.
		lattice[key] = Vector3(0, height(x, z), 0).y
	return float(lattice[key])

func surface_height(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := x - ix
	var fz := z - iz
	var a := node_height(ix, iz)
	var b := node_height(ix + 1, iz)
	var c := node_height(ix + 1, iz + 1)
	var d := node_height(ix, iz + 1)
	if fz <= fx:
		return a + (b - a) * fx + (c - b) * fz
	return a + (c - d) * fx + (d - a) * fz

func color(x: float, z: float, up: float) -> Color:
	var variation := noise.get_noise_2d(x * 0.7 + 91.0, z * 0.7)
	var grass := Color("617c45").lerp(Color("8b995f"), variation * 0.5 + 0.5)
	var stone := Color("797b76")
	if data.biome == "cactus":
		grass = Color("b59a6e").lerp(Color("c0ab82"), variation * 0.5 + 0.5)
		stone = Color("98735b")
	return grass.lerp(stone, smoothstep(0.10, 0.42, 1.0 - up))

func chunk_keys() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var bounds: Array = data.bounds
	for x in range(floori(bounds[0] / 16.0), ceili(bounds[2] / 16.0)):
		for z in range(floori(bounds[1] / 16.0), ceili(bounds[3] / 16.0)):
			result.append(Vector2i(x, z))
	return result

func scatter(key: Vector2i, attempts := 80) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	# Per-chunk RNG makes generation order, visibility and thread scheduling
	# irrelevant. This is visual distribution, never authoritative randomness.
	random.seed = int(data.seed) ^ (key.x * 73856093) ^ (key.y * 19349663)
	for i in attempts:
		var x := key.x * 16.0 + random.randf_range(0.4, 15.6)
		var z := key.y * 16.0 + random.randf_range(0.4, 15.6)
		var point := Vector2(x, z)
		if x < data.bounds[0] or x > data.bounds[2] or z < data.bounds[1] or z > data.bounds[3]:
			continue
		var up := normal(x, z).y
		if up < 0.70:
			continue
		var clearance := route_clearance(point)
		var density := noise.get_noise_2d(x * 1.3 + 200.0, z * 1.3 - 80.0)
		if density < -0.12:
			continue
		var kind := "grass"
		if clearance < -2.5 and i % 7 == 0:
			kind = "cactus" if data.biome == "cactus" else "tree"
		elif data.biome == "cactus":
			kind = "scrub"
		var scale_value := random.randf_range(0.65, 1.3)
		var base := Vector3(x, 0, z)
		base.y = surface_height(base.x, base.z)
		result.append({"kind": kind, "position": base, "scale": scale_value, "yaw": random.randf_range(-PI, PI), "phase": random.randf_range(0, TAU)})
	return result
