extends RefCounted
## The playable cars. Each one is the baseline handling in car_sim.gd plus a
## handful of changed settings, and a model from the car pack.
##
## Cars differ in tempo (how fast the weight swings), power, grip, and how
## quickly the front wheels catch a slide. The physics rules are the same on
## every car so skills carry over.
##
## These numbers come from scripted runs (tools/handling_report.gd), not from
## hands-on driving, so treat them as starting points. The Sedan is the tuned
## one; the other three are a first pass on the same physics.

const CarSim := preload("res://scripts/car/car_sim.gd")

const CARS: Array[Dictionary] = [
	{
		"id": "hatchback",
		"name": "Hatchback",
		"blurb": "Light and forgiving. Easy slides that are hard to spin.",
		"model": "hatchback_01",
		"setup": {
			"lat_freq": 1.55, "inertia": 1150.0, "engine_power": 169000.0, "engine_force": 11500.0,
			"steer_rate": 3.0, "steer_lead": 0.07,
		},
	},
	{
		"id": "sedan",
		"name": "Sedan",
		"blurb": "The benchmark. Holds a 40 degree slide, and spins if you swap sides without a pause.",
		"model": "sedan_07",
		"setup": {},
	},
	{
		"id": "muscle",
		"name": "Muscle",
		"blurb": "Heavy, with a lot of torque. Slow to swing and slow to forgive.",
		"model": "muscle_01",
		"setup": {
			"lat_freq": 1.0, "inertia": 1900.0, "engine_power": 250000.0, "engine_force": 13500.0,
			"d_frac": 0.88, "steer_lead": 0.07,
		},
	},
	{
		"id": "sports",
		"name": "Sports",
		"blurb": "Fastest and grippiest. Bites hard and spins on small mistakes.",
		"model": "sports_14",
		"setup": {
			"lat_freq": 1.8, "inertia": 1200.0, "engine_power": 370000.0, "engine_force": 19000.0,
			"mu_front": 2.0, "mu_rear": 1.95,
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
