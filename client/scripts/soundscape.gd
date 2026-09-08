class_name HerdSoundscape
extends Node3D
## Local, non-looping ambience. No gameplay event is inferred from a snapshot.
## Synthesis happens once per process; the frame loop only schedules cached clips.

signal enabled_changed(value: bool)
signal sound_started(kind: String, sample_id: String)

const CONFIG_PATH := "user://audio.cfg"
const SAMPLE_RATE := 22050
const MAX_DECODED_BYTES := 1048576
const LISTENER_HEIGHT := 1.2
const WIND_GAP := Vector2(28.0, 52.0)
const BIRD_GAP := Vector2(42.0, 86.0)
const FIRST_WIND := Vector2(9.0, 16.0)
const FIRST_BIRD := Vector2(24.0, 42.0)
const AndroidOutput = preload("res://scripts/android_ambience.gd")

static var _bank: Dictionary = {}
static var _bank_bytes := 0
static var _bank_builds := 0

var config_path := CONFIG_PATH
var persist_preference := true
var random_seed := 0
var enabled := true
var foreground := true
var focused := true
var gameplay_visible := false
var connected := false
var fresh_snapshot := false
var active := false
var wind_events := 0
var bird_events := 0
var wind_in := INF
var bird_in := INF
var wind_remaining := 0.0
var bird_remaining := 0.0
var listener: AudioListener3D
var wind_player: AudioStreamPlayer
var bird_player: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()
var android_output: RefCounted

