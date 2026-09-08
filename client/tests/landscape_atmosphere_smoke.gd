extends SceneTree
const Air = preload("res://scripts/landscape_atmosphere.gd")
const Studio = preload("res://tools/landscape_studio.gd")
var checks := 0
var failures := 0
var protected_vertices := 0
var protected_poses := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ATMOSPHERE_FAILED: " + message)

func _run() -> void:
	for biome in 2:
		Studio.recipe_index = biome
		var studio := load("res://tools/landscape_studio.tscn").instantiate() as Node3D
		root.add_child(studio)
		await process_frame
		var air: Node = studio.atmosphere
		air.set_process(false)
		studio.set_process(false)
		check(not air.screen.visible, "Original study allocates no visible screen pass")
		check(air.screen.get_parent() == studio.camera, "Screen is owned by the current camera")
		check(air.screen.mesh.get_surface_count() == 1 and air.screen.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 3, "One full-screen triangle")
		check(air.material.get_shader_parameter("desert_warmth") == float(biome), "Biome-specific horizon color")
		check(air.screen.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and air.screen.gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "No extra shadow caster or GI participant")
		var label := Label3D.new()
		check(air.material.render_priority == -128 and air.material.render_priority < label.render_priority, "Screen pass precedes ordinary transparent world labels, whose pixels are absent from opaque screen copy")
		var late := ShaderMaterial.new()
		late.render_priority = 127
		check(not (late.render_priority < label.render_priority), "Negative first-pass priority127 cannot satisfy the label-preservation ordering")
		label.free()
		air.set_effects(true, false)
		air.set_process(false)
		check(air.process_priority == 100 and air.process_priority > studio.process_priority, "Protection updates after ordinary studio animation and camera work")
		check(air.material.get_shader_parameter("actor_count") == 14 and air.material.get_shader_parameter("actor_rects") == air.rects, "Clouds-only activation installs current silhouettes immediately, before its first frame")
		_cloud_activation_clip(studio)
		air.advance(30.0)
		check(air.elapsed == 0, "First resumed frame does not catch up")
		air.advance(30.0)
		check(is_equal_approx(air.elapsed, 0.1), "Long frame is bounded")
		var before: float = air.elapsed
		for kind in [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
			air._notification(kind)
			air.advance(60)
			check(air.elapsed == before and not air.screen.visible, "Background/focus loss freezes and hides effect")
			air._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
			air._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			air.set_process(false)
			air.advance(60)
			check(air.elapsed == before, "No replay of missed cloud motion")
		air.set_effects(true, true)
		air.set_process(false)
		air.advance(0.1)
		check(air.material.get_shader_parameter("blur_enabled") == true, "Valid study actors permit optional far blur")
		check(air.material.get_shader_parameter("actor_count") == 14, "Every scale figure receives a protective rectangle")
		for rect: Vector4 in air.rects:
			check(is_finite(rect.x) and is_finite(rect.y) and rect.z > rect.x and rect.w > rect.y, "Protection uses nonempty finite projected geometry")
		var actor: Node3D = studio.figures[0]
		var original: Vector3 = actor.position
		actor.global_position = studio.camera.global_position + studio.camera.global_basis.z * 5
		air.advance(0.1)
		check(air.material.get_shader_parameter("blur_enabled") == true and air.material.get_shader_parameter("actor_count") == 13, "Wholly behind-camera actor cannot cover pixels or turn off the whole sky")
		actor.position = original
		air.advance(0.1)
		check(air.material.get_shader_parameter("blur_enabled") == true, "Valid visible actor restores only requested blur")
		await _projected_meshes(studio)
		_passthrough_lifecycle(air)
		air.set_active(false)
		before = air.elapsed
		air.advance(100)
		check(air.elapsed == before and not air.screen.visible, "Hidden/menu gate does not advance")
		var mesh: WeakRef = weakref(air.screen)
		var material: WeakRef = weakref(air.material)
		studio.queue_free()
		await process_frame
		await process_frame
		check(mesh.get_ref() == null and material.get_ref() == null, "World exit releases private screen and material")
	Studio.recipe_index = 0
	await _two_worlds()
	await _runtime_worlds()
	var source := FileAccess.get_file_as_string("res://shaders/landscape_atmosphere.gdshader")
	check(not source.contains("TIME") and source.contains("depth_draw_never"), "No global clock or depth mutation")
	check(source.contains("distance > 110.0") and source.contains("protected_pixel(sample_uv)") and source.contains("CURRENT_RENDERER == RENDERER_COMPATIBILITY"), "Far-only, silhouette-safe, renderer-specific depth reconstruction")
	check(_preserves_unaffected_samples(source), "Near and otherwise unaffected fragments discard before any screen color rewrite")
	check(not _preserves_unaffected_samples(source.replace("discard;", "")), "The old unconditional passthrough cannot satisfy MSAA-sample preservation")
	check(_protects_skyline(source), "Eight neighboring depth samples retain original MSAA coverage at non-actor skyline edges")
	check(not _protects_skyline(source.replace("textureLod(scene_depth, neighbor, 0.0).r", "0.0")), "Negative disabled neighbor depth cannot satisfy skyline protection")
	check(not _preserves_unaffected_samples(source.replace("if (protected_pixel(uv)) { discard; }", "")), "Blur-only guards cannot protect partially covered actor/sky pixels from the cloud branch")
	print("LANDSCAPE_ATMOSPHERE: %d checks/%d failures; %d actual protected vertices at%d posed views, both portrait aspects; two-world resources/clocks; GPU color/depth/compositing appearance remains separate" % [checks, failures, protected_vertices, protected_poses])
	quit(1 if failures else 0)

func _projected_meshes(studio: Node3D) -> void:
	var air: Node = studio.atmosphere
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = size
		await process_frame
		root.size = size
		await process_frame
		check(root.size == size and studio.camera.get_viewport().get_visible_rect().size == Vector2(size), "Actual physical/logical portrait matches protected-pixel coordinate space")
		for view in studio.profile.route.size():
			studio.current_view = view
			for pose in 3:
				studio._show_view()
				for index in studio.figures.size():
					var actor: Node3D = studio.figures[index]
					var phase: float = index * 0.71 + pose * 1.3
					actor.position += Vector3(sin(phase) * 0.18, 0, cos(phase) * 0.14)
					actor.rotation.y = phase
					var body := actor.get_node("Body") as Node3D
					body.scale.y = 1.0 + sin(phase) * 0.025
					body.rotation.z = cos(phase) * 0.035
					for part_name in ["Head", "Tail"]:
						var part := actor.find_child(part_name, true, false) as Node3D
						if part != null:
							part.rotation.x = sin(phase) * 0.18
				air.advance(0.1)
				check(air.material.get_shader_parameter("blur_enabled") == true and air.material.get_shader_parameter("actor_count") == 14, "Every authored viewpoint keeps all fourteen figures protected without needing fail-closed blur")
				check(air.material.get_shader_parameter("actor_rects") == air.rects, "Shader receives the current frame's complete guard array")
				for index in studio.figures.size():
					var actor: Node3D = studio.figures[index]
					var rect: Vector4 = air.rects[index]
					for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
						if not node.is_visible_in_tree() or node.mesh == null:
							continue
						for surface in node.mesh.get_surface_count():
							var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
							for vertex: Vector3 in vertices:
								var world: Vector3 = node.global_transform * vertex
								check(not studio.camera.is_position_behind(world), "Reference meshes remain in front of this studio camera")
								var pixel: Vector2 = studio.camera.unproject_position(world)
								# Independently project real vertices rather than reusing the
								# production AABB-corner algorithm. Four pixels exceeds the
								# two-pixel kernel plus filtered silhouette/AA allowance.
								check(_inside(rect, pixel / Vector2(size)), "Actual posed mesh vertex lies inside its shader protection rectangle")
								check(pixel.x - rect.x * size.x >= 3.98 and pixel.y - rect.y * size.y >= 3.98 and rect.z * size.x - pixel.x >= 3.98 and rect.w * size.y - pixel.y >= 3.98, "Every actual silhouette retains at least the four-pixel safety expansion within float32 projection tolerance")
								protected_vertices += 1
				protected_poses += 1
	# Negative control: merely providing14 nonempty rectangles is insufficient.
	var actor: Node3D = studio.figures[0]
	var center: Vector2 = studio.camera.unproject_position(actor.global_position + Vector3.UP * 0.7) / Vector2(root.size)
	check(not _inside(Vector4(-2, -2, -1, -1), center), "Empty sentinel rectangle cannot falsely protect an actual figure")

func _inside(rect: Vector4, point: Vector2) -> bool:
	return point.x >= rect.x and point.y >= rect.y and point.x <= rect.z and point.y <= rect.w

func _preserves_unaffected_samples(source: String) -> bool:
	var compact := source.replace(" ", "").replace("\t", "").replace("\n", "")
	var guard := "if(!(clouds_enabled&&sky_pixel)&&!soft_pixel){discard;}"
	var actors := "if(protected_pixel(uv)){discard;}"
	var expected_soft := "boolsoft_pixel=blur_enabled&&distance>110.0;"
	return compact.contains(expected_soft) and compact.find(guard) >= 0 and compact.find(guard) < compact.find("textureLod(screen_color,") and compact.find(guard) < compact.find("ALBEDO=") and compact.find(actors) >= 0 and compact.find(actors) < compact.find("boolsky_pixel=")

func _protects_skyline(source: String) -> bool:
	var compact := source.replace(" ", "").replace("\t", "").replace("\n", "")
	var guard := "if(textureLod(scene_depth,neighbor,0.0).r>=0.0000001){discard;}"
	return compact.contains("pixel=1.5/VIEWPORT_SIZE") and compact.contains("for(inty=-1;y<=1;y++)") and compact.contains("for(intx=-1;x<=1;x++)") and compact.contains("if(x==0&&y==0){continue;}") and compact.find(guard) >= 0 and compact.find(guard) < compact.find("textureLod(screen_color,")

func _runtime_worlds() -> void:
	var meadow := load("res://scripts/meadow.gd").new() as Node3D
	root.add_child(meadow)
	await process_frame
	var old_environment: Environment = meadow.world_environment
	var old_sky: Sky = old_environment.sky
	var old_camera: int = meadow.camera.projection
	for region in ["alpine_valley", "dry_wash", "alpine_valley"]:
		meadow.set_landscape(region)
		await process_frame
		var air: Node = meadow.atmosphere
		check(is_instance_valid(air) and air.clouds and not air.blur, "Large regions own a cloud pass with optional blur initially off")
		check(air.actors.size() == 12, "Preview sheep and dogs are protected at creation")
		var actor: Node3D = meadow.make_actor("dog", "guard-fixture", false)
		actor.position = meadow.preview.get_child(10).position
		var guards: Array[Node3D] = [actor]
		meadow.preview.hide()
		meadow.protect_actors(guards)
		check(air.actors == guards and air.actor_meshes.size() == 1, "Authoritative actors replace cached preview meshes")
		meadow.set_soft_distance(true)
		check(air.blur and air.material.get_shader_parameter("blur_enabled"), "Menu preference immediately applies distance softening")
		var too_many: Array[Node3D] = []
		too_many.resize(15)
		too_many.fill(actor)
		check(not air.set_protected_actors(too_many) and not air.material.get_shader_parameter("clouds_enabled") and not air.material.get_shader_parameter("blur_enabled"), "Oversize guard list fails closed before rendering")
		check(air.set_protected_actors(guards) and air.material.get_shader_parameter("clouds_enabled"), "Valid replacement safely restores requested sky")
		meadow.set_soft_distance(false)
		var screen: WeakRef = weakref(air.screen)
		actor.queue_free()
		meadow.set_landscape("juniper")
		await process_frame
		await process_frame
		check(meadow.atmosphere == null and screen.get_ref() == null, "Leaving a large region releases its camera screen")
		check(meadow.camera.projection == old_camera and meadow.world_environment.sky == old_sky, "Legacy camera and sky remain unchanged")
		meadow.preview.show()
	meadow.queue_free()
	await process_frame

func _cloud_activation_clip(studio: Node3D) -> void:
	var air: Node = studio.atmosphere
	var actor: Node3D = studio.figures[0]
	var saved := actor.global_transform
	actor.global_position = studio.camera.global_position - studio.camera.global_basis.z * studio.camera.near * 0.5
	air.set_effects(true, false)
	air.set_process(false)
	check(air.material.get_shader_parameter("clouds_enabled") == false and air.material.get_shader_parameter("blur_enabled") == false, "Actual actor crossing the near/camera plane disables both branches even with clouds-only requested")
	actor.global_transform = saved
	air.advance(0.0)
	check(air.material.get_shader_parameter("clouds_enabled") == true and air.material.get_shader_parameter("blur_enabled") == false, "Recovered geometry restores only requested clouds, never unrequested blur")
	check(air.material.get_shader_parameter("actor_count") == 14 and air.material.get_shader_parameter("actor_rects") == air.rects, "Recovered clouds refresh all projected guards without waiting for clock advancement")

func _passthrough_lifecycle(air: Node) -> void:
	var before: float = air.elapsed
	for cycle in 20:
		air.set_effects(false, false, true)
		check(air.screen.visible and not air.is_processing() and air.passthrough, "Explicit zero-effect pass is visible without a running cloud clock")
		air._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		air._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		air.advance(100)
		check(not air.screen.visible and air.elapsed == before, "Zero-effect pass hides and freezes on focus/background")
		air._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		check(not air.screen.visible, "Focus alone cannot reopen a still-paused comparison")
		air._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		air.advance(100)
		check(air.screen.visible and not air.is_processing() and air.elapsed == before, "Resumed passthrough restores its requested visible state without catch-up")
		air.set_active(false)
		check(not air.screen.visible, "Passthrough also obeys the explicit visibility/menu gate")
		air.set_active(true)
		check(air.screen.visible and air.elapsed == before, "Reopening restores only the zero-effect pass")
		air.set_effects(false, false)
		check(not air.screen.visible and not air.is_processing(), "Returning to Original removes the study pass")

func _isolated_world(size: Vector2i, offset: Vector3) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = offset + Vector3(2, 4, 10)
	camera.look_at(offset + Vector3.UP)
	var actor := Node3D.new()
	viewport.add_child(actor)
	actor.position = offset
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.position.y = 0.5
	actor.add_child(body)
	var air := Air.new()
	viewport.add_child(air)
	var figures: Array[Node3D] = [actor]
	check(air.configure(camera, figures), "Independent atmosphere configures against its own viewport/camera/actor")
	air.set_effects(true, true)
	air.set_process(false)
	air.advance(0.1)
	return {"viewport": viewport, "camera": camera, "actor": actor, "air": air}

func _two_worlds() -> void:
	var first := _isolated_world(Vector2i(720, 1280), Vector3.ZERO)
	var second := _isolated_world(Vector2i(720, 1600), Vector3(30, 5, -12))
	var a: Node = first.air
	var b: Node = second.air
	check(a.material != b.material and a.screen.mesh != b.screen.mesh and a.screen != b.screen, "Both worlds own independent material/mesh/screen state")
	check(a.material.shader == b.material.shader, "Immutable shader source may be shared without sharing uniforms")
	var second_rects: PackedVector4Array = b.rects.duplicate()
	first.actor.position += Vector3(2, 0, 0)
	a.advance(0.08)
	check(is_equal_approx(a.elapsed, 0.08) and b.elapsed == 0.0, "One world's clock cannot advance another")
	check(b.rects == second_rects and b.material.get_shader_parameter("actor_rects") == second_rects, "One moving actor cannot rewrite another viewport's guard uniforms")
	a._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	b.advance(0.03)
	check(not a.screen.visible and b.screen.visible and is_equal_approx(b.elapsed, 0.03), "One helper's focus gate does not disable another helper")
	var private_screen: WeakRef = weakref(a.screen)
	var private_material: WeakRef = weakref(a.material)
	first.viewport.queue_free()
	await process_frame
	await process_frame
	check(private_screen.get_ref() == null and private_material.get_ref() == null, "World removal releases its private screen/material even though camera owns the mesh node")
	check(is_instance_valid(b.screen) and b.screen.visible and b.rects == second_rects, "Other world survives first-world exit unchanged")
	second.viewport.queue_free()
	await process_frame
	await process_frame
