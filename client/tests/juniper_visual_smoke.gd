extends SceneTree
## Immutable shoreline geometry and bounded, non-obstructing visual refinement.
## Raw-array identity was captured on Godot 4.6.3 macOS/arm64 at b2bec44.
## It is same-platform evidence, not a cross-platform libm bit-identity claim.
## Every platform pins the unchanged Juniper-only geometry source and runs all
## actual water/crown/picking/visibility checks; no geometry tolerance is widened.

const BASELINE := {
	"ValleyGroundJuniper": "28602c41dd6a2823b52ab5478ef352b6af2602bdcbe9717bb11785f27554ee7b",
	"JuniperLake": "195f434e8e1dfc7beedd780d544c1b917618cb7d437a269b9ab8da3a8279bf0f",
}
const SOURCE_BASELINE := {
	"profile": "4949c7b9079c3c033a39228ceeacced1cd6c841d50edfbbce85bcd335c385c86",
	"build_land_geometry": "eae51d2d646c0a8e7539b298e8866f4f776452d3d54833ddc285de9fcac6aa60",
	"ground_color": "bd33b9a630d165a93248d93ad75b21a58e69b67109b9fd18d24f1dd677912bb7",
	"clip_water": "7f1f37a49b271c5a3100e4e1615371e8c4f707bbd4da9b50e6ea1ffdf2247344",
}
const PATH: Array[Vector2] = [Vector2(-11, 2), Vector2(-8, -3), Vector2(-3, -6), Vector2(4, -6), Vector2(9, -2), Vector2(11, 4)]
const CLEARINGS: Array[Vector3] = [Vector3(-11, 2, 5.2), Vector3(-1, -6, 4.5), Vector3(11, 4, 4.8)]
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var meadow := preload("res://scripts/meadow.gd").new()
	root.add_child(meadow)
	await process_frame
	meadow.set_process(false)
	meadow.set_landscape("juniper")
	await process_frame
	var captured: Dictionary = {}
	for name in ["ValleyGroundJuniper", "JuniperLake"]:
		var instance := meadow.terrain.find_child(name, true, false) as MeshInstance3D
		if instance == null:
			_check(false, "Missing immutable mesh " + name)
			continue
		var surfaces: Array = []
		for surface in instance.mesh.get_surface_count():
			surfaces.append(instance.mesh.surface_get_arrays(surface))
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes([instance.transform, surfaces]))
		captured[name] = digest.finish().hex_encode()
	if "--capture-baseline" in OS.get_cmdline_user_args():
		print("JUNIPER_GEOMETRY_BASELINE: ", JSON.stringify(captured))
		quit(failures)
		return
	if OS.get_name() == "macOS" and OS.has_feature("arm64"):
		_check(captured == BASELINE, "Juniper ground/water arrays or transform changed: " + JSON.stringify(captured))
		print("JUNIPER_ARRAY_PRESERVATION: exact captured macOS/arm64 geometry")
	else:
		print("JUNIPER_ARRAY_PRESERVATION: no binary golden for this platform; mandatory source and actual geometry checks follow")
	_geometry_source()
	_water_shader(meadow.water)
	_water_geometry(meadow.water)
	_woodland(meadow.terrain)
	_geometry_budget(meadow)
	await _animal_visibility(meadow)
	print("JUNIPER_VISUAL_SMOKE: %d checks, failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("JUNIPER_VISUAL_CHECK_FAILED: " + message)

func _source_function(source: String, name: String) -> String:
	var start := source.find("static func " + name + "(")
	return source.substr(start).get_slice("\nstatic func ", 0) if start >= 0 else ""

func _geometry_source() -> void:
	var scenery := FileAccess.get_file_as_string("res://scripts/juniper_scenery.gd")
	var pieces := {
		"profile": FileAccess.get_file_as_string("res://scripts/juniper_profile.gd"),
		"build_land_geometry": _source_function(scenery, "build_land").get_slice("\n\tvar water_material", 0),
		"ground_color": _source_function(scenery, "ground_color"),
		"clip_water": _source_function(scenery, "_clip_water"),
	}
	for name in SOURCE_BASELINE:
		_check(String(pieces[name]).sha256_text() == SOURCE_BASELINE[name], "Frozen Juniper geometry-generating source changed: " + name)

func _shader_safe(code: String) -> bool:
	var comments := RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\n]*")
	var clean := comments.sub(code, "", true)
	var forbidden := RegEx.create_from_string("\\b(ALPHA|ALPHA_SCISSOR_THRESHOLD|ALPHA_HASH_SCALE|DEPTH|hint_screen_texture|hint_depth_texture|sampler2D|samplerCube)\\b|\\b(VERTEX|POSITION)(?:\\.[xyzw]+)?\\s*(?:[+*/-]?=)|#include")
	return forbidden.search(clean) == null

