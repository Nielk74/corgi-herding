extends SceneTree
## Authoritative route agreement, two-way prediction and update-safe credentials.

func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	# The headless display resets the physical window to 64x64 during startup.
	# Pin the logical viewport too: otherwise a supposed portrait UI test is square.
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	_run.call_deferred()

func _run() -> void:
	# Startup may overwrite the physical size set in _initialize. Camera ray
	# origins use that physical aspect, while unprojection uses the logical one.
	root.size = Vector2i(720, 1280)
	await process_frame
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if root.size != Vector2i(720, 1280) or root.get_visible_rect().size != Vector2(720, 1280):
		_fail("layout checks require matching actual physical and logical portrait viewports")
		return
	if game.network == null or game.meadow == null:
		_fail("main scene dependencies did not initialize")
		return
	game.network.persist_config = false
	game.preview_mode = true
	game._set_busy(true)
	game._select_landscape("alpine") # Legacy fixtures do not use welcome defaults.
	game._show_preview()
	if game.request_busy or not game.menu_error.text.is_empty():
		_fail("a successful join must not leave an Opening message in the menu")
		return
	game.set_process(false)
	game.network.set_process(false)
	# Timeouts and non-JSON HTTP responses are recoverable transport/protocol
	# errors. They must not throw JSON engine errors or erase a saved invitation.
	var transport := HerdConnection.new()
	transport.persist_config = false
	root.add_child(transport)
	transport.set_process(false)
	var saved := {"code": "ABCDEF", "player_id": "0123456789abcdef", "token": "test-only-token"}
	transport.credentials = saved.duplicate(true)
	var failures: Array[String] = []
	transport.request_failed.connect(func(message: String) -> void: failures.append(message))
	transport._on_http_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	transport._on_http_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "not json".to_utf8_buffer())
	transport._on_http_completed(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "<html>unavailable</html>".to_utf8_buffer())
	if failures.size() != 3 or transport.credentials != saved:
		_fail("HTTP failures must retain the saved invitation and report normally")
		return
	transport.queue_free()
	var route_checks := 0
	for kind in ["alpine", "cactus", "larch", "orchard"]:
		game._select_landscape(kind)
		await process_frame
		var bridge_y: float = game.world_layout.bridge_y
		var gate_y: float = game.world_layout.gate_y
		if game.meadow.bridge_y != bridge_y or game.meadow.gate_y != gate_y:
			_fail("rendered route differs from authoritative route")
			return
		if game.meadow.profile.bridge_y != bridge_y or game.meadow.profile.gate_y != gate_y:
			_fail("height profile differs from authoritative route")
			return
		if absf(game.meadow.gate.position.z - (gate_y - 2.0)) > 0.01:
			_fail("gate hinge must be at the offset opening")
			return
		game.meadow.gate_open = false
		if game._walkable(Vector2(6, gate_y)) or not game._walkable(Vector2(0, bridge_y)):
			_fail("closed gate and bridge collision differ from layout")
			return
		if kind in ["larch", "orchard"] and (game._walkable(Vector2(0, 0)) or game._walkable(Vector2(6, 0))):
			_fail("offset landscapes must not retain phantom centered openings")
			return
		game.meadow.gate_open = true
		if kind in ["larch", "orchard"] and game._walkable(Vector2(6, 0)):
			_fail("opening an offset gate must not create a centered opening")
			return
		var routes := [
			[Vector2(-12, 6), Vector2(12, -7)],
			[Vector2(12, -7), Vector2(-12, 6)],
			[Vector2(-9, -6), Vector2(0, bridge_y + 1.0)],
			[Vector2(12, 7), Vector2(0, bridge_y - 1.0)],
			[Vector2(0, bridge_y), Vector2(13, -6)],
			[Vector2(0, bridge_y), Vector2(-12, 7)],
			[Vector2(4, -8), Vector2(9, 8)],
			[Vector2(9, -8), Vector2(4, 8)]
		]
		for route in routes:
			var point: Vector2 = route[0]
			var destination: Vector2 = route[1]
			for step in range(1600):
				var next: Vector2 = point.move_toward(game._next_waypoint(point, destination), 4.0 / 60.0)
				if not game._walkable(next):
					_fail("%s route %s -> %s crosses blocked ground at %s" % [kind, route[0], destination, next])
					return
				point = next
				if point.distance_to(destination) < 0.04:
					break
			if point.distance_to(destination) > 0.08:
				_fail("%s route %s -> %s gets stuck at %s" % [kind, route[0], destination, point])
				return
			route_checks += 1
		game._show_preview()
		# Exercise JSON decoding, not only hand-authored GDScript dictionaries.
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.latest))
		game.network.update_required = false
		game._on_snapshot(snapshot)
		if game.network.update_required or game.selected_landscape != kind:
			_fail("supported JSON snapshot incorrectly requires an update")
			return
		game.meadow.gate_open = false
		for id in game.actors:
			game.actors[id].node.position = game._surface_position(Vector2(-12, -7))
		var gate_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(6, gate_y)) + Vector3(0, 0.7, 0))
		if game._pick_world_interaction(gate_screen) != "gate":
			_fail("offset gate cannot be directly tapped")
			return
	# Nine choices keep large touch targets; no extra controls enter gameplay.
	game._open_settings()
	await process_frame
	for button in [game.alpine_button, game.cactus_button, game.larch_button, game.orchard_button, game.oasis_button, game.cloud_button, game.juniper_button, game.bellflower_button, game.long_valley_button, game.dry_wash_button]:
		if not root.get_visible_rect().encloses(button.get_global_rect()) or button.size.y < 58 or button.size.x < 230:
			_fail("portrait landscape choices must fit with usable touch areas")
			return
	if game.alpine_button.position.y != game.cactus_button.position.y or game.larch_button.position.y != game.orchard_button.position.y or game.larch_button.position.y <= game.alpine_button.position.y:
		_fail("the original landscape choices must retain their two portrait rows")
		return
	if game.oasis_button.position.y <= game.orchard_button.position.y or game.cloud_button.position.y != game.oasis_button.position.y:
		_fail("Oasis and Cloud must share the fourth usable portrait row")
		return
	if game.juniper_button.position.y <= game.cloud_button.position.y:
		_fail("Juniper must retain a separate usable fifth portrait row")
		return
	if game.bellflower_button.position.y != game.long_valley_button.position.y or game.bellflower_button.position.y >= game.alpine_button.position.y:
		_fail("Practice meadow and Long Alpine valley must share the first portrait row")
		return
	# Canonical nested forage geometry accepts JSON numbers but no silent coercion.
	var orchard: Dictionary = JSON.parse_string(JSON.stringify(game._default_layout("orchard")))
	for mutation in ["radius", "center", "id", "extra", "missing"]:
		var bad: Dictionary = orchard.duplicate(true)
		match mutation:
			"radius": bad.forage.radius = "2.2"
			"center": bad.forage.center.x = -7.1
			"id": bad.forage.id = "unfamiliar"
			"extra": bad.forage["hidden_obstacle"] = true
			"missing": bad.erase("forage")
		if game._supported_layout("orchard", bad):
			_fail("unsafe nested forage layout accepted: " + mutation)
			return
	# Forage progress stays server-owned; the only local feedback is body language.
	game._show_preview()
	var sheep_id := "s0"
	game.actors[sheep_id].state = "nibbling"
	var head: Node3D = game.actors[sheep_id].node.get_node("Body/Head")
	for frame in range(90):
		game._process(1.0 / 60.0)
	if head.rotation.x > -0.65 or game.command_panel.visible or game.sit_button.visible:
		_fail("nibbling should lower the muzzle without adding controls")
		return
	game.actors[sheep_id].state = "fleeing"
	for frame in range(90):
		game._process(1.0 / 60.0)
	if absf(head.rotation.x) > 0.02:
		_fail("sheep must lift its head when interrupted")
		return
	# Arrival must never leave a permanent objective banner or repeat when a
	# sheep wanders out and back. Resuming a settled herd is quiet too.
	var arrival: Dictionary = game.latest.duplicate(true)
	arrival.settled = 10
	game._on_snapshot(arrival)
	if game.moment_label.text.is_empty():
		_fail("first arrival can offer one quiet acknowledgement")
		return
	game._process(7.0)
	if not game.moment_label.text.is_empty():
		_fail("arrival acknowledgement must disappear without an extra tap")
		return
	arrival.settled = 9
	game._on_snapshot(arrival)
	arrival.settled = 10
	game._on_snapshot(arrival)
	if not game.moment_label.text.is_empty():
		_fail("a returning sheep must not trigger repeated arrival messages")
		return
	game._on_herd_joined("MEADOW")
	game._on_snapshot(arrival)
	if not game.moment_label.text.is_empty():
		_fail("resuming a settled herd must remain quiet")
		return
	var capabilities := [
		[{}, 0], [{"layout_version": 1}, 1], [{"layout_version": 2.0}, 2],
		[{"layout_version": 3.0}, 3], [{"layout_version": 1, "layout_versions": [1, 2, 3]}, 3],
		[{"layout_version": 4.0}, 4], [{"layout_version": 1, "layout_versions": [1, 2, 3, 4]}, 4],
		[{"layout_versions": [5, 4, 2]}, 5], [{"layout_version": 5}, 5],
		[{"layout_versions": [6, 5, 4]}, 6], [{"layout_version": 6}, 6],
		[{"layout_versions": [7, 6, 5]}, 7], [{"layout_version": 7}, 7],
		[{"layout_versions": [8, 7, 6]}, 8], [{"layout_version": 8}, 8],
		[{"layout_versions": [9, 8, 7]}, 8], [{"layout_version": 9}, -1],
		[{"layout_version": 1, "layout_versions": [1.0, 2.0]}, 2],
		[{"layout_version": 1, "layout_versions": [99, 1]}, 1],
		[{"layout_versions": [99]}, -1], [{"layout_versions": []}, -1],
		[{"layout_versions": "1,2"}, -1], [{"layout_versions": [1, true]}, -1],
		[{"layout_versions": [1, 2.5]}, -1], [{"layout_version": "1"}, -1]
	]
	for pair in capabilities:
		if game.network._layout_capability(pair[0]) != pair[1]:
			_fail("unsafe or backwards-incompatible capability negotiation")
			return
	game.preview_mode = false
	game.network.credentials = {"code": "TEST01", "player_id": "test-player", "token": "test-only-not-a-real-secret"}
	var credentials: Dictionary = game.network.credentials.duplicate(true)
	game.network.connected = false
	game.network.paused = false
	game.network.advertised_layout_version = 2
	game.network.capability_retry_used = false
	game.network._layout_rejected("Test layout rejection")
	if game.network.update_required or game.network.paused or game.network.retry_in < 0 or not game.network.capability_retry_used:
		_fail("v2 probe racing a rollback must re-probe once")
		return
	game.network._layout_rejected("Test layout rejection")
	if not game.network.update_required or not game.network.paused or game.network.retry_in >= 0 or game.network.credentials != credentials:
		_fail("repeated layout rejection must pause with the saved invite intact")
		return
	var prior_snapshot: Dictionary = game.latest.duplicate(true)
	var unknown: Dictionary = prior_snapshot.duplicate(true)
	unknown.layout.version = 99
	game._on_snapshot(unknown)
	if not game.network.update_required or not game.network.paused or game.network.credentials != credentials:
		_fail("unknown layout must pause without losing saved credentials")
		return
	if game.latest != prior_snapshot or not game.welcome.visible or game.hud.visible:
		_fail("unknown layout must not render or replace the supported snapshot")
		return
	# Missing offset layouts are not permission to guess openings or forage zones.
	for kind in ["larch", "orchard", "oasis", "cloud"]:
		unknown = prior_snapshot.duplicate(true)
		unknown.landscape = kind
		unknown.erase("layout")
		game.network.update_required = false
		game._on_snapshot(unknown)
		if not game.network.update_required or game.network.credentials != credentials:
			_fail("missing offset layout must preserve credentials and request an update")
			return
	game.network.update_required = false
	game.network.reject_connection()
	if not game.network.auth_rejected or not game.network.paused or game.network.credentials != credentials or not game.welcome.visible:
		_fail("policy rejection must stop retrying without deleting the saved invitation")
		return
	game.network.paused = false
	game.network.update_required = false
	game.network._on_protocol_ready(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"status": "ok", "protocol": 99, "layout_version": 1}).to_utf8_buffer())
	if not game.network.update_required or not game.network.paused or game.network.socket != null or game.network.credentials != credentials:
		_fail("unknown server protocol must not send credentials or erase the saved herd")
		return
	if not await _test_oasis(game):
		return
	if not await _test_cloud(game):
		return
	print("LAYOUT_SMOKE_OK: ten portrait choices, %d legacy two-way routes, Oasis bypasses, Cloud ridge and quiet resting, offset picking, nested JSON layouts, nibbling feedback, capability negotiation, update-safe credentials" % route_checks)
	quit(0)

