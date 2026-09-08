extends SceneTree
## Ambient PCM, scheduling and actual main-scene lifecycle regressions.
## No live server is contacted; preference writes use a unique disposable path.

const Soundscape = preload("res://scripts/soundscape.gd")
const Connection = preload("res://scripts/network.gd")
const SAVED := {"code": "ABCDEF", "player_id": "p1", "token": "soundscape-test-only-token"}
const LOCAL_ENDPOINT := "http://127.0.0.1:1"
var preference_path := ""
var herd_file_before := ""
var audio_file_before := ""
var orphan_nodes_before := 0
var elapsed := 0.0
var events: Array[Dictionary] = []

func _initialize() -> void:
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	_run.call_deferred()

func _run() -> void:
	preference_path = "user://soundscape-smoke-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	herd_file_before = _file_digest(Connection.CONFIG_PATH)
	audio_file_before = _file_digest(Soundscape.CONFIG_PATH)
	orphan_nodes_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var rig := Soundscape.new()
	rig.persist_preference = false
	rig.random_seed = 824613
	root.add_child(rig)
	rig.set_process(false)
	rig.sound_started.connect(_record_sound)
	if not _pcm_bank(rig) or not _standalone_gates(rig) or not _scheduler(rig):
		return
	rig.queue_free()
	await process_frame
	if is_instance_valid(rig):
		_fail("standalone soundscape did not release its owned nodes")
		return
	if not await _main_lifecycle():
		return
	if _file_digest(Connection.CONFIG_PATH) != herd_file_before or _file_digest(Soundscape.CONFIG_PATH) != audio_file_before:
		_fail("sound tests changed a real saved invitation or default audio preference")
		return
	if FileAccess.file_exists(preference_path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(preference_path)) != OK:
			_fail("could not remove the test's own isolated preference file")
			return
	# Give native audio/HTTP cleanup a quiet frame boundary before inspecting
	# teardown. The simulated scheduler deliberately ran much faster than audio.
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	if int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) > orphan_nodes_before:
		_fail("soundscape lifecycle stress leaked orphan scene nodes")
		return
	print("SOUNDSCAPE_SMOKE_OK: cached bounded PCM, sparse scheduling and long silence, 20 actual focus/background/menu/disconnect cycles, fresh accepted snapshots, preference isolation")
	quit(0)

func _file_digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func _record_sound(kind: String, sample_id: String) -> void:
	events.append({"at": elapsed, "kind": kind, "sample": sample_id})

func _advance(rig: Node, delta: float) -> void:
	if is_finite(delta) and delta >= 0:
		elapsed += delta
	rig.advance(delta)

func _event_count(rig: Node) -> int:
	var state: Dictionary = rig.debug_state()
	return int(state.wind_events) + int(state.bird_events)

func _bounded(rig: Node, context: String) -> bool:
	var state: Dictionary = rig.debug_state()
	if state.allocated_players != 2 or state.voices < 0 or state.voices > 2 or state.bank_builds != 1 or state.bank_bytes <= 0 or state.bank_bytes > 1048576:
		return _fail(context + ": audio players, active voices or decoded memory are unbounded")
	var players := 0
	for node in rig.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			players += 1
			if node.max_polyphony != 1:
				return _fail(context + ": each fixed audio player must have one voice")
	if players != 2:
		return _fail(context + ": allocated player diagnostics differ from the actual scene")
	return true

func _disarmed(rig: Node, context: String) -> bool:
	var state: Dictionary = rig.debug_state()
	if state.active or state.fresh_snapshot or state.voices != 0 or state.wind_in != INF or state.bird_in != INF:
		return _fail(context + ": a closed gate retained sound freshness, voices or deadlines")
	if rig.wind_player.playing or rig.bird_player.playing:
		return _fail(context + ": real audio streams continued after the gate closed")
	return _bounded(rig, context)

func _quietly_armed(rig: Node, context: String) -> bool:
	var state: Dictionary = rig.debug_state()
	if not state.active or not state.fresh_snapshot or state.voices != 0:
		return _fail(context + ": first accepted snapshot must arm quietly, without an immediate sound")
	if state.wind_in < 9.0 or state.wind_in > 16.0 or state.bird_in < 24.0 or state.bird_in > 42.0:
		return _fail(context + ": first sounds lost their bounded quiet delay")
	return _bounded(rig, context)

