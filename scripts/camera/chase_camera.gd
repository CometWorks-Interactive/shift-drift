extends Camera3D
## Chase camera that follows the direction of travel, not the nose, so the car
## visibly hangs sideways in a drift. At low speed it follows the nose instead.

@export var car_path: NodePath = ^"../Car"

const MAX_OFFSET := 1.2                 ## rad the view may sit away from the nose
const TURN_RATE := TAU                  ## rad/s cap, so a spin never whips the view
const FOLLOW := 5.0                     ## how quickly the view settles

var _car: Node3D
var _yaw := 0.0
var _speed_blend := 0.0


func _ready() -> void:
	_car = get_node(car_path)
	top_level = true
	# The camera moves every rendered frame, so it must not be interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_yaw = _car.sim.psi
	_place(1.0)


func snap() -> void:
	_yaw = _car.sim.psi
	_speed_blend = 0.0


func _process(delta: float) -> void:
	_place(delta)


func _place(delta: float) -> void:
	var sim = _car.sim
	# How much to trust the direction of travel: not at all when crawling.
	var trust := smoothstep(5.0, 12.0, sim.speed)
	var offset := clampf(wrapf(_car.travel_yaw() - sim.psi, -PI, PI), -MAX_OFFSET, MAX_OFFSET)
	var target: float = sim.psi + trust * offset
	var diff := wrapf(target - _yaw, -PI, PI)
	var turn := clampf(diff * (1.0 - exp(-FOLLOW * delta)), -TURN_RATE * delta, TURN_RATE * delta)
	_yaw += turn

	_speed_blend = lerpf(_speed_blend, clampf(sim.speed / 28.0, 0.0, 1.0), 1.0 - exp(-3.0 * delta))
	fov = lerpf(62.0, 78.0, _speed_blend)
	var distance := lerpf(9.5, 7.5, _speed_blend)
	var height := lerpf(4.6, 3.8, _speed_blend)

	var car_pos := _car.get_global_transform_interpolated().origin
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	global_position = car_pos - forward * distance + Vector3.UP * height
	look_at(car_pos + forward * 3.0 + Vector3.UP * 0.8, Vector3.UP)
