extends SceneTree
## Replay accepted authoritative-shaped snapshots through the optional teaching
## module. This is not a live-network test or a claim of command packet ACKs.

const Tutorial = preload("res://scripts/gentle_tutorial.gd")
const Commons = preload("res://scripts/commons_navigation.gd")
var checks := 0
var failures := 0
var flows := 0
var advanced: Array = []
var finished_reasons: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var files_before := _preference_hashes()
	_modes_and_freshness()
	for local_id: String in ["herder-a", "herder-b"]:
		for dog_id: String in ["mochi", "maple"]:
			_full_flow(local_id, dog_id)
	_movement_and_selection()
	_commands_and_reconnect()
	_nonconflicting_actions()
	_pressure_and_care()
	_malformed_receipts()
	_malformed_actions()
	_restart_and_skip()
	for path: String in ["res://scripts/gentle_tutorial.gd.uid", "res://tests/gentle_tutorial_smoke.gd.uid"]:
		var uid := FileAccess.get_file_as_string(path).strip_edges()
		_check(ResourceUID.text_to_id(uid) > 0 and ResourceUID.id_to_text(ResourceUID.text_to_id(uid)) == uid, "persisted script UID is valid: " + path)
	_check(_preference_hashes() == files_before, "tutorial does not write audio or invitation preferences")
	print("GENTLE_TUTORIAL_SMOKE: %d checks, %d failures; %d authoritative-shaped flows, both humans/dogs, fresh epochs, idempotent results, ambiguous pressure, manual skips, exact 2D pet reach; no packet-ACK or live-network claim" % [checks, failures, flows])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("GENTLE_TUTORIAL_FAILED: " + message)

func _point(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y}

