# Engine pin

PetalWild is pinned to one Godot build. Do not float it to a newer snapshot during parallel work.

| Field | Value |
| --- | --- |
| Release | Godot 4.8-dev6 |
| Version string | `4.8.dev6.official.8898c2b3d` |
| Published | 2026-09-15 |
| Platform used here | Linux x86_64 |
| Binary | `Godot_v4.8-dev6_linux.x86_64` |
| SHA256 | `7343548b1af2f853618e42af6d3923be6680a71c1adcd40a9d2ee064c327445a` |
| Download | https://github.com/godotengine/godot-builds/releases/download/4.8-dev6/Godot_v4.8-dev6_linux.x86_64.zip |
| Renderer | Forward+ (`project.godot` features `4.8`, `Forward Plus`) |
| Config | `config_version=5` |

Godot 4.8 stable does not exist as of this pin. The newest stable release is 4.7.2 (2026-08-18). This project does not target 4.7.2, and it will not move to 4.8-dev7 or any later build without an explicit engine decision recorded here.

Local path on the cloud agent machine: `$HOME/opt/godot/Godot_v4.8-dev6_linux.x86_64`. The binary is not committed. `tools/run.sh` looks there unless `GODOT` is set.

API note found against this binary: `Environment.TONE_MAP_FILMIC` is gone. The filmic mapper is `Environment.TONE_MAPPER_FILMIC`.
