extends Node3D

const Connection = preload("res://scripts/network.gd")
const Meadow = preload("res://scripts/meadow.gd")
const INK := Color("304d40")
const MUTED := Color("6c7c66")
const PAPER := Color("f5f0df")
const ACCENT := Color("466e59")

var meadow: MeadowDiorama
var network: HerdConnection
var actors: Dictionary = {}
var latest: Dictionary = {}
var local_id := ""
var selected_dog := "mochi"
var go_pending := false
var movement_target := Vector2.ZERO
var movement_seq := 0
var moving := false
var elapsed := 0.0
var hint_time := 0.0
var had_snapshot := false
var request_busy := false
var preview_mode := false
var capture_path := ""
var capture_after := -1.0
var ui: Control
var welcome: Control
var hud: Control
var menu_error: Label
var name_input: LineEdit
var endpoint_input: LineEdit
var invite_input: LineEdit
var resume_button: Button
var create_button: Button
var join_button: Button
var status_label: Label
var invite_label: Button
var companion_label: Label
var hint_label: Label
var moment_label: Label
var dog_mochi: Button
var dog_maple: Button
var go_button: Button
var pet_button: Button
var gate_button: Button
var sit_button: Button
var player_marker: Node3D
var last_settled := 0

func _ready() -> void:
	meadow = Meadow.new()
	add_child(meadow)
	network = Connection.new()
	add_child(network)
	network.snapshot_received.connect(_on_snapshot)
	network.status_changed.connect(_on_status)
	network.request_failed.connect(_on_error)
	network.herd_joined.connect(_on_herd_joined)
	_build_ui()
	for argument in OS.get_cmdline_user_args():
		if argument == "--preview":
			preview_mode = true
		elif argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
			capture_after = 2.0
		elif argument.begins_with("--server="):
			network.endpoint = argument.trim_prefix("--server=")
			endpoint_input.text = network.endpoint
	if preview_mode:
		_show_preview()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _theme()
	layer.add_child(ui)
	_build_welcome()
	_build_hud()
	hud.hide()

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", PAPER)
	theme.set_color("font_disabled_color", "Button", Color("9da38c"))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color("9ca48f"))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "Button", _style(Color("eee9d8"), 16))
	theme.set_stylebox("hover", "Button", _style(Color("e2e6cf"), 16))
	theme.set_stylebox("pressed", "Button", _style(ACCENT, 16))
	theme.set_stylebox("disabled", "Button", _style(Color("e9e6d8"), 16))
	var focus := _style(Color(0, 0, 0, 0), 16)
	focus.border_color = Color("c99c63")
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "LineEdit", _style(Color("fffcf1"), 12))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 12)
	return theme

func _style(color: Color, radius: int, padding := 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _label(text: String, size := 22, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable, width := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 64)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func _primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _style(ACCENT, 16))
	button.add_theme_stylebox_override("hover", _style(Color("587e64"), 16))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", PAPER)

func _column(parent: Node, separation := 12) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column

