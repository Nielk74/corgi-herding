extends SceneTree
## Actual construction/cache comparison. The disabled reference assembles the
## same existing modules without assigning the new optional scree hook.
## No gameplay save, shader, runtime source or prepared cache is modified here.
const Recipe = preload("res://scripts/landscape_recipe.gd")
const Chunks = preload("res://scripts/landscape_chunk_builder.gd")
const Backdrop = preload("res://scripts/landscape_backdrop.gd")
const Props = preload("res://scripts/landscape_props.gd")
const FullBuilder = preload("res://scripts/landscape_scene_builder.gd")
const Navigation = preload("res://scripts/region_navigation.gd")
const Scree = preload("res://scripts/landscape_scree.gd")
var checks := 0
var failures := 0
var compared_vertices := 0
var painted_vertices := 0
var legal_vertices := 0
var face_probes := 0
var painted_faces := 0
var negative_controls := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 25:
			printerr("SCREE_RENDER_FAILED: " + message)

func _without_scree(profile: RefCounted) -> Node3D:
	# Frozen integration baseline: no Scree instance and no channel encoding.
	# Terrain/props/backdrop algorithms themselves are deliberately shared;
	# this checks that enabling the material feature changes ONLY its channel.
	var chunks := Chunks.new(profile, true, true)
	var scene := chunks.build_scene(true)
	var backdrop := Backdrop.new(profile)
	var props := Props.new(profile, true)
	var keys: Array[Vector2i] = profile.chunk_keys()
	for key: Vector2i in keys:
		scene.add_child(props.build_chunk(key))
	for x in range(keys[0].x - 2, keys[-1].x + 3):
		for z in range(keys[0].y - 2, keys[-1].y + 3):
			var key := Vector2i(x, z)
			if not keys.has(key):
				scene.add_child(chunks.build_chunk(key))
	for child in scene.get_children():
		if child is MeshInstance3D:
			child.material_override = backdrop.surface_material
	scene.add_child(backdrop.build())
	return scene

func _inventory(scene: Node3D) -> Dictionary:
	var records := {}
	var resources := {"meshes": {}, "materials": {}, "multimeshes": {}}
	var nodes: Array[Node] = [scene]
	var count := 0
	var triangles := 0
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		count += 1
		nodes.append_array(node.get_children())
		if not node is MeshInstance3D and not node is MultiMeshInstance3D:
			continue
		var instance := node as GeometryInstance3D
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var copies: int = 1 if node is MeshInstance3D else node.multimesh.instance_count
		var path := String(scene.get_path_to(node))
		var surfaces := []
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			surfaces.append(arrays)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3 * copies
			var material: Material = node.get_active_material(i) if node is MeshInstance3D else (instance.material_override if instance.material_override != null else mesh.surface_get_material(i))
			if material != null:
				resources.materials[material.get_instance_id()] = true
			var surface_material := mesh.surface_get_material(i)
			if surface_material != null:
				resources.materials[surface_material.get_instance_id()] = true
		resources.meshes[mesh.get_instance_id()] = true
		var record := {"surfaces": surfaces, "transform": instance.transform, "bounds": mesh.get_aabb(),
			"shadow": instance.cast_shadow, "layers": instance.layers, "gi": instance.gi_mode,
			"visible": instance.visible, "start": instance.visibility_range_begin, "end": instance.visibility_range_end,
			"margin": instance.extra_cull_margin, "copies": copies, "formats": []}
		for i in mesh.get_surface_count():
			record.formats.append(mesh.surface_get_format(i))
		if node is MultiMeshInstance3D:
			resources.multimeshes[node.multimesh.get_instance_id()] = true
			record.buffer = node.multimesh.buffer
			record.instance_bounds = node.multimesh.custom_aabb
			record.instance_format = node.multimesh.transform_format
			record.colors = node.multimesh.use_colors
			record.custom = node.multimesh.use_custom_data
		records[path] = record
	return {"records": records, "nodes": count, "batches": records.size(), "triangles": triangles,
		"meshes": resources.meshes.size(), "materials": resources.materials.size(), "multimeshes": resources.multimeshes.size()}

