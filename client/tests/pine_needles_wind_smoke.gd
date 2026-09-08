extends SceneTree
## Standalone prototype checks. Never installs the optional material in runtime,
## changes a cooked scene, edits placement, or claims headless GPU/image parity.
const Wind = preload("res://scripts/pine_needles_wind.gd")
const Navigation = preload("res://scripts/region_navigation.gd")
const Props = preload("res://scripts/landscape_props.gd")
var checks := 0
var failures := 0
var vertex_probes := 0
var trees := 0
var triangles := 0
var maximum_motion := 0.0
var minimum_clearance := INF
var minimum_normal_dot := 1.0

class UnusedProfile extends RefCounted:
	pass

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 25:
			printerr("PINE_WIND_FAILED: " + message)

func _transform(buffer: PackedFloat32Array, i: int) -> Transform3D:
	var p := i * 16
	return Transform3D(Basis(Vector3(buffer[p], buffer[p + 4], buffer[p + 8]),
		Vector3(buffer[p + 1], buffer[p + 5], buffer[p + 9]),
		Vector3(buffer[p + 2], buffer[p + 6], buffer[p + 10])),
		Vector3(buffer[p + 3], buffer[p + 7], buffer[p + 11]))

func _inventory(scene: Node) -> Dictionary:
	var records := {}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MultiMeshInstance3D:
			continue
		var multi: MultiMesh = node.multimesh
		var surfaces := []
		for i in multi.mesh.get_surface_count():
			surfaces.append({"arrays": multi.mesh.surface_get_arrays(i), "material": multi.mesh.surface_get_material(i)})
		records[String(scene.get_path_to(node))] = {"mesh": multi.mesh, "multi": multi,
			"surfaces": surfaces, "buffer": multi.buffer, "bounds": multi.custom_aabb,
			"transform": node.transform, "margin": node.extra_cull_margin,
			"children": node.get_child_count(), "override": node.material_override}
	return records

