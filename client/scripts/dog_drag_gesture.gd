class_name DogDragGesture
extends Node3D
## Optional direct Go gesture. Taps retain the ordinary contextual menu.

signal gesture_event(event_name: String, dog_id: String, target: Vector2)

const DRAG_THRESHOLD := 14.0
const EMULATED_DEVICE := -1 # Godot 4.6 InputEvent::DEVICE_ID_EMULATION.
const DOG_COLORS := {"mochi": Color("aa6970"), "maple": Color("729a97")}
var host
var armed := false
var dragging := false
var dog_id := ""
var source := ""
var pointer_index := -1
var start_position := Vector2.ZERO
var pointer_position := Vector2.ZERO
var target := Vector3.INF
var landscape := ""
var herd_code := ""
var foreground := true
var focused := true
var marker: MeshInstance3D
var marker_material: StandardMaterial3D

func _ready() -> void:
	name = "DogDragGesture"
	marker = MeshInstance3D.new()
	marker.name = "DogTargetPreview"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.68
	ring.outer_radius = 0.80
	ring.rings = 20
	ring.ring_segments = 6
	marker.mesh = ring
	marker_material = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	marker.hide()

func configure(game) -> void:
	host = game

func can_interact() -> bool:
	return host != null and foreground and focused and host.hud.visible and not host.welcome.visible \
		and (host.preview_mode or (host.network.connected and not host.network.paused)) \
		and not host.awaiting_authoritative_snapshot and host.actors.has(host.local_id) \
		and is_instance_valid(host.actors[host.local_id].node) \
		and not host.actors[host.local_id].node.is_queued_for_deletion()

func arm(id: String, position: Vector2, pointer_source: String, index: int) -> void:
	cancel()
	if not can_interact() or not DOG_COLORS.has(id) or not _dog_exists(id):
		return
	armed = true
	dog_id = id
	source = pointer_source
	pointer_index = index
	start_position = position
	pointer_position = position
	landscape = host.selected_landscape
	herd_code = str(host.network.credentials.get("code", ""))
	marker_material.albedo_color = DOG_COLORS[id]

func capture(event: InputEvent) -> bool:
	if not armed:
		return false
	if not _valid_session():
		cancel()
		# Do not reinterpret a stale captured pointer as a new world press.
		return event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag
	if event is InputEventMagnifyGesture:
		cancel()
		return false
	if event.device == EMULATED_DEVICE:
		# The native pointer owns this gesture; its synthesized counterpart must
		# not trigger either a second world command or a GUI release underneath.
		return event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag
	if event is InputEventScreenTouch:
		if source != "touch" or event.index != pointer_index:
			if event.pressed:
				cancel()
			return true
		if event.canceled:
			cancel()
		elif not event.pressed:
			_release(event.position)
		return true
	if event is InputEventScreenDrag:
		if source == "touch" and event.index == pointer_index:
			_motion(event.position)
		return true
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			cancel()
			return false
		if source != "mouse":
			return true
		if event.canceled:
			cancel()
		elif not event.pressed:
			_release(event.position)
		return true
	if event is InputEventMouseMotion:
		if source == "mouse":
			if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				cancel()
			else:
				_motion(event.position)
		return true
	return false

func _motion(position: Vector2) -> void:
	pointer_position = position
	if not dragging and position.distance_to(start_position) >= DRAG_THRESHOLD:
		dragging = true
		host._close_controls(false)
		host._hint("", 0.0)
		gesture_event.emit("started", dog_id, Vector2.INF)
	if dragging:
		_refresh_target()

func _release(position: Vector2) -> void:
	# Account for coalesced native motion: release itself may cross the threshold.
	_motion(position)
	if not dragging:
		_clear() # A normal tap leaves the stable four-slot menu open.
		return
	_refresh_target() # Re-pick after any camera movement or received snapshot.
	if not _valid_session() or over_ui(position):
		cancel()
		return
	if not target.is_finite():
		# Explain only an intentional release beyond valid ground. Lifecycle,
		# UI and stale-pointer cancellations remain silent, and ownership is
		# cleared before the temporary feedback can trigger any callbacks.
		cancel()
		host._hint("That spot is beyond the path. Try nearer grass.", 2.0)
		return
	var id := dog_id
	var ground := target
	var destination := Vector2(target.x, target.z)
	_clear() # Clear ownership before callbacks; duplicate release cannot resend.
	host.network.command(id, "go", destination)
	host.meadow.mark_destination(ground) # Request feedback, not a server acknowledgement.
	host._hint("%s, over there." % id.capitalize(), 2.0)
	host._acknowledge(id)
	gesture_event.emit("sent", id, destination)

func _refresh_target() -> void:
	target = Vector3.INF
	marker.hide()
	if not _valid_session() or over_ui(pointer_position):
		return
	var point: Vector3 = host.meadow.ground_at(pointer_position)
	if not point.is_finite() or not host._walkable(Vector2(point.x, point.z)):
		return
	target = point
	host.meadow.place_marker(marker, point)
	marker.show()

func over_ui(position: Vector2) -> bool:
	if host == null:
		return false
	# Native touches must not fall through a Button after its emulated mouse
	# event has already been handled. Ignore only genuinely transparent controls.
	for control in host.ui.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and control.get_global_rect().has_point(position):
			return true
	return false

func _dog_exists(id: String) -> bool:
	return host.actors.has(id) and is_instance_valid(host.actors[id].node) \
		and not host.actors[id].node.is_queued_for_deletion()

func _valid_session() -> bool:
	return armed and can_interact() and _dog_exists(dog_id) \
		and host.selected_landscape == landscape \
		and str(host.network.credentials.get("code", "")) == herd_code

func cancel() -> void:
	if not armed:
		return
	var id := dog_id
	_clear()
	gesture_event.emit("cancelled", id, Vector2.INF)

func _clear() -> void:
	armed = false
	dragging = false
	dog_id = ""
	source = ""
	pointer_index = -1
	target = Vector3.INF
	marker.hide()

func _process(_delta: float) -> void:
	if armed:
		if not _valid_session():
			cancel()
		elif dragging:
			_refresh_target()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		foreground = false
		cancel()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		foreground = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		cancel()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
