# 同事录制指南

先按[根README](../README.md)拉取源码并安装完整资源。使用Godot4.7.2；`python3 tools/launch.py`列出游戏/风格。总入口首次运行会自动导入资源并注册脚本类。

## 从过程到成果

| 游戏 | 灰盒/美术入口与操作 | 方案、粗模、试装材料 |
|---|---|---|
| Hole | [GAME](../games/hole/GAME.md)；11美术风格＋共享灰盒 | [process/INDEX](../games/hole/process/INDEX.md) |
| 列车跑酷 | [GAME](../games/train-parkour/GAME.md)；5美术风格＋共享灰盒 | [process/INDEX](../games/train-parkour/process/INDEX.md) |
| 狗闹博物馆 | [GAME](../games/museum-dog/GAME.md)；A01＋共享灰盒 | [process/INDEX](../games/museum-dog/process/INDEX.md)、[骨骼动态夹具](../games/museum-dog/process/animation/) |
| Bubble | [GAME](../games/bubble-buddies/GAME.md)；新D1＋v9灰盒 | [process/INDEX](../games/bubble-buddies/process/INDEX.md) |

每个阶段保留其真实身份：方案图用于展示方向选择；程序化灰盒用于真实游玩；粗模/结构GLB可在Blender中直接编辑；资格试装和当前美术候选分别展示。部分完整灰盒由GDScript/config生成，单件成品模型不等于历史整场粗模。现有方案图不应剪成一次新生成的实录。

## 干净画面

列车的6个Showcase入口默认隐藏原型/调试HUD。博物馆、Bubble的ShowcaseClean默认隐藏原型标注，并保留实际开始/暂停菜单；`--show-hud`用于开发调试。Hole使用随包的`shared/record_clean.gd`运行真实场景，隐藏参数面板、地面标注与代理提示，保留正常输入和声音；准确命令见Hole的GAME。

同一游戏做前后对照时，使用同一相机、分辨率和输入路径。先等资源装配和着色器准备完成，再开始正式镜头。录实际游戏窗口，避免把编辑器、其他桌面窗口或调试控制台带入游戏镜头。

## 连续帧与导出

目标交付1920×1080、30fps连续原生画面。已有合格[录制素材](../media/README.md)可直接取用。实时录屏的文件标为30fps不代表游戏实际输出30个不同画面；不能靠重复帧或插帧补成合格素材。

Godot4.7.2自带逐帧Movie Maker，可用固定步长生成视频。例如已装配的列车入口录600帧：

```sh
python3 tools/launch.py train-parkour halloween-comic --godot /path/to/Godot --resolution 1920x1080 --write-movie /absolute/output/take.avi --fixed-fps 30 --quit-after 600
```

该模式取消实时同步；实际渲染耗时可长于成片时长。它生成连续游戏帧，不证明实时游戏性能。交互录制与固定输入夹具的区别须写进素材记录。博物馆当前骨骼视频附可复录夹具、帧编码器和验证，保留了其受控测试范围。

将原生30fps素材编码成剪辑用MP4时保留原时间轴：

```sh
ffmpeg -i take.avi -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac take.mp4
```

素材旁记录游戏/风格、工程版本、资源哈希、分辨率、原生帧数、输入方式、是否离线渲染及音频情况。正式视频里不放这些技术标注。导出的录制文件放在工程外，确认成片后清掉本次逐帧临时图和失败take；保留验证记录与必要原片。
