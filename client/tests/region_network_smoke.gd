extends "res://tests/commons_network_smoke.gd"
## Actual HTTP and two ordinary WebSocket peers on an explicitly fresh loopback
## server. Nearby destinations use real portrait picking; the distant walk uses
## the same production move sender, then authoritative snapshot reconciliation.

const Region = preload("res://scripts/region_navigation.gd")
const CAMP := Vector2(-48, 74)
const FAR := Vector2(30, -63)
var navigation: RefCounted
var guide_digest := ""

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
	var port_text := endpoint.trim_prefix("http://127.0.0.1:")
	if not endpoint.begins_with("http://127.0.0.1:") or not port_text.is_valid_int() or int(port_text) < 1024 or int(port_text) > 65535 or int(port_text) in [8790, 8791, 8792, 8793, 8795]:
		_fail("explicit fresh loopback port required; shared/live/manual-play ports are forbidden")
		return
	var health := HTTPRequest.new()
	root.add_child(health)
	health.timeout = 8.0
	for frame in range(3): await process_frame
	if health.request(endpoint + "/healthz") != OK:
		_fail("isolated server health request")
		return
	var response: Array = await health.request_completed
	var info: Variant = JSON.parse_string(response[3].get_string_from_utf8()) if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200 else null
	var probe := Connection.new()
	var capability := probe._layout_capability(info) if info is Dictionary else -1
	probe.free()
	health.queue_free()
	if not info is Dictionary or info.get("status") != "ok" or info.get("sessions", -1) != 0 or capability != 7:
		_fail("test server must support exactly current v7 and have zero existing herds")
		return
	herd_digest = _digest("user://herd.cfg")
	sound_digest = _digest("user://audio.cfg")
	guide_digest = _digest("user://guide.cfg")
	navigation = Region.new(Region.default_region())
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.display_name = "Region network A"
	game.soundscape.persist_preference = false
	game.soundscape.set_enabled(false)
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	root.content_scale_size = Vector2i(720, 1600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(720, 1600)
	for frame in range(3): await process_frame
	if not _check(root.size == Vector2i(720, 1600) and root.get_visible_rect().size == Vector2(720, 1600), "real physical and logical 20:9 portrait viewport"):
		return
	game.network.create_herd("alpine_valley")
	if not await _wait(func() -> bool: return game.network.connected and game.had_snapshot, "v7 HTTP creation and accepted authenticated snapshot"):
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.display_name = "Region network B"
	other.snapshot_received.connect(func(snapshot: Dictionary) -> void: other_snapshot = snapshot)
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _wait(func() -> bool: return other.connected and game.actors.size() == 14 and other_snapshot.get("players", []).size() == 2, "real invited peer restores all fourteen actors"):
		return
	if not _check(game.network.advertised_layout_version == 7 and other.advertised_layout_version == 7 and game._supported_layout("alpine_valley", game.latest.layout) and game._supported_layout("alpine_valley", other_snapshot.layout), "both peers negotiate7 and receive the exact canonical immutable region"):
		return
	if not _check(game.network.credentials.player_id != other.credentials.player_id and game.network.credentials.code == other.credentials.code, "two real identities share one herd"):
		return
	var saved: Dictionary = game.network.credentials.duplicate(true)
	var initial_ids := _ids(game.latest)
	monitoring = true
	process_frame.connect(_observe_prediction)
	for dog in ["mochi", "maple"]:
		game.network.command(dog, "stay")
		if not await _wait(func() -> bool: return _dog_matches(dog, "stay", str(game.network.credentials.player_id)), "first herder commands either shared dog"):
			return
		other.command(dog, "come")
		if not await _wait(func() -> bool: return _dog_matches(dog, "come", str(other.credentials.player_id)), "second herder calls either shared dog"):
			return
		other.command(dog, "go", Vector2(-44, 68))
		if not await _wait(func() -> bool: return _dog_matches(dog, "go", str(other.credentials.player_id)) and _dog_position(dog).distance_to(Vector2(-44, 68)) < 0.3, "shared dog actually reaches new-region Go endpoint"):
			return
		game.network.command(dog, "stay")
		if not await _wait(func() -> bool: return _dog_matches(dog, "stay", str(game.network.credentials.player_id)), "first human regains either shared dog's attention"):
			return
	if not await _near_tap(Vector2(-42, 66)):
		return
	var near_sequence: int = game.movement_seq
	if not await _wait(func() -> bool: return _own_seq() == near_sequence and _own_position().distance_to(Vector2(-42, 66)) < 0.3 and not game.moving, "ordinary height-aware tap walks beyond old small-world bounds"):
		return
	# Far point is deliberately beyond the current screen: use the real sender,
	# not a fake tap offscreen, and let main adopt the acknowledged new sequence.
	var far_target := Vector2.INF
	for candidate in [FAR, Vector2(-24, -40), Vector2(44, -36), Vector2(-51, -10)]:
		if _own_position().distance_to(candidate) > 70 and not navigation.visible(_own_position(), candidate) and not navigation.plan(_own_position(), candidate).is_empty():
			far_target = candidate
			break
	if not _check(far_target.is_finite(), "long-route fixture is genuinely occluded from the actual post-tap position"):
		return
	var accepted_seq: int = game.network.move_to(far_target)
	if not await _wait(func() -> bool: return _own_seq() == accepted_seq and game.movement_seq == accepted_seq and not _own_route().is_empty(), "real server retains a nonempty long-region route"):
		return
	await process_frame
	var lost_target := _own_position() + Vector2(6, 0)
	var lost_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(lost_target) - Vector3.UP * 0.03)
	var lost_hit: Vector3 = game.meadow.ground_at(lost_screen)
	if not _check(root.get_visible_rect().has_point(lost_screen) and lost_hit.is_finite() and Vector2(lost_hit.x, lost_hit.z).distance_to(lost_target) < 0.08 and game._pick_world_interaction(lost_screen).is_empty(), "closing-socket negative input is a genuine visible unobstructed world tap"):
		return
	game.network.socket.close()
	game._world_tap(lost_screen)
	if not _check(game.movement_seq == accepted_seq + 1 and game.network.seq == accepted_seq + 1 and game.moving, "real closing socket drops the next locally predicted world input"):
		return
	monitoring = false
	if not await _wait(func() -> bool: return not game.network.connected, "normal transport observes disconnect"):
		return
	if not await _wait(func() -> bool: return game.network.connected and not game.awaiting_authoritative_snapshot, "normal retry accepts authoritative reconnect snapshot"):
		return
	if not _check(_own_seq() == accepted_seq and game.movement_seq == accepted_seq and game.movement_target.distance_to(far_target) < 0.001 and game.network.credentials == saved, "reconnect restores accepted route and discards lost sequence without touching credentials"):
		return
	monitoring = true
	if not await _wait(func() -> bool: return _own_position().distance_to(far_target) < 0.3 and not game.moving, "retained full-region route reaches far destination after reconnect"):
		return
	var return_seq: int = game.network.move_to(CAMP)
	if not await _wait(func() -> bool: return _own_seq() == return_seq and _own_position().distance_to(CAMP) < 0.3 and not game.moving, "full authoritative return walk reaches camp through the same canonical region"):
		return
	if not _check(saw_predicted_motion and _ids(game.latest) == initial_ids and not game.practice_guide.visible and game.moment_label.text.is_empty() and game.latest.settled == 0 and not game.latest.gate_open, "real prediction and stable identities with no tutorial/completion/phantom-gate UI"):
		return
	monitoring = false
	game.network.disconnect_herd()
	other.disconnect_herd()
	game.queue_free()
	other.queue_free()
	await process_frame
	await process_frame
	if not _check(herd_digest == _digest("user://herd.cfg") and sound_digest == _digest("user://audio.cfg") and guide_digest == _digest("user://guide.cfg"), "real local preferences remain untouched"):
		return
	print("REGION_NETWORK_SMOKE_OK: %d checks; fresh isolated v7 HTTP/two WebSockets, real20:9 pick/prediction, shared dog callers/Go, dropped-input reconnect, full long-region outward/return routes and actual mesh grounding" % checks)
	quit(0)

