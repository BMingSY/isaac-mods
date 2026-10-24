# Isaac Mods · 以撒 Mod 合集

《以撒的结合：忏悔+》Mod 合集。

[GitHub 下载](https://github.com/BMingSY/isaac-mods/releases)

## Mod 列表

源码已将道具替换拆分为独立的 **All Items Into One**；四个效果 Mod 可单独启用，需要全道具玩法时再搭配使用。以下标注「待发布」的版本尚未更新到创意工坊。

| Mod | 效果 | 当前版本 | 下载 | 创意工坊 |
| --- | --- | --- | --- | --- |
| [All Items Into One](mods/all_items/) | 按配置的道具 ID 替换普通道具，保留任务和路线道具 | 0.1（待发布） | — | 待发布 |
| [Sacred Heart Stacking](mods/all_sacred_hearts_stacking/) | 重复圣心叠加伤害 | 1.4（待发布） | — | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689) |
| [Ludovico Auto Aim](mods/all_ludovico_autoaim/) | 持有鲁多维科时，按攻击方向键切换自动索敌 | 0.4（待发布） | — | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811712323) |
| [Ludovico Auto Aim V2](mods/all_ludovico_autoaim_v2/) | 每份鲁多维科对应一颗同尺寸大球，共享属性、独立索敌 | 0.4（待发布） | — | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811830257) |
| [真·谷底石](mods/true_rock_bottom/) | 保留的历史最高属性成为后续加成的计算基准 | 0.5 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/true_rock_bottom-v0.5/true_rock_bottom-0.5.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3812009224) |
| [Bethlehem Snake](mods/all_bethlehem_snake/) | 多颗启明星沿原版路线排队，按队尾位置调速，共享叠加光环 | 0.6（待发布） | — | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3813399534) |
| [D6 通关宝箱](mods/d6_ending_chest/) | D6 将可重置的普通道具变为通关大宝箱，接触后触发虚空层结局，保留任务道具 | 0.1 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/d6_ending_chest-v0.1/d6_ending_chest-0.1.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3813446674) |
| [坨坨变身](mods/poop_boss_forms/) | 大便变身为坨坨／滑坨坨及原版变异，Ctrl 选择形态，Boss 弹幕与召唤，一充能副手冲刺，屁股炸弹和接触大便招募粪滴 | 1.2 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/poop_boss_forms-v1.2/poop_boss_forms-1.2.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3814236696) |
| [队伍 DPS](mods/party_dps/) | 左下角独立 DPS 排行，显示自己／队友伤害与占比，支持 Mod Config Menu 及 isaac-lan 房主同步 | 0.1.2 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/party_dps-v0.1.2/party_dps-0.1.2.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3817783724) |
| [局域网联机](https://github.com/BMingSY/isaac-lan) | 2–4 人共享楼层、分房探索与战斗，支持 Mod |  |  |  |

## 安装

点击对应 Mod 的 **Steam 订阅** 链接，在创意工坊页面订阅，启动游戏后在 **MODS** 菜单启用。

手动安装步骤如下：

1. 下载上表中需要的 Mod 安装包，解压后得到一个独立 Mod 文件夹。
2. 找到游戏实际使用的 `mods` 目录。可以从 Steam 的“管理 → 浏览本地文件”打开游戏目录，再查看 `savedatapath.txt` 中的 **Modding Data Path**；以游戏记录的位置为准。
3. 将解压得到的 Mod 文件夹放入 `mods`，确保 `main.lua` 和 `metadata.xml` 直接位于该 Mod 文件夹内。
4. 重启游戏，在 **MODS** 菜单启用对应 Mod。

也可以下载仓库源码，只复制 `mods/` 下需要的 Mod 文件夹。各 Mod 的详细说明见上方列表。

## 问题与建议

问题和建议可以提交到 [Issues](https://github.com/BMingSY/isaac-mods/issues)，请写明 Mod 名称、游戏版本、复现步骤和使用的其他 Mod。

## Skill

[以撒 Mod 编写](skills/isaac-mod-development/SKILL.md)
