extends SceneTree
## Geometry, whole-footprint clearance and offline ownership/retention checks.

const Recipe = preload("res://scripts/landscape_recipe.gd")
const Props = preload("res://scripts/landscape_props.gd")
var checks := 0
var failures := 0

class ControlledRecipe extends RefCounted:
	var points: Array = []
	func scatter(_key: Vector2i) -> Array:
		return points
	func surface_height(x: float, z: float) -> float:
		return x * 0.1 + z * 0.03
	func route_clearance(point: Vector2) -> float:
		return 2.0 - point.length()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("PROPS_FAILED: " + message)

func _transform(buffer: PackedFloat32Array, i: int) -> Transform3D:
	var offset := i * 16
	return Transform3D(Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]), Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]), Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])), Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11]))

func _same_bounds(a: AABB, b: AABB) -> bool:
	return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)

func _meshes(builder: RefCounted) -> void:
	_check(builder.meshes.size() == 10, "Only ten shared meshes, no per-placement geometry")
	for id: String in builder.meshes:
		var mesh: ArrayMesh = builder.meshes[id]
		var count := Props.triangle_count(mesh)
		_check(count == int(mesh.get_meta("triangle_count")), "Cached triangle count matches actual mesh")
		_check(Props._radius(mesh) == float(mesh.get_meta("footprint_radius")), "Cached silhouette radius includes actual vertices")
		_check(count > 20 and count <= 440, "Bounded solid silhouette: " + id)
		_check(mesh.get_aabb().position.y >= -0.00001, "Every prop has an actual base at ground level: " + id)
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			_check(normals.size() == vertices.size() and vertices.size() % 3 == 0, "Every triangle carries explicit normals")
			for i in range(0, vertices.size(), 3):
				var front := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i])
				_check(front.length_squared() > 0.000000001, "No degenerate faces: " + id)
				for j in 3:
					_check(vertices[i + j].is_finite() and normals[i + j].is_finite() and absf(normals[i + j].length() - 1) < 0.00001, "Finite geometry and unit normals")
					_check(front.normalized().dot(normals[i + j]) > 0.9999, "Lighting normal matches clockwise front")
		if id.begins_with("tree"):
			_check(mesh.get_surface_count() == 2 and mesh.get_aabb().size.y > 5.5, "Pines have independent woody trunk and long branch crown")
		if id.begins_with("cactus"):
			_check(mesh.get_aabb().size.x > 1.9 and mesh.get_aabb().size.y > 2.7, "Cactus has articulated arms, not only a post")
	_check(builder.meshes.tree_0.get_aabb() != builder.meshes.tree_1.get_aabb() and builder.meshes.tree_1.get_aabb() != builder.meshes.tree_2.get_aabb(), "Three different pine silhouettes")
	_check(builder.stone.albedo_texture is Texture2D and builder.stone.normal_texture is Texture2D and builder.stone.roughness_texture is Texture2D, "CC0 rock kit textures resolve")
	_check(builder.stone.albedo_texture.resource_path == "res://assets/materials/rock_01/rock_01_diff_1k.jpg", "Stone uses the provenance-tracked rock kit")
	_check(builder.stone.uv1_triplanar and builder.stone.uv1_world_triplanar, "Rock detail does not require invented mesh UVs")

func _chunk(profile: RefCounted, chunk: Node3D) -> void:
	_check(chunk.get_child_count() <= 7, "At most three tall variants, three stones and one scrub batch per chunk")
	_check(int(chunk.get_meta("tall")) <= Props.MAX_TALL and int(chunk.get_meta("stones")) <= Props.MAX_STONES and int(chunk.get_meta("scrub")) <= Props.MAX_SCRUB, "Per-kind instance caps")
	_check(int(chunk.get_meta("instances")) <= Props.MAX_TALL + Props.MAX_STONES + Props.MAX_SCRUB, "Bounded chunk instance count")
	for batch: MultiMeshInstance3D in chunk.get_children():
		_check(batch.owner == chunk and batch.get_child_count() == 0, "Owned leaf batch without per-branch nodes")
		var multi := batch.multimesh
		var buffer := multi.buffer
		var placements: Array = batch.get_meta("placements")
		_check(buffer.size() == multi.instance_count * 16 and placements.size() == multi.instance_count, "Full CPU transform and color buffer retained headlessly")
		_check(batch.visibility_range_end <= 125 and batch.visibility_range_end >= 95, "Detail has chunk-local bounded draw distance")
		var bounds := AABB()
		for i in multi.instance_count:
			var transform := _transform(buffer, i)
			var origin := transform.origin
			var placement: Dictionary = placements[i]
			_check(origin == placement.position, "Serialized buffer retains exact grounded float32 origin")
			var height := Vector3(0, profile.surface_height(origin.x, origin.z), 0).y
			_check(origin.y == height, "Root lies on rendered triangular terrain, not analytical height")
			_check(absf(transform.basis.determinant() - pow(float(placement.scale), 3)) < 0.000002, "Rotation/scale survive CPU layout")
			var clearance := float(profile.route_clearance(Vector2(origin.x, origin.z)))
			_check(clearance < -float(placement.radius) - Props.FOOTPRINT_GAP, "Whole horizontal silhouette is strictly outside the walking union")
			# Independently sample the outer disk. The proven radius also bounds
			# every vertex, including cactus arms and the longest pine bough.
			for angle in [0.0, 0.73, 1.57, 2.39, 3.14, 3.92, 4.71, 5.43]:
				var point := Vector2(origin.x, origin.z) + Vector2(cos(angle), sin(angle)) * float(placement.radius)
				_check(float(profile.route_clearance(point)) < 0, "No overhanging branch disk enters playable ground")
			var instance_bounds: AABB = transform * multi.mesh.get_aabb()
			bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
		_check(_same_bounds(multi.custom_aabb, bounds), "Custom bounds include every transformed prop, not the origin")

