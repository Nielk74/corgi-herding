extends SceneTree
## Actual stored-mesh authoring QA, not server authorization or Android art/FPS.
const Recipe = preload("res://scripts/landscape_recipe.gd")
const FullScene = preload("res://scripts/landscape_scene_builder.gd")
const Backdrop = preload("res://scripts/landscape_backdrop.gd")
const Landforms = preload("res://scripts/dry_wash_landforms.gd")
const Navigation = preload("res://scripts/region_navigation.gd")
const BASE_PROFILE_SHA := "0a2d682557bbd15404086285259619fd86cecd31ceabf9aeeea544b3a0c743a9"
const BASE_BACKDROP_SHA := "87ed999812bc3330d6316dbcff91d75546e54d686fa6279cabd1178e47cae0f1"
const BASE_SHARED_SOURCES := {
	"res://scripts/landscape_scene_builder.gd": "b9ce6e4b2c6d231f929b219d1800f14bb9919c2b0be77becdc11bdd9894edaab",
	"res://scripts/landscape_chunk_builder.gd": "309de1e42336bb535df3c2358410e6f8a0a943b96776c9db8fac47ab274becce",
	"res://scripts/landscape_props.gd": "cadc5924d2603700b30eed8abfea129889864ae7dda533fb796806e83576eae2",
	"res://scripts/landscape_scree.gd": "68328fc43ebe6cb8f07b2afa616dc0c3333cf7a1f8de8a25fcd4193bd9137343",
	"res://scripts/region_navigation.gd": "a28ee940dc2ca85c4e015b32a5428654c8a1eb7ab1dd9db88a74da030ef91784",
	"res://worlds/regions/alpine_valley_01.json": "52adeeb79a412860519061fe95bab88e308d7933d001fcd850b9902b4e7de0d6",
	"res://worlds/long_valley.recipe.json": "0e1fd000bc3c6ec4e25e34a093a59d3e0c93b7faa5cea204ff8e4b68be4827e0"
}
var checks := 0
var failures := 0
var kinds := {}
var cells := {}
var node_normals := {}
var node_heights := {}
var legal_faces := 0
var peak_slope := 0.0
var peak_normal_angle := 0.0
var boundary_samples := 0
var peak_wear := 0.0
var peak_location := Vector2.ZERO
var bank_negative_controls := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if not kinds.has(message):
			printerr("DRY_WASH_FAILED: " + message)
		kinds[message] = int(kinds.get(message, 0)) + 1

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/dry_wash.recipe.json"))
	_validation(data)
	if not Recipe.validate(data).is_empty():
		quit(1)
		return
	var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.region_file))
	var original_region := region.duplicate(true)
	var navigation := Navigation.new(region)
	check(navigation.valid and region.corridors.size() == 13, "Explicit 13-corridor art region validates independently")
	var profile := Recipe.new(data)
	var world := FullScene.new(profile).build()
	root.add_child(world)
	_ground(world, profile, navigation, region)
	_boundaries(profile, navigation, region)
	_fans(profile, navigation, region)
	_mesas(world, profile)
	check(region == original_region and navigation.region == original_region, "Height/style generation does not mutate canonical walking geometry")
	check(world.get_meta("prototype_not_network_layout", false), "Generated art explicitly remains separate from accepted network layout")
	for node: Node in world.find_children("*", "", true, false):
		check(not node is CollisionObject3D, "No generated terrain/detail node grants new physics walking authority")
	world.free()
	await process_frame
	_alpine_unchanged()
	print("DRY_WASH_LANDFORMS: %d checks/%d failures; %d legal-intersecting stored faces, peak slope %.4f degrees at %s; adjacent normal angle %.4f; %d boundary picks; peak stored wear %.5f. Same-runtime Alpine comparison; no Android acceptance." % [checks, failures, legal_faces, peak_slope, peak_location, peak_normal_angle, boundary_samples, peak_wear])
	if failures:
		print(kinds)
	quit(1 if failures else 0)