func _snapshot(tick: int = 10) -> Dictionary:
	var sheep: Array = []
	for index in 10:
		sheep.append({"id": "sheep-%d" % index, "position": _point(9 + (index % 3) * 0.2, -6 + (index / 3) * 0.2), "velocity": _point(0, 0), "state": "grazing", "group": 0})
	# JSON numbers deliberately pass through the same float-decoding step as
	# real incoming snapshots, rather than using only hand-typed integer fields.
	return JSON.parse_string(JSON.stringify({"type": "snapshot", "tick": tick, "code": "GUIDE1", "landscape": "bellflower", "layout": Commons.layout(), "gate_open": false, "settled": 0,
		"players": [{"id": "herder-a", "name": "Herder", "position": _point(-7, 0), "target": _point(-7, 0), "seq": 0, "state": "idle", "connected": true}, {"id": "herder-b", "name": "Herder", "position": _point(-9, 4), "target": _point(-9, 4), "seq": 0, "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "name": "Mochi", "position": _point(-6, 2), "target": _point(-6, 2), "command": "stay", "state": "stay"}, {"id": "maple", "name": "Maple", "position": _point(-8, 3), "target": _point(-8, 3), "command": "stay", "state": "stay"}], "sheep": sheep}))

func _next(snapshot: Dictionary) -> Dictionary:
	var value := snapshot.duplicate(true)
	value.tick = float(value.tick) + 1
	return value

func _actor(actors: Array, id: String) -> Dictionary:
	for actor: Dictionary in actors:
		if actor.id == id:
			return actor
	return {}

func _fresh(stage: String = "walk", local_id: String = "herder-a", dog_id: String = "mochi") -> Dictionary:
	var guide := Tutorial.new()
	guide.configure(true, "GUIDE1", local_id, "bellflower")
	_check(guide.set_connection(1, true), "new epoch accepted")
	var snapshot := _snapshot()
	_check(guide.observe_snapshot(snapshot, 1), "fresh epoch receives baseline")
	while guide.stage() != stage:
		guide.skip_current_lesson()
	if stage not in ["walk", "select", "freeplay"]:
		_check(guide.select_dog(dog_id, 1), "local dog selection can prepare any optional lesson")
	return {"guide": guide, "snapshot": snapshot}

func _move(seq: int, target: Dictionary) -> Dictionary:
	return {"type": "move", "seq": seq, "target": target}

func _command(command: String, dog_id: String = "mochi", target: Dictionary = {}) -> Dictionary:
	var value := {"type": "command", "dog_id": dog_id, "command": command}
	if command == "go":
		value.target = target
	return value

func _sit() -> Dictionary:
	# Match Connection.interact's actual empty dog_id field, not a made-up shape.
	return {"type": "interact", "action": "sit", "dog_id": ""}

func _pet(dog_id: String = "mochi") -> Dictionary:
	return {"type": "interact", "action": "pet", "dog_id": dog_id}

func _arm(guide: RefCounted, message: Dictionary, epoch: int = 1) -> void:
	var before: String = guide.stage()
	_check(guide.record_local_action(message, epoch), "fresh local action arms " + before)
	_check(guide.stage() == before, "local emission alone never completes " + before)

func _result(snapshot: Dictionary, local_id: String, dog_id: String, command: String, target: Dictionary = {}) -> void:
	var player := _actor(snapshot.players, local_id)
	var dog := _actor(snapshot.dogs, dog_id)
	dog.command = command
	dog.caller = local_id
	if command == "come":
		dog.position = _point(float(player.position.x) + 0.8, player.position.y)
		dog.target = player.position.duplicate()
		dog.state = "attentive"
	elif command == "stay":
		dog.target = dog.position.duplicate()
		dog.state = "stay"
	else:
		dog.position = target.duplicate()
		dog.target = target.duplicate()
		dog.state = "attentive"

func _modes_and_freshness() -> void:
	for landscape: String in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper", "bellflower"]:
		var guide := Tutorial.new()
		guide.configure(false, "GUIDE1", "herder-a", landscape)
		guide.set_connection(1, true)
		var snapshot := _snapshot()
		snapshot.landscape = landscape
		_check(not guide.observe_snapshot(snapshot, 1) and not guide.hint().visible, "normal landscape has no implicit tutorial: " + landscape)
		guide.restart()
		_check(not guide.debug_state().enabled, "restart cannot enable teaching outside explicit tutorial mode")
	var guide := Tutorial.new()
	guide.configure(true, "GUIDE1", "herder-a", "bellflower")
	_check(not guide.hint().visible and not guide.record_local_action(_move(1, _point(-5, 0)), 1), "offline tutorial cannot arm or show gameplay hint")
	guide.set_connection(1, true)
	_check(not guide.select_dog("mochi", 1) and not guide.record_local_action(_move(1, _point(-5, 0)), 1), "first snapshot required before local intent")
	var snapshot := _snapshot()
	_check(guide.observe_snapshot(snapshot, 1) and guide.stage() == "walk", "first accepted receipt is baseline only")
	_check(guide.hint().visible and not guide.hint().instruction.is_empty() and not guide.hint().why.is_empty(), "one short instruction and explanation visible after baseline")
	_check(not guide.observe_snapshot(snapshot, 1), "duplicate accepted snapshot does not count as fresh")
	_check(not guide.observe_snapshot(_snapshot(9), 1), "old world tick rejected")
	_check(not guide.observe_snapshot(_snapshot(11), 0) and not guide.record_local_action(_move(1, _point(-5, 0)), 2), "epoch must match for snapshots and actions")
	_arm(guide, _move(1, _point(-5, 0)))
	_check(guide.observe_snapshot(_snapshot(11), 1) and guide.stage() == "walk", "new snapshot without requested result cannot complete")
	guide.set_connection(1, false)
	_check(not guide.hint().visible and not guide.debug_state().pending and not guide.observe_snapshot(_snapshot(12), 1), "disconnect clears pending credit and hides hint")
	_check(not guide.set_connection(1, true) and not guide.set_connection(0, true), "closed epoch cannot be reused or moved backward")
	_check(guide.set_connection(2, true), "replacement connection uses new epoch")
	var invalid_reconnect := _snapshot(800)
	invalid_reconnect.players[0].connected = false
	_check(not guide.observe_snapshot(invalid_reconnect, 2) and not guide.debug_state().fresh, "newer but invalid reconnect receipt cannot establish baseline")
	_check(not guide.record_local_action(_move(2, _point(-3, 0)), 2), "invalid reconnect receipt cannot unlock local arming")
	var retained := _snapshot(1)
	retained.players[0].seq = 1
	retained.players[0].position = _point(-5, 0)
	retained.players[0].target = _point(-5, 0)
	_check(guide.observe_snapshot(retained, 2) and guide.stage() == "walk", "restarted server tick baseline never credits retained prior action")
	_check(guide.observe_snapshot(_next(retained), 2) and guide.stage() == "walk", "later retained replay without a new action still cannot credit")

func _full_flow(local_id: String, dog_id: String) -> void:
	var fixture := _fresh("walk", local_id, dog_id)
	var guide: RefCounted = fixture.guide
	var snapshot: Dictionary = fixture.snapshot
	var steps: Array = []
	guide.lesson_advanced.connect(func(previous: String, current: String, reason: String) -> void: steps.append([previous, current, reason]))
	var target := _point(-5, 0)
	_arm(guide, _move(1, target))
	snapshot = _next(snapshot)
	var player := _actor(snapshot.players, local_id)
	player.seq = 1
	player.target = target.duplicate()
	player.position = _point(-6, 0)
	player.state = "walking"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "walk", "sequence/target echo without arrival is not completed walking")
	snapshot = _next(snapshot)
	player = _actor(snapshot.players, local_id)
	player.position = target.duplicate()
	player.state = "idle"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "select", "actual local seq/target and arrived herder complete walking")
	_check(guide.select_dog(dog_id, 1) and guide.stage() == "select", "selection remains pending until another accepted receipt")
	snapshot = _next(snapshot)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "come", "selected existing dog is confirmed on fresh receipt")
	for command: String in ["come", "stay"]:
		_arm(guide, _command(command, dog_id))
		snapshot = _next(snapshot)
		_result(snapshot, local_id, dog_id, command)
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == ("stay" if command == "come" else "place"), "observed locally called dog result completes " + command)
	var dog_target := _point(7, -6)
	_arm(guide, _command("go", dog_id, dog_target))
	snapshot = _next(snapshot)
	_result(snapshot, local_id, dog_id, "go", dog_target)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "pressure", "arrived Go advances only one lesson on this snapshot")
	_check(not guide.observe_snapshot(snapshot, 1) and guide.stage() == "pressure", "same snapshot cannot also complete pressure")
	snapshot = _next(snapshot)
	snapshot.sheep[0].position.x += 0.08
	snapshot.sheep[0].velocity = _point(0.8, 0)
	snapshot.sheep[0].state = "walking"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "withdraw" and guide.debug_state().pressure_sheep == 1, "same requested dog placement can explain its later unambiguous sheep response")
	_arm(guide, _command("come", dog_id))
	snapshot = _next(snapshot)
	_result(snapshot, local_id, dog_id, "come")
	snapshot.sheep[0].state = "grazing"
	snapshot.sheep[0].velocity = _point(0, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "care", "requested withdrawal and grazing sheep support a quiet-care invitation")
	_arm(guide, _pet(dog_id))
	snapshot = _next(snapshot)
	player = _actor(snapshot.players, local_id)
	player.state = "petting"
	player.target = player.position.duplicate()
	var dog := _actor(snapshot.dogs, dog_id)
	dog.state = "happy"
	dog.command = "stay"
	dog.target = dog.position.duplicate()
	# The server retains the previous caller on pet, including the partner's ID.
	dog.caller = "herder-b" if local_id == "herder-a" else "herder-a"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "freeplay" and not guide.hint().visible, "authoritative petting/happy result finishes without permanent guide HUD")
	_check(steps.size() == 8, "each fresh receipt advances at most one of eight optional lessons")
	for step: Array in steps:
		_check(step[2] == "observed", "complete flow uses observed evidence, not manual/optimistic completion")
	flows += 1