func _compare(before: Dictionary, after: Dictionary, allow_red: bool, label: String) -> void:
	for field in ["nodes", "batches", "triangles", "meshes", "materials", "multimeshes"]:
		check(before[field] == after[field], "%s adds no %s" % [label, field])
	check(before.records.size() == after.records.size(), label + " preserves rendered node paths")
	for path: String in before.records:
		check(after.records.has(path), label + " retains " + path)
		if not after.records.has(path):
			continue
		var a: Dictionary = before.records[path]
		var b: Dictionary = after.records[path]
		for field: String in a:
			if field != "surfaces":
				check(a[field] == b.get(field), label + " preserves actual transforms/cull flags/instance buffers: " + field)
		check(a.surfaces.size() == b.surfaces.size(), label + " preserves surface count")
		for surface in mini(a.surfaces.size(), b.surfaces.size()):
			var first: Array = a.surfaces[surface]
			var second: Array = b.surfaces[surface]
			check(_channels_preserved(first, second, allow_red and path.begins_with("Ground_")), label + " passes the shared channel-preservation predicate")
			for channel in Mesh.ARRAY_MAX:
				if channel == Mesh.ARRAY_COLOR and allow_red and path.begins_with("Ground_"):
					var original: PackedColorArray = first[channel]
					var candidate: PackedColorArray = second[channel]
					check(original.size() == candidate.size(), label + " preserves real vertex color count")
					for i in mini(original.size(), candidate.size()):
						check(original[i].g == candidate[i].g and original[i].b == candidate[i].b and original[i].a == candidate[i].a, label + " keeps G/B and trail alpha exactly unchanged")
				else:
					check(first[channel] == second[channel], "%s preserves exact mesh channel%d at%s" % [label, channel, path])
			compared_vertices += second[Mesh.ARRAY_VERTEX].size()
	if negative_controls == 0:
		for path: String in before.records:
			if path.begins_with("Ground_"):
				_negative_controls(before.records[path].surfaces[0])
				break

func _channels_preserved(a: Array, b: Array, allow_red: bool) -> bool:
	if a.size() != b.size():
		return false
	for channel in Mesh.ARRAY_MAX:
		if channel != Mesh.ARRAY_COLOR or not allow_red:
			if a[channel] != b[channel]:
				return false
		else:
			if not a[channel] is PackedColorArray or not b[channel] is PackedColorArray or a[channel].size() != b[channel].size():
				return false
			for i in a[channel].size():
				if a[channel][i].g != b[channel][i].g or a[channel][i].b != b[channel][i].b or a[channel][i].a != b[channel][i].a:
					return false
	return true

func _negative_controls(sample: Array) -> void:
	for field in ["vertex", "normal", "indices", "uv", "uv2", "green", "blue", "trail_alpha"]:
		var changed := sample.duplicate(true)
		match field:
			"vertex": changed[Mesh.ARRAY_VERTEX][0] += Vector3(0, 0.01, 0)
			"normal": changed[Mesh.ARRAY_NORMAL][0] = -changed[Mesh.ARRAY_NORMAL][0]
			"indices": changed[Mesh.ARRAY_INDEX][0] = changed[Mesh.ARRAY_INDEX][1]
			"uv": changed[Mesh.ARRAY_TEX_UV][0] += Vector2(0.01, 0)
			"uv2": changed[Mesh.ARRAY_TEX_UV2][0] += Vector2(0.01, 0)
			_:
				var color: Color = changed[Mesh.ARRAY_COLOR][0]
				if field == "green": color.g = 0.123
				elif field == "blue": color.b = 0.123
				else: color.a = 0.123
				changed[Mesh.ARRAY_COLOR][0] = color
		check(not _channels_preserved(sample, changed, true), "Shared comparison rejects intentional " + field + " corruption")
		negative_controls += 1
	var red_only := sample.duplicate(true)
	var color: Color = red_only[Mesh.ARRAY_COLOR][0]
	color.r = 0.123
	red_only[Mesh.ARRAY_COLOR][0] = color
	check(_channels_preserved(sample, red_only, true) and not _channels_preserved(sample, red_only, false), "Only intended construction red is allowed; saved-cache red corruption is rejected")
	negative_controls += 1

