class_name ValleyLighting
extends Node3D
## Raster sunlight, contact occlusion and two decorative light shafts.
## Godot 4.6 Compatibility supports SSAO; this is not hardware ray tracing.

const SHAFT_SHADER: Shader = preload("res://shaders/valley_light_shaft.gdshader")

@export var light_shafts_enabled := true

var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	name = "ValleyLighting"
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a9bdc6")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a7bfd8")
	environment.ambient_light_energy = 0.27
	environment.ambient_light_sky_contribution = 0.0
	# The Compatibility scene buffer is LDR. Leave headroom for white sheep
	# instead of increasing exposure to compensate for a dim ambient fill.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.045
	environment.adjustment_saturation = 1.02
	# Small-radius, half-resolution SSAO anchors animals and rocks. No SSIL,
	# screen-space reflections, volumetric fog, or real-time global illumination.
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 0.8
	environment.ssao_power = 1.15
	environment.ssao_detail = 0.2
	environment.ssao_light_affect = 0.08
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 55.0, 85.0
	)
	# Start beyond the playable foreground so haze separates the far ridges
	# without washing out the dogs, sheep, gate, and nearby grazing terraces.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 62.0
	environment.fog_depth_end = 145.0
	environment.fog_depth_curve = 1.6
	environment.fog_density = 0.18
	environment.fog_light_color = Color("a9bbc5")
	environment.fog_light_energy = 0.8
	environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ValleyEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-43, -28, 0)
	sun.light_color = Color("fff0d8")
	sun.light_energy = 0.80
	sun.light_specular = 0.35
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.86
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.6
	# A single orthogonal map keeps shadow rendering bounded on phones.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 82.0
	sun.directional_shadow_fade_start = 0.86
	add_child(sun)
	if light_shafts_enabled:
		_add_light_shaft(Vector3(-11, 8.5, -11), Vector2(3.6, 19), 0.045)
		_add_light_shaft(Vector3(6, 9, -18), Vector2(2.6, 17), 0.032)

func _add_light_shaft(center: Vector3, size: Vector2, opacity: float) -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "SoftSunShaft"
	var quad := QuadMesh.new()
	quad.size = size
	shaft.mesh = quad
	shaft.position = center
	# Match the light direction while presenting a broad side to the fixed view.
	var toward_sun := sun.basis.z.normalized()
	var view_direction := Vector3(8, 28, 38).normalized()
	var side := toward_sun.cross(view_direction).normalized()
	shaft.basis = Basis(side, toward_sun, side.cross(toward_sun).normalized())
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHAFT_SHADER
	material.set_shader_parameter("shaft_color", Color("ffe6b8"))
	material.set_shader_parameter("opacity", opacity)
	shaft.material_override = material
	add_child(shaft)
