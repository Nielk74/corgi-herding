class_name AndroidAmbience
extends RefCounted
## Two bounded, disposable Android PCM voices. Godot 4.6.3's OpenSL output
## retains already mixed PCM across pause; those buffers cannot be flushed from
## AudioServer. Static AudioTracks are instead released on every interruption.
## No custom export template, plugin, network access or media permission needed.

const USAGE_GAME := 14
const CONTENT_TYPE_MUSIC := 2
const CHANNEL_OUT_MONO := 4
const ENCODING_PCM_16BIT := 2
const MODE_STATIC := 0
const AUDIO_SESSION_ID_GENERATE := 0
const WRITE_NON_BLOCKING := 1
const STATE_INITIALIZED := 1

var failed := false
var tracks: Dictionary = {}
var _attributes: Variant
var _format: Variant
var _track_class: Variant

func _init() -> void:
	if not OS.has_feature("android"):
		failed = true
		return
	var attributes_class := JavaClassWrapper.wrap("android.media.AudioAttributes$Builder")
	var attributes_builder: Variant = _invoke(attributes_class, "AudioAttributes$Builder")
	_invoke(attributes_builder, "setUsage", [USAGE_GAME])
	_invoke(attributes_builder, "setContentType", [CONTENT_TYPE_MUSIC])
	_attributes = _invoke(attributes_builder, "build")
	var format_class := JavaClassWrapper.wrap("android.media.AudioFormat$Builder")
	var format_builder: Variant = _invoke(format_class, "AudioFormat$Builder")
	_invoke(format_builder, "setEncoding", [ENCODING_PCM_16BIT])
	_invoke(format_builder, "setSampleRate", [22050])
	_invoke(format_builder, "setChannelMask", [CHANNEL_OUT_MONO])
	_format = _invoke(format_builder, "build")
	_track_class = JavaClassWrapper.wrap("android.media.AudioTrack")
	_check_exception()

func play_voice(kind: String, stream: AudioStreamWAV, gains: Vector2) -> bool:
	if failed:
		stop_all()
		return false
	if kind not in ["wind", "bird"]:
		return false
	stop_voice(kind)
	if failed:
		stop_all()
		return false
	var data := stream.data
	var track: Variant = _invoke(_track_class, "AudioTrack", [_attributes, _format, data.size(), MODE_STATIC, AUDIO_SESSION_ID_GENERATE])
	if track == null:
		_fail()
		stop_all()
		return false
	# Retain immediately so every subsequent error can still release ownership.
	tracks[kind] = track
	var written: Variant = _invoke(track, "write", [data, 0, data.size(), WRITE_NON_BLOCKING])
	var state: Variant = _invoke(track, "getState")
	if failed or written != data.size() or state != STATE_INITIALIZED:
		_fail()
		stop_all()
		return false
	# This stereo-only gain API is deliberate: our mono bird source needs mild
	# left/right placement. Android handles the final speaker/headphone downmix.
	var result: Variant = _invoke(track, "setStereoVolume", [clampf(gains.x, 0.0, 1.0), clampf(gains.y, 0.0, 1.0)])
	if failed or result != 0:
		_fail()
		stop_all()
		return false
	_invoke(track, "play")
	if failed:
		stop_all()
	return not failed

func stop_voice(kind: String) -> void:
	if not tracks.has(kind):
		return
	var track: Variant = tracks[kind]
	tracks.erase(kind)
	# Do not skip cleanup after a failed API call. Static flush() is a no-op;
	# release destroys the native voice rather than pausing it for later replay.
	track.call("pause")
	_check_exception()
	track.call("release")
	_check_exception()

func stop_all() -> void:
	for kind: String in tracks.keys():
		stop_voice(kind)

func _invoke(target: Variant, method: String, args: Array = []) -> Variant:
	if failed or target == null:
		_fail()
		return null
	var result: Variant = target.callv(method, args)
	_check_exception()
	return null if failed else result

func _check_exception() -> void:
	if JavaClassWrapper.get_exception() != null:
		_fail()

func _fail() -> void:
	if not failed:
		push_warning("Android ambience is unavailable; keeping this session quiet.")
	failed = true
