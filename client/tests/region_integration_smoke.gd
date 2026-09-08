extends "res://tests/commons_integration_smoke.gd"
## Reuse only the non-network recorder/portrait/input harness. All v7 snapshots
## below go through actual main validation, prediction, interpolation and menus.
## This is not a Go/WebSocket test; region_network_smoke covers that separately.

const Region = preload("res://scripts/region_navigation.gd")
var camp := Vector2(-48, 74)
var far := Vector2(30, -63) # Shared camp-to-anchor-5 fixture is NOT a visible chord.
var navigation: RefCounted

func _run() -> void:
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
	navigation = Region.new(Region.default_region())
	_check(navigation.valid, "canonical region is valid")
	await _viewport(Vector2i(720, 1280))
	_start(_region_snapshot(camp, camp))
	_check(not recorder.update_required and game.selected_landscape == "alpine_valley" and game.actors.size() == 14, "actual main accepts canonical JSON v7 and fourteen grounded actors")
	_check(game._walkable(camp) and game._walkable(far) and not game._walkable(Vector2(73, 97)), "v7 dispatch precedes old small-world bounds without removing new bounds")
	_check(game.meadow.region_presentation != null and game.meadow.gate == null and game.meadow.bridge == null, "prepared valley presentation has no phantom bridge/gate")
	await _invalid_region_snapshots()
	await _region_prediction()
	await _region_interpolation()
	await _region_reconnect()
	await _region_menu()
	await _startup_default()
	_capabilities()
	_check(recorder.socket == null and recorder.requests.is_empty(), "fixture opens no external connection")
	game.queue_free()
	await _frames()
	_check(before == [_digest("user://herd.cfg"), _digest("user://audio.cfg"), _digest("user://guide.cfg")], "real credentials, audio and guide preferences unchanged")
	print("REGION_INTEGRATION_SMOKE: %d checks, %d failures; canonical v7 raw routes, actual full valley prediction/mesh grounding, cached remote routes, lost-sequence reconnect, ten portrait choices" % [checks, failures])
	quit(1 if failures else 0)

