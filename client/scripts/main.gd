extends Node3D

const Connection = preload("res://scripts/network.gd")
const Meadow = preload("res://scripts/meadow.gd")
const RockNavigation = preload("res://scripts/rock_navigation.gd")
const CloudNavigation = preload("res://scripts/cloud_navigation.gd")
const Soundscape = preload("res://scripts/soundscape.gd")
const ShoreNavigation = preload("res://scripts/shore_navigation.gd")
const CommonsNavigation = preload("res://scripts/commons_navigation.gd")
const DogDrag = preload("res://scripts/dog_drag_gesture.gd")
const PracticeGuide = preload("res://scripts/practice_guide.gd")
const RegionNavigation = preload("res://scripts/region_navigation.gd")
const INK := Color("304d40")
const MUTED := Color("6c7c66")
const PAPER := Color("f5f0df")
const ACCENT := Color("466e59")
const LANDSCAPES := {"alpine": "Alpine valley", "cactus": "Cactus canyon", "larch": "Larch Hollow", "orchard": "Sunward Orchard", "oasis": "Canyon Oasis", "cloud": "Cloud Pasture", "juniper": "Juniper Shore", "bellflower": "Bellflower Commons", "alpine_valley": "Long Alpine valley"}

var meadow: MeadowDiorama
var network: HerdConnection
var soundscape: HerdSoundscape
var dog_drag: DogDrag
var practice_guide: PanelContainer
var restart_guide_button: Button
var guide_settings_row: HBoxContainer
var sound_button: Button
var actors: Dictionary = {}
var latest: Dictionary = {}
var local_id := ""
var selected_dog := "mochi"
var go_pending := false
var movement_target := Vector2.ZERO
var movement_seq := 0
var movement_route: Array[Vector2] = []
var route_target := Vector2.INF
var moving := false
var elapsed := 0.0
var hint_time := 0.0
var had_snapshot := false
var awaiting_authoritative_snapshot := true
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
var arrival_noticed := false
var moment_time := 0.0
var selected_landscape := "alpine"
var alpine_button: Button
var cactus_button: Button
var larch_button: Button
var orchard_button: Button
var oasis_button: Button
var cloud_button: Button
var juniper_button: Button
var bellflower_button: Button
var long_valley_button: Button
var region_navigation: RefCounted
var region_display_plans := 0
var _canonical_region: Dictionary = {}
var region_label: Label
var world_layout := {"version": 1, "bridge_y": 0.0, "gate_y": 0.0}

func _ready() -> void:
	meadow = Meadow.new()
	add_child(meadow)
	network = Connection.new()
	add_child(network)
	network.snapshot_received.connect(_on_snapshot)
	network.status_changed.connect(_on_status)
	network.request_failed.connect(_on_error)
	network.herd_joined.connect(_on_herd_joined)
	network.message_sent.connect(_on_message_sent)
	soundscape = Soundscape.new()
	add_child(soundscape)
	_build_ui()
	dog_drag = DogDrag.new()
	add_child(dog_drag)
	dog_drag.configure(self)
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
	_select_startup_landscape(OS.get_cmdline_user_args())
	if preview_mode:
		_show_preview()

func _select_startup_landscape(arguments: PackedStringArray) -> void:
	# A new player sees the dedicated, optional practice map first. Existing
	# invitations and explicit art previews never become a forced tutorial.
	if network.has_saved_herd() or preview_mode:
		return
	for argument in arguments:
		if argument.begins_with("--landscape="):
			return
	_select_landscape("bellflower")

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
	var landscapes := GridContainer.new()
	landscapes.columns = 2
	landscapes.add_theme_constant_override("h_separation", 8)
	landscapes.add_theme_constant_override("v_separation", 8)
	column.add_child(landscapes)
	alpine_button = _button("Alpine valley", func() -> void: _select_landscape("alpine"))
	cactus_button = _button("Cactus canyon", func() -> void: _select_landscape("cactus"))
	larch_button = _button("Larch Hollow", func() -> void: _select_landscape("larch"))
	orchard_button = _button("Sunward Orchard", func() -> void: _select_landscape("orchard"))
	oasis_button = _button("Canyon Oasis", func() -> void: _select_landscape("oasis"))
	cloud_button = _button("Cloud Pasture", func() -> void: _select_landscape("cloud"))
	juniper_button = _button("Juniper Shore", func() -> void: _select_landscape("juniper"))
	bellflower_button = _button("Practice meadow", func() -> void: _select_landscape("bellflower"))
	long_valley_button = _button("Long Alpine valley", func() -> void: _select_landscape("alpine_valley"))
	for button in [bellflower_button, long_valley_button, alpine_button, cactus_button, larch_button, orchard_button, oasis_button, cloud_button, juniper_button]:
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
	var settings_row := _row(column)
	guide_settings_row = settings_row
	var server_toggle := _button("Server address", func() -> void: endpoint_input.visible = not endpoint_input.visible)
	server_toggle.flat = true
	server_toggle.add_theme_font_size_override("font_size", 17)
	server_toggle.custom_minimum_size.y = 64
	server_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_row.add_child(server_toggle)
	sound_button = _button("Sound · on" if soundscape.enabled else "Sound · off", func() -> void: soundscape.set_enabled(not soundscape.enabled))
	sound_button.flat = true
	sound_button.add_theme_font_size_override("font_size", 17)
	sound_button.custom_minimum_size.y = 64
	sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_row.add_child(sound_button)
	restart_guide_button = _button("Restart guide", _restart_guide)
	restart_guide_button.flat = true
	restart_guide_button.add_theme_font_size_override("font_size", 17)
	restart_guide_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_guide_button.hide()
	ui.add_child(restart_guide_button)
	soundscape.enabled_changed.connect(func(value: bool) -> void: sound_button.text = "Sound · on" if value else "Sound · off")
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
	practice_guide = PracticeGuide.new()
	column.add_child(practice_guide)
	practice_guide.preference_changed.connect(_refresh_guide_settings)
	_refresh_guide_settings()
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