func _movement_and_selection() -> void:
	var fixture := _fresh()
	var guide: RefCounted = fixture.guide
	var snapshot: Dictionary = fixture.snapshot
	_check(not guide.record_local_action(_move(0, _point(-5, 0)), 1), "zero/replayed movement sequence rejected")
	_check(not guide.record_local_action(_move(1, snapshot.players[0].position), 1), "no-op destination does not pretend to teach walking")
	_arm(guide, _move(1, _point(-5, 0)))
	snapshot = _next(snapshot)
	snapshot.players[1].seq = 1
	snapshot.players[1].position = _point(-5, 0)
	snapshot.players[1].target = _point(-5, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "walk", "partner's movement cannot complete the local lesson")
	snapshot = _next(snapshot)
	snapshot.players[0].seq = 2
	snapshot.players[0].position = _point(-5, 0)
	snapshot.players[0].target = _point(-5, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "walk", "a different newer sequence is not the emitted movement")
	_arm(guide, _move(3, _point(-3, 0)))
	_check(not guide.record_local_action(_sit(), 1), "unrelated actual local action cancels old pending movement")
	snapshot = _next(snapshot)
	snapshot.players[0].seq = 3
	snapshot.players[0].position = _point(-3, 0)
	snapshot.players[0].target = _point(-3, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "walk", "superseded intent stays canceled when its result arrives later")
	fixture = _fresh("select")
	guide = fixture.guide
	snapshot = fixture.snapshot
	_check(not guide.select_dog("sheep-0", 1) and not guide.select_dog("absent", 1), "only actual corgis can be selected")
	guide.observe_snapshot(_next(snapshot), 1)
	_check(guide.stage() == "select", "dog presence alone does not invent a local selection")
	guide.select_dog("maple", 1)
	_check(guide.debug_state().selected_dog == "maple", "either shared corgi can be selected")

