class_name MeadowDiorama
extends Node3D
## Original procedural geometry. V7 optionally uses attributed CC0 surface maps.

const GRASS := Color("96ad78")
const DARK := Color("293f36")
const CREAM := Color("fff0d5")
const TerrainProfile = preload("res://scripts/terrain_profile.gd")
const SceneryBatch = preload("res://scripts/static_scenery_batch.gd")
const CloudNavigation = preload("res://scripts/cloud_navigation.gd")
const ShoreNavigation = preload("res://scripts/shore_navigation.gd")
const ShoreScenery = preload("res://scripts/juniper_scenery.gd")
const CommonsNavigation = preload("res://scripts/commons_navigation.gd")
const CommonsScenery = preload("res://scripts/bellflower_scenery.gd")
const RegionNavigationScript = preload("res://scripts/region_navigation.gd")
const RegionPresentation = preload("res://scripts/region_presentation.gd")
const RegionRecipe = preload("res://scripts/landscape_recipe.gd")
const RegionSceneBuilder = preload("res://scripts/landscape_scene_builder.gd")
var camera: Camera3D
var gate: Node3D
var bridge: Node3D
var destination: Node3D
var selection: Node3D
var preview: Node3D
var water: MeshInstance3D
var materials: Dictionary = {}
var elapsed := 0.0
var gate_open := false
var marker_age := 100.0
var zoom := 1.0
var landscape := ""
var terrain: Node3D
var world_environment: Environment
var vertex_material: StandardMaterial3D
var camera_focus := Vector3(-4.0, 1.8, -6.0)
var desired_focus := Vector3(-4.0, 1.8, -6.0)
const CAMERA_OFFSET := Vector3(8, 28, 38)
const FOLLOW_QUIET_HALF_WIDTH := 3.0
var player_follow_initialized := false
var following_walk := false
const TERRAIN_HORIZON_DEPTH := 22.0
var profile: ValleyTerrainProfile
var layout: Dictionary = {"version": 1, "bridge_y": 0.0, "gate_y": 0.0}
var bridge_y := 0.0
var gate_y := 0.0
var forage_center := Vector2(-7, -5)
var forage_radius := 2.2
var rock_center := Vector2.ZERO
var rock_radius := 3.4
var ridge: Dictionary = {}
var ridge_spine: Array[Vector2] = []
var ridge_half_width := 3.6
var ridge_shelves: Array = []
var rest_center := Vector2(11, 4)
var rest_radius := 4.6
var shore: Dictionary = {}
var shore_path: Array[Vector2] = []
var shore_half_width := 3.6
var shore_clearings: Array = []
var commons: Dictionary = {}
var region_profile: RefCounted
var region_navigation: RefCounted
var region_presentation: RefCounted
var _legacy_camera_state: Dictionary = {}
var _legacy_environment: Dictionary = {}
var _lighting_rig: Node3D
var _legacy_shafts: Dictionary = {}

func _ready() -> void:
	_build_light()
	set_landscape("alpine")
	_build_camera()
	destination = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.42)
	destination.visible = false
	selection = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.76)
	selection.visible = false
	_build_preview()

func set_landscape(id: String, incoming_layout: Dictionary = {}) -> void:
	if id == "alpine_valley":
		_set_region_landscape(incoming_layout)
		return
	if landscape == "alpine_valley":
		_leave_region_landscape()
	var next := id if id in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper", "bellflower"] else "alpine"
	var expected_version := 6 if next == "bellflower" else (5 if next == "juniper" else (4 if next == "cloud" else (3 if next == "oasis" else (2 if next == "orchard" else 1))))
	var next_layout := {"version": int(incoming_layout.get("version", expected_version)),
		"bridge_y": float(incoming_layout.get("bridge_y", 3.0 if next == "orchard" else (-4.0 if next == "larch" else 0.0))),
		"gate_y": float(incoming_layout.get("gate_y", 2.0 if next == "orchard" else (4.0 if next == "larch" else 0.0)))}
	if next_layout.version != expected_version:
		push_error("Unsupported landscape layout version")
		return
	if next == "orchard":
		var forage: Dictionary = incoming_layout.get("forage", {})
		var center: Dictionary = forage.get("center", {})
		next_layout["forage"] = {"id": String(forage.get("id", "windfall")),
			"center": {"x": float(center.get("x", -7.0)), "y": float(center.get("y", -5.0))},
			"radius": float(forage.get("radius", 2.2))}
	elif next == "oasis":
		var rock: Dictionary = incoming_layout.get("rock_pass", {})
		var center: Dictionary = rock.get("center", {})
		next_layout["rock_pass"] = {"center": {"x": float(center.get("x", 0.0)), "y": float(center.get("y", 0.0))},
			"radius": float(rock.get("radius", 3.4))}
	elif next == "cloud":
		next_layout["ridge"] = incoming_layout.get("ridge", CloudNavigation.default_ridge()).duplicate(true)
	elif next == "juniper":
		next_layout["shore"] = incoming_layout.get("shore", ShoreNavigation.default_shore()).duplicate(true)
	elif next == "bellflower":
		next_layout["commons"] = incoming_layout.get("commons", CommonsNavigation.default_commons()).duplicate(true)
	if next == landscape and next_layout == layout and is_instance_valid(terrain):
		return
	var previous_landscape := landscape
	landscape = next
	layout = next_layout
	bridge_y = next_layout.bridge_y
	gate_y = next_layout.gate_y
	if next == "orchard":
		forage_center = Vector2(next_layout.forage.center.x, next_layout.forage.center.y)
		forage_radius = next_layout.forage.radius
	elif next == "oasis":
		rock_center = Vector2(next_layout.rock_pass.center.x, next_layout.rock_pass.center.y)
		rock_radius = next_layout.rock_pass.radius
	elif next == "cloud":
		ridge = next_layout.ridge.duplicate(true)
		ridge_spine.clear()
		for point: Dictionary in ridge.spine:
			ridge_spine.append(Vector2(float(point.x), float(point.y)))
		ridge_half_width = float(ridge.half_width)
		ridge_shelves = ridge.shelves.duplicate(true)
		rest_center = Vector2(float(ridge.rest.center.x), float(ridge.rest.center.y))
		rest_radius = float(ridge.rest.radius)
	elif next == "juniper":
		shore = next_layout.shore.duplicate(true)
		shore_path.clear()
		for point: Dictionary in shore.path:
			shore_path.append(Vector2(float(point.x), float(point.y)))
		shore_half_width = float(shore.half_width)
		shore_clearings = shore.clearings.duplicate(true)
	elif next == "bellflower":
		commons = next_layout.commons.duplicate(true)
	profile = TerrainProfile.new(landscape, layout)
	if is_instance_valid(terrain):
		terrain.hide()
		terrain.queue_free()
	gate = null
	bridge = null
	water = null
	terrain = Node3D.new()
	terrain.name = "Landscape_" + landscape
	add_child(terrain)
	if world_environment != null:
		world_environment.background_color = _color("bdcfd0", "d8c1a1", "c4ceca", "cbd8d1", "d8c7ac")
		if next in ["cloud", "juniper", "bellflower"]:
			world_environment.background_color = Color("a9cbdc")
	_build_land()
	_build_backdrop()
	_build_boundaries()
	if landscape not in ["oasis", "cloud", "juniper", "bellflower"]:
		_build_bridge()
		_build_fence()
	_build_details()
	# Scenery is immutable after construction; the animated gate stays separate.
	SceneryBatch.merge(terrain, [gate])
	if is_instance_valid(preview):
		for i in preview.get_child_count():
			var actor := preview.get_child(i) as Node3D
			if landscape == "bellflower":
				actor.position.x = -6.7 + i % 3 if i < 10 else -8.2
				actor.position.z = -0.4 + floorf(i / 3.0) * 1.05 if i < 10 else (-2.0 if i == 10 else 1.0)
			elif landscape == "juniper":
				actor.position.x = -10.7 + i % 3 if i < 10 else -12.2
				actor.position.z = -0.4 + floorf(i / 3.0) * 1.05 if i < 10 else (-1.0 if i == 10 else 2.0)
			elif previous_landscape in ["juniper", "bellflower", "alpine_valley"]:
				# Return the decorative welcome flock to its original arrangement
				# when leaving the new shore; live actors are never repositioned here.
				actor.position.x = -6.5 + sin(i * 2.3) * 2.9 if i < 10 else -10.0 + (i - 10) * 3.0
				actor.position.z = -1.6 + cos(i * 1.6) * 2.7 if i < 10 else 3.3
			actor.position.y = surface_height(actor.position.x, actor.position.z) + 0.03

func _same_region(a: Dictionary, b: Dictionary) -> bool:
	# Compare numeric fields, not int-vs-float dictionary storage or JSON ordering.
	if a.recipe_id != b.recipe_id or a.anchors.size() != b.anchors.size() or a.corridors.size() != b.corridors.size() or a.clearings.size() != b.clearings.size():
		return false
	for side in ["min", "max"]:
		if float(a.bounds[side].x) != float(b.bounds[side].x) or float(a.bounds[side].y) != float(b.bounds[side].y):
			return false
	for i in a.anchors.size():
		if float(a.anchors[i].x) != float(b.anchors[i].x) or float(a.anchors[i].y) != float(b.anchors[i].y):
			return false
	for i in a.corridors.size():
		for key in ["a", "b", "half_width"]:
			if float(a.corridors[i][key]) != float(b.corridors[i][key]):
				return false
	for i in a.clearings.size():
		if float(a.clearings[i].center.x) != float(b.clearings[i].center.x) or float(a.clearings[i].center.y) != float(b.clearings[i].center.y) or float(a.clearings[i].radius) != float(b.clearings[i].radius):
			return false
	return true

func _set_region_landscape(incoming: Dictionary) -> void:
	var canonical := RegionNavigationScript.default_region()
	var wire: Variant = incoming.get("region", canonical)
	if not RegionNavigationScript.validate_geometry(wire).is_empty() or not _same_region(wire, canonical):
		return
	if incoming.get("version", 7) != 7 or incoming.get("bridge_y", 0.0) != 0 or incoming.get("gate_y", 0.0) != 0:
		return
	if landscape == "alpine_valley" and is_instance_valid(terrain):
		return
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/long_valley.recipe.json"))
	if not RegionRecipe.validate(recipe).is_empty():
		return
	_save_legacy_presentation()
	landscape = "alpine_valley"
	layout = {"version": 7, "bridge_y": 0.0, "gate_y": 0.0, "region": canonical.duplicate(true)}
	bridge_y = 0
	gate_y = 0
	gate_open = false
	region_profile = RegionRecipe.new(recipe)
	region_navigation = RegionNavigationScript.new(canonical)
	if is_instance_valid(terrain):
		terrain.hide()
		terrain.queue_free()
	gate = null
	bridge = null
	water = null
	terrain = RegionSceneBuilder.load_or_build(region_profile)
	terrain.name = "Landscape_alpine_valley"
	add_child(terrain)
	region_presentation = RegionPresentation.new(terrain, region_profile, region_navigation)
	# Welcome framing is provisional. The first live idle herder still receives
	# its own one-time placement, including on reconnect into a fresh scene.
	region_presentation.follow(Vector3(-48, surface_height(-48, 74), 74), false)
	region_presentation.reset()
	_apply_region_environment()
	if is_instance_valid(preview):
		for i in preview.get_child_count():
			var actor := preview.get_child(i) as Node3D
			actor.position.x = -44.7 + i % 3 if i < 10 else (-47 if i == 10 else -44)
			actor.position.z = 62.4 + floorf(i / 3.0) * 1.05 if i < 10 else 71.8
			actor.position.y = surface_height(actor.position.x, actor.position.z) + 0.03
	if is_instance_valid(camera):
		region_presentation.apply_camera(camera, zoom)
		camera_focus = region_presentation.camera_focus
		desired_focus = region_presentation.desired_focus

func _save_legacy_presentation() -> void:
	if is_instance_valid(camera):
		for property in ["projection", "keep_aspect", "fov", "near", "far", "size"]:
			_legacy_camera_state[property] = camera.get(property)
		_legacy_camera_state["focus"] = camera_focus
		_legacy_camera_state["desired"] = desired_focus
		_legacy_camera_state["initialized"] = player_follow_initialized
		_legacy_camera_state["walking"] = following_walk
		_legacy_camera_state["zoom"] = zoom
	if world_environment != null:
		for property in ["sky", "background_mode", "ambient_light_source", "ambient_light_sky_contribution", "fog_depth_begin", "fog_depth_end", "fog_depth_curve", "fog_light_color"]:
			_legacy_environment[property] = world_environment.get(property)
	if is_instance_valid(_lighting_rig):
		for child in _lighting_rig.get_children():
			if child is MeshInstance3D:
				_legacy_shafts[child] = child.visible
				child.visible = false

