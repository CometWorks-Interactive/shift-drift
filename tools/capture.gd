extends Node
## Drives the car through a scripted run and saves screenshots, then quits.
## Run with:  godot --path . -- --capture --out=/some/folder [--car=muscle] [--drive=donut]

## Each drive is a list of [duration_s, throttle, lean, handbrake] and the
## seconds into the run at which to save a frame.
const DRIVES := {
	# A flick, a swap to the other side with no pause, then hands off.
	"flick": {
		"phases": [
			[4.0, true, 0.0, false],
			[0.4, true, -1.0, false],
			[2.15, true, 1.0, false],
			[2.0, true, -1.0, false],
			[1.5, true, 0.0, false],
		],
		"shots": [3.9, 4.85, 5.7, 6.5, 7.6, 8.4, 9.9],
	},
	# Power and Shift held from a standstill.
	"donut": {
		"phases": [[7.0, true, 1.0, false]],
		"shots": [1.5, 3.0, 4.5, 6.0, 6.9],
	},
	# A held slide from speed.
	"hold": {
		"phases": [[3.0, true, 0.0, false], [5.0, true, 1.0, false]],
		"shots": [2.9, 4.0, 5.5, 7.0, 7.9],
	},
}

var _phases: Array = DRIVES["flick"]["phases"]
var _shots: Array = DRIVES["flick"]["shots"]
var _car: Node3D
var _time := 0.0
var _shot := 0
var _saved := 0
var _out := "user://"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--drive=") and DRIVES.has(arg.trim_prefix("--drive=")):
			_phases = DRIVES[arg.trim_prefix("--drive=")]["phases"]
			_shots = DRIVES[arg.trim_prefix("--drive=")]["shots"]
	_car = get_node("../Car")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--car="):
			_car.set_car(arg.trim_prefix("--car="))
	_car.override_inputs = true


func _physics_process(delta: float) -> void:
	_time += delta
	var t := 0.0
	var active: Array = [0.0, false, 0.0, false]
	for phase in _phases:
		t += phase[0]
		if _time < t:
			active = phase
			break
	_car.override_throttle = active[1]
	_car.override_lean = active[2]
	_car.override_handbrake = active[3]

	if _shot < _shots.size() and _time >= _shots[_shot]:
		_save(_shot)
		_shot += 1
	elif _shot >= _shots.size():
		if _saved == 0:
			print("no screenshots saved: the window drew %d frames. Is it hidden, or the display asleep?" % Engine.get_frames_drawn())
		get_tree().quit()


func _save(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out.path_join("shot_%d.png" % index)
	image.save_png(path)
	_saved += 1
	print("saved ", path, "  speed ", snappedf(_car.sim.speed, 0.1), "  slip ", snappedf(rad_to_deg(_car.sim.slip_angle), 0.1))
