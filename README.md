# SUIT-VR-S3

A VR game made with Godot 4.7 and Godot XR Tools, built as separate demos per zone that later
come together in one big level (Zone 4).

## Project layout

```
main.tscn        Start scene (XR Tools staging). Its main_scene decides which zone loads.
shared/          Used by every zone: game flow, player, wrist menu, vibration
zones/
  zone_1/        Climbing with crumbling holds and rising lava
  zone_2/        Forest clearing with digging and a metal detector
  debug/         Small test level
addons/          Third-party addons
```

Each zone has two scenes:

- `zone_N_map.tscn` is the world and its rules (a `ZoneMap`). Zone 4 will combine these.
- `zone_N.tscn` inherits `shared/game/game_scene.tscn` and adds the sky, sun and map. This is what a demo runs.

Shared code must not use anything from `zones/`, because a demo build leaves out the other zones.

## Running it

After cloning, download the addon binaries once:

```
.github/scripts/fetch-addon-binaries.sh
```

To play a different zone, change `Main Scene` on the root node of `main.tscn`.

## Builds

- **Pull requests:** `PR check` loads every zone and fails on script or loading errors.
  Locally: `.github/scripts/check-zones.sh`
- **Releases:** run the `godot-ci export` workflow by hand with a version like `v1.0.0`. It builds
  every demo for Quest, Windows and Linux (`SUIT-VR-S3-Demo-1`, `-2`, ...), uploads each as an
  artifact and creates a draft release.

To add a demo, add a line to `demo` in `.github/workflows/godot-ci.yml`.
