extends SceneTree
## Real scene construction, snapshot rendering and input/prediction invariants.
## godot --headless --path client --script res://tests/smoke.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_fail("main scene failed to load")
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.preview_mode = true
	game._show_preview()
	await process_frame
	if int(ProjectSettings.get_setting("display/window/handheld/orientation")) != 1:
		_fail("Android must use portrait orientation")
		return
	if game.command_panel.visible or game.sit_button.visible or game.go_cancel.visible:
		_fail("gameplay controls must remain hidden until requested")
		return
	if game.actors.size() != 14:
		_fail("expected two herders, two dogs and ten sheep")
		return
	if game.meadow.camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		_fail("camera must remain a fixed diorama view")
		return
	if game._walkable(Vector2(0, 5)) or game._walkable(Vector2(6, 0)):
		_fail("river and closed gate must block prediction")
		return
	game.meadow.gate_open = true
	if not game._walkable(Vector2(0, 0)) or not game._walkable(Vector2(6, 0)):
		_fail("bridge and open gate must be walkable")
		return
	# A destination on the bridge must remain a destination, not an instruction
	# to leave through either bank. Exercise prediction without server corrections.
	var bridge_target := Vector2(0, 1)
	for start in [Vector2(-4, 3), Vector2(4, -3)]:
		var point: Vector2 = start
		for step in range(300):
			var next: Vector2 = point.move_toward(game._next_waypoint(point, bridge_target), 4.0 / 60.0)
			if not game._walkable(next):
				_fail("bridge prediction crossed blocked terrain")
				return
			point = next
		if point.distance_to(bridge_target) > 0.08:
			_fail("bridge destination prediction did not settle from both banks")
			return
	# Touch regions overlap when a herder approaches the gate. The closest
	# projected target must win, including when a corgi stands nearby.
	var player: Node3D = game.actors[game.local_id].node
	var nearby_dog: Node3D = game.actors["mochi"].node
	var previous_player := player.position
	var previous_dog := nearby_dog.position
	player.position = Vector3(5.6, 0.11, 0)
	nearby_dog.position = Vector3(5.55, 0.11, -0.4)
	game.meadow.gate_open = false
	var gate_screen: Vector2 = game.meadow.camera.unproject_position(Vector3(6, 0.8, 0))
	var player_screen: Vector2 = game.meadow.camera.unproject_position(player.position + Vector3(0, 0.9, 0))
	var dog_screen: Vector2 = game.meadow.camera.unproject_position(nearby_dog.position + Vector3(0, 0.5, 0))
	if player_screen.distance_to(gate_screen) >= 40.0:
		_fail("gate regression fixture must overlap the herder's touch region")
		return
	if game._pick_world_interaction(gate_screen) != "gate" or game._pick_world_interaction(player_screen) != "player" or game._pick_world_interaction(dog_screen) != "dog:mochi":
		_fail("overlapping world taps must select the closest gate, herder or corgi")
		return
	game._world_tap(gate_screen)
	if game.sit_button.visible or game.command_panel.visible:
		_fail("tapping the nearby gate must not open herder or dog controls")
		return
	player.position = previous_player
	nearby_dog.position = previous_dog
	# A rejected fence target must never advance the local input sequence, which
	# would suppress reconciliation against the server's last accepted movement.
	var previous_seq: int = game.network.seq
	var fence_screen: Vector2 = game.meadow.camera.unproject_position(Vector3(6, 0.10, 6))
	game._world_tap(fence_screen)
	if game.network.seq != previous_seq:
		_fail("unwalkable fence taps must not send predicted movement")
		return
	game.meadow.gate_open = true
	game._select_dog("maple")
	if not game.command_panel.visible or game.command_title.text != "Maple":
		_fail("tapping a corgi must reveal only that dog's commands")
		return
	game._prepare_go()
	if game.selected_dog != "maple" or not game.go_pending or game.command_panel.visible or not game.go_cancel.visible:
		_fail("both dogs must accept commands")
		return
	game._select_dog("mochi")
	if game.go_pending:
		_fail("changing dog must cancel a pending ground command")
		return
	game._command("stay")
	if game.command_panel.visible or game.go_cancel.visible:
		_fail("commands must return to the uncluttered world")
		return
	var existing_dog: Node3D = game.actors["mochi"].node
	game._select_landscape("cactus")
	await process_frame
	if game.selected_landscape != "cactus" or game.actors["mochi"].node != existing_dog:
		_fail("landscape changes must preserve the animals")
		return
	game._select_landscape("alpine")
	await process_frame
	if game.actors.size() != 14 or game.selected_landscape != "alpine":
		_fail("both landscapes must support the same cooperative herd")
		return
	game._open_settings()
	if not game.welcome.visible or game.hud.visible:
		_fail("settings must restore invitation UI")
		return
	print("CLIENT_SMOKE_OK: portrait, contextual controls, alpine/cactus landscapes, 14 actors, shared dogs, bridge prediction, nearest gate hit, fence rejection, settings")
	quit(0)

func _fail(message: String) -> void:
	push_error("CLIENT_SMOKE_FAILED: " + message)
	quit(1)
