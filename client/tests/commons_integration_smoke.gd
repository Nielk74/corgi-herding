extends SceneTree
## Real main/snapshot/UI behavior; the only substitute is a non-network recorder.
## Successful capability selection is tested through the production parser; this
## does not claim a WebSocket handshake (covered separately by network smoke).

const Nav = preload("res://scripts/commons_navigation.gd")
const LOCAL_A := "fixture-player-a"
const LOCAL_B := "fixture-player-b"

class RecordingConnection:
	extends "res://scripts/network.gd"
	var sent: Array[Dictionary] = []
	var attempted: Array[Dictionary] = []
	var requests: Array[Dictionary] = []
	var reconnects := 0
	var drop_next_move := false
	func send(message: Dictionary) -> void:
		var record := {"by": credentials.get("player_id", ""), "message": message.duplicate(true)}
		attempted.append(record)
		if message.get("type") == "move" and drop_next_move:
			drop_next_move = false
			return
		sent.append(record)
	func reconnect() -> void:
		reconnects += 1
		paused = false
		retry_in = -1.0
		status_changed.emit("Fixture reconnect", false)
	func _request(path: String, extra: Dictionary = {}) -> void:
		requests.append({"path": path, "extra": extra.duplicate(true)})

var game: Node3D
var recorder: RecordingConnection
var checks := 0
var failures := 0
var tick := 0
var route_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var herd_before := _digest("user://herd.cfg")
	var sound_before := _digest("user://audio.cfg")
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
	await _viewport(Vector2i(720, 1280))
	_start(_snapshot(Vector2(-5, 0), Vector2(-5, 0)))
	_check(not recorder.update_required and game.selected_landscape == "bellflower", "canonical JSON v6 snapshot accepted")
	_check(game.world_layout == Nav.layout() and game.meadow.profile.landscape == "bellflower", "accepted canonical geometry reaches main and profile")
	_check(game.actors.size() == 14 and not game.awaiting_authoritative_snapshot, "two humans, both dogs and all ten sheep restored")
	await _invalid_layouts()
	_capabilities()
	await _previous_layouts()
	await _prediction()
	await _lost_input()
	await _shared_dogs()
	await _quiet_clearings()
	await _menu()
	_check(recorder.socket == null and recorder.requests.is_empty(), "fixture never opens a socket or creates/joins an external herd")
	game.queue_free()
	await _frames()
	_check(_digest("user://herd.cfg") == herd_before and _digest("user://audio.cfg") == sound_before, "real invitation and audio preference files remain byte-identical")
	print("COMMONS_INTEGRATION_SMOKE: %d checks, %d failures; strict JSON v6, legacy capability parser, %d predicted routes, lost-input reconnect, shared dog controls, three quiet clearings, actual 720x1280/720x1600 menu" % [checks, failures, route_count])
	quit(1 if failures else 0)

func _snapshot(from: Vector2, destination: Vector2, local := LOCAL_A, sequence := 0, state := "idle") -> Dictionary:
	tick += 1
	var route: Array = []
	for point in Nav.plan(from, destination):
		route.append(_point(point))
	var other := LOCAL_B if local == LOCAL_A else LOCAL_A
	var players := [
		{"id": local, "name": "Fixture", "position": _point(from), "target": _point(destination), "route": route, "seq": sequence, "state": state, "connected": true},
		{"id": other, "name": "Partner", "position": _point(Vector2(-7, -2)), "target": _point(Vector2(-7, -2)), "route": [], "seq": 0, "state": "idle", "connected": true},
	]
	var sheep: Array = []
	for index in range(10):
		sheep.append({"id": "fixture-sheep-%d" % index, "position": _point(Vector2(-8 + (index % 5) * 0.6, 2 + (index / 5) * 0.7)), "state": "grazing"})
	var snapshot := {"type": "snapshot", "tick": tick, "landscape": "bellflower", "layout": Nav.layout(), "gate_open": false, "settled": 0, "players": players, "dogs": [
		{"id": "mochi", "position": _point(Vector2(-5, -1)), "state": "idle"},
		{"id": "maple", "position": _point(Vector2(-4, -1)), "state": "idle"}], "sheep": sheep}
	# Exercise real JSON numeric representation rather than only native constants.
	return JSON.parse_string(JSON.stringify(snapshot))

