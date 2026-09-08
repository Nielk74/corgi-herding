extends PanelContainer
## Small optional practice card; transport and lifecycle gates own freshness.

signal preference_changed

const Tutorial = preload("res://scripts/gentle_tutorial.gd")
const Preferences = preload("res://scripts/guide_preferences.gd")
var tutorial := Tutorial.new()
var preferences := Preferences.new()
var instruction_label: Label
var why_label: Label
var skip_button: Button
var hide_button: Button
var context_key := ""
var _practice := false
var _transport_epoch := -1
var _evidence_epoch := 0
var _requested_active := false
var _active := false
var _foreground := true
var _focused := true
var _binding := false

func _ready() -> void:
	name = "PracticeGuide"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f6f1e3")
	style.set_corner_radius_all(18)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	instruction_label = _label(22, Color("304d40"))
	column.add_child(instruction_label)
	why_label = _label(17, Color("53694f"))
	column.add_child(why_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	skip_button = _button("Skip step", func() -> void: tutorial.skip_current_lesson())
	row.add_child(skip_button)
	hide_button = _button("Hide guide", func() -> void: tutorial.skip())
	row.add_child(hide_button)
	tutorial.lesson_changed.connect(func(_stage: String, _instruction: String, _why: String) -> void: _refresh())
	tutorial.finished.connect(_on_finished)
	_refresh()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size.y = 64
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button

func bind_herd(endpoint: String, code: String, player_id: String, landscape: String) -> void:
	var key: String = Preferences.herd_key(endpoint, code, player_id)
	var practice := landscape == "bellflower" and not key.is_empty()
	if context_key == key and _practice == practice:
		return
	_disarm()
	context_key = key
	_practice = practice
	_binding = true
	tutorial.configure(practice, code, player_id, landscape)
	if practice:
		var choice: Dictionary = preferences.choice(key)
		preferences.remember(key, choice.hidden, choice.completed)
		if choice.hidden or choice.completed:
			tutorial.skip()
	_binding = false
	_reconcile_gate()
	_refresh()
	preference_changed.emit()

func set_gameplay_gate(transport_epoch: int, active: bool) -> void:
	if transport_epoch != _transport_epoch:
		_disarm()
		_transport_epoch = transport_epoch
	_requested_active = active
	_reconcile_gate()

func observe_snapshot(snapshot: Dictionary, transport_epoch: int) -> bool:
	if not _active or transport_epoch != _transport_epoch:
		return false
	return tutorial.observe_snapshot(snapshot, _evidence_epoch)

func record_message(message: Dictionary, transport_epoch: int) -> bool:
	if not _active or transport_epoch != _transport_epoch:
		return false
	return tutorial.record_local_action(message, _evidence_epoch)

func select_dog(id: String) -> void:
	if _active:
		tutorial.select_dog(id, _evidence_epoch)

func can_restart(endpoint: String, code: String, player_id: String) -> bool:
	var key: String = Preferences.herd_key(endpoint, code, player_id)
	if key == context_key and not _practice:
		return false
	return not key.is_empty() and preferences.known(key)

func restart_for(endpoint: String, code: String, player_id: String) -> void:
	var key: String = Preferences.herd_key(endpoint, code, player_id)
	if not can_restart(endpoint, code, player_id):
		return
	preferences.remember(key, false, false)
	if context_key == key and _practice:
		tutorial.restart()
		_refresh()
	preference_changed.emit()

func _on_finished(_reason: String) -> void:
	if not _binding and _practice:
		preferences.remember(context_key, tutorial.stage() != "freeplay", tutorial.stage() == "freeplay")
		preference_changed.emit()
	_refresh()

func _disarm() -> void:
	if _active:
		tutorial.set_connection(_evidence_epoch, false)
	_active = false
	_refresh()

func _reconcile_gate() -> void:
	var active := _practice and _requested_active and _foreground and _focused and _transport_epoch >= 0
	if active and not _active:
		_evidence_epoch += 1
		tutorial.set_connection(_evidence_epoch, true)
		_active = true
	elif not active:
		_disarm()
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	else:
		return
	_reconcile_gate()

func _refresh() -> void:
	if instruction_label == null:
		return
	var value: Dictionary = tutorial.hint()
	visible = _active and value.visible
	instruction_label.text = value.instruction
	why_label.text = value.why
