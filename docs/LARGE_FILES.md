# 大资源分片传输

同事使用工程只需克隆 `main`，再安装完整Release资源。安装后资源就在本地工程目录，全部灰盒与美术工程可离线打开；无需切换到资源分支：

```sh
git clone --single-branch --branch main https://github.com/hbzheng0942/greybox-to-multistyle-art-showcases.git
cd greybox-to-multistyle-art-showcases
python3 tools/download_complete.py --install-resources
python3 tools/launch.py
```

`main`保存源码、预览和索引；[large-files分支](https://github.com/hbzheng0942/greybox-to-multistyle-art-showcases/tree/large-files/large-files)保存本次传输的8 MiB片和[清单](https://github.com/hbzheng0942/greybox-to-multistyle-art-showcases/blob/large-files/large-files/manifest.json)。分片使用普通Git，无需Git LFS。不要把资源分支合并到`main`。

## 本次完整包

- 游戏工程源版本：`799c478fe45278cd5db3f3c3a1eb2ec83709583f`。
- 完整ZIP：`greybox-to-multistyle-art-showcases-v0.1.0-20261030.zip`，4,895,618,862 bytes。
- 完整ZIP SHA256：`9e7e8608f3e109215712d62d654b34171f08e35157c537e76502ac71f44bef1d`。
- 传输清单包含448个Git小片，以及5个已完成的Release分卷。已完成的分卷直接复用。
- 最终Release提供19个分卷、`release-files.json`和离线解压脚本。下载器会合并成上面同一个完整ZIP，不额外保留每卷的本地副本。

完整包包含全部4个游戏的可编辑工程、共享灰盒、18个美术开发候选、过程素材及资源池。后续传输工具和文档更新可以继续提交到`main`；它们不会改写此冻结工程包。

## 发布流程与复核

1. 上传每个8 MiB片，核对Git blob SHA1与片段SHA256；分批提交资源分支，失败后按片续传。清单未齐时`complete`为`false`。
2. 完成后锁定资源分支的完整40位commit SHA；[组装工作流](../.github/workflows/assemble-large-files.yml)只读取该commit，拒绝不完整清单。
3. Actions逐段流式拼接一个ZIP，核对范围、每段SHA256、Git片SHA1及完整ZIP SHA256。不解压工程，也不生成19份本地分卷副本。
4. 按原`release-files.json`的范围上传缺少的Release分卷，复用已有的正确分卷。GitHub返回的全部分卷大小与SHA256都一致后才公开Release。
5. 小型发布凭据作为Actions artifact保留，记录工程源commit、资源commit、完整ZIP哈希与各分卷ID/digest。

维护者在[Actions](https://github.com/hbzheng0942/greybox-to-multistyle-art-showcases/actions/workflows/assemble-large-files.yml)选择 **Run workflow**，输入完整资源commit；也可用已登录的GitHub CLI：

```sh
gh workflow run assemble-large-files.yml --ref main -f resources_commit=完整40位资源commit
```

仅重组和校验、不发布时，可在有足够磁盘的机器运行：

```sh
python3 tools/assemble_large_files.py --resources-commit 完整40位资源commit --assemble-only --output ./downloads
```

本版复用的输入分卷在首次发布前属于草稿，维护者本地重组时需通过环境变量`GH_TOKEN`提供已有授权；Actions自动使用本仓库的`GITHUB_TOKEN`。不要把token写入命令参数、清单、源码或日志。

## 已有完整ZIP的离线交接

将完整ZIP和`tools/extract_showcase.py`放在同一目录，运行：

```sh
python3 extract_showcase.py --output ./unpacked
```

脚本先校验完整ZIP哈希，再恢复包内相对资源链接。Windows不能创建符号链接时会还原为文件；已有文件不会被静默覆盖。保留整个解压目录，勿单独移动一个风格子目录。

本流程参考[playable-game-gallery的分片清单与Actions拼接](https://github.com/shencaiyiyi11-byte/playable-game-gallery/blob/main/.github/workflows/pages.yml)。该项目发布Web游戏；本仓库交付完整可编辑工程，云端输出为Release包。