func _start(snapshot: Dictionary, local := LOCAL_A) -> void:
	recorder.credentials = {"code": "FIXTURE", "player_id": local, "token": "test-only-not-an-invitation"}
	recorder.connected = true
	recorder.paused = false
	recorder.update_required = false
	recorder.auth_rejected = false
	recorder.capability_retry_used = false
	recorder.retry_in = -1.0
	recorder.seq = 0
	recorder.sent.clear()
	recorder.attempted.clear()
	recorder.drop_next_move = false
	game._on_herd_joined("FIXTURE")
	recorder.snapshot_received.emit(snapshot)
	game._on_status("Fixture connected", true)

func _invalid_layouts() -> void:
	var mutations := ["no_layout", "null_layout", "empty_layout", "unknown_landscape", "version_string", "version_bool", "version_future", "missing_commons", "extra_feature", "extra_nested", "bridge", "gate", "anchors_missing", "anchors_short", "anchors_reordered", "anchor_string", "anchor_bool", "anchor_extra", "anchor_shift", "corridors_missing", "corridors_short", "phantom_extra", "phantom_replacement", "corridors_reordered", "edge_reversed", "edge_string", "edge_bool", "edge_extra", "width_string", "width_bool", "width_changed", "clearings_short", "clearings_reordered", "radius_string", "radius_changed", "center_missing", "center_string", "clearing_extra"]
	for mutation in mutations:
		var valid := _snapshot(Vector2(-5, 0), Vector2(-5, 0))
		_start(valid)
		var bad: Dictionary = valid.duplicate(true)
		match mutation:
			"no_layout": bad.erase("layout")
			"null_layout": bad.layout = null
			"empty_layout": bad.layout = {}
			"unknown_landscape": bad.landscape = "future_commons"
			"version_string": bad.layout.version = "6"
			"version_bool": bad.layout.version = true
			"version_future": bad.layout.version = 7
			"missing_commons": bad.layout.erase("commons")
			"extra_feature": bad.layout["shore"] = {}
			"extra_nested": bad.layout.commons["spine"] = []
			"bridge": bad.layout.bridge_y = 1
			"gate": bad.layout.gate_y = -1
			"anchors_missing": bad.layout.commons.erase("anchors")
			"anchors_short": bad.layout.commons.anchors.pop_back()
			"anchors_reordered": bad.layout.commons.anchors.reverse()
			"anchor_string": bad.layout.commons.anchors[0].x = "-5"
			"anchor_bool": bad.layout.commons.anchors[1].x = false
			"anchor_extra": bad.layout.commons.anchors[0]["height"] = 0
			"anchor_shift": bad.layout.commons.anchors[1].x = 0.01
			"corridors_missing": bad.layout.commons.erase("corridors")
			"corridors_short": bad.layout.commons.corridors.pop_back()
			"phantom_extra": bad.layout.commons.corridors.append([3, 4])
			"phantom_replacement": bad.layout.commons.corridors[3] = [3, 4]
			"corridors_reordered": bad.layout.commons.corridors.reverse()
			"edge_reversed": bad.layout.commons.corridors[0] = [1, 0]
			"edge_string": bad.layout.commons.corridors[0][0] = "0"
			"edge_bool": bad.layout.commons.corridors[0][0] = false
			"edge_extra": bad.layout.commons.corridors[0].append(2)
			"width_string": bad.layout.commons.half_width = "3.6"
			"width_bool": bad.layout.commons.half_width = true
			"width_changed": bad.layout.commons.half_width = 3.7
			"clearings_short": bad.layout.commons.clearings.pop_back()
			"clearings_reordered": bad.layout.commons.clearings.reverse()
			"radius_string": bad.layout.commons.clearings[0].radius = "7.2"
			"radius_changed": bad.layout.commons.clearings[0].radius = 7.21
			"center_missing": bad.layout.commons.clearings[0].erase("center")
			"center_string": bad.layout.commons.clearings[0].center.y = "0"
			"clearing_extra": bad.layout.commons.clearings[0]["objective"] = true
		var saved: Dictionary = recorder.credentials.duplicate(true)
		var actors_before := _actor_instances()
		recorder.snapshot_received.emit(bad)
		_check(recorder.update_required and recorder.paused and not recorder.connected, mutation + " stops unsupported gameplay")
		_check(recorder.credentials == saved and recorder.has_saved_herd(), mutation + " preserves invitation")
		_check(game.latest == valid and game.world_layout == Nav.layout() and _actor_instances() == actors_before, mutation + " cannot partially mutate accepted world")
		_check(game.welcome.visible and not game.hud.visible and not game.menu_error.text.is_empty(), mutation + " offers settings and a clear update error")
		_check(recorder.sent.is_empty() and recorder.retry_in < 0, mutation + " causes no auth/input/retry burst")
		await _frames()

