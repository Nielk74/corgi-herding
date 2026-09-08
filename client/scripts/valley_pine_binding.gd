extends Node
## Per-world optional pine binding. Cached scene resources are NEVER edited.
## Only three shared pine meshes and their affected MultiMeshes are copied;
## geometry/buffers stay byte-identical and non-pine resources remain shared.
const Wind = preload("res://scripts/pine_needles_wind.gd")
const MOTION_REACH := 0.08
var clock: Node
var _scene: Node3D
var _active := true
var _bindings: Array[Dictionary] = []
var _meshes := {}
var _multis := {}
var _mesh_payload := 0
var _buffer_payload := 0

func configure(scene: Node3D) -> bool:
	if _scene != null or not is_instance_valid(scene):
		return false
	var candidates: Array[MultiMeshInstance3D] = []
	var source: StandardMaterial3D
	for node: Node in scene.find_children("*", "MultiMeshInstance3D", true, false):
		if not String(node.name).begins_with("Tree"):
			continue
		var multi: MultiMesh = node.multimesh
		if multi == null or not multi.mesh is ArrayMesh or multi.mesh.get_surface_count() != 2 or node.material_override != null:
			return false
		var needles := multi.mesh.surface_get_material(1) as StandardMaterial3D
		if needles == null or (source != null and source != needles):
			return false
		if multi.transform_format != MultiMesh.TRANSFORM_3D or not multi.use_colors or multi.use_custom_data or multi.buffer.size() != multi.instance_count * 16:
			return false
		# Current prop batches are untransformed with at least .1m cull margin.
		# Fail closed rather than silently widen an unsupported world's bounds.
		if node.global_basis != Basis.IDENTITY or node.extra_cull_margin < MOTION_REACH:
			return false
		source = needles
		candidates.append(node)
	if candidates.is_empty():
		return false
	var driver := Wind.new()
	if not driver.configure(source):
		driver.free()
		return false
	_scene = scene
	_mesh_payload = 0
	_buffer_payload = 0
	clock = driver
	add_child(clock)
	clock.set_enabled(true)
	for node: MultiMeshInstance3D in candidates:
		var original := node.multimesh
		var original_mesh := original.mesh as ArrayMesh
		if not _meshes.has(original_mesh):
			var copy := original_mesh.duplicate(false) as ArrayMesh
			copy.surface_set_material(1, clock.selected_material())
			# Only private clones can carry the animated scenic picking contract.
			copy.set_meta("pine_wind_surface", 1)
			copy.set_meta("pine_wind_reach", MOTION_REACH)
			_meshes[original_mesh] = copy
			_mesh_payload += _array_payload_bytes(copy)
		if not _multis.has(original):
			var copy := original.duplicate(false) as MultiMesh
			copy.mesh = _meshes[original_mesh]
			_multis[original] = copy
			_buffer_payload += original.buffer.size() * 4
		node.multimesh = _multis[original]
		_bindings.append({"node": node, "original": original, "private": node.multimesh})
	_scene.visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	return true

func set_active(value: bool) -> void:
	_active = value
	_sync_visibility()

func _sync_visibility() -> void:
	if is_instance_valid(clock):
		clock.set_active(_active and is_instance_valid(_scene) and _scene.is_visible_in_tree())

func detach() -> void:
	if is_instance_valid(clock):
		clock.set_enabled(false)
		clock.set_active(false)
		clock.queue_free()
	clock = null
	if is_instance_valid(_scene) and _scene.visibility_changed.is_connected(_sync_visibility):
		_scene.visibility_changed.disconnect(_sync_visibility)
	for record: Dictionary in _bindings:
		if is_instance_valid(record.node) and record.node.multimesh == record.private:
			record.node.multimesh = record.original
	_bindings.clear()
	_meshes.clear()
	_multis.clear()
	_scene = null

func _exit_tree() -> void:
	detach()

static func _array_payload_bytes(mesh: ArrayMesh) -> int:
	# Exposed packed-array payload, not an allocator/RSS or GPU-memory claim.
	# COW can share CPU storage; a new Mesh RID can still upload a private copy.
	var bytes := 0
	for surface in mesh.get_surface_count():
		for array: Variant in mesh.surface_get_arrays(surface):
			if array is PackedVector3Array:
				bytes += array.size() * 12
			elif array is PackedVector2Array:
				bytes += array.size() * 8
			elif array is PackedColorArray:
				bytes += array.size() * 16
			elif array is PackedInt32Array or array is PackedFloat32Array:
				bytes += array.size() * 4
			elif array is PackedByteArray:
				bytes += array.size()
	return bytes

func debug_state() -> Dictionary:
	return {"configured": is_instance_valid(_scene), "affected_batches": _bindings.size(),
		"cloned_meshes": _meshes.size(), "cloned_multimeshes": _multis.size(),
		"mesh_array_payload_bytes": _mesh_payload, "instance_buffer_payload_bytes": _buffer_payload,
		"added_draw_batches": 0, "clock": clock.debug_state() if is_instance_valid(clock) else {},
		"motion_reach": MOTION_REACH}
