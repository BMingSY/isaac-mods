return function(settings, saveSettings)
    local ui = {
        settings = settings,
        unlocked = false,
        keys = {},
        mouseDown = false,
        menuOpen = false,
        selected = 1,
    }
    local font, pixel = Font(), Sprite()
    font:Load("font/pftempestasevencondensed.fnt")
    pixel:Load("gfx/party_dps/pixel.anm2", true)
    pixel:Play("Idle", true)
    local WHITE, MUTED = KColor(0.93, 0.95, 1, 1), KColor(0.59, 0.65, 0.73, 1)
    local PALETTE = {
        { 0.27, 0.66, 0.94 },
        { 0.90, 0.39, 0.46 },
        { 0.47, 0.76, 0.42 },
        { 0.72, 0.51, 0.91 },
    }
    local BASE_WIDTH = 256
    local labels = {}
    local function snap(value)
        return math.floor(value + 0.5)
    end
    local function rectangle(x, y, w, h, r, g, b, a)
        if w <= 0 or h <= 0 then
            return
        end
        pixel.Scale, pixel.Color = Vector(snap(w), snap(h)), Color(r, g, b, a or 1)
        pixel:Render(Vector(snap(x), snap(y)), Vector.Zero, Vector.Zero)
    end
    local function fit(label, width)
        if not width or font:GetStringWidth(label) <= width then
            return label
        end
        while #label > 0 and font:GetStringWidth(label .. "...") > width do
            label = label:sub(1, -2)
        end
        return label .. "..."
    end
    local function text(label, x, y, color, width)
        label = fit(tostring(label), width)
        -- Explicit alignment keeps the measured bounds and actual pixels identical.
        if width then
            x = x + width - font:GetStringWidth(label)
        end
        labels[#labels + 1] = { label, snap(x), snap(y), color or WHITE }
    end
    local function flushText()
        -- No row background can be painted over previously drawn text.
        for _, label in ipairs(labels) do
            font:DrawStringScaled(label[1], label[2], label[3], 1, 1, label[4], 0, false)
        end
        labels = {}
    end
    local function compact(value, width)
        local unit, divisor = "", 1
        for _, entry in ipairs({ { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } }) do
            if value >= entry[1] then
                divisor, unit = entry[1], entry[2]
                break
            end
        end
        local label = string.format("%.1f", value / divisor) .. unit
        if width and font:GetStringWidth(label) > width then
            label = string.format("%.0f", value / divisor) .. unit
        end
        return label
    end
    local function pressed(key)
        local down = Input.IsButtonPressed(key, 0)
        local edge = down and not ui.keys[key]
        ui.keys[key] = down
        return edge
    end
    local function inside(p, x, y, w, h)
        return p.X >= x and p.X <= x + w and p.Y >= y and p.Y <= y + h
    end
    local anchors = { "bottom_left", "bottom_right", "top_left", "top_right" }
    local anchorNames = { "Bottom left", "Bottom right", "Top left", "Top right" }
    local function anchorIndex()
        for i, anchor in ipairs(anchors) do
            if settings.anchor == anchor then
                return i
            end
        end
        return 1
    end
    local function change(row, direction)
        if row == 1 then
            settings.visible = not settings.visible
        elseif row == 2 then
            settings.mode = settings.mode == "run" and "encounter" or "run"
        elseif row == 3 then
            settings.scale = math.max(0.65, math.min(1.25, settings.scale + direction * 0.05))
        elseif row == 4 then
            settings.opacity = math.max(0.3, math.min(1, settings.opacity + direction * 0.05))
        elseif row == 5 then
            settings.anchor = anchors[(anchorIndex() - 1 + direction) % #anchors + 1]
            settings.x, settings.y = nil, nil
        elseif row == 6 then
            ui.unlocked = not ui.unlocked
        elseif row == 7 then
            settings.x, settings.y, settings.anchor = nil, nil, "bottom_left"
        end
        saveSettings()
    end
    local function renderMenu(mouse, down, edge)
        if not ui.menuOpen then
            return
        end
        local x, y = (Isaac.GetScreenWidth() - 244) / 2, (Isaac.GetScreenHeight() - 180) / 2
        local mouseMoved = not ui.menuMouse
            or ui.menuMouse.X ~= mouse.X
            or ui.menuMouse.Y ~= mouse.Y
        ui.menuMouse = { X = mouse.X, Y = mouse.Y }
        if pressed(Keyboard.KEY_ESCAPE) then
            ui.menuOpen = false
            return
        end
        if pressed(Keyboard.KEY_UP) then
            ui.selected = (ui.selected - 2) % 7 + 1
        end
        if pressed(Keyboard.KEY_DOWN) then
            ui.selected = ui.selected % 7 + 1
        end
        if pressed(Keyboard.KEY_LEFT) then
            change(ui.selected, -1)
        end
        if pressed(Keyboard.KEY_RIGHT) or pressed(Keyboard.KEY_ENTER) then
            change(ui.selected, 1)
        end
        local options = {
            { "Show panel", settings.visible and "On" or "Off" },
            { "Statistics", settings.mode == "run" and "Run" or "Encounter" },
            { "Scale", string.format("%d%%", math.floor(settings.scale * 100 + 0.5)) },
            { "Opacity", string.format("%d%%", math.floor(settings.opacity * 100 + 0.5)) },
            { "Position", settings.x and "Custom" or anchorNames[anchorIndex()] },
            { "Move panel", ui.unlocked and "Unlocked" or "Locked" },
            { "Reset position", "Bottom left" },
        }
        rectangle(x - 1, y - 1, 246, 182, 0.27, 0.66, 0.94)
        rectangle(x, y, 244, 180, 0.055, 0.068, 0.09, 0.98)
        rectangle(x, y, 244, 22, 0.105, 0.13, 0.18)
        text("PARTY DPS SETTINGS", x + 10, y + 7)
        text("F6 CLOSE", x + 165, y + 7, MUTED, 69)
        for i, option in ipairs(options) do
            local ry = y + 28 + (i - 1) * 18
            local hover = inside(mouse, x + 6, ry, 232, 17)
            if hover and (mouseMoved or edge) then
                ui.selected = i
            end
            if ui.selected == i then
                rectangle(x + 6, ry, 232, 17, 0.15, 0.27, 0.39, 0.95)
            end
            text(option[1], x + 12, ry + 4)
            text(option[2], x + 123, ry + 4, WHITE, 92)
            text("<", x + 108, ry + 4, MUTED)
            text(">", x + 225, ry + 4, MUTED)
            if hover and edge then
                change(i, mouse.X < x + 123 and -1 or 1)
            end
        end
        text("Click / arrows to adjust | Enter to select", x + 10, y + 163, MUTED)
        flushText()
    end
    function ui:render(view, localOwners, status)
        local mcm = rawget(_G, "ModConfigMenu")
        if mcm and mcm.IsVisible then
            self.menuOpen, self.drag = false, nil
            return
        end
        if pressed(Keyboard.KEY_F6) then
            self.menuOpen = not self.menuOpen
            self.drag = nil
        end
        if pressed(Keyboard.KEY_F8) then
            settings.visible = not settings.visible
            saveSettings()
        end
        if pressed(Keyboard.KEY_F7) then
            settings.mode = settings.mode == "run" and "encounter" or "run"
            saveSettings()
        end
        if pressed(Keyboard.KEY_F9) then
            self.unlocked = not self.unlocked
            self.drag = nil
        end
        local rawMouse = Isaac.WorldToScreen(Input.GetMousePosition(true))
        local down = Input.IsMouseBtnPressed(0)
        local mouseEdge = down and not self.mouseDown
        if not settings.visible then
            renderMenu(rawMouse, down, mouseEdge)
            self.mouseDown = down
            return
        end
        local count = math.max(1, #view.rows)
        -- One coordinate space: every dimension is in screen pixels. Font metrics
        -- set the minimum cell size before the requested panel size is applied.
        local line = math.max(font:GetLineHeight(), font:GetBaselineHeight() + 2)
        local pad, gap = 6, 6
        local numberWidth = math.max(font:GetStringWidth("999.9m"), font:GetStringWidth("DMG")) + 2
        local percentWidth = math.max(font:GetStringWidth("100.0"), font:GetStringWidth("%")) + 2
        local minWidth = 2 * pad
            + 3 * gap
            + 2 * numberWidth
            + percentWidth
            + font:GetStringWidth("PLAYER")
        local width = math.max(snap(BASE_WIDTH * settings.scale), minWidth)
        local rowHeight = math.max(line + 3, snap(17 * settings.scale))
        local header = rowHeight + 2
        local columns, footer = rowHeight, rowHeight
        local height = header
            + columns
            + rowHeight * count
            + footer
            + (self.unlocked and footer or 0)
        local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
        local anchor = settings.anchor
        -- Vanilla draws its stats after Mod rendering. Reserve that column when
        -- using a left anchor; an explicitly dragged position remains the user's.
        local leftMargin = Options and Options.FoundHUD and 96 + snap((Options.HUDOffset or 0) * 20)
            or 14
        local x = settings.x and settings.x * sw
            or (anchor == "bottom_right" or anchor == "top_right") and sw - width - 14
            or leftMargin
        local y = settings.y and settings.y * sh
            or (anchor == "top_left" or anchor == "top_right") and 82
            or sh - height - 18
        x, y =
            snap(math.max(4, math.min(sw - width - 4, x))),
            snap(math.max(4, math.min(sh - height - 4, y)))
        local mouse = rawMouse
        if
            not self.menuOpen
            and self.unlocked
            and mouseEdge
            and inside(mouse, x, y, width, header)
        then
            self.drag = { x = mouse.X - x, y = mouse.Y - y }
        end
        if self.drag and down then
            x = snap(math.max(4, math.min(sw - width - 4, mouse.X - self.drag.x)))
            y = snap(math.max(4, math.min(sh - height - 4, mouse.Y - self.drag.y)))
            settings.x, settings.y = x / sw, y / sh
        elseif self.drag then
            self.drag = nil
            saveSettings()
        end
        rectangle(x - 1, y - 1, width + 2, height + 2, 0.28, 0.35, 0.43, 0.8)
        rectangle(x, y, width, height, 0.055, 0.068, 0.09, settings.opacity)
        rectangle(x, y, width, header, 0.105, 0.13, 0.18, 1)
        rectangle(x, y, 3, header, 0.27, 0.66, 0.94)
        local titleY = y + math.floor((header - line) / 2)
        text("PARTY DPS", x + pad, titleY)
        local minutes, seconds = math.floor(view.seconds / 60), math.floor(view.seconds % 60)
        local summary = (settings.mode == "run" and "RUN " or "FIGHT ")
            .. string.format("%02d:%02d", minutes, seconds)
        local summaryX = x + pad + font:GetStringWidth("PARTY DPS") + gap
        text(summary, summaryX, titleY, MUTED, x + width - pad - 8 - summaryX)
        rectangle(
            x + width - pad - 4,
            y + math.floor((header - 4) / 2),
            4,
            4,
            view.active and 0.42 or 0.5,
            view.active and 0.85 or 0.52,
            0.48
        )
        local shareX = x + width - pad - percentWidth
        local damageX = shareX - gap - numberWidth
        local dpsX = damageX - gap - numberWidth
        local nameWidth = dpsX - gap - (x + pad)
        local columnY = y + header + math.floor((columns - line) / 2)
        text("PLAYER", x + pad, columnY, MUTED)
        text("DPS", dpsX, columnY, MUTED, numberWidth)
        text("DMG", damageX, columnY, MUTED, numberWidth)
        text("%", shareX, columnY, MUTED, percentWidth)
        local leading = view.rows[1] and view.rows[1].damage or 0
        for i, row in ipairs(view.rows) do
            local ry = y + header + columns + (i - 1) * rowHeight
            local c = PALETTE[row.owner] or PALETTE[1]
            rectangle(x + 4, ry + 1, width - 8, rowHeight - 2, 0.13, 0.16, 0.20, 0.65)
            local ratio = leading > 0 and row.damage / leading or 0
            rectangle(x + 4, ry + 1, (width - 8) * ratio, rowHeight - 2, c[1], c[2], c[3], 0.38)
            rectangle(x + 4, ry + 1, 2, rowHeight - 2, c[1], c[2], c[3])
            local label = "P" .. row.owner .. " " .. (localOwners[row.owner] and "YOU" or row.name)
            local ty = ry + math.floor((rowHeight - line) / 2)
            text(fit(label, nameWidth), x + pad, ty)
            text(compact(row.dps, numberWidth), dpsX, ty, WHITE, numberWidth)
            text(compact(row.damage, numberWidth), damageX, ty, WHITE, numberWidth)
            text(string.format("%.1f", row.percent), shareX, ty, WHITE, percentWidth)
        end
        if #view.rows == 0 then
            text(
                fit(status or "Waiting for damage", width - 2 * pad),
                x + pad,
                y + header + columns + math.floor((rowHeight - line) / 2),
                MUTED
            )
        end
        local fy = y + header + columns + count * rowHeight
        local footerY = fy + math.floor((footer - line) / 2)
        text(
            fit(status or ("TOTAL " .. compact(view.dps) .. " DPS"), width - 2 * pad),
            x + pad,
            footerY,
            MUTED
        )
        if self.unlocked then
            text(fit("Drag header | F9 lock", width - 2 * pad), x + pad, footerY + footer, MUTED)
        end
        flushText()
        renderMenu(rawMouse, down, mouseEdge)
        self.mouseDown = down
    end
    function ui:resetPosition()
        settings.x, settings.y, settings.anchor = nil, nil, "bottom_left"
        self.drag = nil
        saveSettings()
    end
    return ui
end
