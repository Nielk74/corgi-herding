extends SceneTree
## Camera-only deterministic checks; no live networking or saved-state writes.

const Meadow = preload("res://scripts/meadow.gd")
var meadow: MeadowDiorama
var checks := 0
var failures := 0
var peak_pan_speed := 0.0
var moving_ground_picks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var herd_before := _digest("user://herd.cfg")
	var audio_before := _digest("user://audio.cfg")
	meadow = Meadow.new()
	root.add_child(meadow)
	await process_frame
	meadow.set_process(false)
	meadow.set_landscape("juniper")
	await process_frame
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		root.content_scale_size = viewport_size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.size = viewport_size
		await process_frame
		_check(root.size == viewport_size and root.get_visible_rect().size == Vector2(viewport_size), "matching actual physical and logical portrait viewports")
		meadow.zoom = 1.0
		meadow.fit_camera()
		var right_results: Array[float] = []
		var left_results: Array[float] = []
		for frequency in [20.0, 30.0, 60.0]:
			right_results.append(_reversal(true, frequency))
			left_results.append(_reversal(false, frequency))
		_check(_span(right_results) < 0.16 and _span(left_results) < 0.16, "reversal framing remains consistent across 20/30/60Hz")
		_quiet_and_rest()
		_bounds_and_lens()
	_check(peak_pan_speed < 4.5, "ordinary walking must not introduce a rapid camera catch-up")
	meadow.queue_free()
	await process_frame
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 1600)]:
		await _main_integration(viewport_size)
	_check(_digest("user://herd.cfg") == herd_before and _digest("user://audio.cfg") == audio_before, "camera tests preserve real invitation and audio preferences")
	_check(moving_ground_picks >= 120, "moving camera requires substantial actual ground-picking coverage")
	print("CAMERA_FOLLOW_SMOKE: %d checks, %d failures; two-way Juniper reversal, 20/30/60Hz, both portrait aspects, stopped/resting/idle correction stability, fixed lens and bounds, local-only main integration; %d moving ground picks, peak ordinary pan %.3f units/s" % [checks, failures, moving_ground_picks, peak_pan_speed])
	quit(1 if failures else 0)

func _place(point: Vector2) -> void:
	meadow.reset_player_follow()
	meadow.follow_player(Vector3(point.x, 0, point.y), false)
	meadow._process(0.0)
	_check(is_equal_approx(meadow.camera_focus.x, clampf(point.x, -6.0, 6.0)), "first idle placement must frame the local herder once")

func _reversal(from_right: bool, frequency: float) -> float:
	var path: Array = [Vector2(13.77, 4.13), Vector2(11, 4), Vector2(9, -2), Vector2(4, -6), Vector2(-1, -6)] if from_right else [Vector2(-14, 0), Vector2(-11, 2), Vector2(-8, -3), Vector2(-3, -6), Vector2(1, -6)]
	var point: Vector2 = path[0]
	_place(point)
	var old_focus := 6.0 if from_right else -6.0
	var old_desired := old_focus
	var delta := 1.0 / frequency
	var initial_basis := meadow.camera.basis
	var initial_size := meadow.camera.size
	var frame_number := 0
	for target: Vector2 in path.slice(1):
		while point.distance_to(target) > 0.00001:
			point = point.move_toward(target, 4.0 * delta)
			var before := meadow.camera_focus.x
			meadow.follow_player(Vector3(point.x, 0, point.y), true)
			meadow._process(delta)
			peak_pan_speed = maxf(peak_pan_speed, absf(meadow.camera_focus.x - before) / delta)
			_check(absf(meadow.camera_focus.x) <= 6.00001 and absf(meadow.desired_focus.x) <= 6.00001, "walking never exceeds original pan bounds")
			_check(meadow.camera.basis.is_equal_approx(initial_basis) and meadow.camera.size == initial_size, "walking cannot rotate or zoom the camera")
			if frame_number % 12 == 0:
				var surface := Vector3(point.x, meadow.surface_height(point.x, point.y), point.y)
				var screen: Vector2 = meadow.camera.unproject_position(surface)
				var picked: Vector3 = meadow.ground_at(screen)
				_check(picked.is_finite() and picked.distance_to(surface) < 0.06, "moving camera projection and actual ground picking must agree")
				moving_ground_picks += 1
			frame_number += 1
			# Frozen release13 follow law: quantitative negative control for the
			# stale opposite-side framing seen in actual Juniper Android captures.
			var old_offset := point.x - old_desired
			if absf(old_offset) > 5.8:
				old_desired = clampf(point.x - signf(old_offset) * 5.8, -6.0, 6.0)
			old_focus = lerpf(old_focus, old_desired, 1.0 - exp(-delta * 1.5))
	var before_rest := meadow.camera_focus
	meadow.follow_player(Vector3(point.x, 0, point.y), false)
	for frame in range(int(frequency * 4)):
		meadow._process(delta)
		_check(meadow.camera_focus == before_rest, "stopping freezes framing instead of drifting during rest")
		old_focus = lerpf(old_focus, old_desired, 1.0 - exp(-delta * 1.5))
	var new_error := absf(meadow.camera_focus.x - point.x)
	var old_error := absf(old_focus - point.x)
	_check(new_error < 3.0 and old_error > 5.7 and new_error + 2.5 < old_error, "reversal must materially reduce old opposite-side bias before resting")
	var nearby_flock := Vector2(-9, -6) if from_right else Vector2(9, -6)
	var probe := Vector3(nearby_flock.x, meadow.surface_height(nearby_flock.x, nearby_flock.y) + 0.6, nearby_flock.y)
	var screen: Vector2 = meadow.camera.unproject_position(probe)
	var viewport_size := root.get_visible_rect().size
	_check(screen.x > viewport_size.x * 0.025 and screen.x < viewport_size.x * 0.975, "nearby trailing-flock probe remains visible after reversal at default zoom")
	print("CAMERA_REVERSAL: %s %.0fHz %s, stopped focus %.3f vs old %.3f; local offset %.3f vs %.3f" % ["right-to-left" if from_right else "left-to-right", frequency, root.get_visible_rect().size, meadow.camera_focus.x, old_focus, new_error, old_error])
	return meadow.camera_focus.x