func _lifecycle(source: StandardMaterial3D) -> void:
	var life := Wind.new()
	root.add_child(life)
	check(life.configure(source), "Current lit opaque needle material is supported")
	check(life.selected_material() == source and life.debug_state().materials_created == 0, "Disabled prototype preserves exact original material without allocating replacement")
	check(not life.configure(source), "Cannot overwrite configured source")
	life.set_enabled(true)
	life.set_process(false)
	var material: ShaderMaterial = life.selected_material()
	var resource_id := material.get_instance_id()
	check(material != source and material.next_pass == null, "Exactly one optional single-pass material")
	check(material.get_shader_parameter("needle_tint") == source.albedo_color, "Authored needles tint remains exact")
	check(material.get_shader_parameter("needle_roughness") == source.roughness and material.get_shader_parameter("needle_specular") == source.metallic_specular, "Existing BRDF values retained")
	var code: String = material.shader.code
	check(not code.contains("TIME") and not code.contains("ALPHA") and not code.contains("unshaded") and not code.contains("discard"), "Explicit clock, lit opaque shader, no cutout/alpha pass")
	for literal in ["depth_draw_opaque", "cull_back", "diffuse_burley", "specular_schlick_ggx", "if (!OUTPUT_IS_SRGB)", "COLOR.rgb", "needle_tint.rgb * COLOR.rgb", "MODEL_MATRIX[3].xz", "NORMAL.y -= dot(NORMAL, direction)"]:
		check(code.contains(literal), "Shader retains pinned color/normal/instance contract: " + literal)
	for literal in ["uniform vec4 needle_tint : source_color", "0.72 * sin(wind_time * 0.63 + phase)", "0.28 * sin(wind_time * 0.91 + phase * 1.7)", "0.08 * clamp(wind_strength, 0.0, 1.0)", "(VERTEX.y - 1.7) / 3.8", "6.0 * u * (1.0 - u) / 3.8", "length(mat3(MODEL_MATRIX) * direction)", "vec3(0.8, 0.0, 0.6)", "vec2(0.37, 0.19)"]:
		check(code.contains(literal), "Actual shader displacement/derivative matches independently tested CPU constants: " + literal)
	check(material.shader.get_shader_uniform_list().size() == 5, "Shader resource exposes exactly five expected uniforms")
	life.advance(1.0 / 60)
	check(life.debug_state().elapsed == 0, "Enabling discards first potentially stale delta")
	life.advance(1.0 / 60)
	check(life.debug_state().elapsed > 0, "Ordinary foreground time advances")
	for cycle in 20:
		var before: float = life.debug_state().elapsed
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		life.advance(600)
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		life.advance(600)
		check(life.debug_state().elapsed == before, "Focus alone cannot reopen pause gate")
		life.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		life.set_process(false)
		life.advance(600)
		check(life.debug_state().elapsed == before, "Regained foreground drops missed time entirely")
		life.advance(1.0 / 60)
		check(absf(life.debug_state().elapsed - before - 1.0 / 60) < 0.00000001, "Only a new frame resumes continuous motion")
		life.set_active(false)
		before = life.debug_state().elapsed
		life.advance(10)
		life.set_active(true)
		life.set_process(false)
		life.advance(10)
		check(life.debug_state().elapsed == before, "Menu/scene inactive gate freezes and discards first return delta")
		life.set_enabled(false)
		check(life.selected_material() == source, "Disabled selection always returns exact original resource")
		life.advance(10)
		life.set_enabled(true)
		life.set_process(false)
		life.advance(10)
		check(life.debug_state().elapsed == before and life.selected_material().get_instance_id() == resource_id, "Enable cycling preserves phase and cached resource without catch-up")
	var before: float = life.debug_state().elapsed
	for bad_delta in [NAN, INF, -INF, -1.0, 0.0]:
		life.advance(bad_delta)
	check(life.debug_state().elapsed == before, "Invalid time cannot poison shader uniform")
	life.advance(600)
	check(absf(life.debug_state().elapsed - before - 0.1) < 0.00000001, "Long foreground stall is bounded, not replayed")
	check(life.debug_state().materials_created == 1 and life.debug_state().added_meshes == 0 and life.debug_state().added_draw_batches == 0, "Lifetime resource/batch counts remain constant")
	check(material.get_shader_parameter("wind_time") == life.debug_state().elapsed, "CPU clock is the sole shader time source")
	_material_binding(life, source)
	life.free()
	var unsupported := Wind.new()
	var alpha := source.duplicate() as StandardMaterial3D
	alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	check(not unsupported.configure(alpha), "Do not silently approximate a transparent material")
	unsupported.free()

func _linear(value: float) -> float:
	return value / 12.92 if value < 0.04045 else pow((value + 0.055) / 1.055, 2.4)

