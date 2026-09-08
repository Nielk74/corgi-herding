class_name GentleTutorial
extends RefCounted
## Optional, presentation-only teaching. There are no timers, rewards or saves.
## The caller must pass ONLY snapshots already accepted by the normal network /
## canonical-layout path, and record_local_action only after a local input was
## actually emitted. Selection is the one explicitly local-only lesson.
##
## Commands and interactions have no server nonce. A fresh local request followed
## by a newer observed result is useful lesson evidence, NOT a packet ACK. An
## identical repeated command may therefore count; a cached snapshot never does.
## Change connection epoch on every reconnect. Its first snapshot only establishes
## a baseline, even if a retained route/command already has the desired result.

signal lesson_changed(stage: String, instruction: String, why: String)
signal lesson_advanced(previous: String, current: String, reason: String)
signal finished(reason: String)

const LESSONS := ["walk", "select", "come", "stay", "place", "pressure", "withdraw", "care", "freeplay"]
const COPY := {
	"walk": ["Tap some grass to walk there.", "Your herder walks while you look around."],
	"select": ["Tap either corgi.", "Both herders can ask either dog for help."],
	"come": ["Ask your selected corgi to Come.", "Give them room to reach you."],
	"stay": ["Tap your corgi again, then choose Stay.", "They can hold a helpful spot while you move."],
	"place": ["Tap your corgi, choose Go, then tap some grass.", "Or drag your corgi there. Position matters more than speed."],
	"pressure": ["Place your corgi beside a few sheep and watch.", "Sheep move away from a nearby dog; leave them a way through."],
	"withdraw": ["Call your corgi away from the sheep, or place them farther away.", "With room around them, the sheep can settle and graze."],
	"care": ["Walk close to your corgi and Pet, or sit in the grass.", "Rest and affection belong here too."],
	"freeplay": ["", ""],
}
const EXACT_INTEGER_LIMIT := 9007199254740991.0
const TARGET_TOLERANCE := 0.01
const WALK_REACHED := 0.12
const DOG_REACHED := 0.2
const DOG_PRESSURE := 4.1
const HERDER_PRESSURE := 2.0
const PET_REACH := 2.5 # Server XY distance, never camera/mesh height.

var _tutorial_mode := false
var _enabled := false
var _code := ""
var _local_id := ""
var _landscape := ""
var _lesson := 0
var _epoch := -1
var _connected := false
var _fresh := false
var _last_tick := -1
var _latest: Dictionary = {}
var _layout: Dictionary = {}
var _animal_ids: Array = []
var _selected := ""
var _pending: Dictionary = {}
var _pressure_sheep: Array[String] = []

func configure(tutorial_mode: bool, herd_code: String, local_player_id: String, landscape_id: String) -> void:
	_tutorial_mode = tutorial_mode and not herd_code.is_empty() and not local_player_id.is_empty() and not landscape_id.is_empty()
	_enabled = _tutorial_mode
	_code = herd_code
	_local_id = local_player_id
	_landscape = landscape_id
	_lesson = 0
	_epoch = -1
	_connected = false
	_fresh = false
	_last_tick = -1
	_latest.clear()
	_layout.clear()
	_animal_ids.clear()
	_selected = ""
	_pending.clear()
	_pressure_sheep.clear()
	_publish_hint()

func set_connection(epoch: int, connected: bool) -> bool:
	if epoch < 0 or epoch < _epoch:
		return false
	# A closed connection cannot be reopened under its old identity. Late events
	# from that socket must not be mistaken for receipts from the replacement.
	if connected and epoch == _epoch and not _connected:
		return false
	if epoch == _epoch and connected == _connected:
		return true
	_epoch = epoch
	_connected = connected
	_fresh = false
	_last_tick = -1
	_latest.clear()
	_pending.clear()
	_publish_hint()
	return true