func _water_shader(water: MeshInstance3D) -> void:
	_check(water.material_override is ShaderMaterial, "Water must use the opaque animated material")
	if not water.material_override is ShaderMaterial:
		return
	var material := water.material_override as ShaderMaterial
	_check(material.shader != null and _shader_safe(material.shader.code), "Water must not use transparency, displacement, screen/depth reads or hidden includes")
	_check(material.next_pass == null, "Water must remain a single pass")
	var strength: Variant = material.get_shader_parameter("ripple_strength")
	# A headless renderer may not expose reflected defaults; parse the actual
	# shader declaration only when no explicit material override is available.
	if strength == null:
		var declaration := RegEx.create_from_string("uniform\\s+float\\s+ripple_strength\\b[^;=]*=\\s*([0-9.eE+-]+)\\s*;").search(material.shader.code)
		if declaration != null and declaration.get_string(1).is_valid_float():
			strength = declaration.get_string(1).to_float()
	_check(strength is float and is_finite(strength) and strength >= 0.0 and strength <= 0.025, "Water modulation must stay restrained")
	_check(material.shader.code.contains("TIME"), "Water's small visual changes must advance over time")
	for code in ["void fragment(){ ALPHA=0.5; }", "void vertex(){ VERTEX.y += sin(TIME); }", "void vertex(){ POSITION = vec4(1.0); }", "uniform sampler2D scene:hint_screen_texture;", "#include \"other.gdshaderinc\""]:
		_check(not _shader_safe(code), "Unsafe water negative control was accepted")
	_check(_shader_safe("// VERTEX = ignored comment\nvoid vertex(){ vec3 p=VERTEX; }\nvoid fragment(){ NORMAL=vec3(0,1,0); }"), "Read-only vertex use and lighting normals remain allowed")

func _water_geometry(water: MeshInstance3D) -> void:
	_check(water.mesh.get_surface_count() == 1, "Refinement must not add water surfaces")
	var faces: PackedVector3Array = water.mesh.get_faces()
	_check(faces.size() > 3000, "Actual clipped water must be nonempty")
	for index in range(0, faces.size(), 3):
		var triangle := PackedVector2Array()
		for local in [faces[index], faces[index + 1], faces[index + 2]]:
			var point: Vector3 = water.global_transform * local
			_check(point.is_finite() and absf(point.y) < 0.000001, "Actual water must remain on the fixed lake plane")
			triangle.append(Vector2(point.x, point.z))
		_check(not _triangle_overlaps_walkable(triangle), "Complete actual water triangle overlaps the canonical dry union")
	print("JUNIPER_WATER_GEOMETRY: %d actual clipped triangles remain outside all dry paths/clearings" % (faces.size() / 3))

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var edge := b - a
	var fraction := clampf((point - a).dot(edge) / edge.length_squared(), 0.0, 1.0) if edge.length_squared() > 0.0 else 0.0
	return point.distance_to(a + fraction * edge)

