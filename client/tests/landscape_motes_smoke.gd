extends SceneTree
## Standalone optional effect only; never instantiates a gameplay scene, opens a
## network connection, alters cooked art, or contacts an Android device.
const Motes = preload("res://scripts/landscape_motes.gd")
const Recipe = preload("res://scripts/landscape_recipe.gd")
var checks := 0
var failures := 0
var _failures_seen := {}
var _peak_visible := 0
var _min_clearance := INF
var _max_clearance := 0.0

class Ground:
	extends RefCounted
	var calls := 0
	var invalid := false
	func surface_height(x: float, z: float) -> float:
		calls += 1
		# Piecewise-linear one-unit ridge: exact rectangle vertex extrema bound it.
		return NAN if invalid else absf(x) * 0.12 + z * 0.03

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	if not _failures_seen.has(message): printerr("LANDSCAPE_MOTES_FAILED: " + message)
	_failures_seen[message] = true

func _new_effect(surface: Object, biome := "alpine", focus := Vector2.ZERO, seed_value := 719) -> Node3D:
	var effect := Motes.new()
	root.add_child(effect)
	_check(effect.configure(surface, focus, biome, seed_value), "Finite actual-ground configuration succeeds")
	effect.set_process(false)
	return effect

func _run() -> void:
	_validation()
	var ground := Ground.new()
	var effect := _new_effect(ground)
	_geometry(effect)
	var initial: Dictionary = effect.debug_state()
	_check(not initial.enabled and not effect.is_processing() and effect._instances.multimesh.visible_instance_count == 0 and not effect._instances.visible, "Effect is fully disabled by default")
	effect.advance(20)
	_check(effect.debug_state().phase == 0, "Disabled effect neither ages nor emits")
	effect.set_enabled(true)
	effect.set_process(false)
	effect.advance(10)
	_check(effect.debug_state().phase == 0, "First enabled frame discards inherited wall time")
	var calls_before := ground.calls
	var global_quiet := 0.0
	var quiet_runs: Array[float] = []
	for step in 2800:
		var source_calls := ground.calls
		effect.advance(0.1)
		_check(ground.calls == source_calls, "No actual-ground sampler call occurs during a runtime step")
		_inspect_vertices(effect, ground, step % 3 == 0)
		var count: int = effect.debug_state().visible_motes
		if count == 0:
			global_quiet += 0.1
		elif global_quiet > 0:
			quiet_runs.append(global_quiet)
			global_quiet = 0.0
	_check(_peak_visible >= 2 and _peak_visible <= 4 and quiet_runs.size() >= 8, "Seeded two-to-four-mote bursts do not fill one another's global quiet gaps")
	for i in range(1, quiet_runs.size()): _check(quiet_runs[i] >= 24.2, "Every complete inter-burst gap has zero visible motes for over24 seconds")
	_check(effect.debug_state().terrain_samples == calls_before, "Runtime retains startup sample count without growing terrain sampling work")
	_lifecycle(effect)
	_reproducibility()
	_resource_roundtrip(effect)
	for pair in [["long_valley", "alpine", Vector2(-42, 64)], ["dry_wash", "cactus", Vector2(-38, 68)]]:
		var profile := Recipe.new(JSON.parse_string(FileAccess.get_file_as_string("res://worlds/" + pair[0] + ".recipe.json")))
		var real := _new_effect(profile, pair[1], pair[2])
		_geometry(real)
		real.set_enabled(true)
		real.set_process(false)
		real.advance(0.05)
		for frame in 320:
			real.advance(0.05)
			_inspect_vertices(real, profile, true)
		var stats: Dictionary = real.debug_state()
		print("MOTES_ACTUAL_GROUND: ", pair[0], " samples=", stats.terrain_samples, " ground_span=", stats.ground_max - stats.ground_min, " conservative_clearance=", stats.minimum_clearance_bound, "..", stats.maximum_clearance_bound)
		real.free()
	effect.free()
	await process_frame
	print("LANDSCAPE_MOTES_SMOKE: %d checks / %d failures; one opaque≤96tri batch, typical%d motes, global quiet gaps, deterministic frozen lifecycle; actual sampled vertex clearance %.4f..%.4fm; standalone only" % [checks, failures, _peak_visible, _min_clearance, _max_clearance])
	quit(1 if failures else 0)

func _validation() -> void:
	var ground := Ground.new()
	for args in [[null, Vector2.ZERO, "alpine", Vector2(6, 4)], [ground, Vector2.INF, "alpine", Vector2(6, 4)], [ground, Vector2.ZERO, "snow", Vector2(6, 4)], [ground, Vector2.ZERO, "cactus", Vector2(1, 4)], [ground, Vector2.ZERO, "cactus", Vector2(13, 4)], [ground, Vector2(1020, 0), "alpine", Vector2(6, 4)]]:
		var effect := Motes.new()
		root.add_child(effect)
		_check(not effect.configure(args[0], args[1], args[2], 1, args[3]) and not effect.configured and effect.get_child_count() == 0, "Invalid configuration fails before allocating any visible geometry")
		effect.free()
	ground.invalid = true
	var invalid := Motes.new()
	root.add_child(invalid)
	_check(not invalid.configure(ground, Vector2.ZERO, "alpine") and invalid.get_child_count() == 0, "Nonfinite actual mesh sample cannot be substituted with guessed ground")
	invalid.free()

