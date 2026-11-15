extends CanvasLayer
## Test-pad readouts and a live tuning list.
## Tab selects a setting, - and = change it, Backspace restores it.

@export var car_path: NodePath = ^"../Car"

## [property on the sim, step, label]
const TUNABLES := [
	["d_frac", 0.02, "lean steer (held drift angle)"],
	["power_grip", 0.02, "rear grip on power"],
	["k_caster", 0.05, "front self-steer (forgiveness)"],
	["slip_damp", 250.0, "slide steadiness"],
	["lat_freq", 0.1, "weight speed, Hz (car's tempo)"],
	["lat_damping", 0.05, "weight bounce (lower = more swing)"],
	["w_break", 0.05, "swing needed for a kick"],
	["kick_gain", 0.05, "kick strength"],
	["kick_time", 0.25, "kick duration, s"],
	["mu_front", 0.05, "front grip"],
	["mu_rear", 0.05, "rear grip"],
	["steer_lock", 0.05, "steering lock, rad (angle ceiling)"],
	["engine_force", 500.0, "engine force"],
]

var _car: Node3D
var _defaults := {}
var _selected := 0
var _readout: Label
var _tuning: Label
var _help: Label
var _gauge: Control
var _peak_slip := 0.0


func _ready() -> void:
	_car = get_node(car_path)
	for t in TUNABLES:
		_defaults[t[0]] = _car.sim.get(t[0])

	_readout = _label(Vector2(16, 12), 20)
	_tuning = _label(Vector2(16, 250), 14)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	_tuning.add_theme_font_override("font", mono)
	_help = _label(Vector2(16, 0), 15)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 16
	_help.offset_top = -84
	_help.offset_bottom = -12
	_help.text = "Space  throttle      Left / Right Shift  throw weight   (A / D and arrows also work)\nS  handbrake (test only)      R  reset\nTab  next setting      -  =  change      Backspace  restore"

	_gauge = Control.new()
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gauge.offset_left = -256
	_gauge.offset_right = -16
	_gauge.offset_top = 16
	_gauge.offset_bottom = 176
	_gauge.draw.connect(_draw_gauge)
	add_child(_gauge)


func _label(at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var t: Array = TUNABLES[_selected]
	match code:
		KEY_TAB:
			if not key.echo:
				_selected = (_selected + 1) % TUNABLES.size()
		KEY_MINUS:
			_car.sim.set(t[0], _car.sim.get(t[0]) - t[1])
		KEY_EQUAL:
			_car.sim.set(t[0], _car.sim.get(t[0]) + t[1])
		KEY_BACKSPACE:
			_car.sim.set(t[0], _defaults[t[0]])
		KEY_R:
			_peak_slip = 0.0


func _process(_delta: float) -> void:
	var sim = _car.sim
	var slip := rad_to_deg(absf(sim.slip_angle))
	_peak_slip = maxf(_peak_slip, slip)
	var state := "grip"
	if sim.guard_active:
		state = "SPIN GUARD"
	elif sim.slide > 0.0:
		state = "DRIFT"
	# A kick is the reward for a well-timed weight throw.
	if sim.kick > 0.05:
		state += "   KICK %d%%" % int(round(sim.kick * 100.0))
	_readout.text = "%3d km/h\nangle %4.1f°   peak %4.1f°\nyaw %+5.0f °/s\n%s" % [
		int(round(sim.speed * 3.6)), slip, _peak_slip, rad_to_deg(sim.yaw_rate), state,
	]

	var lines := PackedStringArray()
	for i in TUNABLES.size():
		var t: Array = TUNABLES[i]
		var value: float = sim.get(t[0])
		var changed := "" if is_equal_approx(value, _defaults[t[0]]) else "  *"
		lines.append("%s %-36s %8.2f%s" % [">" if i == _selected else " ", t[2], value, changed])
	_tuning.text = "\n".join(lines)
	_gauge.queue_redraw()


func _draw_gauge() -> void:
	# Where the car's weight is: left/right from the Shift keys, front/back from the throttle.
	var sim = _car.sim
	var size := _gauge.size
	var centre := size / 2.0
	var reach := size.x / 2.0 - 14.0  # room for a swing of about 2
	_gauge.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	_gauge.draw_line(Vector2(centre.x, 8), Vector2(centre.x, size.y - 8), Color(1, 1, 1, 0.2), 1.0)
	_gauge.draw_line(Vector2(8, centre.y), Vector2(size.x - 8, centre.y), Color(1, 1, 1, 0.2), 1.0)
	var unit := reach / 2.0
	_gauge.draw_arc(centre, unit, 0.0, TAU, 48, Color(1, 1, 1, 0.2), 1.0)
	# Swing the weight past these marks to earn a kick.
	for side in [-1.0, 1.0]:
		var x: float = centre.x + side * sim.w_break * unit
		_gauge.draw_line(Vector2(x, centre.y - 22), Vector2(x, centre.y + 22), Color(1.0, 0.75, 0.2, 0.8), 2.0)
	# Screen left is the car's left, screen up is the car's front. A weight of 1.0 sits on the ring.
	var dot := centre + Vector2(-sim.wy, sim.wx * 0.5) * unit
	var colour := Color(1.0, 0.75, 0.2) if absf(sim.wy) > sim.w_break else Color(0.4, 0.85, 1.0)
	_gauge.draw_circle(dot, 9.0, colour)
	# Key state along the bottom.
	var on := Color(1, 1, 1, 0.95)
	var off := Color(1, 1, 1, 0.2)
	_gauge.draw_rect(Rect2(10, size.y - 16, 46, 8), on if _car.lean > 0.0 else off)
	_gauge.draw_rect(Rect2(size.x - 56, size.y - 16, 46, 8), on if _car.lean < 0.0 else off)
	_gauge.draw_rect(Rect2(centre.x - 23, size.y - 16, 46, 8), on if _car.throttle else off)
