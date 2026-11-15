extends Node3D
## Handling test pad: a flat gridded surface with a few cone layouts.
## The car starts at the origin facing -Z.

const GRID_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.15, 0.16, 0.18);
uniform vec3 line_color : source_color = vec3(0.34, 0.36, 0.40);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float cell) {
	vec2 c = p / cell;
	vec2 g = abs(fract(c - 0.5) - 0.5) / fwidth(c);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	float fine = grid(world_pos.xz, 10.0) * 0.5;
	float coarse = grid(world_pos.xz, 50.0);
	ALBEDO = mix(base_color, line_color, max(fine, coarse));
	ROUGHNESS = 0.95;
}
"""


func _ready() -> void:
	_build_sky_and_light()
	_build_ground()
	_build_cones()
	if "--capture" in OS.get_cmdline_user_args():
		add_child(load("res://tools/capture.gd").new())


func _build_sky_and_light() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.32, 0.6)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_bottom_color = Color(0.15, 0.16, 0.18)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.0025
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_ground() -> void:
	var shader := Shader.new()
	shader.code = GRID_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)


func _build_cones() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.28
	mesh.height = 0.75
	mesh.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.05)
	mat.roughness = 0.6

	var spots: Array[Vector3] = []
	# Slalom straight ahead: weave left and right of each cone.
	for i in 6:
		spots.append(Vector3(0.0, 0.0, -70.0 - 45.0 * i))
	# Two circles to hold a drift around, side by side for a figure of eight.
	for centre in [Vector3(70.0, 0.0, 60.0), Vector3(-70.0, 0.0, 60.0)]:
		for i in 20:
			var angle := TAU * i / 20.0
			spots.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * 28.0)
		spots.append(centre)

	for spot in spots:
		var cone := MeshInstance3D.new()
		cone.mesh = mesh
		cone.material_override = mat
		cone.position = spot + Vector3.UP * 0.375
		add_child(cone)
