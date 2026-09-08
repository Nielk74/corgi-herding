extends SceneTree
## Real scene/GUI plus a real loopback WebSocket write path. Snapshot payloads
## are authoritative-shaped fixtures, not a claim of live Go-server teaching.
## Only a unique local guide preference file is written; no external herd exists.

const Main = preload("res://main.tscn")
const Nav = preload("res://scripts/commons_navigation.gd")
const Preferences = preload("res://scripts/guide_preferences.gd")
const Guide = preload("res://scripts/practice_guide.gd")

class TestConnection:
	extends "res://scripts/network.gd"
	var fail_write := false
	var writes: Array[String] = []
	var requests: Array[Dictionary] = []
	func _write_text(text: String) -> Error:
		writes.append(text)
		return ERR_CONNECTION_ERROR if fail_write else super._write_text(text)
	func _request(path: String, extra: Dictionary = {}) -> void:
		requests.append({"path": path, "extra": extra.duplicate(true)})

var checks := 0
var failures := 0
var game: Node3D
var connection: TestConnection
var listener := TCPServer.new()
var peer: WebSocketPeer
var sent: Array[Dictionary] = []
var received_texts: Array[String] = []
var snapshot: Dictionary
var preference_path := ""
var fixture_endpoint := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var protected_before := _protected_hashes()
	preference_path = "user://guide-smoke-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	game = Main.instantiate()
	root.add_child(game)
	await _frames()
	game.set_process(false)
	game.meadow.set_process(false)
	game.soundscape.persist_preference = false
	game.soundscape.set_enabled(false)
	game.soundscape.set_process(false)
	game.network.free()
	connection = TestConnection.new()
	connection.persist_config = false
	game.add_child(connection)
	connection.set_process(false)
	game.network = connection
	connection.snapshot_received.connect(game._on_snapshot)
	connection.status_changed.connect(game._on_status)
	connection.request_failed.connect(game._on_error)
	connection.herd_joined.connect(game._on_herd_joined)
	connection.message_sent.connect(game._on_message_sent)
	connection.message_sent.connect(func(message: Dictionary, epoch: int) -> void: sent.append({"message": message.duplicate(true), "epoch": epoch}))
	game.practice_guide.preferences.config_path = preference_path
	# Main mirrors the transport's persistence choice. This test starts with
	# no persistence, then uses only a standalone preference object at this path.
	_check(listener.listen(0, "127.0.0.1") == OK, "test owns an ephemeral loopback-only listener")
	fixture_endpoint = "http://127.0.0.1:%d" % listener.get_local_port()
	connection.endpoint = fixture_endpoint
	await _viewport(Vector2i(720, 1280))
	await _socket()
	await _send_gate()
	_start("ABC123", "herder-a")
	_check(game.practice_guide.visible and game.practice_guide.tutorial.stage() == "walk", "first accepted practice receipt shows the optional walk guide")
	_check(game.bellflower_button.text == "Practice meadow", "welcome explicitly names the dedicated practice entry")
	await _real_actions()
	await _lifecycle()
	await _portrait_card_and_settings()
	await _contexts()
	await _preferences()
	for path: String in ["res://scripts/guide_preferences.gd.uid", "res://scripts/practice_guide.gd.uid", "res://tests/practice_guide_smoke.gd.uid"]:
		var uid := FileAccess.get_file_as_string(path).strip_edges()
		_check(ResourceUID.text_to_id(uid) > 0 and ResourceUID.id_to_text(ResourceUID.text_to_id(uid)) == uid, "new guide resource has a canonical persisted UID")
	if peer != null:
		peer.close()
	if connection.socket != null:
		connection.socket.close()
	listener.stop()
	game.queue_free()
	await _frames()
	if FileAccess.file_exists(preference_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(preference_path)) == OK, "remove only the test's unique preference file")
	_check(_protected_hashes() == protected_before, "real invitation, audio and guide files remain byte-identical")
	print("PRACTICE_GUIDE_SMOKE: %d checks, %d failures; real portrait GUI, successful/failed/closing loopback writes, canonical receipt gate, 20 focus/menu/reconnect cycles, both invited identities, separate bounded local preferences; no live-Go or Android visual claim" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PRACTICE_GUIDE_FAILED: " + message)

func _frames() -> void:
	await process_frame
	await process_frame

func _viewport(size: Vector2i) -> void:
	root.content_scale_size = size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = size
	await _frames()
	_check(root.size == size and root.get_visible_rect().size == Vector2(size), "actual physical and logical portrait aspect")
	game.meadow.fit_camera()
	await _frames()

func _socket() -> void:
	if peer != null:
		peer.close()
	if connection.socket != null:
		connection.socket.close()
	connection.socket = WebSocketPeer.new()
	_check(connection.socket.connect_to_url(fixture_endpoint.replace("http://", "ws://") + "/fixture") == OK, "real client loopback socket starts")
	peer = null
	for _index in 240:
		connection.socket.poll()
		if peer == null and listener.is_connection_available():
			peer = WebSocketPeer.new()
			_check(peer.accept_stream(listener.take_connection()) == OK, "test peer accepts only its own socket")
		if peer != null:
			peer.poll()
			if connection.socket.get_ready_state() == WebSocketPeer.STATE_OPEN and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				return
		await process_frame
	_check(false, "loopback handshake must finish within a bounded frame count")

func _received() -> Array:
	var result: Array = []
	received_texts.clear()
	for _index in 8:
		peer.poll()
		connection.socket.poll()
		while peer.get_available_packet_count() > 0:
			var text := peer.get_packet().get_string_from_utf8()
			received_texts.append(text)
			result.append(JSON.parse_string(text))
		# An uncapped headless frame can be much shorter than the loopback TCP
		# delayed-ACK interval. Wait on wall time, not eight nearly-zero frames.
		await create_timer(0.01).timeout
	return result

func _send_gate() -> void:
	connection.connection_epoch = 1
	connection.connected = true
	connection.paused = false
	connection.send({"type": "auth", "token": "fixture-not-a-credential", "player_id": "herder-a"})
	_check(sent.is_empty(), "auth secrets are never broadcast on the presentation signal")
	var auth_bytes: Array = await _received()
	_check(auth_bytes.size() == 1 and auth_bytes[0].get("type") == "auth", "loopback auth bytes are drained without entering presentation feedback")
	connection.move_to(Vector2(-4, 0))
	_check(sent.size() == 1 and sent[0].epoch == 1, "send_text OK emits exactly one current-epoch gameplay message")
	var received: Array = await _received()
	# JSON decode represents seq as float. Compare the actual serialized bytes,
	# not Dictionary equality between a native integer and its decoded float.
	_check(received.size() == 1 and received_texts[0] == JSON.stringify(sent[0].message), "emission corresponds exactly to bytes received by a real loopback peer")
	connection.fail_write = true
	connection.move_to(Vector2(-3, 0))
	_check(sent.size() == 1, "an open socket whose write fails does not emit message_sent")
	_check((await _received()).is_empty(), "injected transport write failure produces no peer bytes")
	connection.fail_write = false
	connection.socket.close()
	connection.command("mochi", "come")
	_check(sent.size() == 1, "closing socket cannot produce successful-emission feedback")
	connection.credentials = {"code": "ABC123", "player_id": "herder-a", "token": "fixture-not-a-credential"}
	connection.endpoint = "http://127.0.0.1:1"
	var prior_epoch := connection.connection_epoch
	connection.reconnect()
	connection.protocol_probe.cancel_request()
	_check(connection.connection_epoch == prior_epoch + 1 and not connection.connected, "production reconnect increases the transport epoch and drops connected state")
	connection.endpoint = fixture_endpoint
	await _socket()
	sent.clear()

func _point(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y}

func _fixture(code: String, local_id: String, tick: int = 10, landscape: String = "bellflower") -> Dictionary:
	var sheep: Array = []
	for index in 10:
		sheep.append({"id": "sheep-%d" % index, "position": _point(9 + (index % 3) * 0.2, -6 + (index / 3) * 0.2), "velocity": _point(0, 0), "state": "grazing", "group": 0})
	var other := "herder-b" if local_id == "herder-a" else "herder-a"
	return JSON.parse_string(JSON.stringify({"type": "snapshot", "code": code, "landscape": landscape, "layout": game._default_layout(landscape), "tick": tick, "gate_open": false, "settled": 0,
		"players": [{"id": local_id, "name": "Herder", "position": _point(-5, 0), "target": _point(-5, 0), "seq": 0, "state": "idle", "connected": true}, {"id": other, "name": "Partner", "position": _point(-8, 3), "target": _point(-8, 3), "seq": 0, "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "name": "Mochi", "position": _point(-6, 1.5), "target": _point(-6, 1.5), "state": "stay", "command": "stay"}, {"id": "maple", "name": "Maple", "position": _point(-7, -2), "target": _point(-7, -2), "state": "stay", "command": "stay"}], "sheep": sheep}))

func _start(code: String, local_id: String, landscape: String = "bellflower") -> void:
	connection.connection_epoch += 1
	connection.connected = true
	connection.paused = false
	connection.seq = 0
	connection.update_required = false
	connection.credentials = {"code": code, "player_id": local_id, "token": "fixture-not-a-credential"}
	game.preview_mode = false
	game._on_herd_joined(code)
	snapshot = _fixture(code, local_id, 10, landscape)
	connection.snapshot_received.emit(snapshot)

func _receipt() -> void:
	snapshot = snapshot.duplicate(true)
	snapshot.tick = float(snapshot.tick) + 1
	connection.snapshot_received.emit(snapshot)

func _actor(id: String, category: String = "players") -> Dictionary:
	for value: Dictionary in snapshot[category]:
		if value.id == id:
			return value
	return {}

func _press(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func _click(position: Vector2) -> void:
	_press(position, true)
	_press(position, false)
	await _frames()

func _find_button(text: String) -> Button:
	for node in game.ui.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func _real_actions() -> void:
	await _frames()
	var target := Vector2(-1.5, 0)
	var screen: Vector2 = game.meadow.camera.unproject_position(game._surface_position(target))
	_check(not game.dog_drag.over_ui(screen) and game._pick_world_interaction(screen).is_empty(), "real walk fixture is dry grass outside UI/actor targets")
	var before := sent.size()
	await _click(screen)
	_check(sent.size() == before + 1 and sent.back().message.type == "move", "actual world tap sends one normal movement message")
	_check(game.practice_guide.tutorial.stage() == "walk" and game.practice_guide.tutorial.debug_state().pending, "successful emission arms but never completes walking")
	var message: Dictionary = sent.back().message
	var player := _actor(game.local_id)
	player.seq = message.seq
	player.target = message.target.duplicate()
	player.state = "walking"
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "walk", "accepted target echo without actual arrival cannot advance guide")
	player = _actor(game.local_id)
	player.position = message.target.duplicate()
	player.state = "idle"
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "select", "authoritative local arrival advances the real scene guide")
	var dog_screen: Vector2 = game.meadow.camera.unproject_position(game.actors.mochi.node.position + Vector3(0, 0.5, 0))
	await _click(dog_screen)
	_check(game.selected_dog == "mochi" and game.command_panel.visible, "actual dog tap retains stable contextual controls")
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "come", "actual local selection reaches guide through main")
	before = sent.size()
	await _click(_find_button("Come").get_global_rect().get_center())
	_check(sent.size() == before + 1 and sent.back().message == {"type": "command", "dog_id": "mochi", "command": "come"}, "actual Come control emits exactly the selected dog command")
	var dog := _actor("mochi", "dogs")
	player = _actor(game.local_id)
	dog.command = "come"
	dog.state = "attentive"
	dog.caller = "herder-b"
	dog.position = _point(float(player.position.x) + 0.8, player.position.y)
	dog.target = player.position.duplicate()
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "come", "partner caller cannot complete the local UI lesson")
	dog = _actor("mochi", "dogs")
	dog.caller = game.local_id
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "stay", "selected dog with actual local caller and position completes Come")
	game._select_dog("mochi")
	await _frames()
	connection.fail_write = true
	await _click(_find_button("Stay").get_global_rect().get_center())
	_check(not game.practice_guide.tutorial.debug_state().pending, "optimistic button animation cannot arm a failed socket write")
	connection.fail_write = false
	dog = _actor("mochi", "dogs")
	dog.command = "stay"
	dog.state = "stay"
	dog.target = dog.position.duplicate()
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "stay", "unarmed desired state cannot complete Stay")
	game._select_dog("mochi")
	await _frames()
	await _click(_find_button("Stay").get_global_rect().get_center())
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "place", "fresh repeated Stay result works without inventing a packet ACK")
	await _frames()
	var drag_start: Vector2 = game.meadow.camera.unproject_position(game.actors.maple.node.position + Vector3(0, 0.5, 0))
	var drag_end: Vector2 = game.meadow.camera.unproject_position(game._surface_position(Vector2(0, 0)))
	_check(game._pick_world_interaction(drag_start) == "dog:maple" and not game.dog_drag.over_ui(drag_end), "placement fixture targets the other corgi and real dry grass")
	before = sent.size()
	_press(drag_start, true)
	var cancelled_motion := InputEventMouseMotion.new()
	cancelled_motion.position = game.practice_guide.skip_button.get_global_rect().get_center()
	cancelled_motion.global_position = cancelled_motion.position
	cancelled_motion.relative = cancelled_motion.position - drag_start
	cancelled_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(cancelled_motion, true)
	_press(cancelled_motion.position, false)
	await _frames()
	_check(sent.size() == before and game.practice_guide.tutorial.stage() == "place" and not game.practice_guide.tutorial.debug_state().pending, "drag release over Skip step cancels without a command or accidental guide advancement")
	_press(drag_start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = drag_end
	motion.global_position = drag_end
	motion.relative = drag_end - drag_start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_press(drag_end, false)
	await _frames()
	_check(sent.size() == before + 1 and sent.back().message.type == "command" and sent.back().message.command == "go" and sent.back().message.dog_id == "maple", "actual direct drag sends exactly one Go for the other shared corgi")
	_check(game.practice_guide.tutorial.stage() == "place" and game.practice_guide.tutorial.debug_state().pending and game.practice_guide.tutorial.debug_state().selected_dog == "maple", "drag selection and successful wire emission arm placement without completing it")
	dog = _actor("maple", "dogs")
	dog.command = "go"
	dog.caller = game.local_id
	dog.state = "attentive"
	dog.target = sent.back().message.target.duplicate()
	dog.position = dog.target.duplicate()
	_receipt()
	_check(game.practice_guide.tutorial.stage() == "pressure", "only the accepted arrived dog completes the direct-drag lesson")
	await _received()

func _lifecycle() -> void:
	# Optional manual steps prepare a repeated interruption fixture; they are
	# deliberately not counted as observed player learning.
	game.practice_guide.restart_for(connection.endpoint, str(connection.credentials.code), game.local_id)
	_receipt()
	for _index in 4:
		game.practice_guide.tutorial.skip_current_lesson()
	for cycle in 20:
		var guide: PanelContainer = game.practice_guide
		game._select_dog("mochi")
		connection.command("mochi", "go", Vector2(-2, -1))
		_check(guide.tutorial.debug_state().pending, "current local Go can arm before lifecycle boundary")
		var old_tick: int = int(snapshot.tick)
		var old_epoch := connection.connection_epoch
		if cycle % 4 == 0:
			guide.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif cycle % 4 == 1:
			guide.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		elif cycle % 4 == 2:
			game._open_settings()
		else:
			connection.connected = false
			game._on_status("Fixture dropped", false)
		_check(not guide.visible and not guide.tutorial.debug_state().pending and not guide.tutorial.debug_state().fresh, "focus/pause/menu/disconnect closes freshness and pending evidence")
		_receipt()
		_check(not guide.visible and not guide.tutorial.debug_state().fresh, "receipts while lifecycle gate is closed cannot arm hints")
		if cycle % 4 == 0:
			guide.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		elif cycle % 4 == 1:
			guide.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		else:
			connection.connection_epoch += 1
			connection.connected = true
			connection.paused = false
			game._on_herd_joined(str(connection.credentials.code))
			await _socket()
		_check(not guide.visible, "gate reopening alone never feeds cached latest")
		_receipt()
		_check(guide.visible and guide.tutorial.stage() == "place" and not guide.tutorial.debug_state().pending, "first accepted reopened receipt is baseline only")
		_check(not guide.record_message({"type": "command", "dog_id": "mochi", "command": "go", "target": _point(-2, -1)}, old_epoch) if connection.connection_epoch != old_epoch else true, "old transport messages cannot arm a replacement connection")
		var duplicate := snapshot.duplicate(true)
		duplicate.tick = old_tick
		connection.snapshot_received.emit(duplicate)
		_check(guide.tutorial.stage() == "place" and not guide.tutorial.debug_state().pending, "old receipt cannot replay completion after gate baseline")
		# main may display an old fixture receipt; restore monotonic source below.
		_receipt()
		await _received()
	var current_stage: String = game.practice_guide.tutorial.stage()
	var bad := snapshot.duplicate(true)
	bad.tick += 100
	bad.layout.commons.corridors.append([3, 4])
	connection.snapshot_received.emit(bad)
	_check(connection.update_required and game.welcome.visible and not game.practice_guide.visible, "noncanonical layout is rejected before the guide and returns safely to settings")
	_check(game.practice_guide.tutorial.stage() == current_stage and not game.practice_guide.tutorial.debug_state().fresh, "invalid high-tick world never reaches tutorial evidence")
	connection.update_required = false
	connection.connection_epoch += 1
	connection.connected = true
	connection.paused = false
	game._on_herd_joined(str(connection.credentials.code))
	await _socket()
	_receipt()

func _portrait_card_and_settings() -> void:
	snapshot.players[1].connected = false # Keep the invite row visible: worst-case HUD height.
	for viewport: Vector2i in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _viewport(viewport)
		game.practice_guide.restart_for(connection.endpoint, str(connection.credentials.code), game.local_id)
		_receipt()
		var area := Rect2(Vector2.ZERO, Vector2(viewport))
		while game.practice_guide.tutorial.stage() != "freeplay":
			await _frames()
			var card: Rect2 = game.practice_guide.get_global_rect()
			_check(game.practice_guide.is_visible_in_tree() and area.encloses(card) and card.size.y <= 225, "every lesson card wraps inside the actual portrait and stays compact")
			for control: Control in [game.practice_guide.instruction_label, game.practice_guide.why_label, game.practice_guide.skip_button, game.practice_guide.hide_button]:
				_check(card.encloses(control.get_global_rect()), "all guide text/actions stay inside the opaque card")
			_check(game.practice_guide.skip_button.size.y >= 64 and game.practice_guide.hide_button.size.y >= 64, "optional guide actions retain phone-sized targets")
			game._select_dog("mochi")
			await _frames()
			_check(game.command_panel.get_global_rect().position.y - card.end.y >= 350, "guide leaves a substantial visible world above unchanged dog controls")
			var sent_before := sent.size()
			var sequence := connection.seq
			await _click(game.practice_guide.instruction_label.get_global_rect().get_center())
			_check(sent.size() == sent_before and connection.seq == sequence, "guide body consumes taps instead of walking the herder behind it")
			await _click(game.practice_guide.skip_button.get_global_rect().get_center())
			_check(sent.size() == sent_before, "Skip step never emits a game command")
		_check(not game.practice_guide.visible, "freeplay removes the guide without a permanent completion display")
		game._open_settings()
		game.endpoint_input.show()
		await _frames()
		_check(game.restart_guide_button.visible, "known practice herd exposes Restart guide in settings")
		for control: Control in [game.bellflower_button, game.resume_button, game.endpoint_input, game.sound_button, game.restart_guide_button, _find_button("Server address")]:
			_check(control.is_visible_in_tree() and area.encloses(control.get_global_rect()), "expanded saved-herd settings including restart fit actual portrait")
		_check(game.sound_button.size.y >= 64 and game.restart_guide_button.size.y >= 64 and _find_button("Server address").size.y >= 64, "all settings row actions remain phone-sized")
		await _click(game.restart_guide_button.get_global_rect().get_center())
		_check(not game.practice_guide.preferences.choice(game.practice_guide.context_key).completed and not game.practice_guide.visible, "settings restart resets choice without displaying a stale gameplay hint")
		await _frames()
		_check(area.encloses(game.endpoint_input.get_global_rect()) and area.encloses(game.menu_error.get_global_rect()), "restart explanation also fits the fully expanded saved-herd menu")
		connection.connection_epoch += 1
		connection.connected = true
		connection.paused = false
		game._on_herd_joined(str(connection.credentials.code))
		await _socket()
		_receipt()
		_check(game.practice_guide.visible and game.practice_guide.tutorial.stage() == "walk", "guide begins on the next accepted Return receipt")
		await _frames()
		await _click(game.practice_guide.hide_button.get_global_rect().get_center())
		_check(not game.practice_guide.visible and game.practice_guide.preferences.choice(game.practice_guide.context_key).hidden, "actual Hide guide control saves only the local preference")
		game.practice_guide.restart_for(connection.endpoint, str(connection.credentials.code), game.local_id)
		_receipt()

func _contexts() -> void:
	var first_key: String = game.practice_guide.context_key
	game.practice_guide.tutorial.skip()
	_start("ABC123", "herder-b")
	_check(game.practice_guide.context_key != first_key and game.practice_guide.visible, "invited peer on the same herd gets their own first-visit guide")
	_start("ABC123", "herder-b", "cactus")
	game._open_settings()
	_check(not game.practice_guide.visible and not game.restart_guide_button.visible, "a confirmed non-practice landscape suppresses guide actions even for a previously known identity")
	for landscape: String in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper"]:
		_start("DEF456", "herder-a", landscape)
		_check(not game.practice_guide.visible and not game.practice_guide.tutorial.debug_state().enabled, "guide remains disabled outside dedicated practice: " + landscape)
		game._open_settings()
		_check(not game.restart_guide_button.visible, "non-practice herd does not gain a permanent guide action")
	game.preview_mode = true
	game._select_landscape("bellflower")
	game._show_preview()
	_check(not game.practice_guide.visible, "non-network art preview cannot teach or write progression")
	game.preview_mode = false
	game._open_settings()
	game._set_busy(false)
	connection.credentials.clear()
	game.endpoint_input.text = fixture_endpoint
	game.name_input.text = "Practice fixture"
	await _frames()
	await _click(game.bellflower_button.get_global_rect().get_center())
	_check(game.selected_landscape == "bellflower" and game.world_layout == Nav.layout(), "Practice entry selects canonical v6 and no other terrain")
	await _click(game.create_button.get_global_rect().get_center())
	_check(connection.requests == [{"path": "/api/herds", "extra": {"landscape": "bellflower"}}], "ordinary Start creates the selected dedicated practice meadow")
	game._set_busy(false)

func _preferences() -> void:
	var prefs := Preferences.new()
	prefs.config_path = preference_path
	var key: String = Preferences.herd_key(fixture_endpoint, "ABC123", "herder-a")
	_check(not prefs.known(key) and prefs.choice(key) == {"hidden": false, "completed": false}, "new local herd defaults to guide on")
	prefs.remember(key, true, false)
	var saved := FileAccess.get_file_as_string(preference_path)
	_check(not saved.contains("ABC123") and not saved.contains("herder-a") and not saved.contains(fixture_endpoint) and not saved.contains("token"), "guide file stores only hashed identity and hidden/completed flags, never credentials")
	var restored := Preferences.new()
	restored.config_path = preference_path
	_check(restored.choice(key) == {"hidden": true, "completed": false}, "hide preference survives a new process-style preference instance")
	var rig := Guide.new()
	rig.preferences.config_path = preference_path
	root.add_child(rig)
	rig.bind_herd(fixture_endpoint, "ABC123", "herder-a", "bellflower")
	rig.set_gameplay_gate(1, true)
	_check(not rig.observe_snapshot(_fixture("ABC123", "herder-a"), 1) and not rig.visible, "reloaded hidden guide never arms from a fresh snapshot")
	rig.restart_for(fixture_endpoint, "ABC123", "herder-a")
	_check(rig.observe_snapshot(_fixture("ABC123", "herder-a", 11), 1) and rig.visible and rig.tutorial.stage() == "walk", "explicit restart restores learning without fake transition/action replay")
	for _index in 8:
		rig.tutorial.skip_current_lesson()
	_check(not rig.visible and rig.preferences.choice(key) == {"hidden": false, "completed": true}, "completion persists only a local completed flag")
	rig.queue_free()
	await _frames()
	var reloaded := Preferences.new()
	reloaded.config_path = preference_path
	_check(reloaded.choice(key).completed, "completed preference survives reload")
	for index in 150:
		reloaded.remember(Preferences.herd_key(fixture_endpoint, "fixture-%d" % index, "herder-a"), false, false)
	var config := ConfigFile.new()
	_check(config.load(preference_path) == OK and config.get_section_keys("practice").size() == Preferences.MAX_HERDS, "local herd preferences have a fixed bounded inventory")
	var invalid_key := "not-a-private-key"
	reloaded.remember(invalid_key, true, true)
	_check(not reloaded.known(invalid_key), "invalid preference keys cannot create arbitrary config sections")

func _protected_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["user://herd.cfg", "user://audio.cfg", "user://guide.cfg"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result
