extends "res://tests/region_network_smoke.gd"
## Separate v8 HTTP/WS evidence; the inherited strict frame/grounding observer
## uses this recipe-specific navigation object, never the v7 canonical cache.
const Catalog = preload("res://scripts/region_catalog.gd")
const DRY_CAMP := Vector2(-44, 79)
const DRY_FAR := Vector2(32, -76)

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
	if not info is Dictionary or info.get("status") != "ok" or info.get("sessions", -1) != 0 or capability != 8:
		_fail("test server must advertise current capability8 and have zero existing herds")
		return
	herd_digest = _digest("user://herd.cfg")
	sound_digest = _digest("user://audio.cfg")
	guide_digest = _digest("user://guide.cfg")
	navigation = Region.new(Catalog.canonical("dry_wash"))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.display_name = "DryWash network A"
	game.soundscape.persist_preference = false
	game.soundscape.set_enabled(false)
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	root.content_scale_size = Vector2i(720, 1600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(720, 1600)
	for frame in range(3): await process_frame
	if not _check(root.size == Vector2i(720, 1600) and root.get_visible_rect().size == Vector2(720, 1600), "real physical and logical 20:9 portrait viewport"):
		return
	game.network.create_herd("dry_wash")
	if not await _wait(func() -> bool: return game.network.connected and game.had_snapshot, "v8 HTTP creation and accepted authenticated snapshot"):
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.display_name = "DryWash network B"
	other.snapshot_received.connect(func(snapshot: Dictionary) -> void: other_snapshot = snapshot)
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _wait(func() -> bool: return other.connected and game.actors.size() == 14 and other_snapshot.get("players", []).size() == 2, "real invited peer restores all fourteen actors"):
		return
	if not _check(game.network.advertised_layout_version == 8 and other.advertised_layout_version == 8 and game._supported_layout("dry_wash", game.latest.layout) and game._supported_layout("dry_wash", other_snapshot.layout), "both peers negotiate8 and receive the exact canonical immutable region"):
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
		other.command(dog, "go", Vector2(-40, 70))
		if not await _wait(func() -> bool: return _dog_matches(dog, "go", str(other.credentials.player_id)) and _dog_position(dog).distance_to(Vector2(-40, 70)) < 0.3, "shared dog actually reaches new-region Go endpoint"):
			return
		game.network.command(dog, "stay")
		if not await _wait(func() -> bool: return _dog_matches(dog, "stay", str(game.network.credentials.player_id)), "first human regains either shared dog's attention"):
			return
	other.move_to(Vector2(-42, 73))
	if not await _wait(func() -> bool: return _other_position().distance_to(Vector2(-42, 73)) < 0.3, "second herder actually walks in the same v8 world"):
		return
	if not await _near_tap(Vector2(-38, 71)):
		return
	var near_sequence: int = game.movement_seq
	if not await _wait(func() -> bool: return _own_seq() == near_sequence and _own_position().distance_to(Vector2(-38, 71)) < 0.3 and not game.moving, "ordinary height-aware tap walks beyond old small-world bounds"):
		return
	# Far point is deliberately beyond the current screen: use the real sender,
	# not a fake tap offscreen, and let main adopt the acknowledged new sequence.
	var far_target := Vector2.INF
	for candidate in [DRY_FAR, Vector2(-51, -57), Vector2(47, -5), Vector2(-48, -18)]:
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
	var return_seq: int = game.network.move_to(DRY_CAMP)
	if not await _wait(func() -> bool: return _own_seq() == return_seq and _own_position().distance_to(DRY_CAMP) < 0.3 and not game.moving, "full authoritative return walk reaches camp through the same canonical region"):
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
	print("DRY_WASH_NETWORK_SMOKE_OK: %d checks; fresh isolated v8 HTTP/two WebSockets, real20:9 pick/prediction, shared dog callers/Go, dropped-input reconnect, full long-region outward/return routes and actual mesh grounding" % checks)
	quit(0)
