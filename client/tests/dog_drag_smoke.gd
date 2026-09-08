extends SceneTree
## Real GUI/world dispatch, including native touch + Godot mouse emulation.

class RecordingConnection:
	extends "res://scripts/network.gd"
	var sent: Array[Dictionary] = []
	func send(message: Dictionary) -> void:
		sent.append(message.duplicate(true))

class RecordingMeadow:
	extends "res://scripts/meadow.gd"
	var destination_calls := 0
	var last_destination := Vector3.INF
	func mark_destination(point: Vector3) -> void:
		destination_calls += 1
		last_destination = point
		super.mark_destination(point)

var game
var recorder: RecordingConnection
var checks := 0
var failures := 0
var tick := 0
var gesture_events: Array = []
var gui_activations := 0
var old_mouse_emulation := false
var old_touch_emulation := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var herd_before := _digest("user://herd.cfg")
	var audio_before := _digest("user://audio.cfg")
	old_mouse_emulation = Input.is_emulating_mouse_from_touch()
	old_touch_emulation = Input.is_emulating_touch_from_mouse()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.meadow.free()
	game.meadow = RecordingMeadow.new()
	game.add_child(game.meadow)
	game.meadow.set_process(false)
	game.dog_drag.set_process(false)
	game.network.free()
	recorder = RecordingConnection.new()
	recorder.persist_config = false
	game.add_child(recorder)
	recorder.set_process(false)
	recorder.status_changed.connect(game._on_status)
	game.network = recorder
	game.dog_drag.gesture_event.connect(func(event_name: String, id: String, point: Vector2) -> void: gesture_events.append([event_name, id, point]))
	game.preview_mode = true
	game._show_preview()
	game.preview_mode = false
	for size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = size
		await _layout()
		_check(root.size == size and root.get_visible_rect().size == Vector2(size), "Matching physical and logical portrait viewports")
		for mode in ["mouse", "native", "mouse_emulates_touch"]:
			_configure_input(mode)
			for dog in ["mochi", "maple"]:
				await _fixture()
				var start := _dog_screen(dog)
				_press(mode, start, true)
				_check(game.command_panel.visible and game.selected_dog == dog and game.dog_drag.armed, "Dog press keeps its existing contextual menu")
				_motion(mode, start + Vector2(5, 2), start)
				_press(mode, start + Vector2(5, 2), false)
				_check(recorder.sent.is_empty() and game.command_panel.visible and game.pet_button.visible and not game.dog_drag.armed, "Small tap motion retains stable Come/Stay/Go/Pet, without a command")
				await _fixture()
				start = _dog_screen(dog)
				var target := _ground_screen(Vector2(-7, -5))
				_press(mode, start, true)
				_motion(mode, target, start)
				_check(game.dog_drag.dragging and game.dog_drag.marker.visible and not game.command_panel.visible, "Direct drag shows only its contextual ground preview")
				_check(game.dog_drag.marker_material.albedo_color == game.dog_drag.DOG_COLORS[dog], "Preview matches the selected dog's collar color")
				_check(is_equal_approx(game.dog_drag.marker.mesh.outer_radius, 0.80) and is_equal_approx(game.dog_drag.marker.mesh.inner_radius, 0.68), "Preview remains visible around the thumb without a permanent control")
				_check(recorder.sent.is_empty() and not game.moving, "Dragging an idle dog pointer cannot start herder movement or issue early Go")
				_check(absf(game.dog_drag.marker.position.y - game.meadow.surface_height(game.dog_drag.target.x, game.dog_drag.target.z) - 0.13) < 0.0001, "Preview is grounded on the actual terrain")
				_press(mode, target, false)
				_assert_one_go(dog, Vector2(-7, -5), mode)
				_check(not game.dog_drag.marker.visible and not game.dog_drag.armed and not game.command_panel.visible, "Release returns to the uncluttered meadow")
				_press(mode, target, false)
				_check(recorder.sent.size() == 1 and game.meadow.destination_calls == 1, "Duplicate release cannot issue a second Go or destination marker")
				_check(gesture_events.size() == 2 and gesture_events[0][0] == "started" and gesture_events[1][0] == "sent", "Tutorial hook emits one start and one sent Go request, not an authoritative confirmation")
			await _gui_release(mode)
	await _cancellations()
	await _existing_walk()
	await _release_revalidation()
	await _terrain_validation()
	Input.set_emulate_mouse_from_touch(old_mouse_emulation)
	Input.set_emulate_touch_from_mouse(old_touch_emulation)
	game.queue_free()
	await _layout()
	_check(_digest("user://herd.cfg") == herd_before and _digest("user://audio.cfg") == audio_before, "Gesture tests preserve invitation and audio preference files")
	print("DOG_DRAG_SMOKE: %d checks / %d failures; both dogs and portrait aspects; real mouse/native/synthetic dispatch, stable taps, one-shot Go, GUI cancellation, lifecycle and missing actors, canonical targets, accepted-walk preservation" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(landscape := "alpine") -> void:
	game._close_controls()
	recorder.connected = true
	recorder.paused = false
	recorder.credentials = {"code": "TEST", "player_id": "p1"}
	game.local_id = "p1"
	game.welcome.hide()
	game.hud.show()
	game.moving = false
	game.awaiting_authoritative_snapshot = true
	tick += 1
	var snapshot := {"tick": tick, "landscape": landscape, "layout": game._default_layout(landscape), "gate_open": false, "settled": 0,
		"players": [{"id": "p1", "position": {"x": -10.0, "y": 0.0}, "state": "idle", "connected": true, "seq": tick}],
		"dogs": [{"id": "mochi", "position": {"x": -8.2, "y": -2.0}, "state": "idle"}, {"id": "maple", "position": {"x": -8.2, "y": 1.0}, "state": "idle"}], "sheep": []}
	game._on_snapshot(snapshot)
	game._process(1.0)
	game.meadow._process(0.0)
	await _layout()
	recorder.sent.clear()
	gesture_events.clear()
	game.meadow.destination_calls = 0
	game.meadow.last_destination = Vector3.INF
	game.meadow.destination.hide()

func _gui_release(mode: String) -> void:
	await _fixture()
	var button := Button.new()
	button.text = "Test GUI target"
	button.position = Vector2(270, 380)
	button.size = Vector2(190, 70)
	button.pressed.connect(func() -> void: gui_activations += 1)
	game.ui.add_child(button)
	await _layout()
	var center := button.get_global_rect().get_center()
	var start := _dog_screen("mochi")
	var before := gui_activations
	_press(mode, start, true)
	_motion(mode, center, start)
	_check(game.dog_drag.dragging and not game.dog_drag.marker.visible, "GUI is never a dog destination preview")
	_press(mode, center, false)
	_check(recorder.sent.is_empty() and gui_activations == before and not game.dog_drag.armed and game.meadow.destination_calls == 0, "Release over GUI cancels without activating its button, herder movement or destination feedback")
	_press(mode, center, true)
	_press(mode, center, false)
	_check(gui_activations == before + 1 and recorder.sent.is_empty(), "Positive GUI tap still works exactly once, including native mouse emulation")
	button.queue_free()
	await _layout()

func _cancellations() -> void:
	for mode in ["mouse", "native"]:
		_configure_input(mode)
		for cause in ["invalid", "menu", "escape", "disconnect", "focus", "background", "missing_dog", "missing_player", "second_touch", "pointer_cancel", "landscape", "fresh_snapshot"]:
			await _fixture()
			var start := _dog_screen("mochi")
			var target := _ground_screen(Vector2(-7, -5))
			_press(mode, start, true)
			_motion(mode, target, start)
			_check(game.dog_drag.marker.visible, "Cancellation fixture must first show a valid target")
			match cause:
				"invalid":
					target = _ground_screen(Vector2(0, 5))
					_motion(mode, target, start)
					_check(not game.dog_drag.marker.visible, "Water hides target feedback rather than retaining a stale valid point")
				"menu": game._open_settings()
				"escape":
					var key := InputEventKey.new()
					key.keycode = KEY_ESCAPE
					key.pressed = true
					root.push_input(key, true)
					_check(game.hud.visible and not game.welcome.visible, "Back/Escape cancels the active gesture without opening a new menu")
				"disconnect":
					recorder.connected = false
					game._on_status("Reconnecting", false)
				"focus": game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
				"background": game.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				"missing_dog":
					_remove_snapshot_actor("dogs", "mochi")
					game.dog_drag._process(0.0)
				"missing_player":
					_remove_snapshot_actor("players", "p1")
					game.dog_drag._process(0.0)
				"second_touch":
					var other := InputEventScreenTouch.new()
					other.index = 9
					other.position = target
					other.pressed = true
					root.push_input(other, true)
				"pointer_cancel": _press(mode, target, false, true)
				"landscape": game._select_landscape("cactus")
				"fresh_snapshot":
					game.awaiting_authoritative_snapshot = true
					game.dog_drag._process(0.0)
			_press(mode, target, false)
			_check(recorder.sent.is_empty() and not game.dog_drag.armed and not game.dog_drag.marker.visible and game.meadow.destination_calls == 0, cause + " cancels without issuing any command or destination feedback")
			if cause == "focus":
				game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			if cause == "background":
				# No real reconnect request: this recording fixture has no transport.
				recorder.resume_after_background = false
				game.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
			_press(mode, target, false)
			_check(recorder.sent.is_empty(), cause + " cannot replay a stale release after reopening gates")
		await _fixture()
		# An invalid transient point is not a command; dragging across the river
		# may still end on a valid bank, routed by the authoritative server.
		var start := _dog_screen("mochi")
		_press(mode, start, true)
		_motion(mode, _ground_screen(Vector2(0, 5)), start)
		_press(mode, _ground_screen(Vector2(-7, -5)), false)
		_assert_one_go("mochi", Vector2(-7, -5), "valid final point after invalid transit")

func _remove_snapshot_actor(collection: String, id: String) -> void:
	var snapshot: Dictionary = game.latest.duplicate(true)
	tick += 1
	snapshot.tick = tick
	snapshot[collection] = snapshot[collection].filter(func(actor: Dictionary) -> bool: return actor.id != id)
	game._on_snapshot(snapshot)

func _existing_walk() -> void:
	await _fixture()
	_configure_input("mouse")
	game.moving = true
	game.movement_target = Vector2(-4, -3)
	game.movement_seq = recorder.seq
	var old_seq: int = recorder.seq
	var start := _dog_screen("maple")
	var target := _ground_screen(Vector2(-7, -5))
	_press("mouse", start, true)
	_motion("mouse", target, start)
	_press("mouse", target, false)
	_assert_one_go("maple", Vector2(-7, -5), "existing accepted walk")
	_check(game.moving and game.movement_target == Vector2(-4, -3) and recorder.seq == old_seq and game.movement_seq == old_seq, "Dog gesture neither stops nor replaces an already accepted herder walk")
	await _fixture()
	# Existing world movement still begins on press, rather than waiting for Go.
	var ground := _ground_screen(Vector2(-5, -4))
	_press("mouse", ground, true)
	_press("mouse", ground, false)
	_check(recorder.sent.size() == 1 and recorder.sent[0].type == "move" and game.moving, "Ordinary ground tap still moves only the herder")

func _terrain_validation() -> void:
	_configure_input("mouse")
	for landscape in ["oasis", "cloud", "juniper", "bellflower"]:
		await _fixture(landscape)
		var start := _dog_screen("mochi")
		var target := _ground_screen(Vector2(-7, -5))
		_press("mouse", start, true)
		_motion("mouse", target, start)
		_press("mouse", target, false)
		_assert_one_go("mochi", Vector2(-7, -5), landscape + " valid surface")
		await _fixture(landscape)
		start = _dog_screen("mochi")
		var invalid := {"oasis": Vector2.ZERO, "cloud": Vector2(3, 8), "juniper": Vector2(0, 2), "bellflower": Vector2(8, 0)}
		target = _ground_screen(invalid[landscape])
		_press("mouse", start, true)
		_motion("mouse", target, start)
		_press("mouse", target, false)
		_check(recorder.sent.is_empty() and not game.dog_drag.marker.visible and game.meadow.destination_calls == 0, landscape + " rejects its canonical obstacle or boundary without destination feedback")

func _release_revalidation() -> void:
	for mode in ["mouse", "native"]:
		_configure_input(mode)
		await _fixture()
		var start := _dog_screen("mochi")
		var pointer := _ground_screen(Vector2(-7, -5))
		_press(mode, start, true)
		_press(mode, pointer, false)
		_assert_one_go("mochi", Vector2(-7, -5), "coalesced motion still validates release")
		await _fixture()
		start = _dog_screen("mochi")
		pointer = _ground_screen(Vector2(-7, -5))
		_press(mode, start, true)
		_motion(mode, pointer, start)
		var previous_target: Vector3 = game.dog_drag.target
		game.meadow.camera_focus.x += 1.5
		game.meadow.desired_focus = game.meadow.camera_focus
		game.meadow._process(0.0)
		var current_target: Vector3 = game.meadow.ground_at(pointer)
		_check(current_target.is_finite() and current_target.distance_to(previous_target) > 0.5, "Camera-change fixture must alter the actual ground under the pointer")
		_press(mode, pointer, false)
		_assert_one_go("mochi", Vector2(current_target.x, current_target.z), "release re-picks the current camera instead of stale preview coordinates")

func _assert_one_go(dog: String, expected: Vector2, context: String) -> void:
	_check(recorder.sent.size() == 1, context + " sends exactly one message")
	if recorder.sent.size() != 1:
		return
	var message := recorder.sent[0]
	_check(message.type == "command" and message.command == "go" and message.dog_id == dog and Vector2(message.target.x, message.target.y).distance_to(expected) < 0.025, context + " sends Go to the intended dog and current valid ground target")
	var ground: Vector3 = game.meadow.last_destination
	_check(game.meadow.destination_calls == 1 and ground.is_finite() and Vector2(ground.x, ground.z).distance_to(expected) < 0.025 and absf(ground.y - game.meadow.surface_height(ground.x, ground.z)) < 0.0001, context + " marks exactly one terrain-grounded destination at the sent endpoint")
	_check(game.meadow.destination.visible and game.meadow.marker_age == 0.0, context + " retains the existing fading request marker after the finger lifts")

func _configure_input(mode: String) -> void:
	Input.set_emulate_mouse_from_touch(mode == "native")
	Input.set_emulate_touch_from_mouse(mode == "mouse_emulates_touch")

func _press(mode: String, point: Vector2, pressed: bool, canceled := false) -> void:
	var event: InputEvent
	if mode == "native":
		var touch := InputEventScreenTouch.new()
		touch.index = 3
		touch.position = point
		touch.pressed = pressed
		touch.canceled = canceled
		event = touch
	else:
		var mouse := InputEventMouseButton.new()
		mouse.position = point
		mouse.global_position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mouse.pressed = pressed
		mouse.canceled = canceled
		event = mouse
	_dispatch(event, mode)

func _motion(mode: String, point: Vector2, before: Vector2) -> void:
	var event: InputEvent
	if mode == "native":
		var drag := InputEventScreenDrag.new()
		drag.index = 3
		drag.position = point
		drag.relative = point - before
		event = drag
	else:
		var mouse := InputEventMouseMotion.new()
		mouse.position = point
		mouse.global_position = point
		mouse.relative = point - before
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
		event = mouse
	_dispatch(event, mode)

func _dispatch(event: InputEvent, mode: String) -> void:
	if mode == "mouse":
		root.push_input(event, true)
	else:
		# Exercise the engine-generated counterpart too, not hand-call _input.
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _dog_screen(id: String) -> Vector2:
	var screen: Vector2 = game.meadow.camera.unproject_position(game.actors[id].node.position + Vector3.UP * 0.5)
	_check(game._pick_world_interaction(screen) == "dog:" + id, "Fixture must visibly select the intended dog")
	return screen

func _ground_screen(point: Vector2) -> Vector2:
	return game.meadow.camera.unproject_position(Vector3(point.x, game.meadow.surface_height(point.x, point.y), point.y))

func _layout() -> void:
	await process_frame
	await process_frame

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("DOG_DRAG_FAILED: " + message)