func _validation(data: Dictionary) -> void:
	check(Recipe.validate(data).is_empty(), "Reviewed dry recipe/style combination validates")
	for key in ["terrain_style", "backdrop_style", "trail_style"]:
		for value in [null, false, true, 0, 1.0, [], {}, "", "unknown"]:
			var bad := data.duplicate(true)
			bad[key] = value
			check(not Recipe.validate(bad).is_empty(), "Malformed " + key + " rejected without construction")
		var alpine := data.duplicate(true)
		alpine.biome = "alpine"
		check(not Recipe.validate(alpine).is_empty(), "Dry style never silently activates in Alpine biome")
		var missing := data.duplicate(true)
		missing.erase("region_file")
		check(not Recipe.validate(missing).is_empty(), "Dry style requires explicit bounded region source")
	var shader := FileAccess.get_file_as_string("res://shaders/landscape_surface.gdshader")
	check(shader.contains("uniform bool wash_enabled = false;") and not shader.contains("ALPHA =") and not shader.contains("VERTEX =") and not shader.contains("VERTEX.y"), "Wash shading is opt-in, opaque and never displaces walking geometry")
	var blocks := RegEx.new()
	check(blocks.compile("(?s)\\tif \\(wash_enabled\\) \\{\\n.*?\\n\\t\\}\\n") == OK and blocks.search_all(shader).size() == 2, "Exactly two dry-only material branches are isolated")
	var original_shader := blocks.sub(shader, "", true).replace("uniform bool wash_enabled = false;\n", "")
	check(original_shader.sha256_text() == "698b4c7ccfd7a0b1601adca00b56790164812cef61b5638eed414317bea7c76b", "Default Alpine shader outside the opt-in branches matches exact frozen 82cd572")
	var triangle: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
	var crossing := {"anchors": [], "corridors": [], "clearings": [{"center": {"x": 0.8, "y": 0.8}, "radius": 0.5}]}
	check(_intersects_legal(triangle, crossing), "Triangle-edge disk intersection is detected even when every stored corner is outside")
	crossing.clearings[0].radius = 0.3
	check(not _intersects_legal(triangle, crossing), "Nearby but disjoint disk negative control stays outside")

func _distance2(point: Vector2, a: Vector2, b: Vector2) -> float:
	# Scalar doubles keep tangencies in the exhaustive triangle/capsule test
	# independent of float32 projection into Vector2's stored coordinates.
	var dx := float(b.x) - float(a.x)
	var dy := float(b.y) - float(a.y)
	var px := float(point.x) - float(a.x)
	var py := float(point.y) - float(a.y)
	var ratio := clampf((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1)
	var ex := px - dx * ratio
	var ey := py - dy * ratio
	return ex * ex + ey * ey

func _inside_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).cross(p - a)
	var second := (c - b).cross(p - b)
	var third := (a - c).cross(p - c)
	return (first >= 0 and second >= 0 and third >= 0) or (first <= 0 and second <= 0 and third <= 0)

func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var first := (b - a).cross(c - a)
	var second := (b - a).cross(d - a)
	var third := (d - c).cross(a - c)
	var fourth := (d - c).cross(b - c)
	if first == 0 and second == 0:
		return maxf(minf(a.x, b.x), minf(c.x, d.x)) <= minf(maxf(a.x, b.x), maxf(c.x, d.x)) and maxf(minf(a.y, b.y), minf(c.y, d.y)) <= minf(maxf(a.y, b.y), maxf(c.y, d.y))
	return first * second <= 0 and third * fourth <= 0