func _material_and_mask(scene: Node3D, data: Dictionary, navigation: RefCounted, expected: RefCounted) -> void:
	var alpine: bool = data.biome == "alpine"
	var far_meshes := 0
	var fine_meshes := 0
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var fine := String(instance.name).begins_with("Ground_")
		var far := String(instance.name).begins_with("Scenic_")
		if not fine and not far:
			continue
		var material := instance.get_active_material(0) as ShaderMaterial
		check(material != null and material.get_shader_parameter("scree_enabled") == alpine, "Full-scene enable flag is true only for Alpine, false for cactus")
		if material != null:
			var code: String = material.shader.code
			check(code.contains("uniform bool scree_enabled = false;") and code.contains("scree_enabled ? clamp(1.0 - COLOR.r"), "Shader is default-off and decodes the actual inverse red channel")
			check(not code.contains("ALPHA =") and not code.contains("discard"), "Material stays opaque with no additional transparency/decal pass")
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			if far:
				far_meshes += 1
				var far_color: Variant = arrays[Mesh.ARRAY_COLOR]
				check(far_color == null or far_color.is_empty(), "Distant surfaces retain their uncolored default-white input")
				check(1.0 - Color.WHITE.r == 0.0, "Default-white far terrain decodes to zero scree even when the Alpine material is enabled")
				continue
			fine_meshes += 1
			if not alpine:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in vertices.size():
				var point := Vector2(vertices[i].x, vertices[i].z)
				var value := 1.0 - colors[i].r
				check(absf(value - expected.mask(point)) <= 1.0 / 255.0, "Cooked red retains expected mask within renderer color packing precision")
				if navigation.contains(point):
					legal_vertices += 1
					check(value == 0.0, "Actual prepared legal vertex has exactly zero scree")
				if value > 0:
					painted_vertices += 1
					check(navigation.signed_clearance(point) < -2, "Actual stored painted vertex is beyond the full one-unit face diameter from legality")
			for face in range(0, indices.size(), 3):
				if colors[indices[face]].r == 1 and colors[indices[face + 1]].r == 1 and colors[indices[face + 2]].r == 1:
					continue
				painted_faces += 1
				var a := vertices[indices[face]]
				var b := vertices[indices[face + 1]]
				var c := vertices[indices[face + 2]]
				for vertex in [a, b, c]:
					check(Vector2(vertex.x - a.x, vertex.z - a.z).length_squared() <= 2.0, "Actual painted triangles keep the claimed one-unit grid diameter")
				for ia in 5:
					for ib in range(5 - ia):
						var point: Vector3 = a * (ia / 4.0) + b * (ib / 4.0) + c * (1.0 - (ia + ib) / 4.0)
						check(not navigation.contains(Vector2(point.x, point.z)), "Actual interpolated colored face never overlaps canonical walkability")
						face_probes += 1
	check(far_meshes == 92 and fine_meshes == 224, "Fine/apron and distant mesh coverage are complete")

func _run() -> void:
	for id in ["long_valley", "dry_wash"]:
		var cache := "res://generated/%s.scn" % id
		check(ResourceLoader.exists(cache), "Cook the next-candidate cache before this prepared test")
		if not ResourceLoader.exists(cache):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		var navigation: RefCounted
		var expected: RefCounted
		if data.has("region_file"):
			navigation = Navigation.new(JSON.parse_string(FileAccess.get_file_as_string(data.region_file)))
			expected = Scree.new(navigation)
		var original := _without_scree(Recipe.new(data))
		root.add_child(original)
		var baseline := _inventory(original)
		var candidate := FullBuilder.new(Recipe.new(data)).build()
		root.add_child(candidate)
		var fresh := _inventory(candidate)
		_compare(baseline, fresh, data.biome == "alpine", id + " before/after")
		_material_and_mask(candidate, data, navigation, expected)
		var packed := ResourceLoader.load(cache, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(packed != null, "Prepared scene loads from disk")
		if packed != null:
			var loaded := packed.instantiate() as Node3D
			root.add_child(loaded)
			check(loaded.get_meta("source_recipe", {}) == data and loaded.get_meta("full_visual_scene", false), "Saved artifact belongs to this full-scene recipe")
			_compare(fresh, _inventory(loaded), false, id + " fresh/saved")
			_material_and_mask(loaded, data, navigation, expected)
			loaded.free()
		print("SCREE_RENDER_SCENE %s: %d nodes,%d batches,%d triangles,%d mesh resources,%d material resources unchanged" % [id, fresh.nodes, fresh.batches, fresh.triangles, fresh.meshes, fresh.materials])
		candidate.free()
		original.free()
	check(painted_vertices > 200 and painted_vertices < 1000 and legal_vertices > 20000 and painted_faces > 500 and face_probes > 7000, "Substantial stored-mask/interpolation evidence in both fresh and saved Alpine scenes")
	print("LANDSCAPE_SCREE_RENDER_SMOKE: %d checks/%d failures;%d actual compared vertices,%d legal vertices,%d painted vertices,%d painted faces,%d interpolation probes,%d negative controls; no Android visual acceptance" % [checks, failures, compared_vertices, legal_vertices, painted_vertices, painted_faces, face_probes, negative_controls])
	quit(1 if failures else 0)