func _apply_region_environment() -> void:
	if world_environment == null:
		return
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("648fac")
	sky_material.sky_horizon_color = Color("c2d1d2")
	sky_material.ground_horizon_color = Color("c2d1d2")
	sky_material.ground_bottom_color = Color("778979")
	var sky := Sky.new()
	sky.sky_material = sky_material
	world_environment.sky = sky
	world_environment.background_mode = Environment.BG_SKY
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_environment.ambient_light_sky_contribution = 0.65
	world_environment.fog_depth_begin = 105.0
	world_environment.fog_depth_end = 480.0
	world_environment.fog_depth_curve = 1.25
	world_environment.fog_light_color = Color("a6bac5")

func _leave_region_landscape() -> void:
	region_presentation = null
	region_navigation = null
	region_profile = null
	for property in _legacy_environment:
		world_environment.set(property, _legacy_environment[property])
	_legacy_environment.clear()
	for shaft in _legacy_shafts:
		if is_instance_valid(shaft):
			shaft.visible = _legacy_shafts[shaft]
	_legacy_shafts.clear()
	if not _legacy_camera_state.is_empty():
		for property in ["projection", "keep_aspect", "fov", "near", "far", "size"]:
			camera.set(property, _legacy_camera_state[property])
		camera_focus = _legacy_camera_state.focus
		desired_focus = _legacy_camera_state.desired
		player_follow_initialized = _legacy_camera_state.initialized
		following_walk = _legacy_camera_state.walking
		zoom = _legacy_camera_state.zoom
		camera.position = camera_focus + CAMERA_OFFSET
		camera.look_at(camera_focus)
	_legacy_camera_state.clear()

func _color(alpine: String, cactus: String, larch := "", orchard := "", oasis := "") -> Color:
	if landscape == "oasis":
		return Color(oasis if not oasis.is_empty() else cactus)
	if landscape == "orchard" and not orchard.is_empty():
		return Color(orchard)
	return Color(cactus if landscape == "cactus" else (larch if landscape == "larch" and not larch.is_empty() else alpine))

func material(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := color.to_html() + str(unshaded)
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

func mesh(parent: Node3D, shape: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material(color)
	instance.position = pos
	parent.add_child(instance)
	return instance

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, pos, color)

func ball(parent: Node3D, pos: Vector3, scale_value: Vector3, color: Color) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 12
	shape.rings = 6
	var node := mesh(parent, shape, pos, color)
	node.scale = scale_value
	return node

func cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, height: float, color: Color, sides := 10) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = sides
	return mesh(parent, shape, pos, color)

func _build_light() -> void:
	var rig = load("res://scripts/valley_lighting.gd").new()
	add_child(rig)
	_lighting_rig = rig
	world_environment = rig.environment

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = camera_focus + CAMERA_OFFSET
	add_child(camera)
	camera.look_at(camera_focus)
	camera.current = true
	camera.near = 0.1
	camera.far = 150.0
	fit_camera()
	get_viewport().size_changed.connect(fit_camera)

func fit_camera() -> void:
	if landscape == "alpine_valley" and region_presentation != null:
		region_presentation.apply_camera(camera, zoom)
		return
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	# Preserve animal readability on phones; gentle horizontal following reveals the valley.
	camera.size = maxf(32.0, 25.5 / aspect) * zoom

func reset_player_follow() -> void:
	if landscape == "alpine_valley" and region_presentation != null:
		region_presentation.reset()
		return
	# A new herd gets one initial framing, not motion inherited from its predecessor.
	player_follow_initialized = false
	stop_player_follow()

func stop_player_follow() -> void:
	if landscape == "alpine_valley" and region_presentation != null:
		region_presentation.stop()
		return
	following_walk = false
	desired_focus = camera_focus

func follow_player(pos: Vector3, walking: bool = true) -> void:
	if landscape == "alpine_valley" and region_presentation != null:
		region_presentation.follow(pos, walking)
		return
	if not pos.is_finite():
		return
	if not player_follow_initialized:
		# Place an initially idle herder before displaying the first gameplay frame.
		# Ordinary idle snapshots/reconciliation must never trigger this again.
		player_follow_initialized = true
		camera_focus.x = clampf(pos.x, -6.0, 6.0)
		desired_focus = camera_focus
	if not walking:
		# No slow camera drift while the pair is resting or petting a dog.
		stop_player_follow()
		return
	# Short walks inside the quiet center leave the view alone. Once a longer
	# walk needs a pan, keep following through its reversal until the herder stops;
	# otherwise the old wide deadzone strands the camera on the previous side.
	if absf(pos.x - camera_focus.x) > FOLLOW_QUIET_HALF_WIDTH:
		following_walk = true
	if following_walk:
		desired_focus.x = clampf(pos.x, -6.0, 6.0)

func _build_land() -> void:
	if landscape == "bellflower":
		CommonsScenery.build_land(self)
		return
	if landscape == "juniper":
		ShoreScenery.build_land(self)
		return
	if landscape == "cloud":
		_build_cloud_land()
		return
	if landscape == "oasis":
		_build_oasis_land()
		return
	# One continuous sampled heightfield: hills are places the herders walk over.
	for side in [-1, 1]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ix in range(44):
			for iz in range(85):
				var x0: float = side * (1.5 + ix)
				var x1: float = side * (2.5 + ix)
				var z0 := -40.0 + iz
				var z1 := z0 + 1.0
				if landscape == "orchard" and (z0 >= 12.0 or z1 <= -12.0):
					# Beyond the immutable play area, the brook meanders through hills.
					# Fit the mesh edge to that curve instead of exposing a stepped grid.
					var columns := 2 if ix < 4 else 1
					# Every column shares the same Z vertices. A finer shore beside a
					# one-unit outer edge creates visible curved T-junction cracks.
					for sz in range(2):
						var from_z := z0 + sz * 0.5
						var to_z := from_z + 0.5
						if columns == 2 and (from_z == 12.0 or to_z == -12.0):
							var inner_z := from_z if from_z == 12.0 else to_z
							var outer_z := to_z if from_z == 12.0 else from_z
							_orchard_transition_strip(surface, side, ix, inner_z, outer_z)
							continue
						for sx in range(columns):
							_orchard_bank_quad(surface, side, ix + sx / float(columns), ix + (sx + 1) / float(columns), from_z, to_z)
					continue
				var a := Vector3(x0, profile.node_height(x0, z0), z0)
				var b := Vector3(x1, profile.node_height(x1, z0), z0)
				var c := Vector3(x1, profile.node_height(x1, z1), z1)
				var d := Vector3(x0, profile.node_height(x0, z1), z1)
				_ground_triangle(surface, a, b, c, Color.WHITE, true)
				_ground_triangle(surface, a, c, d, Color.WHITE, true)
		_finish_surface(surface, "ValleyGround%d" % (0 if side < 0 else 1), true)
	_build_river()
	if landscape == "orchard":
		_trail([Vector2(-30, -2), Vector2(-22, 0), Vector2(-16, 1), Vector2(-11, 1.4), Vector2(-7, 2.3), Vector2(-3.6, bridge_y), Vector2(-1.7, bridge_y)], 0.95)
		_trail([Vector2(1.7, bridge_y), Vector2(3.8, 2.8), Vector2(6, gate_y), Vector2(10, 2.7), Vector2(14, 4.3), Vector2(23, 2.5), Vector2(33, -4)], 0.95)
	elif landscape == "larch":
		_trail([Vector2(-29, -8), Vector2(-21, -3), Vector2(-15, 0), Vector2(-11, -0.5), Vector2(-7, bridge_y + 1.0), Vector2(-3.8, bridge_y), Vector2(-1.7, bridge_y)], 1.0)
		_trail([Vector2(1.7, bridge_y), Vector2(3.2, bridge_y + 0.7), Vector2(3.7, 0), Vector2(4.3, gate_y - 1.2), Vector2(6, gate_y), Vector2(9, gate_y + 0.8), Vector2(13, 6.2), Vector2(20, 7), Vector2(30, 4)], 0.95)
	else:
		_trail([Vector2(-31, -13), Vector2(-24, -7), Vector2(-18, -2), Vector2(-13, -1), Vector2(-8, bridge_y + 0.7), Vector2(-4, bridge_y + 0.3), Vector2(-1.7, bridge_y)], 1.1)
		_trail([Vector2(1.7, bridge_y), Vector2(6, gate_y), Vector2(10, gate_y + 0.8), Vector2(14, gate_y + 2), Vector2(19, 4), Vector2(27, 3), Vector2(35, -2)], 1.05)

func _build_cloud_land() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distant_surface := SurfaceTool.new()
	distant_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TerrainProfile.CLOUD_GRID_STEP
	# One uniform grid continues through every shelf, flank, distant hillside and
	# snowy crag. There are no shoreline walls, overlapping field plates or seams
	# between coarse and fine terrain. The source also grounds feet and touch rays.
	for ix in range(160):
		for iz in range(168):
			var x := -60.0 + ix * step
			var z := -60.0 + iz * step
			var a := Vector3(x, profile.node_height(x, z), z)
			var b := Vector3(x + step, profile.node_height(x + step, z), z)
			var c := Vector3(x + step, profile.node_height(x + step, z + step), z + step)
			var d := Vector3(x, profile.node_height(x, z + step), z + step)
			var depth := -(x + step * 0.5) * 0.2063 - (z + step * 0.5) * 0.9785
			var target := distant_surface if depth > 15.0 else surface
			_ground_triangle(target, a, b, c, Color.WHITE, true)
			_ground_triangle(target, a, c, d, Color.WHITE, true)
	var ground := _finish_surface(surface, "ValleyGroundCloud", true)
	var combined_mesh := ground.mesh as ArrayMesh
	distant_surface.commit(combined_mesh)
	# One mesh keeps every shared edge exact. Only far scenery stops receiving
	# noisy long-distance shadow maps; its normals still receive ordinary sunlight.
	ground.material_override = null
	combined_mesh.surface_set_material(0, vertex_material)
	var distant_material := vertex_material.duplicate() as StandardMaterial3D
	distant_material.disable_receive_shadows = true
	combined_mesh.surface_set_material(1, distant_material)

func _cloud_ground_color(point: Vector3, normal: Vector3) -> Color:
	var depth := -point.x * 0.2063 - point.z * 0.9785
	var u := point.x * 0.9785 - point.z * 0.2063
	var color := Color("8fa96b")
	var stone := smoothstep(0.075, 0.36, 1.0 - normal.y)
	color = color.lerp(Color("68776c"), stone * 0.90)
	color = color.lerp(Color("789780"), (1.0 - smoothstep(-3.0, 0.0, point.y)) * 0.38)
	color = color.lightened(sin(point.x * 0.35 + sin(point.z * 0.2) * 1.1) * 0.025)
	if depth < 12.0:
		var outside := maxf(-profile.cloud_clearance(point.x, point.z), 0.0)
		var slabs := exp(-pow((point.x + 8.0) / 8.0, 2) - pow((point.z - 13.0) / 9.0, 2))
		slabs += exp(-pow((point.x - 12.0) / 7.0, 2) - pow((point.z - 17.0) / 8.0, 2)) * 0.80
		var broken := 0.56 + 0.44 * sin(point.x * 0.72 + point.z * 0.39 + sin(point.z * 0.21))
		var exposure := slabs * smoothstep(1.15, 3.2, outside) * smoothstep(0.20, 0.76, broken)
		color = color.lerp(Color("718078"), exposure * 0.84)
		color = color.lightened(sin(point.x * 0.83 - point.z * 0.58) * exposure * 0.018)
	var country := smoothstep(12.0, 24.0, depth)
	color = color.lerp(Color("91a58e").lerp(Color("738a80"), stone), country * 0.74)
	if depth > 16.0 and depth < 26.0 and profile.cloud_lake_metric(point.x, point.z) < 2.8:
		var shore := 1.0 - smoothstep(0.04, 0.48, absf(point.y - TerrainProfile.CLOUD_LAKE_LEVEL))
		color = color.lerp(Color("a4a698"), shore * 0.80)
	var mountain_front := profile.cloud_mountain_front(u)
	if depth > mountain_front:
		var mountain := Color("687f8c").lerp(Color("97adb8"), smoothstep(-4.0, 4.0, point.y))
		var gully := 0.70 + 0.30 * sin(u * 0.77 + depth * 0.63)
		var snow := smoothstep(2.2 + gully * 0.4, 4.8 + gully * 0.5, point.y)
		mountain = mountain.lerp(Color("e3edf0"), snow * 0.96)
		mountain = mountain.lerp(Color("b6ced9"), smoothstep(37.0, 46.0, depth) * 0.52)
		color = color.lerp(mountain, smoothstep(mountain_front, mountain_front + 5.0, depth))
	return color

