extends SceneTree
## Real authoritative windfall behavior; use only an isolated development server.

const Connection = preload("res://scripts/network.gd")
var game: Node3D
var other: HerdConnection
var previous_progress: Dictionary = {}
var error_message := ""
var tracked_sheep := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var endpoint := "http://127.0.0.1:8791"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.network.persist_config = false
	game.network.credentials = {}
	game.network.endpoint = endpoint
	game.network.request_failed.connect(func(message: String) -> void: error_message = message)
	game.network.snapshot_received.connect(_audit_snapshot)
	game.network.create_herd("orchard")
	if not await _until(func() -> bool: return game.network.connected):
		_fail("create an authoritative orchard")
		return
	other = Connection.new()
	other.persist_config = false
	root.add_child(other)
	other.endpoint = endpoint
	other.request_failed.connect(func(message: String) -> void: error_message = message)
	other.join_herd(str(game.network.credentials.code))
	if not await _until(func() -> bool: return other.connected and game.actors.size() == 14):
		_fail("join the same orchard")
		return
	game.network.move_to(Vector2(-14, 3))
	other.move_to(Vector2(-14, -3))
	game.network.command("mochi", "go", Vector2(-15, -9))
	other.command("maple", "go", Vector2(-15, 9))
	if not await _until(func() -> bool: return not _nibbler().is_empty()):
		_fail("calm sheep discover the windfall without a quest or player command")
		return
	tracked_sheep = str(_nibbler().id)
	var progress_at_disconnect: int = int(_sheep(tracked_sheep).forage.remaining_ticks)
	var credentials: Dictionary = game.network.credentials.duplicate(true)
	game.network.disconnect_herd()
	await create_timer(0.2).timeout
	game.network.reconnect()
	if not await _until(func() -> bool: return game.network.connected):
		_fail("reconnect during a sheep's snack")
		return
	if game.network.credentials != credentials or _sheep(tracked_sheep).is_empty() or int(_sheep(tracked_sheep).forage.remaining_ticks) > progress_at_disconnect:
		_fail("reconnection must retain sheep identity and completed snack progress")
		return
	if not await _until(func() -> bool: return _satiated_count() == 2):
		_fail("both sheep finish on their own and return to ordinary behavior")
		return
	var finished_ids: Array = previous_progress.keys()
	await create_timer(5.0).timeout
	if previous_progress.keys() != finished_ids or _satiated_count() != 2 or game.command_panel.visible or game.sit_button.visible:
		_fail("windfall stays bounded to two sheep without repeat grind or controls")
		return
	if not error_message.is_empty():
		_fail(error_message)
		return
	game.network.disconnect_herd()
	other.disconnect_herd()
	print("FORAGE_NETWORK_SMOKE_OK: two clients, at most two curious sheep, server-owned nibbling, monotonic progress through reconnect, self-resolving detour, no extra controls")
	quit(0)

func _audit_snapshot(snapshot: Dictionary) -> void:
	var assigned := 0
	for sheep: Dictionary in snapshot.get("sheep", []):
		if not sheep.has("forage"):
			continue
		assigned += 1
		var forage: Dictionary = sheep.forage
		var remaining := int(forage.remaining_ticks)
		if forage.zone_id != "windfall" or remaining < 0 or remaining > 80 or bool(forage.satiated) != (remaining == 0):
			error_message = "invalid forage snapshot"
		if previous_progress.has(sheep.id) and remaining > int(previous_progress[sheep.id]):
			error_message = "snack progress reset"
		previous_progress[sheep.id] = remaining
	if assigned > 2:
		error_message = "more than two sheep distracted"

func _nibbler() -> Dictionary:
	for sheep: Dictionary in game.latest.get("sheep", []):
		if sheep.state == "nibbling":
			return sheep
	return {}

func _sheep(id: String) -> Dictionary:
	for sheep: Dictionary in game.latest.get("sheep", []):
		if str(sheep.id) == id:
			return sheep
	return {}

func _satiated_count() -> int:
	var count := 0
	for sheep: Dictionary in game.latest.get("sheep", []):
		if sheep.has("forage") and sheep.forage.satiated and sheep.state not in ["foraging", "nibbling"]:
			count += 1
	return count

func _until(condition: Callable) -> bool:
	for attempt in range(800):
		if not error_message.is_empty():
			return false
		if condition.call():
			return true
		await create_timer(0.05).timeout
	return false

func _fail(message: String) -> void:
	push_error("FORAGE_NETWORK_SMOKE_FAILED: " + message)
	quit(1)
