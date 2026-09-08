extends SceneTree
## The phone must load the real prepared artifact, not silently regenerate it.
const Recipe = preload("res://scripts/landscape_recipe.gd")
const FullBuilder = preload("res://scripts/landscape_scene_builder.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("PREPARED_SCENE_FAILED: " + message)

func _run() -> void:
	for id in ["long_valley", "dry_wash"]:
		var path := "res://generated/%s.scn" % id
		check(ResourceLoader.exists(path), "Run the offline cook before this check")
		if not ResourceLoader.exists(path):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(packed != null, "Prepared artifact loads from disk")
		if packed == null:
			continue
		var scene := packed.instantiate() as Node3D
		root.add_child(scene)
		check(scene.get_meta("source_recipe", {}) == data and scene.get_meta("full_visual_scene", false), "Complete embedded recipe matches current source")
		var triangles := 0
		var meshes := 0
		var instances := 0
		var nodes: Array[Node] = [scene]
		while not nodes.is_empty():
			var node: Node = nodes.pop_back()
			nodes.append_array(node.get_children())
			if node != scene:
				check(node.owner == scene, "Nested scenery belongs to the saved root")
			check(node.get_script() == null, "Loaded landscape has no per-prop CPU script")
			var mesh: Mesh
			var copies := 1
			if node is MeshInstance3D:
				mesh = node.mesh
			elif node is MultiMeshInstance3D:
				mesh = node.multimesh.mesh
				copies = node.multimesh.instance_count
				instances += copies
				var stride := 20 if node.multimesh.use_custom_data else 16
				check(node.multimesh.buffer.size() == copies * stride and node.multimesh.custom_aabb.size.length_squared() > 0, "Prepared vegetation retains its real instances and cull bounds")
			if mesh != null:
				meshes += 1
				for surface in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(surface)
					var indices: Variant = arrays[Mesh.ARRAY_INDEX]
					var count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
					triangles += count / 3 * copies
		check(meshes > 300 and meshes < 1100 and triangles < 650000, "Full landscape including apron/scenery/props respects its complete-scene budget")
		check(scene.get_meta("prop_instances", 0) > 0 and scene.get_meta("scenic_triangles", 0) == 88784, "Prepared world includes props and the scenic ring")
		var profile := Recipe.new(data)
		var loaded := FullBuilder.load_or_build(profile)
		# Cache loading leaves the authoring lattice empty. A fallback generator
		# would fill it with tens of thousands of heights and cannot fake this.
		check(profile.lattice.is_empty() and loaded.get_meta("source_recipe", {}) == data, "Runtime path loads prepared geometry without generating terrain")
		loaded.free()
		print("PREPARED %s: %d mesh batches, %d actual triangles, %d retained instances; no runtime generation" % [id, meshes, triangles, instances])
		scene.free()
	print("PREPARED: %d checks / %d failures; headless saved-resource check, not Android FPS" % [checks, failures])
	quit(0 if failures == 0 else 1)
