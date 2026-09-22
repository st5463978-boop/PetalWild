# Engine pin

PetalWild is built and tested on this exact binary. Do not move the project to another Godot snapshot during parallel work.

| Field | Value |
| --- | --- |
| Version string | `4.8.dev6.official.8898c2b3d` |
| Release tag | `4.8-dev6` |
| Published | 2026-09-15 |
| Binary | `Godot_v4.8-dev6_linux.x86_64` |
| Download | https://github.com/godotengine/godot-builds/releases/download/4.8-dev6/Godot_v4.8-dev6_linux.x86_64.zip |
| SHA-256 | `d3678019d0a6501d754db36807110a02a1cfa24d49886be8d3a72d91faa80ca3` |

Godot 4.8 stable was not published on 22 September 2026. The newest official 4.8 build is this dev snapshot. `tools/fetch_godot.sh` downloads that zip and checks the hash.

The project file requests the GL Compatibility renderer so the garden runs on machines without Vulkan. Forward+ remains the quality target when a Vulkan device is present; do not flip the pin just to chase a newer dev build.
