--[[
@module page_set
@summary 车辆设置页：左卡（模式分段 / 车速 / 俯视车 / PRND / 电量）+ 右卡（标签 + 列表）
布局与 preview.html 对应：set-left 296 宽 / set-right 弹性
]]

local theme = require "theme"
local W, H, TOP = theme.W, theme.H, theme.TOP_H

theme.make_page("set", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    theme.topbar(root, "back", false)

    local BY, BH = TOP + 2, H - TOP - 14
    local LX, LW = 16, 296
    local RX, RW = 16 + 296 + 12, W - 32 - 296 - 12

    ----------------------------------------------------------------
    -- 左卡
    ----------------------------------------------------------------
    theme.card(root, { x = LX, y = BY, w = LW, h = BH })
    -- 模式分段（2×2）
    local seg_y = BY + 12
    local segw = math.floor((LW - 24 - 8) / 2)
    local seg_lbls = {}
    for i, s in ipairs(MOCK.set.segs) do
        local r, c2 = math.floor((i - 1) / 2), (i - 1) % 2
        local x = LX + 12 + c2 * (segw + 8)
        local yy = seg_y + r * 38
        theme.pill(root, { x = x, y = yy, w = segw, h = 30, radius = 9 }, s,
            { bg = (i == MOCK.set.seg_idx) and C.sel_str or C.sel,
              color = (i == MOCK.set.seg_idx) and C.bright or C.sub,
              border = (i == MOCK.set.seg_idx) and C.blue2 or C.line2 })
        local b = airui.container({ parent = root, x = x, y = yy, w = segw, h = 30,
            color = C.bg, color_opacity = 1, radius = 9 })
        b:set_on_click(function()
            db(function()
                MOCK.set.seg_idx = i
                theme.rerender_current()
            end)
        end)
    end

    -- 车速
    airui.label({ parent = root, x = LX + 14, y = seg_y + 84, w = 90, h = 48,
        text = tostring(MOCK.set.speed), color = C.text, font_size = 44 })
    airui.label({ parent = root, x = LX + 100, y = seg_y + 112, w = 60, h = 22,
        text = "km", color = C.sub, font_size = 16 })

    -- 俯视小车：按左卡剩余空间放大到 240（原来 190，车下到电量条之间空 110px）
    local cx = LX + math.floor(LW / 2)
    local cy = seg_y + 168
    local CR = 240
    theme.shapes(root, cx - math.floor(CR / 2), cy, CR, CR, {
        { type = "circle", cx = 120, cy = 131, r = 93, color = 0x16202E, width = 1,
          fill = true, fill_color = 0x16202E, fill_opacity = 220 },
        { type = "rect", x = 76, y = 20, w = 88, h = 200, color = 0xC21E33, width = 1,
          radius = 38, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
        { type = "rect", x = 78, y = 28, w = 58, h = 8, color = 0xF0455C, width = 1,
          radius = 4, fill = true, fill_color = 0xF0455C, fill_opacity = 220 },
        { type = "rect", x = 88, y = 50, w = 63, h = 50, color = 0x2A1218, width = 1,
          radius = 13, fill = true, fill_color = 0x2A1218, fill_opacity = 255 },
        { type = "rect", x = 93, y = 76, w = 53, h = 48, color = 0x4A1A22, width = 1,
          radius = 10, fill = true, fill_color = 0x4A1A22, fill_opacity = 255 },
        { type = "rect", x = 88, y = 149, w = 63, h = 50, color = 0x2A1218, width = 1,
          radius = 13, fill = true, fill_color = 0x2A1218, fill_opacity = 255 },
    })

    -- PRND
    local gears = { "P", "R", "N", "D" }
    for i, g in ipairs(gears) do
        local gx = LX + 30 + (i - 1) * 62
        local on = (MOCK.set.gear == g)
        airui.label({ parent = root, x = gx, y = cy + 250, w = 30, h = 24, text = g,
            color = on and C.blue2 or C.dim, font_size = 18,
            align = airui.TEXT_ALIGN_CENTER })
        local b = airui.container({ parent = root, x = gx - 8, y = cy + 246, w = 46, h = 32,
            color = C.bg, color_opacity = 1 })
        b:set_on_click(function()
            db(function()
                MOCK.gear_pick(g)
                theme.rerender_current()
            end)
        end)
    end

    -- 电量条
    local bat_y = BY + BH - 38
    airui.label({ parent = root, x = LX + 14, y = bat_y - 4, w = 60, h = 26,
        text = MOCK.car.ev .. "%", color = C.blue2, font_size = 20 })
    airui.container({ parent = root, x = LX + 74, y = bat_y + 5, w = 110, h = 6,
        color = C.track, radius = 3 })
    airui.container({ parent = root, x = LX + 74, y = bat_y + 5,
        w = math.floor(110 * MOCK.car.ev / 100), h = 6,
        color = theme.blend(C.blue2, C.cyan, 0.4), radius = 3 })
    airui.label({ parent = root, x = LX + 190, y = bat_y - 2, w = 100, h = 22,
        text = "预计可行驶" .. MOCK.car.range .. "km", color = C.dim, font_size = 16 })

    ----------------------------------------------------------------
    -- 右卡
    ----------------------------------------------------------------
    theme.card(root, { x = RX, y = BY, w = RW, h = BH })
    -- 标签（6 个，自动换行成两行）
    local tw = math.floor((RW - 28 - 5 * 8) / 6)
    local tab_y = BY + 12
    for i, t in ipairs(MOCK.set.tabs) do
        local r = math.floor((i - 1) / 6)
        local x = RX + 14 + (i - 1) % 6 * (tw + 8)
        local yy = tab_y + r * 38
        theme.pill(root, { x = x, y = yy, w = tw, h = 30, radius = 9 }, t,
            { bg = (i == MOCK.set.tab_idx) and C.sel_str or C.sel,
              color = (i == MOCK.set.tab_idx) and C.bright or C.sub,
              border = (i == MOCK.set.tab_idx) and C.blue2 or C.line2 })
        local b = airui.container({ parent = root, x = x, y = yy, w = tw, h = 30,
            color = C.bg, color_opacity = 1, radius = 9 })
        b:set_on_click(function()
            db(function()
                MOCK.set.tab_idx = i
                theme.rerender_current()
            end)
        end)
    end

    -- 设置列表（6 行：标题 + 副标题 + 开启/关闭 开关，对照 .set-row）
    local rows = MOCK.set_rows()
    local n = #rows
    local ly0 = tab_y + 84
    local rh = math.floor((BH - 84 - 12) / math.max(1, n))
    local sw_w, sw_h = 104, 32
    local sw_x = RX + RW - 16 - sw_w
    local txt_w = sw_x - (RX + 16) - 12
    for i, r in ipairs(rows) do
        local yy = ly0 + (i - 1) * rh
        local ty = yy + math.floor(rh / 2) - 24
        airui.label({ parent = root, x = RX + 16, y = ty, w = txt_w, h = 23,
            text = r.t, color = C.title, font_size = 17 })
        airui.label({ parent = root, x = RX + 16, y = ty + 23, w = txt_w, h = 22,
            text = r.s, color = C.dim, font_size = 16 })
        if i < n then
            airui.container({ parent = root, x = RX + 16, y = yy + rh - 1,
                w = RW - 32, h = 1, color = C.line2 })
        end

        -- 开关：104×32 胶囊 + 左右两段「开启 / 关闭」
        local sy = yy + math.floor((rh - sw_h) / 2)
        airui.container({ parent = root, x = sw_x, y = sy, w = sw_w, h = sw_h,
            color = theme.blend(C.page, 0x0A1626, 0.9), radius = 16,
            border_color = C.line, border_width = 1 })
        local seg_w = math.floor(sw_w / 2)
        for k = 1, 2 do
            local want = (k == 1)                       -- 1=开启 2=关闭
            local active = (r.on == want)
            local sx = sw_x + (k - 1) * seg_w + 2
            if active then
                airui.container({ parent = root, x = sx, y = sy + 2, w = seg_w - 4,
                    h = sw_h - 4, radius = 14, color = 0x4E97FF })
            end
            airui.label({ parent = root, x = sx, y = sy + 6, w = seg_w - 4, h = 22,
                text = want and "开启" or "关闭",
                color = active and 0x04101F or C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            local ii, vv, name = i, want, r.t
            theme.click(root, sx, sy + 2, seg_w - 4, sw_h - 4, function()
                MOCK.set_toggle(ii, vv)
                theme.rerender_current()
                sys.timerStart(function()
                    theme.toast(name .. (vv and " 已开启" or " 已关闭"))
                end, 60)
            end, 8)
        end
    end
end)