func _until_voice(rig: Node) -> bool:
	for step in range(80):
		_advance(rig, 0.25)
		if not _bounded(rig, "voice exercise"):
			return false
		if rig.debug_state().voices > 0:
			return true
	return _fail("lifecycle test never exercised a genuinely playing voice")

func _bank_ids() -> Dictionary:
	var ids := {}
	for key in Soundscape.cached_streams():
		ids[key] = Soundscape.cached_streams()[key].get_instance_id()
	return ids

func _pcm_bank(rig: Node) -> bool:
	var bank: Dictionary = Soundscape.cached_streams()
	var names: Array = bank.keys()
	names.sort()
	if names != ["bird_0", "bird_1", "bird_2", "wind_0", "wind_1"]:
		return _fail("ambient inventory must stay fixed at two wind breaths and three bird phrases")
	var bytes := 0
	var measured_peak := 0.0
	for key in names:
		var stream := bank[key] as AudioStreamWAV
		if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo or stream.mix_rate != 22050 or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return _fail("ambient clips must be cached, mono, non-looping 22050Hz signed16-bit PCM: " + key)
		var data := stream.data
		if data.is_empty() or data.size() % 2 != 0 or stream.get_length() < 0.5 or stream.get_length() > 6.0:
			return _fail("ambient clip has an invalid or unbounded duration: " + key)
		bytes += data.size()
		var sum := 0.0
		var energy := 0.0
		var peak := 0.0
		for offset in range(0, data.size(), 2):
			var sample := float(data.decode_s16(offset)) / 32768.0
			if not is_finite(sample) or absf(sample) >= 0.95:
				return _fail("ambient PCM contains clipping or a non-finite sample: " + key)
			peak = maxf(peak, absf(sample))
			sum += sample
			energy += sample * sample
		var count := data.size() / 2
		var rms := sqrt(energy / count)
		if peak < 0.1 or rms < 0.001 or rms > 0.45 or absf(sum / count) > 0.01:
			return _fail("ambient PCM is silent, excessively loud or DC-biased: " + key)
		for offset in [0, 2, data.size() - 4, data.size() - 2]:
			if absi(data.decode_s16(offset)) > 64:
				return _fail("ambient clip endpoints need a quiet fade to avoid clicks: " + key)
		measured_peak = maxf(measured_peak, peak)
	if bytes > 1048576 or bytes != rig.debug_state().bank_bytes:
		return _fail("actual decoded PCM differs from the advertised bounded cache")
	print("SOUNDSCAPE_PCM: %d cached clips, %d decoded bytes, peak %.3f, mono16-bit/22050Hz, faded endpoints and no clipping/DC offset" % [bank.size(), bytes, measured_peak])
	return _bounded(rig, "PCM initialization")

func _standalone_gates(rig: Node) -> bool:
	if not _disarmed(rig, "initialization"):
		return false
	rig.set_foreground(true)
	rig.set_focused(true)
	rig.set_gameplay_visible(true)
	rig.set_connected(true)
	if not _disarmed(rig, "open gates without a snapshot"):
		return false
	rig.observe_snapshot()
	if not _quietly_armed(rig, "first valid snapshot"):
		return false
	for setter in ["set_enabled", "set_foreground", "set_focused", "set_gameplay_visible", "set_connected"]:
		if not _until_voice(rig):
			return false
		rig.call(setter, false)
		if not _disarmed(rig, setter):
			return false
		var count := _event_count(rig)
		rig.observe_snapshot()
		_advance(rig, 3600.0)
		rig.call(setter, true)
		_advance(rig, 0.25)
		if not _disarmed(rig, setter + " reopened with only an old snapshot") or _event_count(rig) != count:
			return _fail("closed-gate time or stale snapshots replayed ambient sounds")
		rig.observe_snapshot()
		if not _quietly_armed(rig, setter + " new receipt"):
			return false
	return true