func _capabilities() -> void:
	_start(_snapshot(Vector2(-5, 0), Vector2(-5, 0)))
	var cases: Array = [[{}, 0], [{"layout_versions": [6, 5, 4]}, 6], [{"layout_versions": [99, 6, 1]}, 6], [{"layout_version": 1, "layout_versions": [1, 2, 3, 4, 5, 6]}, 6]]
	for version in range(7):
		cases.append([{"layout_version": version}, version])
		cases.append([{"layout_versions": range(1, version + 1)}, version] if version > 0 else [{"layout_versions": [0]}, 0])
	for bad in [[], [99], [true, 6], ["6"], [-1, 6], [1.5, 6], "1,6", null]:
		cases.append([{"layout_versions": bad}, -1])
	for bad in ["6", true, 6.1, 7, -1, null]:
		cases.append([{"layout_version": bad}, -1])
	for pair in cases:
		_check(recorder._layout_capability(pair[0]) == pair[1], "highest common capability without coercion: " + JSON.stringify(pair[0]))
	var saved: Dictionary = recorder.credentials.duplicate(true)
	for invalid_health in [{"status": "ok", "protocol": 2, "layout_versions": [6]}, {"status": "ok", "protocol": "1", "layout_versions": [6]}, {"status": "ok", "protocol": 1, "layout_versions": [99]}]:
		recorder.paused = false
		recorder.update_required = false
		recorder._on_protocol_ready(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(invalid_health).to_utf8_buffer())
		_check(recorder.socket == null and recorder.update_required and recorder.credentials == saved, "unsupported health stops before auth and preserves invitation")
	recorder.paused = false
	recorder.connected = false
	recorder.update_required = false
	recorder.advertised_layout_version = 6
	recorder.capability_retry_used = false
	recorder._layout_rejected("Fixture version race")
	_check(recorder.capability_retry_used and recorder.retry_in > 0 and not recorder.update_required, "rollback race gets one bounded capability retry")
	recorder._layout_rejected("Fixture version rejected twice")
	_check(recorder.update_required and recorder.paused and recorder.retry_in < 0 and recorder.credentials == saved, "second version rejection pauses with credentials intact")

