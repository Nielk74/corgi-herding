extends SceneTree
## A visual wear mask must never change real grounding or authorize movement.
const Recipe = preload("res://scripts/landscape_recipe.gd")
const Chunks = preload("res://scripts/landscape_chunk_builder.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("TRAIL_FAILED: " + message)

func _valid_mask_wear(wear: float, wash_fans: bool) -> bool:
	return is_finite(wear) and wear >= 0.0 and wear <= (0.22 if wash_fans else 1.0)

func _valid_center_wear(wear: float, wash_fans: bool) -> bool:
	return _valid_mask_wear(wear, wash_fans) and (wear > 0.12 if wash_fans else wear >= 0.74)

func _run() -> void:
	check(_valid_center_wear(0.74, false) and _valid_center_wear(0.18, true), "Each intended trail style accepts its own center wear")
	check(not _valid_center_wear(0.74, true), "Dark ordinary trail cannot pass as a soft wash fan")
	check(not _valid_center_wear(0.18, false), "Light wash fan cannot weaken ordinary trail center coverage")
	for id in ["long_valley", "dry_wash"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		var profile := Recipe.new(data)
		var wash_fans: bool = data.get("trail_style", "") == "wash_fans"
		var chunks := Chunks.new(profile, true)
		var painted_chunks := Chunks.new(profile, true, true)
		var keys := {}
		var fan_probes := {}
		var stored_fan_probes := {}
		for point: Vector3 in profile.route:
			check(_valid_center_wear(profile.trail_wear(Vector2(point.x, point.z)), wash_fans), "Every authored anchor has its style's positive center wear")
			keys[Vector2i(floori(point.x / 16.0), floori(point.z / 16.0))] = true
		if wash_fans:
			# Probe actual stored grid vertices on declared branches, not only the
			# old seven-knot spine. Full triangle/interpolation and all-edge fan
			# coverage remain mandatory in dry_wash_landforms_smoke.gd.
			for edge: Dictionary in profile.edges:
				var midpoint: Vector2 = (Vector2(edge.a) + Vector2(edge.b)) * 0.5
				var point := Vector2(roundf(midpoint.x), roundf(midpoint.y))
				check(_valid_center_wear(profile.trail_wear(point), true), "Declared wash branch has restrained positive center wear")
				fan_probes[point] = true
				keys[Vector2i(floori(point.x / 16.0), floori(point.y / 16.0))] = true
			check(not fan_probes.is_empty(), "Wash fan checks require declared branches")
		check(profile.trail_wear(Vector2(-400, 400)) == 0.0, "Distant ground does not inherit a trail")
		var marked := 0
		for key: Vector2i in keys:
			var chunk := chunks.build_chunk(key)
			var before := chunk.mesh.surface_get_arrays(0)
			var before_bounds := chunk.mesh.get_aabb()
			var painted := painted_chunks.build_chunk(key)
			var after := painted.mesh.surface_get_arrays(0)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				check(before[channel] == after[channel], "Wear painting leaves the original mesh channel byte-identical")
			check(painted.mesh.get_aabb() == before_bounds, "Culling bounds are unchanged")
			var old_colors: PackedColorArray = before[Mesh.ARRAY_COLOR]
			var new_colors: PackedColorArray = after[Mesh.ARRAY_COLOR]
			var vertices: PackedVector3Array = after[Mesh.ARRAY_VERTEX]
			for i in vertices.size():
				var tint := new_colors[i]
				check(Vector3(tint.r, tint.g, tint.b) == Vector3(old_colors[i].r, old_colors[i].g, old_colors[i].b), "Only unused alpha changes, not source tint")
				check(tint.a >= 0.0 and tint.a <= 1.0, "Stored mask is bounded")
				var point := Vector2(vertices[i].x, vertices[i].z)
				if wash_fans:
					check(_valid_mask_wear(1.0 - tint.a, true), "Actual stored wash mask stays within 0..0.22")
					if fan_probes.has(point):
						check(_valid_center_wear(1.0 - tint.a, true), "Actual branch vertex retains restrained positive fan wear")
						stored_fan_probes[point] = true
				if tint.a < 0.999:
					marked += 1
					var p := Vector2(vertices[i].x, vertices[i].z)
					check(profile.route_clearance(p) > 0.0, "Marked trail vertices stay in the authored broad walking corridor")
			chunk.free()
			painted.free()
		check(stored_fan_probes.size() == fan_probes.size(), "Every selected wash branch probe exists in the actual painted mesh")
		check(marked > 50, "Wear is actually retained in mesh colors, not just a CPU calculation")
		var packed := load("res://generated/%s.scn" % id) as PackedScene
		check(packed != null, "Cooked scene exists")
		if packed != null:
			var scene := packed.instantiate()
			var loaded_marked := 0
			for chunk: Node in scene.get_children():
				if not chunk is MeshInstance3D or not String(chunk.name).begins_with("Ground_"):
					continue
				var arrays: Array = chunk.mesh.surface_get_arrays(0)
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				for tint: Color in colors:
					if wash_fans:
						check(_valid_mask_wear(1.0 - tint.a, true), "Saved wash fan mask retains its strict 0..0.22 bound")
					loaded_marked += int(tint.a < 0.999)
			check(loaded_marked > marked, "Full saved scene retains the trail beyond selected sample chunks")
			scene.free()
	var source := FileAccess.get_file_as_string("res://shaders/landscape_surface.gdshader")
	check(not source.contains("ALPHA =") and not source.contains("discard"), "The trail is opaque terrain, not a transparent decal")
	print("TRAIL: %d checks / %d failures; preserved terrain geometry and saved wear masks" % [checks, failures])
	quit(0 if failures == 0 else 1)
