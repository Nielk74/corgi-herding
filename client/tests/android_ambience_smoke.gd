extends SceneTree
## Exercise production Android ownership/error paths without an emulator or JNI.
## The fake boundary models Java return values/exceptions, not native acoustics;
## real captured Android pause/resume output remains a separate release gate.

const NativeOutput = preload("res://scripts/android_ambience.gd")
const Soundscape = preload("res://scripts/soundscape.gd")

class FakeTrack:
	extends RefCounted
	var fault := ""
	var exception_box: Dictionary
	var history: Array
	var index := 0
	var buffer_bytes := 0
	var transfer_mode := -1
	var session_id := -1
	var state := 2
	var payload := PackedByteArray()
	var write_offset := -1
	var write_mode := -1
	var gains := Vector2.ZERO
	var playing := false
	var pauses := 0
	var releases := 0

	func write(data: PackedByteArray, offset: int, count: int, mode: int) -> int:
		history.append([index, "write"])
		payload = data
		write_offset = offset
		write_mode = mode
		state = 1
		if fault == "write_exception":
			exception_box.pending = true
			return 0
		if fault == "short_write":
			return count - 2
		if fault == "bad_state":
			state = 0
		return count

	func getState() -> int:
		history.append([index, "state"])
		return state

	func setStereoVolume(left: float, right: float) -> int:
		history.append([index, "gain"])
		gains = Vector2(left, right)
		return -3 if fault == "bad_gain" else 0

	func play() -> void:
		history.append([index, "play"])
		playing = true
		if fault == "play_exception":
			exception_box.pending = true

	func pause() -> void:
		history.append([index, "pause"])
		pauses += 1
		playing = false
		if fault == "pause_exception":
			exception_box.pending = true

	func release() -> void:
		history.append([index, "release"])
		releases += 1
		playing = false
		state = 0

class FakeTrackClass:
	extends RefCounted
	var exception_box := {"pending": false}
	var history: Array = []
	var created: Array[FakeTrack] = []
	var next_fault := ""

	func AudioTrack(_attributes: Variant, _format: Variant, size: int, mode: int, session: int) -> Variant:
		var fault := next_fault
		next_fault = ""
		if fault == "constructor_exception":
			exception_box.pending = true
			return null
		var track := FakeTrack.new()
		track.fault = fault
		track.exception_box = exception_box
		track.history = history
		track.index = created.size()
		track.buffer_bytes = size
		track.transfer_mode = mode
		track.session_id = session
		history.append([track.index, "create"])
		created.append(track)
		return track

class NativeHarness:
	extends NativeOutput
	var fake_class := FakeTrackClass.new()

	func configure() -> void:
		# Production construction correctly declines non-Android hosts. Inject
		# only the JNI boundary; play/stop/cleanup are the real implementation.
		failed = false
		_track_class = fake_class
		_attributes = {"usage": 14, "content_type": 2}
		_format = {"rate": 22050, "channels": 4, "encoding": 2}

	func _check_exception() -> void:
		if fake_class.exception_box.pending:
			fake_class.exception_box.pending = false
			_fail()

var cases := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.has_feature("android"):
		_fail("this isolated fake-JNI regression is intended for a headless host")
		return
	if not _ownership() or not _errors():
		return
	if not await _soundscape_gates():
		return
	print("ANDROID_AMBIENCE_SMOKE_OK: %d checks, exact PCM/static-track configuration, two-slot ownership, error cleanup, 20 real Soundscape lifecycle cycles; native acoustics require Android capture" % cases)
	quit(0)

func _check(condition: bool, message: String) -> bool:
	if not condition:
		return _fail(message)
	cases += 1
	return true

func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false

func _new_output() -> NativeHarness:
	var output := NativeHarness.new()
	output.configure()
	return output

func _wind() -> AudioStreamWAV:
	return Soundscape.cached_streams().wind_0

func _bird() -> AudioStreamWAV:
	return Soundscape.cached_streams().bird_0

func _all_released(output: NativeHarness) -> bool:
	if not output.tracks.is_empty():
		return false
	for track: FakeTrack in output.fake_class.created:
		if track.releases != 1 or track.playing:
			return false
	return true