func _commands_and_reconnect() -> void:
	for lesson: String in ["come", "stay", "place"]:
		var command := "go" if lesson == "place" else lesson
		var fixture := _fresh(lesson)
		var guide: RefCounted = fixture.guide
		var snapshot: Dictionary = fixture.snapshot
		var target := _point(-3, 0)
		_check(not guide.record_local_action(_command(command, "maple", target), 1), "unselected dog cannot satisfy " + lesson)
		_arm(guide, _command(command, "mochi", target))
		snapshot = _next(snapshot)
		_result(snapshot, "herder-b", "mochi", command, target)
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == lesson, "partner caller cannot be credited for " + lesson)
		snapshot = _next(snapshot)
		_result(snapshot, "herder-a", "maple", command, target)
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == lesson, "right caller on wrong corgi cannot complete " + lesson)
		guide.set_connection(1, false)
		guide.set_connection(2, true)
		snapshot.tick = 1
		_result(snapshot, "herder-a", "mochi", command, target)
		_check(not guide.record_local_action(_command(command, "mochi", target), 2), "reconnect cannot arm before first snapshot")
		guide.observe_snapshot(snapshot, 2)
		_check(guide.stage() == lesson, "first reconnected result is baseline only for " + lesson)
		snapshot = _next(snapshot)
		guide.observe_snapshot(snapshot, 2)
		_check(guide.stage() == lesson, "retained command cannot replay lesson credit")
		_arm(guide, _command(command, "mochi", target), 2)
		_check(not guide.observe_snapshot(snapshot, 2), "same-tick receipt cannot credit repeated command")
		var old_socket := _next(snapshot)
		old_socket.tick = 999
		_check(not guide.observe_snapshot(old_socket, 1), "old socket cannot credit new local command")
		snapshot = _next(snapshot)
		guide.observe_snapshot(snapshot, 2)
		_check(guide.stage() != lesson, "fresh repeat with unchanged desired tuple completes observed lesson, not a claimed packet ACK")
	var fixture := _fresh("place")
	var guide: RefCounted = fixture.guide
	var snapshot: Dictionary = fixture.snapshot
	_arm(guide, _command("go", "mochi", _point(-3, 0)))
	snapshot = _next(snapshot)
	_result(snapshot, "herder-a", "mochi", "go", _point(-2, 0))
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "place", "wrong Go target cannot complete placement")
	snapshot = _next(snapshot)
	snapshot.dogs[0].target = _point(-3, 0)
	snapshot.dogs[0].state = "go"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "place", "target echo without dog arrival cannot complete placement")
	guide.select_dog("maple", 1)
	snapshot = _next(snapshot)
	_result(snapshot, "herder-a", "mochi", "go", _point(-3, 0))
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "place" and not guide.debug_state().pending, "switching selected corgi cancels previous intent")

