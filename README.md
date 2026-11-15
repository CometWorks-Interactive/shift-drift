# Shift Drift

A three-key drift game for [GitHub Game Off 2026](https://itch.io/jam/game-off-2026). The theme is **SHIFT**.

There is no steering wheel. Space is the throttle, and the two Shift keys throw the car's weight left or right. The weight swings like a pendulum, so the skill is timing your presses to the swing.

## Controls

| Key | Action |
|---|---|
| Space | Throttle |
| Left Shift / Right Shift | Throw the car's weight to that side |
| A / D or arrow keys | Same as the Shift keys |
| R | Reset the car |

Test-pad only: `1`–`4` switch car, `,` / `.` change the car's look, `S` is a handbrake, `Tab` selects a handling setting, `-` and `=` change it, and `Backspace` restores it.

## How to drift

- **Press early.** The car turns a beat after the key.
- **Hold Shift on the throttle** to hold a slide. Tap Shift to make it shallower.
- **Lift off the throttle** to end the slide.
- **Flick:** tap the opposite Shift for about 0.4 seconds, then swap. If the weight swings past the amber marks on the gauge you get a kick and a bigger slide.

## Cars

| Car | Character |
|---|---|
| Hatchback | Light and forgiving. Almost any flick earns a kick, but the kick is small. |
| Sedan | The benchmark. Flick for about 0.4 s to earn the kick. |
| Muscle | Heavy and fast. Slow to swing, needs room, and its kick lasts longest. |
| Sports | Fastest and grippiest. A shallow slide unless you hit a tight flick window. |

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

`handling_report.gd` takes options after `--`: `car=muscle` tests a car from the roster, and `setting=value` pairs override individual settings, for example `-- car=sports kick_gain=0.6`.

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