func _intersects_legal(points: Array[Vector2], region: Dictionary) -> bool:
	for clearing: Dictionary in region.clearings:
		var center := Vector2(clearing.center.x, clearing.center.y)
		if _inside_triangle(center, points[0], points[1], points[2]):
			return true
		for i in 3:
			if _distance2(center, points[i], points[(i + 1) % 3]) <= float(clearing.radius) * float(clearing.radius):
				return true
	for edge: Dictionary in region.corridors:
		var a := Vector2(region.anchors[int(edge.a)].x, region.anchors[int(edge.a)].y)
		var b := Vector2(region.anchors[int(edge.b)].x, region.anchors[int(edge.b)].y)
		if _inside_triangle(a, points[0], points[1], points[2]) or _inside_triangle(b, points[0], points[1], points[2]):
			return true
		for i in 3:
			var c := points[i]
			var d := points[(i + 1) % 3]
			if _segments_cross(a, b, c, d):
				return true
			var nearest := minf(minf(_distance2(a, c, d), _distance2(b, c, d)), minf(_distance2(c, a, b), _distance2(d, a, b)))
			if nearest <= float(edge.half_width) * float(edge.half_width):
				return true
	return false

func _ground(world: Node3D, profile: RefCounted, navigation: RefCounted, region: Dictionary) -> void:
	check(Landforms.BENCH_WIDTH == 2.5 and Landforms.BENCH_WIDTH > sqrt(2.0), "Outside bench exceeds a full stored one-unit triangle diameter")
	var total := 0
	for child: Node in world.get_children():
		if not child is MeshInstance3D or not String(child.name).begins_with("Ground_"):
			continue
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in vertices.size():
			var p := Vector2(vertices[i].x, vertices[i].z)
			if node_normals.has(p):
				check(node_normals[p] == normals[i], "Actual adjacent chunks share exactly encoded normals")
				check(node_heights[p] == vertices[i].y, "Actual adjacent chunks share exact stored heights without seam steps")
			node_normals[p] = normals[i]
			node_heights[p] = vertices[i].y
			check(vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1) < 0.00001, "Stored terrain vertices/normals are finite and normalized")
			var wear := 1.0 - colors[i].a
			peak_wear = maxf(peak_wear, wear)
			check(wear >= 0 and wear <= 0.22, "Actual encoded wash wear is bounded at 0.22")
			if wear > 0:
				# Positive interior margin means one closed capsule/disk contains
				# the whole face, so interpolated paint cannot escape between nodes.
				check(navigation.contains(p) and navigation.signed_clearance(p) > sqrt(2.0), "Painted source vertex lies more than an entire face diameter inside legal ground")
		for i in range(0, indices.size(), 3):
			total += 1
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			var points: Array[Vector2] = [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]
			var key := Vector2i(floori(minf(a.x, minf(b.x, c.x))), floori(minf(a.z, minf(b.z, c.z))))
			if not cells.has(key):
				cells[key] = []
			cells[key].append([a, b, c])
			if not _intersects_legal(points, region):
				continue
			legal_faces += 1
			var front := (c - a).cross(b - a).normalized()
			var slope := rad_to_deg(acos(clampf(front.y, -1, 1)))
			if slope > peak_slope:
				peak_slope = slope
				peak_location = (points[0] + points[1] + points[2]) / 3
			check(front.y > 0 and slope <= 20.0, "Every stored triangle intersecting legal ground stays at or below 20 degrees")
			for j in 3:
				var p := points[j]
				var clearance: float = navigation.signed_clearance(p)
				check(clearance >= -sqrt(2.0) - 0.00005, "Independent full triangle/union intersection bounds every corner's outside distance")
				check(Landforms.height(p, 0, clearance, profile.noise) == Landforms.height(p, 0, 0, profile.noise), "Outer bank amplitude cannot enter any legal-intersecting triangle corner")
				if clearance < -0.3 and Landforms.height(p, 0, clearance - Landforms.BENCH_WIDTH, profile.noise) > Landforms.height(p, 0, clearance, profile.noise) + 0.01:
					bank_negative_controls += 1
				check(front.dot(normals[indices[i + j]]) > 0.95, "Stored normals describe actual gentle legal faces")
				var angle := rad_to_deg(acos(clampf(normals[indices[i + j]].dot(normals[indices[i + (j + 1) % 3]]), -1, 1)))
				peak_normal_angle = maxf(peak_normal_angle, angle)
				check(angle <= 15, "Adjacent stored normals do not form a sharp bank crease inside legal ground")
			for weights in [Vector3(0.2, 0.3, 0.5), Vector3(0.6, 0.2, 0.2)]:
				var p: Vector3 = a * weights.x + b * weights.y + c * weights.z
				check(absf(profile.surface_height(p.x, p.z) - p.y) < 0.00003, "Actual face-interior height matches foot/pick sampling")
	check(total == 114688 and legal_faces > 10000, "Full fine terrain/apron and substantial legal area were actually inspected")
	check(bank_negative_controls > 100, "Removing the bench in a counterfactual really leaks bank relief into legal-intersecting faces")