func _build_cloud_backdrop() -> void:
	# Open water belongs to the lower valley beyond the ridge, not to a repeated
	# playable crossing. Its polygon boundary is hidden beneath the sampled banks.
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	var center := across * 5.0 + away * 21.0
	center.y = TerrainProfile.CLOUD_LAKE_LEVEL
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(8):
		for i in range(80):
			var angle0 := i * TAU / 80.0
			var angle1 := (i + 1) * TAU / 80.0
			var r0 := ring / 8.0
			var r1 := (ring + 1) / 8.0
			var a := center + (across * cos(angle0) * 9.5 + away * sin(angle0) * 3.7) * r0
			var b := center + (across * cos(angle0) * 9.5 + away * sin(angle0) * 3.7) * r1
			var c := center + (across * cos(angle1) * 9.5 + away * sin(angle1) * 3.7) * r1
			var d := center + (across * cos(angle1) * 9.5 + away * sin(angle1) * 3.7) * r0
			_cloud_water_triangle(lake, a, b, c)
			if ring > 0:
				_cloud_water_triangle(lake, a, c, d)
	water = _finish_surface(lake, "CloudDistantTarn")

func _cloud_water_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (c - a).cross(b - a).y < 0:
		var previous_b := b
		b = c
		c = previous_b
	for point in [a, b, c]:
		var water_depth := maxf(TerrainProfile.CLOUD_LAKE_LEVEL - profile.sample(point.x, point.z), 0.0)
		var color := Color("9ebbb3").lerp(Color("527f94"), smoothstep(0.015, 0.46, water_depth))
		color = color.lightened(sin(point.x * 0.44 + point.z * 0.81) * 0.022)
		surface.set_color(color)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(point)

func _build_cloud_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 684231
	# Each small grove lives downhill from the actual corridor, separated by air
	# and landforms. No crown belt encloses the playable space.
	for p in [Vector3(-18, 0, -7), Vector3(-20.3, 0, -8.5), Vector3(-17.8, 0, -10.5), Vector3(17.5, 0, -3), Vector3(19.5, 0, -4.9), Vector3(21, 0, -2.5)]:
		_pine(p, rng.randf_range(0.60, 0.90))
	for p in [Vector3(-14.5, 0, 7.4), Vector3(-10.5, 0, 8.0), Vector3(-7, 0, 6.5), Vector3(1.5, 0, -10.8), Vector3(9.8, 0, -4.8), Vector3(16.9, 0, 8.8)]:
		if profile.cloud_clearance(p.x, p.z) > -1.25:
			continue
		_rock(p + Vector3(0, 0.21, 0), Vector3(rng.randf_range(1.2, 1.8), 0.70, rng.randf_range(0.95, 1.35)))
		_shrub(p + Vector3(0.7, 0.04, 0.4), 0.45)
	for p in [Vector3(-10.0, 0, 10.6), Vector3(-6.2, 0, 13.4), Vector3(13.1, 0, 12.5), Vector3(7.1, 0, 17.2)]:
		if profile.cloud_clearance(p.x, p.z) < -2.0:
			_cloud_outcrop(p, Vector2(1.9, 1.1), 0.45)
			_cloud_outcrop(p + Vector3(1.9, 0, 0.9), Vector2(0.9, 0.7), 0.28)
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	# Unequal small woodland pockets follow the distant slope and shore. Their
	# tiny scale is a distance cue; there is no straight row of full-sized trees.
	for coordinate: Vector2 in [Vector2(-10.5, 17.8), Vector2(-12.0, 18.4), Vector2(-9.2, 18.9), Vector2(-11.2, 20.0), Vector2(-2.5, 24.0), Vector2(-1.4, 25.1), Vector2(-3.8, 25.3), Vector2(13.1, 20.4), Vector2(15.1, 21.5), Vector2(13.8, 23.0)]:
		var p := across * coordinate.x + away * coordinate.y
		if profile.sample(p.x, p.z) > TerrainProfile.CLOUD_LAKE_LEVEL + 0.45:
			_pine(p, rng.randf_range(0.30, 0.48))
	for coordinate: Vector2 in [Vector2(2.2, 19.2), Vector2(1.2, 19.5), Vector2(9.4, 21.6)]:
		var p := across * coordinate.x + away * coordinate.y
		if profile.sample(p.x, p.z) > TerrainProfile.CLOUD_LAKE_LEVEL + 0.12:
			_cloud_outcrop(p, Vector2(0.6, 0.4), 0.18)
	var blooms := SurfaceTool.new()
	blooms.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(145):
		var p := Vector2(rng.randf_range(-16.5, 16.5), rng.randf_range(-10.5, 10.5))
		if not CloudNavigation.contains(p, ridge):
			continue
		var ground := _grounded(Vector3(p.x, 0.025, p.y))
		var scale_value := rng.randf_range(0.08, 0.15)
		var tint := Color("738955")
		_triangle(blooms, ground + Vector3(-scale_value, 0, 0), ground + Vector3(scale_value, 0, 0), ground + Vector3(0, scale_value * 1.8, 0.04), tint)
		if i % 3 == 0:
			var flower := ground + Vector3(0, scale_value * 1.7, 0)
			var petals := Color("d5c38c") if i % 2 else Color("c5b8d2")
			_triangle(blooms, flower + Vector3(-0.075, 0, 0), flower + Vector3(0.075, 0, 0), flower + Vector3(0, 0.075, 0), petals)
	_finish_surface(blooms, "CloudAlpineFlowers")
	# A quiet rest shelf, not a destination marker or an interaction hub.
	var blanket := rest_center + Vector2(0.5, 1.2)
	_draped_patch(blanket, Vector2(2.7, 1.6), Color("b5a991"), 0.035)
	for x in [blanket.x - 0.8, blanket.x + 0.8]:
		_draped_patch(Vector2(x, blanket.y), Vector2(0.11, 1.6), Color("e5dfc7"), 0.05)
	var basket := cylinder(terrain, _grounded(Vector3(blanket.x + 1.5, 0.22, blanket.y - 0.3)), 0.23, 0.20, 0.44, Color("a58c64"), 8)
	basket.rotation.z = 0.08

func _cloud_outcrop(pos: Vector3, extent: Vector2, rise: float) -> void:
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foot: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in range(7):
		var angle := i * TAU / 7.0 + pos.x * 0.17
		var radius := 0.85 + sin(i * 2.3) * 0.15
		var point := pos + Vector3(cos(angle) * extent.x, 0, sin(angle) * extent.y) * radius
		foot.append(_grounded(point + Vector3(0, 0.015, 0)))
		point = point.lerp(pos, 0.25)
		top.append(_grounded(point + Vector3(0, rise * (0.7 + 0.25 * sin(i * 1.8)), 0)))
	var peak := _grounded(pos + Vector3(extent.x * 0.12, rise, -extent.y * 0.15))
	for i in range(7):
		var next := (i + 1) % 7
		_triangle(rock, foot[i], foot[next], top[next], Color("64736d"))
		_triangle(rock, foot[i], top[next], top[i], Color("748078"))
		_triangle(rock, top[i], top[next], peak, Color("91a08c").darkened((i % 3) * 0.035))
	_finish_surface(rock, "CloudBedrock", true)

func _build_oasis_land() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in range(120):
		for iz in range(105):
			var x := -60.0 + ix
			var z := -40.0 + iz
			var a := Vector3(x, profile.node_height(x, z), z)
			var b := Vector3(x + 1.0, profile.node_height(x + 1.0, z), z)
			var c := Vector3(x + 1.0, profile.node_height(x + 1.0, z + 1.0), z + 1.0)
			var d := Vector3(x, profile.node_height(x, z + 1.0), z + 1.0)
			_ground_triangle(surface, a, b, c, Color.WHITE, true)
			_ground_triangle(surface, a, c, d, Color.WHITE, true)
	_finish_surface(surface, "ValleyGroundOasis", true)
	_build_oasis_rock()

func _build_oasis_rock() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Keep the collision envelope fully grounded, but never draw it as a disc:
	# a dense low surface follows the soil, with a broken inner stone shoulder
	# fading to the surrounding ground's exact palette and normals at its edge.
	for ring in range(16):
		for segment in range(64):
			var angle0 := segment * TAU / 64.0
			var angle1 := (segment + 1) * TAU / 64.0
			var r0 := rock_radius * ring / 16.0
			var r1 := rock_radius * (ring + 1) / 16.0
			var a := Vector2(cos(angle0), sin(angle0)) * r0 + rock_center
			var b := Vector2(cos(angle0), sin(angle0)) * r1 + rock_center
			var c := Vector2(cos(angle1), sin(angle1)) * r1 + rock_center
			var d := Vector2(cos(angle1), sin(angle1)) * r0 + rock_center
			_oasis_apron_triangle(surface, a, b, c)
			if ring > 0:
				_oasis_apron_triangle(surface, a, c, d)
	_oasis_rock_lobe(surface,
		[Vector2(-2.7, -0.7), Vector2(-2.1, -1.9), Vector2(-0.8, -2.35), Vector2(0.5, -1.4), Vector2(1.45, -0.1), Vector2(0.6, 0.72), Vector2(-1.05, 0.45)],
		[0.75, 1.03, 1.30, 1.10, 1.40, 1.57, 1.35], Color("af8a62"))
	_oasis_rock_lobe(surface,
		[Vector2(-0.30, 1.02), Vector2(1.20, 0.93), Vector2(2.50, 0.65), Vector2(2.43, 1.65), Vector2(1.30, 2.79), Vector2(0.15, 2.65), Vector2(-0.60, 1.80)],
		[0.86, 1.15, 0.80, 1.06, 0.78, 1.05, 0.75], Color("c1a077"))
	_oasis_rock_lobe(surface,
		[Vector2(-2.85, 0.62), Vector2(-1.85, 0.53), Vector2(-1.08, 1.23), Vector2(-1.20, 2.52), Vector2(-2.12, 2.34), Vector2(-2.85, 1.48)],
		[0.47, 0.75, 0.90, 0.75, 0.95, 0.55], Color("a17a55"))
	_finish_surface(surface, "RockPassOutcrop", true)

