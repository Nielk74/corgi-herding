extends SceneTree
## Offline, optional material-mask QA. No terrain/shader/gameplay mutation.
const Scree = preload("res://scripts/landscape_scree.gd")
const Navigation = preload("res://scripts/region_navigation.gd")
var checks := 0
var failures := 0
var painted := 0
var walkable := 0
var boundary_samples := 0
var triangle_samples := 0
var peak := 0.0
var peak_delta := 0.0

class CountingSource:
	extends RefCounted
	var navigation: RefCounted
	var calls := 0
	func _init(nav: RefCounted) -> void:
		navigation = nav
	func contains(point: Vector2) -> bool:
		calls += 1
		return navigation.contains(point)
	func signed_clearance(point: Vector2) -> float:
		calls += 1
		return navigation.signed_clearance(point)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 25:
			printerr("SCREE_MASK_FAILED: " + message)

func inspect(point: Vector2, mask: RefCounted, navigation: RefCounted) -> float:
	var value: float = mask.mask(point)
	check(is_finite(value) and value >= 0 and value <= 0.82, "Material mask is finite, bounded and restrained")
	var inside: bool = navigation.contains(point)
	var clearance: float = navigation.signed_clearance(point)
	if inside:
		walkable += 1
		check(value == 0, "Canonical walkable ground has exactly zero scree")
	if clearance >= -2 or clearance <= -7.25:
		check(value == 0, "Boundary buffer and distant ground remain untouched")
	if value > 0:
		painted += 1
		peak = maxf(peak, value)
		check(not inside and clearance < -2 and clearance > -7.25, "Every painted sample is on a genuine exposed outer shoulder")
	return value

func _triangle_safety(mask: RefCounted, navigation: RefCounted) -> void:
	var faces := 0
	for z in range(12, 92):
		for x in range(-74, -30):
			var corners := [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]
			var values: Array[float] = []
			for point: Vector2 in corners:
				values.append(mask.mask(point))
			for ids in [[0, 1, 2], [0, 2, 3]]:
				if values[ids[0]] + values[ids[1]] + values[ids[2]] == 0:
					continue
				faces += 1
				# Every interpolated point is within sqrt(2) of a painted vertex.
				# Its >2-unit distance from the dry union proves the whole face is
				# outside (distance-to-union is1-Lipschitz), not just these probes.
				for index: int in ids:
					if values[index] > 0:
						check(navigation.signed_clearance(corners[index]) < -2, "Painted face has a source vertex farther than its entire diameter from walkability")
				for ia in 5:
					for ib in range(5 - ia):
						var a := ia / 4.0
						var b := ib / 4.0
						var point: Vector2 = corners[ids[0]] * a + corners[ids[1]] * b + corners[ids[2]] * (1.0 - a - b)
						check(not navigation.contains(point), "Actual one-unit triangle interpolation cannot paint through a legal boundary")
						triangle_samples += 1
	check(faces >= 100 and faces < 600, "Scree occupies a small bounded selection of existing faces")

func _boundaries(mask: RefCounted, navigation: RefCounted, region: Dictionary) -> void:
	var exposed := 0
	var marked_exposed := 0
	for clearing: Dictionary in region.clearings:
		var center := Vector2(clearing.center.x, clearing.center.y)
		var marked_angles := 0
		for angle in 180:
			var normal := Vector2.from_angle(TAU * angle / 180)
			var rim: Vector2 = center + normal * float(clearing.radius)
			for offset in [-0.05, 0.0, 0.0001, 0.5, 1.99, 2.0, 2.1, 4.0, 8.0]:
				inspect(center + normal * (float(clearing.radius) + offset), mask, navigation)
				boundary_samples += 1
			if absf(navigation.signed_clearance(rim)) < 0.0001:
				exposed += 1
				if mask.mask(rim + normal * 4.0) > 0.01:
					marked_angles += 1
					marked_exposed += 1
		check(marked_angles < 45, "No clearing acquires a continuous stone perimeter or majority arc")
	for edge: Dictionary in region.corridors:
		var a := Vector2(region.anchors[int(edge.a)].x, region.anchors[int(edge.a)].y)
		var b := Vector2(region.anchors[int(edge.b)].x, region.anchors[int(edge.b)].y)
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x)
		for ratio in [0.0, 0.25, 0.5, 0.75, 1.0]:
			for side in [-1.0, 1.0]:
				for offset in [-0.05, 0.0, 0.0001, 0.5, 1.99, 2.0, 2.1, 4.0, 8.0]:
					inspect(a.lerp(b, ratio) + normal * side * (float(edge.half_width) + offset), mask, navigation)
					boundary_samples += 1
	check(marked_exposed > 10 and marked_exposed < exposed * 0.20, "Most exposed canonical perimeter remains grassy; only selected shoulders are painted")
	print("SCREE_BOUNDARY_COVERAGE: %d/%d exposed disk directions marked" % [marked_exposed, exposed])

