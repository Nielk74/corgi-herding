extends SceneTree
## Real geometry, portrait picking and framing, separate from navigation fixtures.

const Navigation = preload("res://scripts/commons_navigation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("BELLFLOWER_VISUAL_FAILED: " + message)

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.preview_mode = true
	game.network.persist_config = false
	game.network.set_process(false)
	var started := Time.get_ticks_msec()
	game._select_landscape("bellflower")
	game._show_preview()
	game.set_process(false)
	game.meadow.set_process(false)
	await process_frame
	var build_ms := Time.get_ticks_msec() - started
	var meadow = game.meadow
	_check(game.selected_landscape == "bellflower" and game.world_layout == Navigation.layout(), "Canonical v6 layout did not reach scene")
	_check(meadow.gate == null and meadow.bridge == null and meadow.water == null, "Common inherited a gate, bridge or water")
	_check(game.moment_label.text == "" and not game.command_panel.visible, "Common must not introduce completion or permanent controls")
	_check(game.actors.size() == 14, "Preview must retain two herders, two dogs and ten sheep")
	for actor in game.actors.values():
		var point: Vector3 = actor.node.position
		_check(Navigation.contains(Vector2(point.x, point.z)), "Actor spawn lies outside the common")
		_check(absf(point.y - meadow.surface_height(point.x, point.z) - 0.03) < 0.001, "Actor feet differ from sampled mesh")
	var queue: Array[Node] = [game]
	var nodes := 0
	var meshes := 0
	var triangles := 0
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		nodes += 1
		queue.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			meshes += 1
			triangles += node.mesh.get_faces().size() / 3
	_check(triangles <= 100000 and nodes <= 1400 and meshes <= 1000, "Full scene exceeds existing mobile geometry budget")
	var ground := meadow.terrain.get_node("ValleyGroundBellflower") as MeshInstance3D
	var ground_faces := ground.mesh.get_faces()
	var low := INF
	var high := -INF
	var vertices := 0
	for p in ground_faces:
		_check(p.is_finite(), "Nonfinite ground vertex")
		if Navigation.contains(Vector2(p.x, p.z)):
			_check(absf(p.y - meadow.surface_height(p.x, p.z)) <= 0.002, "Actual walking triangle and sampled surface disagree")
			low = minf(low, p.y)
			high = maxf(high, p.y)
			vertices += 1
	_check(vertices >= 2500 and high - low >= 1.4, "Common needs actual checked playable relief")
	_check(meadow.surface_height(10, -6) - meadow.surface_height(10, 6) >= 0.8, "Sunny shoulder should visibly rise above sheltered hollow")
	var occluders: Array[Dictionary] = []
	for instance in meadow.terrain.find_children("*", "MeshInstance3D", true, false):
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		var transform: Transform3D = instance.global_transform
		var faces: PackedVector3Array = instance.mesh.get_faces()
		for i in faces.size():
			faces[i] = transform * faces[i]
		occluders.append({"name": instance.name, "faces": faces, "aabb": transform * instance.get_aabb()})
	var probes := 0
	var picks := 0
	var rejected := 0
	var frame_rays := 0
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.size = size
		await process_frame
		_check(root.get_visible_rect().size == Vector2(size), "Checks must use actual portrait logical viewport")
		for pan in [-6.0, 0.0, 6.0]:
			meadow.camera_focus.x = pan
			meadow.desired_focus.x = pan
			for zoom in [0.8, 1.0, 1.18]:
				meadow.zoom = zoom
				meadow.fit_camera()
				meadow._process(0.0)
				for center in [Vector2(-10, -1), Vector2(-5, 0), Vector2(0, 0), Vector2(4, -4), Vector2(10, -6), Vector2(4, 4), Vector2(10, 6)]:
					for offset in [Vector2.ZERO, Vector2(-1.25, 0), Vector2(1.25, 0)]:
						var point: Vector2 = center + offset
						_check(Navigation.contains(point), "Animal probe fixture must be inside common")
						var foot := Vector3(point.x, meadow.surface_height(point.x, point.y), point.y)
						var animal := foot + Vector3.UP * 0.60
						var screen: Vector2 = meadow.camera.unproject_position(animal)
						if not Rect2(Vector2.ZERO, Vector2(size)).has_point(screen):
							continue
						var origin: Vector3 = meadow.camera.project_ray_origin(screen)
						var endpoint := animal.move_toward(origin, 0.06)
						var blocked := ""
						for occluder in occluders:
							if occluder.aabb.intersects_segment(origin, endpoint) != null and _hit(occluder.faces, origin, endpoint):
								blocked = String(occluder.name)
								break
						_check(blocked.is_empty(), "Animal hidden by %s at %s aspect%s pan%s zoom%s" % [blocked, point, size, pan, zoom])
						probes += 1
						var ground_screen: Vector2 = meadow.camera.unproject_position(foot)
						if Rect2(Vector2.ZERO, Vector2(size)).has_point(ground_screen):
							var hit: Vector3 = meadow.ground_at(ground_screen)
							_check(hit.is_finite() and hit.distance_to(foot) <= 0.06, "Portrait ground pick differs at %s pan%s zoom%s" % [point, pan, zoom])
							picks += 1
				for point in [Vector2(7, 0), Vector2(10, 0), Vector2(-14, 0), Vector2(0, -9), Vector2(0, 9)]:
					_check(not Navigation.contains(point), "Rejected tap fixture must be outside union")
					var outside := Vector3(point.x, meadow.surface_height(point.x, point.y), point.y)
					var screen: Vector2 = meadow.camera.unproject_position(outside)
					if Rect2(Vector2.ZERO, Vector2(size)).has_point(screen):
						_check(not meadow.ground_at(screen).is_finite(), "Nonwalkable fork/slope tap created shortcut")
						rejected += 1
				if pan != 0.0:
					for row in [0.88, 0.98]:
						for column in [0.02, 0.5, 0.98]:
							var screen := Vector2(size) * Vector2(column, row)
							var origin: Vector3 = meadow.camera.project_ray_origin(screen)
							_check(_hit(ground_faces, origin, origin + meadow.camera.project_ray_normal(screen) * meadow.camera.far), "Ground ends inside lower portrait frame")
							frame_rays += 1
	_check(probes >= 220 and picks >= 220 and rejected >= 35 and frame_rays == 72, "Insufficient portrait geometry coverage")
	await _menu(game)
	print("BELLFLOWER_VISUAL: %d checks, %d failures; %d dry vertices %.2f relief; %d visibility/%d picks/%d rejected/%d lower rays; %d tris/%d nodes/%d meshes; build%dms" % [checks, failures, vertices, high - low, probes, picks, rejected, frame_rays, triangles, nodes, meshes, build_ms])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _hit(faces: PackedVector3Array, origin: Vector3, endpoint: Vector3) -> bool:
	for i in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(origin, endpoint, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false

func _menu(game) -> void:
	root.content_scale_size = Vector2i(720, 1280)
	root.size = Vector2i(720, 1280)
	game._open_settings()
	game.resume_button.show()
	game.endpoint_input.show()
	await process_frame
	await process_frame
	var viewport := Rect2(Vector2.ZERO, Vector2(720, 1280))
	var card: Control = game.welcome.get_child(0).get_child(0)
	_check(viewport.encloses(card.get_global_rect()), "Eight choices, Return, expanded server and Sound must fit short portrait")
	for control in [game.juniper_button, game.bellflower_button, game.resume_button, game.endpoint_input, game.sound_button]:
		_check(control.is_visible_in_tree() and viewport.encloses(control.get_global_rect()), "Real menu control is clipped")
	_check(game.bellflower_button.position.y == game.juniper_button.position.y, "New choice must share fourth row without growing the menu")
	_check(game.bellflower_button.size.x >= 230 and game.bellflower_button.size.y >= 58, "Bellflower touch target too small")