func _oasis_apron_triangle(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	# Positive X/Z area already gives Godot's upward clockwise front face:
	# (c3-a3).cross(b3-a3).y > 0. Keep it aligned with the stored ground normals.
	if (b - a).cross(c - a) < 0:
		var previous_b := b
		b = c
		c = previous_b
	for point in [a, b, c]:
		var local: Vector2 = point - rock_center
		var angle := atan2(local.y, local.x)
		var broken_edge := 2.16 + sin(angle * 3.0 + 0.4) * 0.30 + sin(angle * 5.0 - 1.0) * 0.22
		var stone := 1.0 - smoothstep(broken_edge - 0.55, broken_edge + 0.60, local.length())
		var ground := Vector3(point.x, profile.sample(point.x, point.y), point.y)
		var normal := profile.normal_at(point.x, point.y)
		var color := _oasis_ground_color(ground, normal)
		# The low connecting stone is visible between the three main lobes, so
		# those breaks read as crevices in one outcrop rather than walkable gaps.
		var exposed := Color("a78962").darkened(0.055 * pow(sin(local.x * 2.0 - local.y), 2))
		color = color.lerp(exposed, stone * 0.92)
		ground.y += 0.004 + stone * (0.19 + 0.07 * sin(local.x * 1.3 + local.y * 1.8))
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(ground)

func _oasis_rock_lobe(surface: SurfaceTool, outline: Array, heights: Array, color: Color) -> void:
	var centroid := Vector2.ZERO
	for point: Vector2 in outline:
		centroid += point
	centroid /= outline.size()
	var top: Array[Vector3] = []
	var foot: Array[Vector3] = []
	var average_height := 0.0
	for i in range(outline.size()):
		var point: Vector2 = outline[i]
		var upper := point.lerp(centroid, 0.15 + 0.05 * sin(i * 2.3))
		foot.append(_grounded(Vector3(point.x + rock_center.x, 0.06, point.y + rock_center.y)))
		top.append(_grounded(Vector3(upper.x + rock_center.x, heights[i], upper.y + rock_center.y)))
		average_height += heights[i]
	var peak := _grounded(Vector3(centroid.x + rock_center.x - 0.18, average_height / outline.size() + 0.20, centroid.y + rock_center.y + 0.12))
	for i in range(outline.size()):
		var next := (i + 1) % outline.size()
		var side_color := color.darkened(0.12 if i % 3 else 0.28)
		_triangle(surface, foot[i], foot[next], top[next], side_color)
		_triangle(surface, foot[i], top[next], top[i], side_color)
		_triangle(surface, top[i], top[next], peak, color.lightened(0.035 * sin(i * 1.7)))

func _oasis_front_depth(across: float) -> float:
	return 15.1 + sin(across * 0.21) * 0.35 + 3.4 * exp(-pow((across - 3.0) / 6.0, 2))

func _build_oasis_backdrop() -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	for layer in range(2):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows: Array = []
		var bands: Array[float] = [0.0, 0.19, 0.42, 0.65, 0.83, 1.0]
		for i in range(101):
			var u := -45.0 + i * 0.90
			var near := layer == 0
			var front := across * u + away * (_oasis_front_depth(u) if near else 29.5)
			front.y = profile.sample(front.x, front.z) if near else 0.5
			var crest := across * (u + sin(u * 0.57) * 0.20) + away * ((24.5 if near else 35.0) + sin(u * 0.19) * 2.0)
			if near:
				crest.y = 1.7 + 8.1 * exp(-pow((u + 11.0) / 7.1, 2)) + 6.5 * exp(-pow((u - 16.0) / 8.8, 2))
			else:
				crest.y = 2.0 + 4.7 * exp(-pow((u - 3.0) / 6.0, 2)) + 3.0 * exp(-pow((u + 17.0) / 9.0, 2))
			crest.y += 0.45 * smoothstep(-0.25, 0.45, sin(u * 0.57)) + 0.16 * sin(u * 1.8)
			if not near:
				crest.y += 0.62 * sin(u * 0.67) + 0.38 * sin(u * 0.29 + 1.0)
			crest.y = maxf(crest.y, front.y + 0.9)
			var row: Array[Vector3] = []
			for fraction in bands:
				var point := front.lerp(crest, fraction)
				var groove := pow(absf(sin(u * 0.55 + fraction * 0.4)), 8)
				point.y -= groove * sin(fraction * PI) * (1.25 if near else 0.35)
				point += away * sin(u * 0.44 + fraction * 3.4) * sin(fraction * PI) * 0.55
				if near and fraction > 0.0 and fraction <= 0.42:
					point.y = maxf(point.y, profile.sample(point.x, point.z) + 0.10)
				row.append(point)
			var back := crest + away * 8.0
			back.y = -2.0
			row.append(back)
			rows.append(row)
		for i in range(rows.size() - 1):
			for band in range(bands.size()):
				var color := Color("ae805c").lerp(Color("cfaf80"), bands[band] * 0.85)
				color = color.darkened(pow(absf(sin(i * 0.47)), 5) * 0.12)
				if layer == 1:
					color = Color("bea88d").lerp(Color("d1bea2"), bands[band] * 0.65)
				_triangle(surface, rows[i][band], rows[i + 1][band], rows[i + 1][band + 1], color)
				_triangle(surface, rows[i][band], rows[i + 1][band + 1], rows[i][band + 1], color.lightened(0.015))
		_finish_surface(surface, "WeatheredCanyonShoulders" if layer == 0 else "DistantDesertButtes")
	# This whole water ellipse is surrounded by the continuous ground in front
	# of the canyon foot, so the cliff cannot slice it into an exposed blue wedge.
	var pool := SurfaceTool.new()
	pool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(2.0, TerrainProfile.OASIS_POOL_LEVEL, -15.1)
	for i in range(64):
		var angle0 := i * TAU / 64.0
		var angle1 := (i + 1) * TAU / 64.0
		var a := center + Vector3(cos(angle0) * 5.8, 0, sin(angle0) * 2.8)
		var b := center + Vector3(cos(angle1) * 5.8, 0, sin(angle1) * 2.8)
		_triangle(pool, center, a, b, Color("5f9590"))
	_finish_surface(pool, "DistantSpringPool")

func _build_oasis_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51624
	for p in [Vector3(-15.5, 0, -8), Vector3(-19, 0, -3), Vector3(-17.5, 0, 7.5), Vector3(-9.5, 0, -11.7), Vector3(12.5, 0, -10), Vector3(18, 0, -4.5), Vector3(18, 0, 8), Vector3(-11, 0, 13), Vector3(12, 0, 13.5)]:
		_rock(p + Vector3(0, 0.22, 0), Vector3(rng.randf_range(1.3, 2.3), rng.randf_range(0.7, 1.2), rng.randf_range(1.2, 1.8)))
		if p.x < 0 or p.z < 0:
			_cactus(p + Vector3(1.7, 0, 0.35), rng.randf_range(0.65, 0.98))
		_agave(p + Vector3(-0.9, 0, 0.55), rng.randf_range(0.5, 0.8))
	for p in [Vector3(-4.5, 0, -15), Vector3(8.7, 0, -16), Vector3(12, 0, -12.5), Vector3(14.8, 0, 7.0)]:
		_oasis_palm(p, rng.randf_range(0.80, 1.0))
		_shrub(p + Vector3(-0.9, 0.03, 0.7), 0.75)
	# Sparse foreground pockets sit on the rising non-playable shoulders, not
	# across either dog route. Unequal spacing avoids a perimeter fence of props.
	for p in [Vector3(-13.6, 0, 13.1), Vector3(-10.8, 0, 14.8), Vector3(15.7, 0, 13.8), Vector3(13.9, 0, 16.4)]:
		_rock(p + Vector3(0, 0.27, 0), Vector3(1.9, 0.95, 1.35))
		_agave(p + Vector3(0.9, 0, 0.35), 0.85)
	for i in range(75):
		var p := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-10.3, 10.3))
		if Vector2(p.x, p.z).distance_to(rock_center) < rock_radius + 1.0:
			continue
		if p.x < 6 and absf(p.z) < 6.5:
			continue # Both dog routes stay visually open.
		var color := Color("889761") if p.x > 5 else Color("b59e6c")
		var grass := cylinder(terrain, _grounded(p + Vector3(0, 0.13, 0)), 0.0, 0.10, rng.randf_range(0.13, 0.28), color, 4)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rest := Vector2(11.8, 4.5)
	_draped_patch(rest, Vector2(2.7, 1.7), Color("c09573"), 0.035)
	for x in [rest.x - 0.8, rest.x + 0.8]:
		_draped_patch(Vector2(x, rest.y), Vector2(0.10, 1.7), Color("ead5ab"), 0.05)
	var basket := cylinder(terrain, _grounded(Vector3(13.0, 0.26, 4.0)), 0.26, 0.23, 0.52, Color("a48155"), 9)
	basket.rotation.z = 0.08

func _oasis_palm(pos: Vector3, palm_scale: float) -> void:
	var palm := Node3D.new()
	palm.position = _grounded(pos)
	palm.scale = Vector3.ONE * palm_scale
	terrain.add_child(palm)
	for i in range(4):
		var from := Vector3(sin(i * 0.4) * 0.28, i * 0.85, 0)
		var to := Vector3(sin((i + 1) * 0.4) * 0.28, (i + 1) * 0.85, 0)
		var trunk := cylinder(palm, (from + to) * 0.5, 0.12, 0.15, from.distance_to(to) + 0.025, Color("a58a60"), 8)
		trunk.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown := Vector3(0.28, 3.4, 0)
	for i in range(8):
		var angle := i * TAU / 8.0 + pos.x * 0.16
		var direction := Vector3(cos(angle), 0, sin(angle))
		var crosswise := Vector3(-sin(angle), 0, cos(angle)) * 0.25
		var middle := crown + direction * 1.1 + Vector3.UP * 0.28
		var tip := crown + direction * (1.8 + sin(i * 2.3) * 0.2) - Vector3.UP * 0.65
		var color := Color("758c5c") if i % 2 else Color("94a16c")
		_triangle(leaves, crown, middle - crosswise, middle + crosswise, color)
		_triangle(leaves, middle - crosswise, tip, middle + crosswise, color)
	var fronds := mesh(palm, leaves.commit(), Vector3.ZERO, Color.WHITE)
	fronds.material_override = vertex_material

func _oasis_track_wear(point: Vector3) -> float:
	var x := point.x - rock_center.x
	var z := point.z - rock_center.y
	var span := 1.0 - smoothstep(7.2, 9.4, absf(x))
	var north := -5.2 * sqrt(maxf(0.0, 1.0 - pow(x / 8.6, 2)))
	var south := 5.7 * sqrt(maxf(0.0, 1.0 - pow(x / 9.2, 2))) + sin(x * 0.45) * 0.22
	var north_wear := exp(-pow((z - north) / 1.05, 2)) * (0.23 + 0.12 * sin(x * 0.60 + 0.8))
	var south_wear := exp(-pow((z - south) / 1.25, 2)) * (0.19 + 0.10 * cos(x * 0.77))
	var entry := exp(-pow((z - 0.8 - sin((x + 17.0) * 0.24) * 0.45) / 1.2, 2)) * (1.0 - smoothstep(-9.0, -6.5, x))
	var exit_path := exp(-pow((z - sin((x - 9.0) * 0.19) * 1.1) / 1.3, 2)) * smoothstep(7.0, 10.0, x)
	return maxf(maxf(north_wear, south_wear) * span, maxf(entry, exit_path) * 0.27)

func _oasis_ground_color(point: Vector3, normal: Vector3) -> Color:
	var color := Color("c4a377")
	color = color.lerp(Color("a77c5b"), smoothstep(0.12, 0.45, 1.0 - normal.y) * 0.78)
	color = color.lerp(Color("b18c63"), smoothstep(1.0, 5.0, point.y) * 0.30)
	var pasture := smoothstep(4.0, 11.0, point.x) * (1.0 - smoothstep(8.0, 17.0, absf(point.z)))
	var spring_green := exp(-pow((point.x - 5.0) / 10.0, 2) - pow((point.z + 12.5) / 7.5, 2))
	color = color.lerp(Color("829b67"), maxf(pasture * 0.94, spring_green * 0.83))
	color = color.lerp(Color("d0b383"), _oasis_track_wear(point))
	color = color.lightened(sin(point.x * 0.22 + point.z * 0.15 + sin(point.z * 0.35) * 0.8) * 0.025)
	return color.lightened(sin(point.x * 0.12 + point.z * 0.08) * 0.014)

func _orchard_bank_quad(surface: SurfaceTool, side: float, offset0: float, offset1: float, z0: float, z1: float) -> void:
	var a := _orchard_bank_point(side, offset0, z0)
	var b := _orchard_bank_point(side, offset1, z0)
	var c := _orchard_bank_point(side, offset1, z1)
	var d := _orchard_bank_point(side, offset0, z1)
	_ground_triangle(surface, a, b, c, Color.WHITE, true)
	_ground_triangle(surface, a, c, d, Color.WHITE, true)

func _orchard_bank_point(side: float, offset: float, z: float) -> Vector3:
	var x := profile.river_center(z) + side * (profile.river_width(z) + offset)
	return Vector3(x, profile.raw_height(x, z), z)

func _orchard_transition_strip(surface: SurfaceTool, side: float, column: float, inner_z: float, outer_z: float) -> void:
	# One full inner edge matches the unchanged walking grid. The opposite edge
	# splits in two to match the finer bank mesh, with no hanging midpoint vertex.
	var a := _orchard_bank_point(side, column, inner_z)
	var b := _orchard_bank_point(side, column + 1.0, inner_z)
	var c := _orchard_bank_point(side, column + 1.0, outer_z)
	var d := _orchard_bank_point(side, column + 0.5, outer_z)
	var e := _orchard_bank_point(side, column, outer_z)
	_ground_triangle(surface, a, b, c, Color.WHITE, true)
	_ground_triangle(surface, a, c, d, Color.WHITE, true)
	_ground_triangle(surface, a, d, e, Color.WHITE, true)

