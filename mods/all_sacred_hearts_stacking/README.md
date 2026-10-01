# 全圣心 + 伤害叠加

**All Sacred Hearts + Stacking · v1.2**

[Steam 创意工坊订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689) · [GitHub 安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.2/all_sacred_hearts_stacking-1.2.zip)

适用于《以撒的结合：忏悔+》，使用游戏自带 Lua 接口，无需 REPENTOGON 或其他前置 Mod。

## 效果

- 普通道具底座变成圣心（182），覆盖道具池、商店、普通 Boss 奖励、固定掉落、已存在的道具及原地重掷后的道具。
- 保留任务和路线道具。
- 重复获得圣心时继续叠加伤害：第一颗由游戏正常计算，每多一颗再执行一次 `伤害 = 当前伤害 × 2.3 + 1`。
- 按每个玩家当前实际持有的圣心数量计算，失去道具时刷新。切换房间或重新计算属性不会凭空增加层数。
- 保留底座的价格和二选一分组；拾取后的空底座不会补出新道具。

以初始伤害 3.5、无其他伤害效果的普通以撒为例，预期伤害如下：

| 圣心数量 | 伤害 |
| --- | --- |
| 0 | 3.5 |
| 1 | 9.05 |
| 2 | 21.815 |
| 3 | 51.1745 |

## 保留的任务道具

全家福、照片、两块钥匙碎片、刀柄和刀刃、两块破碎铲子、妈妈的铲子、爸爸的便条、教条均在保留名单中。除此之外，还会保留其他带 `ItemConfig.TAG_QUEST` 标记的道具。

## 安装

在 [Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689)点击订阅，启动游戏后在 **MODS** 菜单启用本 Mod。

也可以下载 [v1.2 安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.2/all_sacred_hearts_stacking-1.2.zip)，解压后将 `all_sacred_hearts_stacking` 文件夹放入游戏实际使用的 `mods` 目录，重启并启用。

详见[合集安装说明](https://github.com/BMingSY/isaac-mods#安装)。

## 范围和兼容性

这里的“道具”指房间里的 collectible 道具底座，角色初始背包和控制台直接添加的其他物品不做转换。金币、钥匙、炸弹、心、卡牌和饰品属于其他拾取物。

额外伤害叠加在游戏计算出的伤害上逐颗应用。其他 Mod 也修改伤害或替换道具时，最终结果可能受回调执行顺序影响。

## 验证情况

已通过 Lua 语法检查，并使用本机游戏的枚举和回调分发脚本进行了模拟检查，覆盖普通道具替换、11 个指定任务道具在各替换入口的保留、额外任务标记、空底座、分组保留、伤害叠加、失去道具、重复重算、继续游戏和多个玩家分别计算。

**尚未进行游戏内实测。** 模拟检查不验证游戏引擎内部的属性计算、路线或全部物品交互；价格保留通过核对 `Morph` 的 `KeepPrice` 参数检查。

游戏内可按以下步骤检查：

1. 开一局普通以撒，检查宝箱房、商店和普通 Boss 奖励是否为圣心。
2. 检查妈妈奖励的全家福/照片、天使雕像的钥匙碎片和支线刀组件是否保留。
3. 拿两颗以上圣心，检查伤害是否随数量继续增加；反复切换房间，检查伤害是否稳定。

如已开启调试控制台，`spawn 5.100.1` 应生成圣心，`spawn 5.100.327` 应保留全家福，`giveitem c182` 可用于测试多颗叠加。

## 版本记录

- **1.2**：首次发布到 Steam 创意工坊，补充中文发布说明、预览图和创意工坊 ID；上传工具自动递增版本号，游戏代码与 1.1 一致。
- **1.1**：保留指定路线道具和其他带任务标记的道具；统一道具池、实体生成和底座更新时的过滤规则。
- **1.0**：实现全部道具底座替换和重复圣心伤害叠加。

## 接口参考

- [ModCallbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html)
- [EntityPickup.Morph](https://wofsauge.github.io/IsaacDocs/rep/EntityPickup.html#Morph)
- [EntityPlayer.GetCollectibleNum](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html#GetCollectibleNum)
- [ItemConfigItem.HasTags](https://wofsauge.github.io/IsaacDocs/rep/ItemConfig_Item.html#HasTags)
