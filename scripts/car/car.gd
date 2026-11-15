extends Node3D
## The player's car: reads the three keys, steps the drift model, and moves the
## visible car. Everything moves in _physics_process so physics interpolation
## can smooth it.
##
## The visible car comes from the purchased model pack when it is installed
## (see car_library.gd). Without the pack it is built from boxes.

const CarSim := preload("res://scripts/car/car_sim.gd")
const CarLibrary := preload("res://scripts/car/car_library.gd")

## Emitted when the car is put back at the start, so effects can clear themselves.
signal was_reset
## Emitted after the visible model changes.
signal model_changed

const MAX_ROLL := deg_to_rad(7.0)
const MAX_PITCH := deg_to_rad(2.5)
const MODEL_SCALE := 0.8          ## the pack's cars are about 25% larger than life
const WHEELSPIN_SPEED := 30.0     ## m/s the rear tyres spin up to in a full slide on power

## Which pack model to show, for example "sports_01". Ignored if the pack is missing.
@export var model_id := "sports_01"

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

var _visual: Node3D               ## everything visible, rebuilt when the model changes
var _body: Node3D                 ## the part that rolls and pitches
var _steer_pivots: Array[Node3D] = []
var _spin_pivots: Array[Node3D] = []
var _spin_is_rear: Array[bool] = []
var _spin_radius: Array[float] = []
var _rear_left := Vector3(-0.85, 0.0, 1.3)    ## rear tyre contact points, car space
var _rear_right := Vector3(0.85, 0.0, 1.3)
var _roll := 0.0
var _pitch := 0.0


func _ready() -> void:
	_build_visual()
	reset_car()


func reset_car() -> void:
	sim.reset()
	_roll = 0.0
	_pitch = 0.0
	_apply_transform()
	reset_physics_interpolation()
	was_reset.emit()


## Swap the visible car. Handling is not changed.
func set_model(id: String) -> void:
	model_id = id
	_build_visual()
	_apply_transform()
	reset_physics_interpolation()
	model_changed.emit()


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
	_spin_wheels(delta)
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


func _spin_wheels(delta: float) -> void:
	# Rear tyres spin faster than the road in a slide on power.
	var rear_speed := maxf(sim.vx, lerpf(sim.vx, WHEELSPIN_SPEED, sim.pw * sim.slide))
	for i in _spin_pivots.size():
		var surface_speed := rear_speed if _spin_is_rear[i] else sim.vx
		_spin_pivots[i].rotation.x = wrapf(_spin_pivots[i].rotation.x + surface_speed * delta / _spin_radius[i], -PI, PI)


func _apply_transform() -> void:
	position = Vector3(-sim.pos.y, 0.0, -sim.pos.x)
	rotation.y = sim.psi
	if _body:
		_body.rotation = Vector3(_pitch, 0.0, _roll)
	for pivot in _steer_pivots:
		pivot.rotation.y = sim.steer


## Where a rear tyre touches the ground, in world space. side: -1 left, +1 right.
func rear_contact(side: float) -> Vector3:
	return position + Basis(Vector3.UP, sim.psi) * (_rear_left if side < 0.0 else _rear_right)


## The car's velocity in world space.
func world_velocity() -> Vector3:
	return Vector3(-sim.vel.y, 0.0, -sim.vel.x)


## Direction of travel as a Godot yaw angle. Falls back to the heading when slow.
func travel_yaw() -> float:
	if sim.speed < 0.5:
		return sim.psi
	return atan2(sim.vel.y, sim.vel.x)


# --- Building the visible car ---

func _build_visual() -> void:
	if _visual:
		remove_child(_visual)
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	_body = Node3D.new()
	_visual.add_child(_body)
	_steer_pivots.clear()
	_spin_pivots.clear()
	_spin_is_rear.clear()
	_spin_radius.clear()

	var model: Node3D = CarLibrary.instantiate(model_id) if CarLibrary.available() else null
	if model:
		_build_from_model(model)
	else:
		_build_placeholder()


