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
var command_panel: PanelContainer
var command_title: Label
var go_cancel: Button
var go_button: Button
var pet_button: Button
var sit_button: Button
var player_marker: Node3D
var last_settled := 0
var selected_landscape := "alpine"
var alpine_button: Button
var cactus_button: Button
var region_label: Label

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
		elif argument.begins_with("--landscape="):
			_select_landscape(argument.trim_prefix("--landscape="))
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
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		welcome.add_theme_constant_override(key, 30)
	welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	welcome.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 610
	card.add_theme_stylebox_override("panel", _style(Color("f6f1e3f2"), 24, 28))
	center.add_child(card)
	var column := _column(card, 14)
	column.add_child(_label("A LITTLE WORLD, TOGETHER", 15, MUTED))
	column.add_child(_label("Corgi Herding", 42))
	column.add_child(_label("Two herders, two corgis. No rush.", 22, MUTED))
	name_input = _field("Herder", network.display_name, 24)
	column.add_child(name_input)
	var landscapes := _row(column, 8)
	alpine_button = _button("Alpine valley", func() -> void: _select_landscape("alpine"))
	cactus_button = _button("Cactus canyon", func() -> void: _select_landscape("cactus"))
	for button in [alpine_button, cactus_button]:
		button.custom_minimum_size.y = 64
		button.add_theme_font_size_override("font_size", 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		landscapes.add_child(button)
	_primary(alpine_button)
	create_button = _button("Start in the Alps", _create)
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
	resume_button = _button("Return to our herd", _resume)
	resume_button.visible = network.has_saved_herd()
	column.add_child(resume_button)
	menu_error = _label("", 17, Color("976d52"))
	menu_error.custom_minimum_size.x = 540
	menu_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(menu_error)
	var server_toggle := _button("Server address", func() -> void: endpoint_input.visible = not endpoint_input.visible)
	server_toggle.flat = true
	server_toggle.add_theme_font_size_override("font_size", 17)
	server_toggle.custom_minimum_size.y = 38
	column.add_child(server_toggle)
	endpoint_input = _field("https://your-server.example", network.endpoint)
	endpoint_input.add_theme_font_size_override("font_size", 18)
	endpoint_input.hide()
	column.add_child(endpoint_input)
	var version := _label("Prototype " + str(ProjectSettings.get_setting("application/config/version", "0.1.0")), 14, MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(version)

func _build_hud() -> void:
	hud = MarginContainer.new()
	ui.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		hud.add_theme_constant_override(key, 26)
	var column := _column(hud, 8)
	var header := _row(column, 12)
	var brand := _column(header, 2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_label = _label("Alpine valley", 22, INK)
	brand.add_child(region_label)
	status_label = _label("Connecting…", 15, MUTED)
	brand.add_child(status_label)
	var menu := _button("···", _open_settings, 64)
	menu.tooltip_text = "Herd and server settings"
	menu.flat = true
	menu.add_theme_font_size_override("font_size", 30)
	header.add_child(menu)
	invite_label = _button("Invite · —", _copy_invite)
	invite_label.custom_minimum_size.y = 56
	invite_label.add_theme_font_size_override("font_size", 18)
	invite_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(invite_label)
	companion_label = _label("Share this code with your other herder", 14, MUTED)
	column.add_child(companion_label)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(air)
	moment_label = _label("", 21, INK)
	moment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(moment_label)
	command_panel = PanelContainer.new()
	command_panel.add_theme_stylebox_override("panel", _style(Color("f6f1e3ed"), 22, 14))
	column.add_child(command_panel)
	var commands := _column(command_panel, 4)
	var command_header := _row(commands)
	command_title = _label("Mochi", 21)
	command_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_header.add_child(command_title)
	var close_commands := _button("×", _close_controls, 60)
	close_commands.flat = true
	close_commands.custom_minimum_size.y = 48
	command_header.add_child(close_commands)
	var actions := _row(commands, 6)
	var come := _button("Come", func() -> void: _command("come"))
	var stay := _button("Stay", func() -> void: _command("stay"))
	go_button = _button("Go", _prepare_go)
	pet_button = _button("Pet", func() -> void: _interact("pet"))
	for button in [come, stay, go_button, pet_button]:
		button.custom_minimum_size.y = 72
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	command_panel.hide()
	sit_button = _button("Sit here", func() -> void: _interact("sit"), 150)
	sit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sit_button.hide()
	column.add_child(sit_button)
	go_cancel = _button("Cancel", _prepare_go, 120)
	go_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go_cancel.hide()
	column.add_child(go_cancel)
	hint_label = _label("", 18, INK)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)

func _close_controls() -> void:
	command_panel.hide()
	sit_button.hide()
	go_cancel.hide()
	go_pending = false

func _configure() -> bool:
	menu_error.text = ""
	return network.configure(endpoint_input.text, name_input.text)

func _select_landscape(landscape: String) -> void:
	if landscape not in ["alpine", "cactus"]:
		return
	selected_landscape = landscape
	meadow.set_landscape(landscape)
	for button in [alpine_button, cactus_button]:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
	_primary(alpine_button if landscape == "alpine" else cactus_button)
	if region_label != null:
		region_label.text = "Alpine valley" if landscape == "alpine" else "Cactus canyon"
	if create_button != null:
		create_button.text = "Start in the Alps" if landscape == "alpine" else "Start in the canyon"

func _create() -> void:
	if not request_busy and _configure():
		_set_busy(true)
		network.create_herd(selected_landscape)

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
	alpine_button.disabled = value
	cactus_button.disabled = value
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
	_close_controls()
	_hint("Tap to walk. Tap a corgi to talk to them.", 6.0)
	invite_label.show()
	companion_label.show()
	moment_label.text = ""
	last_settled = 0

func _on_status(text: String, is_connected: bool) -> void:
	status_label.text = "" if is_connected else text
	status_label.visible = not is_connected
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
	_close_controls()
	selected_dog = id
	command_title.text = id.capitalize()
	command_panel.show()
	_update_context()
	_hint("", 0.0)

func _command(command: String) -> void:
	if not network.connected and not preview_mode:
		_hint("Wait for your meadow to reconnect.")
		return
	_close_controls()
	network.command(selected_dog, command)
	_hint("%s, %s." % [selected_dog.capitalize(), command], 2.0)
	_acknowledge(selected_dog)

func _prepare_go() -> void:
	if not network.connected and not preview_mode:
		_hint("Wait for your meadow to reconnect.")
		return
	go_pending = not go_pending
	command_panel.hide()
	sit_button.hide()
	go_cancel.visible = go_pending
	_hint("Tap a place for %s." % selected_dog.capitalize() if go_pending else "", 20.0 if go_pending else 0.0)

func _interact(action: String) -> void:
	if not network.connected and not preview_mode:
		return
	network.interact(action, selected_dog if action == "pet" else "")
	_close_controls()
	if action == "sit":
		moving = false
		_hint("Stay a while. Tap the ground when you’re ready.", 5.0)
	elif action == "pet":
		_acknowledge(selected_dog)
		_hint("Good dog, %s." % selected_dog.capitalize(), 3.0)

func _hint(text: String, duration := 4.0) -> void:
	if hint_label != null:
		hint_label.text = text
		hint_time = duration

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if go_pending or command_panel.visible or sit_button.visible:
			_close_controls()
			_hint("", 0.0)
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

func _pick_world_interaction(screen_pos: Vector2) -> String:
	var candidates: Array[Dictionary] = []
	for id in ["mochi", "maple"]:
		if actors.has(id):
			candidates.append({"id": "dog:" + id, "position": actors[id].node.position + Vector3(0, 0.5, 0), "radius": 44.0})
	if actors.has(local_id):
		candidates.append({"id": "player", "position": actors[local_id].node.position + Vector3(0, 0.9, 0), "radius": 40.0})
		if not meadow.gate_open:
			candidates.append({"id": "gate", "position": _surface_position(Vector2(6, 0)) + Vector3(0, 0.7, 0), "radius": 42.0})
	var nearest := ""
	var nearest_distance := INF
	for candidate in candidates:
		var distance := meadow.camera.unproject_position(candidate.position).distance_to(screen_pos)
		if distance < float(candidate.radius) and distance < nearest_distance:
			nearest_distance = distance
			nearest = str(candidate.id)
	return nearest

func _world_tap(screen_pos: Vector2) -> void:
	# Choose the closest visible target when generous mobile hit areas overlap.
	if not go_pending:
		var interaction := _pick_world_interaction(screen_pos)
		if interaction.begins_with("dog:"):
			_select_dog(interaction.trim_prefix("dog:"))
			return
		if actors.has(local_id):
			var player: Node3D = actors[local_id].node
			if interaction == "player":
				_close_controls()
				sit_button.show()
				_hint("", 0.0)
				return
			if interaction == "gate":
				_close_controls()
				if Vector2(player.position.x - 6, player.position.z).length() < 3.0:
					_interact("gate")
				else:
					movement_target = Vector2(5 if player.position.x < 6 else 7, 0)
					movement_seq = network.move_to(movement_target)
					moving = true
					_hint("Walk closer, then tap the gate.", 3.0)
				return
	var ground := meadow.ground_at(screen_pos)
	if not ground.is_finite():
		_hint("The steep slopes shelter this valley. Keep to the open ground.", 3.0)
		return
	# Water is readable as a real obstacle; tap the bridge or other bank to cross.
	if absf(ground.x) < 1.5 and absf(ground.z) > 1.85:
		_hint("The bridge is the dry way across.")
		return
	var target := Vector2(ground.x, ground.z)
	if not _walkable(target):
		_hint("Follow the fence to the gate.", 3.0)
		return
	meadow.mark_destination(ground)
	if go_pending:
		network.command(selected_dog, "go", target)
		_close_controls()
		_hint("%s, over there." % selected_dog.capitalize(), 2.0)
		_acknowledge(selected_dog)
	else:
		_close_controls()
		_hint("", 0.0)
		movement_seq = network.move_to(target)
		movement_target = target
		moving = true

func _surface_position(point: Vector2) -> Vector3:
	# The server simulates a 2D plane; presentation follows the same ground mesh
	# used for touch picking, including the bridge deck and raised pasture slopes.
	return Vector3(point.x, meadow.surface_height(point.x, point.y) + 0.03, point.y)

func _on_snapshot(snapshot: Dictionary) -> void:
	latest = snapshot
	var landscape := str(snapshot.get("landscape", "alpine"))
	if landscape != selected_landscape:
		_select_landscape(landscape)
	meadow.preview.hide()
	meadow.gate_open = bool(snapshot.get("gate_open", false))
	var present: Dictionary = {}
	var player_count := 0
	for kind in ["player", "dog", "sheep"]:
		for data: Dictionary in snapshot.get("sheep" if kind == "sheep" else kind + "s", []):
			var id := str(data.id)
			present[id] = true
			var pos := _surface_position(Vector2(float(data.position.x), float(data.position.y)))
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
	invite_label.visible = player_count < 2
	companion_label.visible = player_count < 2
	companion_label.text = "Waiting for your other herder"
	var settled := int(snapshot.get("settled", 0))
	if settled == 10 and last_settled < 10:
		moment_label.text = "A peaceful place to rest. You brought them here together."
		_hint("Sit together. The corgis have earned a little affection.", 10.0)
	elif settled < 10 and last_settled == 10:
		moment_label.text = ""
	last_settled = settled
	_update_context()

func _update_context() -> void:
	if not actors.has(local_id):
		return
	var player: Node3D = actors[local_id].node
	if actors.has(selected_dog):
		var dog: Node3D = actors[selected_dog].node
		# Interaction reach is authoritative in plan coordinates, not rendered height.
		pet_button.visible = Vector2(player.position.x, player.position.z).distance_to(Vector2(dog.position.x, dog.position.z)) < 2.5
	else:
		pet_button.hide()

func _process(delta: float) -> void:
	elapsed += delta
	hint_time -= delta
	if hint_time <= 0 and hint_time > -delta:
		hint_label.text = "Tap a place for %s." % selected_dog.capitalize() if go_pending else ""
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
		# Re-sample after horizontal prediction/interpolation. Linear 3D interpolation
		# would cut through a hill or float above a hollow between snapshots.
		node.position.y = meadow.surface_height(node.position.x, node.position.z) + 0.03
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
	if actors.has(local_id) and hud.visible:
		meadow.follow_player(actors[local_id].node.position)
	if actors.has(selected_dog) and hud.visible and (command_panel.visible or go_pending):
		meadow.selection.visible = true
		meadow.place_marker(meadow.selection, actors[selected_dog].node.position)
	else:
		meadow.selection.visible = false
	if capture_after >= 0:
		capture_after -= delta
		if capture_after <= 0:
			capture_after = -1
			_capture.call_deferred()

func _next_waypoint(point: Vector2, target: Vector2) -> Vector2:
	# Mirror server/internal/game/world.go waypoint, including stops on the bridge.
	if point.x < -1.5 and target.x > -1.5:
		if absf(point.y) > 1.4:
			return Vector2(-2.1, 0)
		return target if target.x < 1.5 else Vector2(2.1, 0)
	if point.x > 1.5 and target.x < 1.5:
		if absf(point.y) > 1.4:
			return Vector2(2.1, 0)
		return target if target.x > -1.5 else Vector2(-2.1, 0)
	if absf(point.x) <= 1.5:
		return target if absf(target.x) <= 1.5 else Vector2(2.1 if target.x >= 0 else -2.1, 0)
	if (point.x < 6 and target.x > 6) or (point.x > 6 and target.x < 6):
		var side := 1.0 if point.x > 6 else -1.0
		return Vector2(6 + side * 0.6, 0) if not meadow.gate_open or absf(point.y) > 1.4 else Vector2(6 - side * 0.6, 0)
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
	_on_snapshot({"gate_open": false, "settled": 0, "landscape": selected_landscape,
		"players": [{"id": "p1", "position": {"x": -10, "y": 2}, "state": "idle", "connected": true}, {"id": "p2", "position": {"x": -4, "y": 5}, "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "position": {"x": -8, "y": 3}, "state": "wander"}, {"id": "maple", "position": {"x": -2.5, "y": 4}, "state": "wander"}], "sheep": sheep})
	status_label.text = "Preview · not connected"

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(capture_path)
	print("SCREENSHOT_SAVED " + capture_path if result == OK else "SCREENSHOT_FAILED")
	get_tree().quit(0 if result == OK else 1)