func _ready() -> void:
	_load_preference()
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	_ensure_bank()
	if OS.has_feature("android"):
		android_output = AndroidOutput.new()
	listener = AudioListener3D.new()
	listener.name = "HerderListener"
	add_child(listener)
	# The fixed camera's horizontal bearing, without its elevated position/tilt.
	listener.rotation.y = atan2(8.0, 38.0)
	wind_player = AudioStreamPlayer.new()
	wind_player.name = "WindBreath"
	wind_player.max_polyphony = 1
	wind_player.volume_db = -16.0
	add_child(wind_player)
	bird_player = AudioStreamPlayer3D.new()
	bird_player.name = "DistantBird"
	bird_player.max_polyphony = 1
	bird_player.volume_db = -17.0
	bird_player.max_db = -10.0
	bird_player.unit_size = 12.0
	bird_player.max_distance = 42.0
	bird_player.panning_strength = 0.65
	bird_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(bird_player)
	# Never autoplay, including a welcome preview or scene restored from disk.
	_disarm()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			set_foreground(false)
		NOTIFICATION_APPLICATION_RESUMED:
			set_foreground(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			set_focused(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			set_focused(true)
		NOTIFICATION_PAUSED:
			_disarm()

func _exit_tree() -> void:
	_disarm()

func _process(delta: float) -> void:
	advance(delta)

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_disarm()
	if persist_preference:
		var config := ConfigFile.new()
		config.set_value("sound", "enabled", enabled)
		if config.save(config_path) != OK:
			push_warning("Sound preference could not be saved.")
	enabled_changed.emit(enabled)

func set_foreground(value: bool) -> void:
	if foreground != value:
		foreground = value
		_disarm()

func set_focused(value: bool) -> void:
	if focused != value:
		focused = value
		_disarm()

func set_gameplay_visible(value: bool) -> void:
	if gameplay_visible != value:
		gameplay_visible = value
		_disarm()

func set_connected(value: bool) -> void:
	if connected != value:
		connected = value
		_disarm()

func invalidate_snapshot() -> void:
	# Also used when replacing a herd without first closing the menu.
	_disarm()

func observe_snapshot() -> void:
	# A queued snapshot received behind a menu or while unfocused is not fresh
	# enough to start sound later. Repeated valid snapshots do not reset timers.
	if not _gates_open() or fresh_snapshot:
		return
	fresh_snapshot = true
	active = true
	listener.make_current()
	_quiet_start()

func set_listener_position(herder_position: Vector3) -> void:
	if listener != null:
		listener.global_position = herder_position + Vector3.UP * LISTENER_HEIGHT

func _gates_open() -> bool:
	return enabled and foreground and focused and gameplay_visible and connected and is_inside_tree() and not get_tree().paused

func _disarm() -> void:
	active = false
	fresh_snapshot = false
	wind_in = INF
	bird_in = INF
	_stop_voices()
	if listener != null:
		listener.clear_current()

func _stop_voices() -> void:
	if android_output != null:
		android_output.stop_all()
	if wind_player != null:
		wind_player.stop()
	if bird_player != null:
		bird_player.stop()
	wind_remaining = 0.0
	bird_remaining = 0.0

func _quiet_start() -> void:
	wind_in = rng.randf_range(FIRST_WIND.x, FIRST_WIND.y)
	bird_in = rng.randf_range(FIRST_BIRD.x, FIRST_BIRD.y)

func advance(delta: float) -> void:
	if not active:
		return
	if not _gates_open():
		_disarm()
		return
	if not is_finite(delta) or delta < 0.0:
		return
	if delta > 1.0:
		# A suspended or stalled frame must never replay a backlog of birds.
		_stop_voices()
		_quiet_start()
		return
	wind_remaining = maxf(0.0, wind_remaining - delta)
	bird_remaining = maxf(0.0, bird_remaining - delta)
	if wind_remaining == 0.0:
		wind_player.stop()
		if android_output != null:
			android_output.stop_voice("wind")
	if bird_remaining == 0.0:
		bird_player.stop()
		if android_output != null:
			android_output.stop_voice("bird")
	wind_in -= delta
	bird_in -= delta
	if wind_in <= 0.0:
		var sample_id := "wind_%d" % rng.randi_range(0, 1)
		var stream: AudioStreamWAV = _bank[sample_id]
		wind_player.stream = stream
		var played := true
		if android_output != null:
			played = android_output.play_voice("wind", stream, Vector2.ONE * db_to_linear(wind_player.volume_db))
		else:
			wind_player.play()
		wind_remaining = stream.get_length() if played else 0.0
		wind_in = stream.get_length() + rng.randf_range(WIND_GAP.x, WIND_GAP.y)
		if played:
			wind_events += 1
			sound_started.emit("wind", sample_id)
	if bird_in <= 0.0:
		var sample_id := "bird_%d" % rng.randi_range(0, 2)
		var stream: AudioStreamWAV = _bank[sample_id]
		# A distant point relative to the herder, not the high camera. No object
		# tracking or per-animal sound players are needed for this local ambience.
		var angle := rng.randf_range(-PI, PI)
		var distance := rng.randf_range(10.0, 18.0)
		bird_player.global_position = listener.global_position + Vector3(cos(angle) * distance, rng.randf_range(2.0, 5.0), sin(angle) * distance)
		bird_player.stream = stream
		var played := true
		if android_output != null:
			var offset := bird_player.global_position - listener.global_position
			var gain := db_to_linear(bird_player.volume_db) * minf(1.0, bird_player.unit_size / maxf(offset.length(), 0.001))
			var pan := clampf(offset.normalized().dot(listener.global_basis.x) * bird_player.panning_strength, -1.0, 1.0)
			played = android_output.play_voice("bird", stream, Vector2(1.0 - maxf(pan, 0.0), 1.0 + minf(pan, 0.0)) * gain)
		else:
			bird_player.play()
		bird_remaining = stream.get_length() if played else 0.0
		bird_in = stream.get_length() + rng.randf_range(BIRD_GAP.x, BIRD_GAP.y)
		if played:
			bird_events += 1
			sound_started.emit("bird", sample_id)
	if android_output != null and android_output.failed:
		# A backend failure releases both slots; diagnostic voice counts must not
		# claim that the other clip is still audible. Never fall back to OpenSL.
		android_output.stop_all()
		wind_remaining = 0.0
		bird_remaining = 0.0

func debug_state() -> Dictionary:
	return {"enabled": enabled, "foreground": foreground, "focused": focused,
		"gameplay_visible": gameplay_visible, "connected": connected,
		"fresh_snapshot": fresh_snapshot, "active": active,
		"voices": int(wind_remaining > 0.0) + int(bird_remaining > 0.0),
		"allocated_players": int(wind_player != null) + int(bird_player != null),
		"wind_remaining": wind_remaining, "bird_remaining": bird_remaining,
		"wind_in": wind_in, "bird_in": bird_in,
		"wind_events": wind_events, "bird_events": bird_events,
		"android_tracks": android_output.tracks.size() if android_output != null else 0,
		"android_failed": android_output.failed if android_output != null else false,
		"bank_bytes": _bank_bytes, "bank_builds": _bank_builds}

static func cached_streams() -> Dictionary:
	_ensure_bank()
	return _bank.duplicate()

func _load_preference() -> void:
	if not persist_preference:
		return
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		var value: Variant = config.get_value("sound", "enabled", true)
		enabled = value if value is bool else true

static func _ensure_bank() -> void:
	if not _bank.is_empty():
		return
	_bank["wind_0"] = _wind(4.6, 4127)
	_bank["wind_1"] = _wind(5.8, 9301)
	_bank["bird_0"] = _bird(0.82, 0)
	_bank["bird_1"] = _bird(1.04, 1)
	_bank["bird_2"] = _bird(0.67, 2)
	for stream: AudioStreamWAV in _bank.values():
		_bank_bytes += stream.data.size()
	_bank_builds += 1
	assert(_bank_bytes <= MAX_DECODED_BYTES)

static func _wind(duration: float, seed_value: int) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(duration * SAMPLE_RATE))
	var noise := RandomNumberGenerator.new()
	noise.seed = seed_value
	var fast := 0.0
	var slow := 0.0
	for i in samples.size():
		var t := float(i) / SAMPLE_RATE
		var white := noise.randf_range(-1.0, 1.0)
		fast += (white - fast) * 0.28
		slow += (white - slow) * 0.055
		var envelope := pow(sin(PI * float(i) / (samples.size() - 1)), 2.0)
		var gust := 0.72 + 0.18 * sin(t * 2.2) + 0.1 * sin(t * 5.1 + 0.8)
		samples[i] = (fast - slow) * envelope * gust
	return _pcm(samples, 0.7)

static func _bird(duration: float, variant: int) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(duration * SAMPLE_RATE))
	var notes: Array[Vector2] = [Vector2(0.09, 0.24), Vector2(0.39, 0.58)]
	if variant == 1:
		notes = [Vector2(0.13, 0.36), Vector2(0.62, 0.82)]
	elif variant == 2:
		notes = [Vector2(0.08, 0.21), Vector2(0.3, 0.44), Vector2(0.5, 0.59)]
	for note_index in notes.size():
		var note := notes[note_index]
		var phase := 0.0
		var start := int(note.x * SAMPLE_RATE)
		var end := int(note.y * SAMPLE_RATE)
		for i in range(start, end):
			var progress := float(i - start) / (end - start - 1)
			var pitch := 2050.0 + variant * 230.0 + note_index * 130.0
			pitch += sin(progress * PI) * 580.0 - progress * 320.0
			phase += TAU * pitch / SAMPLE_RATE
			var envelope := pow(sin(PI * progress), 2.0)
			samples[i] = (sin(phase) + 0.08 * sin(phase * 2.0)) * envelope
	return _pcm(samples, 0.45)

static func _pcm(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var largest := 0.000001
	for sample in samples:
		largest = maxf(largest, absf(sample))
	var gain := peak / largest
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i] * gain, -0.95, 0.95) * 32767.0)
		# Signed, little-endian 16-bit PCM; zero-envelope endpoints avoid clicks.
		data[i * 2] = value & 255
		data[i * 2 + 1] = (value >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
