class_name StaticSceneryBatch
extends RefCounted
## Optional construction-time batching for a disposable static scenery subtree.
## Returns the number of primitive instances replaced; never traverses exclusions.

static func merge(root: Node3D, excluded_roots: Array[Node]) -> int:
	if root == null or excluded_roots.has(root):
		return 0
	var defaults := StandardMaterial3D.new()
	defaults.roughness = 0.95
	var material_rules: Dictionary = {}
	for property: Dictionary in defaults.get_property_list():
		var key := String(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if key == "albedo_color" or key.begins_with("resource_") or key.begins_with("metadata/"):
			continue
		material_rules[key] = defaults.get(key)
	var groups: Dictionary = {}
	var material_cache: Dictionary = {}
	_collect(root, Transform3D.IDENTITY, excluded_roots, groups, material_rules, material_cache)
	var merged := 0
	for key: String in groups:
		var group: Dictionary = groups[key]
		var sources: Array = group.sources
		# A singleton saves no draw calls and benefits from its original bounds.
		if sources.size() < 2:
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.vertices
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_COLOR] = group.colors
		arrays[Mesh.ARRAY_INDEX] = group.indices
		var combined := ArrayMesh.new()
		combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.roughness = 0.95
		material.vertex_color_use_as_albedo = true
		# Pinned Compatibility converts the final albedo from sRGB in scene.glsl.
		# Keep authored material colors raw; manually linearizing would double-convert.
		material.vertex_color_is_srgb = true
		var batch := MeshInstance3D.new()
		batch.name = "StaticSceneryBatch_" + key.replace(":", "_")
		batch.mesh = combined
		batch.material_override = material
		batch.cast_shadow = group.cast_shadow
		batch.layers = group.layers
		batch.gi_mode = group.gi_mode
		root.add_child(batch)
		for source: MeshInstance3D in sources:
			source.hide()
			source.queue_free()
		merged += sources.size()
	return merged

static func _collect(node: Node3D, relative: Transform3D, excluded: Array[Node], groups: Dictionary, rules: Dictionary, cache: Dictionary) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or excluded.has(child):
			continue
		var spatial := child as Node3D
		if not spatial.visible or spatial.is_set_as_top_level():
			continue
		var local := relative * spatial.transform
		if local.basis.determinant() <= 0.000001:
			continue
		if spatial is MeshInstance3D:
			_append(spatial, local, groups, rules, cache)
		_collect(spatial, local, excluded, groups, rules, cache)

static func _append(source: MeshInstance3D, local: Transform3D, groups: Dictionary, rules: Dictionary, cache: Dictionary) -> void:
	var source_name := String(source.name).to_lower()
	if source_name.contains("valleyground") or source_name.contains("ridge") or source_name.contains("trail"):
		return
	if not source.mesh is PrimitiveMesh or source.mesh.get_surface_count() != 1:
		return
	if source.get_child_count() > 0 or source.get_script() != null or source.mesh.get_script() != null:
		return
	if source.skin != null or source.material_overlay != null or source.transparency != 0.0:
		return
	if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0:
		return
	var material := source.get_active_material(0) as StandardMaterial3D
	if material == null or not _plain_material(material, rules, cache):
		return
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or normals.size() != vertices.size():
		return
	if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty():
		return
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		if vertices.size() % 3 != 0:
			return
		for index in vertices.size():
			indices.append(index)
	if indices.size() % 3 != 0:
		return
	for index in indices:
		if index < 0 or index >= vertices.size():
			return
	var key := "%d:%d:%d" % [source.cast_shadow, source.layers, source.gi_mode]
	if not groups.has(key):
		groups[key] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
			"colors": PackedColorArray(), "indices": PackedInt32Array(), "sources": [],
			"cast_shadow": source.cast_shadow, "layers": source.layers, "gi_mode": source.gi_mode}
	var group: Dictionary = groups[key]
	var offset: int = group.vertices.size()
	var normal_basis := local.basis.inverse().transposed()
	for index in vertices.size():
		group.vertices.append(local * vertices[index])
		group.normals.append((normal_basis * normals[index]).normalized())
		group.colors.append(material.albedo_color)
	# Retain the source index order exactly. Positive determinants preserve winding.
	for index in indices:
		group.indices.append(offset + index)
	group.sources.append(source)

static func _plain_material(material: StandardMaterial3D, rules: Dictionary, cache: Dictionary) -> bool:
	var id := material.get_instance_id()
	if cache.has(id):
		return cache[id]
	var compatible := material.get_script() == null and is_equal_approx(material.albedo_color.a, 1.0)
	for key: String in rules:
		if material.get(key) != rules[key]:
			compatible = false
			break
	cache[id] = compatible
	return compatible
