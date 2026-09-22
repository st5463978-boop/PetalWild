# Engine pin

Exact binary used for this build:

`Godot Engine v4.8.dev6.official.8898c2b3d`

Release: Godot 4.8-dev6, official, commit `8898c2b3d`.

Download: https://github.com/godotengine/godot-builds/releases/download/4.8-dev6/Godot_v4.8-dev6_linux.x86_64.zip

Local path on the build machine: `~/.local/godot/Godot_v4.8-dev6_linux.x86_64`. The binary is not committed.

Stable 4.8 was not available when this pin was made. Later snapshots, including any newer 4.8-dev, are not this build. Do not move the project to another Godot version during parallel work.

## Renderer

`project.godot` sets `renderer/rendering_method` to `gl_compatibility`.

This VM has no `/dev/dri` and no Vulkan device. The process runs on Mesa llvmpipe (LLVM 20.1.2) through X11 and OpenGL 4.5. Forward+, volumetric fog, SDFGI, and real-time shadows are off. Shadows are disabled in the garden when the adapter name contains `llvmpipe`.

Godot 4.8-dev6 treats `:=` inference from an untyped Variant as a parse error. Annotate those variables. The project warning key `debug/gdscript/warnings/inference_on_variant` does not suppress it.

Autoloads preload their scripts. `class_name` is available to scene scripts after `godot --headless --path . --import --quit` has written `.godot/global_script_class_cache.cfg`.
