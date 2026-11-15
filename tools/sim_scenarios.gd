extends SceneTree
## Headless check of the drift model. Run with:
##   godot --headless --path . --script res://tools/sim_scenarios.gd
## Each scenario is a list of [duration_s, throttle, lean, handbrake] phases.

const CarSim := preload("res://scripts/car/car_sim.gd")
const DT := 1.0 / 60.0


func _init() -> void:
	_run("straight: throttle 8 s", [[8.0, true, 0.0, false]])
	_run("plain lean: 4 s straight, hold left 4 s", [[4.0, true, 0.0, false], [4.0, true, 1.0, false]])
	_run("flick: 4 s straight, right 0.35 s, left 4 s", [[4.0, true, 0.0, false], [0.35, true, -1.0, false], [4.0, true, 1.0, false]])
	_run("lift recovers: lean left 3 s, then lift and centre 2 s", [[4.0, true, 0.0, false], [3.0, true, 1.0, false], [2.0, false, 0.0, false]])
	_run("exit on power: lean left 3 s, centre on throttle 3 s", [[4.0, true, 0.0, false], [3.0, true, 1.0, false], [3.0, true, 0.0, false]])
	_run("transition: left 2.5 s, right 2.5 s, centre 2 s", [[4.0, true, 0.0, false], [2.5, true, 1.0, false], [2.5, true, -1.0, false], [2.0, true, 0.0, false]])
	_run("lift-off entry: lift 0.4 s while leaning, back on", [[4.0, true, 0.0, false], [0.4, false, 1.0, false], [3.5, true, 1.0, false]])
	_run("handbrake entry: 0.5 s handbrake with lean, then power", [[4.0, true, 0.0, false], [0.5, true, 1.0, true], [3.5, true, 1.0, false]])
	_run("standstill: no input 2 s, then lean only 2 s", [[2.0, false, 0.0, false], [2.0, false, 1.0, false]])
	_run("slow turn: 1 s throttle then lean 3 s", [[1.0, true, 0.0, false], [3.0, true, 1.0, false]])
	quit()


func _run(title: String, phases: Array) -> void:
	var sim := CarSim.new()
	print("\n== ", title)
	for phase in phases:
		var steps := int(round(phase[0] / DT))
		var peak_slip := 0.0
		var peak_yaw := 0.0
		var min_speed := INF
		var guard_ticks := 0
		for i in steps:
			sim.step(DT, phase[1], phase[2], phase[3])
			peak_slip = maxf(peak_slip, absf(sim.slip_angle))
			peak_yaw = maxf(peak_yaw, absf(sim.yaw_rate))
			min_speed = minf(min_speed, sim.speed)
			if sim.guard_active:
				guard_ticks += 1
			if is_nan(sim.pos.x) or is_nan(sim.psi):
				print("   NaN at step ", i)
				return
		print("   %4.2fs thr=%d lean=%+.0f hb=%d | end: speed %5.1f  slip %6.1f deg  yaw %6.1f deg/s  heading %7.1f deg | peak slip %5.1f  peak yaw %5.1f  min speed %4.1f  guard %d ticks" % [
			phase[0], int(phase[1]), phase[2], int(phase[3]),
			sim.speed, rad_to_deg(sim.slip_angle), rad_to_deg(sim.yaw_rate), rad_to_deg(sim.psi),
			rad_to_deg(peak_slip), rad_to_deg(peak_yaw), min_speed, guard_ticks,
		])