func _close_controls(cancel_dog_drag := true) -> void:
	if cancel_dog_drag and dog_drag != null:
		dog_drag.cancel()
	command_panel.hide()
	sit_button.hide()
	go_cancel.hide()
	go_pending = false

func _configure() -> bool:
	menu_error.text = ""
	return network.configure(endpoint_input.text, name_input.text)

func _default_layout(landscape: String) -> Dictionary:
	if landscape == "alpine_valley":
		if _canonical_region.is_empty():
			_canonical_region = RegionNavigation.default_region()
		return {"version": 7, "bridge_y": 0.0, "gate_y": 0.0, "region": _canonical_region.duplicate(true)}
	if landscape == "bellflower":
		return CommonsNavigation.layout()
	if landscape == "juniper":
		return ShoreNavigation.layout()
	if landscape == "cloud":
		return CloudNavigation.layout()
	if landscape == "oasis":
		return {"version": 3, "bridge_y": 0.0, "gate_y": 0.0, "rock_pass": {"center": {"x": 0.0, "y": 0.0}, "radius": 3.4}}
	if landscape == "orchard":
		return {"version": 2, "bridge_y": 3.0, "gate_y": 2.0, "forage": {"id": "windfall", "center": {"x": -7.0, "y": -5.0}, "radius": 2.2}}
	return {"version": 1, "bridge_y": -4.0 if landscape == "larch" else 0.0, "gate_y": 4.0 if landscape == "larch" else 0.0}

func _supported_layout(landscape: String, layout: Dictionary) -> bool:
	return LANDSCAPES.has(landscape) and _matches_layout(layout, _default_layout(landscape))

