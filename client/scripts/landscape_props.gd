extends RefCounted
## Reusable, deterministic scenic props. They never define walking collision.
## Each returned chunk owns its batched children and retained CPU transforms.

const MAX_TALL := 12
const MAX_STONES := 6
const MAX_SCRUB := 6
const VARIANTS := 3
const FOOTPRINT_GAP := 0.25

var recipe: RefCounted
var meshes: Dictionary = {}
var bark: StandardMaterial3D
var needles: StandardMaterial3D
var succulent: StandardMaterial3D
var stone: StandardMaterial3D
var brush: StandardMaterial3D

func _init(profile: RefCounted, use_textures := true) -> void:
	recipe = profile
	bark = _material(Color("696254"))
	needles = _material(Color("637a56"))
	succulent = _material(Color("819472"))
	brush = _material(Color("8c916b"))
	stone = _material(Color("b2b2aa"))
	if use_textures:
		var base := "res://assets/materials/rock_01/rock_01"
		stone.albedo_texture = load(base + "_diff_1k.jpg")
		stone.normal_enabled = true
		stone.normal_texture = load(base + "_nor_gl_1k.png")
		stone.normal_scale = 0.6
		stone.roughness_texture = load(base + "_rough_1k.jpg")
		stone.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		stone.uv1_triplanar = true
		stone.uv1_world_triplanar = true
		stone.uv1_scale = Vector3.ONE * 0.8
		stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for variant in VARIANTS:
		meshes["tree_%d" % variant] = _pine(variant)
		meshes["cactus_%d" % variant] = _cactus(variant)
		meshes["stone_%d" % variant] = _stone(variant)
	meshes["scrub_0"] = _scrub()
	for mesh: ArrayMesh in meshes.values():
		mesh.set_meta("footprint_radius", _radius(mesh))
		mesh.set_meta("triangle_count", triangle_count(mesh))

func build_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "LandscapeProps_%d_%d" % [key.x, key.y]
	var batches: Dictionary = {}
	var counts := {"tall": 0, "stone": 0, "scrub": 0}
	var placements: Array = recipe.scatter(key)
	for i in placements.size():
		var placement: Dictionary = placements[i]
		var kind := String(placement.kind)
		var variant := (i + absi(key.x * 7 + key.y * 11)) % VARIANTS
		if kind in ["tree", "cactus"]:
			if counts.tall >= MAX_TALL:
				continue
		elif i % 11 == 0 and counts.stone < MAX_STONES:
			kind = "stone"
		elif kind == "scrub" and i % 5 == 0 and counts.scrub < MAX_SCRUB:
			variant = 0
		else:
			continue
		var mesh_key := "%s_%d" % [kind, variant]
		var mesh: ArrayMesh = meshes[mesh_key]
		var position: Vector3 = placement.position
		# Query the stored triangular surface again, even if a caller reused an
		# older scatter list. Upright trunks use a single rooted contact point.
		position.y = recipe.surface_height(position.x, position.z)
		var scale_value := float(placement.scale)
		var radius := float(mesh.get_meta("footprint_radius")) * scale_value
		# Clearance is a signed distance bound for the union. Keeping the whole
		# horizontal bounding disk outside avoids branches over walking ground.
		if float(recipe.route_clearance(Vector2(position.x, position.z))) >= -radius - FOOTPRINT_GAP:
			continue
		if not batches.has(mesh_key):
			batches[mesh_key] = []
		batches[mesh_key].append({"position": position, "scale": scale_value, "yaw": float(placement.yaw), "radius": radius})
		counts["tall" if kind in ["tree", "cactus"] else kind] += 1
	var instances := 0
	var triangles := 0
	for mesh_key: String in batches:
		var items: Array = batches[mesh_key]
		var mesh: ArrayMesh = meshes[mesh_key]
		var batch := _batch(mesh_key, mesh, items)
		chunk.add_child(batch)
		batch.owner = chunk
		instances += items.size()
		triangles += int(mesh.get_meta("triangle_count")) * items.size()
	chunk.set_meta("instances", instances)
	chunk.set_meta("triangles", triangles)
	chunk.set_meta("tall", counts.tall)
	chunk.set_meta("stones", counts.stone)
	chunk.set_meta("scrub", counts.scrub)
	return chunk

## Call after attaching a returned chunk to a larger scene before packing it.
## Default ownership already supports PackedScene.pack(chunk) independently.
static func set_scene_owner(chunk: Node, scene_owner: Node) -> void:
	if chunk != scene_owner:
		chunk.owner = scene_owner
	for child: Node in chunk.get_children():
		set_scene_owner(child, scene_owner)

static func triangle_count(mesh: ArrayMesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()) / 3
	return count

