# 全圣心 + 伤害叠加

**All Sacred Hearts + Stacking · v1.3**

[Steam 创意工坊订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3811263689) · [GitHub 安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.3/all_sacred_hearts_stacking-1.3.zip)

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

也可以下载 [v1.3 安装包](https://github.com/BMingSY/isaac-mods/releases/download/all_sacred_hearts_stacking-v1.3/all_sacred_hearts_stacking-1.3.zip)，解压后将 `all_sacred_hearts_stacking` 文件夹放入游戏实际使用的 `mods` 目录，重启并启用。

详见[合集安装说明](https://github.com/BMingSY/isaac-mods#安装)。

## 范围和兼容性

这里的“道具”指房间里的 collectible 道具底座，角色初始背包和控制台直接添加的其他物品不做转换。金币、钥匙、炸弹、心、卡牌和饰品属于其他拾取物。

额外伤害叠加在游戏计算出的伤害上逐颗应用。其他 Mod 也修改伤害或替换道具时，最终结果可能受回调执行顺序影响。


## 版本记录

- **1.3**：更新创意工坊介绍和安装说明。
- **1.2**：首次发布到 Steam 创意工坊，补充中文发布说明、预览图和创意工坊 ID；上传工具自动递增版本号，游戏代码与 1.1 一致。
- **1.1**：保留指定路线道具和其他带任务标记的道具；统一道具池、实体生成和底座更新时的过滤规则。
- **1.0**：实现全部道具底座替换和重复圣心伤害叠加。

## 接口参考

- [ModCallbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html)
- [EntityPickup.Morph](https://wofsauge.github.io/IsaacDocs/rep/EntityPickup.html#Morph)
- [EntityPlayer.GetCollectibleNum](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html#GetCollectibleNum)
- [ItemConfigItem.HasTags](https://wofsauge.github.io/IsaacDocs/rep/ItemConfig_Item.html#HasTags)