func _row(parent: Node, separation := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	return row

func _field(placeholder: String, value: String, max_length := 0) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = value
	field.custom_minimum_size.y = 58
	field.max_length = max_length
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return field

func _build_welcome() -> void:
	welcome = MarginContainer.new()
	ui.add_child(welcome)
	welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	welcome.add_theme_constant_override("margin_left", 44)
	welcome.add_theme_constant_override("margin_right", 44)
	welcome.add_theme_constant_override("margin_top", 30)
	welcome.add_theme_constant_override("margin_bottom", 30)
	welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := _row(welcome, 32)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 500
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _style(Color("f6f1e3f5"), 24, 30))
	layout.add_child(card)
	var column := _column(card, 10)
	column.add_child(_label("A LITTLE WORLD, TOGETHER", 16, MUTED))
	column.add_child(_label("Corgi Herding", 46))
	var description := _label("Two herders. Two corgis.\nTen sheep with their own ideas.", 22, MUTED)
	description.add_theme_constant_override("line_spacing", 5)
	column.add_child(description)
	var space := Control.new()
	space.custom_minimum_size.y = 5
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(space)
	column.add_child(_label("YOUR NAME", 14, MUTED))
	name_input = _field("Herder", network.display_name, 24)
	column.add_child(name_input)
	column.add_child(_label("MEADOW SERVER", 14, MUTED))
	endpoint_input = _field("https://your-server.example", network.endpoint)
	endpoint_input.add_theme_font_size_override("font_size", 19)
	column.add_child(endpoint_input)
	create_button = _button("Start a meadow", _create)
	_primary(create_button)
	column.add_child(create_button)
	var join_row := _row(column)
	invite_input = _field("Invite code", "", 12)
	invite_input.text_changed.connect(func(value: String) -> void:
		var caret := invite_input.caret_column
		invite_input.text = value.to_upper()
		invite_input.caret_column = caret)
	join_row.add_child(invite_input)
	join_button = _button("Join", _join, 108)
	join_row.add_child(join_button)
	resume_button = _button("Return to our meadow", _resume)
	resume_button.visible = network.has_saved_herd()
	column.add_child(resume_button)
	menu_error = _label("", 17, Color("976d52"))
	menu_error.custom_minimum_size.x = 440
	menu_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(menu_error)
	column.add_child(_label("A quiet cooperative prototype · v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0")), 15, MUTED))
	var right := _column(layout)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	var poetry := _label("No rush.\nThey’ll get there.", 35, INK)
	poetry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(poetry)
	var subtitle := _label("TEN SHEEP & A GATE", 16, Color("5b7158"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(subtitle)

func _build_hud() -> void:
	hud = MarginContainer.new()
	ui.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		hud.add_theme_constant_override(key, 28)
	var column := _column(hud, 12)
	var header := _row(column, 20)
	var brand := _column(header, 3)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_child(_label("Corgi Herding", 30))
	brand.add_child(_label("TEN SHEEP & A GATE", 13, Color("657856")))
	var invitation := _column(header, 2)
	invite_label = _button("Invite · —", _copy_invite, 210)
	invite_label.custom_minimum_size.y = 48
	invite_label.add_theme_font_size_override("font_size", 20)
	invitation.add_child(invite_label)
	companion_label = _label("A place for your other herder", 14, Color("657856"))
	companion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invitation.add_child(companion_label)
	var connection := _column(header, 3)
	connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = _label("Finding your meadow…", 16, Color("657856"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	connection.add_child(status_label)
	var menu := _button("Meadow settings", _open_settings)
	menu.custom_minimum_size.y = 40
	menu.add_theme_font_size_override("font_size", 16)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	connection.add_child(menu)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(air)
	moment_label = _label("", 26, INK)
	moment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(moment_label)
	var footer := _row(column, 18)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var command_panel := PanelContainer.new()
	command_panel.add_theme_stylebox_override("panel", _style(Color("f6f1e3ed"), 22, 14))
	footer.add_child(command_panel)
	var commands := _column(command_panel, 10)
	var dogs := _row(commands, 8)
	dog_mochi = _button("Mochi", func() -> void: _select_dog("mochi"), 150)
	dog_maple = _button("Maple", func() -> void: _select_dog("maple"), 150)
	dog_mochi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dog_maple.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dogs.add_child(dog_mochi)
	dogs.add_child(dog_maple)
	var actions := _row(commands, 8)
	actions.add_child(_button("Come", func() -> void: _command("come"), 110))
	actions.add_child(_button("Stay", func() -> void: _command("stay"), 110))
	go_button = _button("Go there", _prepare_go, 146)
	actions.add_child(go_button)
	var care := _column(footer, 8)
	care.alignment = BoxContainer.ALIGNMENT_END
	gate_button = _button("Open gate", func() -> void: _interact("gate"), 154)
	gate_button.hide()
	care.add_child(gate_button)
	pet_button = _button("Pet Mochi", func() -> void: _interact("pet"), 154)
	pet_button.hide()
	care.add_child(pet_button)
	sit_button = _button("Sit a while", func() -> void: _interact("sit"), 154)
	care.add_child(sit_button)
	hint_label = _label("Tap the grass to walk. You both care for both corgis.", 18, INK)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint_label)
	_select_dog("mochi")

func _configure() -> bool:
	menu_error.text = ""
	return network.configure(endpoint_input.text, name_input.text)

func _create() -> void:
	if not request_busy and _configure():
		_set_busy(true)
		network.create_herd()

func _join() -> void:
	if not request_busy and _configure():
		_set_busy(true)
		network.join_herd(invite_input.text)

func _resume() -> void:
	if _configure() and network.has_saved_herd():
		_on_herd_joined(str(network.credentials.code))
		network.reconnect()
	else:
		menu_error.text = "Your saved meadow belongs to another server. Restore its address, or start a new meadow."

func _set_busy(value: bool) -> void:
	request_busy = value
	create_button.disabled = value
	join_button.disabled = value
	resume_button.disabled = value
	if value:
		menu_error.text = "Opening a little world…"

func _on_herd_joined(code: String) -> void:
	_set_busy(false)
	local_id = str(network.credentials.get("player_id", ""))
	invite_label.text = "Invite · " + code
	welcome.hide()
	hud.show()
	meadow.preview.hide()
	# Switching herds never leaves actors or movement from the previous world.
	for id in actors:
		actors[id].node.queue_free()
	actors.clear()
	latest = {}
	had_snapshot = false
	moving = false
	go_pending = false
	last_settled = 0

func _on_status(text: String, is_connected: bool) -> void:
	status_label.text = "● " + ("Connected" if is_connected else text)
	status_label.add_theme_color_override("font_color", Color("4a7459") if is_connected else Color("926e4e"))
	if not is_connected:
		moving = false

func _on_error(message: String) -> void:
	_set_busy(false)
	menu_error.text = message
	_hint(message, 7.0)
	if not network.has_saved_herd() and not preview_mode:
		_open_settings()

func _open_settings() -> void:
	network.disconnect_herd()
	welcome.show()
	hud.hide()
	resume_button.visible = network.has_saved_herd()
	endpoint_input.text = network.endpoint
	name_input.text = network.display_name
	moving = false

func _copy_invite() -> void:
	DisplayServer.clipboard_set(str(network.credentials.get("code", "MEADOW")))
	_hint("Invite copied. Share it with your other herder.", 4.0)

func _select_dog(id: String) -> void:
	selected_dog = id
	go_pending = false
	if dog_mochi == null:
		return
	for button in [dog_mochi, dog_maple]:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
	_primary(dog_mochi if id == "mochi" else dog_maple)
	go_button.text = "Go there"
	pet_button.text = "Pet " + id.capitalize()
	_hint("%s is listening. Come, Stay, or Go there." % id.capitalize(), 3.5)

func _command(command: String) -> void:
	if not network.connected and not preview_mode:
		_hint("Wait for your meadow to reconnect.")
		return
	go_pending = false
	go_button.text = "Go there"
	network.command(selected_dog, command)
	_hint("%s, %s." % [selected_dog.capitalize(), command], 2.0)
	_acknowledge(selected_dog)

func _prepare_go() -> void:
	if not network.connected and not preview_mode:
		_hint("Wait for your meadow to reconnect.")
		return
	go_pending = not go_pending
	go_button.text = "Cancel" if go_pending else "Go there"
	_hint("Tap a place in the grass for %s." % selected_dog.capitalize() if go_pending else "Tap the grass to walk.", 20.0 if go_pending else 3.0)

func _interact(action: String) -> void:
	if not network.connected and not preview_mode:
		return
	network.interact(action, selected_dog if action == "pet" else "")
	if action == "sit":
		moving = false
		_hint("Stay a while. Tap the grass when you’re ready.", 5.0)
	elif action == "pet":
		_acknowledge(selected_dog)
		_hint("Good dog, %s." % selected_dog.capitalize(), 3.0)

func _hint(text: String, duration := 4.0) -> void:
	if hint_label != null:
		hint_label.text = text
		hint_time = duration

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if go_pending:
			_prepare_go()
		elif hud.visible:
			_open_settings()
		return
	if event is InputEventMagnifyGesture:
		meadow.zoom = clampf(meadow.zoom / event.factor, 0.8, 1.18)
		meadow.fit_camera()
	if not hud.visible or (not network.connected and not preview_mode):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			meadow.zoom = clampf(meadow.zoom + (-0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.05), 0.8, 1.18)
			meadow.fit_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_world_tap(event.position)

func _world_tap(screen_pos: Vector2) -> void:
	# Directly tapping a dog is an alternative to the two quiet command tabs.
	if not go_pending:
		for id in ["mochi", "maple"]:
			if actors.has(id):
				var actor: Node3D = actors[id].node
				var projected := meadow.camera.unproject_position(actor.position + Vector3(0, 0.5, 0))
				if projected.distance_to(screen_pos) < 34.0:
					_select_dog(id)
					return
	var ground := meadow.ground_at(screen_pos)
	if not ground.is_finite():
		return
	# Water is readable as a real obstacle; tap the bridge or other bank to cross.
	if absf(ground.x) < 1.5 and absf(ground.z) > 1.85:
		_hint("The bridge is the dry way across.")
		return
	meadow.mark_destination(ground)
	var target := Vector2(ground.x, ground.z)
	if go_pending:
		network.command(selected_dog, "go", target)
		go_pending = false
		go_button.text = "Go there"
		_hint("%s, over there." % selected_dog.capitalize(), 2.0)
		_acknowledge(selected_dog)
	else:
		movement_seq = network.move_to(target)
		movement_target = target
		moving = true

func _on_snapshot(snapshot: Dictionary) -> void:
	latest = snapshot
	meadow.preview.hide()
	meadow.gate_open = bool(snapshot.get("gate_open", false))
	var present: Dictionary = {}
	var player_count := 0
	for kind in ["player", "dog", "sheep"]:
		for data: Dictionary in snapshot.get("sheep" if kind == "sheep" else kind + "s", []):
			var id := str(data.id)
			present[id] = true
			var pos := Vector3(float(data.position.x), 0.11, float(data.position.y))
			if not actors.has(id):
				var node := meadow.make_actor(kind, id, kind == "player" and id != local_id)
				node.position = pos
				if kind == "player":
					var name_tag := Label3D.new()
					name_tag.text = "You" if id == local_id else str(data.get("name", "Your other herder"))
					name_tag.font_size = 36
					name_tag.pixel_size = 0.012
					name_tag.position.y = 2.7
					name_tag.modulate = Color("fff2d5")
					name_tag.outline_modulate = Color("4f6453")
					name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					node.add_child(name_tag)
				actors[id] = {"node": node, "target": pos, "kind": kind, "state": "idle", "phase": float(id.hash() % 100) / 10.0, "ack": 0.0}
			var actor: Dictionary = actors[id]
			actor.state = str(data.get("state", "idle"))
			actor.target = pos
			if kind == "player":
				if bool(data.get("connected", false)):
					player_count += 1
				if id == local_id:
					var server_seq := int(data.get("seq", 0))
					network.seq = maxi(network.seq, server_seq)
					if not had_snapshot:
						movement_seq = server_seq
						actor.node.position = pos
						if data.has("target"):
							movement_target = Vector2(float(data.target.x), float(data.target.y))
							moving = Vector2(pos.x, pos.z).distance_to(movement_target) > 0.12
					if server_seq >= movement_seq:
						# Small correction retains immediate touch feedback; large drift snaps.
						var drift: float = actor.node.position.distance_to(pos)
						actor.node.position = pos if drift > 2.0 else actor.node.position.lerp(pos, 0.24)
						if actor.state == "sitting" or actor.state == "petting":
							moving = false
	for id in actors.keys():
		if not present.has(id):
			actors[id].node.queue_free()
			actors.erase(id)
	had_snapshot = true
	companion_label.text = "Both herders are here" if player_count == 2 else "Waiting for your other herder"
	var settled := int(snapshot.get("settled", 0))
	if settled == 10 and last_settled < 10:
		moment_label.text = "A softer patch of grass. You brought them here together."
		_hint("Sit in the grass. The corgis have earned a little affection.", 10.0)
	elif settled < 10 and last_settled == 10:
		moment_label.text = ""
	last_settled = settled
	_update_context()

func _update_context() -> void:
	if not actors.has(local_id):
		return
	var player: Node3D = actors[local_id].node
	gate_button.visible = not meadow.gate_open and Vector2(player.position.x - 6, player.position.z).length() < 3.0
	pet_button.visible = actors.has(selected_dog) and player.position.distance_to(actors[selected_dog].node.position) < 2.5

func _process(delta: float) -> void:
	elapsed += delta
	hint_time -= delta
	if hint_time <= 0 and hint_time > -delta:
		hint_label.text = "Tap a place for %s." % selected_dog.capitalize() if go_pending else "Tap the grass to walk. You both care for both corgis."
	for id in actors:
		var actor: Dictionary = actors[id]
		var node: Node3D = actor.node
		var before := node.position
		if id == local_id and moving and (network.connected or preview_mode):
			var point := Vector2(node.position.x, node.position.z)
			var step_target := _next_waypoint(point, movement_target)
			var next := point.move_toward(step_target, 4.0 * delta)
			if _walkable(next):
				node.position.x = next.x
				node.position.z = next.y
			if next.distance_to(movement_target) < 0.08:
				moving = false
		elif id != local_id:
			node.position = node.position.lerp(actor.target, 1.0 - exp(-delta * 12.0))
		var motion := node.position - before
		var walking := motion.length() > delta * 0.10
		if walking:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-motion.x, -motion.z), 1.0 - exp(-delta * 12))
		var body: Node3D = node.get_node("Body")
		var phase := elapsed * (10.0 if actor.kind == "dog" else 7.0) + float(actor.phase)
		var sitting: bool = actor.state == "sitting" or actor.state == "resting"
		body.position.y = lerpf(body.position.y, -0.32 if sitting else (absf(sin(phase)) * 0.07 if walking else sin(phase * 0.19) * 0.012), minf(delta * 10, 1.0))
		body.rotation.z = sin(phase) * 0.035 if walking else 0.0
		actor.ack = maxf(0.0, float(actor.ack) - delta)
		if actor.kind == "dog":
			var tail: Node3D = body.get_node("Tail")
			tail.position.x = sin(elapsed * 19) * (0.13 if actor.ack > 0 or actor.state == "happy" else 0.025)
	if actors.has(selected_dog) and hud.visible:
		meadow.selection.visible = true
		meadow.selection.position = actors[selected_dog].node.position + Vector3(0, 0.10, 0)
	else:
		meadow.selection.visible = false
	if capture_after >= 0:
		capture_after -= delta
		if capture_after <= 0:
			capture_after = -1
			_capture.call_deferred()

func _next_waypoint(point: Vector2, target: Vector2) -> Vector2:
	if point.x < -1.6 and target.x > -1.5:
		return Vector2(-1.7, 0) if absf(point.y) > 0.3 else Vector2(1.9, 0)
	if point.x > 1.6 and target.x < 1.5:
		return Vector2(1.7, 0) if absf(point.y) > 0.3 else Vector2(-1.9, 0)
	if absf(point.x) <= 1.6:
		return Vector2(1.9 if target.x > 0 else -1.9, 0)
	if point.x < 5.8 and target.x > 6:
		return Vector2(5.7, 0) if absf(point.y) > 0.3 or not meadow.gate_open else Vector2(6.4, 0)
	if point.x > 6.2 and target.x < 6:
		return Vector2(6.3, 0) if absf(point.y) > 0.3 or not meadow.gate_open else Vector2(5.6, 0)
	return target

func _walkable(point: Vector2) -> bool:
	if absf(point.x) > 17 or absf(point.y) > 11:
		return false
	if absf(point.x) < 1.5 and absf(point.y) > 1.85:
		return false
	if absf(point.x - 6) < 0.18 and (not meadow.gate_open or absf(point.y) > 1.8):
		return false
	return true

func _acknowledge(id: String) -> void:
	if actors.has(id):
		actors[id].ack = 1.5

func _show_preview() -> void:
	local_id = "p1"
	network.credentials = {"code": "MEADOW", "player_id": "p1"}
	_on_herd_joined("MEADOW")
	var sheep: Array = []
	for i in range(10):
		sheep.append({"id": "s%d" % i, "position": {"x": -5.5 + sin(i * 2.3) * 3, "y": -1.6 + cos(i * 1.6) * 2.6}, "state": "grazing"})
	_on_snapshot({"gate_open": false, "settled": 0,
		"players": [{"id": "p1", "position": {"x": -10, "y": 2}, "state": "idle", "connected": true}, {"id": "p2", "position": {"x": -4, "y": 5}, "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "position": {"x": -8, "y": 3}, "state": "wander"}, {"id": "maple", "position": {"x": -2.5, "y": 4}, "state": "wander"}], "sheep": sheep})
	status_label.text = "Preview · not connected"

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(capture_path)
	print("SCREENSHOT_SAVED " + capture_path if result == OK else "SCREENSHOT_FAILED")
	get_tree().quit(0 if result == OK else 1)