func _build_river() -> void:
	var channel := SurfaceTool.new()
	channel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water_step := 0.25 if landscape == "orchard" else 1.0
	var water_start := -36.0 if landscape == "orchard" else -20.0
	var water_length := 45.0 - water_start
	for iz in range(int(water_length / water_step)):
		var z0 := water_start + iz * water_step
		var z1 := z0 + water_step
		var w0 := profile.river_width(z0)
		var w1 := profile.river_width(z1)
		var center0 := profile.river_center(z0)
		var center1 := profile.river_center(z1)
		_triangle(channel, Vector3(center0 - w0, 0, z0), Vector3(center0 + w0, 0, z0), Vector3(center1 + w1, 0, z1), Color.WHITE)
		_triangle(channel, Vector3(center0 - w0, 0, z0), Vector3(center1 + w1, 0, z1), Vector3(center1 - w1, 0, z1), Color.WHITE)
	water = mesh(terrain, channel.commit(), Vector3(0, TerrainProfile.WATER_LEVEL, 0), _color("477f88", "638f88", "", "5d908e"))
	water.name = "RiverSurface"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		var bank := SurfaceTool.new()
		bank.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bank_length := water_length if landscape == "orchard" else 32.0
		for iz in range(int(bank_length / water_step)):
			var z0 := water_start + iz * water_step
			var z1 := z0 + water_step
			var x0: float = profile.river_center(z0) + side * profile.river_width(z0)
			var x1: float = profile.river_center(z1) + side * profile.river_width(z1)
			var a := Vector3(x0, profile.sample(x0, z0), z0)
			var b := Vector3(x1, profile.sample(x1, z1), z1)
			var c := Vector3(x1 - side * 0.13, -0.82, z1)
			var d := Vector3(x0 - side * 0.13, -0.82, z0)
			_triangle(bank, a, b, c, _color("7e8875", "a18162"))
			_triangle(bank, a, c, d, _color("858d78", "ad8a67"))
		_finish_surface(bank, "CutRiverbank")
	for i in range(29):
		var z := -18.0 + i * 2.05
		var x := profile.river_center(z) + sin(i * 2.6) * profile.river_width(z) * 0.60
		var stripe := box(terrain, Vector3(x, TerrainProfile.WATER_LEVEL + 0.018, z), Vector3(0.35 + fmod(i * 0.33, 0.5), 0.008, 0.025), _color("8fb5b1", "a8bca4"))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _terrain_height(x: float, z: float) -> float:
	return profile.sample(x, z)

func surface_height(x: float, z: float) -> float:
	if landscape == "alpine_valley" and region_profile != null:
		if region_presentation != null:
			return region_presentation.surface_height(x, z)
		# Explicit construction-only fallback before the prepared mesh is indexed.
		return region_profile.surface_height(x, z)
	return profile.surface_height(x, z)

func surface_normal(x: float, z: float) -> Vector3:
	if landscape == "alpine_valley" and region_profile != null:
		if region_presentation != null:
			return region_presentation.surface_normal(x, z)
		return region_profile.normal(x, z)
	if profile.bridge_at(x, z) or absf(x - profile.river_center(z)) < profile.river_width(z):
		return Vector3.UP
	var step := 0.06
	var dx := (surface_height(x + step, z) - surface_height(x - step, z)) / (step * 2.0)
	var dz := (surface_height(x, z + step) - surface_height(x, z - step)) / (step * 2.0)
	return Vector3(-dx, 1, -dz).normalized()

func place_marker(marker: Node3D, pos: Vector3) -> void:
	var normal := surface_normal(pos.x, pos.z)
	var right := Vector3.RIGHT.slide(normal).normalized()
	marker.basis = Basis(right, normal, right.cross(normal).normalized())
	marker.position = Vector3(pos.x, surface_height(pos.x, pos.z) + 0.13, pos.z)

func _grounded(pos: Vector3) -> Vector3:
	return Vector3(pos.x, surface_height(pos.x, pos.z) + pos.y, pos.z)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front-facing. Match winding to the normal,
	# including the mirrored left bank, so two-sided shading cannot invert the light.
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0:
		var previous_b := b
		b = c
		c = previous_b
		normal = -normal
	# Compatibility converts the final albedo from sRGB inside scene.glsl.
	# Converting here as well crushes the greens and turns rock shadows black.
	surface.set_color(color)
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)

func _ground_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, smooth_terrain := false) -> void:
	# Clip only the distant ground, behind overlapping mountain bases. The foreground
	# still extends past the viewport; the skyline is real silhouette against the sky.
	var polygon: Array[Vector3] = [a, b, c]
	var clipped: Array[Vector3] = []
	var previous := polygon.back() as Vector3
	var previous_gap := _ground_horizon_gap(previous)
	for point in polygon:
		var gap := _ground_horizon_gap(point)
		var inside := gap >= 0.0
		var previous_inside := previous_gap >= 0.0
		if inside != previous_inside:
			clipped.append(previous.lerp(point, previous_gap / (previous_gap - gap)))
		if inside:
			clipped.append(point)
		previous = point
		previous_gap = gap
	for i in range(1, clipped.size() - 1):
		if smooth_terrain:
			_terrain_triangle(surface, clipped[0], clipped[i], clipped[i + 1])
		else:
			_triangle(surface, clipped[0], clipped[i], clipped[i + 1], color)

func _larch_front_depth(across: float) -> float:
	# The whole playable rectangle is nearer than depth 14.27. This irregular foot
	# stays beyond it while letting the low saddle remain low, not a raised wall.
	return maxf(14.7, 14.8 + sin(across * 0.23) * 1.8)

func _ground_horizon_gap(point: Vector3) -> float:
	var depth := -point.x * 0.2063 - point.z * 0.9785
	var limit := TERRAIN_HORIZON_DEPTH
	if landscape == "larch":
		var across := point.x * 0.9785 - point.z * 0.2063
		# Only a narrow overlap under the granite foot is needed. Farther heightfield
		# would pierce the lower saddle and expose an artificial green cut-off slab.
		limit = _larch_front_depth(across) + 0.12
	elif landscape == "orchard":
		limit = 32.0
	elif landscape == "oasis":
		var across := point.x * 0.9785 - point.z * 0.2063
		limit = _oasis_front_depth(across) + 0.10
	elif landscape in ["cloud", "juniper", "bellflower"]:
		limit = 49.0
	return limit - depth

func _terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (c - a).cross(b - a).y < 0:
		var previous_b := b
		b = c
		c = previous_b
	for point in [a, b, c]:
		var normal := profile.normal_at(point.x, point.z)
		if landscape == "bellflower":
			var depth: float = -point.x * 0.2063 - point.z * 0.9785
			if depth > 27.0:
				normal = normal.lerp((c - a).cross(b - a).normalized(), smoothstep(27.0, 35.0, depth)).normalized()
			surface.set_color(CommonsScenery.ground_color(self, point, normal))
			surface.set_normal(normal)
			surface.add_vertex(point)
			continue
		if landscape == "juniper":
			var depth: float = -point.x * 0.2063 - point.z * 0.9785
			if depth > 28.0:
				normal = normal.lerp((c - a).cross(b - a).normalized(), smoothstep(28.0, 34.0, depth)).normalized()
			surface.set_color(ShoreScenery.ground_color(self, point, normal))
			surface.set_normal(normal)
			surface.add_vertex(point)
			continue
		if landscape == "cloud":
			var depth: float = -point.x * 0.2063 - point.z * 0.9785
			var u: float = point.x * 0.9785 - point.z * 0.2063
			var mountain_front := profile.cloud_mountain_front(u)
			if depth > mountain_front + 1.0:
				var faceting := smoothstep(mountain_front + 1.0, mountain_front + 5.0, depth)
				normal = normal.lerp((c - a).cross(b - a).normalized(), faceting).normalized()
			surface.set_color(_cloud_ground_color(point, normal))
			surface.set_normal(normal)
			surface.add_vertex(point)
			continue
		if landscape == "oasis":
			surface.set_color(_oasis_ground_color(point, normal))
			surface.set_normal(normal)
			surface.add_vertex(point)
			continue
		var color := _color("88a46a", "c4a06f", "99a579", "a2b079", "c4a377")
		var flank := smoothstep(0.12, 0.45, 1.0 - normal.y)
		color = color.lerp(_color("798273", "a67b58", "838777", "8e9971", "a77c5b"), flank * 0.78)
		var high_meadow := smoothstep(1.0, 5.0, point.y)
		color = color.lerp(_color("71905c", "b58e62", "899a69", "8da56e", "b18c63"), high_meadow * 0.30)
		if landscape == "orchard":
			var depth: float = -point.x * 0.2063 - point.z * 0.9785
			var across: float = point.x * 0.9785 - point.z * 0.2063
			var distance := smoothstep(15.0, 28.0, depth)
			var fields := 0.5 + 0.5 * sin(point.x * 0.18 + sin(point.z * 0.11) * 1.5)
			color = color.lerp(Color("b7b786").lerp(Color("a8b69a"), fields), distance * 0.8)
			# Field color belongs to the ground itself, never a floating overlay that
			# bridges a hill or spans from grass across the recessed stream.
			var hay_field := 1.0 - smoothstep(0.65, 1.20, pow((across + 9.0) / 3.8, 2) + pow((depth - 19.0) / 1.4, 2))
			var high_field := 1.0 - smoothstep(0.65, 1.20, pow((across + 2.0) / 3.4, 2) + pow((depth - 27.0) / 1.4, 2))
			color = color.lerp(Color("b4b17b"), hay_field * 0.65)
			color = color.lerp(Color("b6bc93"), high_field * 0.55)
		color = color.lightened(sin(point.x * 0.12 + point.z * 0.08) * 0.014)
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(point)

func _finish_surface(surface: SurfaceTool, label: String, shadow := false) -> MeshInstance3D:
	if vertex_material == null:
		vertex_material = StandardMaterial3D.new()
		vertex_material.vertex_color_use_as_albedo = true
		vertex_material.vertex_color_is_srgb = true
		vertex_material.roughness = 1.0
		vertex_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = surface.commit()
	node.material_override = vertex_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(node)
	return node