func _pressure_and_care() -> void:
	for ambiguity: String in ["none", "other_dog", "local_herder", "partner", "wrong_caller", "toward_dog", "no_motion", "no_request"]:
		var fixture := _fresh("pressure")
		var guide: RefCounted = fixture.guide
		var snapshot: Dictionary = fixture.snapshot
		var target := _point(7, -6)
		if ambiguity != "no_request":
			_arm(guide, _command("go", "mochi", target))
		snapshot = _next(snapshot)
		_result(snapshot, "herder-a", "mochi", "go", target)
		snapshot.sheep[0].position.x += 0.1 if ambiguity != "no_motion" else 0
		snapshot.sheep[0].velocity = _point(-0.8 if ambiguity == "toward_dog" else 0.8, 0)
		snapshot.sheep[0].state = "walking"
		if ambiguity == "other_dog":
			snapshot.dogs[1].position = _point(8, -6)
		elif ambiguity in ["local_herder", "partner"]:
			snapshot.players[0 if ambiguity == "local_herder" else 1].position = _point(8, -6)
		elif ambiguity == "wrong_caller":
			snapshot.dogs[0].caller = "herder-b"
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == ("withdraw" if ambiguity == "none" else "pressure"), "conservative observed pressure: " + ambiguity)
		if ambiguity != "none":
			guide.skip_current_lesson()
			_check(guide.stage() == "withdraw", "ambiguous co-op pressure can always be skipped manually")
	for problem: String in ["none", "near_dog", "other_dog", "not_grazing", "no_request"]:
		var fixture := _fresh("withdraw")
		var guide: RefCounted = fixture.guide
		var snapshot: Dictionary = fixture.snapshot
		var target := _point(0, -4) if problem != "near_dog" else _point(7, -6)
		if problem != "no_request":
			_arm(guide, _command("go", "mochi", target))
		snapshot = _next(snapshot)
		_result(snapshot, "herder-a", "mochi", "go", target)
		if problem == "other_dog":
			snapshot.dogs[1].position = _point(8, -6)
		elif problem == "not_grazing":
			snapshot.sheep[0].state = "walking"
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == ("care" if problem == "none" else "withdraw"), "withdrawal requires actual space and grazing: " + problem)
	for distance: float in [0.0, 2.499999, 2.5, 2.500001, 3.0]:
		var fixture := _fresh("care")
		var guide: RefCounted = fixture.guide
		var snapshot: Dictionary = fixture.snapshot
		_arm(guide, _pet())
		snapshot = _next(snapshot)
		snapshot.players[0].position = _point(0, 0)
		snapshot.players[0].target = _point(0, 0)
		snapshot.players[0].state = "petting"
		snapshot.dogs[0].position = _point(distance, 0)
		snapshot.dogs[0].target = _point(distance, 0)
		snapshot.dogs[0].state = "happy"
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == ("freeplay" if distance <= 2.5 else "care"), "strict inclusive scalar 2D pet distance %.6f" % distance)
	var fixture := _fresh("care")
	var guide: RefCounted = fixture.guide
	var snapshot: Dictionary = fixture.snapshot
	_check(not guide.record_local_action(_pet("maple"), 1), "wrong selected dog cannot be credited for petting")
	_arm(guide, _pet())
	snapshot = _next(snapshot)
	snapshot.players[1].state = "petting"
	snapshot.dogs[0].state = "happy"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "care", "partner petting cannot complete local care")
	_arm(guide, _sit())
	snapshot = _next(snapshot)
	snapshot.players[0].state = "sitting"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "freeplay", "sitting is an equal optional finish without mandatory petting")
	fixture = _fresh("care")
	guide = fixture.guide
	snapshot = _next(fixture.snapshot)
	_arm(guide, _pet())
	snapshot.players[0].position = _point(0, 0)
	snapshot.players[0].target = _point(0, 0)
	snapshot.players[0].state = "petting"
	snapshot.dogs[0].position = _point(1.5, 2)
	snapshot.dogs[0].target = _point(1.5, 2)
	snapshot.dogs[0].state = "happy"
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "freeplay", "inclusive 2.5m diagonal uses server XY, not rendered height")

