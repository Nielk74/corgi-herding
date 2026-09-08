extends SceneTree
const Factory = preload("res://scripts/meadow.gd")
const Batch = preload("res://scripts/actor_batch.gd")
var checks := 0
var failures := 0
var compared_vertices := 0
var peak_position_error := 0.0
var peak_normal_error := 0.0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 30:
			printerr("ACTOR_BATCH_FAILED: " + message)

func _visible_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and node.visible else 0
	for child in node.get_children():
		count += _visible_meshes(child)
	return count

func _geometry(actor: Node3D, part: String) -> Dictionary:
	var body := actor.get_node("Body") as Node3D
	var node := body if part == "Body" else body.get_node_or_null(part) as Node3D
	var result := {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "indices": PackedInt32Array(), "draw_flags": PackedInt32Array(), "materials": {}}
	if node == null:
		return result
	var exclusions: Array[Node] = []
	if part == "Body":
		for name in ["Head", "Tail"]:
			var animated := body.get_node_or_null(name)
			if animated != null:
				exclusions.append(animated)
	_collect_geometry(node, exclusions, result)
	return result

func _collect_geometry(node: Node3D, exclusions: Array[Node], result: Dictionary) -> void:
	if exclusions.has(node) or not node.visible:
		return
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var transform := instance.global_transform
		var normal_basis := transform.basis.inverse().transposed()
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as StandardMaterial3D
			check(material != null, "Factory and batch retain lit StandardMaterial surfaces")
			if material == null:
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var base: int = result.positions.size()
			for index in vertices.size():
				result.positions.append(transform * vertices[index])
				result.normals.append((normal_basis * normals[index]).normalized())
				var color := material.albedo_color
				if material.vertex_color_use_as_albedo:
					check(material.vertex_color_is_srgb and colors is PackedColorArray and colors.size() == vertices.size(), "Baked per-part colors retain authored sRGB semantics")
					color *= colors[index]
				result.colors.append(color)
				result.draw_flags.append_array(PackedInt32Array([instance.cast_shadow, instance.layers, instance.gi_mode]))
			if indices is PackedInt32Array and not indices.is_empty():
				for index in indices:
					result.indices.append(base + index)
			else:
				for index in vertices.size():
					result.indices.append(base + index)
			# Color is intentionally baked above; all remaining lighting modes
			# must match the original plain-material renderer semantics.
			var semantics := [material.roughness, material.metallic, material.metallic_specular, material.shading_mode, material.cull_mode, material.transparency, material.depth_draw_mode]
			result.materials[JSON.stringify(semantics)] = true
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_geometry(child, exclusions, result)

func _equivalent(a: Dictionary, b: Dictionary, record_peaks := false) -> bool:
	if a.positions.size() != b.positions.size() or a.normals.size() != b.normals.size() or a.colors.size() != b.colors.size() or a.indices != b.indices or a.draw_flags != b.draw_flags or a.materials != b.materials:
		return false
	for i in a.positions.size():
		if not a.positions[i].is_finite() or not b.positions[i].is_finite() or not a.normals[i].is_finite() or not b.normals[i].is_finite():
			return false
		if absf(a.normals[i].length() - 1.0) > 0.00001 or absf(b.normals[i].length() - 1.0) > 0.00001:
			return false
		var position_error: float = a.positions[i].distance_to(b.positions[i])
		var normal_error: float = a.normals[i].distance_to(b.normals[i])
		if record_peaks:
			compared_vertices += 1
			peak_position_error = maxf(peak_position_error, position_error)
			peak_normal_error = maxf(peak_normal_error, normal_error)
		# ArrayMesh normals have renderer packing; inverse-transpose under a
		# nonuniform actor pose can amplify its last-bit angular quantization.
		if position_error > 0.00003 or normal_error > 0.0002 or not a.colors[i].is_equal_approx(b.colors[i]):
			return false
	return true

func _pose(actor: Node3D, pose: int) -> void:
	actor.position = Vector3(41.25, 12.3, -62.5)
	actor.rotation = Vector3(0.04, 0.31 + pose * 0.63, -0.025)
	actor.scale = Vector3(1.25, 0.78, 1.08) if pose == 5 else Vector3.ONE
	var body := actor.get_node("Body") as Node3D
	body.rotation = Vector3(0, 0, 0.035 if pose in [1, 3, 5] else 0)
	body.position.y = -0.32 if pose == 2 else (0.07 if pose == 1 else 0.0)
	var head := body.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = -0.82 if pose in [3, 5] else 0.0
	var tail := body.get_node_or_null("Tail") as Node3D
	if tail != null:
		tail.position.x = 0.13 if pose in [1, 4] else (-0.13 if pose == 5 else 0.0)