func _scheduler(rig: Node) -> bool:
	rig.invalidate_snapshot()
	rig.observe_snapshot()
	var before: Dictionary = rig.debug_state()
	for duplicate in range(200):
		rig.observe_snapshot()
	if rig.debug_state() != before:
		return _fail("duplicate active snapshots replay sounds or reset scheduling deadlines")
	var ids := _bank_ids()
	events.clear()
	var silence := 0.0
	var longest_silence := 0.0
	var maximum_voices := 0
	for step in range(960):
		_advance(rig, 0.25)
		if not _bounded(rig, "four-minute scheduler stress"):
			return false
		var state: Dictionary = rig.debug_state()
		maximum_voices = maxi(maximum_voices, state.voices)
		silence = silence + 0.25 if state.voices == 0 else 0.0
		longest_silence = maxf(longest_silence, silence)
		if step % 4 == 0:
			var prior: Dictionary = rig.debug_state()
			for duplicate in range(20):
				rig.observe_snapshot()
			if rig.debug_state() != prior:
				return _fail("20Hz duplicate snapshots postpone ambient scheduling")
	if longest_silence < 15.0 or maximum_voices == 0 or events.size() < 5:
		return _fail("soundscape must exercise real sounds while retaining long all-voice silence")
	var last: Dictionary = {}
	var kinds: Dictionary = {}
	for event in events:
		if not event.kind in ["wind", "bird"] or not String(event.sample).begins_with(event.kind + "_") or not ids.has(event.sample):
			return _fail("scheduler emitted an unknown or uncached ambient sample")
		if last.has(event.kind) and event.at - last[event.kind] < (32.5 if event.kind == "wind" else 42.5):
			return _fail("same-kind ambient rate exceeds its deliberate silence gap")
		last[event.kind] = event.at
		kinds[event.kind] = true
		var in_minute := 0
		for other in events:
			if other.at >= event.at and other.at < event.at + 60.0:
				in_minute += 1
		if in_minute > 5:
			return _fail("ambient starts exceed five per rolling minute")
	if kinds.size() != 2 or ids != _bank_ids():
		return _fail("scheduler must exercise both ambient types without rebuilding PCM")
	# A legitimate coincidence of the two deadlines is the maximum pressure
	# case. Exercise it explicitly rather than relying on a random overlap.
	rig.wind_in = 0.0
	rig.bird_in = 0.0
	rig.set_listener_position(Vector3(4, 2, -3))
	var before_overlap := _event_count(rig)
	_advance(rig, 0.0)
	if rig.debug_state().voices != 2 or _event_count(rig) != before_overlap + 2 or not _bounded(rig, "coincident ambient deadlines"):
		return _fail("simultaneous wind/bird deadlines must consume exactly two fixed voices")
	var bird_offset: Vector3 = rig.bird_player.global_position - rig.listener.global_position
	var horizontal_distance := Vector2(bird_offset.x, bird_offset.z).length()
	if horizontal_distance < 9.999 or horizontal_distance > 18.001 or bird_offset.y < 1.999 or bird_offset.y > 5.001:
		return _fail("spatial bird must remain a bounded distant sound relative to the herder")
	for duplicate in range(100):
		rig.observe_snapshot()
		_advance(rig, 0.0)
	if _event_count(rig) != before_overlap + 2 or rig.debug_state().voices != 2:
		return _fail("duplicate receipts retriggered the coincident voices")
	var count := _event_count(rig)
	_advance(rig, 3600.0)
	if _event_count(rig) != count or not _quietly_armed(rig, "hour-long stalled frame"):
		return _fail("a stalled frame caught up old ambient events")
	before = rig.debug_state()
	for invalid_delta in [-1.0, INF, NAN]:
		_advance(rig, invalid_delta)
		if rig.debug_state() != before:
			return _fail("non-finite/negative time changed audio scheduling")
	for step in range(32):
		_advance(rig, 0.25)
	if _event_count(rig) != count:
		return _fail("a resumed stalled frame burst into sound before the new quiet interval")
	print("SOUNDSCAPE_SCHEDULER: %d sparse starts in 240s, longest silence %.2fs, natural maximum %d voices plus bounded two-voice coincidence, stable cache, no duplicate/stall catch-up" % [events.size() - 2, longest_silence, maximum_voices])
	return true

func _snapshot() -> Dictionary:
	var sheep: Array[Dictionary] = []
	for i in range(10):
		sheep.append({"id": "s%d" % i, "position": {"x": -5.0 + (i % 3), "y": -2.0 + floorf(i / 3.0)}, "state": "grazing"})
	return {"type": "snapshot", "tick": 120, "landscape": "alpine", "layout": {"version": 1, "bridge_y": 0.0, "gate_y": 0.0}, "gate_open": false, "settled": 0,
		"players": [{"id": "p1", "name": "Test herder", "position": {"x": -10.0, "y": 2.0}, "target": {"x": -10.0, "y": 2.0}, "state": "idle", "seq": 1, "connected": true}],
		"dogs": [{"id": "mochi", "position": {"x": -8.0, "y": 3.0}, "state": "wander"}, {"id": "maple", "position": {"x": -3.0, "y": 4.0}, "state": "wander"}], "sheep": sheep}

