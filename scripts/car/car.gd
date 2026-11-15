extends Node3D
## The player's car: reads the three keys, steps the drift model, and moves a
## placeholder body. Everything moves in _physics_process so physics
## interpolation can smooth it.

const CarSim := preload("res://scripts/car/car_sim.gd")

## Emitted when the car is put back at the start, so effects can clear themselves.
signal was_reset

const MAX_ROLL := deg_to_rad(7.0)
const MAX_PITCH := deg_to_rad(2.5)
const TRACK_HALF := 0.85
const WHEEL_RADIUS := 0.33

var sim := CarSim.new()

# Input state. Keys are tracked by hand because Left and Right Shift are one
# action as far as Godot's input map is concerned.
var _left_keys := {}
var _right_keys := {}
var _throttle_keys := {}
var _handbrake_keys := {}
var _latest_side := 0.0

# Set by tests to drive the car without a keyboard.
var override_inputs := false
var override_throttle := false
var override_lean := 0.0
var override_handbrake := false

var throttle := false
var lean := 0.0
var handbrake := false

var _body: Node3D
var _front_left: Node3D
var _front_right: Node3D
var _roll := 0.0
var _pitch := 0.0


func _ready() -> void:
	_build_placeholder()
	reset_car()


func reset_car() -> void:
	sim.reset()
	_roll = 0.0
	_pitch = 0.0
	_apply_transform()
	reset_physics_interpolation()
	was_reset.emit()


func _notification(what: int) -> void:
	# Browsers and the OS can swallow key-up events when focus is lost.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_left_keys.clear()
		_right_keys.clear()
		_throttle_keys.clear()
		_handbrake_keys.clear()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var id := "%d:%d" % [code, key.location]
	match code:
		KEY_SHIFT:
			if key.location == KEY_LOCATION_RIGHT:
				_set_side(_right_keys, id, key.pressed, -1.0)
			else:
				_set_side(_left_keys, id, key.pressed, 1.0)
		KEY_A, KEY_LEFT:
			_set_side(_left_keys, id, key.pressed, 1.0)
		KEY_D, KEY_RIGHT:
			_set_side(_right_keys, id, key.pressed, -1.0)
		KEY_SPACE, KEY_W, KEY_UP:
			_set_key(_throttle_keys, id, key.pressed)
		KEY_S, KEY_DOWN:
			_set_key(_handbrake_keys, id, key.pressed)
		KEY_R:
			if key.pressed:
				reset_car()


func _set_key(keys: Dictionary, id: String, pressed: bool) -> void:
	if pressed:
		keys[id] = true
	else:
		keys.erase(id)


func _set_side(keys: Dictionary, id: String, pressed: bool, side: float) -> void:
	_set_key(keys, id, pressed)
	if pressed:
		_latest_side = side


func _physics_process(delta: float) -> void:
	if override_inputs:
		throttle = override_throttle
		lean = override_lean
		handbrake = override_handbrake
	else:
		throttle = not _throttle_keys.is_empty()
		handbrake = not _handbrake_keys.is_empty()
		var l := not _left_keys.is_empty()
		var r := not _right_keys.is_empty()
		# Both held: the most recent press wins. Windows browsers drop a Shift
		# key-up while the other Shift is held, so "both" must never mean anything.
		if l and r:
			lean = _latest_side
		elif l:
			lean = 1.0
		elif r:
			lean = -1.0
		else:
			lean = 0.0

	sim.step(delta, throttle, lean, handbrake)
	_update_body_motion(delta)
	_apply_transform()