func _nonconflicting_actions() -> void:
	for lesson: String in ["come", "stay", "place", "pressure", "withdraw"]:
		for activity: String in ["walk", "sit", "other_dog"]:
			var fixture := _fresh(lesson)
			var guide: RefCounted = fixture.guide
			var snapshot: Dictionary = fixture.snapshot
			var command := lesson if lesson in ["come", "stay"] else "go"
			var target := _point(7, -6) if lesson in ["place", "pressure"] else _point(-3, 0)
			_arm(guide, _command(command, "mochi", target))
			var action := _move(1, _point(-6, 0)) if activity == "walk" else (_sit() if activity == "sit" else _command("stay", "maple"))
			_check(not guide.record_local_action(action, 1), "non-conflicting activity does not claim new lesson evidence: " + lesson + "/" + activity)
			_check(guide.stage() == lesson and guide.debug_state().pending, "pending selected-dog result survives valid " + activity + " during " + lesson)
			snapshot = _next(snapshot)
			if activity == "walk":
				snapshot.players[0].seq = 1
				snapshot.players[0].target = action.target.duplicate()
				snapshot.players[0].position = action.target.duplicate()
			elif activity == "sit":
				snapshot.players[0].state = "sitting"
			else:
				snapshot.dogs[1].caller = "herder-a"
			_result(snapshot, "herder-a", "mochi", command, target)
			if lesson == "pressure":
				snapshot.sheep[0].position.x += 0.08
				snapshot.sheep[0].velocity = _point(0.8, 0)
				snapshot.sheep[0].state = "walking"
			guide.observe_snapshot(snapshot, 1)
			_check(guide.stage() != lesson, "original freshly requested dog result still teaches after " + activity + " during " + lesson)
	for conflict: Dictionary in [_command("stay"), _pet()]:
		var fixture := _fresh("place")
		var guide: RefCounted = fixture.guide
		var snapshot: Dictionary = fixture.snapshot
		_arm(guide, _command("go", "mochi", _point(-3, 0)))
		_check(not guide.record_local_action(conflict, 1) and not guide.debug_state().pending, "selected-dog Stay or Pet cancels the old Go evidence")
		snapshot = _next(snapshot)
		_result(snapshot, "herder-a", "mochi", "go", _point(-3, 0))
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == "place", "late result from a conflictingly replaced command cannot advance")
	var fixture := _fresh("place")
	var guide: RefCounted = fixture.guide
	var snapshot: Dictionary = fixture.snapshot
	_arm(guide, _command("go", "mochi", _point(-3, 0)))
	_arm(guide, _command("go", "mochi", _point(-2, 0)))
	snapshot = _next(snapshot)
	_result(snapshot, "herder-a", "mochi", "go", _point(-3, 0))
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "place", "a new selected-dog Go replaces the required destination")
	snapshot = _next(snapshot)
	_result(snapshot, "herder-a", "mochi", "go", _point(-2, 0))
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "pressure", "only the newer selected-dog destination completes placement")
	for interaction: Dictionary in [_sit(), _pet()]:
		fixture = _fresh("care")
		guide = fixture.guide
		snapshot = fixture.snapshot
		_arm(guide, interaction)
		_check(not guide.record_local_action(_move(1, _point(-5, 0)), 1) and not guide.debug_state().pending, "walking still conflicts with pending care evidence")
		snapshot = _next(snapshot)
		snapshot.players[0].state = "sitting" if interaction.action == "sit" else "petting"
		snapshot.dogs[0].position = _point(-6, 0)
		snapshot.dogs[0].target = _point(-6, 0)
		snapshot.dogs[0].state = "happy"
		guide.observe_snapshot(snapshot, 1)
		_check(guide.stage() == "care", "late care state cannot credit an action canceled by walking")
	fixture = _fresh("walk")
	guide = fixture.guide
	snapshot = fixture.snapshot
	_arm(guide, _move(1, _point(-5, 0)))
	_arm(guide, _move(2, _point(-4, 0)))
	_check(not guide.record_local_action(_move(1, _point(-5, 0)), 1), "stale emitted sequence cannot replace newer pending movement")
	snapshot = _next(snapshot)
	snapshot.players[0].seq = 1
	snapshot.players[0].position = _point(-5, 0)
	snapshot.players[0].target = _point(-5, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "walk", "conflicting newer walk still excludes the old movement result")
	_check(not guide.record_local_action(_command("stay", "maple"), 1) and guide.debug_state().pending, "helping a dog does not stop the herder's valid walk evidence")
	snapshot = _next(snapshot)
	snapshot.players[0].seq = 2
	snapshot.players[0].position = _point(-4, 0)
	snapshot.players[0].target = _point(-4, 0)
	guide.observe_snapshot(snapshot, 1)
	_check(guide.stage() == "select", "newer arrived walk remains observable after helping a dog")
	for action: Dictionary in [{"type": "move", "seq": "1", "target": _point(-5, 0)}, _command("stay", "unknown-dog"), {"type": "interact", "action": "sit", "dog_id": "mochi"}]:
		fixture = _fresh("place")
		guide = fixture.guide
		_check(not guide.record_local_action(action, 1) and not guide.debug_state().pending, "invalid actions never invent pending evidence")

