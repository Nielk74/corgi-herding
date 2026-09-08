extends SceneTree
## Deterministic source-mesh/lifecycle QA. Not Android visibility or GPU timing.
const Life = preload("res://scripts/valley_life.gd")
const Meadow = preload("res://scripts/meadow.gd")
var checks := 0
var failures := 0
var peak_speed := 0.0

class Surface:
	extends RefCounted
	var calls := 0
	func node_height(x: float, z: float) -> float:
		return Vector3(0, 20 + sin(x * 0.11) * 9 + cos(z * 0.06) * 6 + absf(sin((x + z) * 0.031)) * 8, 0).y
	func surface_height(x: float, z: float) -> float:
		calls += 1
		var ix := floorf(x)
		var iz := floorf(z)
		var fx := x - ix
		var fz := z - iz
		var a := node_height(ix, iz)
		var b := node_height(ix + 1, iz)
		var c := node_height(ix + 1, iz + 1)
		var d := node_height(ix, iz + 1)
		return a + (b - a) * fx + (c - b) * fz if fz <= fx else a + (c - d) * fx + (d - a) * fz

class BadSurface:
	extends RefCounted
	func surface_height(_x: float, _z: float) -> float:
		return NAN

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 25:
			printerr("VALLEY_LIFE_FAILED: " + message)

func transform_at(buffer: PackedFloat32Array, index: int) -> Transform3D:
	var offset := index * 16
	return Transform3D(Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
		Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
		Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])),
		Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11]))

func frozen(life: Node3D, message: String) -> void:
	var elapsed: float = life.elapsed
	var buffer: PackedFloat32Array = life._instances.multimesh.buffer.duplicate()
	life.advance(600)
	check(life.elapsed == elapsed and life._instances.multimesh.buffer == buffer, message)

