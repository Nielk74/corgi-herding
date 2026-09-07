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
	game._select_dog("maple")
	game._prepare_go()
	if game.selected_dog != "maple" or not game.go_pending:
		_fail("both dogs must accept commands")
		return
	game._select_dog("mochi")
	if game.go_pending:
		_fail("changing dog must cancel a pending ground command")
		return
	game._open_settings()
	if not game.welcome.visible or game.hud.visible:
		_fail("settings must restore invitation UI")
		return
	print("CLIENT_SMOKE_OK: scene, 14 actors, shared dogs, bridge, gate, settings")
	quit(0)

func _fail(message: String) -> void:
	push_error("CLIENT_SMOKE_FAILED: " + message)
	quit(1)