func _geometry(effect: Node3D) -> void:
	_check(effect.get_child_count() == 1 and effect._instances is MultiMeshInstance3D, "Exactly one batched child with no per-mote nodes")
	var multi: MultiMesh = effect._instances.multimesh
	var mesh: ArrayMesh = multi.mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(mesh.get_surface_count() == 1 and vertices.size() == 24 and multi.instance_count == 12 and multi.visible_instance_count <= 4, "Eight-triangle shape has a hard12-instance/96-triangle cap")
	_check(effect._buffer.size() == 192 and multi.get_meta("cpu_instance_buffer") == effect._buffer and multi.custom_aabb == effect.debug_state().bounds, "Fixed192-float CPU buffer and explicit full wind-arc cull bounds")
	for point in vertices: _check(point.length() < Motes.MESH_REACH, "Actual vertex fits the conservative rotated silhouette sphere")
	for i in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i + 1]
		var c: Vector3 = vertices[i + 2]
		_check((c - a).cross(b - a).dot((a + b + c) / 3) > 0, "Every closed convex face has outward Godot-clockwise winding")
	var material: StandardMaterial3D = mesh.surface_get_material(0)
	_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not material.emission_enabled and material.metallic_specular == 0 and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.next_pass == null, "Muted opaque unshaded material cannot sparkle, emit, flash or add transparency passes")
	_check(effect._instances.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and effect._instances.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and effect._instances.visibility_range_end == 75, "No shadow/GI work and bounded75m distance culling")
	_check(not effect.configure(Ground.new(), Vector2.ZERO, "alpine"), "Already configured effect cannot replace private resources silently")

func _inspect_vertices(effect: Node3D, source: Object, inspect: bool) -> void:
	var state: Dictionary = effect.debug_state()
	var count: int = state.visible_motes
	_peak_visible = maxi(_peak_visible, count)
	_check(count >= 0 and count <= 4 and effect._instances.multimesh.visible_instance_count == count, "Visible count agrees with a single small global burst")
	if not inspect or count == 0: return
	_check(effect._instances.multimesh.buffer == effect._buffer, "Uploaded MultiMesh transform/color payload equals the retained CPU buffer")
	var vertices: PackedVector3Array = effect._instances.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in count:
		var transform := _transform(effect._buffer, i)
		_check(transform.origin.is_finite() and absf(transform.basis.determinant()) <= 1.000001, "Opaque fade changes bounded geometry scale, never alpha or a flash")
		for vertex in vertices:
			var actual := transform * vertex
			var ground: float = source.surface_height(actual.x, actual.z)
			var clearance := actual.y - ground
			_min_clearance = minf(_min_clearance, clearance)
			_max_clearance = maxf(_max_clearance, clearance)
			_check(state.bounds.has_point(actual) and state.area.has_point(Vector2(actual.x, actual.z)), "Every rotated/scaled actual vertex stays in its sampled rectangle and cull AABB")
			_check(is_finite(clearance) and clearance > 0 and clearance >= state.minimum_clearance_bound - 0.0001 and clearance <= state.maximum_clearance_bound + 0.0001, "Actual moving mesh vertices remain strictly above sampled ground within reported bounds")
		for offset in 4:
			var channel: float = effect._buffer[i * 16 + 12 + offset]
			_check(channel == 1 if offset == 3 else channel >= 0 and channel <= 0.55, "Instance colors stay muted with fully opaque alpha")

func _transform(buffer: PackedFloat32Array, index: int) -> Transform3D:
	var i := index * 16
	return Transform3D(Basis(Vector3(buffer[i], buffer[i + 4], buffer[i + 8]), Vector3(buffer[i + 1], buffer[i + 5], buffer[i + 9]), Vector3(buffer[i + 2], buffer[i + 6], buffer[i + 10])), Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]))

