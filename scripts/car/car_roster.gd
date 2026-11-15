extends RefCounted
## The playable cars. Each one is the baseline handling in car_sim.gd plus a
## handful of changed settings, and a model from the car pack.
##
## Cars differ in tempo (how fast the weight swings), how strict the kick
## window is, how big the kick is, speed and grip. The weight bounce, the
## self-steer and the assists are the same on every car so skills carry over.
##
## These numbers come from scripted runs (tools/handling_report.gd), not from
## hands-on driving, so treat them as starting points.

const CarSim := preload("res://scripts/car/car_sim.gd")

const CARS: Array[Dictionary] = [
	{
		"id": "hatchback",
		"name": "Hatchback",
		"blurb": "Light and forgiving. Almost any flick earns a kick, but the kick is small.",
		"model": "hatchback_01",
		"setup": {
			"lat_freq": 1.55, "inertia": 1150.0, "engine_force": 6300.0,
			"w_break": 1.5, "k_feint": 5.0, "kick_gain": 0.3, "slip_damp": 3000.0,
		},
	},
	{
		"id": "sedan",
		"name": "Sedan",
		"blurb": "The benchmark. Flick for about 0.4 s to earn the kick.",
		"model": "sedan_07",
		"setup": {},
	},
	{
		"id": "muscle",
		"name": "Muscle",
		"blurb": "Heavy and fast. Slow to swing, needs room, and its kick lasts longest.",
		"model": "muscle_01",
		"setup": {
			"lat_freq": 1.0, "inertia": 1900.0, "engine_force": 9000.0, "power_grip": 0.35,
			"d_frac": 0.45, "kick_gain": 0.6, "kick_time": 3.0, "slip_damp": 3400.0,
		},
	},
	{
		"id": "sports",
		"name": "Sports",
		"blurb": "Fastest and grippiest. A shallow slide unless you hit a tight flick window.",
		"model": "sports_14",
		"setup": {
			"lat_freq": 1.8, "inertia": 1200.0, "engine_force": 10500.0,
			"mu_front": 2.55, "mu_rear": 2.92, "w_break": 1.75, "k_feint": 10.0,
			"d_frac": 0.42, "kick_gain": 0.8, "slip_damp": 3000.0,
		},
	},
]

const DEFAULT := "sedan"


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for car in CARS:
		out.append(car["id"])
	return out


## The roster entry for a car, or the default car if the id is unknown.
static func find(id: String) -> Dictionary:
	for car in CARS:
		if car["id"] == id:
			return car
	return find(DEFAULT)


## A fresh physics model set up as the given car.
static func make_sim(id: String) -> CarSim:
	var sim := CarSim.new()
	var setup: Dictionary = find(id)["setup"]
	for key in setup:
		sim.set(key, setup[key])
	return sim
