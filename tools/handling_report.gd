extends SceneTree
## One-table summary of how the car handles, for tuning by numbers.
## Run with:  godot --headless --path . --script res://tools/handling_report.gd
## Optional, after "--":  car=muscle  to test a car from the roster, and
## setting=value pairs to override individual settings, e.g.  slip_damp=3000

const CarSim := preload("res://scripts/car/car_sim.gd")
const CarRoster := preload("res://scripts/car/car_roster.gd")
const DT := 1.0 / 60.0

var _overrides := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		if parts[0] == "car":
			var entry := CarRoster.find(parts[1])
			print("car: ", entry["name"])
			_overrides.merge(entry["setup"], true)
		else:
			_overrides[parts[0]] = parts[1].to_float()
	if not _overrides.is_empty():
		print("overrides: ", _overrides)

	# HOLD: is a held slide steady?
	var hold := _series([[4.0, true, 0.0], [8.0, true, 1.0]])
	var h: Array = hold.slice(240)
	var steady := _mean(h.slice(300))
	var late: Array = h.slice(180)
	print("\nHOLD   peak %5.1f  steady %5.1f  overshoot %3.0f%%  later wobble %4.1f..%4.1f  reach 80%% in %.2fs  press-to-10deg %.2fs" % [
		h.max(), steady, (h.max() / steady - 1.0) * 100.0, late.min(), late.max(),
		_first_above(h, 0.8 * steady), _first_above(h, 10.0),
	])
	var angles := PackedStringArray()
	for i in range(0, 480, 30):
		angles.append("%4.0f" % h[i])
	print("       angle every 0.5 s: ", " ".join(angles))

	# FEATHER: tap the key after a slide is established, at 50% and 75% duty.
	var feather_text := PackedStringArray()
	for duty in [0.5, 0.75]:
		var phases := [[4.0, true, 0.0], [2.5, true, 1.0]]
		for i in 16:
			phases.append([0.25 * (1.0 - duty), true, 0.0])
			phases.append([0.25 * duty, true, 1.0])
		var feather: Array = _series(phases).slice(390 + 120)
		feather_text.append("%d%% taps: mean %4.1f (%4.1f..%4.1f)" % [int(duty * 100), _mean(feather), feather.min(), feather.max()])
	print("FEATHER  ", "    ".join(feather_text))

	# LIFT-HOLD: lifting the throttle should end the slide even with Shift still held.
	var lift_hold: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], [2.0, false, 1.0]]).slice(390)
	print("LIFT with Shift still held: angle after 0.5 s %4.1f, 1.0 s %4.1f, 1.5 s %4.1f" % [lift_hold[30], lift_hold[60], lift_hold[90]])

	# RELEASE and LIFT: how fast does the slide end?
	var release: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], [3.0, true, 0.0]]).slice(390)
	var lift: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], [3.0, false, 0.0]]).slice(390)
	print("RELEASE on power: under 10 deg after %.2fs      LIFT and release: under 10 deg after %.2fs" % [
		_first_below(release, 10.0), _first_below(lift, 10.0),
	])

	# TAP: a short press should nudge the line, not start a slide.
	var tap: Array = _series([[4.0, true, 0.0], [0.15, true, 1.0], [2.0, true, 0.0]]).slice(240)
	print("TAP 0.15 s: peak angle %4.1f" % tap.max())

	# FLICK: opposite key for d seconds, then swap.
	var row := PackedStringArray()
	for d in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.5]:
		var s: Array = _series([[4.0, true, 0.0], [d, true, -1.0], [2.5, true, 1.0]], true)
		var from := 240 + int(round(d / DT))
		var after: Array = s.slice(from)
		row.append("%.1f:%2.0f/%2.0f%s" % [d, after.max(), _mean(after), "G" if _guard else ""])
	print("FLICK      (opposite-hold s : peak/mean angle over 2.5 s)  ", "  ".join(row))

	# TRANSITION: drift left, pause g seconds, drift right.
	row = PackedStringArray()
	for g in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8]:
		var s: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], [g, true, 0.0], [2.5, true, -1.0]], true)
		var from := 390 + int(round(g / DT))
		var after: Array = s.slice(from)
		row.append("%.1f:%2.0f/%2.0f%s" % [g, after.max(), _mean(after), "G" if _guard else ""])
	print("TRANSITION (pause s : peak/mean angle over 2.5 s)          ", "  ".join(row))

	# SPEED: steady hold angle and radius at different entry speeds.
	row = PackedStringArray()
	for run_up in [2.0, 3.0, 5.0, 9.0]:
		var sim := _make()
		for i in int(run_up / DT):
			sim.step(DT, true, 0.0, false)
		var entry: float = sim.speed
		var peak := 0.0
		for i in int(6.0 / DT):
			sim.step(DT, true, 1.0, false)
			peak = maxf(peak, absf(sim.slip_angle))
		var radius: float = sim.speed / maxf(absf(sim.yaw_rate), 0.01)
		row.append("in %2.0f m/s: peak %2.0f end %2.0f r %3.0fm v %2.0f" % [entry, rad_to_deg(peak), rad_to_deg(absf(sim.slip_angle)), radius, sim.speed])
	print("SPEED      ", "   ".join(row))
	quit()


var _guard := false


func _make() -> RefCounted:
	var sim := CarSim.new()
	for key in _overrides:
		sim.set(key, _overrides[key])
	return sim


## Runs the phases and returns |drift angle| in degrees for every tick.
func _series(phases: Array, track_guard := false) -> Array:
	var sim := _make()
	var out := []
	if track_guard:
		_guard = false
	for phase in phases:
		for i in int(round(phase[0] / DT)):
			sim.step(DT, phase[1], phase[2], false)
			out.append(rad_to_deg(absf(sim.slip_angle)))
			if track_guard and sim.guard_active:
				_guard = true
	return out


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1)


func _first_above(values: Array, level: float) -> float:
	for i in values.size():
		if values[i] >= level:
			return i * DT
	return -1.0


func _first_below(values: Array, level: float) -> float:
	for i in values.size():
		if values[i] < level:
			return i * DT
	return -1.0