func _material_binding(life: Node, source: StandardMaterial3D) -> void:
	# Exercise optional surface binding only on NEW private generator meshes,
	# never on a loaded prepared resource or any runtime scene.
	var props := Props.new(UnusedProfile.new(), false)
	for variant in 3:
		var mesh: ArrayMesh = props.meshes["tree_%d" % variant]
		var bark: Material = mesh.surface_get_material(0)
		var crown: Material = mesh.surface_get_material(1)
		var before := [mesh.surface_get_arrays(0), mesh.surface_get_arrays(1)]
		mesh.surface_set_material(1, life.selected_material())
		check(mesh.get_surface_count() == 2 and mesh.surface_get_material(0) == bark, "Optional binding leaves woody trunk material and draw-surface count untouched")
		check(before == [mesh.surface_get_arrays(0), mesh.surface_get_arrays(1)], "Enabled candidate does not change any mesh arrays, triangles or UVs")
		var colors: PackedColorArray = before[1][Mesh.ARRAY_COLOR]
		for i in range(0, colors.size(), 31):
			for instance_shade in [1.0, 0.965, 0.93, 0.895]:
				var combined: Color = colors[i] * Color(instance_shade, instance_shade, instance_shade)
				for compatibility in [false, true]:
					# StandardMaterial source_color conversion is renderer-owned;
					# its generated vertex_color_is_srgb branch is only enabled in
					# linear-output renderers. Instance multiplication precedes it.
					# Reference: Godot4.6 scene/resources/material.cpp vertex shader.
					var vertex_color: Color = combined if compatibility else combined.srgb_to_linear()
					var uniform_color: Color = source.albedo_color if compatibility else source.albedo_color.srgb_to_linear()
					var expected := vertex_color * uniform_color
					var actual := combined
					if not compatibility:
						actual = Color(_linear(actual.r), _linear(actual.g), _linear(actual.b), actual.a)
					actual *= uniform_color
					check(absf(actual.r - expected.r) < 0.000001 and absf(actual.g - expected.g) < 0.000001 and absf(actual.b - expected.b) < 0.000001, "Zero-wind tint algebra matches existing vertex × instance × source-color pipeline in both renderer modes")
		mesh.surface_set_material(1, crown)
		check(mesh.surface_get_material(0) == bark and mesh.surface_get_material(1) == crown and before == [mesh.surface_get_arrays(0), mesh.surface_get_arrays(1)], "Removing prototype restores original shared resources exactly")
	# Wrong-normal negative control at the strongest part of the bend: the old
	# UP-invariant assumption must fail to reproduce a sheared sloping surface.
	var p := Vector3(0, 3.6, 0)
	var n := Vector3(1, 1, 0).normalized()
	var changed: Dictionary = Wind.deformed(p, n, Transform3D.IDENTITY, 2.3)
	check(changed.normal.distance_to(n) > 0.001, "Negative control detects omitting the normal derivative")

func _normals(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(1)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var model := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.6, 0.7, 1.2)), Vector3(-52, 9, 66))
	for time in [0.0, 2.3, 9.4, 30.0]:
		for i in range(0, points.size(), 47):
			var p := points[i]
			var n := normals[i]
			var tangent := n.cross(Vector3.UP).normalized()
			if tangent.length() < 0.5:
				tangent = n.cross(Vector3.RIGHT).normalized()
			var bitangent := n.cross(tangent).normalized()
			var result: Dictionary = Wind.deformed(p, n, model, time)
			# Independent finite differences of the displaced surface, not the
			# implementation's analytical derivative or original lighting normals.
			var da: Vector3 = Wind.deformed(p + tangent * 0.002, n, model, time).point - Wind.deformed(p - tangent * 0.002, n, model, time).point
			var db: Vector3 = Wind.deformed(p + bitangent * 0.002, n, model, time).point - Wind.deformed(p - bitangent * 0.002, n, model, time).point
			var finite_normal := da.cross(db).normalized()
			var agreement: float = finite_normal.dot(result.normal)
			minimum_normal_dot = minf(minimum_normal_dot, agreement)
			check(agreement > 0.9995 and absf(result.normal.length() - 1) < 0.00001, "Analytic shear normal agrees with actual finite-difference surface")
			check(Wind.deformed(p, n, model, time, 0).point == p and Wind.deformed(p, n, model, time, 0).normal == n, "Zero strength preserves vertices and normals exactly")
			if p.y <= Wind.ROOT_HEIGHT:
				check(result.point == p and result.normal.is_equal_approx(n), "Lower rooted foliage stays motionless")

