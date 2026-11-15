# Shift Drift

A three-key drift game for [GitHub Game Off 2026](https://itch.io/jam/game-off-2026). The theme is **SHIFT**.

There is no steering wheel. Space is the throttle, and the two Shift keys throw the car's weight left or right. Weight moves the way it does in a real car, so the skill is timing your presses and your throttle to where the weight is.

## Controls

| Key | Action |
|---|---|
| Space | Throttle |
| Left Shift / Right Shift | Throw the car's weight to that side |
| A / D or arrow keys | Same as the Shift keys |
| R | Reset the car |

Test-pad only: `1`–`4` switch car, `,` / `.` change the car's look, `S` is a handbrake, `Tab` selects a handling setting, `-` and `=` change it, and `Backspace` restores it.

## How to drift

The car is rear-wheel drive and it punishes clumsy inputs. The rear wheels have their own spin speed: the harder they spin, the less sideways grip the tail has.

- **Press early.** The car turns a beat after the key.
- **Hold Shift on the throttle** to hold a slide. At speed that is a steady drift of about 40 degrees.
- **Slow in, tight out.** The same hold makes a tighter arc the slower you enter. There are no brakes, so lift early to lose speed.
- **Donut:** hold Shift and the throttle from a standstill. At low speed the engine spins the wheels freely and the tail swings right round.
- **Lift off the throttle** and the wheels stop spinning, the weight pitches forward, and the car snaps straight and a little past it.
- **Pause between Shifts** in an S-bend. Swap sides with less than half a second's pause and the car rotates faster than the front wheels can catch it: it spins.
- **Flick:** tap the opposite Shift first, then swap. A longer tap throws the car into a bigger slide; too long and it spins.
- **Do not overcorrect.** A long stab of opposite Shift to catch a slide sends the car round the other way.

## Cars

| Car | Character |
|---|---|
| Hatchback | Light and forgiving. Easy slides that are hard to spin. |
| Sedan | The benchmark. Holds a 40 degree slide, and spins if you swap sides without a pause. |
| Muscle | Heavy, with a lot of torque. Slow to swing and slow to forgive. |
| Sports | Fastest and grippiest. Bites hard and spins on small mistakes. |

Each car is the baseline handling plus a few changed settings, listed in `scripts/car/car_roster.gd`.

## Running it

Open the folder in [Godot 4.7](https://godotengine.org/download) and press Play, or run:

```bash
godot --path .
```

## Status

Early work in progress. So far there is a handling test pad, four cars, tyre smoke and skid marks. Courses, scoring and sound are not built yet.

## Layout

```
scenes/            Godot scenes
scripts/car/       Drift physics model and the player car
scripts/camera/    Chase camera
scripts/effects/   Skid marks and tyre smoke
scripts/ui/        On-screen readouts and live tuning
scripts/world/     Test pad
tools/             Headless handling checks, asset import, model gallery
```

## Handling checks

These run without a window and print numbers, which makes tuning repeatable:

```bash
godot --headless --path . --script res://tools/sim_scenarios.gd
godot --headless --path . --script res://tools/handling_report.gd
```

`handling_report.gd` takes options after `--`: `car=muscle` tests a car from the roster, and `setting=value` pairs override individual settings, for example `-- car=sports steer_rate=2.6`.

## Assets

The game uses the purchased "Low Poly Racing Pack (Street Race)" models. Their licence does not allow redistribution, so the model files are not in this repository and `assets/vendor/` is ignored by git. Without them the game still runs, with a car made of boxes.

If you own the pack, copy it in from a Unity project and let Godot import it:

```bash
python3 tools/import_pack.py "/path/to/Assets/Low Poly Racing Pack"
godot --headless --path . --import
```

The models carry no materials of their own (Unity assigns them in prefabs), so the script also writes a manifest of which material each part uses. `scripts/car/car_library.gd` reads it. On the test pad, `,` and `.` step through the car models.

To render a labelled contact sheet of every model:

```bash
godot --path . --script res://tools/car_gallery.gd -- --out=/some/folder
```
