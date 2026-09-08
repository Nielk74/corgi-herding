extends "res://tests/network_smoke.gd"
## Real HTTP + two real WebSocket clients. Requires a fresh disposable loopback
## server; this test must never attach to a player's saved development meadow.
## No transport, snapshot, prediction or reconnect fields are reset to pass it.

const Commons = preload("res://scripts/commons_navigation.gd")
var checks := 0
var herd_digest := ""
var sound_digest := ""
var endpoint := ""
var failed := false
var monitoring := false
var saw_predicted_motion := false
var previous_rendered := Vector2.INF

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
	var port_text := endpoint.trim_prefix("http://127.0.0.1:")
	if not endpoint.begins_with("http://127.0.0.1:") or not port_text.is_valid_int() or int(port_text) < 1024 or int(port_text) > 65535 or int(port_text) in [8790, 8791, 8792, 8793]:
		_fail("explicit isolated loopback port required; shared/live ports8790–8793 are forbidden")
		return
	# This guard is mandatory even on CI: never add a herd to a reused server.
	var health := HTTPRequest.new()
	root.add_child(health)
	health.timeout = 8.0
	for frame in range(3):
		await process_frame
	if health.request(endpoint + "/healthz") != OK:
		_fail("isolated server health request")
		return
	var response: Array = await health.request_completed
	var info: Variant = JSON.parse_string(response[3].get_string_from_utf8()) if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200 else null
	var capability_probe := Connection.new()
	var capability := capability_probe._layout_capability(info) if info is Dictionary else -1
	capability_probe.free()
	health.queue_free()
	if not info is Dictionary or info.get("status") != "ok" or info.get("sessions", -1) != 0 or capability != 6:
		_fail("test server must be healthy, support v6 and have exactly zero existing herds")
		return
	herd_digest = _digest("user://herd.cfg")
	sound_digest = _digest("user://audio.cfg")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.display_name = "Commons network A"
	game.soundscape.persist_preference = false
	game.soundscape.set_enabled(false)
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	# Match the actual portrait camera's physical and logical aspect after startup.
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(720, 1280)
	for frame in range(3):
		await process_frame
	if not _check(root.size == Vector2i(720, 1280) and root.get_visible_rect().size == Vector2(720, 1280), "matching real physical/logical portrait viewport"):
		return
	game.network.create_herd("bellflower")
	if not await _wait(func() -> bool: return game.network.connected and game.had_snapshot, "real v6 HTTP creation and first authenticated snapshot"):
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.display_name = "Commons network B"
	other.snapshot_received.connect(func(snapshot: Dictionary) -> void: other_snapshot = snapshot)
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _wait(func() -> bool: return other.connected and game.actors.size() == 14 and other_snapshot.get("players", []).size() == 2, "invite joins second authenticated peer and all14 actors"):
		return
	if not _check(game.network.credentials.code == other.credentials.code and game.network.credentials.player_id != other.credentials.player_id, "both sockets share one herd with distinct real player identities"):
		return
	if not _check(game.network.advertised_layout_version == 6 and other.advertised_layout_version == 6 and game._supported_layout("bellflower", game.latest.layout) and game._supported_layout("bellflower", other_snapshot.layout), "both clients negotiated v6 and received the canonical explicit fork"):
		return
	if not _check(game.meadow.gate == null and game.meadow.bridge == null and not game.latest.gate_open and game.latest.settled == 0, "Commons has no phantom crossing or completion objective"):
		return
	var initial_credentials: Dictionary = game.network.credentials.duplicate(true)
	var initial_ids := _ids(game.latest)
	monitoring = true
	process_frame.connect(_observe_prediction)
	# Ordinary height-aware taps, with genuine local prediction and server acks.
	# The two branch ends cannot be joined by a fabricated straight corridor.
	for destination in [Vector2(10, -6), Vector2(10, 6), Vector2(-5, 5), Vector2(10, 6), Vector2(10, -6)]:
		if not await _tap_walk(destination):
			return
	if not _check(saw_predicted_motion, "at least one genuine unacknowledged local prediction moved before server acknowledgement"):
		return
	# Start a cross-branch route and then close ONLY the real transport. A world
	# tap in the closing-before-next-poll window is predicted but cannot be sent.
	if not await _tap(Vector2(10, 6)):
		return
	var expected_seq: int = game.movement_seq
	if not await _wait(func() -> bool: return _own_seq() == expected_seq and not _own_route().is_empty(), "cross-branch movement retains a server-owned anchor queue"):
		return
	var accepted_target: Vector2 = game.movement_target
	var accepted_seq := _own_seq()
	# Prepare the projection before closing; do not yield between close and tap.
	await _frame_tap_camera()
	var lost_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(-5, 5)) - Vector3(0, 0.03, 0))
	game.network.socket.close()
	game._world_tap(lost_screen)
	if not _check(game.movement_seq == accepted_seq + 1 and game.network.seq == accepted_seq + 1 and game.moving, "actual closing WebSocket drops a real, locally predicted next input"):
		return
	monitoring = false # Reconnect's authoritative reseed may intentionally snap.
	if not await _wait(func() -> bool: return not game.network.connected, "socket close is observed by the ordinary retry mechanism"):
		return
	if not await _wait(func() -> bool: return game.network.connected and not game.awaiting_authoritative_snapshot, "ordinary retry obtains the first authoritative reconnect snapshot"):
		return
	if not _check(_own_seq() == accepted_seq and game.movement_seq == accepted_seq and game.movement_target.distance_to(accepted_target) < 0.001 and game.network.credentials == initial_credentials, "production reconnect discards the lost input and preserves accepted route, sequence and invitation"):
		return
	monitoring = true
	if not await _wait(func() -> bool: return _own_position().distance_to(accepted_target) < 0.3 and not game.moving, "reconnected herder completes the original accepted branch walk"):
		return
	# Both human identities can issue both dogs' ordinary commands. Commands are
	# observed in the other peer's authoritative snapshots, not optimistic UI.
	for dog in ["mochi", "maple"]:
		game.network.command(dog, "stay")
		if not await _wait(func() -> bool: return _dog_command(dog) == "stay", "first human Stay is authoritative for either shared dog"):
			return
		other.command(dog, "come")
		if not await _wait(func() -> bool: return _dog_command(dog) == "come", "second human Come is authoritative for either shared dog"):
			return
		other.command(dog, "go", Vector2(10, -6))
		if not await _wait(func() -> bool: return _dog_command(dog) == "go" and _dog_position(dog).distance_to(Vector2(10, -6)) < 0.35, "second human sends either shared dog down the lower branch"):
			return
		game.network.command(dog, "go", Vector2(10, 6))
		if not await _wait(func() -> bool: return _dog_command(dog) == "go" and _dog_position(dog).distance_to(Vector2(10, 6)) < 0.35, "first human returns either shared dog through the fork to the upper branch"):
			return
	if not _check(_ids(game.latest) == initial_ids and game.latest.settled == 0 and not game.latest.gate_open and game.moment_label.text.is_empty() and error_message.is_empty(), "all actor identities persist and the journey remains quiet and error-free"):
		return
	game.network.disconnect_herd()
	other.disconnect_herd()
	game.queue_free()
	other.queue_free()
	await process_frame
	await process_frame
	if not _check(_digest("user://herd.cfg") == herd_digest and _digest("user://audio.cfg") == sound_digest, "network acceptance preserves real local preferences and invitations"):
		return
	print("COMMONS_NETWORK_SMOKE_OK: %d checks; fresh isolated server, canonical v6 HTTP/invite/two real WebSockets/14 actors, predicted fork taps both ways, real closing-socket lost-input retry, both humans/both dogs across branches, no arrival UI or preference writes" % checks)
	quit(0)