static func _radius(mesh: ArrayMesh) -> float:
	var radius := 0.0
	for i in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			radius = maxf(radius, Vector2(point.x, point.z).length())
	return radius

func _batch(id: String, mesh: ArrayMesh, placements: Array) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = placements.size()
	var buffer := PackedFloat32Array()
	buffer.resize(placements.size() * 16)
	var bounds := AABB()
	for i in placements.size():
		var p: Dictionary = placements[i]
		var basis := Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * float(p.scale))
		var transform := Transform3D(basis, p.position)
		var tint := Color.WHITE.darkened(float(i % 4) * 0.035)
		var row := PackedFloat32Array([
			basis.x.x, basis.y.x, basis.z.x, transform.origin.x,
			basis.x.y, basis.y.y, basis.z.y, transform.origin.y,
			basis.x.z, basis.y.z, basis.z.z, transform.origin.z,
			tint.r, tint.g, tint.b, tint.a,
		])
		for column in 16:
			buffer[i * 16 + column] = row[column]
		var instance_bounds: AABB = transform * mesh.get_aabb()
		bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
	# Explicit CPU storage survives dummy/headless rendering and scene packing.
	# No GPU-only setters, no per-branch nodes, no all-world culling aggregate.
	multi.buffer = buffer
	multi.custom_aabb = bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = id.to_pascal_case()
	batch.multimesh = multi
	batch.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	batch.visibility_range_end = 125.0 if id.begins_with("tree") else 95.0
	batch.extra_cull_margin = 0.1
	batch.set_meta("placements", placements)
	return batch

func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.96
	return material

func _surface(material: Material) -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	return surface

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color, outward: Vector3) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 0.000000001:
		return
	if normal.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(point)

