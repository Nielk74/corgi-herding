extends SceneTree
## Authoritative route agreement, two-way prediction and update-safe credentials.

func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	_run.call_deferred()

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if game.network == null or game.meadow == null:
		_fail("main scene dependencies did not initialize")
		return
	game.network.persist_config = false
	game.preview_mode = true
	game._show_preview()
	game.set_process(false)
	game.network.set_process(false)
	var route_checks := 0
	for kind in ["alpine", "cactus", "larch"]:
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
		if kind == "larch" and (game._walkable(Vector2(0, 0)) or game._walkable(Vector2(6, 0))):
			_fail("Larch must not retain phantom centered openings")
			return
		game.meadow.gate_open = true
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
	# The three choices must remain on the portrait welcome card, not overflow.
	game._open_settings()
	await process_frame
	for button in [game.alpine_button, game.cactus_button, game.larch_button]:
		if not root.get_visible_rect().encloses(button.get_global_rect()) or button.size.y < 58:
			_fail("portrait landscape choices must fit with usable touch areas")
			return
	game.preview_mode = false
	game.network.credentials = {"code": "TEST01", "player_id": "test-player", "token": "test-only-not-a-real-secret"}
	var credentials: Dictionary = game.network.credentials.duplicate(true)
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
	# A missing Larch layout is not permission to guess its new opening centers.
	unknown = prior_snapshot.duplicate(true)
	unknown.erase("layout")
	game.network.update_required = false
	game._on_snapshot(unknown)
	if not game.network.update_required or game.network.credentials != credentials:
		_fail("missing Larch layout must preserve credentials and request an update")
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
	print("LAYOUT_SMOKE_OK: three portrait choices, %d two-way routes, offset picking, JSON snapshot agreement, update-safe credentials" % route_checks)
	quit(0)

func _fail(message: String) -> void:
	push_error("LAYOUT_SMOKE_FAILED: " + message)
	quit(1)