func _prediction() -> void:
	var routes := [[Vector2(-5, 0), Vector2(10, -6)], [Vector2(-5, 0), Vector2(10, 6)], [Vector2(10, -6), Vector2(-5, 0)], [Vector2(10, 6), Vector2(-5, 0)], [Vector2(10, -6), Vector2(10, 6)], [Vector2(10, 6), Vector2(10, -6)]]
	for pair in routes:
		for hz in [20.0, 60.0]:
			var retained := _snapshot(pair[0], pair[1], LOCAL_A, 7, "walking")
			_start(retained)
			_check(game.movement_seq == 7 and game.movement_target.is_equal_approx(pair[1]), "snapshot restores accepted movement target and sequence")
			_check(game.movement_route == Nav.decode_route(retained.players[0].route), "snapshot restores exact retained anchor queue")
			_walk_to(pair[1], 1.0 / hz)
			_check(recorder.sent.is_empty(), "retained route playback never resends an input")
			await _frames()
	# Actual world picking also has to reach the move sender, not just a helper.
	_start(_snapshot(Vector2(-5, 0), Vector2(-5, 0)))
	await _tap_ground(Vector2(10, -6))
	_check(recorder.sent.size() == 1 and recorder.sent[0].message.type == "move" and game.moving, "height-aware world tap emits one predicted movement input")
	if game.moving:
		_walk_to(game.movement_target, 1.0 / 60.0)
	var before := recorder.sent.size()
	await _tap_ground(Vector2(7, 0), false)
	_check(not Nav.contains(Vector2(7, 0)) and recorder.sent.size() == before and not game.moving, "phantom inter-branch shortcut tap is rejected")
	for invalid_route in [[{"x": 3, "y": 4}], [{"x": 0, "y": 0}, {"x": 0, "y": 0}], [{"x": "0", "y": 0}]]:
		var snapshot := _snapshot(Vector2(10, -6), Vector2(10, 6), LOCAL_A, 8, "walking")
		snapshot.players[0].route = invalid_route
		_start(snapshot)
		_check(game.movement_route.is_empty() and game.moving, "malformed retained queue is rejected whole without losing the accepted destination")
		_walk_to(Vector2(10, 6), 1.0 / 60.0)
		_check(recorder.sent.is_empty(), "local recovery of an invalid presentation queue does not invent server inputs")
		await _frames()

func _previous_layouts() -> void:
	# Feed genuine old JSON layout contracts through main's accepted-snapshot
	# signal path. Actor simulation and transport interoperability have their own
	# regression suites; no live server is contacted by this compatibility test.
	for landscape in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper"]:
		var snapshot := _snapshot(Vector2(-5, 0), Vector2(-5, 0))
		snapshot.landscape = landscape
		snapshot.layout = JSON.parse_string(JSON.stringify(game._default_layout(landscape)))
		snapshot.players = []
		snapshot.dogs = []
		snapshot.sheep = []
		_start(snapshot)
		_check(not recorder.update_required and game.selected_landscape == landscape and game.latest == snapshot, "new client accepts previous canonical layout: " + landscape)
		_check(game.world_layout == game._default_layout(landscape), "previous geometry is canonical, not coerced into v6")
		if landscape in ["alpine", "cactus"]:
			snapshot.erase("layout")
			recorder.snapshot_received.emit(snapshot)
			_check(not recorder.update_required and game.selected_landscape == landscape, "old centered server without layout remains accepted")
		await _frames()

func _lost_input() -> void:
	var accepted := _snapshot(Vector2(10, -6), Vector2(10, 6), LOCAL_A, 7, "walking")
	_start(accepted)
	game._process(0.1)
	recorder.drop_next_move = true
	# Keep the dropped destination away from the two contextual dog hit areas.
	await _tap_ground(Vector2(-5, 5))
	_check(game.movement_seq == 8 and recorder.seq == 8 and recorder.sent.is_empty(), "closing-transport substitute drops a genuinely predicted unacknowledged tap")
	recorder.disconnect_herd()
	_check(game.awaiting_authoritative_snapshot and not game.moving, "disconnect freezes prediction and requests authoritative reseed")
	var before := _local_point()
	game._process(0.5)
	_check(_local_point().is_equal_approx(before), "disconnected client never advances the retained walk")
	var saved: Dictionary = recorder.credentials.duplicate(true)
	recorder.reconnect()
	recorder.connected = true
	recorder.status_changed.emit("Fixture restored", true)
	recorder.snapshot_received.emit(accepted)
	_check(game.movement_seq == 7 and recorder.seq == 8 and game.moving and not game.awaiting_authoritative_snapshot, "first reconnect snapshot rebases lost local sequence without reducing transport sequence")
	_check(game.movement_target.is_equal_approx(Vector2(10, 6)) and game.movement_route == Nav.decode_route(accepted.players[0].route), "reconnect restores server destination and original queue, not dropped destination")
	_check(recorder.credentials == saved and recorder.sent.is_empty(), "reconnect neither replaces invitation nor retransmits lost movement")
	_walk_to(Vector2(10, 6), 1.0 / 60.0)
	await _tap_ground(Vector2(-5, 5))
	_check(game.movement_seq == 9 and recorder.sent.size() == 1, "next real tap remains monotonic after reseed")