func _run() -> void:
	var bounds := Rect2(-72, -96, 144, 192)
	var source := Surface.new()
	var reference := Surface.new()
	var life := Life.new()
	root.add_child(life)
	check(life.configure(source, bounds, 411), "Valid one-unit surface configures the bounded component")
	life.set_process(false)
	var state: Dictionary = life.debug_state()
	var node: MultiMeshInstance3D = life._instances
	var multi := node.multimesh
	var mesh_id := multi.mesh.get_instance_id()
	var material_id := node.material_override.get_instance_id()
	var surface_calls: int = source.calls
	check(state.count == 3 and state.draw_batches == 1 and state.triangles == 24, "Exactly three silhouettes / one batch /24 actual triangles")
	check(life.get_child_count() == 1 and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and node.gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "Single decorative node has no shadow or GI passes")
	check(life.get_meta("decorative_only") and node.get_meta("decorative_only") and not life.get_meta("affects_navigation"), "Explicit decoration metadata never represents animal AI")
	check(multi.instance_count == 3 and multi.use_custom_data and not multi.use_colors and multi.buffer.size() == 48, "Actual CPU-retained instance buffer has three stride16 transforms/custom values")
	check(surface_calls == state.sampling_calls and surface_calls > 2000 and surface_calls < 5000, "Full orbit rectangles are sampled once with bounded startup work")
	var material := node.material_override as ShaderMaterial
	var shader: String = material.shader.code
	check(not "ALPHA" in shader and not "TIME" in shader and "INSTANCE_CUSTOM.x" in shader and "unshaded" in shader, "Opaque shader has explicit paused wing phase, no native-time animation")
	var arrays := multi.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(vertices.size() == Life.TRIANGLES_PER_BIRD * 3, "Rendered mesh agrees with advertised triangle budget")
	for bird: Dictionary in state.birds:
		var sampled_maximum := -INF
		for x in range(floori(bird.center.x - bird.radius.x - 1), ceili(bird.center.x + bird.radius.x + 1) + 1):
			for z in range(floori(bird.center.y - bird.radius.y - 1), ceili(bird.center.y + bird.radius.y + 1) + 1):
				sampled_maximum = maxf(sampled_maximum, reference.node_height(x, z))
		check(sampled_maximum == bird.maximum_ground and bird.height >= sampled_maximum + 14, "Entire flight rectangle clears actual triangle vertex maximum, not sparse path samples")
		for step in 720:
			var theta := TAU * step / 720.0
			var point := Vector2(bird.center.x + cos(theta) * bird.radius.x, bird.center.y + sin(theta) * bird.radius.y)
			check(bounds.has_point(point) and bird.height - 0.35 - reference.surface_height(point.x, point.y) > 13.6, "Complete flight stays inside scenic bounds and well above sampled terrain")
	var still_wings := 0
	var flexing_wings := 0
	for frame in 2400:
		var old: PackedFloat32Array = multi.buffer.duplicate()
		life.advance(0.1)
		var buffer: PackedFloat32Array = multi.buffer
		for i in 3:
			var transform := transform_at(buffer, i)
			var speed := transform.origin.distance_to(transform_at(old, i).origin) / 0.1
			peak_speed = maxf(peak_speed, speed)
			check(transform.origin.is_finite() and speed < 1.2, "World-space gliding is slow, finite and continuous")
			check(absf(transform.basis.x.dot(transform.basis.y)) < 0.00001 and absf(transform.basis.y.dot(transform.basis.z)) < 0.00001, "Actual buffer contains an orthogonal scaled orientation")
			var flex := buffer[i * 16 + 12]
			check(absf(flex) <= Life.WING_FLEX, "Soft wing deformation remains bounded")
			still_wings += int(flex == 0)
			flexing_wings += int(flex != 0)
			for vertex in vertices:
				vertex.y += absf(vertex.x) * flex
				var world := transform * vertex
				check(multi.custom_aabb.has_point(world), "Actual shader-deformed vertex stays inside declared cull bounds")
				check(bounds.has_point(Vector2(world.x, world.z)) and world.y - reference.surface_height(world.x, world.z) > 13.0, "Entire banked/wing-flexed silhouette clears terrain within scenic envelope")
		check(source.calls == surface_calls and multi.mesh.get_instance_id() == mesh_id and node.material_override.get_instance_id() == material_id, "No per-frame terrain sampling or mesh/material rebuild")
	check(flexing_wings > 50 and still_wings > flexing_wings * 15, "Long still-wing glides dominate occasional brief flexes")
	var before: float = life.elapsed
	life.advance(1000)
	check(absf(life.elapsed - before - 0.1) < 0.000001 and life.debug_state().discarded_time > 999, "Large resumed delta discards missed time instead of catch-up motion")
	for cycle in 20:
		life.set_active(false)
		frozen(life, "Inactive component freezes actual transforms and wing phase")
		life.set_active(true)
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		frozen(life, "Paused/unfocused component freezes")
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		frozen(life, "Focus alone cannot bypass the application-pause gate")
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		frozen(life, "Resume alone cannot bypass missing focus")
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		life.hide()
		frozen(life, "Hidden component does not advance ambient motion")
		life.show()
		var previous: float = life.elapsed
		life.advance(0.02)
		check(life.elapsed > previous and source.calls == surface_calls, "Foreground resumes normally without source regeneration")
	for invalid_delta in [NAN, INF, -1.0, 0.0]:
		var previous: float = life.elapsed
		life.advance(invalid_delta)
		check(life.elapsed == previous, "Invalid frame intervals fail quietly")
	check(not life.configure(source, bounds, 412) and source.calls == surface_calls, "Repeated configure cannot regenerate an active component")
	var copy := Life.new()
	root.add_child(copy)
	check(copy.configure(Surface.new(), bounds, 411), "Same seeded setup is reproducible")
	check(copy.debug_state().birds == state.birds, "Bird orbits do not depend on frame order or global RNG")
	copy.queue_free()
	var invalid := Life.new()
	root.add_child(invalid)
	check(not invalid.configure(source, Rect2(0, 0, 50000, 50000)), "Unbounded configuration is rejected before loops")
	check(not invalid.configure(BadSurface.new(), bounds) and invalid.get_child_count() == 0, "Unavailable source fails without a partial render batch")
	invalid.queue_free()
	life.queue_free()
	await process_frame
	var meadow := Meadow.new()
	root.add_child(meadow)
	await process_frame
	meadow.set_process(false)
	check(meadow.valley_life == null, "Old landscapes do not acquire new decorative motion")
	meadow.set_landscape("alpine_valley")
	check(is_instance_valid(meadow.valley_life) and meadow.valley_life.get_parent() == meadow, "V7 owns exactly one separate decorative sibling")
	check(not meadow.terrain.is_ancestor_of(meadow.valley_life), "Birds never enter prepared terrain/picking/camera-clearance indexes")
	check(meadow.region_profile.lattice.is_empty(), "Real v7 life setup reads prepared mesh, never runtime FastNoise")
	var actual_life: Node3D = meadow.valley_life
	actual_life.set_process(false)
	for bird: Dictionary in actual_life.debug_state().birds:
		for i in 360:
			var theta := TAU * i / 360.0
			var x: float = bird.center.x + cos(theta) * bird.radius.x
			var z: float = bird.center.y + sin(theta) * bird.radius.y
			check(bird.height - 0.35 - meadow.surface_height(x, z) > 13.6, "Complete real prepared-terrain orbit keeps its clearance")
	for frame in 2400:
		actual_life.advance(0.1)
		var actual_buffer: PackedFloat32Array = actual_life._instances.multimesh.buffer
		for i in 3:
			var transform := transform_at(actual_buffer, i)
			for vertex in vertices:
				vertex.y += absf(vertex.x) * actual_buffer[i * 16 + 12]
				var world := transform * vertex
				check(world.y - meadow.surface_height(world.x, world.z) > 13.0, "Actual prepared ground stays below every animated bird vertex")
	check(meadow.region_profile.lattice.is_empty(), "Real runtime flight checks leave generation caches empty")
	meadow.set_landscape("alpine")
	check(meadow.valley_life == null and not actual_life.active, "Leaving v7 immediately deactivates and releases its life component")
	meadow.queue_free()
	await process_frame
	print("VALLEY_LIFE_SMOKE: %d checks / %d failures;3 birds,1 opaque batch,24 triangles,%d configure samples,peak glide%.3fm/s; no Android visibility/FPS claim" % [checks, failures, surface_calls, peak_speed])
	quit(1 if failures else 0)
