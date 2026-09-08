extends SceneTree
## Tests actual scenic geometry and stitched border; not gameplay or GPU proof.
const Recipe = preload("res://scripts/landscape_recipe.gd")
const Backdrop = preload("res://scripts/landscape_backdrop.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("BACKDROP_FAILED: " + message)

func _run() -> void:
	for id in ["long_valley", "dry_wash"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		var recipe := Recipe.new(data)
		var builder := Backdrop.new(recipe)
		var scene := builder.build()
		root.add_child(scene)
		var border := {}
		var triangles := 0
		var shared := {}
		var material: ShaderMaterial
		check(scene.get_meta("not_walkable_scenery", false), "Scenery has no authoritative layout claim")
		check(scene.get_child_count() <= 100, "Bounded spatial batches")
		for child: MeshInstance3D in scene.get_children():
			check(child.owner == scene, "Chunk owned by packed scene")
			var arrays := child.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			material = child.mesh.surface_get_material(0)
			check(material == builder.surface_material, "Chunks share one rich ground material")
			for i in range(0, indices.size(), 3):
				triangles += 1
				var a := indices[i]
				var b := indices[i + 1]
				var c := indices[i + 2]
				var front := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).normalized()
				var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
				check(front.y > 0 and minf(front.dot(normals[a]), minf(front.dot(normals[b]), front.dot(normals[c]))) > 0.0, "Actual scenic triangle fronts and smooth normals agree")
				check(not (center.x > -112 and center.x < 112 and center.z > -128 and center.z < 128), "No overlapping ground inside detailed rectangle")
			for i in vertices.size():
				var vertex := vertices[i]
				check(absf(normals[i].length() - 1.0) < 0.00001, "Scenic normals are normalized")
				if shared.has(vertex):
					check(shared[vertex] == normals[i], "Shared chunk border normals are bit-identical")
				shared[vertex] = normals[i]
				check(vertex.is_finite() and absf(vertex.x) <= 320 and absf(vertex.z) <= 320, "Finite bounded scenic vertices")
				var edge := (absf(vertex.x) == 112 and absf(vertex.z) <= 128) or (absf(vertex.z) == 128 and absf(vertex.x) <= 112)
				if edge:
					check(vertex.y == recipe.node_height(vertex.x, vertex.z), "Stitch uses exact stored fine mesh height")
					border[Vector2(vertex.x, vertex.z)] = true
		for x in range(-112, 113):
			check(border.has(Vector2(x, -128)) and border.has(Vector2(x, 128)), "Every north/south one-unit edge node stitched")
		for z in range(-128, 129):
			check(border.has(Vector2(-112, z)) and border.has(Vector2(112, z)), "Every east/west one-unit edge node stitched")
		check(triangles == scene.get_meta("triangle_count") and triangles < 90000, "Counted scenic triangles respect explicit budget")
		for role in ["ground", "rock"]:
			for suffix in ["albedo", "normal", "roughness"]:
				var texture := material.get_shader_parameter(role + "_" + suffix) as Texture2D
				check(texture != null and texture.get_width() == 1024 and texture.get_height() == 1024, "Real licensed surface maps are bound")
		print("BACKDROP %s: %d chunks, %d triangles, %d stitched boundary vertices" % [id, scene.get_child_count(), triangles, border.size()])
		scene.free()
	print("BACKDROP: %d checks / %d failures; geometry/resource evidence only" % [checks, failures])
	quit(0 if failures == 0 else 1)