func _region_snapshot(from: Vector2, destination: Vector2, sequence := 0, state := "idle") -> Dictionary:
	tick += 1
	var route: Array = []
	for anchor: Vector2 in navigation.plan(from, destination):
		route.append(_point(anchor))
	var sheep: Array = []
	for index in range(10):
		sheep.append({"id": "fixture-sheep-%d" % index, "position": _point(Vector2(-44.7 + index % 3, 62.4 + floorf(index / 3.0) * 1.05)), "state": "grazing"})
	return JSON.parse_string(JSON.stringify({"type": "snapshot", "code": "FIXTURE", "tick": tick, "landscape": "alpine_valley", "layout": game._default_layout("alpine_valley"), "gate_open": false, "settled": 0,
		"players": [{"id": LOCAL_A, "position": _point(from), "target": _point(destination), "seq": sequence, "route": route, "state": state, "connected": true},
			{"id": LOCAL_B, "position": _point(Vector2(-45, 74)), "target": _point(Vector2(-45, 74)), "seq": 0, "route": [], "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "position": _point(Vector2(-47, 71.8)), "target": _point(Vector2(-47, 71.8)), "state": "idle", "command": "stay", "caller": LOCAL_A},
			{"id": "maple", "position": _point(Vector2(-44, 71.8)), "target": _point(Vector2(-44, 71.8)), "state": "idle", "command": "stay", "caller": LOCAL_B}], "sheep": sheep}))

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
	var mutations := ["layout_missing", "layout_extra", "region_extra", "future_version", "version_string", "recipe", "bounds", "anchor", "corridor", "clearing", "point_string", "point_bool", "point_extra", "point_nan", "point_outside", "target_outside", "seq_fraction", "seq_bool", "tick_negative", "code", "missing_local", "duplicate_id", "disconnected_local", "missing_dog", "null_route", "string_route", "dict_route", "empty_occluded", "duplicate_route", "target_in_route", "noncanonical_route", "unsafe_source", "unsafe_final", "dog_route"]
	for mutation in mutations:
		_start(valid)
		var bad: Dictionary = valid.duplicate(true)
		match mutation:
			"layout_missing": bad.erase("layout")
			"layout_extra": bad.layout.hidden_obstacle = true
			"region_extra": bad.layout.region.spine = []
			"future_version": bad.layout.version = 8
			"version_string": bad.layout.version = "7"
			"recipe": bad.layout.region.recipe_id = "different_region"
			"bounds": bad.layout.region.bounds.max.y += 1
			"anchor": bad.layout.region.anchors[1].x += 0.01
			"corridor": bad.layout.region.corridors[0].half_width += 0.01
			"clearing": bad.layout.region.clearings[0].radius += 0.01
			"point_string": bad.players[0].position.x = "-48"
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
			"unsafe_source": bad.players[0].route = [_point(Vector2(-24, -40))]
			"unsafe_final": bad.players[0].route = [_point(unsafe_final)]
			"dog_route": bad.dogs[0].route = null
		var ids := _actor_instances()
		var saved: Dictionary = recorder.credentials.duplicate(true)
		recorder.snapshot_received.emit(bad)
		_check(recorder.update_required and recorder.paused and recorder.credentials == saved, mutation + " fails closed without erasing invitation")
		_check(game.latest == valid and game.world_layout == game._default_layout("alpine_valley") and _actor_instances() == ids, mutation + " cannot partially mutate accepted actors/layout/snapshot")
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
	for pair in [[camp, far], [far, camp], [Vector2(-51, -10), Vector2(34, 8)], [Vector2(34, 8), Vector2(-51, -10)]]:
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
		_check(not game.practice_guide.visible and game.moment_label.text.is_empty(), "large valley has no practice lesson or arrival banner")
		await _frames()

func _region_interpolation() -> void:
	for id in [LOCAL_B, "mochi", "fixture-sheep-0"]:
		var initial := _region_snapshot(camp, camp)
		var category := "players" if id == LOCAL_B else ("dogs" if id == "mochi" else "sheep")
		for entry: Dictionary in initial[category]:
			if entry.id == id:
				entry.position = _point(camp)
				if category != "sheep": entry.target = _point(camp)
		_start(initial)
		var delayed: Dictionary = initial.duplicate(true)
		delayed.tick += 1
		for entry: Dictionary in delayed[category]:
			if entry.id == id:
				entry.position = _point(far)
				if category != "sheep": entry.target = _point(far)
		recorder.snapshot_received.emit(delayed)
		_check(not recorder.update_required, "delayed remote endpoint passes full canonical snapshot validation")
		var previous := camp
		for frame in range(700):
			game._process(1.0 / 60.0)
			var position: Vector3 = game.actors[id].node.position
			var point := Vector2(position.x, position.z)
			_check(navigation.visible(previous, point) and position.is_finite() and absf(position.y - game.meadow.surface_height(point.x, point.y) - 0.03) < 0.001, "remote %s never interpolates through void or off mesh" % id)
			previous = point
			if point.distance_to(far) < 0.03: break
		_check(previous.distance_to(far) < 0.03, "delayed remote actor completes its display route")
		_check(game.region_display_plans == 1, "fixed remote endpoint builds one retained display route, not one graph search per frame")
		await _frames()
	# A slightly changing snapshot endpoint must also reuse still-safe anchors;
	# a static-only test would miss repeated graph searches in ordinary motion.
	var initial := _region_snapshot(camp, camp)
	initial.players[1].position = _point(camp)
	initial.players[1].target = _point(camp)
	_start(initial)
	var delayed: Dictionary = initial.duplicate(true)
	delayed.players[1].position = _point(far)
	delayed.players[1].target = _point(far)
	delayed.tick += 1
	recorder.snapshot_received.emit(delayed)
	game._process(0.00001)
	_check(game.region_display_plans == 1 and not game.actors[LOCAL_B].display_route.is_empty(), "changing-endpoint fixture starts with a retained blocked-chord route")
	var previous_route: Array = game.actors[LOCAL_B].display_route.duplicate()
	var shifted := far + Vector2(0.01, 0.0)
	delayed.players[1].position = _point(shifted)
	delayed.players[1].target = _point(shifted)
	delayed.tick += 1
	recorder.snapshot_received.emit(delayed)
	game._process(0.00001)
	_check(not recorder.update_required and game.region_display_plans == 1 and game.actors[LOCAL_B].display_route == previous_route, "new authoritative endpoint reuses a still-safe display queue without another graph search")
	await _frames()

func _region_reconnect() -> void:
	var retained := _region_snapshot(camp, far, 19, "walking")
	_start(retained)
	game._process(0.1)
	recorder.drop_next_move = true
	game.movement_seq = recorder.move_to(Vector2(-42, 64))
	game.movement_target = Vector2(-42, 64)
	game.moving = true
	_check(game.movement_seq == 20 and recorder.sent.is_empty(), "fixture models an emitted but transport-dropped local sequence")
	recorder.status_changed.emit("Disconnected", false)
	_check(game.awaiting_authoritative_snapshot and not game.moving, "disconnect pauses prediction and requests authoritative reseed")
	recorder.connected = true
	recorder.snapshot_received.emit(retained)
	_check(game.movement_seq == 19 and game.movement_target == far and game.movement_route == navigation.decode_route(retained.players[0].route), "same-tick reconnect restores actual retained sequence/target/route, not lost input")
	_check(not game.awaiting_authoritative_snapshot and game.moving and not game.practice_guide.visible, "accepted reconnect resumes movement without tutorial replay")
	await _frames()

func _region_menu() -> void:
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _viewport(size)
		_start(_region_snapshot(camp, camp))
		game._open_settings()
		game.endpoint_input.show()
		game.menu_error.text = ""
		await _frames()
		var choices: Array = [game.bellflower_button, game.long_valley_button, game.alpine_button, game.cactus_button, game.larch_button, game.orchard_button, game.oasis_button, game.cloud_button, game.juniper_button, game.dry_wash_button]
		_check(game.bellflower_button.position.y == game.long_valley_button.position.y and game.long_valley_button.position.y < game.alpine_button.position.y, "practice and large valley are the first portrait row")
		for index in choices.size():
			var rect: Rect2 = choices[index].get_global_rect()
			_check(root.get_visible_rect().encloses(rect) and rect.size.x >= 230 and rect.size.y >= 64, "all ten real menu targets remain large and on screen")
			for earlier in index:
				_check(not rect.intersects(choices[earlier].get_global_rect()), "landscape targets do not overlap")
		for control in [game.resume_button, game.sound_button, game.endpoint_input, game.create_button, game.join_button, game.name_input, _button_named(game.welcome, "Server address")]:
			_check(control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()), "expanded menu keeps Return and all settings on screen")
		game._set_busy(true)
		for choice in choices: _check(choice.disabled, "all ten choices disabled during request")
		game._set_busy(false)
		await _click(game.bellflower_button.get_global_rect().get_center())
		_check(game.selected_landscape == "bellflower", "actual first-row Practice target remains selectable")
		await _click(game.long_valley_button.get_global_rect().get_center())
		_check(game.selected_landscape == "alpine_valley" and game.create_button.text == "Explore the long valley", "actual first-row large-valley target selects canonical region")
		var saved: Dictionary = recorder.credentials.duplicate(true)
		var reconnects: int = recorder.reconnects
		await _click(game.resume_button.get_global_rect().get_center())
		_check(recorder.reconnects == reconnects + 1 and recorder.credentials == saved, "saved Return keeps original identity after landscape browsing")

func _startup_default() -> void:
	var saved: Dictionary = recorder.credentials.duplicate(true)
	recorder.credentials = {}
	game.preview_mode = false
	game._select_landscape("alpine")
	game._select_startup_landscape(PackedStringArray())
	_check(game.selected_landscape == "bellflower" and game.world_layout == Nav.layout(), "real startup selection path defaults a fresh install to Practice meadow")
	_check(not game.practice_guide.visible and not game.network.has_saved_herd(), "welcome selection does not fabricate a herd or start lesson evidence")
	game._select_landscape("cactus")
	game._select_startup_landscape(PackedStringArray(["--landscape=cactus"]))
	_check(game.selected_landscape == "cactus", "explicit landscape preview choice overrides fresh-install practice default")
	game.preview_mode = true
	game._select_startup_landscape(PackedStringArray(["--preview"]))
	_check(game.selected_landscape == "cactus", "art preview never receives automatic practice selection")
	game.preview_mode = false
	recorder.credentials = saved
	game._select_landscape("alpine")
	game._select_startup_landscape(PackedStringArray())
	_check(game.selected_landscape == "alpine" and recorder.credentials == saved, "saved invitation path is not redirected or erased by first-visit defaults")
	await _frames()