func _accept(game: Node, snapshot: Dictionary) -> bool:
	game.network.connected = true
	game.network.paused = false
	game._on_status("", true)
	game._on_snapshot(snapshot.duplicate(true))
	return _quietly_armed(game.soundscape, "actual main accepted snapshot")

func _cancel_test_probe(game: Node) -> void:
	# _resume and Android resume exercise the real integration hooks, but their
	# health request is cancelled immediately and targets only closed loopback1.
	game.network.protocol_probe.cancel_request()
	game.network.http.cancel_request()
	game.network.set_process(false)

func _main_lifecycle() -> bool:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.meadow.set_process(false)
	game.network.set_process(false)
	game.network.persist_config = false
	game.network.credentials = SAVED.duplicate(true)
	game.network.endpoint = LOCAL_ENDPOINT
	game.endpoint_input.text = LOCAL_ENDPOINT
	game.network.display_name = "Audio test herder"
	game.name_input.text = game.network.display_name
	var rig: Node = game.soundscape
	rig.set_process(false)
	rig.config_path = preference_path
	rig.persist_preference = true
	rig.set_enabled(true)
	rig.sound_started.connect(_record_sound)
	await process_frame
	if not _disarmed(rig, "actual main welcome") or not game.sound_button.is_visible_in_tree():
		return _fail("welcome must be silent with its small preference available")
	game.preview_mode = true
	game._show_preview()
	game.network.connected = true
	game.network.paused = false
	game._sync_soundscape_gates()
	game._on_snapshot(_snapshot())
	if not _disarmed(rig, "actual main preview"):
		return false
	game.preview_mode = false
	game.network.credentials = SAVED.duplicate(true)
	game._open_settings()
	game._resume()
	_cancel_test_probe(game)
	await process_frame
	if not _disarmed(rig, "actual Return before authoritative snapshot"):
		return false
	var snapshot := _snapshot()
	if not _accept(game, snapshot):
		return false
	var ids := _bank_ids()
	var allocated := rig.get_child_count()
	var prior: Dictionary = rig.debug_state()
	for duplicate in range(100):
		game._on_snapshot(snapshot.duplicate(true))
	if rig.debug_state() != prior:
		return _fail("duplicate actual main snapshots reset active audio or its deadlines")
	game.actors[game.local_id].node.position = game._surface_position(Vector2(-9, 1))
	game._process(0.0)
	var expected_listener: Vector3 = game.actors[game.local_id].node.position + Vector3.UP * 1.2
	if rig.listener.global_position.distance_to(expected_listener) > 0.001 or rig.listener.global_position.distance_to(game.meadow.camera.global_position) < 5:
		return _fail("ambient spatial listener must follow the herder, not the elevated camera")
	for cycle in range(20):
		if not _until_voice(rig):
			return false
		game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		game._on_snapshot(snapshot.duplicate(true))
		game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		if not _disarmed(rig, "focus cycle%d before new receipt" % cycle) or not _accept(game, snapshot):
			return false
		if not _until_voice(rig):
			return false
		game.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		game._on_snapshot(snapshot.duplicate(true))
		game.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_cancel_test_probe(game)
		if not _disarmed(rig, "Android background cycle%d" % cycle) or not _accept(game, snapshot):
			return false
		if not _until_voice(rig):
			return false
		game._open_settings()
		game._on_snapshot(snapshot.duplicate(true))
		game._resume()
		_cancel_test_probe(game)
		await process_frame
		if not _disarmed(rig, "menu/Return cycle%d before new receipt" % cycle) or not _accept(game, snapshot):
			return false
		if not _until_voice(rig):
			return false
		game.network.disconnect_herd()
		game._on_snapshot(snapshot.duplicate(true))
		game.network.connected = true
		game.network.paused = false
		game._on_status("", true)
		if not _disarmed(rig, "reconnect cycle%d before new receipt" % cycle) or not _accept(game, snapshot):
			return false
		if game.network.credentials != SAVED or rig.get_child_count() != allocated or _bank_ids() != ids:
			return _fail("repeated main lifecycle cycles changed credentials or grew audio allocations")
		if game.sound_button.is_visible_in_tree() or game.command_panel.visible or game.sit_button.visible:
			return _fail("sound must not add permanent gameplay controls")
	# A supported same-tick first reconnect snapshot is a valid new receipt.
	# Unknown layouts are not, and must never arm ambience through the error UI.
	game.network.disconnect_herd()
	game.network.connected = true
	game.network.paused = false
	game._on_status("", true)
	var invalid := snapshot.duplicate(true)
	invalid.layout.version = 99
	game._on_snapshot(invalid)
	if not game.network.update_required or not _disarmed(rig, "invalid main snapshot") or game.network.credentials != SAVED:
		return _fail("an unsupported snapshot armed sound or erased the saved invitation")
	game._resume()
	_cancel_test_probe(game)
	await process_frame
	game.network.connected = true
	game.network.paused = false
	game._on_status("", true)
	var no_local := snapshot.duplicate(true)
	no_local.players = []
	game._on_snapshot(no_local)
	if not _disarmed(rig, "snapshot without restored local herder"):
		return false
	invalid = snapshot.duplicate(true)
	invalid.landscape = "unrecognized"
	game._on_snapshot(invalid)
	if not game.network.update_required or not _disarmed(rig, "unrecognized landscape snapshot") or game.network.credentials != SAVED:
		return _fail("an unrecognized landscape armed sound or erased the saved invitation")
	if not await _preferences(game):
		return false
	game.queue_free()
	await process_frame
	if is_instance_valid(game):
		return _fail("main lifecycle fixture did not release its owned scene")
	print("SOUNDSCAPE_LIFECYCLE: 20 actual focus/background/menu/disconnect cycles each, same-tick fresh receipts, invalid snapshots silent, fixed player/cache allocations, isolated preference roundtrip")
	return true