func _ownership() -> bool:
	var output := _new_output()
	if not _check(not output.play_voice("third", _wind(), Vector2.ONE) and output.tracks.is_empty(), "unknown voice kind allocated a native track"):
		return false
	if not _check(output.play_voice("wind", _wind(), Vector2(-1.0, 2.0)), "valid wind did not start"):
		return false
	var wind: FakeTrack = output.fake_class.created[0]
	if not _check(wind.payload == _wind().data and wind.buffer_bytes == _wind().data.size() and wind.write_offset == 0 and wind.write_mode == 1 and wind.transfer_mode == 0 and wind.session_id == 0, "native voice changed cached PCM or static/nonblocking configuration"):
		return false
	if not _check(wind.gains == Vector2(0.0, 1.0) and wind.playing and wind.state == 1, "gain bounds or initialized playback state are incorrect"):
		return false
	if not _check(output.fake_class.history == [[0, "create"], [0, "write"], [0, "state"], [0, "gain"], [0, "play"]], "playback must follow complete PCM write and initialized-state validation"):
		return false
	if not _check(output.play_voice("bird", _bird(), Vector2(0.1, 0.05)) and output.tracks.size() == 2, "two independent kinds did not occupy exactly two slots"):
		return false
	if not _check(output.play_voice("wind", _wind(), Vector2.ONE * 0.15) and output.tracks.size() == 2 and wind.pauses == 1 and wind.releases == 1, "replacing a slot retained its old native track"):
		return false
	var replacement_start := output.fake_class.history.find([2, "create"])
	if not _check(output.fake_class.history.find([0, "release"]) < replacement_start, "replacement created a third live native voice before releasing the old one"):
		return false
	output.stop_all()
	var history_size := output.fake_class.history.size()
	output.stop_all()
	output.stop_voice("wind")
	return _check(_all_released(output) and output.fake_class.history.size() == history_size, "native disarm must release every slot exactly once and be idempotent")

func _errors() -> bool:
	for fault in ["short_write", "bad_state", "bad_gain", "write_exception", "play_exception", "constructor_exception"]:
		var output := _new_output()
		if not _check(output.play_voice("bird", _bird(), Vector2.ONE * 0.1), fault + ": failed to establish an already-playing other slot"):
			return false
		output.fake_class.next_fault = fault
		if not _check(not output.play_voice("wind", _wind(), Vector2.ONE * 0.1), fault + ": invalid native operation was accepted"):
			return false
		if not _check(output.failed and _all_released(output), fault + ": a failed backend retained a native track, including the other slot"):
			return false
		var count := output.fake_class.created.size()
		if not _check(not output.play_voice("wind", _wind(), Vector2.ONE) and output.fake_class.created.size() == count, fault + ": failed native backend resumed or retried playback"):
			return false
		output.stop_all()
		if not _check(_all_released(output), fault + ": cleanup after failure released a track twice"):
			return false
	# A pause exception must not skip release, or leave the OTHER kind audible.
	var output := _new_output()
	output.fake_class.next_fault = "pause_exception"
	if not _check(output.play_voice("wind", _wind(), Vector2.ONE * 0.1) and output.play_voice("bird", _bird(), Vector2.ONE * 0.1), "pause-error fixture could not start two tracks"):
		return false
	if not _check(not output.play_voice("wind", _wind(), Vector2.ONE * 0.1), "slot replacement ignored the old track's pause error"):
		return false
	return _check(output.failed and _all_released(output), "pause error prevented release or preserved the other native slot")

func _arm(rig: Node) -> void:
	rig.set_foreground(true)
	rig.set_focused(true)
	rig.set_gameplay_visible(true)
	rig.set_connected(true)
	rig.observe_snapshot()

func _force_two(rig: Node) -> bool:
	rig.wind_in = 0.0
	rig.bird_in = 0.0
	rig.advance(0.0)
	return _check(rig.android_output.tracks.size() == 2 and not rig.wind_player.playing and not rig.bird_player.playing, "native routing must not also start Godot's retained OpenSL voices")

