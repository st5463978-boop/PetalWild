# Godot store pass

27 September 2026. Viva Piñata emulation was not cloned, not run, and not copied.

The launcher README at `VivaPinataPlus/VivaPinataPlus` commit `3098b70` has no store URL. The only links are a placeholder GitHub releases path (`yourusername/viva-pinata-qol-mods`), a Discord invite, and an email address. There is no Godot project and no asset pack in that repository.

## What was opened

Godot 4.8-dev6 official `8898c2b3d` (`tools/fetch_godot.sh`), `--rendering-driver opengl3`, Mesa llvmpipe. The asset-library HTTP API returned 403 from this machine. Store pages were read in the browser text fetch.

| Listing | What it is | Decision |
| --- | --- | --- |
| [Kenney Starter Kit City Builder](https://store.godotengine.org/asset/kenney/starter-kit-city-builder/) | Godot 4.6 project. Place, rotate, demolish, save. MIT code, CC0 models, sprites, and sounds. Lilita One is OFL. Commit `4535092`. | ADOPT. Running sample town, 122 cells, rendered on this pin. |
| [CityCrafter3D](https://github.com/immaculate-lift-studio/CityCrafter3D) | MIT editor plugin. `generate_city_async` needs a `CityConfiguration` with PackedScenes. Default block is 200 and the street is 25. The README points at the asset store and at Kenney city-kit commercial, industrial, and suburban (CC0). | STUDY. Not a world. Not vendored. |
| [Quaternius Medieval Village MegaKit](https://store.godotengine.org/asset/quaternius/medieval-village-megakit/) | Store text says the free standard file is a portion of the models and not a Godot project. | Left on the store. |
| [NatureForge meadow kit](https://store.godotengine.org/asset/emace-art/natureforge-stylized-meadow-farm-kit/) | Custom licence: no redistribution of the pack. Listed maximum Godot 4.7.2. | REJECT. |
| [Gaea](https://store.godotengine.org/asset/benjatk/gaea/) | MIT graph addon. Listed maximum Godot 4.3. | Not vendored. |
| [SimpleXTerrain](https://store.godotengine.org/asset/prajwal-m/simplexterrain/) | MIT, Godot .NET, bundles Terrain3D. | Not vendored. This pin stays the standard binary. |
| [Roommate](https://store.godotengine.org/asset/hoork/roommate/) | MPL-2.0 indoor level builder. | Not vendored. |

## What landed

`third_party/kenney_city_builder/` is the kit, with paths moved under that folder. `scenes/parish.tscn` is that project's main scene: the original fifteen structures stay first, so F3 still loads `sample map/map.res` (122 cells, cash 5860). Play still starts on an empty grid with $10000. `run/main_scene` points at it. The grove scene remains `scenes/main.tscn`.

Church, restaurant, cafe, clinic, school, shop, library, bakery, post office, town hall, and inn are appended after that list. Their meshes are original boxes in `assets/civic/`, not Kenney models. Enter on a small apartment (building a–d) or on one of those opens that building: a jelly, a short list for the day, and furniture that has to stay in the room. Each building keeps its own list.

Grove Park is still unbuilt. The parish grid does not replace utility scoring, the session inventory, or navigation.