func _clearance(point: Vector2) -> float:
	var result := -INF
	for clearing in CLEARINGS:
		result = maxf(result, clearing.z - point.distance_to(Vector2(clearing.x, clearing.y)))
	for index in range(PATH.size() - 1):
		result = maxf(result, 3.6 - _distance_to_segment(point, PATH[index], PATH[index + 1]))
	return result

func _triangle_overlaps_walkable(triangle: PackedVector2Array) -> bool:
	for clearing in CLEARINGS:
		var center := Vector2(clearing.x, clearing.y)
		if Geometry2D.is_point_in_polygon(center, triangle):
			return true
		for edge in 3:
			if _distance_to_segment(center, triangle[edge], triangle[(edge + 1) % 3]) <= clearing.z:
				return true
	for index in range(PATH.size() - 1):
		var a := PATH[index]
		var b := PATH[index + 1]
		if Geometry2D.is_point_in_polygon(a, triangle) or Geometry2D.is_point_in_polygon(b, triangle):
			return true
		for edge in 3:
			var c := triangle[edge]
			var d := triangle[(edge + 1) % 3]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
			if minf(minf(_distance_to_segment(a, c, d), _distance_to_segment(b, c, d)), minf(_distance_to_segment(c, a, b), _distance_to_segment(d, a, b))) <= 3.6:
				return true
	return false

func _woodland(terrain: Node3D) -> void:
	var woodland := terrain.find_child("JuniperWoodland", true, false) as MeshInstance3D
	_check(woodland != null, "Woodland mesh must exist")
	if woodland == null:
		return
	var plantings: Array = woodland.get_meta("plantings", [])
	_check(plantings.size() >= 15 and plantings.size() <= 32, "Woodland must contain bounded planted groups")
	var forms: Dictionary = {}
	var groups: Dictionary = {}
	for index in plantings.size():
		var planting: Dictionary = plantings[index]
		var point: Vector2 = planting.get("position", Vector2.INF)
		var radius: float = planting.get("radius", -1.0)
		_check(point.is_finite() and radius > 0 and radius <= 3.0, "Planting envelope must be finite and modest")
		_check(_clearance(point) < -radius - 0.34, "Crown envelope intrudes into playable shore")
		var form: String = planting.get("form", "")
		_check(form in ["spreading", "crooked", "windward"], "Unknown tree silhouette")
		forms[form] = true
		var group: int = planting.get("group", -1)
		_check(group >= 0, "Every tree must belong to a spatial group")
		groups[group] = int(groups.get(group, 0)) + 1
		for other_index in range(index):
			var other: Dictionary = plantings[other_index]
			_check(point.distance_to(other.position) >= 0.8 * (radius + float(other.radius)) - 0.0001, "Tree envelopes are crowded/interpenetrating")
	_check(forms.size() == 3 and groups.size() >= 5, "Woodland needs distinct silhouettes and multiple groups")
	var counts: Dictionary = {}
	for count in groups.values():
		counts[count] = true
	_check(counts.size() >= 3, "Woodland groups must not repeat the same tree count")
	var faces: PackedVector3Array = woodland.mesh.get_faces()
	_check(faces.size() >= 900 and faces.size() / 3 <= 15000, "Woodland actual geometry must be nonempty and bounded")
	var closest := -INF
	for local in faces:
		var vertex: Vector3 = woodland.global_transform * local
		var point := Vector2(vertex.x, vertex.z)
		closest = maxf(closest, _clearance(point))
		_check(vertex.is_finite() and _clearance(point) < 0.0, "Actual crown vertex enters playable shore")
		var inside_envelope := false
		for planting: Dictionary in plantings:
			if point.distance_to(planting.position) <= float(planting.radius) + 0.0001:
				inside_envelope = true
				break
		_check(inside_envelope, "Actual crown vertex exceeds every declared envelope")
	for index in range(0, faces.size(), 3):
		var triangle := PackedVector2Array()
		for local in [faces[index], faces[index + 1], faces[index + 2]]:
			var point: Vector3 = woodland.global_transform * local
			triangle.append(Vector2(point.x, point.z))
		_check(not _triangle_overlaps_walkable(triangle), "Actual crown triangle spans the playable shore")
	_check(_triangle_overlaps_walkable(PackedVector2Array([Vector2(-25, -15), Vector2(25, -15), Vector2(0, 15)])), "Spanning triangle negative control must fail")
	print("JUNIPER_WOODLAND: %d trees, %d groups, %d forms, %d triangles, nearest crown clearance %.3fm" % [plantings.size(), groups.size(), forms.size(), faces.size() / 3, closest])