func _trail(points: Array, width: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var start: Vector2 = points[i]
		var finish: Vector2 = points[i + 1]
		var count := maxi(1, int(ceil(start.distance_to(finish) / 0.45)))
		var side := (finish - start).normalized().orthogonal() * width * 0.5
		for segment in range(count):
			var from := start.lerp(finish, float(segment) / count)
			var to := start.lerp(finish, float(segment + 1) / count)
			var a := _grounded(Vector3(from.x + side.x, 0.035, from.y + side.y))
			var b := _grounded(Vector3(from.x - side.x, 0.035, from.y - side.y))
			var c := _grounded(Vector3(to.x - side.x, 0.035, to.y - side.y))
			var d := _grounded(Vector3(to.x + side.x, 0.035, to.y + side.y))
			_ground_triangle(surface, a, b, c, _color("b1b593", "d5b384"))
			_ground_triangle(surface, a, c, d, _color("b1b593", "d5b384"))
	_finish_surface(surface, "WanderingTrail")

func _build_backdrop() -> void:
	if landscape == "bellflower":
		return # Its common, foothills and mountain folds are one continuous mesh.
	if landscape == "juniper":
		return # Continuous mesh already includes the bay, foothills and snow peaks.
	if landscape == "cloud":
		_build_cloud_backdrop()
		return
	# Connected, asymmetric ridges and gullies follow the reference valleys. A large
	# crag on one flank faces a lower saddle; there is no row of separate cones.
	if landscape == "oasis":
		_build_oasis_backdrop()
		return
	if landscape == "orchard":
		_build_orchard_distance()
		_build_orchard_trees()
		return
	if landscape == "larch":
		_ridge_strip(30.0, 37.0, -1.3, 7.1, 1.1, true, true)
		_ridge_strip(14.8, 24.8, 2.0, 7.8, 0.65, false, false)
		_build_larch_forests()
	else:
		_ridge_strip(29.5, 36.5, -1.9, 7.3, 0.9, false, true)
		_ridge_strip(15.5, 25.5, 3.0, 7.0 if landscape == "alpine" else 5.0, 0.0, landscape == "alpine", false)
	if landscape == "alpine":
		for i in range(27):
			var z := -15.0 + sin(i * 1.7) * 2.1
			var x := -25.0 + i * 2.1
			if absf(x) > 3.5:
				_pine(Vector3(x, 0, z), 0.66 + fmod(i * 0.33, 0.42), i % 4 == 0)
		for i in range(15):
			var p := Vector3(-21.5 + sin(i * 1.7) * 1.9, 0, -12.0 + i * 1.9)
			_pine(p, 0.9 + fmod(i * 0.23, 0.35), i % 3 == 0)

func _build_larch_forests() -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	var rng := RandomNumberGenerator.new()
	rng.seed = 79241
	# Three uneven woodland pockets climb the shoulder at different depths. Crown
	# silhouettes overlap in the view, but their geometry must not interpenetrate.
	var groups := [
		{"center": Vector2(-23.5, 9.0), "radius": Vector2(4.8, 3.0), "count": 16},
		{"center": Vector2(-13.8, 11.1), "radius": Vector2(3.5, 2.3), "count": 10},
		{"center": Vector2(-6.5, 12.4), "radius": Vector2(1.9, 1.5), "count": 5},
	]
	# Each entry stores across/depth coordinates and its actual crown radius.
	# Reserve the nearby detail trees too: their independent placement previously
	# let a golden larch intersect an evergreen in the smallest woodland pocket.
	var planted: Array[Vector3] = []
	for p in [Vector3(-14, 0, -8), Vector3(-10, 0, -9.5), Vector3(-15.2, 0, 5.7), Vector3(13, 0, -8.8), Vector3(15.6, 0, -5.8), Vector3(13.8, 0, 8.3)]:
		planted.append(Vector3(p.dot(across), p.dot(away), 1.25))
	for group in groups:
		var placed := 0
		for attempt in range(180):
			if placed >= int(group.count):
				break
			var angle := rng.randf_range(0, TAU)
			var radius := sqrt(rng.randf())
			var local: Vector2 = group.center + Vector2(cos(angle), sin(angle)) * group.radius * radius
			if local.y > _larch_front_depth(local.x) - 0.65:
				continue
			var scale_value := rng.randf_range(0.62, 1.28)
			var crown_radius := 1.08 * scale_value + 0.06
			var crowded := false
			for other in planted:
				var clearance := maxf(1.70, crown_radius + other.z + 0.15)
				if local.distance_to(Vector2(other.x, other.y)) < clearance:
					crowded = true
					break
			if crowded:
				continue
			var p := across * local.x + away * local.y
			if absf(p.x) < 3.8:
				continue
			planted.append(Vector3(local.x, local.y, crown_radius))
			placed += 1
			if rng.randf() < 0.18:
				_pine(p, scale_value * 0.91)
			else:
				_larch(p, scale_value, rng.randf() < 0.37)
	for p in [Vector3(15, 0, -10), Vector3(17.8, 0, -6), Vector3(18.3, 0, 8.0)]:
		_larch(p, 0.92, p.z > 0)

func _build_orchard_distance() -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	# Real rounded hills now live in the heightfield. Only the distant mountain
	# silhouette is separate, centered within BOTH portrait camera pan extremes.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	var bands: Array[float] = [0.0, 0.22, 0.48, 0.72, 0.89, 1.0]
	for i in range(101):
		var u := -45.0 + i * 0.90
		var front := across * u + away * (30.1 + sin(u * 0.22) * 0.7)
		front.y = profile.sample(front.x, front.z)
		var crest := across * (u + sin(u * 0.70) * 0.12) + away * (35.0 + sin(u * 0.27) * 1.4)
		crest.y = 2.0 + 6.7 * exp(-pow((u - 1.8) / 5.0, 2))
		crest.y += 3.8 * exp(-pow((u + 12.0) / 5.3, 2)) + 3.0 * exp(-pow((u - 15.0) / 7.0, 2))
		crest.y += 0.30 * sin(u * 1.15) + 0.15 * sin(u * 2.1)
		crest.y = maxf(crest.y, front.y + 0.7)
		var row: Array[Vector3] = []
		for fraction in bands:
			var point := front.lerp(crest, fraction)
			point.y -= sin(fraction * PI) * pow(absf(sin(u * 0.66)), 8) * 0.65
			point += away * sin(u * 0.37 + fraction * 3.0) * sin(fraction * PI) * 0.35
			row.append(point)
		var back := crest + away * 9.0
		back.y = -3.0
		row.append(back)
		rows.append(row)
	for i in range(rows.size() - 1):
		for band in range(bands.size()):
			var color := Color("91a59a").lerp(Color("a7bbc0"), smoothstep(0.0, 4.0, band))
			color = color.darkened(pow(absf(sin(i * 0.59)), 5) * 0.07)
			_triangle(surface, rows[i][band], rows[i + 1][band], rows[i + 1][band + 1], color)
			_triangle(surface, rows[i][band], rows[i + 1][band + 1], rows[i][band + 1], color.lightened(0.01))
	_finish_surface(surface, "SunwardDistantMountain")
	for coordinate in [Vector2(-4, 23), Vector2(-1.5, 22), Vector2(0.6, 24)]:
		_chalet(across * coordinate.x + away * coordinate.y, 0.43)
	var road: Array[Vector2] = []
	for coordinate in [Vector2(-12, 12.5), Vector2(-10, 16), Vector2(-5, 18.5), Vector2(-2, 22), Vector2(-5, 26.5)]:
		var point: Vector3 = across * coordinate.x + away * coordinate.y
		road.append(Vector2(point.x, point.z))
	_trail(road, 0.43)

func _build_orchard_trees() -> void:
	var trees := [
		Vector3(-22, 1.04, -11), Vector3(-17.5, 1.12, -9.5),
		Vector3(-13.0, 0.79, -13.8), Vector3(-8.8, 0.95, -11.2),
		Vector3(-4.1, 0.68, -15.1), Vector3(-12.4, 0.92, -6.4),
		Vector3(-18.7, 0.91, -4.5), Vector3(-24, 1.07, -1.5),
		Vector3(-19.2, 1.08, 8), Vector3(15.4, 0.96, 7.5),
		Vector3(6, 0.66, -21), Vector3(16, 0.63, -24),
	]
	for entry in trees:
		_apple_tree(Vector3(entry.x, 0, entry.z), entry.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31029
	for i in range(12):
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * forage_radius * 0.78
		var point := forage_center + Vector2(cos(angle), sin(angle)) * distance
		_apple(terrain, _grounded(Vector3(point.x, 0.12, point.y)), 0.25, i % 3 == 0)
	# The clearing remains grass, not a colored trigger circle or a collectible pad.
	for i in range(5):
		var point := forage_center + Vector2(sin(i * 2.1), cos(i * 2.1)) * forage_radius * 0.83
		var leaf := ball(terrain, _grounded(Vector3(point.x, 0.025, point.y)), Vector3(0.30, 0.035, 0.12), Color("b6a068"))
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apple_tree(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.name = "AppleTree"
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	tree.rotation.y = pos.x * 0.14
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 1.35, 0), 0.15, 0.25, 2.7, Color("8c7858"), 9)
	for side in [-1, 1]:
		var limb := cylinder(tree, Vector3(side * 0.38, 2.25, 0), 0.10, 0.16, 1.5, Color("8c7858"), 7)
		limb.rotation.z = side * -0.63
	_apple_crown(tree, pos.x * 0.71 + pos.z * 0.31)
	for i in range(4):
		var angle := i * TAU / 4.0 + 0.4
		_apple(tree, Vector3(cos(angle) * 1.62, 2.67 + 0.20 * sin(i * 1.8), sin(angle) * 1.17), 0.24, i == 1)

func _apple_crown(parent: Node3D, phase: float) -> void:
	# One closed, softly lobed crown avoids the intersecting ellipsoid seams and
	# repeated stacked-hat silhouette of the first Android pass.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for ring in range(9):
		var latitude := ring * PI / 8.0
		var row: Array[Vector3] = []
		for segment in range(15):
			var angle := segment * TAU / 14.0
			var lobes := 1.0 + 0.09 * sin(angle * 3.0 + phase) + 0.05 * cos(angle * 2.0 - latitude * 3.0)
			var radius := sin(latitude) * lobes
			row.append(Vector3(cos(angle) * radius * 2.05, 3.45 + cos(latitude) * 1.15 + sin(angle * 3.0 + phase) * sin(latitude) * 0.12, sin(angle) * radius * 1.68))
		rings.append(row)
	for ring in range(8):
		for segment in range(14):
			var color := Color("93aa69").lightened(sin(phase) * 0.035)
			_crown_triangle(surface, rings[ring][segment], rings[ring + 1][segment], rings[ring + 1][segment + 1], color)
			_crown_triangle(surface, rings[ring][segment], rings[ring + 1][segment + 1], rings[ring][segment + 1], color)
	var crown := mesh(parent, surface.commit(), Vector3.ZERO, Color.WHITE)
	crown.name = "Crown"
	crown.material_override = vertex_material

func _crown_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var center := Vector3(0, 3.45, 0)
	if (c - a).cross(b - a).dot((a + b + c) / 3.0 - center) < 0:
		var saved_b := b
		b = c
		c = saved_b
	for point in [a, b, c]:
		var relative: Vector3 = point - center
		var normal := Vector3(relative.x / 4.2, relative.y / 1.32, relative.z / 2.82).normalized()
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(point)

func _apple(parent: Node3D, pos: Vector3, diameter: float, golden: bool) -> void:
	var shape := SphereMesh.new()
	shape.radius = diameter * 0.5
	shape.height = diameter * 0.93
	shape.radial_segments = 8
	shape.rings = 4
	var apple := mesh(parent, shape, pos, Color("c7a059") if golden else Color("b36d50"))
	apple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ridge_strip(front_depth: float, crest_depth: float, base_height: float, amplitude: float, phase: float, snow: bool, hazy: bool) -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	var sections: Array = []
	var count := 131
	var bands: Array[float] = [0.0, 0.16, 0.32, 0.48, 0.62, 0.74, 0.84, 0.91, 1.0]
	for i in range(count):
		var u := -52.0 + i * 0.8
		var structure := 0.48 + 0.66 * exp(-pow((u + 12.0) / 9.0, 2)) + 0.98 * exp(-pow((u - 10.0) / 5.0, 2)) + 0.62 * exp(-pow((u - 29.0) / 10.0, 2))
		if landscape == "larch" and not hazy:
			# A dominant granite flank faces a much lower open saddle.
			structure = 0.28 + 1.45 * exp(-pow((u + 13.0) / 5.7, 2)) + 0.34 * exp(-pow((u - 25.0) / 10.0, 2))
		var jagged := 0.22 * pow(maxf(sin(u * 0.93 + phase), 0.0), 4) + 0.11 * sin(u * 2.03 - phase)
		if landscape == "cactus":
			structure = 0.56 + 0.65 * smoothstep(-0.2, 0.6, sin(u * 0.17 + phase))
			jagged *= 0.35
		var crest_height := base_height + amplitude * (structure + jagged)
		var foot_depth := front_depth + sin(u * 0.23) * 1.8
		if landscape == "larch" and not hazy:
			foot_depth = _larch_front_depth(u)
		var front := across * u + away * foot_depth
		front.y = base_height - 1.4 if hazy else profile.sample(front.x, front.z)
		var crest := across * (u + sin(u * 0.7) * 0.20) + away * (crest_depth + sin(u * 0.31 + phase) * 2.9)
		crest.y = maxf(crest_height, front.y + (0.6 if hazy else 1.4))
		var row: Array[Vector3] = []
		for band in bands:
			var point := front.lerp(crest, band)
			var middle := sin(band * PI)
			var gully := pow(absf(sin(u * 0.61 + phase)), 10)
			point.y -= gully * middle * (2.1 if not hazy else 0.65)
			point.y += sin(u * 1.16 + band * 5.1) * middle * 0.45
			point += across * sin(u * 0.91 + band * 4.0) * middle * 0.24
			point += away * sin(u * 0.71 + band * 4.6) * middle * 1.05
			if landscape == "larch" and not hazy and band > 0.0 and band <= 0.32:
				# The first rock ledges cover the tiny heightfield overlap. Gullies above
				# remain deep and the crest is untouched, preserving the open saddle.
				point.y = maxf(point.y, profile.sample(point.x, point.z) + middle * 0.35)
			row.append(point)
		var back := crest + away * 8.0
		back.y = base_height - 2.5
		row.append(back)
		sections.append(row)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count - 1):
		for band in range(bands.size()):
			var color := _color("6e7a79", "a57755", "7d837e")
			if band <= 1:
				color = _color("738d62", "b48b62", "8a9571")
			elif band <= 4:
				color = _color("727d79", "986e51", "7e8580")
			else:
				color = _color("8d9897", "bc946c", "9ca39b")
			var u := -52.0 + (i + 0.5) * 0.8
			var gully := pow(absf(sin(u * 0.61 + phase)), 10)
			color = color.darkened(gully * 0.15)
			var height: float = (sections[i][band].y + sections[i + 1][mini(band + 1, bands.size() - 1)].y) * 0.5
			var fraction := bands[band]
			var snowline := 9.4 + sin(u * 0.49) * 1.0
			var snow_patch := sin(u * 0.68 + fraction * 3.4) + 0.42 * cos(u * 1.37 - fraction * 4.1)
			if snow and band < bands.size() - 1 and height > snowline and fraction > lerpf(0.88, 0.67, gully) and snow_patch > 0.05:
				color = Color("e3e9e2").darkened(gully * 0.08)
			if hazy:
				color = _color("9eb5bd", "c1ac97").lightened(sin(i * 0.4) * 0.025)
				if landscape == "larch" and height > 8.1 and band >= 7 and snow_patch > 0.15:
					color = Color("ccd8d8")
			_triangle(surface, sections[i][band], sections[i + 1][band], sections[i + 1][band + 1], color)
			_triangle(surface, sections[i][band], sections[i + 1][band + 1], sections[i][band + 1], color.lightened(0.018))
	_finish_surface(surface, "DistantRidgeline" if hazy else ("GraniteFlank" if landscape == "larch" else ("AlpineCrags" if snow else "ErodedCanyon")))

