return function(items, getTargetID, selectTarget, defaultTarget)
    local registered
    local category, section = "All Items Into One", "Replacement"
    return function()
        local mcm = rawget(_G, "ModConfigMenu")
        if not mcm or mcm == registered or not mcm.AddSetting or not mcm.OptionType then
            return
        end
        if mcm.RemoveCategory then mcm.RemoveCategory(category) end
        mcm.AddSetting(category, section, {
            Type = mcm.OptionType.NUMBER,
            Minimum = 1,
            Maximum = items.maximumID(),
            ModifyBy = 1,
            Default = defaultTarget,
            CurrentSetting = getTargetID,
            Display = function()
                return "Target item ID: " .. getTargetID()
            end,
            DisplayTranslate = function()
                return "目标道具 ID：" .. getTargetID()
            end,
            OnChange = function(id)
                if type(id) ~= "number" or id ~= math.floor(id) then return end
                -- Skip unused IDs so a gap cannot trap the numeric selector.
                local step = id >= getTargetID() and 1 or -1
                while id >= 1 and id <= items.maximumID() do
                    if selectTarget(id) then return end
                    id = id + step
                end
            end,
            Info = { "Choose any valid collectible ID. For direct entry, use the console: allitems 329." },
            InfoTranslate = { "可选任意有效道具 ID；直接输入可用控制台命令：allitems 329。" },
        })
        registered = mcm
    end
end