func _soundscape_gates() -> bool:
	var rig := Soundscape.new()
	rig.persist_preference = false
	rig.random_seed = 94812
	root.add_child(rig)
	rig.set_process(false)
	var output := _new_output()
	rig.android_output = output
	for cycle in range(20):
		for gate in ["focus", "background", "menu", "disconnect", "disabled"]:
			_arm(rig)
			if not _force_two(rig):
				return false
			match gate:
				"focus": rig.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
				"background": rig.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				"menu": rig.set_gameplay_visible(false)
				"disconnect": rig.set_connected(false)
				"disabled": rig.set_enabled(false)
			if not _check(_all_released(output) and not rig.fresh_snapshot and rig.debug_state().voices == 0, "%s cycle%d: closed gate retained native PCM ownership" % [gate, cycle]):
				return false
			rig.observe_snapshot()
			match gate:
				"focus": rig.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
				"background": rig.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
				"menu": rig.set_gameplay_visible(true)
				"disconnect": rig.set_connected(true)
				"disabled": rig.set_enabled(true)
			rig.advance(3600.0)
			if not _check(_all_released(output) and not rig.fresh_snapshot, "%s cycle%d: reopening replayed a released track without a new snapshot" % [gate, cycle]):
				return false
			rig.observe_snapshot()
			rig.advance(1.0)
			if not _check(output.tracks.is_empty() and rig.wind_in >= 8.0 and rig.bird_in >= 23.0, "%s cycle%d: fresh native lifecycle skipped quiet start" % [gate, cycle]):
				return false
	# Expiry, a stalled frame and scene removal also release native ownership.
	if not _force_two(rig):
		return false
	for step in range(7):
		rig.advance(1.0)
	if not _check(_all_released(output), "natural clip expiry retained native track resources"):
		return false
	if not _force_two(rig):
		return false
	rig.advance(3600.0)
	if not _check(_all_released(output), "stalled frame retained queued native PCM"):
		return false
	# A native pause error can arise on ordinary expiry, outside play_voice's
	# error paths. The other live slot must stop in that same advance call.
	output.fake_class.next_fault = "pause_exception"
	if not _force_two(rig):
		return false
	rig.wind_remaining = 0.01
	rig.bird_remaining = 1.0
	rig.advance(0.02)
	if not _check(output.failed and _all_released(output) and rig.debug_state().voices == 0, "ordinary expiry failure left the other native voice audible despite zero diagnostics"):
		return false
	output = _new_output()
	rig.android_output = output
	# A real scheduling failure may interrupt the other already-playing kind.
	# Neither diagnostics nor sound_started may claim an inaudible start, and
	# repeated frames must not turn the failed native backend into a hot retry.
	var signals: Array = []
	rig.sound_started.connect(func(kind: String, sample: String): signals.append([kind, sample]))
	rig.wind_in = 100.0
	rig.bird_in = 0.0
	rig.advance(0.0)
	if not _check(output.tracks.size() == 1 and signals.size() == 1, "failed-start integration fixture did not establish an audible other slot"):
		return false
	var events_before: Vector2i = Vector2i(rig.wind_events, rig.bird_events)
	output.fake_class.next_fault = "constructor_exception"
	rig.wind_in = 0.0
	rig.advance(0.0)
	var state: Dictionary = rig.debug_state()
	if not _check(state.android_failed and state.android_tracks == 0 and state.voices == 0 and state.wind_remaining == 0.0 and state.bird_remaining == 0.0 and _all_released(output), "failed native scheduling retained a voice or misreported audio health"):
		return false
	if not _check(Vector2i(rig.wind_events, rig.bird_events) == events_before and signals.size() == 1 and rig.wind_in > 28.0, "failed native start incremented sound events or skipped its backoff"):
		return false
	var created_before := output.fake_class.created.size()
	for frame in range(120):
		rig.advance(1.0 / 60.0)
	if not _check(output.fake_class.created.size() == created_before and signals.size() == 1 and not rig.wind_player.playing and not rig.bird_player.playing, "failed native output retried each frame or fell back to retained OpenSL playback"):
		return false
	# A new isolated backend gives scene teardown actual resources to release.
	output = _new_output()
	rig.android_output = output
	if not _force_two(rig):
		return false
	rig.queue_free()
	await process_frame
	return _check(not is_instance_valid(rig) and _all_released(output), "scene teardown retained native playback")