func _build_boundaries() -> void:
	if landscape in ["oasis", "cloud", "juniper", "bellflower"]:
		return # The canyon shoulders and planted outcrops are composed separately.
	# Scattered outcrops follow the rising slopes. No rectangular necklace of shrubs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9401
	for p in [Vector3(-18, 0, -8), Vector3(-20, 0, -3), Vector3(-18.5, 0, 8), Vector3(18.7, 0, -7), Vector3(21, 0, 3), Vector3(18, 0, 9.5), Vector3(-12, 0, 12.7), Vector3(13, 0, 13.5)]:
		_rock(p + Vector3(0, 0.25, 0), Vector3(rng.randf_range(1.4, 2.8), rng.randf_range(0.8, 1.7), rng.randf_range(1.3, 2.4)))
		_shrub(p + Vector3(rng.randf_range(-1.0, 1.0), 0.05, 0.75), rng.randf_range(0.6, 0.9))
	if landscape == "orchard":
		# Low broken outcrops and bramble pockets follow the outer terrace shoulder.
		# They frame the accessible pasture without becoming a tree or shrub wall.
		for p in [Vector3(-18, 0.04, 2), Vector3(-18.7, 0.04, 6), Vector3(18.8, 0.04, -3)]:
			_shrub(p, 1.0)
		return
	for p in [Vector3(-25, 0, 17), Vector3(25, 0, 17), Vector3(-15, 0, 20), Vector3(14, 0, 22)]:
		if landscape == "cactus":
			_cactus(p, 1.3)
		elif landscape == "larch":
			_larch(p, 1.1, p.x > 0)
		else:
			_pine(p, 1.2, p.x < 0)

func _rock(pos: Vector3, scale_value: Vector3) -> void:
	var rock := ball(terrain, _grounded(pos), scale_value, _color("8b9383", "b18a63"))
	rock.rotation = Vector3(0.2, pos.x * 0.3, -0.14)

func _shrub(pos: Vector3, size: float) -> void:
	ball(terrain, _grounded(pos) + Vector3(0, size * 0.32, 0), Vector3(size * 1.85, size, size * 1.3), _color("66825c", "929b68"))
	if landscape == "cactus":
		_agave(pos + Vector3(0.6, 0, 0.25), size * 0.75)

func _build_bridge() -> void:
	bridge = Node3D.new()
	bridge.name = "Footbridge"
	bridge.position = Vector3(0, 0, bridge_y)
	terrain.add_child(bridge)
	for i in range(12):
		box(bridge, Vector3(-1.78 + i * 0.325, 0.13, 0), Vector3(0.305, 0.20, 3.9), _color("cda77a", "b68e67", "b89368") if i % 3 else _color("bf966b", "a8805c", "aa845e"))
	for z in [-2.0, 2.0]:
		for x in [-1.9, 0.0, 1.9]:
			box(bridge, Vector3(x, 0.62, z), Vector3(0.14, 1.16, 0.14), Color("8d7656"))
		box(bridge, Vector3(0, 0.92, z), Vector3(4.0, 0.12, 0.12), Color("b09066"))

func _build_fence() -> void:
	for interval in [Vector2(-10.5, gate_y - 2.0), Vector2(gate_y + 2.0, 10.5)]:
		var segments := maxi(1, int(ceil((interval.y - interval.x) / 1.7)))
		var spacing: float = (interval.y - interval.x) / segments
		for i in range(segments + 1):
			var z: float = interval.x + i * spacing
			box(terrain, _grounded(Vector3(6, 0.62, z)), Vector3(0.18, 1.18, 0.18), Color("9e8361"))
			if i < segments:
				for y in [0.4, 0.87]:
					var from := _grounded(Vector3(6, y, z))
					var to := _grounded(Vector3(6, y, z + spacing))
					var beam := box(terrain, (from + to) * 0.5, Vector3(0.10, 0.13, from.distance_to(to)), Color("c5a47a"))
					beam.look_at(to, Vector3.UP)
	gate = Node3D.new()
	gate.position = _grounded(Vector3(6, 0, gate_y - 2.0))
	terrain.add_child(gate)
	for z in [0.15, 1.0, 2.0, 3.0, 3.85]:
		box(gate, Vector3(0, 0.60, z), Vector3(0.13, 1.0, 0.14), Color("ae8960"))
	for y in [0.25, 0.9]:
		box(gate, Vector3(0, y, 2), Vector3(0.16, 0.15, 4), Color("c7a171"))
	var diagonal := box(gate, Vector3(0, 0.57, 2), Vector3(0.12, 0.12, 3.95), Color("b9966b"))
	diagonal.rotation.x = -0.16

func _build_details() -> void:
	if landscape == "bellflower":
		CommonsScenery.build_details(self)
		return
	if landscape == "juniper":
		ShoreScenery.build_details(self)
		return
	if landscape == "cloud":
		_build_cloud_details()
		return
	if landscape == "oasis":
		_build_oasis_details()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 42079
	for i in range(105):
		var x := rng.randf_range(-16.5, 16.5)
		var z := rng.randf_range(-10.4, 10.4)
		if absf(x) < 2.2 or absf(z) < 2.0 or absf(x - 6) < 0.8:
			continue
		var grass := cylinder(terrain, _grounded(Vector3(x, 0.12, z)), 0.0, 0.11, rng.randf_range(0.14, 0.3), _color("708957", "ad9e6d"), 4)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			ball(terrain, _grounded(Vector3(x, 0.25, z)), Vector3(0.12, 0.10, 0.12), Color("f5e4ae") if i % 2 else _color("d0aec3", "ce977e"))
	for p in [Vector3(-14, 0, -8), Vector3(-10, 0, -9.5), Vector3(-15.2, 0, 5.7), Vector3(13, 0, -8.8), Vector3(15.6, 0, -5.8), Vector3(13.8, 0, 8.3)]:
		if landscape == "orchard":
			continue # All twelve orchard crowns are composed around the clear route.
		elif landscape == "cactus":
			_cactus(p, rng.randf_range(0.9, 1.25))
			_agave(p + Vector3(1.1, 0.1, 0.6), 0.8)
		elif landscape == "larch":
			_larch(p, rng.randf_range(0.82, 1.10), p.x > 0)
		else:
			_tree(p, rng.randf_range(0.85, 1.15))
	for p in [Vector3(-2.4, 0, 7), Vector3(2.3, 0, -5), Vector3(-2.6, 0, -7.4), Vector3(15, 0, 4)]:
		ball(terrain, _grounded(p + Vector3(0, 0.12, 0)), Vector3(0.85, 0.50, 0.7), _color("a4a58f", "b99a75"))
		ball(terrain, _grounded(p + Vector3(0.45, 0.09, 0.22)), Vector3(0.4, 0.30, 0.4), _color("b0b09a", "c6a681"))
	# A place to rest, with no menu or reward machine.
	var rest := Vector2(12.4, 6.4) if landscape == "larch" else Vector2(11.6, 5.5)
	_draped_patch(rest, Vector2(2.8, 1.8), _color("d6bda0", "bc8165", "b99472"), 0.035)
	for x in [rest.x - 0.8, rest.x + 0.8]:
		_draped_patch(Vector2(x, rest.y), Vector2(0.12, 1.8), Color("f1dcc0"), 0.050)
	var basket := cylinder(terrain, _grounded(Vector3(rest.x + 1.2, 0.28, rest.y - 0.6)), 0.27, 0.23, 0.55, Color("b68d57"))
	basket.rotation.z = 0.07
	# One small wooden trail sign, shaped in world space.
	box(terrain, _grounded(Vector3(4.4, 0.7, gate_y - 3.1)), Vector3(0.12, 1.4, 0.12), Color("9e8361"))
	box(terrain, _grounded(Vector3(4.4, 1.15, gate_y - 3.1)), Vector3(1.0, 0.37, 0.12), Color("c6a475"))
	if landscape == "alpine":
		# A distant chalet and hay shelter are quiet hints of life beyond this stop.
		_chalet(Vector3(24, 0, -15), 0.85)
		_chalet(Vector3(-26, 0, -13), 0.60)
	elif landscape == "cactus":
		for p in [Vector3(-23, 0, -15), Vector3(21, 0, -14), Vector3(-20, 0, 8), Vector3(25, 0, 5), Vector3(9, 0, -17)]:
			_cactus(p, 1.25)
			_agave(p + Vector3(1.2, 0, 0.5), 1.0)
	elif landscape == "larch":
		_chalet(Vector3(25, 0, -9), 0.67)
		var resting_log := cylinder(terrain, _grounded(Vector3(rest.x - 1.8, 0.24, rest.y + 1.2)), 0.23, 0.26, 1.8, Color("92775b"), 9)
		resting_log.rotation.z = PI / 2
	else:
		var bench := Node3D.new()
		bench.position = _grounded(Vector3(13.0, 0, 5.3))
		terrain.add_child(bench)
		box(bench, Vector3(0, 0.48, 0), Vector3(2.0, 0.15, 0.58), Color("ac9369"))
		for x in [-0.73, 0.73]:
			box(bench, Vector3(x, 0.23, 0), Vector3(0.15, 0.46, 0.39), Color("8e7c5c"))

func _tree(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 1.0, 0), 0.13, 0.23, 2, Color("8e7e5f"))
	ball(tree, Vector3(0, 2.7, 0), Vector3(2.5, 3.2, 2.5), Color("718d62"))
	ball(tree, Vector3(-0.7, 2.3, 0.2), Vector3(1.8, 1.9, 1.8), Color("88a071"))
	ball(tree, Vector3(0.55, 3.2, -0.15), Vector3(1.9, 2.2, 1.9), Color("91a778"))

func _pine(pos: Vector3, tree_scale: float, autumn := false) -> void:
	var tree := Node3D.new()
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 0.75, 0), 0.09, 0.16, 1.5, Color("8d8065"), 7)
	for i in range(3):
		var needles := Color("b5a14d") if autumn else Color("476b59")
		if autumn and pos.x > 0:
			needles = Color("ac7845")
		cylinder(tree, Vector3(0, 1.6 + i * 0.74, 0), 0.03, 1.10 - i * 0.23, 2.0 - i * 0.26, needles.lightened(i * 0.035), 7)

