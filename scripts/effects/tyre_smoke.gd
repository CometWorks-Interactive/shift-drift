extends MultiMeshInstance3D
## Tyre smoke from the rear wheels, as a pool of soft camera-facing puffs.
## Hand-rolled instead of a particle node so the amount can follow how hard the
## car is sliding, and so it behaves the same in the browser renderer.

@export var car_path: NodePath = ^"../Car"

const POOL := 384
const RATE := 45.0            ## puffs per second per tyre in a full slide at about 30 km/h; more when faster
const LIFE := 1.5             ## s
const START_SIZE := 0.9       ## m
const END_SIZE := 4.2         ## m
const PLAIN := Color(0.93, 0.94, 0.96)
const KICKED := Color(1.0, 0.72, 0.38)   ## tint while a timed-throw kick is active
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0.0, -100.0, 0.0))

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

void vertex() {
	// Face the camera, keeping the instance's position and scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float soft = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * soft * soft;
}
"""

var _car: Node3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _strength := PackedFloat32Array()
var _colour := PackedColorArray()
var _alive := PackedByteArray()
var _next := 0
var _owed := [0.0, 0.0]       ## fractional puffs waiting to be spawned, per tyre
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_car = get_node(car_path)
	_car.was_reset.connect(clear)
	# Puffs are moved every rendered frame here, so they must not be interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-5000.0, -5.0, -5000.0), Vector3(10000.0, 30.0, 10000.0))

	_pos.resize(POOL)
	_vel.resize(POOL)
	_age.resize(POOL)
	_strength.resize(POOL)
	_colour.resize(POOL)
	_alive.resize(POOL)

	# A soft round blob that always faces the camera. The falloff is computed in
	# the shader, so there is no texture to load and no square edge to show.
	var shader := Shader.new()
	shader.code = PUFF_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 1  # draw over the skid marks
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = POOL
	multimesh = mm
	clear()


func clear() -> void:
	for i in POOL:
		_alive[i] = 0
		multimesh.set_instance_transform(i, HIDDEN)
	_owed = [0.0, 0.0]


func _physics_process(delta: float) -> void:
	# Smoke comes from sliding sideways and from spinning the wheels (a donut or a burnout).
	var slide: float = maxf(_car.sim.slide, _car.sim.wheelspin)
	if slide <= 0.0:
		_owed = [0.0, 0.0]
		return
	var kick: float = _car.sim.kick if _car.sim.kick_gain > 0.0 else 0.0
	var colour := PLAIN.lerp(KICKED, clampf(kick * 1.3, 0.0, 1.0))
	var car_velocity: Vector3 = _car.world_velocity()
	for tyre in 2:
		# Faster cars cover more ground per second, so they need more puffs to leave an unbroken trail.
		_owed[tyre] += RATE * slide * (0.6 + _car.sim.speed / 22.0) * delta
		while _owed[tyre] >= 1.0:
			_owed[tyre] -= 1.0
			_spawn(_car.rear_contact(-1.0 if tyre == 0 else 1.0), car_velocity, slide, colour)


func _spawn(at: Vector3, car_velocity: Vector3, slide: float, colour: Color) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	_alive[i] = 1
	_age[i] = 0.0
	_strength[i] = lerpf(0.28, 0.6, slide)
	_colour[i] = colour
	_pos[i] = at + Vector3(_rng.randf_range(-0.2, 0.2), 0.25, _rng.randf_range(-0.2, 0.2))
	# Smoke is dragged along a little by the car, then hangs and rises.
	_vel[i] = car_velocity * 0.22 + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(0.8, 1.8), _rng.randf_range(-1.2, 1.2))


func _process(delta: float) -> void:
	var drag := exp(-2.0 * delta)
	for i in POOL:
		if _alive[i] == 0:
			continue
		_age[i] += delta
		var t := _age[i] / LIFE
		if t >= 1.0:
			_alive[i] = 0
			multimesh.set_instance_transform(i, HIDDEN)
			continue
		_vel[i] = Vector3(_vel[i].x * drag, _vel[i].y, _vel[i].z * drag)
		_pos[i] += _vel[i] * delta
		var size := lerpf(START_SIZE, END_SIZE, 1.0 - (1.0 - t) * (1.0 - t))
		# Keep the whole puff above the ground, or the ground cuts a hard line through it.
		var at := Vector3(_pos[i].x, maxf(_pos[i].y, size * 0.44), _pos[i].z)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)), at))
		# Quick fade in, long fade out.
		var alpha := _strength[i] * minf(t * 12.0, 1.0) * (1.0 - t) * (1.0 - t)
		var c := _colour[i]
		multimesh.set_instance_color(i, Color(c.r, c.g, c.b, alpha))