func _test_oasis(game: Node) -> bool:
	# Valid double-precision server position rounds slightly inside in Vector2.
	# Keep the collision radius strict and project only presentation outward.
	var rounded_boundary := Vector2(3.3979288218588337, 0.11865828913749826)
	if game.RockNavigation.visible(rounded_boundary, rounded_boundary):
		_fail("boundary rounding regression fixture no longer exercises the issue")
		return false
	var safe_boundary: Vector2 = game.RockNavigation.presentation_point(rounded_boundary)
	if not game.RockNavigation.visible(safe_boundary, safe_boundary) or safe_boundary.distance_to(rounded_boundary) > 0.00002:
		_fail("presentation projection must fix float rounding without changing collision")
		return false
	var fixture_path := ProjectSettings.globalize_path("res://").path_join("../protocol/rock-routes.json")
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not fixtures is Array or fixtures.size() != 32:
		_fail("shared Go/Godot rock planner fixtures are missing")
		return false
	for fixture: Dictionary in fixtures:
		var from := Vector2(fixture.from.x, fixture.from.y)
		var target := Vector2(fixture.target.x, fixture.target.y)
		var route: Array[Vector2] = game.RockNavigation.plan(from, target)
		if route.size() != fixture.route.size():
			_fail("Go/Godot planner route length differs: " + str(fixture.name))
			return false
		for index in route.size():
			if route[index].distance_to(game.RockNavigation.ANCHORS[int(fixture.route[index])]) > 0.00001:
				_fail("Go/Godot chosen bypass differs: " + str(fixture.name))
				return false
	game.preview_mode = true
	game._select_landscape("oasis")
	game._show_preview()
	await process_frame
	game.set_process(false)
	if game.meadow.bridge != null or game.meadow.gate != null or game._walkable(Vector2.ZERO):
		_fail("Oasis must have a solid rock and no river/gate fixtures")
		return false
	for point in [Vector2(0, -5.2), Vector2(0, 5.2), Vector2(6, -8), Vector2(6, 0), Vector2(6, 8)]:
		if not game._walkable(point):
			_fail("Oasis dry bypasses must not inherit river or fence collision")
			return false
	var canonical: Dictionary = JSON.parse_string(JSON.stringify(game._default_layout("oasis")))
	if not game._supported_layout("oasis", canonical):
		_fail("canonical Oasis JSON did not decode")
		return false
	for mutation in ["radius", "center", "extra", "missing", "version", "forage"]:
		var bad: Dictionary = canonical.duplicate(true)
		match mutation:
			"radius": bad.rock_pass.radius = "3.4"
			"center": bad.rock_pass.center.y = 0.1
			"extra": bad.rock_pass["secret_path"] = true
			"missing": bad.erase("rock_pass")
			"version": bad.version = 2
			"forage": bad["forage"] = {"id": "windfall"}
		if game._supported_layout("oasis", bad):
			_fail("unsafe Oasis layout accepted: " + mutation)
			return false
	var routes := [
		[Vector2(-13, -1.5), Vector2(12, -3)],
		[Vector2(12, -3), Vector2(-13, -1.5)],
		[Vector2(-13, 1.5), Vector2(12, 3)],
		[Vector2(12, 3), Vector2(-13, 1.5)],
		[Vector2(-12, 0), Vector2(12, 0)],
		[Vector2(12, 0), Vector2(-12, 0)],
		[Vector2(0, -7), Vector2(0, 7)],
		[Vector2(0, 7), Vector2(0, -7)],
		[Vector2(-3.5, 0), Vector2(3.5, 0)],
		[Vector2(3.5, 0), Vector2(-3.5, 0)]
	]
	for route in routes:
		for frequency in [20.0, 60.0, 4.0]:
			var point: Vector2 = route[0]
			game.movement_route.clear()
			game.route_target = Vector2.INF
			for step in range(1400):
				var next: Vector2 = game._predict_step(point, route[1], 1.0 / frequency)
				if not game._walkable(next) or not game.RockNavigation.visible(point, next) or point.distance_to(next) > 4.0 / frequency + 0.0001:
					_fail("Oasis prediction crossed rock or exceeded walking speed")
					return false
				point = next
				if point.distance_to(route[1]) < 0.04:
					break
			if point.distance_to(route[1]) > 0.08:
				_fail("Oasis route stuck: %s -> %s at %s" % [route[0], route[1], point])
				return false
	# An ordinary tap on rock does not advance input sequence, and the former
	# gate position cannot leave a phantom contextual interaction behind.
	for id in game.actors:
		game.actors[id].node.position = game._surface_position(Vector2(-12, 8))
	var gate_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(6, 0)) + Vector3(0, 0.7, 0))
	if game._pick_world_interaction(gate_screen) == "gate":
		_fail("Oasis retains a phantom gate tap")
		return false
	var old_seq: int = game.network.seq
	game._world_tap(game.meadow.camera.unproject_position(game._surface_position(Vector2.ZERO)))
	if game.network.seq != old_seq:
		_fail("tapping the rock must not send invalid predicted movement")
		return false
	# Delayed snapshots may straddle the rock; interpolation must remain outside.
	var sheep: Node3D = game.actors.s0.node
	sheep.position = game._surface_position(Vector2(-3.5, 0))
	game.actors.s0.target = game._surface_position(Vector2(3.5, 0))
	for frame in range(240):
		var before := Vector2(sheep.position.x, sheep.position.z)
		game._process(1.0 / 60.0)
		if not game.RockNavigation.visible(before, Vector2(sheep.position.x, sheep.position.z)):
			_fail("delayed animal interpolation cut through the rock")
			return false
	if Vector2(sheep.position.x, sheep.position.z).distance_to(Vector2(3.5, 0)) > 0.15:
		_fail("safe interpolation failed to catch up around the rock")
		return false
	sheep.position = game._surface_position(rounded_boundary)
	game.actors.s0.target = game._surface_position(Vector2(-8, 0))
	for frame in range(240):
		game._process(1.0 / 60.0)
	if Vector2(sheep.position.x, sheep.position.z).distance_to(Vector2(-8, 0)) > 0.15:
		_fail("a boundary-rounding snapshot must not freeze a remote animal")
		return false
	return true