func _larch(pos: Vector3, tree_scale: float, rust := false) -> void:
	var tree := Node3D.new()
	tree.name = "RustLarch" if rust else "GoldenLarch"
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	tree.rotation.y = pos.x * 0.19
	terrain.add_child(tree)
	var needles := Color("bb9f48") if not rust else Color("b58043")
	cylinder(tree, Vector3(0, 1.65, 0), 0.07, 0.15, 3.3, Color("8b7962"), 8)
	for i in range(5):
		var branch := cylinder(tree, Vector3(0.04 * sin(i), 1.2 + i * 0.55, 0), 0.015, 1.03 - i * 0.18, 1.2 - i * 0.09, needles.lightened(i * 0.025), 9)
		branch.rotation.y = i * 0.31
	for side in [-1, 1]:
		var limb := box(tree, Vector3(side * 0.25, 1.1, 0.05), Vector3(0.63, 0.055, 0.07), Color("8b7962"))
		limb.rotation.z = side * 0.22
	for i in range(2):
		var leaf_pos := Vector3(pos.x + sin(pos.z + i * 2.5) * 0.7, 0.035, pos.z + cos(pos.x + i * 2.2) * 0.65)
		ball(terrain, _grounded(leaf_pos), Vector3(0.30, 0.035, 0.19), needles.darkened(0.05))

func _cactus(pos: Vector3, cactus_scale: float) -> void:
	var cactus := Node3D.new()
	cactus.position = _grounded(pos)
	cactus.scale = Vector3.ONE * cactus_scale
	cactus.rotation.y = pos.x * 0.31
	terrain.add_child(cactus)
	var green := Color("779771")
	cylinder(cactus, Vector3(0, 1.35, 0), 0.22, 0.27, 2.7, green, 9)
	ball(cactus, Vector3(0, 2.70, 0), Vector3(0.45, 0.46, 0.45), green)
	for side in [-1, 1]:
		var height := 1.15 if side < 0 else 1.65
		var branch := cylinder(cactus, Vector3(side * 0.40, height, 0), 0.15, 0.18, 0.8, green, 8)
		branch.rotation.z = PI / 2
		cylinder(cactus, Vector3(side * 0.75, height + 0.36, 0), 0.15, 0.17, 0.72, green, 8)
		ball(cactus, Vector3(side * 0.75, height + 0.72, 0), Vector3(0.31, 0.32, 0.31), green)
	# A single small bloom replaces collectible-looking visual noise.
	ball(cactus, Vector3(0.05, 2.96, 0), Vector3(0.19, 0.11, 0.18), Color("d99591"))

func _agave(pos: Vector3, size: float) -> void:
	pos = _grounded(pos)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(7):
		var angle := i * TAU / 7
		var tip := pos + Vector3(cos(angle) * 0.7, 0.68, sin(angle) * 0.7) * size
		var side := Vector3(-sin(angle), 0, cos(angle)) * size * 0.13
		_triangle(surface, pos - side, pos + side, tip, Color("8a9e88").lightened((i % 3) * 0.045))
	_finish_surface(surface, "Agave")

func _chalet(pos: Vector3, cabin_scale: float) -> void:
	var cabin := Node3D.new()
	cabin.position = _grounded(pos)
	cabin.scale = Vector3.ONE * cabin_scale
	cabin.rotation.y = 0.24
	terrain.add_child(cabin)
	box(cabin, Vector3(0, 0.9, 0), Vector3(3.0, 1.8, 2.6), Color("c8b796"))
	box(cabin, Vector3(0, 0.55, 1.32), Vector3(0.55, 1.1, 0.06), Color("756c59"))
	for side in [-1, 1]:
		var roof := box(cabin, Vector3(side * 0.87, 2.05, 0), Vector3(2.15, 0.16, 3.1), Color("918c7a"))
		roof.rotation.z = side * -0.5
		box(cabin, Vector3(side * 0.9, 1.13, 1.33), Vector3(0.48, 0.54, 0.07), Color("57716b"))

func _draped_patch(center: Vector2, size: Vector2, color: Color, lift: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count_x := maxi(1, int(ceil(size.x / 0.35)))
	var count_z := maxi(1, int(ceil(size.y / 0.35)))
	for ix in range(count_x):
		for iz in range(count_z):
			var x0 := center.x - size.x * 0.5 + size.x * ix / count_x
			var x1 := center.x - size.x * 0.5 + size.x * (ix + 1) / count_x
			var z0 := center.y - size.y * 0.5 + size.y * iz / count_z
			var z1 := center.y - size.y * 0.5 + size.y * (iz + 1) / count_z
			var a := _grounded(Vector3(x0, lift, z0))
			var b := _grounded(Vector3(x1, lift, z0))
			var c := _grounded(Vector3(x1, lift, z1))
			var d := _grounded(Vector3(x0, lift, z1))
			_triangle(surface, a, b, c, color)
			_triangle(surface, a, c, d, color)
	_finish_surface(surface, "PicnicCloth")

func make_actor(kind: String, identity: String, second_herder := false) -> Node3D:
	var actor := Node3D.new()
	actor.name = identity
	add_child(actor)
	var body := Node3D.new()
	body.name = "Body"
	actor.add_child(body)
	match kind:
		"dog": _dog(body, identity == "maple")
		"sheep": _sheep(body, identity)
		"player": _herder(body, second_herder)
	return actor

func _dog(parent: Node3D, maple: bool) -> void:
	var coat := Color("b77d48") if maple else Color("d59b52")
	ball(parent, Vector3(0, 0.48, 0.10), Vector3(0.68, 0.65, 1.15), coat)
	ball(parent, Vector3(0, 0.64, -0.52), Vector3(0.72, 0.72, 0.61), coat)
	ball(parent, Vector3(0, 0.48, -0.25), Vector3(0.59, 0.51, 0.31), CREAM)
	ball(parent, Vector3(0, 0.54, -0.85), Vector3(0.45, 0.3, 0.34), CREAM)
	ball(parent, Vector3(0, 0.6, -1.01), Vector3(0.17, 0.12, 0.10), DARK)
	for side in [-1, 1]:
		var ear := cylinder(parent, Vector3(side * 0.25, 1.06, -0.48), 0.025, 0.18, 0.55, coat, 3)
		ear.rotation.z = side * -0.24
		ball(parent, Vector3(side * 0.23, 1.07, -0.58), Vector3(0.14, 0.27, 0.05), Color("e2b193"))
		ball(parent, Vector3(side * 0.23, 0.72, -0.78), Vector3(0.075, 0.085, 0.065), DARK)
		for z in [-0.25, 0.48]:
			box(parent, Vector3(side * 0.24, 0.17, z), Vector3(0.18, 0.29, 0.23), CREAM)
	var tail := ball(parent, Vector3(0, 0.68, 0.7), Vector3(0.26, 0.32, 0.34), CREAM)
	tail.name = "Tail"
	var collar := cylinder(parent, Vector3(0, 0.58, -0.42), 0.31, 0.31, 0.10, Color("729a97") if maple else Color("aa6970"))
	collar.rotation.x = PI / 2

func _sheep(parent: Node3D, identity: String) -> void:
	var wool := Color("f0e7d2") if identity.hash() % 3 == 0 else Color("fff4df")
	ball(parent, Vector3(0, 0.60, 0.08), Vector3(0.80, 0.85, 1.0), wool)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.70, -0.35)
	parent.add_child(head)
	for side in [-1, 1]:
		ball(parent, Vector3(side * 0.22, 0.79, 0.22), Vector3(0.5, 0.48, 0.65), wool)
		for z in [-0.23, 0.38]:
			box(parent, Vector3(side * 0.24, 0.21, z), Vector3(0.12, 0.36, 0.12), Color("766b58"))
		ball(head, Vector3(side * 0.27, 0.08, -0.07), Vector3(0.27, 0.13, 0.18), Color("8d7c65"))
	ball(head, Vector3(0, -0.04, -0.16), Vector3(0.42, 0.50, 0.45), Color("786c57"))
	ball(head, Vector3(0, 0.21, -0.02), Vector3(0.48, 0.3, 0.4), wool)
	ball(parent, Vector3(0, 0.65, 0.65), Vector3(0.23, 0.25, 0.28), wool)

func _herder(parent: Node3D, second: bool) -> void:
	var coat := Color("b67764") if second else Color("4f8580")
	for side in [-1, 1]:
		box(parent, Vector3(side * 0.19, 0.34, 0), Vector3(0.24, 0.57, 0.29), Color("526150"))
		ball(parent, Vector3(side * 0.19, 0.10, -0.10), Vector3(0.28, 0.21, 0.42), Color("705d49"))
		ball(parent, Vector3(side * 0.46, 0.94, 0), Vector3(0.21, 0.72, 0.26), coat)
	cylinder(parent, Vector3(0, 0.98, 0), 0.32, 0.43, 0.82, coat)
	ball(parent, Vector3(0, 1.64, 0), Vector3(0.58, 0.60, 0.58), Color("dca77d"))
	cylinder(parent, Vector3(0, 1.90, 0), 0.56, 0.56, 0.08, Color("e5cc95"))
	cylinder(parent, Vector3(0, 2.08, 0), 0.22, 0.34, 0.32, Color("d2b67e"))
	box(parent, Vector3(0, 1.45, -0.25), Vector3(0.22, 0.16, 0.13), Color("d3a15e"))

func _ring(parent: Node3D, pos: Vector3, color: Color, radius: float) -> Node3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - 0.035
	shape.outer_radius = radius + 0.035
	shape.rings = 24
	shape.ring_segments = 6
	var ring := mesh(parent, shape, pos + Vector3(0, 0.18, 0), color)
	ring.material_override = material(color, true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

func _build_preview() -> void:
	preview = Node3D.new()
	add_child(preview)
	for i in range(10):
		var sheep := make_actor("sheep", "preview_s%d" % i)
		sheep.reparent(preview)
		sheep.position = _grounded(Vector3(-6.5 + sin(i * 2.3) * 2.9, 0.03, -1.6 + cos(i * 1.6) * 2.7))
		sheep.rotation.y = i * 0.9
	for i in range(2):
		var dog := make_actor("dog", "mochi" if i == 0 else "maple")
		dog.reparent(preview)
		dog.position = _grounded(Vector3(-10 + i * 3, 0.03, 3.3))
		dog.rotation.y = -0.5 + i

func mark_destination(pos: Vector3) -> void:
	place_marker(destination, pos)
	destination.visible = true
	marker_age = 0.0

func ground_at(screen_pos: Vector2) -> Vector3:
	if landscape == "alpine_valley" and region_presentation != null:
		return region_presentation.ground_at(camera, screen_pos)
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.001:
		return Vector3.INF
	var previous_t := 0.0
	var previous_gap := origin.y - surface_height(origin.x, origin.z)
	for step in range(1, 601):
		var t := step * 0.25
		var point := origin + direction * t
		var gap := point.y - surface_height(point.x, point.z)
		if gap <= 0.0 and previous_gap > 0.0:
			var low := previous_t
			var high := t
			for iteration in range(15):
				var middle := (low + high) * 0.5
				var sample_point := origin + direction * middle
				if sample_point.y > surface_height(sample_point.x, sample_point.z):
					low = middle
				else:
					high = middle
			var result := origin + direction * ((low + high) * 0.5)
			if absf(result.x) > 17 or absf(result.z) > 11:
				return Vector3.INF
			if landscape == "oasis" and Vector2(result.x, result.z).distance_to(rock_center) < rock_radius:
				return Vector3.INF
			if landscape == "cloud" and not CloudNavigation.contains(Vector2(result.x, result.z), ridge):
				return Vector3.INF
			if landscape == "juniper" and not ShoreNavigation.contains(Vector2(result.x, result.z), shore):
				return Vector3.INF
			if landscape == "bellflower" and not CommonsNavigation.contains(Vector2(result.x, result.z), commons):
				return Vector3.INF
			result.y = surface_height(result.x, result.z)
			return result
		previous_t = t
		previous_gap = gap
	return Vector3.INF

func _process(delta: float) -> void:
	elapsed += delta
	if landscape == "alpine_valley" and region_presentation != null:
		region_presentation.advance(delta)
		region_presentation.apply_camera(camera, zoom)
		camera_focus = region_presentation.camera_focus
		desired_focus = region_presentation.desired_focus
	else:
		camera_focus = camera_focus.lerp(desired_focus, 1.0 - exp(-delta * 1.5))
		camera.position = camera_focus + CAMERA_OFFSET
		camera.look_at(camera_focus)
	marker_age += delta
	destination.visible = marker_age < 2.0
	destination.scale = Vector3.ONE * (1.0 + sin(marker_age * 5) * 0.1)
	if is_instance_valid(gate):
		gate.rotation.y = lerp_angle(gate.rotation.y, -1.45 if gate_open else 0.0, minf(delta * 4, 1.0))