func _update_body_motion(delta: float) -> void:
	# The body leans the instant a key goes down, even though the turn lags,
	# then the real cornering force takes over.
	var at_speed := smoothstep(2.0, 14.0, sim.speed)
	var key_part := lean * at_speed
	var force_part := clampf(sim.lat_accel / 10.0, -1.2, 1.2)
	var roll_target := -MAX_ROLL * (0.45 * key_part + 0.55 * force_part)
	var pitch_target := MAX_PITCH * clampf(sim.long_accel / 6.0, -1.5, 1.5)
	var blend := 1.0 - exp(-10.0 * delta)
	_roll = lerpf(_roll, roll_target, blend)
	_pitch = lerpf(_pitch, pitch_target, blend)


func _apply_transform() -> void:
	position = Vector3(-sim.pos.y, 0.0, -sim.pos.x)
	rotation.y = sim.psi
	if _body:
		_body.rotation = Vector3(_pitch, 0.0, _roll)
		_front_left.rotation.y = sim.steer
		_front_right.rotation.y = sim.steer


## Where a rear tyre touches the ground, in world space. side: -1 left, +1 right.
func rear_contact(side: float) -> Vector3:
	return position + Basis(Vector3.UP, sim.psi) * Vector3(side * TRACK_HALF, 0.0, sim.cg_to_rear)


## The car's velocity in world space.
func world_velocity() -> Vector3:
	return Vector3(-sim.vel.y, 0.0, -sim.vel.x)


## Direction of travel as a Godot yaw angle. Falls back to the heading when slow.
func travel_yaw() -> float:
	if sim.speed < 0.5:
		return sim.psi
	return atan2(sim.vel.y, sim.vel.x)


func _build_placeholder() -> void:
	_body = Node3D.new()
	add_child(_body)

	var paint := _material(Color(0.86, 0.16, 0.2), 0.35)
	var glass := _material(Color(0.07, 0.09, 0.12), 0.15)
	var dark := _material(Color(0.06, 0.06, 0.07), 0.8)
	var head := _material(Color(1.0, 0.96, 0.8), 0.3, 1.5)
	var tail := _material(Color(1.0, 0.1, 0.1), 0.3, 1.2)

	# Forward is -Z.
	_box(_body, Vector3(1.8, 0.45, 4.3), Vector3(0, 0.55, 0.05), paint)
	_box(_body, Vector3(1.55, 0.42, 2.0), Vector3(0, 0.98, 0.35), glass)
	_box(_body, Vector3(1.56, 0.06, 1.7), Vector3(0, 1.2, 0.35), paint)
	_box(_body, Vector3(1.7, 0.05, 0.35), Vector3(0, 1.0, 2.0), paint)       # spoiler
	_box(_body, Vector3(0.08, 0.2, 0.08), Vector3(0.6, 0.88, 2.0), dark)
	_box(_body, Vector3(0.08, 0.2, 0.08), Vector3(-0.6, 0.88, 2.0), dark)
	_box(_body, Vector3(1.84, 0.12, 4.34), Vector3(0, 0.36, 0.05), dark)     # sill
	for x in [-0.6, 0.6]:
		_box(_body, Vector3(0.4, 0.12, 0.05), Vector3(x, 0.62, -2.1), head)
		_box(_body, Vector3(0.4, 0.12, 0.05), Vector3(x, 0.62, 2.2), tail)

	_front_left = _wheel(Vector3(-TRACK_HALF, WHEEL_RADIUS, -sim.cg_to_front), dark)
	_front_right = _wheel(Vector3(TRACK_HALF, WHEEL_RADIUS, -sim.cg_to_front), dark)
	_wheel(Vector3(-TRACK_HALF, WHEEL_RADIUS, sim.cg_to_rear), dark)
	_wheel(Vector3(TRACK_HALF, WHEEL_RADIUS, sim.cg_to_rear), dark)


func _material(color: Color, roughness: float, glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = at
	parent.add_child(inst)


func _wheel(at: Vector3, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	add_child(pivot)
	var mesh := CylinderMesh.new()
	mesh.top_radius = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.height = 0.26
	mesh.radial_segments = 16
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.rotation.z = PI / 2.0
	pivot.add_child(inst)
	return pivot