func _near_tap(destination: Vector2) -> bool:
	await process_frame
	await process_frame
	var screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(destination) - Vector3.UP * 0.03)
	var ground: Vector3 = game.meadow.ground_at(screen)
	if not _check(root.get_visible_rect().has_point(screen) and ground.is_finite() and Vector2(ground.x, ground.z).distance_to(destination) < 0.08 and game._pick_world_interaction(screen).is_empty(), "actual camera picks nearby intended ground, not animal UI"):
		return false
	var sequence: int = game.network.seq
	game._world_tap(screen)
	return _check(game.movement_seq == sequence + 1 and game.moving, "ordinary world tap creates immediate local prediction")

func _dog_matches(id: String, command: String, caller: String) -> bool:
	for dog: Dictionary in other_snapshot.get("dogs", []):
		if dog.id == id:
			return dog.command == command and dog.get("caller", "") == caller
	return false

func _wait(condition: Callable, context: String) -> bool:
	# A 160m journey at the unchanged4m/s speed is intrinsically longer than the
	# tiny-diorama12.5s helper. This bound is v7-only, never changes old tests.
	for attempt in range(1400):
		if failed: return false
		if not error_message.is_empty():
			_fail(context + ": server/client reported an error")
			return false
		if not _safe_actors(): return false
		if condition.call():
			checks += 1
			return true
		await create_timer(0.05).timeout
	_fail(context + ": bounded70-second wait expired")
	return false

func _safe_actors() -> bool:
	if not monitoring: return true
	for actor: Dictionary in game.actors.values():
		var position: Vector3 = actor.node.position
		if not _check(position.is_finite() and navigation.contains(Vector2(position.x, position.z)) and absf(position.y - game.meadow.surface_height(position.x, position.z) - 0.03) < 0.001, "every actual actor remains inside the strict region on its indexed terrain mesh"):
			return false
	return true

func _observe_prediction() -> void:
	if not monitoring or not is_instance_valid(game) or not game.actors.has(game.local_id):
		previous_rendered = Vector2.INF
		return
	var position: Vector3 = game.actors[game.local_id].node.position
	var point := Vector2(position.x, position.z)
	if previous_rendered.is_finite() and not _check(navigation.visible(previous_rendered, point), "actual local frame-to-frame movement never crosses a region void"):
		return
	previous_rendered = point
	if game.moving and game.movement_seq > _own_seq() and point.distance_to(_own_position()) > 0.01:
		saw_predicted_motion = true