func _shared_dogs() -> void:
	for human in [LOCAL_A, LOCAL_B]:
		for dog in ["mochi", "maple"]:
			_start(_snapshot(Vector2(-5, 0), Vector2(-5, 0), human), human)
			for instruction in ["Come", "Stay"]:
				game._select_dog(dog)
				await _frames()
				var button := _button_named(game.command_panel, instruction)
				_check(button != null, "context exposes " + instruction)
				if button != null:
					await _click(button.get_global_rect().get_center())
					_check(recorder.sent.back() == {"by": human, "message": {"type": "command", "dog_id": dog, "command": instruction.to_lower()}}, "either local human commands either shared dog through GUI")
					_check(not game.command_panel.visible, "dog command returns to quiet world")
			game._select_dog(dog)
			await _frames()
			await _click(game.go_button.get_global_rect().get_center())
			_check(game.go_pending and not game.command_panel.visible, "actual Go button awaits a world target")
			await _tap_ground(Vector2(10, 6))
			var message: Dictionary = recorder.sent.back().message
			_check(recorder.sent.back().by == human and message.type == "command" and message.command == "go" and message.dog_id == dog and Nav.contains(Vector2(message.target.x, message.target.y)), "both humans can send either corgi along either branch")
			_check(not game.go_pending and not game.command_panel.visible and not game.moving, "dog target must not silently walk the human or leave permanent controls")

func _quiet_clearings() -> void:
	for center in [Vector2(-5, 0), Vector2(10, -6), Vector2(10, 6)]:
		var snapshot := _snapshot(center, center, LOCAL_A, 3, "sitting")
		_start(snapshot)
		game._process(7.0)
		_check(game.moment_label.text.is_empty() and game.moment_time == 0 and not game.moving, "every clearing supports quiet resting, not arrival scoring")
		_check(not game.command_panel.visible and not game.sit_button.visible and not game.go_cancel.visible and game.hint_label.text.is_empty(), "rest has no persistent command or objective HUD")
		# Even an old generic settled counter must not turn this level into a goal.
		snapshot.settled = 10
		recorder.snapshot_received.emit(snapshot)
		_check(game.moment_label.text.is_empty() and recorder.sent.is_empty(), "generic settled state cannot add an arrival banner to Commons")
		var world_point: Vector3 = game.actors[LOCAL_A].node.position + Vector3(0, 1, 0)
		await _frame_camera()
		game._world_tap(game.meadow.camera.unproject_position(world_point))
		_check(game.sit_button.visible, "herder world interaction reveals only contextual Sit")
		await _frames()
		await _click(game.sit_button.get_global_rect().get_center())
		_check(recorder.sent.size() == 1 and recorder.sent[0].message == {"type": "interact", "action": "sit", "dog_id": ""} and not game.sit_button.visible, "Sit works in all three clearings and dismisses itself")