func _negative_controls(sample: Dictionary) -> void:
	for field in ["positions", "normals", "colors", "indices", "draw_flags", "materials", "nonfinite_position", "nonfinite_normal", "zero_normal"]:
		var changed: Dictionary = sample.duplicate(true)
		match field:
			"positions": changed.positions[0] += Vector3(0.002, 0, 0)
			"normals": changed.normals[0] = -changed.normals[0]
			"colors": changed.colors[0] = Color.MAGENTA
			"indices": changed.indices[0] = changed.indices[1]
			"draw_flags": changed.draw_flags[0] = -1
			"materials": changed.materials["unexpected"] = true
			"nonfinite_position": changed.positions[0] = Vector3(NAN, 0, 0)
			"nonfinite_normal": changed.normals[0] = Vector3(INF, 0, 0)
			"zero_normal": changed.normals[0] = Vector3.ZERO
		check(not _equivalent(sample, changed), "Comparison rejects mutated " + field)

func _run() -> void:
	var factory := Factory.new()
	var old_count := 0
	var new_count := 0
	for i in range(14):
		var kind := "player" if i < 2 else ("dog" if i < 4 else "sheep")
		var id := ("mochi" if i == 2 else "maple") if i in [2, 3] else "batch_test_%d" % i
		var actor: Node3D = factory.make_actor(kind, id, i == 1)
		factory.remove_child(actor)
		root.add_child(actor)
		var reference: Node3D = factory.make_actor(kind, id, i == 1)
		factory.remove_child(reference)
		root.add_child(reference)
		# Merge after an existing whole-actor/body pose: world placement must
		# not be accidentally baked into the local body geometry a second time.
		_pose(actor, 1)
		_pose(reference, 1)
		var body := actor.get_node("Body") as Node3D
		var head := body.get_node_or_null("Head") as Node3D
		var tail := body.get_node_or_null("Tail") as Node3D
		var tail_mesh: Mesh = tail.mesh if tail is MeshInstance3D else null
		var tail_material: Material = tail.material_override if tail is MeshInstance3D else null
		var before := _visible_meshes(actor)
		old_count += before
		check(Batch.optimize(actor) > 0, "Rigid body parts were batched")
		await process_frame
		var after := _visible_meshes(actor)
		new_count += after
		check(after <= 2 and after < before, "Each actor now uses one or two visible mesh batches")
		check(actor.get_node("Body") == body, "Body animation node is unchanged")
		if head != null:
			check(body.get_node("Head") == head, "Sheep head remains its original animated node")
			head.rotation.x = -0.82
			check(head.get_child_count() == 1 and head.get_child(0).get_parent() == head, "Batched head geometry still follows nibbling rotation")
		if tail != null:
			check(body.get_node("Tail") == tail and tail is MeshInstance3D, "Dog tail remains the original movable mesh")
			check(tail.mesh == tail_mesh and tail.material_override == tail_material, "Wagging tail retains the exact original geometry and material resources")
			tail.position.x = 0.13
			check(tail.position.x > 0.12, "Tail can still wag independently")
		body.rotation.z = 0.035
		body.position.y = -0.32
		check(Batch.optimize(actor) == 0, "Repeated optimization is a no-op")
		for pose in 6:
			_pose(actor, pose)
			_pose(reference, pose)
			for part in ["Body", "Head", "Tail"]:
				var original := _geometry(reference, part)
				var batched := _geometry(actor, part)
				check(_equivalent(original, batched, true), "%s %s pose%d preserves every vertex, inverse-transpose normal, triangle index, authored color and render mode" % [kind, part, pose])
				if i == 0 and pose == 0 and part == "Body":
					_negative_controls(original)
		check(not reference.get_node("Body").get_meta("rigid_parts_batched", false), "Reference actor is not accidentally optimized by the comparison")
		actor.free()
		reference.free()
	factory.free()
	print("ACTOR_BATCH: %d checks / %d failures; %d→%d visible meshes for the same two herders/two dogs/ten sheep" % [checks, failures, old_count, new_count])
	print("ACTOR_BATCH_EQUIVALENCE: %d posed vertex comparisons; peak position error %.9f, normal error %.9f; nine negative controls" % [compared_vertices, peak_position_error, peak_normal_error])
	quit(0 if failures == 0 else 1)
