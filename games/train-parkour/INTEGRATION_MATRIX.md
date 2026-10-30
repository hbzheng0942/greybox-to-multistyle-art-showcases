# H07 integration matrix

The packaged combination is frozen from stable integrated source `a92b3e3` (`codex/h07-framerate-20261030`). Native/Godot file identities are recorded in [INTEGRATION_MATRIX.json](INTEGRATION_MATRIX.json). Private working paths, raw diffs and provider records are excluded.

| Component | State | Origin / current inclusion |
|---|---|---|
| 城市/轨道环境与实体下城city08 | integrated | Integrated 37-track/nine-region scene. Lower city contains109 buildings and36 batches; art/human acceptance remains open. |
| 原G1环境与道具 | integrated | Canonical G1 facade/tower/keep/hazard/lantern resources remain bound by content hash; no experimental remesh substitution. |
| T2幽灵列车 | integrated | Current T2 with local face refinement is the active train. The superseded T1 train is not an alternate showcase style. |
| Festival V2 动态角色与互动 | integrated | Three actual G1 actors, rigid-part skeleton/IK, ghost deformation, pumpkin actions and H horn are included. Not a human play/animation acceptance claim. |
| 车脸/虹膜/灯芯与双端车灯 | integrated | Final white-face/iris treatment, buffer lenses and two downward unshadowed train lights are included; original T2 mesh/texture bytes are shared. |
| 保质静态/描边合批 | integrated | Exact batching is integrated. Optional geometry-cache code is included, but no cached geometry/import output is shipped. No60fps claim. |
| 材质/暖窗/近景灯/天空与表面光场 | integrated | Current integrated material/light files are preserved. Metadata-only public cleanup does not change asset bytes or lighting values. |
| 共享玩法/相机/输入运行链 | integrated | Shared source is staged without gameplay/collision/speed/camera retuning. Public adapters only select style, hide prototype HUD and isolate application/save namespaces. |
| 最终统一入口 | integrated | Build static H07 first, then attach Festival V2; this avoids merging animated actors into the static geometry. |
| 新frame-rate/atlas/hoisted-shader实验 | excluded-work-in-progress | Unsubmitted separate source variant, based on older477d81c and explicitly marked in progress. Not merged, used as a replacement, or claimed as verified performance. |
| 试验重拓扑/远距LOD替换 | not-integrated | Unapproved geometry-changing remesh candidates are not substituted for canonical near/important-distant G1 models. |

The complete headless contract passed six synthetic-input branches, with all37 tracks in the union and all9 regions declared/assembled, no construction errors, no recovery and no camera-contract errors. The staged source hashes stayed unchanged during that run. This is a technical contract; it does not establish rendering, stable frame rate, concept fidelity or human final acceptance.

The final public adapter gives this package its own application/save namespace. It is included in subsequent native entry checks; it does not replace the integrated art or frozen gameplay. Read [GAME.md](GAME.md) and [validation/index.json](validation/index.json) before extending the case.