func _malformed_receipts() -> void:
	var mutations: Array[Callable] = [
		func(s: Dictionary) -> void: s.type = "error",
		func(s: Dictionary) -> void: s.code = "OTHER1",
		func(s: Dictionary) -> void: s.landscape = "alpine",
		func(s: Dictionary) -> void: s.tick = "11",
		func(s: Dictionary) -> void: s.tick = true,
		func(s: Dictionary) -> void: s.tick = 11.5,
		func(s: Dictionary) -> void: s.tick = INF,
		func(s: Dictionary) -> void: s.tick = NAN,
		func(s: Dictionary) -> void: s.tick = -1,
		func(s: Dictionary) -> void: s.tick = 9007199254740992.0,
		func(s: Dictionary) -> void: s.erase("layout"),
		func(s: Dictionary) -> void: s.layout = {},
		func(s: Dictionary) -> void: s.layout.version = 99,
		func(s: Dictionary) -> void: s.players = [],
		func(s: Dictionary) -> void: s.players.remove_at(0),
		func(s: Dictionary) -> void: s.players[0].connected = false,
		func(s: Dictionary) -> void: s.players[0].connected = 1,
		func(s: Dictionary) -> void: s.players[0].seq = "1",
		func(s: Dictionary) -> void: s.players[0].seq = 1.5,
		func(s: Dictionary) -> void: s.players[0].position.x = INF,
		func(s: Dictionary) -> void: s.players[0].target.x = true,
		func(s: Dictionary) -> void: s.dogs = "dogs",
		func(s: Dictionary) -> void: s.dogs[0] = null,
		func(s: Dictionary) -> void: s.dogs[0].id = "maple",
		func(s: Dictionary) -> void: s.dogs[0].id = "replacement",
		func(s: Dictionary) -> void: s.dogs[0].position = {"x": 0},
		func(s: Dictionary) -> void: s.dogs[0].state = null,
		func(s: Dictionary) -> void: s.dogs[0].caller = 123,
		func(s: Dictionary) -> void: s.sheep = [],
		func(s: Dictionary) -> void: s.sheep[0].id = "replacement",
		func(s: Dictionary) -> void: s.sheep[0].velocity.y = NAN,
	]
	for index in mutations.size():
		var fixture := _fresh()
		var guide: RefCounted = fixture.guide
		_arm(guide, _move(1, _point(-5, 0)))
		var malformed := _next(fixture.snapshot)
		mutations[index].call(malformed)
		var before: Dictionary = guide.debug_state()
		_check(not guide.observe_snapshot(malformed, 1), "malformed or wrong-context receipt rejected %d" % index)
		_check(guide.debug_state() == before, "rejected receipt cannot overwrite accepted baseline or pending evidence %d" % index)
		_check(guide.observe_snapshot(_next(fixture.snapshot), 1), "valid next receipt still works after malformed candidate %d" % index)
	var fixture := _fresh()
	var snapshot: Dictionary = fixture.snapshot
	var guide: RefCounted = fixture.guide
	_arm(guide, _move(1, _point(-5, 0)))
	# Incoming dictionaries are untrusted mutable objects, not owned game state.
	snapshot.players[0].seq = 700
	snapshot.layout.version = 99
	_check(guide.debug_state().last_tick == 10 and guide.debug_state().pending, "input dictionary mutation cannot alias stored evidence")
	var valid := _snapshot(11)
	valid.dogs.reverse()
	valid.sheep.reverse()
	_check(guide.observe_snapshot(valid, 1), "snapshot actor ordering is not identity")

