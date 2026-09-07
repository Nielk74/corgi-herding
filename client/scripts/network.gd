class_name HerdConnection
extends Node
## Small transport: HTTP invitations, authenticated WebSocket snapshots, reconnect.

signal snapshot_received(snapshot: Dictionary)
signal status_changed(text: String, connected: bool)
signal herd_joined(code: String)
signal request_failed(message: String)

const DEFAULT_SERVER := "http://127.0.0.1:8790"
const CONFIG_PATH := "user://herd.cfg"
var endpoint := DEFAULT_SERVER
var display_name := "Herder"
var credentials: Dictionary = {}
var connected := false
var socket: WebSocketPeer
var http: HTTPRequest
var retry_in := -1.0
var retry_count := 0
var authenticated := false
var was_open := false
var connecting_time := 0.0
var snapshot_age := 0.0
var seq := 0
var paused := false

func _ready() -> void:
	_load_config()
	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)

func configure(base_url: String, player_name: String) -> bool:
	var clean := base_url.strip_edges().trim_suffix("/")
	if not (clean.begins_with("http://") or clean.begins_with("https://")):
		request_failed.emit("Use an http:// or https:// server address.")
		return false
	if clean != endpoint:
		credentials = {}
	endpoint = clean
	display_name = player_name.strip_edges().left(24)
	if display_name.is_empty():
		display_name = "Herder"
	_save_config()
	return true

func create_herd() -> void:
	_request("/api/herds")

func join_herd(code: String) -> void:
	var clean := code.strip_edges().to_upper()
	var valid := clean.length() == 6
	for character in clean:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
			valid = false
	if not valid:
		request_failed.emit("Enter the invitation from your other herder.")
		return
	_request("/api/herds/" + clean.uri_encode() + "/join")

func has_saved_herd() -> bool:
	return credentials.has("code") and credentials.has("player_id") and credentials.has("token")

func reconnect() -> void:
	if not has_saved_herd():
		return
	paused = false
	retry_in = -1.0
	authenticated = false
	was_open = false
	connecting_time = 0.0
	if socket != null:
		socket.close()
	socket = WebSocketPeer.new()
	var ws_url := endpoint.replace("https://", "wss://").replace("http://", "ws://")
	var error := socket.connect_to_url(ws_url + "/api/herds/" + str(credentials.code) + "/ws")
	status_changed.emit("Finding your meadow…", false)
	if error != OK:
		_retry()

func disconnect_herd() -> void:
	paused = true
	connected = false
	retry_in = -1.0
	if socket != null:
		socket.close()
	socket = null
	status_changed.emit("Your meadow is saved", false)

func move_to(target: Vector2) -> int:
	seq += 1
	send({"type": "move", "seq": seq, "target": {"x": target.x, "y": target.y}})
	return seq

func command(dog_id: String, instruction: String, target := Vector2.ZERO) -> void:
	var message := {"type": "command", "dog_id": dog_id, "command": instruction}
	if instruction == "go":
		message["target"] = {"x": target.x, "y": target.y}
	send(message)

func interact(action: String, dog_id := "") -> void:
	send({"type": "interact", "action": action, "dog_id": dog_id})

func send(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func _request(path: String) -> void:
	status_changed.emit("Opening a little world…", false)
	var error := http.request(endpoint + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"name": display_name}))
	if error != OK:
		request_failed.emit("A request is already in progress. Try again in a moment.")

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Cannot reach this meadow. Check the server address and connection.")
		return
	if response_code < 200 or response_code >= 300:
		var message := "The meadow could not be opened (%d)." % response_code
		if parsed is Dictionary:
			message = str(parsed.get("error", parsed.get("message", message)))
		request_failed.emit(message)
		return
	if not parsed is Dictionary or not parsed.has("token") or not parsed.has("player_id") or not parsed.has("code"):
		request_failed.emit("This server speaks a different game protocol.")
		return
	credentials = {"code": str(parsed.code), "player_id": str(parsed.player_id), "token": str(parsed.token)}
	seq = 0
	_save_config()
	herd_joined.emit(str(credentials.code))
	reconnect()

func _process(delta: float) -> void:
	if paused:
		return
	if retry_in >= 0:
		retry_in -= delta
		if retry_in <= 0:
			reconnect()
		return
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		connecting_time += delta
		if connecting_time > 12:
			_retry()
	elif state == WebSocketPeer.STATE_OPEN:
		was_open = true
		if not authenticated:
			authenticated = true
			send({"type": "auth", "player_id": credentials.player_id, "token": credentials.token})
		while socket.get_available_packet_count() > 0:
			var message: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if not message is Dictionary:
				continue
			if message.get("type") == "snapshot":
				snapshot_age = 0.0
				if not connected:
					connected = true
					retry_count = 0
					status_changed.emit("Together in the meadow", true)
				snapshot_received.emit(message)
			elif message.get("type") == "error":
				request_failed.emit(str(message.get("message", "The meadow needs a moment.")))
		snapshot_age += delta
		if snapshot_age > 12:
			_retry()
	elif state == WebSocketPeer.STATE_CLOSED:
		# Invalid saved credentials must return to the invitation screen, not loop forever.
		if socket.get_close_code() == 1008 or socket.get_close_code() == 4001:
			paused = true
			connected = false
			credentials = {}
			_save_config()
			request_failed.emit("This invitation has expired. Start or join a meadow again.")
		else:
			_retry()

func _retry() -> void:
	connected = false
	retry_count += 1
	retry_in = minf(1.5 * pow(1.6, retry_count - 1), 15.0)
	snapshot_age = 0.0
	if socket != null:
		socket.close()
	socket = null
	status_changed.emit("Reconnecting… your animals are waiting", false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		disconnect_herd()
	elif what == NOTIFICATION_APPLICATION_RESUMED and has_saved_herd():
		reconnect()

func _load_config() -> void:
	endpoint = str(ProjectSettings.get_setting("corgi/server_url", DEFAULT_SERVER))
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		endpoint = str(config.get_value("connection", "endpoint", endpoint))
		display_name = str(config.get_value("connection", "name", "Herder"))
		credentials = config.get_value("connection", "credentials", {})

func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value("connection", "endpoint", endpoint)
	config.set_value("connection", "name", display_name)
	config.set_value("connection", "credentials", credentials)
	config.save(CONFIG_PATH)