func _tap_walk(destination: Vector2) -> bool:
	if not await _tap(destination):
		return false
	var sequence: int = game.movement_seq
	return await _wait(func() -> bool: return _own_seq() == sequence and _own_position().distance_to(destination) < 0.3 and not game.moving, "real predicted tap reaches the authoritative destination along declared corridors")

func _tap(destination: Vector2) -> bool:
	await _frame_tap_camera()
	var screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(destination) - Vector3(0, 0.03, 0))
	var ground: Vector3 = game.meadow.ground_at(screen)
	if not _check(root.get_visible_rect().has_point(screen) and ground.is_finite() and Vector2(ground.x, ground.z).distance_to(destination) < 0.08, "actual portrait tap picks the intended terrain"):
		return false
	var previous_seq: int = game.network.seq
	game._world_tap(screen)
	return _check(game.movement_seq == previous_seq + 1 and game.moving, "world interaction creates one real move and arms immediate prediction")

func _frame_tap_camera() -> void:
	game.meadow.zoom = 0.8
	game.meadow.camera_focus = Vector3(3, 1.8, -6)
	game.meadow.desired_focus = game.meadow.camera_focus
	game.meadow.fit_camera()
	game.meadow._process(0.0)
	await process_frame
	await process_frame

func _wait(condition: Callable, context: String) -> bool:
	for attempt in range(250):
		if failed:
			return false
		if not error_message.is_empty():
			_fail(context + ": server/client reported an error")
			return false
		if not _safe_actors():
			return false
		if condition.call():
			checks += 1
			return true
		await create_timer(0.05).timeout
	_fail(context + ": bounded250-poll wait expired")
	return false

func _safe_actors() -> bool:
	if not monitoring:
		return true
	for kind in ["players", "dogs", "sheep"]:
		for actor: Dictionary in game.latest.get(kind, []):
			var position := Commons.presentation_point(Vector2(actor.position.x, actor.position.y))
			if not _check(Commons.contains(position), "received authoritative actor stays inside canonical Commons"):
				return false
	for actor: Dictionary in game.actors.values():
		var position: Vector3 = actor.node.position
		if not _check(Commons.contains(Vector2(position.x, position.z)) and absf(position.y - game.meadow.surface_height(position.x, position.z) - 0.03) < 0.001, "rendered/predicted actors stay on the playable sampled ground"):
			return false
	_observe_prediction()
	return true

func _observe_prediction() -> void:
	if not monitoring or not is_instance_valid(game) or not game.actors.has(game.local_id):
		previous_rendered = Vector2.INF
		return
	var position: Vector3 = game.actors[game.local_id].node.position
	var point := Vector2(position.x, position.z)
	if previous_rendered.is_finite() and not _check(Commons.visible(previous_rendered, point), "every actual rendered local segment stays inside the declared fork"):
		return
	previous_rendered = point
	if game.moving and game.movement_seq > _own_seq():
		if point.distance_to(_own_position()) > 0.01:
			saw_predicted_motion = true

func _ids(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for kind in ["players", "dogs", "sheep"]:
		for actor: Dictionary in snapshot.get(kind, []):
			result.append(str(actor.id))
	result.sort()
	return result

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _check(condition: bool, context: String) -> bool:
	checks += 1
	if not condition:
		_fail(context)
	return condition

func _fail(context: String) -> void:
	if failed:
		return
	failed = true
	if is_instance_valid(game):
		game.network.disconnect_herd()
	if is_instance_valid(other):
		other.disconnect_herd()
	printerr("COMMONS_NETWORK_SMOKE_FAILED: " + context)
	quit(1)