func _build_from_model(model: Node3D) -> void:
	# Pack cars face +Z; ours faces -Z. Two holders with the same turn and scale:
	# one rides on the body (rolls and pitches), one stays flat for the wheels.
	var body_holder := _holder(_body)
	var wheel_holder := _holder(_visual)
	body_holder.add_child(model)

	# Find the wheels and brake discs, with their positions relative to the model.
	var wheels: Array[Node3D] = []
	var discs: Array[Node3D] = []
	var places := {}
	_collect(model, Transform3D.IDENTITY, wheels, discs, places)

	var rear: Array[Vector3] = []
	var pivot_for := {}
	for wheel in wheels:
		var place: Transform3D = places[wheel]
		var steer := Node3D.new()
		steer.position = place.origin
		wheel_holder.add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		wheel.get_parent().remove_child(wheel)
		spin.add_child(wheel)
		wheel.transform = Transform3D(place.basis, Vector3.ZERO)
		pivot_for[wheel] = steer

		var is_rear := place.origin.z < 0.0
		if not is_rear:
			_steer_pivots.append(steer)
		else:
			rear.append(place.origin)
		_spin_pivots.append(spin)
		_spin_is_rear.append(is_rear)
		var mesh_node := wheel as MeshInstance3D
		var radius := 0.4
		if mesh_node and mesh_node.mesh:
			var size := mesh_node.mesh.get_aabb().size
			radius = maxf(maxf(size.x, size.y), size.z) * 0.5
		_spin_radius.append(maxf(radius * MODEL_SCALE, 0.1))

	# Each brake disc follows the steering of its nearest wheel but does not spin.
	for disc in discs:
		var place: Transform3D = places[disc]
		var nearest: Node3D = null
		var best := 0.6
		for wheel in wheels:
			var gap: float = (places[wheel] as Transform3D).origin.distance_to(place.origin)
			if gap < best:
				best = gap
				nearest = wheel
		if nearest == null:
			continue
		var steer: Node3D = pivot_for[nearest]
		disc.get_parent().remove_child(disc)
		steer.add_child(disc)
		disc.transform = Transform3D(place.basis, place.origin - steer.position)

	# Skid marks and smoke come from the outermost rear tyre on each side.
	if not rear.is_empty():
		var left := rear[0]
		var right := rear[0]
		for point in rear:
			if point.x > left.x:
				left = point      # model +X is the car's left once turned round
			if point.x < right.x:
				right = point
		_rear_left = Vector3(-left.x, 0.0, -left.z) * MODEL_SCALE
		_rear_right = Vector3(-right.x, 0.0, -right.z) * MODEL_SCALE


func _holder(parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.rotation.y = PI
	holder.scale = Vector3.ONE * MODEL_SCALE
	parent.add_child(holder)
	return holder


func _collect(node: Node, parent_place: Transform3D, wheels: Array[Node3D], discs: Array[Node3D], places: Dictionary) -> void:
	for child in node.get_children():
		var part := child as Node3D
		if part == null:
			continue
		var place := parent_place * part.transform
		var part_name := String(part.name).to_lower()
		if part.visible and part_name.contains("wheel") and not part_name.contains("steering"):
			wheels.append(part)
			places[part] = place
		elif part.visible and part_name.contains("brake"):
			discs.append(part)
			places[part] = place
		else:
			_collect(part, place, wheels, discs, places)


func _build_placeholder() -> void:
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

	var radius := 0.33
	for side in [-1.0, 1.0]:
		_placeholder_wheel(Vector3(side * 0.85, radius, -sim.cg_to_front), radius, dark, false)
		_placeholder_wheel(Vector3(side * 0.85, radius, sim.cg_to_rear), radius, dark, true)
	_rear_left = Vector3(-0.85, 0.0, sim.cg_to_rear)
	_rear_right = Vector3(0.85, 0.0, sim.cg_to_rear)


func _placeholder_wheel(at: Vector3, radius: float, mat: Material, is_rear: bool) -> void:
	var steer := Node3D.new()
	steer.position = at
	_visual.add_child(steer)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.26
	mesh.radial_segments = 16
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.rotation.z = PI / 2.0
	steer.add_child(inst)
	if not is_rear:
		_steer_pivots.append(steer)


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
