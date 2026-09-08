extends SceneTree
## Authoring pipeline acceptance. Does not claim these maps are playable yet.

const Recipe = preload("res://scripts/landscape_recipe.gd")
const Builder = preload("res://scripts/landscape_chunk_builder.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("RECIPE_FAILED: " + message)

func _run() -> void:
	for id in ["long_valley", "dry_wash"]:
		var path := "res://worlds/%s.recipe.json" % id
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(Recipe.validate(data).is_empty(), "Canonical art recipe validates")
		if not Recipe.validate(data).is_empty():
			continue
		var profile := Recipe.new(data)
		var builder := Builder.new(profile)
		var start := Time.get_ticks_msec()
		var scene := builder.build_scene()
		var duration := Time.get_ticks_msec() - start
		var meshes := {}
		var triangles := 0
		for chunk: MeshInstance3D in scene.get_children():
			var arrays := chunk.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			_check(vertices.size() == 289 and indices.size() == 1536, "Every chunk uses indexed 16x16 cells")
			for i in vertices.size():
				var point := vertices[i]
				var key := Vector2(point.x, point.z)
				_check(point.is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1.0) < 0.00001, "Finite world-space surface and unit normals")
				if meshes.has(key):
					_check(meshes[key].point == point and meshes[key].normal == normals[i], "Adjacent chunks have bit-identical shared heights and normals")
				else:
					meshes[key] = {"point": point, "normal": normals[i]}
			for i in range(0, indices.size(), 3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i + 1]]
				var c := vertices[indices[i + 2]]
				_check((c - a).cross(b - a).y > 0.0, "Terrain triangles have consistent upward fronts")
		var scatter := 0
		for key: Vector2i in profile.chunk_keys():
			var objects: Array = profile.scatter(key)
			_check(objects == profile.scatter(key), "Scatter is seeded and independent of generation order")
			for object: Dictionary in objects:
				var point: Vector3 = object.position
				var mesh_height := Vector3(0, profile.surface_height(point.x, point.z), 0).y
				_check(point.y == mesh_height, "All detail bases sit on the actual triangle surface, not the unsampled analytical profile")
				if object.kind in ["tree", "cactus"]:
					_check(profile.route_clearance(Vector2(point.x, point.z)) < -2.5, "Tall props never block the intended walking area")
				scatter += 1
		_check(scene.get_child_count() <= 140 and triangles <= 72000, "Large terrain stays within the bounded offline chunk budget")
		var changed: Dictionary = data.duplicate(true)
		changed.seed += 1
		var other := Recipe.new(changed)
		_check(other.scatter(Vector2i.ZERO) != profile.scatter(Vector2i.ZERO), "New seed changes detail layout")
		for missing in ["route", "bounds", "half_width", "clearings"]:
			var bad: Dictionary = data.duplicate(true)
			bad.erase(missing)
			_check(not Recipe.validate(bad).is_empty(), "Incomplete recipe rejected")
		for bad_bounds in [[0, 0, 0, 0], [0, 0, 9999, 9999], [0, false, 20, 20], [0, 1, 2]]:
			var bad: Dictionary = data.duplicate(true)
			bad.bounds = bad_bounds
			_check(not Recipe.validate(bad).is_empty(), "Unbounded or nonnumeric geometry rejected")
		print("LANDSCAPE_RECIPE %s: %d chunks, %d terrain triangles, %d grounded detail placements; mesh build %dms (host authoring time, not phone FPS)" % [id, scene.get_child_count(), triangles, scatter, duration])
		scene.free()
	print("LANDSCAPE_RECIPE: %d checks / %d failures; prototype art only, no new network terrain selected" % [checks, failures])
	quit(1 if failures else 0)
