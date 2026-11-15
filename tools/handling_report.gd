extends SceneTree
## One-table summary of how a car handles, for tuning by numbers.
## Run with:  godot --headless --path . --script res://tools/handling_report.gd
## Optional, after "--":  car=muscle  to test a car from the roster, and
## setting=value pairs to override individual settings, e.g.  d_frac=0.6
##
## Angles are drift angles in degrees. "SPIN" means the car went past 100
## degrees, which is a spin. In the tests that drift left, "other side" means
## the car swung back past straight.

const CarSim := preload("res://scripts/car/car_sim.gd")
const CarRoster := preload("res://scripts/car/car_roster.gd")
const DT := 1.0 / 60.0
const SPIN := 100.0

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
		print("settings: ", _overrides)

	_straight()

	# HOLD: is a held slide steady?
	var h: Array = _mag(_series([[4.0, true, 0.0], [8.0, true, 1.0]]).slice(240))
	var steady := _mean(h.slice(300))
	var late: Array = h.slice(180)
	print("HOLD   peak %5.1f  steady %5.1f  later wobble %4.1f..%4.1f  press-to-10deg %.2fs  reach 30deg %.2fs%s" % [
		h.max(), steady, late.min(), late.max(), _first_above(h, 10.0), _first_above(h, 30.0), _flag(h),
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
		var feather: Array = _mag(_series(phases).slice(390 + 120))
		feather_text.append("%d%% taps: mean %4.1f (%4.1f..%4.1f)%s" % [int(duty * 100), _mean(feather), feather.min(), feather.max(), _flag(feather)])
	print("FEATHER  ", "    ".join(feather_text))

	# Ending a slide. The car drifts left (negative angles); positive = swung to the other side.
	_ending("RELEASE  Shift off, power on  ", [3.0, true, 0.0])
	_ending("LIFT     power off, Shift off ", [3.0, false, 0.0])
	_ending("LIFT     power off, Shift held", [3.0, false, 1.0])

	# TAP: a short press should nudge the line, not start a slide.
	var tap: Array = _mag(_series([[4.0, true, 0.0], [0.15, true, 1.0], [2.0, true, 0.0]]).slice(240))
	print("TAP 0.15 s: peak angle %4.1f" % tap.max())

	# FLICK: opposite key for d seconds, then swap.
	var row := PackedStringArray()
	for d in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.5]:
		var after: Array = _mag(_series([[4.0, true, 0.0], [d, true, -1.0], [2.5, true, 1.0]]).slice(240 + int(round(d / DT))))
		row.append(_cell("%.1f" % d, after))
	print("FLICK      (opposite-hold s : peak/mean angle over 2.5 s)  ", "  ".join(row))

	# TRANSITION: drift left, pause g seconds, drift right.
	row = PackedStringArray()
	for g in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8]:
		var after: Array = _mag(_series([[4.0, true, 0.0], [2.5, true, 1.0], [g, true, 0.0], [2.5, true, -1.0]]).slice(390 + int(round(g / DT))))
		row.append(_cell("%.1f" % g, after))
	print("TRANSITION (pause s : peak/mean angle over 2.5 s)          ", "  ".join(row))

	# OVERCORRECT: drift left, jab the opposite key for t seconds, then hands off.
	row = PackedStringArray()
	for t in [0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 1.0]:
		var after: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], [t, true, -1.0], [3.0, true, 0.0]]).slice(390)
		row.append("%.1f:%s" % [t, "SPIN" if _mag(after).max() > SPIN else "%2.0f" % maxf(after.max(), 0.0)])
	print("OVERCORRECT (opposite jab s : furthest swing to the other side)  ", "  ".join(row))

	# SPEED: held slide from different entry speeds.
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
		row.append("in %2.0f m/s: peak %s end %2.0f r %3.0fm v %2.0f" % [
			entry, "SPIN" if rad_to_deg(peak) > SPIN else "%2.0f" % rad_to_deg(peak), rad_to_deg(absf(sim.slip_angle)), radius, sim.speed,
		])
	print("SPEED      ", "   ".join(row))

	# U-TURN: power and Shift held from different entry speeds, until the car
	# is travelling back the way it came. Width is how much road that took.
	row = PackedStringArray()
	for run_up in [1.0, 1.5, 2.0, 3.0, 5.0]:
		var sim := _make()
		for i in int(run_up / DT):
			sim.step(DT, true, 0.0, false)
		var entry: float = sim.speed
		var start: Vector2 = sim.pos
		var peak := 0.0
		var turned := false
		for i in int(10.0 / DT):
			sim.step(DT, true, 1.0, false)
			peak = maxf(peak, absf(sim.slip_angle))
			if sim.vel.x < 0.0 and absf(sim.vel.angle()) > PI - 0.05:
				turned = true
				break
		var result := "none"
		if turned:
			result = "%2.0f m, %s" % [sim.pos.y - start.y, "SPIN" if rad_to_deg(peak) > SPIN else "peak %2.0f" % rad_to_deg(peak)]
		row.append("in %2.0f m/s: %s" % [entry, result])
	print("U-TURN     ", "   ".join(row))

	# DONUT: full power with Shift held from a standstill. The last 4 of 8 s are measured.
	var sim := _make()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var speed_sum := 0.0
	var angle_sum := 0.0
	var psi_at_4 := 0.0
	for i in int(8.0 / DT):
		sim.step(DT, true, 1.0, false)
		if i == 240:
			psi_at_4 = sim.psi
		if i >= 240:
			low = low.min(sim.pos)
			high = high.max(sim.pos)
			speed_sum += sim.speed
			angle_sum += absf(sim.slip_angle)
	var size := high - low
	print("DONUT  power + Shift from a standstill: circle %2.0f m across, %.1f turns in 4 s, %2.0f km/h, angle %2.0f" % [
		maxf(size.x, size.y), absf(sim.psi - psi_at_4) / TAU, speed_sum / 240.0 * 3.6, rad_to_deg(angle_sum / 240.0),
	])
	quit()