func _stored_height(p: Vector2) -> float:
	for face: Array in cells.get(Vector2i(floori(p.x), floori(p.y)), []):
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var e := Vector2(b.x - a.x, b.z - a.z)
		var f := Vector2(c.x - a.x, c.z - a.z)
		var q := p - Vector2(a.x, a.z)
		var u := q.cross(f) / e.cross(f)
		var v := e.cross(q) / e.cross(f)
		if u >= -0.000001 and v >= -0.000001 and u + v <= 1.000001:
			return a.y + u * (b.y - a.y) + v * (c.y - a.y)
	return NAN

func _boundary_point(p: Vector2, profile: RefCounted, navigation: RefCounted) -> void:
	var actual := _stored_height(p)
	check(is_finite(actual) and absf(actual - profile.surface_height(p.x, p.y)) < 0.00003, "Boundary interpolation hits actual stored terrain, not merely an infinite analytic field")
	var clearance: float = navigation.signed_clearance(p)
	if clearance >= -2.5:
		check(Landforms.height(p, 0, clearance, profile.noise) == Landforms.height(p, 0, 0, profile.noise), "Entire 2.5-unit outside bench stays free of bank relief")
	boundary_samples += 1

func _boundaries(profile: RefCounted, navigation: RefCounted, region: Dictionary) -> void:
	for clearing: Dictionary in region.clearings:
		var center := Vector2(clearing.center.x, clearing.center.y)
		for i in 72:
			var direction := Vector2.from_angle(i * TAU / 72)
			for offset in [-0.01, 0.0, 0.01, 1.4, 2.49, 2.5, 2.51]:
				_boundary_point(center + direction * (float(clearing.radius) + offset), profile, navigation)
	for edge: Dictionary in region.corridors:
		var a := Vector2(region.anchors[int(edge.a)].x, region.anchors[int(edge.a)].y)
		var b := Vector2(region.anchors[int(edge.b)].x, region.anchors[int(edge.b)].y)
		var direction := (b - a).normalized()
		var side := Vector2(-direction.y, direction.x)
		for i in 9:
			for sign_value in [-1, 1]:
				for offset in [-0.01, 0.0, 0.01, 1.4, 2.49, 2.5, 2.51]:
					_boundary_point(a.lerp(b, i / 8.0) + side * sign_value * (float(edge.half_width) + offset), profile, navigation)

func _fans(profile: RefCounted, navigation: RefCounted, region: Dictionary) -> void:
	var side_fans := 0
	for index in region.corridors.size():
		var edge: Dictionary = profile.edges[index]
		for i in range(1, 8):
			var p: Vector2 = edge.a.lerp(edge.b, i / 8.0)
			var wear: float = profile.trail_wear(p)
			check(wear > 0.12 and wear <= 0.22 and navigation.contains(p), "All 13 declared corridors have soft positive fan wear, not only the old seven-knot spine")
		if index >= 6:
			var middle: Vector2 = edge.a.lerp(edge.b, 0.5)
			var distance := INF
			for i in range(profile.route.size() - 1):
				var a: Vector3 = profile.route[i]
				var b: Vector3 = profile.route[i + 1]
				distance = minf(distance, sqrt(_distance2(middle, Vector2(a.x, a.z), Vector2(b.x, b.z))))
			if distance > 2.0 and profile.trail_wear(middle) > 0.12:
				side_fans += 1
	check(side_fans == 7, "Seven real side-branch midpoints gain fans where the old narrow angular trail had no wear")