func _preferences(game: Node) -> bool:
	var rig: Node = game.soundscape
	if Soundscape.CONFIG_PATH == Connection.CONFIG_PATH:
		return _fail("audio preference must not share the saved invitation file")
	game._open_settings()
	game.endpoint_input.show()
	await process_frame
	var viewport: Rect2 = root.get_visible_rect()
	if viewport.size != Vector2(720, 1280) or not game.resume_button.is_visible_in_tree():
		return _fail("audio menu coverage must use the real portrait viewport and saved Return")
	var controls := [game.name_input, game.alpine_button, game.cactus_button, game.larch_button, game.orchard_button, game.oasis_button, game.cloud_button, game.juniper_button, game.bellflower_button, game.long_valley_button, game.dry_wash_button, game.create_button, game.invite_input, game.join_button, game.resume_button, game.endpoint_input]
	var settings_buttons := 0
	for child in game.sound_button.get_parent().get_children():
		if child is Button:
			settings_buttons += 1
			controls.append(child)
			if child.size.y < 64.0:
				return _fail("Sound, Server address and Soft distance must retain64px logical touch targets")
	if settings_buttons != 3 or game.soft_distance_button.get_parent() != game.sound_button.get_parent():
		return _fail("Sound, Server address and Soft distance must share exactly one small settings row")
	for control in controls:
		if not control.is_visible_in_tree() or not viewport.encloses(control.get_global_rect()):
			return _fail("saved Return and expanded server/audio settings do not fit the actual720x1280 portrait menu")
	game.sound_button.pressed.emit()
	if rig.enabled or not game.sound_button.text.ends_with("off") or not _disarmed(rig, "actual menu sound off"):
		return _fail("menu sound preference did not turn off and stop playback")
	var config := ConfigFile.new()
	if config.load(preference_path) != OK or config.get_sections() != PackedStringArray(["sound"]) or config.get_section_keys("sound") != PackedStringArray(["enabled"]) or config.get_value("sound", "enabled") != false:
		return _fail("sound preference must persist separately as a single boolean")
	var restored := Soundscape.new()
	restored.config_path = preference_path
	restored.random_seed = 441
	root.add_child(restored)
	restored.set_process(false)
	if restored.enabled or not _disarmed(restored, "restored muted preference"):
		return _fail("muted preference did not survive soundscape recreation")
	restored.queue_free()
	await process_frame
	game.sound_button.pressed.emit()
	if not rig.enabled or not game.sound_button.text.ends_with("on") or not _disarmed(rig, "menu sound on without a fresh snapshot"):
		return _fail("enabling sound must stay quiet until returning to a fresh world")
	if config.load(preference_path) != OK or config.get_value("sound", "enabled") != true or game.network.credentials != SAVED:
		return _fail("audio preference roundtrip changed or mixed with invitation credentials")
	return true

func _fail(message: String) -> bool:
	push_error("SOUNDSCAPE_SMOKE_FAILED: " + message)
	quit(1)
	return false