func observe_snapshot(snapshot: Dictionary, epoch: int) -> bool:
	if not _enabled or not _connected or epoch != _epoch or not _valid_snapshot(snapshot):
		return false
	var tick := int(snapshot.tick)
	if tick <= _last_tick:
		return false
	var previous := _latest
	_latest = snapshot.duplicate(true)
	_last_tick = tick
	if not _fresh:
		_fresh = true
		_pending.clear()
		if _layout.is_empty():
			_layout = snapshot.layout.duplicate(true)
			_animal_ids = _ids(snapshot.dogs) + _ids(snapshot.sheep)
		_publish_hint()
		return true
	if not _pending.is_empty() and tick > int(_pending.tick):
		_evaluate(previous)
	return true

func select_dog(dog_id: String, epoch: int) -> bool:
	if not _can_record(epoch) or _actor(_latest.dogs, dog_id).is_empty():
		return false
	_selected = dog_id
	_pending.clear()
	if stage() == "select":
		_pending = {"kind": "select", "dog_id": dog_id, "tick": _last_tick}
	return true

func record_local_action(message: Dictionary, epoch: int) -> bool:
	if not _can_record(epoch):
		return false
	if not _valid_action(message):
		return false
	var kind: String = message.type
	if kind == "move" and (int(message.seq) <= int(_actor(_latest.players, _local_id).seq) or (_pending.get("kind") == "move" and int(message.seq) <= int(_pending.seq))):
		return false
	if (kind == "command" or (kind == "interact" and message.action == "pet")) and _actor(_latest.dogs, message.dog_id).is_empty():
		return false
	# Moving/sitting beside a commanded dog or helping the other dog does not
	# replace that dog's intent. Preserve its original receipt boundary; only a
	# genuinely conflicting action can cancel or replace existing evidence.
	if _conflicts_with_pending(message):
		_pending.clear()
	var current := stage()
	if kind == "move":
		if current != "walk":
			return false
		var player := _actor(_latest.players, _local_id)
		if int(message.seq) <= int(player.seq) or _distance(message.target, player.position) < 0.25:
			return false
	elif kind == "command":
		if String(message.dog_id) != _selected or _actor(_latest.dogs, _selected).is_empty():
			return false
		var command: String = message.command
		if not ((current == "come" and command == "come") or (current == "stay" and command == "stay") or (current in ["place", "pressure"] and command == "go") or (current == "withdraw" and command in ["come", "go"])):
			return false
	elif kind == "interact":
		if current != "care" or (message.action == "pet" and (String(message.dog_id) != _selected or _actor(_latest.dogs, _selected).is_empty())):
			return false
	_pending = message.duplicate(true)
	_pending.kind = kind
	_pending.tick = _last_tick
	return true

func _conflicts_with_pending(message: Dictionary) -> bool:
	if _pending.is_empty():
		return false
	match String(_pending.kind):
		"command":
			return (message.type == "command" and message.dog_id == _pending.dog_id) or (message.type == "interact" and message.action == "pet" and message.dog_id == _pending.dog_id)
		"move":
			return message.type in ["move", "interact"] # Sit/Pet stop the herder.
		"interact":
			return message.type in ["move", "interact"] or (_pending.action == "pet" and message.type == "command" and message.dog_id == _pending.dog_id)
	return false

func skip_current_lesson() -> void:
	if _enabled and stage() != "freeplay":
		_advance("manual")

func skip() -> void:
	if not _enabled:
		return
	_enabled = false
	_pending.clear()
	_publish_hint()
	finished.emit("skipped")

func restart() -> void:
	if not _tutorial_mode:
		return
	_enabled = true
	_lesson = 0
	_fresh = false
	_latest.clear()
	_pending.clear()
	_selected = ""
	_pressure_sheep.clear()
	# Keep this epoch's high-water tick: restart does not make cached data fresh.
	_publish_hint()

func stage() -> String:
	return LESSONS[_lesson]

func hint() -> Dictionary:
	var visible := _enabled and _connected and _fresh and stage() != "freeplay"
	return {"visible": visible, "stage": stage(), "instruction": COPY[stage()][0] if visible else "", "why": COPY[stage()][1] if visible else ""}