func _geometry_budget(meadow: Node3D) -> void:
	var queue: Array[Node] = [meadow]
	var nodes := 0
	var meshes := 0
	var triangles := 0
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		nodes += 1
		queue.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			meshes += 1
			triangles += node.mesh.get_faces().size() / 3
	_check(triangles <= 100000 and nodes <= 1400 and meshes <= 1000, "Juniper exceeds existing mobile geometry budget")
	print("JUNIPER_VISUAL_BUDGET: %d triangles, %d nodes, %d meshes (meadow only; full-scene budget remains in shore_smoke)" % [triangles, nodes, meshes])

func _animal_visibility(meadow: Node3D) -> void:
	var occluders: Array[Dictionary] = []
	for mesh in meadow.terrain.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var transform: Transform3D = mesh.global_transform
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for index in faces.size():
			faces[index] = transform * faces[index]
		occluders.append({"name": mesh.name, "faces": faces, "aabb": transform * mesh.get_aabb()})
	var probes := 0
	var picks := 0
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = size
		await process_frame
		_check(root.get_visible_rect().size == Vector2(size), "Visibility test requires actual portrait aspect ratio")
		for pan in [-6.0, 6.0]:
			meadow.camera_focus.x = pan
			meadow.desired_focus.x = pan
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow._process(0.0)
				for center in [Vector2(-11, 2), Vector2(-1, -6), Vector2(11, 4), Vector2(-6, -4.2), Vector2(6.5, -4.0)]:
					for offset in [Vector2.ZERO, Vector2(-1.4, 0), Vector2(1.4, 0)]:
						var point: Vector2 = center + offset
						_check(_clearance(point) > 0.0, "Animal probe must be inside the dry union")
						var animal := Vector3(point.x, meadow.surface_height(point.x, point.y) + 0.60, point.y)
						var screen: Vector2 = meadow.camera.unproject_position(animal)
						if not Rect2(Vector2.ZERO, Vector2(size)).has_point(screen):
							continue
						var origin: Vector3 = meadow.camera.project_ray_origin(screen)
						var endpoint := animal.move_toward(origin, 0.06)
						var blocked := ""
						for occluder in occluders:
							if occluder.aabb.intersects_segment(origin, endpoint) == null:
								continue
							var faces: PackedVector3Array = occluder.faces
							for index in range(0, faces.size(), 3):
								if Geometry3D.segment_intersects_triangle(origin, endpoint, faces[index], faces[index + 1], faces[index + 2]) != null:
									blocked = String(occluder.name)
									break
							if not blocked.is_empty():
								break
						_check(blocked.is_empty(), "Animal chest occluded by %s at %s / %s pan%s zoom%s" % [blocked, point, size, pan, zoom])
						var ground := animal - Vector3.UP * 0.60
						var ground_screen: Vector2 = meadow.camera.unproject_position(ground)
						if Rect2(Vector2.ZERO, Vector2(size)).has_point(ground_screen):
							var hit: Vector3 = meadow.ground_at(ground_screen)
							_check(hit.is_finite() and hit.distance_to(ground) <= 0.06, "Actual portrait ground pick differs from the animal's ground")
							picks += 1
						probes += 1
	_check(probes >= 120, "Insufficient actual-mesh portrait animal visibility probes")
	_check(picks >= 120, "Insufficient actual portrait picking probes")
	print("JUNIPER_ANIMAL_VISIBILITY: %d clear portrait chest probes and %d ground picks across both aspects, follow extremes and three zooms" % [probes, picks])
