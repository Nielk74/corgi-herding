extends "res://tests/network_smoke.gd"
## Run only against an isolated temporary server, never a player's saved world.

func _run() -> void:
	var endpoint := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
	if not endpoint.begins_with("http://127.0.0.1:"):
		_fail("Juniper network test requires an explicit loopback-only test server")
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.display_name = "Juniper test A"
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	for frame in range(3):
		await process_frame
	game.network.create_herd("juniper")
	if not await _until(func() -> bool: return game.network.connected):
		_fail("Juniper invitation creation and first v5 WebSocket")
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.display_name = "Juniper test B"
	other.snapshot_received.connect(func(snapshot: Dictionary) -> void: other_snapshot = snapshot)
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _until(func() -> bool: return other.connected and game.actors.size() == 14):
		_fail("second Juniper herder joins all14 rendered actors")
		return
	if game.network.advertised_layout_version != 8 or other.advertised_layout_version != 8 or not game._supported_layout("juniper", game.latest.layout) or other_snapshot.landscape != "juniper":
		_fail("clients must negotiate current v8 capability and share the canonical v5 shore")
		return
	if game.meadow.gate != null or game.meadow.bridge != null:
		_fail("Juniper inherited a phantom crossing")
		return
	for destination in [Vector2(-1, -6), Vector2(11, 4), Vector2(-14, 0)]:
		game._world_tap(game.meadow.camera.unproject_position(game._surface_position(destination)))
		if not await _until(func() -> bool: return _own_position().distance_to(destination) < 0.3):
			_fail("real shore taps must walk around the bay outward and back")
			return
	game.network.move_to(Vector2(11, 4))
	if not await _until(func() -> bool: return not _own_route().is_empty()):
		_fail("a lake detour must retain canonical shore anchors")
		return
	var accepted_seq := _own_seq()
	game.network.disconnect_herd()
	await create_timer(0.15).timeout
	game.network.seq = 0
	game.network.reconnect()
	if not await _until(func() -> bool: return game.network.connected and _own_position().distance_to(Vector2(11, 4)) < 0.3):
		_fail("reconnect must complete the accepted shore route")
		return
	if game.network.seq != accepted_seq or game.movement_seq != accepted_seq or game.awaiting_authoritative_snapshot:
		_fail("reconnect must restore input/prediction sequence")
		return
	for dog_id in ["mochi", "maple"]:
		other.command(dog_id, "go", Vector2(11, 4))
		if not await _until(func() -> bool: return _dog_position(dog_id).distance_to(Vector2(11, 4)) < 0.35):
			_fail("other herder routes either shared dog around the bay")
			return
		game.network.command(dog_id, "go", Vector2(-11, 2))
		if not await _until(func() -> bool: return _dog_position(dog_id).distance_to(Vector2(-11, 2)) < 0.35):
			_fail("first herder routes either shared dog back")
			return
	if game.latest.settled != 0 or not game.moment_label.text.is_empty() or not error_message.is_empty():
		_fail("the shore must remain quiet, without errors or arrival UI")
		return
	game.network.disconnect_herd()
	other.disconnect_herd()
	game.queue_free()
	other.queue_free()
	await process_frame
	print("SHORE_NETWORK_SMOKE_OK: v5 creation/invite/two WebSockets/14 actors, true shore taps outward/back, retained reconnect route+sequence, both shared dogs outward/back, no arrival UI")
	quit(0)