func debug_state() -> Dictionary:
	return {"enabled": _enabled, "stage": stage(), "epoch": _epoch, "connected": _connected, "fresh": _fresh, "last_tick": _last_tick, "pending": not _pending.is_empty(), "selected_dog": _selected, "pressure_sheep": _pressure_sheep.size()}

func _can_record(epoch: int) -> bool:
	return _enabled and _connected and _fresh and epoch == _epoch and stage() != "freeplay"

func _evaluate(previous: Dictionary) -> void:
	var player := _actor(_latest.players, _local_id)
	var dog := _actor(_latest.dogs, _selected)
	match stage():
		"walk":
			if int(player.seq) == int(_pending.seq) and _distance(player.target, _pending.target) <= TARGET_TOLERANCE and _distance(player.position, _pending.target) <= WALK_REACHED and player.state == "idle":
				_advance()
		"select":
			if not dog.is_empty() and _pending.dog_id == _selected:
				_advance()
		"come", "stay", "place":
			if _command_result(dog, player, true):
				# The same real Go can introduce its observed sheep effect on a later
				# snapshot. It cannot finish two lessons from one receipt.
				var carry := _pending.duplicate(true) if stage() == "place" else {}
				_advance()
				if not carry.is_empty():
					carry.tick = _last_tick
					_pending = carry
		"pressure":
			if not _command_result(dog, player, false):
				return
			var observed: Array[String] = []
			for sheep: Dictionary in _latest.sheep:
				var before := _actor(previous.sheep, sheep.id)
				var distance := _distance(sheep.position, dog.position)
				if before.is_empty() or distance < 0.01 or distance >= DOG_PRESSURE or sheep.state not in ["walking", "fleeing"] or _other_pressure(sheep, dog.id):
					continue
				var away_x := (float(sheep.position.x) - float(dog.position.x)) / distance
				var away_y := (float(sheep.position.y) - float(dog.position.y)) / distance
				var speed := float(sheep.velocity.x) * away_x + float(sheep.velocity.y) * away_y
				var movement := (float(sheep.position.x) - float(before.position.x)) * away_x + (float(sheep.position.y) - float(before.position.y)) * away_y
				if speed > 0.1 and movement > 0.001:
					observed.append(sheep.id)
			if not observed.is_empty():
				_pressure_sheep = observed
				_advance()
		"withdraw":
			if not _command_result(dog, player, true):
				return
			var observed := 0
			for sheep: Dictionary in _latest.sheep:
				if not _pressure_sheep.is_empty() and sheep.id not in _pressure_sheep:
					continue
				if sheep.state != "grazing" or _distance(sheep.position, dog.position) < DOG_PRESSURE or _other_pressure(sheep, dog.id):
					return
				observed += 1
			if observed > 0:
				_advance()
		"care":
			if _pending.action == "sit":
				if player.state == "sitting" and _distance(player.target, player.position) <= TARGET_TOLERANCE:
					_advance()
			elif not dog.is_empty() and player.state == "petting" and dog.state == "happy" and dog.command == "stay" and _distance(player.position, dog.position) <= PET_REACH and _distance(dog.position, dog.target) <= TARGET_TOLERANCE and _distance(player.position, player.target) <= TARGET_TOLERANCE:
				# Pet intentionally does not change dog.caller on the Go server.
				_advance()

func _command_result(dog: Dictionary, player: Dictionary, reached: bool) -> bool:
	if dog.is_empty() or dog.get("caller", "") != _local_id or dog.command != _pending.command:
		return false
	match String(_pending.command):
		"come":
			return _distance(dog.target, player.position) <= TARGET_TOLERANCE and (not reached or (dog.state == "attentive" and _distance(dog.position, player.position) <= 1.2))
		"stay":
			return dog.state == "stay" and _distance(dog.target, dog.position) <= TARGET_TOLERANCE
		"go":
			return _distance(dog.target, _pending.target) <= TARGET_TOLERANCE and (not reached or (dog.state == "attentive" and _distance(dog.position, _pending.target) <= DOG_REACHED))
	return false

