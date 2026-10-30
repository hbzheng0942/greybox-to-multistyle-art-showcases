# Process material / 流程素材

The complete archive includes the actual greybox input, current playable candidates, existing concept/early native assembly images, and isolated editable geometry. These are separate, accurately labelled stages. Historical pictures are process evidence and may contain their original prototype HUD; they do not describe current final art or a live generation session.

Start with `python3 games/train-parkour/launch.py --style greybox --godot /path/to/Godot`. Then use the matching style entry for the current result. Open the linked GLB in Godot or Blender to record an actual object/geometry edit. Concept images can be shown as existing direction selection; do not present them as a newly completed AI call.

| Style | Existing direction | Historical native assembly | Editable component / actual scope |
|---|---|---|
| clay | [Concept](clay/concept.png) | [Native stage](clay/early-assembly.png) | [GLB](models/clay-rail-sleeper.glb) — Authored production-v1 reusable geometry, still referenced by P21; editable kit component. |
| pixel-v2 | [Concept](pixel-v2/concept.png) | [Native stage](pixel-v2/early-assembly.jpg) | [GLB](models/pixel-current-concourse.glb) — Current V2 editable concourse component; this is not a recovered historical rough-world project. |
| paper-atlas | [Concept](paper-atlas/concept.png) | [Native stage](paper-atlas/early-assembly.jpg) | [GLB](models/paper-early-sample-world.glb) — Initial Paper sample geometry inherited by the R9 scene builder; isolated editable component. |
| odd-logistics | [Concept](odd-logistics/concept.png) | [Native stage](odd-logistics/early-assembly.jpg) | [GLB](models/b2-proxy-kit.glb) — S6 six-module editable proxy kit, reused by current B2 runtime. |
| halloween-comic | [Concept](halloween-comic/concept.png) | [Native stage](halloween-comic/early-assembly.jpg) | [GLB](models/h07-current-t2-train.glb) — Current editable T2 train asset with local face refinement; not a standalone early scene. H07 rough environment is authored in the included procedural source/layout. |

Current native results are in each `styles/<id>/thumbnail.jpg` and the corresponding project entry. Pixel V2 and H07 do not claim an independently recovered standalone rough-world GLB: their early images and the actual current editable geometry/source are distinguished in the manifest. No rejected full game project is included.

H07 editable environment source is `../shared/engine-main/game/themes/halloween_07/continuous/` and `lower_city_layers.gd`; current material/light values and model bindings remain in the same engine root. B2 proxy modules and Paper sample geometry are actual inputs still used by the current composition.

See [manifest.json](manifest.json) for stage identity/version and file hashes, and [../INTEGRATION_MATRIX.md](../INTEGRATION_MATRIX.md) before changing H07. Large GLB bytes require the complete archive; the source Git checkout supplies the tracked preview images and relative resource links.