func _menu() -> void:
	_start(_snapshot(Vector2(-5, 0), Vector2(-5, 0)))
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _viewport(size)
		game._open_settings()
		game.endpoint_input.show()
		game.menu_error.text = ""
		await _frames()
		var buttons: Array = [game.alpine_button, game.cactus_button, game.larch_button, game.orchard_button, game.oasis_button, game.cloud_button, game.juniper_button, game.bellflower_button]
		var server := _button_named(game.welcome, "Server address")
		_check(game.resume_button.visible and server != null, "saved Return and expanded server controls are really present")
		for index in range(buttons.size()):
			var button: Button = buttons[index]
			var rectangle := button.get_global_rect()
			_check(root.get_visible_rect().encloses(rectangle) and rectangle.size.x >= 230 and rectangle.size.y >= 64, "all eight landscape targets fit real portrait at usable size")
			for earlier in range(index):
				_check(not rectangle.intersects(buttons[earlier].get_global_rect()), "landscape touch areas never overlap")
		for control in [server, game.sound_button, game.resume_button, game.endpoint_input, game.create_button, game.join_button, game.name_input]:
			_check(control != null and root.get_visible_rect().encloses(control.get_global_rect()), "expanded saved-herd menu remains entirely on screen")
		_check(server.size.y >= 64 and game.sound_button.size.y >= 64, "sound and server retain full phone touch height")
		game._set_busy(true)
		for button in buttons:
			_check(button.disabled, "all eight landscapes are disabled during an in-flight request")
		game._set_busy(false)
		game.menu_error.text = ""
		for button in buttons:
			_check(not button.disabled, "all eight landscapes recover after a request")
		await _click(game.bellflower_button.get_global_rect().get_center())
		_check(game.selected_landscape == "bellflower" and game.create_button.text == "Linger in the meadow", "eighth GUI target selects the actual Commons journey")
		var saved: Dictionary = recorder.credentials.duplicate(true)
		await _click(game.sound_button.get_global_rect().get_center())
		_check(recorder.credentials == saved, "local sound preference cannot replace invitation credentials")
		game.soundscape.set_enabled(false)
		var reconnects := recorder.reconnects
		await _click(game.resume_button.get_global_rect().get_center())
		_check(recorder.reconnects == reconnects + 1 and recorder.credentials == saved and not game.welcome.visible, "actual saved Return invokes only the recording reconnect and keeps identity")

func _walk_to(destination: Vector2, delta: float) -> void:
	var previous := _local_point()
	for step in range(1800):
		game._process(delta)
		var current := _local_point()
		_check(Nav.contains(current) and Nav.visible(previous, current), "predicted segment stays in explicit corridor union")
		_check(current.distance_to(previous) <= 4.0 * delta + 0.0001, "prediction respects movement speed")
		_check(absf(game.actors[game.local_id].node.position.y - game.meadow.surface_height(current.x, current.y) - 0.03) < 0.0001, "predicted actor remains on sampled actual terrain")
		previous = current
		if not game.moving:
			break
	_check(previous.distance_to(destination) < 0.12 and not game.moving and game.movement_route.is_empty(), "predicted route reaches destination and consumes retained queue")
	_check(game.moment_label.text.is_empty(), "walking a branch never creates completion UI")
	route_count += 1

func _tap_ground(point: Vector2, must_pick := true) -> void:
	await _frame_camera()
	var screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(point) - Vector3(0, 0.03, 0))
	_check(root.get_visible_rect().has_point(screen), "world tap fixture lies inside the real portrait frame")
	var hit: Vector3 = game.meadow.ground_at(screen)
	if must_pick:
		_check(hit.is_finite() and Vector2(hit.x, hit.z).distance_to(point) < 0.08, "real height-aware picking reaches intended walkable destination")
	game._world_tap(screen)

func _frame_camera() -> void:
	game.meadow.zoom = 0.8
	game.meadow.camera_focus = Vector3(3, 1.8, -6)
	game.meadow.desired_focus = game.meadow.camera_focus
	game.meadow.fit_camera()
	game.meadow._process(0.0)
	await _frames()

func _viewport(size: Vector2i) -> void:
	root.content_scale_size = size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = size
	await _frames()
	_check(root.size == size and root.get_visible_rect().size == Vector2(size), "physical and logical portrait aspect must both be real")

func _actor_instances() -> Dictionary:
	var result := {}
	for id in game.actors:
		result[id] = game.actors[id].node.get_instance_id()
	return result

func _button_named(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := _button_named(child, title)
		if found != null:
			return found
	return null

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
	await _frames()

func _frames() -> void:
	await process_frame
	await process_frame

func _point(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}

func _local_point() -> Vector2:
	var position: Vector3 = game.actors[game.local_id].node.position
	return Vector2(position.x, position.z)

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("COMMONS_INTEGRATION_FAILED: " + message)
