# Real World Open World — Mobile Prototype

Godot 4.5 prototype designed for a GitHub + Termux workflow.

## Current build
- 3D open world prototype
- mountains, forests, lake, roads, cabin and lookout
- day/night lighting
- clear/rain/snow weather controls
- touch joystick + WASD
- Android ARM64 export preset
- GitHub Actions APK build

## Build
Push this repository to GitHub. The workflow in `.github/workflows/android.yml` builds an APK and uploads it as a workflow artifact.

This is a prototype foundation, not a finished photorealistic AAA game. The next iterations should replace procedural placeholder geometry with optimized original PBR assets, terrain streaming, LODs, vegetation instancing, vehicles, NPCs, missions and save data.