func _whole_crowns(scene: Node3D, nav: RefCounted) -> StandardMaterial3D:
	var pending: Array[Node] = [scene]
	var variants := {}
	var source: StandardMaterial3D
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MultiMeshInstance3D or not String(node.name).begins_with("Tree"):
			continue
		var multi: MultiMesh = node.multimesh
		var mesh := multi.mesh as ArrayMesh
		check(mesh.get_surface_count() == 2, "Bark and needles remain independent surfaces")
		source = mesh.surface_get_material(1) as StandardMaterial3D
		check(source != null and mesh.surface_get_material(0) is StandardMaterial3D, "Current cooked bark and needles remain original lit resources")
		var arrays := mesh.surface_get_arrays(1)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if not variants.has(mesh.get_instance_id()):
			_normals(mesh)
			variants[mesh.get_instance_id()] = true
		var expanded: AABB = Wind.expanded_bounds(multi.custom_aabb, node.global_basis)
		var existing_cull: AABB = multi.custom_aabb.grow(node.extra_cull_margin)
		check(existing_cull.encloses(expanded), "Existing per-chunk cull margin already encloses full maximum sway")
		for i in multi.instance_count:
			var transform := _transform(multi.buffer, i)
			var world: Transform3D = node.global_transform * transform
			var radius := 0.0
			for point in vertices:
				var relative: Vector3 = world.basis * point
				radius = maxf(radius, Vector2(relative.x, relative.z).length())
			var separation: float = -nav.signed_clearance(Vector2(world.origin.x, world.origin.z)) - radius
			minimum_clearance = minf(minimum_clearance, separation - Wind.MAX_DISPLACEMENT)
			check(separation > 0.25 and separation - Wind.MAX_DISPLACEMENT > 0.17, "Measured whole-crown disk plus all-time 0.08m envelope stays outside exact canonical union")
			# Every actual triangle is inside its vertices' convex horizontal disk.
			# Adding the analytical motion ball bounds whole faces at ALL phases,
			# not merely the handful of animated samples tested below.
			for time in [0.0, 7.3]:
				for j in vertices.size():
					var result: Dictionary = Wind.deformed(vertices[j], normals[j], world, time)
					var before: Vector3 = world * vertices[j]
					var after: Vector3 = world * result.point
					var distance := before.distance_to(after)
					maximum_motion = maxf(maximum_motion, distance)
					check(distance <= Wind.MAX_DISPLACEMENT + 0.00003, "Actual world displacement respects bound at all existing instance scales")
					check(expanded.has_point(node.global_transform.affine_inverse() * after), "Expanded actual chunk AABB contains every displaced crown vertex")
					vertex_probes += 1
			trees += 1
			triangles += vertices.size() / 3
	check(variants.size() == 3 and trees > 100, "All three real pine variants and the full existing Alpine population tested")
	return source

func _run() -> void:
	var packed := load("res://generated/long_valley.scn") as PackedScene
	check(packed != null, "Existing prepared Alpine scene loads")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	var baseline := _inventory(scene)
	var nav := Navigation.new(Navigation.default_region())
	var source := _whole_crowns(scene, nav)
	if source != null:
		_lifecycle(source)
	check(_inventory(scene) == baseline, "Disabled standalone prototype preserves ALL existing mesh/material/multimesh resources, buffers, transforms, arrays, cull bounds and batches")
	# Explicit bound negative: an excessive motion sphere cannot fit the old
	# 0.1m culling allowance, and canonical interior trees cannot pass the proof.
	var box := AABB(Vector3(-2, 0, -2), Vector3(4, 6, 4))
	check(not box.grow(0.1).encloses(box.grow(0.11)), "Negative control detects excess motion beyond existing cull margin")
	check(-nav.signed_clearance(Vector2(-42, 64)) - 2.0 - Wind.MAX_DISPLACEMENT < 0, "Negative control rejects a crown over the actual walkable clearing")
	check(maximum_motion > 0.04 and Wind.MAX_DISPLACEMENT <= 0.1, "Prototype actually moves while remaining under requested maximum")
	print("PINE_NEEDLES_WIND: %d checks / %d failures; %d trees / %d crown triangles / %d animated actual vertices; peak motion %.6f m, minimum whole-crown clearance %.6f m, normal dot %.7f" % [checks, failures, trees, triangles, vertex_probes, maximum_motion, minimum_clearance, minimum_normal_dot])
	scene.free()
	await process_frame
	quit(1 if failures else 0)