func _other_pressure(sheep: Dictionary, selected_id: String) -> bool:
	for dog: Dictionary in _latest.dogs:
		if dog.id != selected_id and _distance(dog.position, sheep.position) < DOG_PRESSURE:
			return true
	for player: Dictionary in _latest.players:
		if _distance(player.position, sheep.position) < HERDER_PRESSURE:
			return true
	return false

func _advance(reason: String = "observed") -> void:
	var previous := stage()
	_lesson = mini(_lesson + 1, LESSONS.size() - 1)
	_pending.clear()
	lesson_advanced.emit(previous, stage(), reason)
	_publish_hint()
	if stage() == "freeplay":
		finished.emit(reason)

func _publish_hint() -> void:
	var current := hint()
	lesson_changed.emit(current.stage, current.instruction, current.why)

func _valid_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.get("type") != "snapshot" or snapshot.get("code") != _code or snapshot.get("landscape") != _landscape or not _integer(snapshot.get("tick")):
		return false
	if not snapshot.get("layout") is Dictionary or snapshot.layout.is_empty() or (not _layout.is_empty() and snapshot.layout != _layout):
		return false
	if not snapshot.get("players") is Array or not snapshot.get("dogs") is Array or not snapshot.get("sheep") is Array:
		return false
	if snapshot.players.size() < 1 or snapshot.players.size() > 2 or snapshot.dogs.size() != 2 or snapshot.sheep.is_empty() or snapshot.sheep.size() > 40:
		return false
	var seen: Dictionary = {}
	for category: String in ["players", "dogs", "sheep"]:
		for value: Variant in snapshot[category]:
			if not value is Dictionary or not value.get("id") is String or value.id.is_empty() or seen.has(value.id) or not _point(value.get("position")) or not value.get("state") is String:
				return false
			seen[value.id] = true
			if category != "sheep" and not _point(value.get("target")):
				return false
			if category == "players" and (not _integer(value.get("seq")) or not value.get("connected") is bool):
				return false
			if category == "dogs" and (not value.get("command") is String or not value.get("caller", "") is String):
				return false
			if category == "sheep" and not _point(value.get("velocity")):
				return false
	var player := _actor(snapshot.players, _local_id)
	if player.is_empty() or not player.connected:
		return false
	if not _animal_ids.is_empty() and _animal_ids != _ids(snapshot.dogs) + _ids(snapshot.sheep):
		return false
	return true

func _valid_action(message: Dictionary) -> bool:
	match message.get("type", ""):
		"move":
			return _keys(message, ["type", "seq", "target"]) and _integer(message.get("seq")) and float(message.seq) > 0 and _point(message.get("target"))
		"command":
			if not message.get("dog_id") is String:
				return false
			if message.get("command") == "go":
				return _keys(message, ["type", "dog_id", "command", "target"]) and _point(message.get("target"))
			return message.get("command") in ["come", "stay"] and _keys(message, ["type", "dog_id", "command"])
		"interact":
			if message.get("action") == "sit":
				return _keys(message, ["type", "action", "dog_id"]) and message.dog_id == ""
			return message.get("action") == "pet" and message.get("dog_id") is String and _keys(message, ["type", "action", "dog_id"])
	return false

static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= EXACT_INTEGER_LIMIT and floorf(float(value)) == float(value)

static func _point(value: Variant) -> bool:
	if not value is Dictionary or not _keys(value, ["x", "y"]):
		return false
	return (value.x is int or value.x is float) and (value.y is int or value.y is float) and is_finite(float(value.x)) and is_finite(float(value.y))

static func _distance(a: Dictionary, b: Dictionary) -> float:
	# Scalar doubles preserve the server's inclusive 2.5m interaction boundary.
	var dx := float(a.x) - float(b.x)
	var dy := float(a.y) - float(b.y)
	return sqrt(dx * dx + dy * dy)

static func _actor(actors: Array, id: String) -> Dictionary:
	for value: Dictionary in actors:
		if value.id == id:
			return value
	return {}

static func _ids(actors: Array) -> Array:
	var result: Array = []
	for value: Dictionary in actors:
		result.append(value.id)
	result.sort()
	return result