func _lifecycle(effect: Node3D) -> void:
	for pair in [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN], [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED], [Node.NOTIFICATION_PAUSED, Node.NOTIFICATION_UNPAUSED]]:
		var phase: float = effect.debug_state().phase
		var buffer: PackedFloat32Array = effect._buffer.duplicate()
		effect.notification(pair[0])
		effect.advance(100)
		_check(effect.debug_state().phase == phase and effect._buffer == buffer and not effect._instances.visible, "Background or tree pause freezes both clock and geometry")
		effect.notification(pair[1])
		effect.advance(100)
		_check(effect.debug_state().phase == phase and effect._buffer == buffer, "First returned foreground frame is discarded completely")
		effect.advance(0.05)
		_check(absf(effect.debug_state().phase - phase - 0.05) < 0.000001, "Only a fresh subsequent foreground step resumes gentle motion")
	effect.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	effect.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	effect.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var phase: float = effect.debug_state().phase
	effect.advance(50)
	_check(effect.debug_state().phase == phase and not effect._instances.visible, "Focus gain cannot override an outstanding application pause")
	effect.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	effect.advance(50)
	for mode in ["hidden", "active", "enabled"]:
		phase = effect.debug_state().phase
		if mode == "hidden": effect.hide()
		elif mode == "active": effect.set_active(false)
		else: effect.set_enabled(false)
		effect.advance(100)
		_check(effect.debug_state().phase == phase, mode + " freezes local phase")
		if mode == "hidden": effect.show()
		elif mode == "active": effect.set_active(true)
		else: effect.set_enabled(true)
		effect.advance(100)
		_check(effect.debug_state().phase == phase, mode + " restoration never catches up wall time")
	var parent := Node3D.new()
	root.add_child(parent)
	effect.reparent(parent)
	parent.hide()
	phase = effect.debug_state().phase
	effect.advance(100)
	_check(effect.debug_state().phase == phase and not effect.is_processing(), "Hidden ancestor freezes its child's actual processing, not only direct-hide state")
	parent.show()
	effect.set_process(false)
	effect.advance(100)
	_check(effect.debug_state().phase == phase, "Ancestor visibility restoration discards the first wall-time step")
	paused = true
	effect.advance(100)
	_check(effect.debug_state().tree_paused and effect.debug_state().phase == phase, "Actual SceneTree pause freezes the helper")
	paused = false
	effect.set_process(false)
	effect.advance(100)
	_check(not effect.debug_state().tree_paused and effect.debug_state().phase == phase, "Actual SceneTree resume does not replay missed time")
	effect.reparent(root)
	parent.free()
	effect.advance(100) # Reparent visibility notification may request one skip.
	phase = effect.debug_state().phase
	effect.advance(100)
	_check(absf(effect.debug_state().phase - phase - 0.1) < 0.000001, "Later long stalls advance at most0.1seconds")
	phase = effect.debug_state().phase
	for invalid in [0, -1, NAN, INF]: effect.advance(invalid)
	_check(effect.debug_state().phase == phase, "Nonpositive/nonfinite time cannot corrupt the local clock")
	effect.advance(1.0e308)
	effect.advance(1.0e308)
	_check(is_finite(effect.debug_state().discarded_time) and effect.debug_state().phase < Motes.CYCLE_SECONDS, "Finite extreme wall gaps cannot overflow the bounded phase or saturated diagnostic")
	effect.set_process(false)

func _reproducibility() -> void:
	var a := _new_effect(Ground.new())
	var b := _new_effect(Ground.new())
	var different := _new_effect(Ground.new(), "alpine", Vector2.ZERO, 720)
	_check(a.debug_state().bursts == b.debug_state().bursts and a.debug_state().bursts != different.debug_state().bursts, "Explicit seed reproduces paths without making every area identical")
	_check(a._instances.multimesh != b._instances.multimesh and a._instances.multimesh.mesh != b._instances.multimesh.mesh and a._instances.multimesh.mesh.surface_get_material(0) != b._instances.multimesh.mesh.surface_get_material(0), "Every effect owns private mesh/material/instance resources")
	for effect in [a, b]:
		effect.set_enabled(true)
		effect.set_process(false)
		effect.advance(0.05)
	for frame in 180:
		a.advance(0.05)
		b.advance(0.05)
		_check(a._buffer == b._buffer and a.debug_state().phase == b.debug_state().phase, "Equal seed and local steps produce byte-identical actual instance buffers")
	a.free()
	b.free()
	different.free()

func _resource_roundtrip(effect: Node3D) -> void:
	var packed := PackedScene.new()
	_check(packed.pack(effect) == OK, "An optional helper can be packed without serializing its active local clock")
	var restored := packed.instantiate() as Node3D
	root.add_child(restored)
	_check(not restored.configured and not restored.debug_state().enabled and not restored.is_processing() and restored.get_child_count() == 0, "Reloaded helper discards its owned stale pose and stays empty/disabled until explicitly configured")
	_check(restored.configure(Ground.new(), Vector2.ZERO, "alpine") and restored.get_child_count() == 1 and not restored._instances.visible, "Reloaded optional helper may be explicitly configured once without duplicate batches")
	restored.free()
	var path := OS.get_cache_dir().path_join("corgi-motes-" + str(OS.get_process_id()) + ".res")
	var multi: MultiMesh = effect._instances.multimesh
	_check(ResourceSaver.save(multi, path) == OK, "Private instance resource serializes for inspection")
	var loaded := ResourceLoader.load(path, "MultiMesh", ResourceLoader.CACHE_MODE_IGNORE) as MultiMesh
	_check(loaded != null and loaded.get_meta("cpu_instance_buffer") == effect._buffer and loaded.custom_aabb == multi.custom_aabb and loaded.instance_count == multi.instance_count and loaded.visible_instance_count == multi.visible_instance_count, "Saved private resource retains exact CPU buffer, culling and visible-instance count")
	_check(loaded.buffer == effect._buffer, "Serialized MultiMesh upload retains the actual nonzero transform/color buffer")
	_check(loaded.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == multi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Serialized mote geometry remains byte-identical")
	_check(DirAccess.remove_absolute(path) == OK, "Only the test's exact temporary resource is removed")
