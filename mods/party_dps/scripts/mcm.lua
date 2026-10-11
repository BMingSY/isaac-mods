-- Optional public Mod Config Menu integration. Both menus share the same settings.
return function(settings, ui, saveSettings)
    local registered
    local category, section = "Party DPS", "Display"
    local anchors = { "bottom_left", "bottom_right", "top_left", "top_right" }
    local positions = { "Bottom left", "Bottom right", "Top left", "Top right" }
    local positionsCN = { "左下角", "右下角", "左上角", "右上角" }
    return function()
        local mcm = rawget(_G, "ModConfigMenu")
        if not mcm or mcm == registered or not mcm.AddSetting or not mcm.OptionType then
            return
        end
        if mcm.RemoveCategory then
            mcm.RemoveCategory(category)
        end
        mcm.UpdateCategory(category, {
            NameTranslate = "队伍 DPS",
            Info = { "Damage per second for you and your party." },
            InfoTranslate = { "显示自己和队友的每秒伤害、累计伤害与占比。" },
        })
        mcm.UpdateSubcategory(category, section, { NameTranslate = "面板" })
        local function add(option)
            mcm.AddSetting(category, section, option)
        end
        local function boolean(label, labelCN, get, set, default)
            add({
                Type = mcm.OptionType.BOOLEAN,
                Default = default,
                CurrentSetting = get,
                Display = function()
                    return label .. ": " .. (get() and "On" or "Off")
                end,
                DisplayTranslate = function()
                    return labelCN .. "：" .. (get() and "开" or "关")
                end,
                OnChange = function(value)
                    set(value)
                    saveSettings()
                end,
            })
        end
        boolean("Show panel", "显示面板", function()
            return settings.visible
        end, function(value)
            settings.visible = value
        end, true)
        add({
            Type = mcm.OptionType.NUMBER,
            Minimum = 1,
            Maximum = 2,
            ModifyBy = 1,
            Default = 1,
            CurrentSetting = function()
                return settings.mode == "run" and 2 or 1
            end,
            Display = function()
                return "Statistics: " .. (settings.mode == "run" and "Run" or "Encounter")
            end,
            DisplayTranslate = function()
                return "统计范围：" .. (settings.mode == "run" and "整局" or "本场战斗")
            end,
            OnChange = function(value)
                settings.mode = value == 2 and "run" or "encounter"
                saveSettings()
            end,
        })
        local function percentage(key, label, labelCN, minimum, maximum, default)
            add({
                Type = mcm.OptionType.NUMBER,
                Minimum = minimum,
                Maximum = maximum,
                ModifyBy = 5,
                Default = default,
                CurrentSetting = function()
                    return math.floor(settings[key] * 100 + 0.5)
                end,
                Display = function()
                    return label .. ": " .. math.floor(settings[key] * 100 + 0.5) .. "%"
                end,
                DisplayTranslate = function()
                    return labelCN .. "：" .. math.floor(settings[key] * 100 + 0.5) .. "%"
                end,
                OnChange = function(value)
                    settings[key] = math.max(minimum, math.min(maximum, value)) / 100
                    saveSettings()
                end,
            })
        end
        percentage("scale", "Panel size", "面板大小", 65, 125, 65)
        percentage("opacity", "Opacity", "背景不透明度", 30, 100, 90)
        add({
            Type = mcm.OptionType.NUMBER,
            Minimum = 1,
            Maximum = 4,
            ModifyBy = 1,
            Default = 1,
            CurrentSetting = function()
                for i, anchor in ipairs(anchors) do
                    if settings.anchor == anchor then
                        return i
                    end
                end
                return 1
            end,
            Display = function()
                for i, anchor in ipairs(anchors) do
                    if settings.anchor == anchor then
                        return "Position: " .. (settings.x and "Custom" or positions[i])
                    end
                end
            end,
            DisplayTranslate = function()
                for i, anchor in ipairs(anchors) do
                    if settings.anchor == anchor then
                        return "面板位置：" .. (settings.x and "自定义" or positionsCN[i])
                    end
                end
            end,
            OnChange = function(value)
                settings.anchor, settings.x, settings.y = anchors[value], nil, nil
                ui.drag = nil
                saveSettings()
            end,
        })
        boolean("Unlock dragging (F9)", "解锁拖动（F9）", function()
            return ui.unlocked
        end, function(value)
            ui.unlocked, ui.drag = value, nil
        end, false)
        add({
            Type = mcm.OptionType.BOOLEAN,
            Default = false,
            CurrentSetting = function()
                return false
            end,
            Display = "Reset position: press confirm",
            DisplayTranslate = "重置到左下角：按确认键",
            OnChange = function(value)
                if value then
                    ui:resetPosition()
                end
            end,
        })
        registered = mcm
    end
end
