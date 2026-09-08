extends SceneTree
## Fixed contextual targets under live snapshots; GUI events, never emit_pressed.

class RecordingConnection:
	extends "res://scripts/network.gd"
	var sent: Array[Dictionary] = []
	func send(message: Dictionary) -> void:
		sent.append(message.duplicate(true))

var game: Node3D
var recorder: RecordingConnection
var checks := 0
var failures := 0
var snapshot_tick := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var herd_before := _digest("user://herd.cfg")
	var audio_before := _digest("user://audio.cfg")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.network.free()
	recorder = RecordingConnection.new()
	recorder.persist_config = false
	game.add_child(recorder)
	recorder.set_process(false)
	recorder.connected = true
	game.network = recorder
	game.preview_mode = true
	game._show_preview()
	await _layout()
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = viewport_size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = viewport_size
		await _layout()
		_check(root.get_visible_rect().size == Vector2(viewport_size), "real portrait viewport")
		for dog_id in ["mochi", "maple"]:
			await _snapshot(dog_id, "near")
			game._select_dog(dog_id)
			await _layout()
			if dog_id == "mochi":
				# Reproduce the old layout hazard in-memory as a negative control:
				# hiding Pet really does move Go under the saved Pet tap location.
				var old_pet_center: Vector2 = game.pet_button.get_global_rect().get_center()
				game.pet_button.hide()
				await _layout()
				_check(game.go_button.get_global_rect().has_point(old_pet_center), "old reflow must put Go under the original Pet target")
				await _click(old_pet_center)
				_check(game.go_pending, "old hidden-Pet layout must reproduce the accidental Go action")
				game.pet_button.show()
				game._select_dog(dog_id)
				await _layout()
			var pet_rect: Rect2 = game.pet_button.get_global_rect()
			var go_rect: Rect2 = game.go_button.get_global_rect()
			var fixed_pet_center := pet_rect.get_center()
			_check(game.pet_button.is_visible_in_tree() and not game.pet_button.disabled, "near Pet must be visible and enabled")
			_check(pet_rect.size.y >= 72.0 and not go_rect.has_point(fixed_pet_center), "Pet has its own touch-sized slot")
			for state in ["far", "missing_dog", "missing_player"]:
				await _snapshot(dog_id, state)
				_check(game.pet_button.is_visible_in_tree() and game.pet_button.disabled, state + " keeps a disabled Pet slot")
				_stable_rectangles(pet_rect, go_rect, state)
				recorder.sent.clear()
				await _click(fixed_pet_center)
				_check(recorder.sent.is_empty() and not game.go_pending and not game.moving and game.command_panel.visible, state + " GUI tap cannot activate Go, movement or Pet")
			# Press while reachable, then let an accepted snapshot move the dog
			# before release. The original intended target must never become Go.
			await _snapshot(dog_id, "near")
			_press(fixed_pet_center, true)
			await _snapshot(dog_id, "far")
			_press(fixed_pet_center, false)
			await _layout()
			_stable_rectangles(pet_rect, go_rect, "move during press")
			_check(recorder.sent.is_empty() and not game.go_pending and game.command_panel.visible, "a held Pet tap remains harmless if the dog wanders away")
			# Also cover movement between the last context update and activation.
			await _snapshot(dog_id, "near")
			game.actors[dog_id].node.position = game._surface_position(Vector2(-6, 2))
			_check(not game.pet_button.disabled, "stale enabled-state fixture")
			await _click(fixed_pet_center)
			_check(recorder.sent.is_empty() and not game.go_pending and game.command_panel.visible and game.pet_button.disabled, "activation must recheck current reach")
			await _snapshot(dog_id, "near")
			_stable_rectangles(pet_rect, go_rect, "back within reach")
			await _click(fixed_pet_center)
			_check(recorder.sent == [{"type": "interact", "action": "pet", "dog_id": dog_id}], "reachable fixed-slot GUI tap sends exactly one Pet to the selected dog")
			_check(not game.command_panel.visible and not game.pet_button.is_visible_in_tree() and not game.go_pending, "successful Pet returns to the uncluttered world")
			recorder.sent.clear()
			# Positive Go control: this test would fail if GUI injection did nothing.
			game._select_dog(dog_id)
			await _layout()
			await _click(game.go_button.get_global_rect().get_center())
			_check(game.go_pending and game.go_cancel.visible and not game.command_panel.visible, "actual Go slot still opens target selection")
			game._close_controls()
			await _layout()
			_check(not game.pet_button.is_visible_in_tree(), "Pet is not a persistent HUD control")
	game.queue_free()
	await _layout()
	_check(_digest("user://herd.cfg") == herd_before and _digest("user://audio.cfg") == audio_before, "test must preserve real invitation and audio preferences")
	print("CONTEXT_CONTROLS_SMOKE: %d checks, %d failures; both dogs, real 720x1280/720x1600 GUI taps, near/far/missing snapshots, fixed Pet/Go rectangles, delayed release and activation recheck" % [checks, failures])
	quit(1 if failures else 0)

func _snapshot(dog_id: String, state: String) -> void:
	snapshot_tick += 1
	var snapshot := {
		"tick": snapshot_tick, "landscape": "alpine", "layout": {"version": 1, "bridge_y": 0.0, "gate_y": 0.0},
		"gate_open": false, "settled": 0, "sheep": [],
		"players": [{"id": "p1", "position": {"x": -10.0, "y": 2.0}, "state": "idle", "connected": true, "seq": snapshot_tick}],
		"dogs": [{"id": dog_id, "position": {"x": -9.0 if state == "near" else -6.0, "y": 2.0}, "state": "idle"}],
	}
	if state == "missing_dog":
		snapshot.dogs = []
	if state == "missing_player":
		snapshot.players = []
	game._on_snapshot(snapshot)
	# Exercise the normal rendered interpolation/context update, rather than
	# teleporting fixtures into the actor map and bypassing snapshot handling.
	game._process(0.6)
	await _layout()

func _stable_rectangles(pet_rect: Rect2, go_rect: Rect2, state: String) -> void:
	_check(game.pet_button.get_global_rect().is_equal_approx(pet_rect), state + " must preserve Pet's rectangle")
	_check(game.go_button.get_global_rect().is_equal_approx(go_rect), state + " must preserve Go's rectangle")

func _click(point: Vector2) -> void:
	_press(point, true)
	_press(point, false)
	await _layout()

func _press(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func _layout() -> void:
	await process_frame
	await process_frame

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("CONTEXT_CONTROLS_FAILED: " + message)
