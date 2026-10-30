# Museum production process

These are actual preserved inputs/checkpoints for recording the process. They are not extra completed games. The game root contains the current editable museum and greybox; no obsolete complete project was duplicated.

1. **Input greybox:** run `shared/game/dog_game.tscn`; source-bound input stills are under `A01/greybox-inputs/`.
2. **Direction exploration:** the final eight direction images are listed below; A01 is active, A04/A08 selected and queued.
3. **A01 spatial plan:** [design](A01/design/) and [atlas](A01/atlas/) preserve the actual plan/rendering notes and concept views. Concept images are not native screenshots.
4. **Coarse massing:** [S6 native-v2 stills](A01/rough/native-v2/) show the actual procedural proxy stage. The current shared greybox is editable and runnable; these stills are historical S6 evidence.
5. **Asset references:** [isolated modeling inputs](A01/modeling-references/) map real reference images to semantic asset IDs. Current editable model bytes are the style's `assets/` links into the repository hash store. Open GLBs in Blender after downloading the complete asset archive.
6. **Assembly changes:** [first full assembly](A01/assembly/full-assembly-01/), [environment layering](A01/assembly/environment-layering-02/) and [7499 polish checkpoint](A01/assembly/polish-20261030-published-7499002260658bd3/) retain their stage/version identity. Different cameras are development comparisons, not pixel-synchronous before/after.
7. **Skeletal integration:** [actual dog/adult native videos, bone-pose frames and replay commands](animation/README.md); [component completeness matrix](../INTEGRATION_MATRIX.md). Child/staff rigging remains pending.

| Direction | Production status | Actual concept |
|---|---|---|
| A01 充气巡回博物馆 | active | [image](../process/directions/A01-concept.png) |
| A02 搪瓷机器科学馆 | explored only | [image](../process/directions/A02-concept.png) |
| A03 海盐铸玻璃馆 | explored only | [image](../process/directions/A03-concept.png) |
| A04 竹编田野博物馆 | queued | [image](../process/directions/A04-concept.png) |
| A05 混凝土考古堡 | explored only | [image](../process/directions/A05-concept.png) |
| A06 巨型首饰匣自然馆 | explored only | [image](../process/directions/A06-concept.png) |
| A07 压榨软木标本工坊 | explored only | [image](../process/directions/A07-concept.png) |
| A08 手绘赛璐璐冒险馆 | queued | [image](../process/directions/A08-concept.png) |

`catalog.json` lists each image/model, stage and content hash. Images are normal Git files for GitHub preview. Process is `.gdignore`d so Godot does not import every process image/model into the playable project. Raw API/provider records, company links and credentials are excluded.
