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

首次上传后，上传工具会给 Mod 写入创意工坊 ID，并自动递增本地版本号。上传工具可能在打包后才递增版本，因此还需下载条目，核对包内 `metadata.xml` 的版本与仓库一致。后续更新使用相同 ID，避免创建重复项目。

## 道具替换与效果拆分

| 目录 | 英文标题 | 创意工坊 ID |
| --- | --- | --- |
| `all_items` | All Items Into One | [3825974753](https://steamcommunity.com/sharedfiles/filedetails/?id=3825974753) |
| `all_sacred_hearts_stacking` | Sacred Heart Stacking | 3811263689 |
| `all_ludovico_autoaim` | Ludovico Auto Aim | 3811712323 |
| `all_ludovico_autoaim_v2` | Ludovico Auto Aim V2 | 3811830257 |
| `all_bethlehem_snake` | Bethlehem Snake | 3813399534 |

原有目录名、创意工坊 ID 和 Lua 注册名保留，显示标题以 `metadata.xml` 为准；启明星队列继续读取原有存档。

发布前按仓库 `AGENTS.md` 将完整标题和说明交给用户审阅。各 Mod 的 `metadata.xml` 保存已发布的标题、说明、版本和创意工坊 ID。

[All Items Into One](https://steamcommunity.com/sharedfiles/filedetails/?id=3825974753) 已作为独立条目发布，四个效果 Mod 的迁移说明均链接到该条目。后续更新沿用各自的创意工坊 ID。已确认文案若再次修改，仍需重新审阅。

工具使用参考：[Isaac Blueprints 上传教程](https://isaacblueprints.com/tutorials/crash_course/uploading_a_mod/)。
