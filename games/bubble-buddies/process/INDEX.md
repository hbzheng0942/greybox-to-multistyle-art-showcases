# Bubble Buddies production process

Two distinct production lineages are preserved; **original D01 is not WorkBuddy D1**. These are process inputs and qualification checkpoints, not extra completed art games.

## Initial greybox

Run `styles/greybox/play.tscn` from the game root. The shared v9 gameplay is the actual accepted input for art development.

## Original four directions

Each of [D01](original-lineage/D01/), [D03](original-lineage/D03/), [D05](original-lineage/D05/) and [D10](original-lineage/D10/) includes its actual selected concept, spatial/interaction drawings, current asset-reference images, native qualification stills and the current bound editable GLBs (`current-models.json`). No superseded full project or old provider/model version is included. All four remain qualification assemblies, not accepted full art service loops.

The actual existing S6 procedural host is preserved, sharing the current v9 gameplay source. For a coarse-stage screen recording, for example:

```sh
godot --path games/bubble-buddies --rendering-method gl_compatibility --script res://process/original-lineage/shared-proxy/launcher.gd -- --style=D03
```

D01/D03/D05/D10 select the four original procedural profiles. This is a **coarse S6 proxy**, not the later fitted model qualification. It defaults to the shared clean recording mode; add `--show-hud` after the final `--` to restore its source-stage badge/labels. Do not label the coarse proxy finished art. Editable GLBs can also be opened directly in Blender after downloading the complete asset archive.

## WorkBuddy new four directions

| Direction | Status | Actual selected concept |
|---|---|---|
| d1-animal-city | active development | [concept](../process/workbuddy/directions/d1-animal-city.png) |
| d2-handcrafted-coop | queued | [concept](../process/workbuddy/directions/d2-handcrafted-coop.png) |
| d3-cel-dusk | queued | [concept](../process/workbuddy/directions/d3-cel-dusk.png) |
| d4-riso | queued | [concept](../process/workbuddy/directions/d4-riso.png) |

[D1 design/S6 probes](workbuddy/D1/design/), [representative pilots](workbuddy/D1/pilots/) and [r7/r8/r9 assembly changes](workbuddy/D1/assembly/) preserve the real development path. Current editable rough/environment geometry is under `styles/d1-animal-city/environment/`; current model resources are in that style's `assets/`. Run `styles/d1-animal-city/play.tscn` for the assembled r9 development game. Historical concept views and the current shared gameplay camera differ; compare as development stages, not pixel-synchronous repair evidence.

Images are normal Git files so GitHub renders them. Model bytes use the shared hash store, delivered in the complete archive. `process/.gdignore` prevents bulk process assets from filling the playable project's import cache. `catalog.json` identifies each item/stage/hash. Supplier calls, quote/receipt histories, company links and credentials are excluded.
