extends SceneTree
## Geometry/material equivalence and exclusion checks for optional static batching.

const Batcher = preload("res://scripts/static_scenery_batch.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var terrain := Node3D.new()
	root.add_child(terrain)
	var holder := Node3D.new()
	holder.position = Vector3(4, 2, -3)
	holder.rotation = Vector3(0.2, 0.3, -0.1)
	terrain.add_child(holder)
	var original := _prop(holder, Color("a06534"))
	original.scale = Vector3(2.0, 0.5, 1.2)
	var expected_transform := holder.transform * original.transform
	var original_arrays := original.mesh.surface_get_arrays(0)
	_prop(terrain, Color("3e6255"))
	var unshadowed_a := _prop(terrain, Color("ccae68"))
	unshadowed_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var unshadowed_b := _prop(terrain, Color("9dbb89"))
	unshadowed_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gate := Node3D.new()
	terrain.add_child(gate)
	var gate_mesh := _prop(gate, Color.WHITE)
	var mirrored := _prop(terrain, Color.WHITE)
	mirrored.scale.x = -1
	var vertex_terrain := _prop(terrain, Color.WHITE)
	vertex_terrain.name = "ValleyGround"
	var textured := _prop(terrain, Color.WHITE)
	textured.material_override.albedo_texture = GradientTexture2D.new()
	var transparent := _prop(terrain, Color.WHITE)
	transparent.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shiny := _prop(terrain, Color.WHITE)
	shiny.material_override.roughness = 0.4
	var merged: int = Batcher.merge(terrain, [gate])
	if merged != 4:
		_fail("expected exactly four compatible sources, got %d" % merged)
		return
	await process_frame
	var batches: Array[MeshInstance3D] = []
	for node in terrain.get_children():
		if node is MeshInstance3D and String(node.name).begins_with("StaticSceneryBatch_"):
			batches.append(node)
	if batches.size() != 2:
		_fail("shadowed and unshadowed props must have separate batches")
		return
	var shadowed: MeshInstance3D
	for batch in batches:
		if batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			shadowed = batch
	if shadowed == null:
		_fail("shadow casting was lost")
		return
	var result := shadowed.mesh.surface_get_arrays(0)
	var normal_basis := expected_transform.basis.inverse().transposed()
	for index in original_arrays[Mesh.ARRAY_VERTEX].size():
		var expected_vertex: Vector3 = expected_transform * original_arrays[Mesh.ARRAY_VERTEX][index]
		var expected_normal: Vector3 = (normal_basis * original_arrays[Mesh.ARRAY_NORMAL][index]).normalized()
		if result[Mesh.ARRAY_VERTEX][index].distance_to(expected_vertex) > 0.00001 or result[Mesh.ARRAY_NORMAL][index].distance_to(expected_normal) > 0.0001:
			_fail("nonuniform transforms changed geometry or normals")
			return
		if not result[Mesh.ARRAY_COLOR][index].is_equal_approx(Color("a06534")):
			_fail("authored sRGB albedo must not be manually linearized")
			return
	for index in original_arrays[Mesh.ARRAY_INDEX].size():
		if result[Mesh.ARRAY_INDEX][index] != original_arrays[Mesh.ARRAY_INDEX][index]:
			_fail("source triangle winding/order changed")
			return
	for preserved in [gate_mesh, mirrored, vertex_terrain, textured, transparent, shiny]:
		if not is_instance_valid(preserved) or not preserved.visible:
			_fail("an excluded or incompatible source was changed")
			return
	if Batcher.merge(terrain, [gate]) != 0:
		_fail("rebatching must not consume the existing combined surfaces")
		return
	print("STATIC_SCENERY_BATCH_OK: geometry, normals, winding, authored color, shadow groups, exclusions, idempotence")
	terrain.queue_free()
	await process_frame
	quit(0)

func _prop(parent: Node3D, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 4
	instance.mesh = sphere
	var material := StandardMaterial3D.new()
	material.roughness = 0.95
	material.albedo_color = color
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _fail(message: String) -> void:
	push_error("STATIC_SCENERY_BATCH_FAILED: " + message)
	quit(1)