func _quiet_and_rest() -> void:
	_place(Vector2.ZERO)
	var initial := meadow.camera_focus
	for frame in range(300):
		var x := sin(frame * 0.17) * 2.8
		meadow.follow_player(Vector3(x, sin(frame) * 0.7, 0), true)
		meadow._process(1.0 / 60.0)
		_check(meadow.camera_focus == initial and not meadow.following_walk, "short walks stay inside the quiet center")
	for frame in range(300):
		meadow.follow_player(Vector3(sin(frame) * 0.035, 2.0, cos(frame) * 0.04), false)
		meadow._process(1.0 / 60.0)
		_check(meadow.camera_focus == initial, "idle correction and terrain-height jitter cannot pan")
	meadow.follow_player(Vector3(5, 0, 0), true)
	meadow._process(0.25)
	_check(meadow.following_walk and meadow.camera_focus.x > 0.0, "a deliberate walk outside the quiet area begins smooth following")
	var stopped := meadow.camera_focus
	for frame in range(300):
		meadow.follow_player(Vector3(5.0 + sin(frame) * 0.035, 0, 0), false)
		meadow._process(1.0 / 60.0)
		_check(meadow.camera_focus == stopped and meadow.desired_focus == stopped, "rest stays exact even outside the quiet area")
	meadow.follow_player(Vector3.INF, true)
	meadow._process(1.0)
	_check(meadow.camera_focus == stopped, "invalid presentation input cannot poison framing")
	# Rest may leave a small smoothing lag. A brief off-center step can pan, but
	# must not jump to the player or continue drifting after that step ends.
	var before_short := meadow.camera_focus
	for frame in range(6):
		meadow.follow_player(Vector3(5.0 + (frame + 1) * 4.0 / 60.0, 0, 0), true)
		meadow._process(1.0 / 60.0)
	var after_short := meadow.camera_focus
	_check(after_short.x > before_short.x and after_short.x - before_short.x < 0.7, "brief off-center walk starts a bounded smooth pan, not a snap")
	meadow.follow_player(Vector3(5.4, 0, 0), false)
	meadow._process(4.0)
	_check(meadow.camera_focus == after_short, "brief off-center walk stops camera movement immediately on rest")

func _bounds_and_lens() -> void:
	for zoom in [0.8, 1.0, 1.18]:
		meadow.zoom = zoom
		meadow.fit_camera()
		_place(Vector2.ZERO)
		var lens := meadow.camera.size
		var basis := meadow.camera.basis
		for destination in [-17.0, 17.0, -17.0]:
			for frame in range(180):
				meadow.follow_player(Vector3(destination, 4.0, 10), true)
				meadow._process(1.0 / 60.0)
				_check(absf(meadow.camera_focus.x) <= 6.00001 and absf(meadow.desired_focus.x) <= 6.00001, "extreme input respects existing ±6 limits")
				_check(meadow.camera.size == lens and meadow.camera.basis.is_equal_approx(basis), "all zoom presets preserve their fixed lens/angle during follow")
				_check(is_equal_approx(meadow.camera_focus.y, 1.8) and is_equal_approx(meadow.camera_focus.z, -6.0), "follow remains horizontal, independent of hill height")
		meadow.stop_player_follow()
		var stopped := meadow.camera_focus
		meadow._process(10.0)
		_check(meadow.camera_focus == stopped, "explicit pause freezes pending camera interpolation")

