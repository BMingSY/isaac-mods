# Isaac Mods · 以撒 Mod 合集

《以撒的结合：忏悔+》Mod 合集。

[GitHub 下载](https://github.com/BMingSY/isaac-mods/releases)

## Mod 列表

| Mod | 效果 | 当前版本 | 下载 | 创意工坊 |
| --- | --- | --- | --- | --- |
| [全圣心 + 伤害叠加](mods/all_sacred_hearts_stacking/) | 普通道具变为圣心，重复圣心叠加伤害，保留任务和路线道具 | 1.3 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.3/all_sacred_hearts_stacking-1.3.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689) |
| [全鲁多维科 + 自动索敌](mods/all_ludovico_autoaim/) | 普通道具变为鲁多维科科技，按攻击方向键切换自动索敌，保留任务道具 | 0.3 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_ludovico_autoaim-v0.3/all_ludovico_autoaim-0.3.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811712323) |
| [全鲁多维科 + 自动索敌 V2](mods/all_ludovico_autoaim_v2/) | 普通道具变为鲁多维科科技，重复拾取改为同尺寸大球，共享属性、独立索敌，保留任务道具 | 0.3 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_ludovico_autoaim_v2-v0.3/all_ludovico_autoaim_v2-0.3.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811830257) |
| [真·谷底石](mods/true_rock_bottom/) | 保留的历史最高属性成为后续加成的计算基准 | 0.4 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/true_rock_bottom-v0.4/true_rock_bottom-0.4.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3812009224) |
| [全启明星 + 贪吃蛇队列](mods/all_bethlehem_snake/) | 普通道具变为启明星，多颗星星沿原版路线排队，按队尾位置调速，全部光环共享叠加效果 | 0.5 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_bethlehem_snake-v0.5/all_bethlehem_snake-0.5.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3813399534) |
| [D6 通关宝箱](mods/d6_ending_chest/) | D6 将可重置的普通道具变为通关大宝箱，接触后触发虚空层结局，保留任务道具 | 0.1 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/d6_ending_chest-v0.1/d6_ending_chest-0.1.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3813446674) |
| [坨坨变身](mods/poop_boss_forms/) | 大便变身为坨坨／滑坨坨及原版变异，Ctrl 选择形态，Boss 弹幕与召唤，一充能副手冲刺，屁股炸弹和接触大便招募粪滴 | 1.2 | [安装包](https://github.com/BMingSY/isaac-mods/releases/download/poop_boss_forms-v1.2/poop_boss_forms-1.2.zip) | [Steam 订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3814236696) |
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
