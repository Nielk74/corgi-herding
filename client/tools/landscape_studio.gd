extends Node3D
## Visual authoring stage only. Scale figures are not a simulated/saved herd.
## Never use these staged poses as evidence of navigation or gameplay success.

const Recipe = preload("res://scripts/landscape_recipe.gd")
const Builder = preload("res://scripts/landscape_scene_builder.gd")
const Lighting = preload("res://scripts/valley_lighting.gd")
const ActorFactory = preload("res://scripts/meadow.gd")
const ActorBatch = preload("res://scripts/actor_batch.gd")
const Life = preload("res://scripts/valley_life.gd")
static var recipe_index := 0
const RECIPE_PATHS := ["res://worlds/long_valley.recipe.json", "res://worlds/dry_wash.recipe.json"]
var profile: RefCounted
var camera: Camera3D
var figures: Array[Node3D] = []
var current_view := 0
var elapsed := 0.0
var caption: Label
var rendering_caption: Label
var next_report := 1.0

func _ready() -> void:
	var path: String = RECIPE_PATHS[recipe_index]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--recipe="):
			path = argument.trim_prefix("--recipe=")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var errors: Array[String] = Recipe.validate(data)
	if not errors.is_empty():
		push_error("Landscape studio: " + "; ".join(errors))
		return
	profile = Recipe.new(data)
	var terrain := Builder.load_or_build(profile)
	add_child(terrain)
	var life := Life.new()
	add_child(life)
	life.configure(profile, Rect2(Vector2(data.bounds[0], data.bounds[1]), Vector2(data.bounds[2] - data.bounds[0], data.bounds[3] - data.bounds[1])), int(data.seed))
	var rig := Lighting.new()
	rig.light_shafts_enabled = false
	add_child(rig)
	# Original legacy lighting stays untouched. This stage uses a sky gradient
	# with the same real-time raster sun; there is no indirect-light bake yet.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("648fac")
	sky_material.sky_horizon_color = Color("c2d1d2")
	sky_material.ground_horizon_color = Color("c2d1d2")
	sky_material.ground_bottom_color = Color("778979")
	var sky := Sky.new()
	sky.sky_material = sky_material
	rig.environment.sky = sky
	rig.environment.background_mode = Environment.BG_SKY
	rig.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	rig.environment.ambient_light_sky_contribution = 0.65
	rig.environment.fog_depth_begin = 105.0
	rig.environment.fog_depth_end = 480.0
	rig.environment.fog_depth_curve = 1.25
	rig.environment.fog_light_color = Color("a6bac5")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 32.0
	camera.current = true
	camera.far = 600.0
	add_child(camera)
	var factory := ActorFactory.new()
	for i in range(14):
		var kind := "player" if i < 2 else ("dog" if i < 4 else "sheep")
		var identity := ("mochi" if i == 2 else "maple") if i in [2, 3] else "ScaleFigure%d" % i
		var actor: Node3D = factory.make_actor(kind, identity, i == 1)
		ActorBatch.optimize(actor)
		factory.remove_child(actor)
		add_child(actor)
		figures.append(actor)
	factory.free()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(22, 28)
	layer.add_child(panel)
	caption = Label.new()
	caption.add_theme_color_override("font_color", Color("203c38"))
	caption.add_theme_font_size_override("font_size", 18)
	panel.add_child(caption)
	var next := Button.new()
	next.text = "Next viewpoint"
	next.custom_minimum_size = Vector2(210, 56)
	next.pressed.connect(func() -> void: current_view = (current_view + 1) % profile.route.size(); _show_view())
	panel.add_child(next)
	var biome := Button.new()
	biome.text = "See cactus country" if recipe_index == 0 else "Return to the Alps"
	biome.custom_minimum_size = Vector2(210, 56)
	biome.pressed.connect(func() -> void: recipe_index = (recipe_index + 1) % RECIPE_PATHS.size(); get_tree().reload_current_scene())
	panel.add_child(biome)
	rendering_caption = Label.new()
	rendering_caption.add_theme_color_override("font_color", Color("203c38"))
	rendering_caption.add_theme_font_size_override("font_size", 14)
	panel.add_child(rendering_caption)
	get_viewport().size_changed.connect(_show_view)
	_show_view()

func _show_view() -> void:
	var anchor: Vector3 = profile.route[current_view]
	var focus := Vector3(anchor.x, profile.surface_height(anchor.x, anchor.z) + 1.8, anchor.z - 6.0)
	camera.position = focus + Vector3(6, 14, 50)
	camera.look_at(focus)
	var size := get_viewport().get_visible_rect().size
	camera.size = maxf(32.0, 25.5 / (size.x / maxf(size.y, 1.0)))
	for i in figures.size():
		var offset := Vector2(-4.0 + (i % 5) * 1.6, 1.0 + floorf(i / 5.0) * 2.0)
		var x := anchor.x + offset.x
		var z := anchor.z + offset.y
		figures[i].position = Vector3(x, profile.surface_height(x, z), z)
	caption.text = "Landscape studio · %s\nView %d · scale figures, not gameplay" % [profile.data.id, current_view + 1]

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= next_report and rendering_caption != null:
		next_report = elapsed + 1.0
		rendering_caption.text = "%d draw calls · %d visible primitives\nRenderer counters, not phone performance" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	for i in figures.size():
		var body := figures[i].get_node("Body") as Node3D
		body.scale.y = 1.0 + sin(elapsed * 1.25 + i * 1.13) * 0.008
