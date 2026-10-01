# 发布到 Steam 创意工坊

GitHub 合集用于维护源码，每个 Mod 可以作为独立创意工坊项目发布。

全圣心 Mod 已发布：[Steam 创意工坊页面](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689)。对应 ID 已保存在该 Mod 的 `metadata.xml` 中。

游戏安装目录中附带上传工具，Windows 下的位置为：

```text
tools/ModUploader/ModUploader.exe
```

工具的窗口标题可能仍显示 Afterbirth+，但可以用于 Repentance 和 Repentance+。

## 发布步骤

1. 登录拥有游戏的 Steam 账号，并运行游戏附带的 ModUploader。
2. 点击 **Choose Mod**，选中准备发布的 Mod 目录内的 `metadata.xml`。例如，先将本仓库的 `mods/all_sacred_hearts_stacking/` 文件夹复制到游戏使用的 Mod 目录，再选择其中的 `metadata.xml`。
3. 核对标题、说明、标签和可见性，并按工具要求选择预览图。
4. 点击 **Upload Mod**，成功后用 **View Mod** 打开创意工坊页面检查。
5. 若 Steam 要求接受创意工坊协议，需要通过该 Steam 账号完成。

首次上传后，上传工具会给 Mod 写入创意工坊 ID，并自动递增版本号。将上传后的 `metadata.xml` 同步回仓库，后续更新使用相同 ID，避免创建重复项目。

## 圣心 Mod 的发布文案

标题：**全圣心 + 伤害叠加 / All Sacred Hearts + Stacking**

说明可使用：

```text
适用于《以撒的结合：忏悔+》。

普通道具底座全部变成圣心（182），覆盖道具池、商店、普通 Boss 奖励和固定掉落。

保留全家福、照片、钥匙碎片、刀柄/刀刃、铲子组件、爸爸的便条、教条，
以及其他带任务标记的道具。

每多拿一颗圣心，伤害再乘 2.3，然后加 1。按当前持有数量计算，失去道具时刷新。

无需 REPENTOGON 或其他前置 Mod。

已通过 Lua 语法和回调模拟检查，尚未完成游戏内实测。

源码与下载：https://github.com/BMingSY/isaac-mods
```

工具使用参考：[Isaac Blueprints 上传教程](https://isaacblueprints.com/tutorials/crash_course/uploading_a_mod/)。
