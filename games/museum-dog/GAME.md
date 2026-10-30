# Museum Dog / 狗闹博物馆

A dog grabs, throws and knocks over museum exhibits. One shared gameplay scene supports the current inflatable museum development style.

![Current integrated skeletal native view](previews/current-skeletal-native.png)

The current package freezes `integrated-skeletal-20261030`: the `754b7eac17927af0` environment/physics plus the 27-bone dog and six 52-bone adult skins. The image is an actual frame from the staged controlled native fixture. Child/staff new skeletal assets remain pending; this is a work in progress.

| Direction | Included | Progress |
|---|---|---|
| Greybox | `shared/game/dog_game.tscn` | Shared gameplay v0.3.2 |
| A01 inflatable museum | `styles/A01/runtime/integrated-skeletal-20261030/play.tscn` | Complete environment; dog + 6 adult skeletal integration; 2 child / 2 staff new rigs pending |
| A04 bamboo museum | Concept in `process/directions/` | Selected, queued |
| A08 cel adventure | Concept in `process/directions/` | Selected, queued |

Download the complete Release archive, open `project.godot` in Godot 4.7.2 and allow source assets to import. The default entry is A01. From the repository root:

```sh
godot --headless --editor --import --path games/museum-dog
godot --path games/museum-dog
godot --path games/museum-dog res://shared/game/dog_game.tscn
```

WASD moves; right-drag rotates the camera; E grabs/releases; Space jumps or throws; Shift runs; F barks; R resets.

Both entries default to clean recording presentation: `shared/showcase_clean.gd` hides prototype CanvasLayer/Label3D overlays every frame. Gameplay, input, sound and physics remain in their owners. Pass `-- --show-hud` after the command to restore developer overlays; `-- --showcase-clean` explicitly selects the default. This switch also applies to the process replay fixture.

[Production process](process/INDEX.md) includes actual direction/atlas images, greybox input, coarse massing, modeling references, assembly checkpoints and editable current source. [Skeletal recordings and repeatable capture](process/animation/README.md) show actual changing bone poses and native grab/carry/throw/reset. The controlled fixture passed 37 assertions and recorded seven Skeleton3D / 19 skinned meshes. Some nearby NPCs occlude the fixture camera; this is neither human live play nor real-time FPS certification or H4/H5 acceptance.

`shared/game/` owns gameplay and spatial contracts; `shared/audio/` owns reusable sound; `styles/A01/` owns the fixed environment, modules and visual assets. The package uses one hash-addressed resource store and an isolated `Museum Dog Showcase` user-data namespace. The earlier standalone static version and rejected full projects are excluded.

The dog uses distance-driven skeletal IK; adults sample two source motion clips with a bone-only retargeting driver. Existing procedural motion remains for children/staff. [INTEGRATION_MATRIX.md](INTEGRATION_MATRIX.md) records exactly what is integrated and pending. Canonical sources were unchanged; [INTEGRATION.md](INTEGRATION.md), `styles.json` and `files-manifest.json` describe this distinct portable package.