func _test_cloud(game: Node) -> bool:
	game._select_landscape("cloud")
	game._show_preview()
	await process_frame
	game.set_process(false)
	if game.meadow.gate != null or game.meadow.bridge != null or game.meadow.profile.river_width(0.0) != 0.0:
		_fail("Cloud retains a phantom river or gate")
		return false
	if game.meadow.water != null and game.meadow.water.name != "CloudDistantTarn":
		_fail("Cloud water must be distant scenery, not the old river channel")
		return false
	var canonical: Dictionary = JSON.parse_string(JSON.stringify(game._default_layout("cloud")))
	if not game._supported_layout("cloud", canonical):
		_fail("canonical Cloud JSON arrays did not decode")
		return false
	for mutation in ["missing", "version", "spine_size", "spine_order", "spine_bool", "spine_string", "width", "shelf", "rest", "extra", "rock"]:
		var bad := canonical.duplicate(true)
		match mutation:
			"missing": bad.erase("ridge")
			"version": bad.version = 3
			"spine_size": bad.ridge.spine.pop_back()
			"spine_order": bad.ridge.spine.reverse()
			"spine_bool": bad.ridge.spine[2].y = true
			"spine_string": bad.ridge.spine[2].x = "5"
			"width": bad.ridge.half_width += 0.000001
			"shelf": bad.ridge.shelves[1].center.x += 0.1
			"rest": bad.ridge.rest.radius = 5.2
			"extra": bad.ridge.spine[0]["path"] = true
			"rock": bad["rock_pass"] = {"center": {"x": 0, "y": 0}, "radius": 3.4}
		if game._supported_layout("cloud", bad):
			_fail("unsafe Cloud layout accepted: " + mutation)
			return false
	var start := Vector2(-12, 5)
	var target := Vector2(12, 8)
	for frequency in [20.0, 60.0, 4.0]:
		var point := start
		game.movement_route.clear()
		game.route_target = Vector2.INF
		for step in 1600:
			var next: Vector2 = game._predict_step(point, target, 1.0 / frequency)
			if not game.CloudNavigation.visible(point, next) or point.distance_to(next) > 4.0 / frequency + 0.0001:
				_fail("Cloud main prediction leaves the corridor or exceeds walking speed")
				return false
			point = next
			if point.distance_to(target) < 0.04:
				break
		if point.distance_to(target) > 0.08:
			_fail("Cloud main prediction failed to complete its bypass")
			return false
	var sheep: Node3D = game.actors.s0.node
	sheep.position = game._surface_position(start)
	game.actors.s0.target = game._surface_position(target)
	for frame in 480:
		var before := Vector2(sheep.position.x, sheep.position.z)
		game._process(1.0 / 60.0)
		if not game.CloudNavigation.visible(before, Vector2(sheep.position.x, sheep.position.z)):
			_fail("Cloud delayed interpolation cuts across the slope outside the ridge")
			return false
	if Vector2(sheep.position.x, sheep.position.z).distance_to(target) > 0.15:
		_fail("Cloud interpolation never catches up along the ridge")
		return false
	game._show_preview()
	var seq: int = game.network.seq
	game._world_tap(game.meadow.camera.unproject_position(game._surface_position(Vector2(0, 9))))
	if game.network.seq != seq:
		_fail("Cloud void tap must not issue predicted movement")
		return false
	var gate_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(6, 0)) + Vector3(0, 0.7, 0))
	if game._pick_world_interaction(gate_screen) == "gate":
		_fail("Cloud still has an invisible gate interaction")
		return false
	var snapshot: Dictionary = game.latest.duplicate(true)
	snapshot.settled = 10
	game._on_snapshot(snapshot)
	if not game.moment_label.text.is_empty() or game.moment_time != 0.0:
		_fail("Cloud must not announce a completion when sheep reach the upper shelf")
		return false
	game._on_status("Reconnecting", false)
	game._on_snapshot(snapshot)
	if not game.moment_label.text.is_empty():
		_fail("Cloud quiet resting must persist through reconnect")
		return false
	return true

func _fail(message: String) -> void:
	push_error("LAYOUT_SMOKE_FAILED: " + message)
	quit(1)
