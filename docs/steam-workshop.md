# 发布到 Steam 创意工坊

GitHub 合集用于维护源码，每个 Mod 可以作为独立创意工坊项目发布。

Sacred Heart Stacking 沿用原条目：[Steam 创意工坊页面](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689)。对应 ID 已保存在该 Mod 的 `metadata.xml` 中。

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

## 道具替换与效果拆分

| 目录 | 英文标题 | 创意工坊 ID |
| --- | --- | --- |
| `all_items` | All Items Into One | 首次发布时新建 |
| `all_sacred_hearts_stacking` | Sacred Heart Stacking | 3811263689 |
| `all_ludovico_autoaim` | Ludovico Auto Aim | 3811712323 |
| `all_ludovico_autoaim_v2` | Ludovico Auto Aim V2 | 3811830257 |
| `all_bethlehem_snake` | Bethlehem Snake | 3813399534 |

原有目录名、创意工坊 ID 和 Lua 注册名保留，显示标题以 `metadata.xml` 为准；启明星队列继续读取原有存档。

发布前按仓库 `AGENTS.md` 将完整标题和说明交给用户审阅。当前 `metadata.xml` 中的说明是待审阅稿，不代表已经发布。

先创建 All Items Into One 的新条目，回填它自己的创意工坊 ID，再将新条目链接加入四个效果 Mod 的迁移说明；修改后的完整说明需再次审阅。随后更新四个原条目，并同步 README 中的发布状态。不要将效果 Mod 的旧 ID 用于新 Mod。

工具使用参考：[Isaac Blueprints 上传教程](https://isaacblueprints.com/tutorials/crash_course/uploading_a_mod/)。
