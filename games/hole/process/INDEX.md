# Hole · 本地录制与过程材料

先使用[共享纯灰盒工程](../shared/greybox/project/project.godot)和所选[视觉风格工程](../styles.json)录真实操作；历史概念/阶段图用于解释已有制作过程，不演成现场AI生成。完整模型资源请先按仓库根README下载。

1. 灰盒输入：打开shared/greybox/project/project.godot。场景、实例和规则由scripts及data/graybox_config.json生成，可直接编辑。
2. 风格方向：打开下表concept图片，明确标为“方案/概念”。
3. 结构与资产：可在Godot/Blender打开共享quay-module.glb及逐风格editable-asset-sample.glb。前者是既有规则结构模块，后者是当前选用模型；没有现成整场粗模GLB，不伪造粗模身份。
4. 历史试装与当前结果：下表给出真实阶段图及最新对应原生图。阶段图不是可运行历史工程；当前完整工程仍只保留最新候选。
5. 真实运行：从所选project运行；需要干净画面时用`Godot --path <project目录> --script <仓库>/games/hole/shared/record_clean.gd`，手动操作并使用屏幕录制。此脚本只隐藏HUD/调试标签，不自动操作。

|风格|方案|已有阶段|最新原生|可编辑单件|
|---|---|---|---|---|
|游乐园|[concept](amusement/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](amusement/stage-history.png)|[native](amusement/native-current.png)|[GLB](amusement/editable-asset-sample.glb)|
|零食店|[concept](snack/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](snack/stage-history.png)|[native](snack/native-current.png)|[GLB](snack/editable-asset-sample.glb)|
|蘑菇森林|[concept](mycelium/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](mycelium/stage-history.png)|[native](mycelium/native-current.png)|[GLB](mycelium/editable-asset-sample.glb)|
|月面基地|[concept](lunar/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](lunar/stage-history.png)|[native](lunar/native-current.png)|[GLB](lunar/editable-asset-sample.glb)|
|珊瑚海集市|[concept](coral/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](coral/stage-history.png)|[native](coral/native-current.png)|[GLB](coral/editable-asset-sample.glb)|
|沙漠商队|[concept](saffron/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](saffron/stage-history.png)|[native](saffron/native-current.png)|[GLB](saffron/editable-asset-sample.glb)|
|纸艺雪镇|[concept](papercraft/concept.png)|[历史道具补齐前原生试装（保留当时HUD）](papercraft/stage-history.png)|[native](papercraft/native-current.png)|[GLB](papercraft/editable-asset-sample.glb)|
|国风漫画·青绿朱砂市集|[concept](comic/concept.png)|[历史参考图/模型形体与材质对照](comic/stage-history.png)|[native](comic/native-current.png)|[GLB](comic/editable-asset-sample.glb)|
|复古搪瓷玩具港口|[concept](enamel/concept.png)|[历史参考图/模型形体与材质对照](enamel/stage-history.png)|[native](enamel/native-current.png)|[GLB](enamel/editable-asset-sample.glb)|
|糖果陶瓷小镇|[concept](ceramic/concept.png)|[同组资产，组装/材质参数调整前](ceramic/stage-history.png)|[native](ceramic/native-current.png)|[GLB](ceramic/editable-asset-sample.glb)|
|轨道科幻小镇|[concept](orbital/concept.png)|[同组资产，组装/材质参数调整前](orbital/stage-history.png)|[native](orbital/native-current.png)|[GLB](orbital/editable-asset-sample.glb)|

陶瓷/科幻另有baseline-controls.json与final-controls.json，可在本风格工程中临时替换data/style-controls.json并运行对照，录完恢复final；只是参数条件切换，不能说成新的资产生成。

共享灰盒是原始v0.3输入；历史主题经过尺寸/相机合同迭代（零食店另有历史基线）。跨这些不同版本只能讲流程或近似动作对照，不能宣称所有11风格逐帧/空间严格同步。陶瓷与轨道科幻本轮配套同端回放才有已核对的相同仿真事件。

完整灰盒可玩；历史概念、参考/模型对照和原生图按身份分开。没有保存的完整历史工程/生成过程录像不补造。


## 干净录制：真实运行中隐藏原型UI

先在Godot4.7.2编辑器打开目标project.godot，等待资源导入完成。之后在仓库根运行（将Godot替换为本机可执行路径）：

```sh
Godot --path games/hole/styles/ceramic/project --script "$PWD/games/hole/shared/record_clean.gd" -- --clean-size=1920x1080
Godot --path games/hole/shared/greybox/project --script "$PWD/games/hole/shared/record_clean.gd" -- --clean-size=1920x1080
```

其他风格只需替换styles后的目录名。此脚本在游戏实际运行时隐藏hud、ground_labels和代理调试显示；保留手动WASD/方向键、R重开、Space暂停和游戏声音，不自动操作，也不靠截图后裁UI。窗口加载完成后再开始系统录屏；终端会输出HOLE_CLEAN_VIEW_READY。可省略--clean-size保留工程原生1280×800；1920×1080参数设置真实viewport，录制文件实际帧率另行检查。

本地完整流程材料见[过程索引](INDEX.md)。共享灰盒是原始v0.3输入；历史风格的尺寸/相机合同有迭代，不能把所有11套当成严格同输入/同尺度同步对照。