func _tube(surface: SurfaceTool, points: Array[Vector3], radii: Array[float], sides: int, tint: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	for i in points.size():
		var tangent: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		if i == 0 and points[i] == Vector3.ZERO:
			tangent = Vector3.UP
		var side := tangent.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.5:
			side = tangent.cross(Vector3.RIGHT).normalized()
		var across := tangent.cross(side).normalized()
		var ring := PackedVector3Array()
		for j in sides:
			var angle := float(j) * TAU / sides
			ring.append(points[i] + (side * cos(angle) + across * sin(angle)) * radii[i])
		rings.append(ring)
	for i in range(points.size() - 1):
		for j in sides:
			var k := (j + 1) % sides
			var outward: Vector3 = (rings[i][j] + rings[i][k]) * 0.5 - points[i]
			var color := tint.darkened(float(j % 3) * 0.055)
			_triangle(surface, rings[i][j], rings[i + 1][j], rings[i + 1][k], color, outward)
			_triangle(surface, rings[i][j], rings[i + 1][k], rings[i][k], color, outward)
	for j in sides:
		_triangle(surface, points[0], rings[0][j], rings[0][(j + 1) % sides], tint, points[0] - points[1])
		var last := points.size() - 1
		_triangle(surface, points[last], rings[last][j], rings[last][(j + 1) % sides], tint, points[last] - points[last - 1])

func _bough(surface: SurfaceTool, root: Vector3, tip: Vector3, width: float, tint: Color) -> void:
	var along := (tip - root).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	var rings: Array[PackedVector3Array] = []
	for t in [0.32, 0.72]:
		var center := root.lerp(tip, t) + Vector3.DOWN * width * sin(t * PI) * 0.25
		var spread := width * (1.0 if t < 0.5 else 0.58)
		rings.append(PackedVector3Array([center + side * spread, center + up * spread * 0.40, center - side * spread, center - up * spread * 0.55]))
	for i in 4:
		var j := (i + 1) % 4
		var out: Vector3 = (rings[0][i] + rings[0][j]) * 0.5 - root.lerp(tip, 0.32)
		_triangle(surface, root, rings[0][j], rings[0][i], tint, out)
		_triangle(surface, rings[0][i], rings[0][j], rings[1][j], tint, out)
		_triangle(surface, rings[0][i], rings[1][j], rings[1][i], tint.lightened(0.035), out)
		_triangle(surface, rings[1][i], rings[1][j], tip, tint, out)

func _pine(variant: int) -> ArrayMesh:
	var height := 5.7 + variant * 0.42
	var trunk := _surface(bark)
	var lean := Vector3(0.08 * (variant - 1), 0, 0.07)
	_tube(trunk, [Vector3.ZERO, Vector3.UP * height * 0.35 + lean * 0.3, Vector3.UP * height * 0.72 + lean * 0.7, Vector3.UP * height + lean], [0.19, 0.15, 0.085, 0.012], 6, Color.WHITE)
	var mesh := trunk.commit()
	var crown := _surface(needles)
	for tier in 5:
		var y := 1.45 + tier * (height - 2.0) / 5.0
		var length := 1.90 - tier * 0.29 + variant * 0.025
		var count := 3 + (tier + variant) % 2
		for branch in count:
			var angle := branch * TAU / count + tier * 1.61 + variant * 0.7
			var direction := Vector3(cos(angle), 0, sin(angle))
			var size := length * (0.84 + 0.14 * sin(branch * 7.1 + tier * 4.3 + variant))
			var root := Vector3.UP * (y + 0.11 * sin(angle * 2)) + lean * (y / height)
			var tip := root + direction * size + Vector3.UP * (-0.12 + tier * 0.038 + sin(angle) * 0.13)
			_bough(crown, root, tip, size * 0.24, Color.WHITE.darkened(float(tier % 3) * 0.055))
	# Uneven narrow leaders avoid the repeated perfect-cone silhouette.
	for branch in 3:
		var angle := branch * TAU / 3 + variant
		_bough(crown, Vector3.UP * (height - 1.05) + lean, Vector3.UP * (height - 0.08 * branch) + Vector3(cos(angle), 0, sin(angle)) * 0.22 + lean, 0.16, Color.WHITE.lightened(0.03))
	crown.commit(mesh)
	return mesh

func _cactus(variant: int) -> ArrayMesh:
	var surface := _surface(succulent)
	var height := 2.8 + variant * 0.28
	_tube(surface, [Vector3.ZERO, Vector3(0.025, 0.9, 0), Vector3(-0.025, height - 0.35, 0.03), Vector3(0, height - 0.07, 0.03), Vector3(0, height, 0.03)], [0.24, 0.28, 0.23, 0.13, 0.015], 7, Color.WHITE)
	for arm in 2:
		var sign_value := -1.0 if arm == 0 else 1.0
		var y := 1.0 + arm * 0.60 + variant * 0.07
		var width := 0.87 + arm * 0.13
		var z := 0.12 if arm == 0 else -0.09
		_tube(surface, [Vector3(sign_value * 0.14, y, z), Vector3(sign_value * width * 0.75, y + 0.03, z), Vector3(sign_value * width, y + 0.30, z), Vector3(sign_value * width, y + 1.12 - arm * 0.18, z), Vector3(sign_value * width, y + 1.25 - arm * 0.18, z)], [0.18, 0.19, 0.17, 0.12, 0.012], 7, Color.WHITE.darkened(0.03 * arm))
	return surface.commit()

func _stone(variant: int) -> ArrayMesh:
	var surface := _surface(stone)
	var rings: Array[PackedVector3Array] = []
	for tier in 3:
		var ring := PackedVector3Array()
		for i in 7:
			var angle := i * TAU / 7.0 + tier * 0.13
			var width: float = [0.63, 0.77, 0.38][tier] * (1.0 + 0.16 * sin(i * 3.7 + variant))
			var y: float = [0.0, 0.32, 0.65][tier] * (1.0 + variant * 0.1)
			ring.append(Vector3(cos(angle) * width, y + (0.07 * sin(i * 2.8) if tier > 0 else 0.0), sin(angle) * width * (0.70 + variant * 0.06)))
		rings.append(ring)
	for tier in 2:
		for i in 7:
			var j := (i + 1) % 7
			var out: Vector3 = (rings[tier][i] + rings[tier][j]) * 0.5 - Vector3.UP * 0.25
			_triangle(surface, rings[tier][i], rings[tier + 1][i], rings[tier + 1][j], Color.WHITE, out)
			_triangle(surface, rings[tier][i], rings[tier + 1][j], rings[tier][j], Color.WHITE, out)
	for i in 7:
		_triangle(surface, Vector3.ZERO, rings[0][i], rings[0][(i + 1) % 7], Color.WHITE, Vector3.DOWN)
		_triangle(surface, Vector3(0.06, 0.75 + variant * 0.06, -0.04), rings[2][i], rings[2][(i + 1) % 7], Color.WHITE, Vector3.UP)
	return surface.commit()

func _scrub() -> ArrayMesh:
	var surface := _surface(brush)
	for i in 4:
		var angle := i * 2.4
		var tip := Vector3(cos(angle) * 0.37, 0.42 + i * 0.065, sin(angle) * 0.37)
		_tube(surface, [Vector3.ZERO, tip * 0.65, tip], [0.025, 0.019, 0.008], 4, Color("a29b7f"))
		_bough(surface, tip * 0.42, tip + Vector3.UP * 0.14, 0.13, Color.WHITE.darkened(0.04 * i))
	return surface.commit()