func _pack_roundtrip(chunk: Node3D) -> void:
	var scene := Node3D.new()
	scene.name = "PropRetentionFixture"
	scene.add_child(chunk)
	Props.set_scene_owner(chunk, scene)
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "Prop scene packs with retargeted nested ownership")
	var path := "user://landscape-props-smoke-%d.scn" % OS.get_process_id()
	_check(ResourceSaver.save(packed, path) == OK, "Batched scene saves without a GPU")
	var stored: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_check(stored != null, "Batched scene reloads from disk")
	if stored != null:
		var copy := stored.instantiate()
		_check(copy.get_child_count() == 1 and copy.get_child(0).get_child_count() == chunk.get_child_count(), "All owned batches survive nested save/load")
		for i in chunk.get_child_count():
			var before: MultiMeshInstance3D = chunk.get_child(i)
			var after: MultiMeshInstance3D = copy.get_child(0).get_child(i)
			_check(before.multimesh.buffer == after.multimesh.buffer, "Saved CPU buffers retain every transform/color byte")
			_check(before.multimesh.custom_aabb == after.multimesh.custom_aabb, "Saved custom bounds retain distant chunk positions")
			_check(after.multimesh.mesh.get_surface_count() == before.multimesh.mesh.get_surface_count(), "All material surfaces retained")
		copy.free()
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only this test's temporary packed scene")
	scene.free()

func _negative_controls() -> void:
	var profile := ControlledRecipe.new()
	var builder := Props.new(profile, false)
	for point in [Vector3(0, 999, 0), Vector3(3, 999, 0)]:
		profile.points = [{"kind": "tree", "position": point, "scale": 1.0, "yaw": 0.0}]
		var unsafe := builder.build_chunk(Vector2i.ZERO)
		_check(unsafe.get_child_count() == 0, "Reject both an inside trunk and an outside trunk whose branches overhang the walkable disk")
		unsafe.free()
	profile.points.clear()
	for i in 100:
		profile.points.append({"kind": "tree", "position": Vector3(10 + i * 0.01, 999, 10), "scale": 1.0, "yaw": i * 0.1})
	var bounded := builder.build_chunk(Vector2i.ZERO)
	_check(int(bounded.get_meta("instances")) == Props.MAX_TALL, "Excess input placements cannot exceed the tall prop cap")
	for batch: MultiMeshInstance3D in bounded.get_children():
		for i in batch.multimesh.instance_count:
			var point := _transform(batch.multimesh.buffer, i).origin
			_check(point.y == Vector3(0, profile.surface_height(point.x, point.z), 0).y, "Stale scatter heights are resampled, not preserved")
	bounded.free()

func _run() -> void:
	_negative_controls()
	for id in ["long_valley", "dry_wash"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s.recipe.json" % id))
		_check(Recipe.validate(data).is_empty(), "Current authored recipe validates")
		var profile := Recipe.new(data)
		var builder := Props.new(profile)
		_meshes(builder)
		var instances := 0
		var triangles := 0
		var batches := 0
		var tall := 0
		var stones := 0
		var scrub := 0
		var max_instances := 0
		var max_batches := 0
		var max_triangles := 0
		var sample: Node3D
		var start := Time.get_ticks_msec()
		for key: Vector2i in profile.chunk_keys():
			var chunk := builder.build_chunk(key)
			_chunk(profile, chunk)
			instances += int(chunk.get_meta("instances"))
			triangles += int(chunk.get_meta("triangles"))
			batches += chunk.get_child_count()
			tall += int(chunk.get_meta("tall"))
			stones += int(chunk.get_meta("stones"))
			scrub += int(chunk.get_meta("scrub"))
			max_instances = maxi(max_instances, int(chunk.get_meta("instances")))
			max_batches = maxi(max_batches, chunk.get_child_count())
			max_triangles = maxi(max_triangles, int(chunk.get_meta("triangles")))
			if sample == null and chunk.get_child_count() >= 2:
				sample = chunk
				var again := builder.build_chunk(key)
				_check(again.get_child_count() == chunk.get_child_count(), "Deterministic chunk batch count")
				for i in chunk.get_child_count():
					_check(chunk.get_child(i).multimesh.buffer == again.get_child(i).multimesh.buffer, "Build order does not change prop transforms")
				again.free()
			else:
				chunk.free()
		_check(tall > 15 and stones > 10, "Large recipe contains visible tall silhouettes and stones")
		_check(triangles <= 300000 and instances <= 1600 and batches <= 650, "Full authored world remains inside explicit prop budget")
		if id == "dry_wash":
			_check(scrub > 10, "Cactus biome includes low branching scrub")
		_check(sample != null, "Nonempty distant batch available for persistence check")
		if sample != null:
			_pack_roundtrip(sample)
		print("LANDSCAPE_PROPS %s: %d instances (%d tall/%d stone/%d scrub), %d batches, %d triangles; build+checks %dms, not phone FPS" % [id, instances, tall, stones, scrub, batches, triangles, Time.get_ticks_msec() - start])
		print("LANDSCAPE_PROPS %s peak per chunk: %d instances, %d batches, %d triangles" % [id, max_instances, max_batches, max_triangles])
	print("LANDSCAPE_PROPS: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