func _mesas(world: Node3D, profile: RefCounted) -> void:
	var ring := world.get_node("ScenicRing")
	var builder := Backdrop.new(profile)
	var tops: Array = [{"count": 0, "unblended": 0, "height": -INF, "min_height": INF, "min_blend": 1.0}, {"count": 0, "unblended": 0, "height": -INF, "min_height": INF, "min_blend": 1.0}, {"count": 0, "unblended": 0, "height": -INF, "min_height": INF, "min_blend": 1.0}]
	var max_height := -INF
	var vertices_checked := 0
	for child: MeshInstance3D in ring.get_children():
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			vertices_checked += 1
			max_height = maxf(max_height, vertex.y)
			var p := Vector2(vertex.x, vertex.z)
			var distance := maxf(maxf(builder.inner.position.x - p.x, p.x - builder.inner.end.x), maxf(builder.inner.position.y - p.y, p.y - builder.inner.end.y))
			var blend := smoothstep(0.0, 56.0, distance)
			var expected: float = profile.node_height(p.x, p.y) if blend < 1 else 0.0
			if blend > 0:
				expected = lerpf(expected, Landforms.far_height(p, profile.noise), blend)
			check(vertex.y == Vector3(0, expected, 0).y, "Actual scenic vertex follows dry mesa formula through the real fine/coarse blend")
			for i in Landforms.MESAS.size():
				var mesa: Dictionary = Landforms.MESAS[i]
				if ((p - Vector2(mesa.center)) / Vector2(mesa.radius)).length() < 0.3:
					tops[i].count += 1
					tops[i].height = maxf(tops[i].height, vertex.y)
					tops[i].min_height = minf(tops[i].min_height, vertex.y)
					tops[i].min_blend = minf(tops[i].min_blend, blend)
					if blend == 1.0:
						tops[i].unblended += 1
					# A continuous fine/coarse mix at the plateau fringe is allowed;
					# actual height, not a binary blend flag, is the visibility gate.
					check(absf(vertex.y - float(mesa.top)) <= 1.0, "Broad actual mesa top survives the fine-ring blend within one unit of its declared height")
	for i in tops.size():
		check(tops[i].count > 20 and tops[i].height > float(Landforms.MESAS[i].top) - 1, "Each mesa has a visible-sized stored plateau, not an unrepresented analytic peak")
		check(tops[i].unblended > 20 and float(tops[i].unblended) / tops[i].count >= 0.9, "Each actual mesa retains a substantial fully unblended plateau core")
	check(max_height <= 55 and vertices_checked > 30000, "Actual dry skyline remains low mesas, without inherited high Gaussian Alpine peaks")
	print("DRY_MESAS: %d stored vertices; highest %.4f; plateau counts %s" % [vertices_checked, max_height, tops])

