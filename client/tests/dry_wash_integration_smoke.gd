extends "res://tests/region_integration_smoke.gd"
## Reuse the recorder, presentation-route and reconnect harness; all snapshot
## identities, canonical geometry and full-route destinations below are v8.
const Catalog = preload("res://scripts/region_catalog.gd")

func _run() -> void:
	camp = Vector2(-44, 79)
	far = Vector2(32, -76)
	var before := [_digest("user://herd.cfg"), _digest("user://audio.cfg"), _digest("user://guide.cfg")]
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _frames()
	game.set_process(false)
	game.meadow.set_process(false)
	game.network.free()
	recorder = RecordingConnection.new()
	recorder.persist_config = false
	recorder.endpoint = "http://fixture.invalid"
	game.add_child(recorder)
	recorder.set_process(false)
	game.network = recorder
	recorder.snapshot_received.connect(game._on_snapshot)
	recorder.status_changed.connect(game._on_status)
	recorder.request_failed.connect(game._on_error)
	recorder.herd_joined.connect(game._on_herd_joined)
	game.soundscape.persist_preference = false
	game.soundscape.set_enabled(false)
	game.soundscape.set_process(false)
	game.preview_mode = false
	navigation = Region.new(Catalog.canonical("dry_wash"))
	_check(navigation.valid, "canonical region is valid")
	await _viewport(Vector2i(720, 1280))
	_start(_region_snapshot(camp, camp))
	_check(not recorder.update_required and game.selected_landscape == "dry_wash" and game.actors.size() == 14, "actual main accepts canonical JSON v8 and fourteen grounded actors")
	_check(game._walkable(camp) and game._walkable(far) and not game._walkable(Vector2(73, 97)), "v8 dispatch precedes old small-world bounds without removing new bounds")
	_check(game.meadow.region_presentation != null and game.meadow.gate == null and game.meadow.bridge == null, "prepared valley presentation has no phantom bridge/gate")
	await _invalid_region_snapshots()
	await _region_prediction()
	await _region_interpolation()
	await _region_reconnect()
	await _dry_picking()
	await _region_menu()
	await _cross_region_cache()
	await _startup_default()
	_capabilities()
	_check(recorder.socket == null and recorder.requests.is_empty(), "fixture opens no external connection")
	game.queue_free()
	await _frames()
	_check(before == [_digest("user://herd.cfg"), _digest("user://audio.cfg"), _digest("user://guide.cfg")], "real credentials, audio and guide preferences unchanged")
	print("DRY_WASH_INTEGRATION_SMOKE: %d checks, %d failures; canonical v8 raw routes, actual full dry wash prediction/mesh grounding, cached remote routes, lost-sequence reconnect, ten portrait choices" % [checks, failures])
	quit(1 if failures else 0)

