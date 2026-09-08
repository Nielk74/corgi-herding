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

func _run() -> void:
	for id in ["long_valley", "dry_wash"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		var profile := Recipe.new(data)
		var chunks := Chunks.new(profile, true)
		var painted_chunks := Chunks.new(profile, true, true)
		var keys := {}
		for point: Vector3 in profile.route:
			check(profile.trail_wear(Vector2(point.x, point.z)) >= 0.74, "Every authored trail anchor has a worn center")
			keys[Vector2i(floori(point.x / 16.0), floori(point.z / 16.0))] = true
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
				if tint.a < 0.999:
					marked += 1
					var p := Vector2(vertices[i].x, vertices[i].z)
					check(profile.route_clearance(p) > 0.0, "Marked trail vertices stay in the authored broad walking corridor")
			chunk.free()
			painted.free()
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
					loaded_marked += int(tint.a < 0.999)
			check(loaded_marked > marked, "Full saved scene retains the trail beyond selected sample chunks")
			scene.free()
	var source := FileAccess.get_file_as_string("res://shaders/landscape_surface.gdshader")
	check(not source.contains("ALPHA =") and not source.contains("discard"), "The trail is opaque terrain, not a transparent decal")
	print("TRAIL: %d checks / %d failures; preserved terrain geometry and saved wear masks" % [checks, failures])
	quit(0 if failures == 0 else 1)