func _legacy_profile() -> GDScript:
	# Reconstruct the exact 82cd572 script by removing only the reviewed opt-in
	# dry additions. Its pinned source hash makes this a frozen same-runtime
	# comparison, not a platform-dependent mesh golden or a second live formula.
	var source := FileAccess.get_file_as_string("res://scripts/landscape_recipe.gd")
	source = source.replace('const DryLandforms = preload("res://scripts/dry_wash_landforms.gd")\n', '')
	source = source.replace('const CACTUS_STYLES := {"terrain_style": "wash_terraces", "backdrop_style": "low_mesas", "trail_style": "wash_fans"}\n', '')
	var start := source.find('\tfor style in CACTUS_STYLES:')
	var end := source.find('\n\treturn errors\n', start)
	check(start >= 0 and end > start, "Opt-in style validation has a bounded removable block")
	if start >= 0 and end > start:
		source = source.substr(0, start) + source.substr(end + 1)
	source = source.replace('\tif data.get("terrain_style", "") == "wash_terraces":\n\t\treturn DryLandforms.height(point, grade, route_clearance(point), noise)\n', '')
	source = source.replace('\tif data.get("trail_style", "") == "wash_fans":\n\t\treturn DryLandforms.fan_wear(point, edges, noise)\n', '')
	check(source.sha256_text() == BASE_PROFILE_SHA, "Stripped profile source exactly matches frozen 82cd572")
	var script := GDScript.new()
	script.source_code = source
	check(script.reload() == OK, "Frozen baseline profile compiles on this same editor/runtime")
	return script

func _arrays(node: Node) -> Dictionary:
	var record := {"class": node.get_class()}
	if node is Node3D:
		record.transform = node.transform
	if node is MeshInstance3D:
		record.surfaces = []
		for i in node.mesh.get_surface_count():
			record.surfaces.append(node.mesh.surface_get_arrays(i))
	if node is MultiMeshInstance3D:
		record.buffer = node.multimesh.buffer
		record.aabb = node.multimesh.custom_aabb
		record.mesh = []
		for i in node.multimesh.mesh.get_surface_count():
			record.mesh.append(node.multimesh.mesh.surface_get_arrays(i))
	if node is GeometryInstance3D:
		record.shadow = node.cast_shadow
		record.range_end = node.visibility_range_end
	return record

func _alpine_unchanged() -> void:
	# Shared assemblers/props/recipe are genuinely the same baseline inputs, not
	# a freshly changed implementation silently used on both sides of comparison.
	for file: String in BASE_SHARED_SOURCES:
		check(FileAccess.get_file_as_string(file).sha256_text() == BASE_SHARED_SOURCES[file], "Common Alpine construction input remains exactly frozen: " + file)
	var legacy := _legacy_profile()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/long_valley.recipe.json"))
	var current_profile := Recipe.new(data)
	var old_profile: RefCounted = legacy.new(data)
	var current := FullScene.new(current_profile).build()
	var old := FullScene.new(old_profile).build()
	var before := {}
	for node: Node in old.find_children("*", "", true, false):
		before[String(old.get_path_to(node))] = _arrays(node)
	var compared := 0
	for node: Node in current.find_children("*", "", true, false):
		var key := String(current.get_path_to(node))
		check(before.has(key) and before[key] == _arrays(node), "Every actual Alpine node/mesh/instance buffer matches frozen pre-dry profile")
		compared += 1
	check(compared == before.size() and compared > 500, "Full Alpine scene comparison covers matching node inventory")
	check(current.get_node("ScenicRing").get_child(0).mesh.surface_get_material(0).get_shader_parameter("wash_enabled") == false, "Alpine material keeps dry-only shading disabled")
	var backdrop_source := FileAccess.get_file_as_string("res://scripts/landscape_backdrop.gd")
	backdrop_source = backdrop_source.replace('const DryLandforms = preload("res://scripts/dry_wash_landforms.gd")\n', '')
	backdrop_source = backdrop_source.replace('\tsurface_material.set_shader_parameter("wash_enabled", profile.data.get("trail_style", "") == "wash_fans")\n', '')
	backdrop_source = backdrop_source.replace('\t\t\tif profile.data.get("backdrop_style", "") == "low_mesas":\n\t\t\t\tmountains = DryLandforms.far_height(Vector2(x, z), profile.noise)\n', '')
	check(backdrop_source.sha256_text() == BASE_BACKDROP_SHA, "Inactive dry branch leaves exact frozen Alpine backdrop source")
	print("DRY_ALPINE_BASELINE: %d actual nodes, full array/instance-buffer equality against frozen 82cd572 profile; inactive backdrop branch source pinned" % compared)
	current.free()
	old.free()
