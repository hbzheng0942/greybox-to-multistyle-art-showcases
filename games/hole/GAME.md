# Hole · 11种视觉风格

同一套吞噬玩法的11个当前完整开发候选。旧滨水工程、失败版本、概念分支和蘑菇单槽试装未纳入。图片来自对应版本的历史原生截图。

|风格|工程|当前状态|
|---|---|---|
|游乐园|[打开工程](styles/amusement/project/project.godot)|可试玩开发候选；人工终验待定|
|零食店|[打开工程](styles/snack/project/project.godot)|可试玩开发候选；人工终验待定|
|蘑菇森林|[打开工程](styles/mycelium/project/project.godot)|可试玩开发候选；人工终验待定|
|月面基地|[打开工程](styles/lunar/project/project.godot)|可试玩开发候选；人工终验待定|
|珊瑚海集市|[打开工程](styles/coral/project/project.godot)|可试玩开发候选；人工终验待定|
|沙漠商队|[打开工程](styles/saffron/project/project.godot)|可试玩开发候选；人工终验待定|
|纸艺雪镇|[打开工程](styles/papercraft/project/project.godot)|可试玩开发候选；人工终验待定|
|国风漫画·青绿朱砂市集|[打开工程](styles/comic/project/project.godot)|可试玩开发候选；人工终验待定|
|复古搪瓷玩具港口|[打开工程](styles/enamel/project/project.godot)|可试玩开发候选；人工终验待定|
|糖果陶瓷小镇|[打开工程](styles/ceramic/project/project.godot)|可试玩开发候选；人工终验待定|
|轨道科幻小镇|[打开工程](styles/orbital/project/project.godot)|可试玩开发候选；人工终验待定|

## 启动

先按仓库根README取得完整资源包；保持整个仓库目录结构。用Godot4.7.2打开所选风格的project.godot，导入资源后运行。WASD/方向键移动，R重开，Space暂停。陶瓷/科幻已内置正确风格和最终combined参数，无需环境变量。

每种风格保留自己的原生工程根，避免旧模块和全局类相互影响。大资源在仓库shared/assets/sha256只存一份，工程通过仓库内相对链接引用；移交时保留链接关系。当前运行/编辑依赖已保留，生产平台、供应商任务和缓存不属于此包。

## 状态与来源

七套主题是固定可试玩候选；国风漫画与搪瓷保留确定性装配、文字和材质绑定；陶瓷/轨道科幻为lookdev开发alpha，仍有概念还原差异。技术导入/运行检查不替代人工手感、美术终验或实时性能认证。

逐风格入口与状态见[styles.json](styles.json)，文件hash见[files-manifest.json](files-manifest.json)。字体授权见[共享授权](shared/licenses/Noto-CJK-OFL.txt)。


## 干净录制：真实运行中隐藏原型UI

先在Godot4.7.2编辑器打开目标project.godot，等待资源导入完成。之后在仓库根运行（将Godot替换为本机可执行路径）：

```sh
Godot --path games/hole/styles/ceramic/project --script "$PWD/games/hole/shared/record_clean.gd" -- --clean-size=1920x1080
Godot --path games/hole/shared/greybox/project --script "$PWD/games/hole/shared/record_clean.gd" -- --clean-size=1920x1080
```

其他风格只需替换styles后的目录名。此脚本在游戏实际运行时隐藏hud、ground_labels和代理调试显示；保留手动WASD/方向键、R重开、Space暂停和游戏声音，不自动操作，也不靠截图后裁UI。窗口加载完成后再开始系统录屏；终端会输出HOLE_CLEAN_VIEW_READY。可省略--clean-size保留工程原生1280×800；1920×1080参数设置真实viewport，录制文件实际帧率另行检查。

本地完整流程材料见[process/INDEX.md](process/INDEX.md)。共享灰盒是原始v0.3输入；历史风格的尺寸/相机合同有迭代，不能把所有11套当成严格同输入/同尺度同步对照。
