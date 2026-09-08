extends SceneTree
## Real authoring resources and serialized meshes, not an Android GPU/FPS test.
## Temporary files are uniquely owned by this run; herd/audio preferences untouched.

const Recipe = preload("res://scripts/landscape_recipe.gd")
const Validator = preload("res://scripts/strict_region_validator.gd")
const Builder = preload("res://scripts/landscape_chunk_builder.gd")
var checks := 0
var failures := 0
var instances_checked := 0
var region_directory := ""
var output_directory := ""
var temporary_files: Array[String] = []
var owned_directories: Array[String] = []
var wind_source := ""
var failure_kinds := {}
var diagnostic_phase := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		var key := diagnostic_phase + ": " + message
		if not failure_kinds.has(key):
			printerr("LANDSCAPE_RENDER_FAILED: " + key)
		failure_kinds[key] = int(failure_kinds.get(key, 0)) + 1

func _run() -> void:
	var suffix := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	region_directory = "res://worlds/regions/.validation-smoke-" + suffix
	output_directory = "user://landscape-render-smoke-" + suffix
	if not _make_directory(region_directory) or not _make_directory(output_directory):
		_cleanup()
		quit(1)
		return
	wind_source = FileAccess.get_file_as_string("res://shaders/meadow_grass.gdshader")
	_check(wind_source.contains("render_mode cull_disabled;") and not wind_source.contains("ALPHA") and not wind_source.contains("discard"), "Grass is opaque and double-sided without alpha overdraw")
	_check(wind_source.contains("VERTEX.x += (gust + flutter) * tip * tip * 0.10 * wind_strength") and wind_source.contains("* 0.2;") and wind_source.contains("hint_range(0.0, 1.0)"), "Wind equation and declared range match the conservative culling-bound test")
	_check(wind_source.contains("TIME") and wind_source.contains("INSTANCE_CUSTOM.x") and wind_source.contains("clamp(VERTEX.y / 0.28, 0.0, 1.0)"), "Shader consumes time and instance phase with pinned roots")
	_validation_cases()
	for id: String in ["long_valley", "dry_wash"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		_check(Recipe.validate(data).is_empty(), "Canonical recipe validates before textured construction")
		var profile := Recipe.new(data)
		var builder := Builder.new(profile, true)
		var scene := builder.build_scene(true)
		root.add_child(scene)
		await process_frame
		await process_frame
		diagnostic_phase = id + " before save"
		var original := _verify_scene(scene, profile, data.biome)
		var packed := PackedScene.new()
		_check(packed.pack(scene) == OK, "Textured ground and owned MultiMeshes pack")
		var path := output_directory + "/" + id + ".scn"
		_check(not FileAccess.file_exists(path), "Scene output does not overwrite existing files")
		temporary_files.append(path)
		_check(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK, "Actual compressed binary scene saves")
		var reloaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_check(reloaded != null, "Saved scene loads from disk, not the PackedScene object")
		if reloaded != null:
			var restored := reloaded.instantiate() as Node3D
			_check(restored != null, "Saved landscape instantiates")
			if restored != null:
				root.add_child(restored)
				await process_frame
				await process_frame
				diagnostic_phase = id + " after load"
				var after := _verify_scene(restored, profile, data.biome)
				_check(original == after, "Serialized terrain arrays and all grass instance buffers remain identical")
				restored.free()
		print("LANDSCAPE_RENDER %s: %d scene children, actual PBR/grass resources verified before and after save-load" % [id, scene.get_child_count()])
		scene.free()
		await process_frame
	_cleanup()
	await process_frame
	print("LANDSCAPE_RENDER: %d checks / %d failures; %d rendered-instance grounding checks; headless resource/geometry evidence only" % [checks, failures, instances_checked])
	if failures:
		print(failure_kinds)
	quit(1 if failures else 0)

func _make_directory(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		_check(false, "Refuse to reuse a pre-existing temporary directory")
		return false
	var ok := DirAccess.make_dir_recursive_absolute(absolute) == OK
	_check(ok, "Create isolated temporary directory")
	if ok:
		owned_directories.append(path)
	return ok

func _cleanup() -> void:
	for path in temporary_files:
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only this test's temporary file")
	for path in owned_directories:
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove empty test-owned directory")

func _verify_scene(scene: Node3D, profile: RefCounted, biome: String) -> Dictionary:
	_check(scene.get_meta("prototype_not_network_layout", false) == true, "Saved art retains the explicit non-network marker")
	_check(scene.get_meta("recipe_id", "") == profile.data.id, "Saved recipe identity retained")
	var cells := {}
	var buffers := {}
	var terrain_count := 0
	var detail_count := 0
	var terrain_triangles := 0
	var detail_triangles := 0
	var minimum_alignment := 1.0
	var minimum_walk_alignment := 1.0
	var weakest_face := Vector3.ZERO
	var weakest_inside := false
	for child in scene.get_children():
		_check(child.owner == scene, "Every exported chunk/detail belongs to its PackedScene root")
		if not child is MeshInstance3D:
			continue
		terrain_count += 1
		var mesh := (child as MeshInstance3D).mesh
		var arrays := mesh.surface_get_arrays(0)
		buffers[String(child.name)] = arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		terrain_triangles += indices.size() / 3
		_check(uv2.size() == vertices.size(), "Every terrain vertex has a bake-ready UV2")
		for i in uv2.size():
			_check(uv2[i].is_finite() and uv2[i].x >= 0 and uv2[i].x <= 1 and uv2[i].y >= 0 and uv2[i].y <= 1, "Finite UV2 inside chunk atlas")
		for i in range(0, indices.size(), 3):
			var a: Vector3 = child.global_transform * vertices[indices[i]]
			var b: Vector3 = child.global_transform * vertices[indices[i + 1]]
			var c: Vector3 = child.global_transform * vertices[indices[i + 2]]
			var front := (c - a).cross(b - a).normalized()
			var alignment := minf(front.dot(normals[indices[i]]), minf(front.dot(normals[indices[i + 1]]), front.dot(normals[indices[i + 2]])))
			var center := (a + b + c) / 3.0
			var inside: bool = profile.route_clearance(Vector2(center.x, center.z)) >= 0
			if inside:
				minimum_walk_alignment = minf(minimum_walk_alignment, alignment)
			if alignment < minimum_alignment:
				minimum_alignment = alignment
				weakest_face = (a + b + c) / 3.0
				weakest_inside = profile.route_clearance(Vector2(weakest_face.x, weakest_face.z)) >= 0
			# An inaccessible sharp crest can have legitimately divergent smooth
			# normals. Opposite-facing normals cannot; walking ground also keeps
			# a stronger alignment requirement for readable gentle shading.
			_check(front.y > 0 and alignment > 0.0 and (not inside or alignment > 0.5), "Actual triangle fronts and stored normals agree; gentle route normals remain closely aligned")
			_check(not (-front.y > 0 and -alignment > 0.0), "Reversed triangle negative control fails the same front-facing predicate")
			var key := Vector2i(floori(center.x), floori(center.z))
			if not cells.has(key):
				cells[key] = []
			cells[key].append([a, b, c])
		_material(mesh.surface_get_material(0), biome)
	_check(terrain_count == profile.chunk_keys().size() and terrain_count <= Validator.MAX_CHUNKS and terrain_triangles <= Validator.MAX_TERRAIN_TRIANGLES, "Exported terrain meets validated chunk/triangle limits")
	print("LANDSCAPE_NORMALS ", diagnostic_phase, " min_alignment=", minimum_alignment, " min_walk_alignment=", minimum_walk_alignment, " weakest=", weakest_face, " inside=", weakest_inside)
	for child in scene.get_children():
		if not child is MultiMeshInstance3D:
			continue
		detail_count += 1
		var instance := child as MultiMeshInstance3D
		var multi := instance.multimesh
		_check(multi.transform_format == MultiMesh.TRANSFORM_3D and multi.use_colors and multi.use_custom_data, "Actual MultiMesh has 3D transforms, colors and phases")
		_check(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and instance.visibility_range_end > 0 and instance.visibility_range_end <= 80, "Grass has bounded draw distance and no per-blade shadow pass")
		var shader := instance.material_override as ShaderMaterial
		_check(shader != null and shader.shader != null and shader.get_rid().is_valid() and shader.shader.get_rid().is_valid(), "Grass shader remains bound after scene frames/save-load")
		if shader != null and shader.shader != null:
			_check(shader.shader.code == wind_source, "Saved grass uses the reviewed shader source")
		# Godot's dummy renderer intentionally lacks individual instance getters
		# and automatic AABBs. Its real set_buffer/get_buffer and custom_aabb
		# storage DO survive binary serialization; decode exactly that resource.
		var data := multi.buffer
		_check(data.size() == multi.instance_count * 20, "Actual serialized MultiMesh stores every transform/color/phase; individual dummy setters would lose all data")
		if data.size() != multi.instance_count * 20:
			continue
		var aabb := multi.custom_aabb
		_check(aabb.size.length_squared() > 0 and aabb.position.is_finite() and aabb.size.is_finite(), "Each per-chunk MultiMesh stores a finite nonempty culling AABB")
		var mesh_vertices: PackedVector3Array = multi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		detail_triangles += mesh_vertices.size() / 3 * multi.instance_count
		var saved := []
		for i in multi.instance_count:
			instances_checked += 1
			var offset := i * 20
			var basis := Basis(Vector3(data[offset], data[offset + 4], data[offset + 8]), Vector3(data[offset + 1], data[offset + 5], data[offset + 9]), Vector3(data[offset + 2], data[offset + 6], data[offset + 10]))
			var transform := Transform3D(basis, Vector3(data[offset + 3], data[offset + 7], data[offset + 11]))
			var world_transform := instance.global_transform * transform
			var point := world_transform.origin
			var face_y := _triangle_height(cells, point.x, point.z)
			_check(is_finite(face_y) and absf(point.y - face_y) <= 0.00003, "Actual instance base intersects the rendered triangle, independent of profile helper")
			_check(absf(point.y + 0.25 - face_y) > 0.2, "Raised-instance negative control is rejected by the grounding tolerance")
			var scale_value := transform.basis.get_scale().x
			_check(scale_value >= 0.6499 and scale_value <= 1.3001, "Actual instance scale remains in authored range")
			var custom := Color(data[offset + 16], data[offset + 17], data[offset + 18], data[offset + 19])
			_check(is_finite(custom.r) and custom.r >= 0 and custom.r <= TAU + 0.004, "Per-instance phase survives float16/float32 renderer packing")
			var tint := Color(data[offset + 12], data[offset + 13], data[offset + 14], data[offset + 15])
			_check(tint.a == 1.0 and tint.r > 0 and tint.g > 0 and tint.b > 0, "Grass instance color is opaque and nonzero")
			var maximum_shift := 1.2 * 0.10 * scale_value
			_check(instance.extra_cull_margin >= maximum_shift, "Cull allowance covers maximum declared wind strength, not only its default")
			for vertex in mesh_vertices:
				var actual := transform * vertex
				_check(aabb.grow(0.0001).has_point(actual), "Actual static grass geometry is enclosed by its chunk's saved AABB")
				if vertex.y == 0.0:
					var tip := clampf(vertex.y / 0.28, 0.0, 1.0)
					_check(tip * tip * 0.12 == 0.0, "Every rendered root remains pinned at maximum gust")
				var shifted := actual + transform.basis.x.normalized() * maximum_shift
				_check(aabb.grow(instance.extra_cull_margin + 0.0001).has_point(shifted) and aabb.grow(instance.extra_cull_margin + 0.0001).has_point(actual - transform.basis.x.normalized() * maximum_shift), "Actual expanded AABB encloses both extrema of animated grass")
			saved.append([transform, custom, tint])
		buffers[String(child.name)] = [data, aabb, saved]
	_check(detail_count > 0 and detail_count <= terrain_count, "Textured CLI path includes real spatially chunked detail meshes")
	_check(scene.get_child_count() <= 2 * Validator.MAX_CHUNKS and terrain_triangles + detail_triangles <= 150000, "Current complete prototype scene has a bounded terrain-plus-detail budget")
	return buffers

func _material(value: Material, biome: String) -> void:
	var material := value as StandardMaterial3D
	_check(material != null, "Actual terrain has a PBR material")
	if material == null:
		return
	_check(material.get_rid().is_valid() and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opaque terrain material has a bound rendering resource")
	_check(material.uv1_triplanar and material.uv1_world_triplanar and material.uv1_scale == Vector3.ONE * 0.25, "World triplanar mapping preserves material continuity between chunks")
	_check(material.normal_enabled and is_equal_approx(material.normal_scale, 0.65) and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "GL normal and roughness map settings retained")
	_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Terrain uses mipmapped texture sampling")
	var id := "coast_sand_03" if biome == "cactus" else "aerial_grass_rock"
	var textures := [material.albedo_texture, material.normal_texture, material.roughness_texture]
	var suffixes := ["_diff_1k.jpg", "_nor_gl_1k.png", "_rough_1k.jpg"]
	for i in textures.size():
		var texture: Texture2D = textures[i]
		_check(texture != null, "All three PBR texture slots resolve")
		if texture == null:
			continue
		_check(texture.get_width() == 1024 and texture.get_height() == 1024 and texture.get_rid().is_valid(), "Bound map has actual 1024px dimensions and a resource RID")
		_check(texture.resource_path.ends_with(id + suffixes[i]), "Expected biome texture survives scene serialization")
		var import_settings := ConfigFile.new()
		_check(import_settings.load(texture.resource_path + ".import") == OK, "Texture import recipe exists")
		_check(import_settings.get_value("params", "mipmaps/generate", false) and import_settings.get_value("params", "compress/mode", -1) == 2, "Imported texture requests mipmaps and VRAM compression")
		_check(import_settings.get_value("params", "compress/normal_map", -1) == (1 if i == 1 else 2), "Only GL normal texture uses normal-map compression")

func _triangle_height(cells: Dictionary, x: float, z: float) -> float:
	var key := Vector2i(floori(x), floori(z))
	for triangle: Array in cells.get(key, []):
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var p := Vector2(x - a.x, z - a.z)
		var det := v0.cross(v1)
		var u := p.cross(v1) / det
		var v := v0.cross(p) / det
		if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
			return a.y + u * (b.y - a.y) + v * (c.y - a.y)
	return INF

func _validation_cases() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/long_valley.recipe.json"))
	var valid_region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.region_file))
	_check(Validator.validate(valid_region, data.bounds).is_empty(), "Current region passes strict nested validation")
	var bad_regions: Array = [null, [], {}, {"bounds": {}, "anchors": [], "corridors": [], "clearings": []}]
	for path in [["bounds"], ["bounds", "min"], ["bounds", "max", "x"], ["anchors"], ["anchors", 0], ["anchors", 0, "x"], ["corridors"], ["corridors", 0], ["corridors", 0, "a"], ["corridors", 0, "half_width"], ["clearings"], ["clearings", 0], ["clearings", 0, "center"], ["clearings", 0, "radius"]]:
		for replacement in [null, "bad", true, [], {}]:
			var bad: Dictionary = valid_region.duplicate(true)
			_replace(bad, path, replacement)
			bad_regions.append(bad)
	for replacement in [-1, 0.5, 32, 1e100, INF, NAN]:
		var bad: Dictionary = valid_region.duplicate(true)
		bad.corridors[0].a = replacement
		bad_regions.append(bad)
	for replacement in [-1, 0, 3.99, 24.01, INF]:
		var bad: Dictionary = valid_region.duplicate(true)
		bad.corridors[0].half_width = replacement
		bad_regions.append(bad)
	for replacement in [-1, 3.99, 32.01, INF]:
		var bad: Dictionary = valid_region.duplicate(true)
		bad.clearings[0].radius = replacement
		bad_regions.append(bad)
	for field in ["anchors", "corridors", "clearings"]:
		var bad: Dictionary = valid_region.duplicate(true)
		bad[field] = []
		bad_regions.append(bad)
		bad = valid_region.duplicate(true)
		var count := 65 if field == "corridors" else (33 if field == "anchors" else 17)
		while bad[field].size() < count:
			bad[field].append(bad[field][0].duplicate(true))
		bad_regions.append(bad)
	for reverse in [false, true]:
		var bad: Dictionary = valid_region.duplicate(true)
		var edge: Dictionary = bad.corridors[0].duplicate(true)
		if reverse:
			var index: Variant = edge.a
			edge.a = edge.b
			edge.b = index
		bad.corridors.append(edge)
		bad_regions.append(bad)
	var self_edge: Dictionary = valid_region.duplicate(true)
	self_edge.corridors[0].b = self_edge.corridors[0].a
	bad_regions.append(self_edge)
	for path in [["anchors", 0, "x"], ["clearings", 0, "center", "y"], ["bounds", "min", "x"]]:
		var bad: Dictionary = valid_region.duplicate(true)
		_replace(bad, path, 2048)
		bad_regions.append(bad)
	for bad in bad_regions:
		_check(not Validator.validate(bad, data.bounds).is_empty(), "Malformed nested region rejected without indexing/coercion errors")
	var region_path := region_directory + "/case.json"
	temporary_files.append(region_path)
	for source in ["{", "null", "[]", "{\"bounds\":{},\"anchors\":[],\"corridors\":[],\"clearings\":[]}", JSON.stringify(self_edge), JSON.stringify(valid_region), " ".repeat(Validator.MAX_REGION_BYTES + 1)]:
		var file := FileAccess.open(region_path, FileAccess.WRITE)
		_check(file != null, "Create test-owned local region fixture")
		if file == null:
			continue
		file.store_string(source)
		file.close()
		var local: Dictionary = data.duplicate(true)
		local.region_file = region_path
		_check(Recipe.validate(local).is_empty() == (source == JSON.stringify(valid_region)), "Actual recipe file loader cleanly accepts/rejects local region contents")
	for path in [true, "user://region.json", "res://worlds/regions/../elsewhere.json", region_directory + "/missing.json"]:
		var bad: Dictionary = data.duplicate(true)
		bad.region_file = path
		_check(not Recipe.validate(bad).is_empty(), "Invalid or missing local region path rejected")
	for path in [["seed"], ["route", 0, 2], ["clearings", 0, 0], ["bounds", 0]]:
		for replacement in [INF, NAN, 1e100, true, "bad"]:
			var bad: Dictionary = data.duplicate(true)
			_replace(bad, path, replacement)
			_check(not Recipe.validate(bad).is_empty(), "Nonfinite/coercion/absolute-coordinate input rejected before mesh generation")
	for seed in [-2147483649.0, 2147483648.0, 0.5]:
		var bad: Dictionary = data.duplicate(true)
		bad.seed = seed
		_check(not Recipe.validate(bad).is_empty(), "Seed bounded before integer conversion")
	for seed in [-2147483648.0, 2147483647.0]:
		var boundary: Dictionary = data.duplicate(true)
		boundary.seed = seed
		_check(Recipe.validate(boundary).is_empty(), "Both signed 32-bit seed endpoints accepted")
	for height in [-128.0, 128.0, -128.01, 128.01]:
		var boundary: Dictionary = data.duplicate(true)
		boundary.route[0][2] = height
		_check(Recipe.validate(boundary).is_empty() == (absf(height) <= 128), "Authored height bound is explicit and inclusive")
	_check(Validator.bounds_errors([0, 0, 224, 160]).is_empty(), "Exactly 140 aligned chunks allowed")
	_check(not Validator.bounds_errors([0.1, 0.1, 224.1, 160.1]).is_empty(), "Partial edge chunks count against the same budget")
	_check(not Validator.bounds_errors([0, 0, 512, 512]).is_empty(), "512-square dimensions cannot evade the actual mesh budget")
	_check(Validator.bounds_errors([1008, 1008, 1024, 1024]).is_empty() and not Validator.bounds_errors([1008, 1008, 1024.01, 1024]).is_empty(), "Absolute lattice coordinate bound is explicit")

func _replace(value: Dictionary, path: Array, replacement: Variant) -> void:
	var cursor: Variant = value
	for i in range(path.size() - 1):
		cursor = cursor[path[i]]
	cursor[path[-1]] = replacement