func _matches_layout(value: Variant, expected: Variant) -> bool:
	# JSON numbers decode as floats; nested terrain/forage geometry must still
	# match exactly. Unknown keys or coerced string/bool coordinates are unsafe.
	if expected is Dictionary:
		if not value is Dictionary or value.size() != expected.size():
			return false
		for key in expected:
			if not value.has(key) or not _matches_layout(value[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not value is Array or value.size() != expected.size():
			return false
		for i in expected.size():
			if not _matches_layout(value[i], expected[i]):
				return false
		return true
	if typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return typeof(value) in [TYPE_INT, TYPE_FLOAT] and float(value) == float(expected)
	return typeof(value) == typeof(expected) and value == expected

func _select_landscape(landscape: String, layout: Dictionary = {}) -> void:
	if not LANDSCAPES.has(landscape):
		return
	var next_layout := _default_layout(landscape) if layout.is_empty() else layout.duplicate(true)
	# A missing/invalid prepared region must not leave a new logical landscape
	# paired with the previous rendered meadow. No old geometry is guessed.
	meadow.set_landscape(landscape, next_layout)
	if meadow.landscape != landscape:
		return
	if landscape == "alpine_valley":
		_ensure_region_navigation()
	if dog_drag != null:
		dog_drag.cancel()
	selected_landscape = landscape
	movement_route.clear()
	route_target = Vector2.INF
	world_layout = next_layout
	for button in [alpine_button, cactus_button, larch_button, orchard_button, oasis_button, cloud_button, juniper_button, bellflower_button, long_valley_button]:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
	_primary({"alpine": alpine_button, "cactus": cactus_button, "larch": larch_button, "orchard": orchard_button, "oasis": oasis_button, "cloud": cloud_button, "juniper": juniper_button, "bellflower": bellflower_button, "alpine_valley": long_valley_button}[landscape])
	if region_label != null:
		region_label.text = LANDSCAPES[landscape]
	if create_button != null:
		create_button.text = {"alpine": "Start in the Alps", "cactus": "Start in the canyon", "larch": "Rest in Larch Hollow", "orchard": "Wander through the orchard", "oasis": "Find shade in the oasis", "cloud": "Wander above the valley", "juniper": "Wander beside the lake", "bellflower": "Linger in the meadow", "alpine_valley": "Explore the long valley"}[landscape]

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
	larch_button.disabled = value
	orchard_button.disabled = value
	oasis_button.disabled = value
	cloud_button.disabled = value
	juniper_button.disabled = value
	bellflower_button.disabled = value
	long_valley_button.disabled = value
	if value:
		menu_error.text = "Opening a little world…"

func _on_herd_joined(code: String) -> void:
	soundscape.invalidate_snapshot()
	meadow.reset_player_follow()
	_set_busy(false)
	menu_error.text = ""
	local_id = str(network.credentials.get("player_id", ""))
	invite_label.text = "Invite · " + code
	welcome.hide()
	hud.show()
	meadow.preview.hide()
	# Switching herds never leaves actors or movement from the previous world.
	for id in actors:
		actors[id].node.queue_free()
	actors.clear()
	region_display_plans = 0
	latest = {}
	had_snapshot = false
	awaiting_authoritative_snapshot = true
	movement_route.clear()
	route_target = Vector2.INF
	moving = false
	_close_controls()
	_hint("Tap to walk. Tap a corgi to talk to them.", 6.0)
	invite_label.show()
	companion_label.show()
	moment_label.text = ""
	last_settled = 0
	arrival_noticed = false
	moment_time = 0.0
	_sync_soundscape_gates()
	_sync_guide_gates()

func _on_status(text: String, is_connected: bool) -> void:
	soundscape.set_connected(is_connected)
	status_label.text = "" if is_connected else text
	status_label.visible = not is_connected
	status_label.add_theme_color_override("font_color", Color("4a7459") if is_connected else Color("926e4e"))
	if not is_connected:
		if dog_drag != null:
			dog_drag.cancel()
		moving = false
		# A tap may have been predicted but never received by the server. Rebase
		# once after reconnect instead of waiting forever for that lost sequence.
		# Arrival bookkeeping is separate: reconnect must not repeat its message.
		awaiting_authoritative_snapshot = true
	_sync_guide_gates()

func _on_error(message: String) -> void:
	_set_busy(false)
	menu_error.text = message
	_hint(message, 7.0)
	if (not network.has_saved_herd() or network.update_required or network.auth_rejected) and not preview_mode:
		_open_settings()

func _open_settings() -> void:
	if dog_drag != null:
		dog_drag.cancel()
	soundscape.set_gameplay_visible(false)
	network.disconnect_herd()
	welcome.show()
	hud.hide()
	resume_button.visible = network.has_saved_herd()
	endpoint_input.text = network.endpoint
	name_input.text = network.display_name
	moving = false
	_sync_soundscape_gates()
	_sync_guide_gates()
	_refresh_guide_settings()

func _sync_soundscape_gates() -> void:
	soundscape.set_gameplay_visible(hud.visible and not welcome.visible and not preview_mode)
	soundscape.set_connected(network.connected and not network.paused)

func _sync_guide_gates() -> void:
	if practice_guide != null:
		practice_guide.set_gameplay_gate(network.connection_epoch, network.connected and not network.paused and hud.visible and not welcome.visible and not preview_mode and not awaiting_authoritative_snapshot)

func _on_message_sent(message: Dictionary, epoch: int) -> void:
	_sync_guide_gates()
	practice_guide.record_message(message, epoch)

func _refresh_guide_settings() -> void:
	if restart_guide_button == null or practice_guide == null:
		return
	practice_guide.preferences.persist_config = network.persist_config
	var available: bool = practice_guide.can_restart(network.endpoint, str(network.credentials.get("code", "")), str(network.credentials.get("player_id", "")))
	# Non-practice settings retain their original two-button structure, not an
	# invisible third action. The optional control only joins the row when useful.
	var parent: Node = guide_settings_row if available else ui
	if restart_guide_button.get_parent() != parent:
		restart_guide_button.hide()
		restart_guide_button.reparent(parent, false)
	restart_guide_button.visible = available

func _restart_guide() -> void:
	practice_guide.restart_for(network.endpoint, str(network.credentials.get("code", "")), str(network.credentials.get("player_id", "")))
	menu_error.text = "The guide will begin when you return to the practice meadow."

func _copy_invite() -> void:
	DisplayServer.clipboard_set(str(network.credentials.get("code", "MEADOW")))
	_hint("Invite copied. Share it with your other herder.", 4.0)

func _select_dog(id: String) -> void:
	_close_controls()
	selected_dog = id
	practice_guide.select_dog(id)
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
	# A dog may move between the snapshot/layout update and the tap's release.
	# Keep this check at activation as well as on the disabled button state.
	if action == "pet" and not _can_pet_selected_dog():
		_update_context()
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

func _input(event: InputEvent) -> void:
	# Only an already-armed dog pointer is captured before GUI dispatch. A
	# release over a Button cancels the drag instead of activating that Button.
	if dog_drag != null and dog_drag.capture(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if dog_drag.armed or go_pending or command_panel.visible or sit_button.visible:
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
	# Native touch and its synthetic mouse event describe one action, not two.
	# GUI still receives emulated mouse events; only world input ignores them.
	if event.device == DogDrag.EMULATED_DEVICE:
		return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_world_pointer_press(event.position, "touch", event.index)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			meadow.zoom = clampf(meadow.zoom + (-0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.05), 0.8, 1.18)
			meadow.fit_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_world_pointer_press(event.position, "mouse", 0)

func _world_pointer_press(position: Vector2, source: String, index: int) -> void:
	if dog_drag == null or not dog_drag.can_interact() or dog_drag.over_ui(position):
		return
	var interaction := _pick_world_interaction(position) if not go_pending else ""
	_world_tap(position)
	if interaction.begins_with("dog:"):
		dog_drag.arm(interaction.trim_prefix("dog:"), position, source, index)

func _pick_world_interaction(screen_pos: Vector2) -> String:
	var candidates: Array[Dictionary] = []
	for id in ["mochi", "maple"]:
		if actors.has(id):
			candidates.append({"id": "dog:" + id, "position": actors[id].node.position + Vector3(0, 0.5, 0), "radius": 44.0})
	if actors.has(local_id):
		candidates.append({"id": "player", "position": actors[local_id].node.position + Vector3(0, 0.9, 0), "radius": 40.0})
		if not _has_route_navigation() and not meadow.gate_open:
			candidates.append({"id": "gate", "position": _surface_position(Vector2(6, world_layout.gate_y)) + Vector3(0, 0.7, 0), "radius": 42.0})
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
				if Vector2(player.position.x - 6, player.position.z - float(world_layout.gate_y)).length() < 3.0:
					_interact("gate")
				else:
					movement_target = Vector2(5 if player.position.x < 6 else 7, world_layout.gate_y)
					movement_seq = network.move_to(movement_target)
					moving = true
					_hint("Walk closer, then tap the gate.", 3.0)
				return
	var ground := meadow.ground_at(screen_pos)
	if not ground.is_finite():
		_hint("The shore curves around the water. Keep to the beach and grass." if selected_landscape == "juniper" else "The steep slopes shelter this valley. Keep to the open ground.", 3.0)
		return
	# Water is readable as a real obstacle; tap the bridge or other bank to cross.
	if not _has_route_navigation() and absf(ground.x) < 1.5 and absf(ground.z - float(world_layout.bridge_y)) > 1.85:
		_hint("The bridge is the dry way across.")
		return
	var target := Vector2(ground.x, ground.z)
	if not _walkable(target):
		var message := "Follow the fence to the gate."
		if selected_landscape == "oasis":
			message = "There is open ground around the rock."
		elif selected_landscape == "cloud":
			message = "The grassy ridge is the gentle way through."
		elif selected_landscape == "juniper":
			message = "The beach is the gentle way around the lake."
		elif selected_landscape == "bellflower":
			message = "Both grassy branches lead to open meadow."
		_hint(message, 3.0)
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
	var landscape := str(snapshot.get("landscape", "alpine"))
	var layout: Variant = snapshot.get("layout", {})
	# Old centered worlds remain compatible. Never guess an unfamiliar route,
	# or silently display a centered bridge for a new landscape.
	if not LANDSCAPES.has(landscape) or not layout is Dictionary:
		network.require_update("Update Corgi Herding to visit this landscape.")
		return
	if layout.is_empty() and landscape in ["alpine", "cactus"]:
		layout = _default_layout(landscape)
	if not _supported_layout(landscape, layout):
		network.require_update("Update Corgi Herding to follow this valley's route.")
		return
	var region_actors: Dictionary = {}
	if landscape == "alpine_valley":
		_ensure_region_navigation()
		region_actors = _validate_region_snapshot(snapshot)
		if region_actors.is_empty():
			network.require_update("This valley sent an unsupported animal route. Your invitation is kept.")
			return
	layout = _default_layout(landscape)
	var first_snapshot := not had_snapshot
	var restore_movement := first_snapshot or awaiting_authoritative_snapshot
	if landscape != selected_landscape or layout != world_layout:
		_select_landscape(landscape, layout)
	if landscape == "alpine_valley" and (meadow.landscape != landscape or meadow.region_presentation == null):
		network.require_update("This valley's scenery could not be loaded. Your invitation is kept.")
		return
	if landscape == "alpine_valley":
		for data: Dictionary in region_actors.values():
			for point: Vector2 in [data.position, data.get("target", data.position)]:
				if not is_finite(meadow.surface_height(point.x, point.y)):
					network.require_update("This valley's ground could not be loaded. Your invitation is kept.")
					return
	latest = snapshot
	meadow.preview.hide()
	meadow.gate_open = bool(snapshot.get("gate_open", false))
	var present: Dictionary = {}
	var player_count := 0
	for kind in ["player", "dog", "sheep"]:
		for data: Dictionary in snapshot.get("sheep" if kind == "sheep" else kind + "s", []):
			var id := str(data.id)
			present[id] = true
			var point := Vector2(float(data.position.x), float(data.position.y))
			if landscape == "alpine_valley":
				point = region_actors[id].position
			elif _has_route_navigation():
				point = _presentation_point(point)
			var pos := _surface_position(point)
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
					if restore_movement:
						movement_seq = server_seq
						actor.node.position = pos
						if data.has("target"):
							movement_target = Vector2(float(data.target.x), float(data.target.y))
							if _has_route_navigation():
								movement_target = _presentation_point(movement_target)
							moving = actor.state == "walking" and Vector2(pos.x, pos.z).distance_to(movement_target) > 0.12
						else:
							movement_target = Vector2(pos.x, pos.z)
							moving = false
						movement_route.clear()
						route_target = Vector2.INF
						awaiting_authoritative_snapshot = false
					if server_seq >= movement_seq:
						if _has_route_navigation():
							if landscape == "alpine_valley":
								var accepted_target: Vector2 = region_actors[id].target
								if server_seq > movement_seq or movement_target != accepted_target:
									movement_seq = server_seq
									movement_target = accepted_target
									moving = actor.state == "walking" and point.distance_to(movement_target) > 0.12
								movement_route.assign(region_actors[id].route)
							else:
								movement_route = _decode_route(data.get("route", []))
							route_target = movement_target
						# Small correction retains immediate touch feedback; large drift snaps.
						var drift: float = actor.node.position.distance_to(pos)
						var correction: Vector3 = actor.node.position.lerp(pos, 0.24)
						if _has_route_navigation() and not _route_visible(Vector2(actor.node.position.x, actor.node.position.z), Vector2(correction.x, correction.z)):
							correction = pos
						actor.node.position = pos if drift > 2.0 else correction
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
	if first_snapshot and settled == 10:
		arrival_noticed = true
	if selected_landscape in ["cloud", "juniper", "bellflower", "alpine_valley"]:
		# All three shelves are places to linger; reaching the highest one is
		# neither a completion event nor more important than resting halfway.
		moment_label.text = ""
		moment_time = 0.0
	elif settled == 10 and last_settled < 10 and not arrival_noticed:
		arrival_noticed = true
		moment_label.text = "A peaceful place to rest."
		moment_label.modulate.a = 1.0
		moment_time = 6.0
	elif settled < 10:
		moment_label.text = ""
		moment_time = 0.0
	last_settled = settled
	_update_context()
	_sync_soundscape_gates()
	if actors.has(local_id) and not awaiting_authoritative_snapshot:
		soundscape.set_listener_position(actors[local_id].node.position)
		soundscape.observe_snapshot()
		# No optimistic/cached snapshot path reaches the teaching module. It also
		# checks identity, receipt tick and the exact requested observed result.
		practice_guide.preferences.persist_config = network.persist_config
		practice_guide.bind_herd(network.endpoint, str(network.credentials.get("code", "")), local_id, landscape if not preview_mode else "")
		_sync_guide_gates()
		practice_guide.observe_snapshot(snapshot, network.connection_epoch)

func _update_context() -> void:
	# Four stable slots: removing Pet lets Go expand under an already-aimed tap.
	# The whole panel still disappears when closed; unavailable Pet only dims.
	pet_button.disabled = not _can_pet_selected_dog()

func _can_pet_selected_dog() -> bool:
	if not actors.has(local_id) or not actors.has(selected_dog):
		return false
	var player: Node3D = actors[local_id].node
	var dog: Node3D = actors[selected_dog].node
	if not is_instance_valid(player) or not is_instance_valid(dog):
		return false
	# Interaction reach is authoritative in plan coordinates, not rendered height.
	return Vector2(player.position.x, player.position.z).distance_to(Vector2(dog.position.x, dog.position.z)) < 2.5

func _process(delta: float) -> void:
	_sync_soundscape_gates()
	_sync_guide_gates()
	elapsed += delta
	if moment_time > 0:
		moment_time = maxf(0.0, moment_time - delta)
		moment_label.modulate.a = minf(moment_time, 1.0)
		if moment_time == 0:
			moment_label.text = ""
	hint_time -= delta
	if hint_time <= 0 and hint_time > -delta:
		hint_label.text = "Tap a place for %s." % selected_dog.capitalize() if go_pending else ""
	for id in actors:
		var actor: Dictionary = actors[id]
		var node: Node3D = actor.node
		if _has_route_navigation():
			var safe_point := _presentation_point(Vector2(node.position.x, node.position.z))
			node.position.x = safe_point.x
			node.position.z = safe_point.y
			var safe_target := _presentation_point(Vector2(actor.target.x, actor.target.z))
			actor.target.x = safe_target.x
			actor.target.z = safe_target.y
		var before := node.position
		if id == local_id and moving and (network.connected or preview_mode):
			var point := Vector2(node.position.x, node.position.z)
			var next := _predict_step(point, movement_target, delta)
			if _walkable(next):
				node.position.x = next.x
				node.position.z = next.y
			if next.distance_to(movement_target) < 0.08:
				moving = false
		elif id != local_id:
			var next_position: Vector3 = node.position.lerp(actor.target, 1.0 - exp(-delta * 12.0))
			if selected_landscape == "alpine_valley":
				next_position = _region_display_step(actor, node.position, next_position)
			elif _has_route_navigation():
				var point := Vector2(node.position.x, node.position.z)
				var next := Vector2(next_position.x, next_position.z)
				if not _route_visible(point, next):
					# Interpolating a chord across a curved route must not draw an
					# animal through solid rock during a delayed snapshot.
					var target := Vector2(actor.target.x, actor.target.z)
					var route := _plan_route(point, target)
					next = point.move_toward(_route_waypoint(point, target, route), point.distance_to(next))
					if _route_visible(point, next):
						next_position.x = next.x
						next_position.z = next.y
					else:
						next_position = node.position
			node.position = next_position
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
		elif actor.kind == "sheep":
			var head := body.get_node_or_null("Head") as Node3D
			if head != null:
				# A lowered muzzle is the feedback: no apple counter or task popup.
				var nibbling: bool = actor.state == "nibbling" and not walking
				var head_angle := -0.82 + sin(phase * 0.75) * 0.06 if nibbling else 0.0
				head.rotation.x = lerpf(head.rotation.x, head_angle, minf(delta * 7.0, 1.0))
	if command_panel.visible:
		_update_context()
	if actors.has(local_id) and hud.visible:
		meadow.follow_player(actors[local_id].node.position, moving and (network.connected or preview_mode))
		soundscape.set_listener_position(actors[local_id].node.position)
	else:
		meadow.stop_player_follow()
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

func _predict_step(point: Vector2, target: Vector2, delta: float) -> Vector2:
	if not _has_route_navigation():
		return point.move_toward(_next_waypoint(point, target), 4.0 * delta)
	var remaining := 4.0 * minf(delta, 0.25)
	while remaining > 0.00001:
		var distance := minf(remaining, 0.08)
		var next := point.move_toward(_next_waypoint(point, target), distance)
		if not _walkable(next) or not _route_visible(point, next):
			break
		point = next
		remaining -= distance
	return point

func _next_waypoint(point: Vector2, target: Vector2) -> Vector2:
	if _has_route_navigation():
		if target != route_target:
			movement_route = _plan_route(point, target)
			route_target = target
		return _route_waypoint(point, target, movement_route)
	# Mirror server/internal/game/world.go waypoint, including stops on the bridge.
	var bridge_y := float(world_layout.bridge_y)
	# Returning from pasture reaches the fence before the river. On offset
	# routes, river-first routing would steer directly into the closed fence.
	if point.x > 6 and target.x < 6:
		return _gate_waypoint(point)
	if point.x < -1.5 and target.x > -1.5:
		if absf(point.y - bridge_y) > 1.4:
			return Vector2(-2.1, bridge_y)
		return target if target.x < 1.5 else Vector2(2.1, bridge_y)
	if point.x > 1.5 and target.x < 1.5:
		if absf(point.y - bridge_y) > 1.4:
			return Vector2(2.1, bridge_y)
		return target if target.x > -1.5 else Vector2(-2.1, bridge_y)
	if absf(point.x) <= 1.5:
		return target if absf(target.x) <= 1.5 else Vector2(2.1 if target.x >= 0 else -2.1, bridge_y)
	if (point.x < 6 and target.x > 6) or (point.x > 6 and target.x < 6):
		return _gate_waypoint(point)
	return target

func _gate_waypoint(point: Vector2) -> Vector2:
	var side := 1.0 if point.x > 6 else -1.0
	var gate_y := float(world_layout.gate_y)
	return Vector2(6 + side * 0.6, gate_y) if not meadow.gate_open or absf(point.y - gate_y) > 1.4 else Vector2(6 - side * 0.6, gate_y)

func _walkable(point: Vector2) -> bool:
	if selected_landscape == "alpine_valley":
		return region_navigation != null and region_navigation.contains(point)
	if absf(point.x) > 17 or absf(point.y) > 11:
		return false
	if selected_landscape == "bellflower":
		return CommonsNavigation.contains(point)
	if selected_landscape == "juniper":
		return ShoreNavigation.contains(point)
	if selected_landscape == "cloud":
		return CloudNavigation.contains(point)
	if selected_landscape == "oasis":
		return point.distance_to(Vector2(world_layout.rock_pass.center.x, world_layout.rock_pass.center.y)) >= float(world_layout.rock_pass.radius)
	if absf(point.x) < 1.5 and absf(point.y - float(world_layout.bridge_y)) > 1.85:
		return false
	if absf(point.x - 6) < 0.18 and (not meadow.gate_open or absf(point.y - float(world_layout.gate_y)) > 1.8):
		return false
	return true

func _has_route_navigation() -> bool:
	return selected_landscape in ["oasis", "cloud", "juniper", "bellflower", "alpine_valley"]

func _presentation_point(point: Vector2) -> Vector2:
	if selected_landscape == "alpine_valley":
		return region_navigation.presentation_point(point)
	if selected_landscape == "bellflower":
		return CommonsNavigation.presentation_point(point)
	if selected_landscape == "juniper":
		return ShoreNavigation.presentation_point(point)
	return CloudNavigation.presentation_point(point) if selected_landscape == "cloud" else RockNavigation.presentation_point(point)

func _route_visible(from: Vector2, to: Vector2) -> bool:
	if selected_landscape == "alpine_valley":
		return region_navigation.visible(from, to)
	if selected_landscape == "bellflower":
		return CommonsNavigation.visible(from, to)
	if selected_landscape == "juniper":
		return ShoreNavigation.visible(from, to)
	return CloudNavigation.visible(from, to) if selected_landscape == "cloud" else RockNavigation.visible(from, to)

func _plan_route(from: Vector2, to: Vector2) -> Array[Vector2]:
	if selected_landscape == "alpine_valley":
		return region_navigation.plan(from, to)
	if selected_landscape == "bellflower":
		return CommonsNavigation.plan(from, to)
	if selected_landscape == "juniper":
		return ShoreNavigation.plan(from, to)
	return CloudNavigation.plan(from, to) if selected_landscape == "cloud" else RockNavigation.plan(from, to)

func _route_waypoint(from: Vector2, to: Vector2, route: Array[Vector2]) -> Vector2:
	if selected_landscape == "alpine_valley":
		return region_navigation.next_waypoint(from, to, route)
	if selected_landscape == "bellflower":
		return CommonsNavigation.next_waypoint(from, to, route)
	if selected_landscape == "juniper":
		return ShoreNavigation.next_waypoint(from, to, route)
	return CloudNavigation.next_waypoint(from, to, route) if selected_landscape == "cloud" else RockNavigation.next_waypoint(from, to, route)

func _decode_route(data: Variant) -> Array[Vector2]:
	if selected_landscape == "alpine_valley":
		# Convenience only; actual v7 wire snapshots use validated_route before
		# touching latest/actors so invalid [] cannot masquerade as a direct leg.
		return region_navigation.decode_route(data)
	if selected_landscape == "bellflower":
		return CommonsNavigation.decode_route(data)
	if selected_landscape == "juniper":
		return ShoreNavigation.decode_route(data)
	return CloudNavigation.decode_route(data) if selected_landscape == "cloud" else RockNavigation.decode_route(data)

func _acknowledge(id: String) -> void:
	if actors.has(id):
		actors[id].ack = 1.5

func _ensure_region_navigation() -> void:
	if region_navigation == null:
		region_navigation = RegionNavigation.new(_default_layout("alpine_valley").region)

func _region_point(value: Variant) -> Vector2:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["x", "y"]):
		return Vector2.INF
	for coordinate: Variant in [value.x, value.y]:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
			return Vector2.INF
	var point: Vector2 = region_navigation.presentation_point(Vector2(value.x, value.y))
	return point if region_navigation.contains(point) else Vector2.INF

func _validate_region_snapshot(snapshot: Dictionary) -> Dictionary:
	if not region_navigation.valid or snapshot.get("type") != "snapshot" or snapshot.get("code") != str(network.credentials.get("code", "")):
		return {}
	var tick: Variant = snapshot.get("tick")
	if not _region_integer(tick):
		return {}
	var result: Dictionary = {}
	for category: String in ["players", "dogs", "sheep"]:
		var entries: Variant = snapshot.get(category)
		if not entries is Array or entries.is_empty() or entries.size() > (2 if category != "sheep" else 40) or (category == "dogs" and entries.size() != 2):
			return {}
		for value: Variant in entries:
			if not value is Dictionary or not value.get("id") is String or value.id.is_empty() or value.id.length() > 64 or result.has(value.id) or not value.get("state") is String:
				return {}
			var point := _region_point(value.get("position"))
			if not point.is_finite():
				return {}
			var data := {"position": point}
			if category != "sheep":
				var target := _region_point(value.get("target"))
				if not target.is_finite():
					return {}
				var decoded: Dictionary = region_navigation.validated_route(value.get("route", []), point, target)
				if not decoded.ok:
					return {}
				data.target = target
				data.route = decoded.route
			if category == "players" and (not value.get("connected") is bool or not _region_integer(value.get("seq"))):
				return {}
			result[value.id] = data
	var local_present := false
	for player: Dictionary in snapshot.players:
		local_present = local_present or (player.id == local_id and player.connected)
	return result if local_present else {}

func _region_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) <= 9007199254740991.0 and floorf(float(value)) == float(value)

func _region_display_step(actor: Dictionary, position: Vector3, proposed: Vector3) -> Vector3:
	var from := Vector2(position.x, position.z)
	var target := Vector2(actor.target.x, actor.target.z)
	if not actor.has("display_route"):
		actor.display_route = [] as Array[Vector2]
		actor.display_target = Vector2.INF
		actor.display_blocked = false
	var route: Array[Vector2] = actor.display_route
	if region_navigation.visible(from, target):
		route.clear()
		actor.display_target = target
		actor.display_blocked = false
		return proposed
	while not route.is_empty() and from.distance_to(route[0]) <= 0.08:
		route.pop_front()
	var usable: bool = not route.is_empty() and region_navigation.visible(from, route[0]) and region_navigation.visible(route[-1], target)
	# A moving authoritative endpoint can often reuse the same anchor queue.
	# A failed fixed endpoint is also remembered, avoiding a per-frame 2N plan.
	if not usable and (actor.display_target != target or not actor.display_blocked):
		route.assign(region_navigation.plan(from, target))
		region_display_plans += 1
		actor.display_blocked = route.is_empty()
	actor.display_target = target
	if route.is_empty():
		return position
	var next := from.move_toward(route[0], from.distance_to(Vector2(proposed.x, proposed.z)))
	return Vector3(next.x, position.y, next.y) if region_navigation.visible(from, next) else position

func _show_preview() -> void:
	local_id = "p1"
	network.credentials = {"code": "MEADOW", "player_id": "p1"}
	_on_herd_joined("MEADOW")
	var sheep: Array = []
	for i in range(10):
		var point := Vector2(-7 + (i % 3) * 1.15, -2 + floorf(i / 3.0) * 1.15) if _has_route_navigation() else Vector2(-5.5 + sin(i * 2.3) * 3, -1.6 + cos(i * 1.6) * 2.6)
		if selected_landscape == "juniper":
			point = Vector2(-10.7 + i % 3, -0.4 + floorf(i / 3.0) * 1.05)
		elif selected_landscape == "bellflower":
			point = Vector2(-6.7 + i % 3, -0.4 + floorf(i / 3.0) * 1.05)
		sheep.append({"id": "s%d" % i, "position": {"x": point.x, "y": point.y}, "state": "grazing"})
	var preview_snapshot := {"gate_open": false, "settled": 0, "landscape": selected_landscape, "layout": world_layout,
		"players": [{"id": "p1", "position": {"x": -10, "y": 2}, "state": "idle", "connected": true}, {"id": "p2", "position": {"x": -4, "y": 5}, "state": "idle", "connected": true}],
		"dogs": [{"id": "mochi", "position": {"x": -8, "y": 3}, "state": "wander"}, {"id": "maple", "position": {"x": -2.5, "y": 4}, "state": "wander"}], "sheep": sheep}
	if selected_landscape == "cloud":
		preview_snapshot.players[0].position = {"x": -13.0, "y": -1.5}
		preview_snapshot.players[1].position = {"x": -13.0, "y": 1.5}
		preview_snapshot.dogs[0].position = {"x": -11.0, "y": -2.0}
		preview_snapshot.dogs[1].position = {"x": -11.0, "y": 2.0}
	elif selected_landscape == "juniper":
		preview_snapshot.players[0].position = {"x": -14.0, "y": 0.0}
		preview_snapshot.players[1].position = {"x": -14.0, "y": 3.0}
		preview_snapshot.dogs[0].position = {"x": -12.2, "y": -1.0}
		preview_snapshot.dogs[1].position = {"x": -12.2, "y": 2.0}
	elif selected_landscape == "bellflower":
		preview_snapshot.players[0].position = {"x": -10.0, "y": -1.0}
		preview_snapshot.players[1].position = {"x": -10.0, "y": 2.0}
		preview_snapshot.dogs[0].position = {"x": -8.2, "y": -2.0}
		preview_snapshot.dogs[1].position = {"x": -8.2, "y": 1.0}
	elif selected_landscape == "alpine_valley":
		preview_snapshot.type = "snapshot"
		preview_snapshot.code = "MEADOW"
		preview_snapshot.tick = 0
		preview_snapshot.players[0].position = {"x": -48.0, "y": 74.0}
		preview_snapshot.players[1].position = {"x": -45.0, "y": 74.0}
		preview_snapshot.dogs[0].position = {"x": -47.0, "y": 71.8}
		preview_snapshot.dogs[1].position = {"x": -44.0, "y": 71.8}
		for entry: Dictionary in preview_snapshot.players + preview_snapshot.dogs:
			entry.target = entry.position.duplicate()
			entry.seq = 0
		for i in sheep.size():
			sheep[i].position = {"x": -44.7 + i % 3, "y": 62.4 + floorf(i / 3.0) * 1.05}
	_on_snapshot(preview_snapshot)
	status_label.text = "Preview · not connected"

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(capture_path)
	print("SCREENSHOT_SAVED " + capture_path if result == OK else "SCREENSHOT_FAILED")
	get_tree().quit(0 if result == OK else 1)
