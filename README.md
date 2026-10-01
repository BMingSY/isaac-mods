# Isaac Mods · 以撒 Mod 合集

《以撒的结合：忏悔+》Lua Mod 合集。每个 Mod 使用独立目录、独立版本和独立下载包，可以按需安装，后续新 Mod 也放在这个仓库中。

## Mod 列表

| Mod | 效果 | 当前版本 | 下载 |
| --- | --- | --- | --- |
| [全圣心 + 伤害叠加](mods/all_sacred_hearts_stacking/) | 普通道具变为圣心，重复圣心叠加伤害，保留任务和路线道具 | 1.1 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.1/all_sacred_hearts_stacking-1.1.zip) |

## 安装

1. 下载上表中需要的 Mod 安装包，解压后得到一个独立 Mod 文件夹。
2. 找到游戏实际使用的 `mods` 目录。可以从 Steam 的“管理 → 浏览本地文件”打开游戏目录，再查看 `savedatapath.txt` 中的 **Modding Data Path**；以游戏记录的位置为准。
3. 将解压得到的 Mod 文件夹放入 `mods`，确保 `main.lua` 和 `metadata.xml` 直接位于该 Mod 文件夹内。
4. 重启游戏，在 **MODS** 菜单启用对应 Mod。

也可以下载仓库源码，只复制 `mods/` 下需要的 Mod 文件夹。各 Mod 的兼容范围、效果、验证情况和限制写在各自的说明里。

## 仓库结构

```text
mods/
  all_sacred_hearts_stacking/
    main.lua
    metadata.xml
    README.md
scripts/
  package_mods.py
docs/
  steam-workshop.md
```

## 添加新 Mod

在 `mods/<mod目录名>/` 中添加 Mod 文件和说明。`metadata.xml` 的 `directory` 应与文件夹名称一致，`version` 表示该 Mod 的独立版本。再更新上方列表。

用 Python 3 打包全部 Mod：

```sh
python3 scripts/package_mods.py
```

或只打包指定 Mod：

```sh
python3 scripts/package_mods.py all_sacred_hearts_stacking
```

安装包生成在 `dist/` 下，名称为 `<mod目录名>-<版本>.zip`，压缩包中只有一个可直接安装的 Mod 文件夹。

发布时建议每个 Mod 使用独立标签，例如 `all_sacred_hearts_stacking-v1.1`，并在对应 GitHub Release 中附上安装包。

## Steam 创意工坊

合集仓库用于统一维护源码。每个 Mod 也可以单独发布到 Steam 创意工坊，步骤见 [发布说明](docs/steam-workshop.md)。

问题和建议可以提交到 [Issues](https://github.com/BMingSY/isaac-mods/issues)，请写明 Mod 名称、游戏版本、复现步骤和使用的其他 Mod。