func _region_snapshot(from: Vector2, destination: Vector2, sequence := 0, state := "idle") -> Dictionary:
	tick += 1
	var route: Array = []
	for anchor: Vector2 in navigation.plan(from, destination):
		route.append(_point(anchor))
	var sheep: Array = []
	for index in range(10):
		sheep.append({"id": "fixture-sheep-%d" % index, "position": _point(Vector2(-39.7 + index % 3, 66.4 + floorf(index / 3.0) * 1.05)), "state": "grazing"})
	return JSON.parse_string(JSON.stringify({"type": "snapshot", "code": "FIXTURE", "tick": tick, "landscape": "dry_wash", "layout": game._default_layout("dry_wash"), "gate_open": false, "settled": 0,
		"players": [{"id": LOCAL_A, "position": _point(from), "target": _point(destination), "seq": sequence, "route": route, "state": state, "connected": true},
			{"id": LOCAL_B, "position": _point(Vector2(-41, 79)), "target": _point(Vector2(-41, 79)), "seq": 0, "route": [], "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "position": _point(Vector2(-43, 76.8)), "target": _point(Vector2(-43, 76.8)), "state": "idle", "command": "stay", "caller": LOCAL_A},
			{"id": "maple", "position": _point(Vector2(-40, 76.8)), "target": _point(Vector2(-40, 76.8)), "state": "idle", "command": "stay", "caller": LOCAL_B}], "sheep": sheep}))

func _invalid_region_snapshots() -> void:
	var valid := _region_snapshot(camp, far, 7, "walking")
	_check(not valid.players[0].route.is_empty(), "negative route fixture genuinely requires anchors")
	var unsafe_final := Vector2.INF
	for anchor: Dictionary in navigation.region.anchors:
		var point := Vector2(anchor.x, anchor.y)
		if navigation.visible(camp, point) and not navigation.visible(point, far):
			unsafe_final = point
			break
	_check(unsafe_final.is_finite(), "unsafe-final fixture has a valid source leg but blocked last leg")
	var unsafe_source := _unsafe_queue("source")
	var unsafe_middle := _unsafe_queue("middle")
	_check(not unsafe_source.is_empty() and not unsafe_middle.is_empty(), "Recipe-specific source and middle fixtures use only canonical v8 anchors")
	var mutations := ["layout_missing", "layout_extra", "region_extra", "future_version", "wrong_known_version", "swapped_region", "version_string", "recipe", "bounds", "anchor", "corridor", "clearing", "point_string", "point_bool", "point_extra", "point_nan", "point_outside", "target_outside", "seq_fraction", "seq_bool", "tick_negative", "code", "missing_local", "duplicate_id", "disconnected_local", "missing_dog", "null_route", "string_route", "dict_route", "empty_occluded", "duplicate_route", "target_in_route", "noncanonical_route", "unsafe_source", "unsafe_middle", "unsafe_final", "overlong", "dog_route"]
	for mutation in mutations:
		_start(valid)
		var bad: Dictionary = valid.duplicate(true)
		match mutation:
			"layout_missing": bad.erase("layout")
			"layout_extra": bad.layout.hidden_obstacle = true
			"region_extra": bad.layout.region.spine = []
			"future_version": bad.layout.version = 9
			"wrong_known_version": bad.layout.version = 7
			"swapped_region": bad.layout.region = Catalog.canonical("alpine_valley")
			"version_string": bad.layout.version = "8"
			"recipe": bad.layout.region.recipe_id = "different_region"
			"bounds": bad.layout.region.bounds.max.y += 1
			"anchor": bad.layout.region.anchors[1].x += 0.01
			"corridor": bad.layout.region.corridors[0].half_width += 0.01
			"clearing": bad.layout.region.clearings[0].radius += 0.01
			"point_string": bad.players[0].position.x = "-44"
			"point_bool": bad.players[0].position.x = true
			"point_extra": bad.players[0].position.z = 1
			"point_nan": bad.players[0].position.x = NAN
			"point_outside": bad.players[0].position = _point(Vector2(500, 500))
			"target_outside": bad.players[0].target = _point(Vector2(500, 500))
			"seq_fraction": bad.players[0].seq = 7.5
			"seq_bool": bad.players[0].seq = true
			"tick_negative": bad.tick = -1
			"code": bad.code = "OTHER"
			"missing_local": bad.players.pop_front()
			"duplicate_id": bad.dogs[0].id = LOCAL_A
			"disconnected_local": bad.players[0].connected = false
			"missing_dog": bad.dogs.pop_back()
			"null_route": bad.players[0].route = null
			"string_route": bad.players[0].route = "[]"
			"dict_route": bad.players[0].route = {}
			"empty_occluded": bad.players[0].route = []
			"duplicate_route": bad.players[0].route.append(bad.players[0].route[0].duplicate())
			"target_in_route": bad.players[0].route.append(_point(far))
			"noncanonical_route": bad.players[0].route[0].x += 0.01
			"unsafe_source": bad.players[0].route = unsafe_source
			"unsafe_middle": bad.players[0].route = unsafe_middle
			"overlong":
				bad.players[0].route = []
				for i in 15: bad.players[0].route.append(navigation.region.anchors[i % 14].duplicate())
			"unsafe_final": bad.players[0].route = [_point(unsafe_final)]
			"dog_route": bad.dogs[0].route = null
		var active_navigation: RefCounted = game.region_navigation
		var ids := _actor_instances()
		var saved: Dictionary = recorder.credentials.duplicate(true)
		recorder.snapshot_received.emit(bad)
		_check(recorder.update_required and recorder.paused and recorder.credentials == saved, mutation + " fails closed without erasing invitation")
		_check(game.latest == valid and game.world_layout == game._default_layout("dry_wash") and _actor_instances() == ids and game.region_navigation == active_navigation, mutation + " cannot partially mutate accepted actors/layout/snapshot")
		await _frames()
	# Empty/omitted queues are legal for a direct walking leg, never a reason to
	# fabricate a detour. Malformed raw queues stay invalid even for that leg.
	for omit in [false, true]:
		var direct := _region_snapshot(camp, Vector2(-42, 64), 8, "walking")
		if omit:
			direct.players[0].erase("route")
		_start(direct)
		_check(not recorder.update_required and game.moving and game.movement_route.is_empty(), "direct walking accepts empty or omitted raw queue")
		for malformed in [null, {}, "[]", [0]]:
			_start(direct)
			var bad: Dictionary = direct.duplicate(true)
			bad.players[0].route = malformed
			recorder.snapshot_received.emit(bad)
			_check(recorder.update_required and game.latest == direct, "direct endpoint visibility cannot mask malformed raw queue")
		await _frames()

func _region_prediction() -> void:
	for pair in [[camp, far], [far, camp], [Vector2(-51, -57), Vector2(47, -5)], [Vector2(47, -5), Vector2(-51, -57)], [camp, Vector2(-51, 40)], [Vector2(-51, 40), camp]]:
		var retained := _region_snapshot(pair[0], pair[1], 12, "walking")
		_start(retained)
		_check(game.movement_seq == 12 and game.movement_route == navigation.decode_route(retained.players[0].route), "accepted snapshot restores exact canonical anchor queue")
		var previous := _local_point()
		for frame in range(2200):
			game._process(0.05)
			var point := _local_point()
			var position: Vector3 = game.actors[LOCAL_A].node.position
			_check(navigation.contains(point) and navigation.visible(previous, point) and point.distance_to(previous) <= 0.2001, "full-region predicted segment is strict, bounded and cannot shortcut a void")
			_check(position.is_finite() and absf(position.y - game.meadow.surface_height(point.x, point.y) - 0.03) < 0.0001, "every predicted foot remains on the actual indexed mesh")
			previous = point
			if not game.moving:
				break
		_check(_local_point().distance_to(pair[1]) < 0.13 and not game.moving and recorder.sent.is_empty(), "retained long route reaches target without resending input")
		_check(not game.practice_guide.visible and game.moment_label.text.is_empty(), "wide wash has no practice lesson or arrival banner")
		await _frames()

func _unsafe_queue(kind: String) -> Array:
	for a: Dictionary in navigation.region.anchors:
		var first := Vector2(a.x, a.y)
		if first == far: continue
		if kind == "source" and not navigation.visible(camp, first) and navigation.visible(first, far):
			return [a.duplicate()]
		if kind != "middle" or not navigation.visible(camp, first): continue
		for b: Dictionary in navigation.region.anchors:
			var second := Vector2(b.x, b.y)
			if second != far and second != first and not navigation.visible(first, second) and navigation.visible(second, far):
				return [a.duplicate(), b.duplicate()]
	return []

func _dry_picking() -> void:
	_start(_region_snapshot(camp, camp))
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _viewport(viewport_size)
		for anchor: Dictionary in navigation.region.anchors:
			var point := Vector2(anchor.x, anchor.y)
			var ground: Vector3 = game._surface_position(point) - Vector3.UP * 0.03
			game.meadow.reset_player_follow()
			game.meadow.follow_player(ground, false)
			game.meadow.fit_camera()
			var screen: Vector2 = game.meadow.camera.unproject_position(ground)
			var hit: Vector3 = game.meadow.ground_at(screen)
			_check(root.get_visible_rect().has_point(screen) and hit.is_finite() and hit.distance_to(ground) < 0.08, "Every dry clearing has a real indexed-ground pick in both portrait aspects: " + str(point))
			_check(game.meadow.region_presentation.camera_lift <= 18 and game.meadow.camera.far == 600 and game.meadow.camera.keep_aspect == Camera3D.KEEP_WIDTH, "DryWash retains the same bounded region camera, not an enlarged old diorama zoom")
	var rejected: Vector3 = game.meadow.region_presentation.ray_ground(Vector3(71, 100, 95), Vector3.DOWN)
	_check(not navigation.contains(Vector2(71, 95)) and not rejected.is_finite(), "Actual scenic ground outside the canonical wash cannot become a walking tap")
	_check(game.meadow.region_profile.lattice.is_empty(), "Runtime actor grounding and picking consume prepared mesh without rebuilding the authoring lattice")
	await _frames()

func _cross_region_cache() -> void:
	_start(_region_snapshot(camp, camp))
	var dry_navigation: RefCounted = game.region_navigation
	var dry_layout: Dictionary = game.world_layout.duplicate(true)
	var legacy_camera: Dictionary = game.meadow._legacy_camera_state.duplicate()
	var legacy_environment: Dictionary = game.meadow._legacy_environment.duplicate()
	_check(game.meadow.valley_life == null and game.meadow.valley_pines == null, "Alpine-only birds and pine wind do not leak into DryWash")
	var original_navigation := navigation
	navigation = Region.new(Catalog.canonical("alpine_valley"))
	var alpine: Dictionary = super._region_snapshot(Vector2(-48, 74), Vector2(-48, 74))
	navigation = original_navigation
	_start(alpine)
	var alpine_navigation: RefCounted = game.region_navigation
	_check(not recorder.update_required and game.selected_landscape == "alpine_valley" and alpine_navigation != dry_navigation, "Accepted v8-to-v7 snapshot switches to the separate canonical navigation cache")
	_check(game.meadow.valley_life != null and game.meadow.valley_pines != null, "Original Alpine life and pine binding resume only on their registered landscape")
	var saved: Dictionary = recorder.credentials.duplicate(true)
	var actor_ids := _actor_instances()
	var bad := _region_snapshot(camp, far, 11, "walking")
	bad.players[0].route = []
	recorder.snapshot_received.emit(bad)
	_check(recorder.update_required and game.latest == alpine and game.world_layout == Catalog.layout("alpine_valley") and game.region_navigation == alpine_navigation and _actor_instances() == actor_ids and recorder.credentials == saved, "Invalid incoming v8 route cannot replace an accepted v7 world, cache, actors or invitation")
	_start(_region_snapshot(camp, camp))
	_check(game.region_navigation == dry_navigation and game.world_layout == dry_layout and not recorder.update_required, "Valid cross-region reconnect reuses the existing v8 cache rather than rebuilding it")
	game._open_settings()
	await _frames()
	await _click(game.dry_wash_button.get_global_rect().get_center())
	_check(game.selected_landscape == "dry_wash" and game.create_button.text == "Explore the wide wash" and game.dry_wash_button.text == "Wide cactus wash", "Actual tenth portrait choice clearly distinguishes the large wash from old cactus canyon")
	var credentials_before: Dictionary = recorder.credentials.duplicate(true)
	game._select_landscape("cactus")
	_check(game.meadow.region_presentation == null and game.meadow.region_navigation == null and game.meadow.gate != null and game.meadow.bridge != null, "Returning to old cactus restores its original small-world presentation and openings")
	for property in ["projection", "keep_aspect", "fov", "near", "far"]:
		_check(game.meadow.camera.get(property) == legacy_camera[property], "Legacy camera property is restored after multiple large-region transitions: " + property)
	for property in legacy_environment:
		_check(game.meadow.world_environment.get(property) == legacy_environment[property], "Legacy environment is restored exactly: " + property)
	_check(recorder.credentials == credentials_before, "Landscape browsing never changes saved identity")
	await _frames()