func _straight() -> void:
	var sim := _make()
	var to_60 := -1.0
	var spin_time := 0.0
	for i in int(20.0 / DT):
		sim.step(DT, true, 0.0, false)
		if sim.wheelspin > 0.5:
			spin_time += DT
		if to_60 < 0.0 and sim.speed * 3.6 >= 60.0:
			to_60 = (i + 1) * DT
	var top: float = sim.speed
	var squat: float = 0.0
	sim = _make()
	for i in int(1.0 / DT):
		sim.step(DT, true, 0.0, false)
	squat = sim.wx
	for i in int(5.0 / DT):
		sim.step(DT, true, 0.0, false)
	for i in int(0.6 / DT):
		sim.step(DT, false, 0.0, false)
	print("STRAIGHT top %3.0f km/h  0-60 in %.2fs  wheelspin for %.1fs  weight on rear: %+.0f%% under power, %+.0f%% after a lift" % [
		top * 3.6, to_60, spin_time, squat * 100.0, sim.wx * 100.0,
	])


## Establish a left drift, then apply `ending` ([seconds, throttle, lean]) and describe what happens.
func _ending(title: String, ending: Array) -> void:
	var after: Array = _series([[4.0, true, 0.0], [2.5, true, 1.0], ending]).slice(390)
	var mags := _mag(after)
	var straight := _first_below(mags, 10.0)
	var text := "under 10 deg after %.2fs" % straight if straight >= 0.0 else "never under 10 deg"
	if mags.max() > SPIN:
		text = "SPIN"
	print("%s: %s, furthest swing to the other side %4.1f, at 0.5/1.0/1.5 s: %4.0f %4.0f %4.0f" % [
		title, text, maxf(after.max(), 0.0), after[30], after[60], after[90],
	])


func _make() -> RefCounted:
	var sim := CarSim.new()
	for key in _overrides:
		sim.set(key, _overrides[key])
	return sim


## Runs the phases ([seconds, throttle, lean]) and returns the signed drift angle in degrees for every tick.
func _series(phases: Array) -> Array:
	var sim := _make()
	var out := []
	for phase in phases:
		for i in int(round(phase[0] / DT)):
			sim.step(DT, phase[1], phase[2], false)
			out.append(rad_to_deg(sim.slip_angle))
	return out


func _mag(values: Array) -> Array:
	return values.map(func(v): return absf(v))


func _flag(mags: Array) -> String:
	return "  SPIN" if mags.max() > SPIN else ""


func _cell(label: String, mags: Array) -> String:
	if mags.max() > SPIN:
		return "%s:SPIN" % label
	return "%s:%2.0f/%2.0f" % [label, mags.max(), _mean(mags)]


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
