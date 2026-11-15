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

Test-pad only: `S` is a handbrake, `Tab` selects a handling setting, `-` and `=` change it, `Backspace` restores it.

## How to drift

- **Press early.** The car turns a beat after the key.
- **Hold Shift on the throttle** to hold a slide. Tap Shift to make it shallower.
- **Lift off the throttle** to end the slide.
- **Flick:** tap the opposite Shift for about 0.4 seconds, then swap. If the weight swings past the amber marks on the gauge you get a kick and a bigger slide.

## Running it

Open the folder in [Godot 4.7](https://godotengine.org/download) and press Play, or run:

```bash
godot --path .
```

## Status

Early work in progress. So far there is a handling test pad with a placeholder car, tyre smoke and skid marks. Courses, scoring and sound are not built yet.

## Layout

```
scenes/            Godot scenes
scripts/car/       Drift physics model and the player car
scripts/camera/    Chase camera
scripts/effects/   Skid marks and tyre smoke
scripts/ui/        On-screen readouts and live tuning
scripts/world/     Test pad
tools/             Headless handling checks
```

## Handling checks

These run without a window and print numbers, which makes tuning repeatable:

```bash
godot --headless --path . --script res://tools/sim_scenarios.gd
godot --headless --path . --script res://tools/handling_report.gd
```

`handling_report.gd` accepts overrides after `--`, for example `-- kick_gain=0.6 lat_freq=1.1`.

## Assets

The final game will use purchased 3D models. Their licence does not allow redistribution, so the model files are not in this repository.