func _malformed_actions() -> void:
	var invalid: Array = [{}, {"type": "move"}, {"type": "move", "seq": true, "target": _point(-5, 0)}, {"type": "move", "seq": "1", "target": _point(-5, 0)}, {"type": "move", "seq": 1.5, "target": _point(-5, 0)}, {"type": "move", "seq": 1, "target": {"x": -5, "y": 0, "z": 0}}, {"type": "move", "seq": 1, "target": _point(INF, 0)}, {"type": "move", "seq": 1, "target": _point(-5, 0), "player_id": "herder-b"}]
	for action: Dictionary in invalid:
		var fixture := _fresh()
		_check(not fixture.guide.record_local_action(action, 1) and not fixture.guide.debug_state().pending, "malformed action cannot arm intent")
	for action: Dictionary in [{"type": "command", "dog_id": "mochi", "command": "come", "target": _point(0, 0)}, {"type": "command", "dog_id": "mochi", "command": "fetch"}, {"type": "command", "dog_id": 0, "command": "come"}, {"type": "command", "dog_id": "mochi", "command": "come", "caller": "herder-a"}]:
		var fixture := _fresh("come")
		_check(not fixture.guide.record_local_action(action, 1), "unknown/coerced/forged command cannot arm")
	var fixture := _fresh("care")
	_check(not fixture.guide.record_local_action({"type": "interact", "action": "sit", "dog_id": "mochi"}, 1), "sit must use actual local wire shape")
	_check(not fixture.guide.record_local_action({"type": "interact", "action": "gate", "dog_id": ""}, 1), "gate activity is not care evidence")

func _restart_and_skip() -> void:
	var fixture := _fresh("pressure")
	var guide: RefCounted = fixture.guide
	guide.lesson_advanced.connect(func(previous: String, current: String, reason: String) -> void: advanced.append([previous, current, reason]))
	guide.finished.connect(func(reason: String) -> void: finished_reasons.append(reason))
	guide.skip_current_lesson()
	_check(advanced.back() == ["pressure", "withdraw", "manual"], "skip-current surfaces a manual reason, not observed progress")
	guide.set_connection(1, false)
	guide.skip_current_lesson()
	_check(guide.stage() == "care" and not guide.hint().visible, "optional skip works even when disconnected")
	guide.skip_current_lesson()
	_check(guide.stage() == "freeplay" and finished_reasons.back() == "manual", "manual completion has no mandatory gameplay")
	var count := advanced.size()
	guide.skip_current_lesson()
	_check(advanced.size() == count, "freeplay cannot emit endless completion events")
	guide.restart()
	_check(guide.stage() == "walk" and not guide.debug_state().fresh and not guide.debug_state().pending and guide.debug_state().selected_dog.is_empty(), "restart clears progress without inventing fresh receipt")
	guide.set_connection(2, true)
	guide.observe_snapshot(_snapshot(10), 2)
	_arm(guide, _move(1, _point(-5, 0)), 2)
	guide.restart()
	_check(not guide.observe_snapshot(_snapshot(10), 2), "restart cannot turn cached tick into fresh data")
	guide.observe_snapshot(_snapshot(11), 2)
	_check(guide.stage() == "walk" and not guide.debug_state().pending, "restart's first fresh receipt is baseline only")
	guide.skip()
	_check(not guide.debug_state().enabled and not guide.hint().visible and finished_reasons.back() == "skipped", "skip-all disables hints and marks manual choice")
	_check(not guide.observe_snapshot(_snapshot(12), 2), "skipped tutorial stops processing snapshots")
	guide.restart()
	_check(guide.debug_state().enabled and not guide.hint().visible, "explicit restart re-enables only configured tutorial mode")

func _preference_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["user://audio.cfg", "user://herd.cfg"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result