func _main_integration(viewport_size: Vector2i) -> void:
	root.content_scale_size = viewport_size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = viewport_size
	await process_frame
	_check(root.size == viewport_size and root.get_visible_rect().size == Vector2(viewport_size), "matching actual main integration physical and logical portrait viewports")
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.meadow.set_process(false)
	game.network.set_process(false)
	game.network.persist_config = false
	game.preview_mode = true
	game._select_landscape("alpine") # Legacy small-world camera fixture.
	game._show_preview()
	game._process(0.0)
	game.meadow._process(0.0)
	await process_frame
	var local: Node3D = game.actors[game.local_id].node
	local.position = game._surface_position(Vector2.ZERO)
	game.actors[game.local_id].target = local.position
	game.meadow.reset_player_follow()
	game._process(0.0)
	game.meadow._process(0.0)
	var initial: Vector3 = game.meadow.camera_focus
	for id in game.actors:
		if id != game.local_id:
			game.actors[id].node.position = game._surface_position(Vector2(15, 8))
			game.actors[id].target = game.actors[id].node.position
	for frame in range(60):
		local.position.x = sin(frame) * 0.03
		game._process(1.0 / 60.0)
		game.meadow._process(1.0 / 60.0)
		_check(game.meadow.camera_focus == initial, "main ignores distant partner/dogs/sheep and resting reconciliation jitter")
	# Actual GUI/world-input path: one ground press remains held after arrival.
	# A stationary pointer is not repeated movement intent or a reason to pan.
	var target := Vector2(-7, 0)
	var pointer: Vector2 = game.meadow.camera.unproject_position(game._surface_position(target))
	var press := InputEventMouseButton.new()
	press.position = pointer
	press.global_position = pointer
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	_check(game.moving, "real ground press must initiate predicted walking")
	var input_seq: int = game.network.seq
	for frame in range(300):
		game._process(1.0 / 60.0)
		game.meadow._process(1.0 / 60.0)
		if not game.moving:
			break
	_check(not game.moving and Vector2(local.position.x, local.position.z).distance_to(target) < 0.12, "ground press must arrive normally before held-pointer check")
	var held_focus: Vector3 = game.meadow.camera_focus
	for frame in range(120):
		var motion := InputEventMouseMotion.new()
		motion.position = pointer
		motion.global_position = pointer
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		game._process(1.0 / 60.0)
		game.meadow._process(1.0 / 60.0)
		_check(game.meadow.camera_focus == held_focus and game.network.seq == input_seq, "held stationary pointer cannot restart walking or camera follow")
	press.pressed = false
	press.button_mask = 0
	root.push_input(press, true)
	# A fresh idle reconnect corrects the actor, but is not a new-session camera
	# placement; preserving the current view avoids a visible resting snap.
	var reconnect: Dictionary = game.latest.duplicate(true)
	reconnect.players[0].position = {"x": local.position.x + 0.035, "y": local.position.z}
	reconnect.players[0]["seq"] = input_seq
	reconnect.players[0].state = "idle"
	game._on_status("Reconnecting…", false)
	game._on_snapshot(reconnect)
	game._process(0.0)
	game.meadow._process(2.0)
	_check(game.meadow.camera_focus == held_focus and game.meadow.player_follow_initialized, "idle reconnect correction preserves resting frame without reinitializing")
	# Opening settings or losing the actor must also stop a pending pan.
	game.meadow.follow_player(Vector3(5, 0, 0), true)
	game.meadow._process(0.25)
	var before_menu: Vector3 = game.meadow.camera_focus
	game._open_settings()
	game._process(0.0)
	game.meadow._process(2.0)
	_check(game.meadow.camera_focus == before_menu and not game.meadow.following_walk, "actual menu transition freezes the camera")
	game.hud.show()
	game.meadow.follow_player(Vector3(-5, 0, 0), true)
	game.meadow._process(0.25)
	var before_missing: Vector3 = game.meadow.camera_focus
	game.actors[game.local_id].node.queue_free()
	game.actors.erase(game.local_id)
	game._process(0.0)
	game.meadow._process(2.0)
	_check(game.meadow.camera_focus == before_missing, "missing local actor freezes pending camera motion")
	game._show_preview()
	_check(not game.meadow.player_follow_initialized, "a new herd resets one-time framing")
	game._process(0.0)
	game.meadow._process(0.0)
	_check(game.meadow.player_follow_initialized and is_equal_approx(game.meadow.camera_focus.x, -6.0), "new idle herd gets its own initial frame")
	game.queue_free()
	await process_frame

func _span(values: Array[float]) -> float:
	return values.max() - values.min()

func _digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("CAMERA_FOLLOW_FAILED: " + message)