func _islands(mask: RefCounted) -> void:
	var occupied := {}
	for z in range(24, 184):
		for x in range(-148, -60):
			if mask.mask(Vector2(x * 0.5, z * 0.5)) > 0.01:
				occupied[Vector2i(x, z)] = true
	var area := occupied.size() * 0.25
	var components := 0
	while not occupied.is_empty():
		components += 1
		var queue: Array[Vector2i] = [occupied.keys()[0]]
		occupied.erase(queue[0])
		while not queue.is_empty():
			var point: Vector2i = queue.pop_back()
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = point + direction
				if occupied.has(neighbor):
					occupied.erase(neighbor)
					queue.append(neighbor)
	check(components >= 4 and components <= 12 and area > 40 and area < 220, "Unequal disconnected patches leave substantial grassy gaps")
	print("SCREE_PATCHES: %d disconnected islands,%.2f square units above1percent mask" % [components, area])

func _run() -> void:
	var region := Navigation.default_region()
	var navigation := Navigation.new(region)
	var source := CountingSource.new(navigation)
	var mask := Scree.new(source)
	var second := Scree.new(navigation)
	var disabled := Scree.new()
	check(navigation.valid and not disabled.debug_state().enabled, "Canonical source is explicit; optional helper defaults off without it")
	for z in range(-96, 97):
		for x in range(-72, 73):
			var point := Vector2(x, z)
			var value := inspect(point, mask, navigation)
			check(value == second.mask(point) and disabled.mask(point) == 0, "Output is deterministic and has no implicit legacy activation")
	_boundaries(mask, navigation, region)
	_triangle_safety(mask, navigation)
	_islands(mask)
	for z in range(56, 368):
		for x in range(-288, -128):
			var point := Vector2(x, z) * 0.25
			var value: float = mask.mask(point)
			peak_delta = maxf(peak_delta, maxf(absf(value - mask.mask(point + Vector2(0.25, 0))), absf(value - mask.mask(point + Vector2(0, 0.25)))))
	check(peak > 0.20 and peak <= 0.82 and peak_delta < 0.26, "Visible but soft bounded material variation, not abrupt mask edges")
	var calls_before: int = source.calls
	for point in [Vector2(400, 400), Vector2(44, -78), Vector2.ZERO, Vector2(INF, NAN)]:
		check(mask.mask(point) == 0, "Unrelated region/invalid points stay entirely untouched")
	check(source.calls == calls_before, "Broad phase avoids canonical union work for unrelated world vertices")
	var original := Color(0.31, 0.72, 0.64, 0.17)
	for value in [0.0, 0.15, 0.82, 1.0, NAN]:
		var encoded: Color = Scree.encode(original, value)
		check(encoded.g == original.g and encoded.b == original.b and encoded.a == original.a, "Encoding changes red only and preserves existing trail alpha exactly")
		check(absf((1.0 - encoded.r) - (value if is_finite(value) else 0.0)) < 0.0000001, "Full-scene shader can decode inverse red without alpha/decal passes")
	check(1.0 - Scree.encode(Color.WHITE, 0).r == 0, "Default white distant vertex color is neutral")
	var stats: Dictionary = mask.debug_state()
	check(source.calls == stats.source_queries and stats.source_queries <= stats.calls * 0.25 and stats.added_vertices == 0 and stats.added_draw_batches == 0, "Offline mask has bounded source work and creates no rendering/geometry resources")
	# Exact region object and visibility cache remain owned by navigation.
	check(navigation.region == region and navigation.debug_state().cache_builds == 1, "Art mask never changes canonical geometry or rebuilds route visibility")
	print("LANDSCAPE_SCREE_SMOKE: %d checks/%d failures;%d legal samples,%d boundary samples,%d interpolated-face probes;peak%.3f,quarter-unit variation%.3f,source queries%d/%d; material-only/no Android acceptance" % [checks, failures, walkable, boundary_samples, triangle_samples, peak, peak_delta, stats.source_queries, stats.calls])
	quit(1 if failures else 0)
