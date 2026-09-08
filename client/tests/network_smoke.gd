extends SceneTree
## Uses an isolated development server; never run against a player's saved meadow.
## godot --headless --path client --script res://tests/network_smoke.gd -- --server=http://127.0.0.1:8791

const Connection = preload("res://scripts/network.gd")
var game: Node3D
var other: HerdConnection
var other_snapshot: Dictionary = {}
var error_message := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var endpoint := "http://127.0.0.1:8791"
	var landscape := "cactus"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
		elif argument.begins_with("--landscape="):
			landscape = argument.trim_prefix("--landscape=")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.display_name = "Smoke herder A"
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	game.network.create_herd(landscape)
	if not await _until(func() -> bool: return game.network.connected):
		_fail("first Godot HTTP creation/WebSocket authentication")
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.display_name = "Smoke herder B"
	other.snapshot_received.connect(func(snapshot: Dictionary) -> void: other_snapshot = snapshot)
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _until(func() -> bool: return other.connected and game.actors.size() == 14):
		_fail("second Godot client joins the same 14-actor world")
		return
	if game.latest.get("landscape") != landscape or other_snapshot.get("landscape") != landscape or game.selected_landscape != landscape:
		_fail("both clients display the creator's landscape")
		return
	var layout: Dictionary = game._default_layout(landscape)
	if not game._supported_layout(landscape, game.latest.get("layout", {})) or game.meadow.bridge_y != layout.bridge_y or game.meadow.gate_y != layout.gate_y:
		_fail("snapshot, terrain and prediction share the authoritative route")
		return
	game.network.seq = 50
	game.network.move_to(Vector2(-10, -1.5))
	if not await _until(func() -> bool: return _own_seq() == 51):
		_fail("server acknowledges sequenced Godot movement")
		return
	game.network.command("mochi", "stay")
	other.command("maple", "stay")
	if not await _until(func() -> bool: return _dog_command("mochi") == "stay" and _dog_command("maple") == "stay"):
		_fail("both herders issue commands")
		return
	other.command("mochi", "come")
	if not await _until(func() -> bool: return _dog_command("mochi") == "come"):
		_fail("second herder commands the shared first dog")
		return
	if landscape in ["larch", "orchard"]:
		var gate_y: float = layout.gate_y
		var gate_screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(6, gate_y)) + Vector3(0, 0.7, 0))
		game._world_tap(gate_screen)
		if not await _until(func() -> bool: return _own_position().distance_to(Vector2(5, gate_y)) < 0.3):
			_fail("touching distant offset gate routes the herder over the bridge")
			return
		gate_screen = game.meadow.camera.unproject_position(game._surface_position(Vector2(6, gate_y)) + Vector3(0, 0.7, 0))
		game._world_tap(gate_screen)
		if not await _until(func() -> bool: return game.meadow.gate_open and other_snapshot.get("gate_open", false)):
			_fail("nearby offset gate tap opens the same gate for both clients")
			return
		game.network.move_to(Vector2(11, 7))
		if not await _until(func() -> bool: return _own_position().distance_to(Vector2(11, 7)) < 0.3):
			_fail("herder reaches the rest pasture")
			return
		game.network.move_to(Vector2(-10, 0))
		if not await _until(func() -> bool: return _own_position().distance_to(Vector2(-10, 0)) < 0.3):
			_fail("return journey navigates the offset gate before the bridge")
			return
	var acknowledged_before_reconnect: int = _own_seq()
	game.network.disconnect_herd()
	await create_timer(0.15).timeout
	game.network.seq = 0
	game.network.reconnect()
	if not await _until(func() -> bool: return game.network.connected and game.network.seq >= acknowledged_before_reconnect):
		_fail("reconnect restores acknowledged input sequence")
		return
	game.network.move_to(Vector2(-11, 0))
	if not await _until(func() -> bool: return _own_seq() == acknowledged_before_reconnect + 1):
		_fail("movement is accepted after reconnect")
		return
	if not error_message.is_empty():
		_fail("unexpected server error")
		return
	game.network.disconnect_herd()
	other.disconnect_herd()
	print("CLIENT_NETWORK_SMOKE_OK: shared %s landscape/layout, HTTP invite/join, two authenticated WebSockets, 14 rendered actors, shared commands, movement, reconnect sequence" % landscape)
	quit(0)

func _until(condition: Callable) -> bool:
	for attempt in range(250):
		if condition.call():
			return true
		await create_timer(0.05).timeout
	return false

func _own_seq() -> int:
	for player: Dictionary in game.latest.get("players", []):
		if str(player.id) == game.local_id:
			return int(player.seq)
	return -1

func _own_position() -> Vector2:
	for player: Dictionary in game.latest.get("players", []):
		if str(player.id) == game.local_id:
			return Vector2(float(player.position.x), float(player.position.y))
	return Vector2.INF

func _dog_command(id: String) -> String:
	for dog: Dictionary in other_snapshot.get("dogs", []):
		if str(dog.id) == id:
			return str(dog.command)
	return ""

func _fail(context: String) -> void:
	push_error("CLIENT_NETWORK_SMOKE_FAILED: " + context + (" (" + error_message + ")" if not error_message.is_empty() else ""))
	quit(1)
