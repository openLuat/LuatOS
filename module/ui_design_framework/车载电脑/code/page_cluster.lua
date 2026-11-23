--[[
@module page_cluster
@summary 仪表盘页：油量柱 / 双速度表盘 / ADAS 场景 / 电量与档位栏
布局与 preview.html 对应：cl-top 54 / cl-bottom 54 / 主表盘 236 / 副表盘 190
]]

local theme = require "theme"
local _ln, _ci, _rc = theme._ln, theme._ci, theme._rc
local W, H = theme.W, theme.H

theme.make_page("cluster", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    -- 背景 + 光晕（半径必须收在画布内：r=360 会甩到屏幕外，留下色块残影）
    theme.shapes(root, 0, 0, W, H, {
        { type = "circle", cx = 340, cy = 340, r = 260,
          color = theme.blend(0x14468C, C.bg, 0.30), width = 1,
          fill = true, fill_color = theme.blend(0x14468C, C.bg, 0.30),
          fill_opacity = 255 },
    })

    ----------------------------------------------------------------
    -- 顶栏 54
    ----------------------------------------------------------------
    local ty = 17
    airui.label({ parent = root, x = 240, y = ty, w = 120, h = 24,
        text = MOCK.cluster.time, color = C.name, font_size = 17 })
    airui.label({ parent = root, x = 380, y = ty, w = 90, h = 24,
        text = MOCK.cluster.weather, color = C.name, font_size = 17 })
    -- 模式切换
    theme.icon(root, 486, ty + 4, 16, "left", C.green)
    airui.label({ parent = root, x = 506, y = ty, w = 90, h = 24,
        text = MOCK.cluster.modes[MOCK.cluster.mode_idx], color = C.green,
        font_size = 16, align = airui.TEXT_ALIGN_CENTER })
    theme.icon(root, 600, ty + 4, 16, "right", C.green)
    local mdo = theme.debounce()
    local la = airui.container({ parent = root, x = 482, y = ty, w = 20, h = 24,
        color = C.bg, color_opacity = 1 })
    la:set_on_click(function() db(function() MOCK.cluster_mode(-1) theme.rerender_current() end) end)
    local ra = airui.container({ parent = root, x = 596, y = ty, w = 20, h = 24,
        color = C.bg, color_opacity = 1 })
    ra:set_on_click(function() db(function() MOCK.cluster_mode(1) theme.rerender_current() end) end)
    airui.label({ parent = root, x = 640, y = ty, w = 110, h = 24,
        text = MOCK.cluster.dir, color = C.green, font_size = 17 })
    airui.label({ parent = root, x = W - 180, y = ty, w = 158, h = 24,
        text = MOCK.cluster.total, color = C.sub, font_size = 16,
        align = airui.TEXT_ALIGN_RIGHT })

    ----------------------------------------------------------------
    -- 主区
    ----------------------------------------------------------------
    -- 左侧油量柱
    local bx = 22
    local bcy = math.floor(H * 0.5) - 20
    airui.label({ parent = root, x = bx - 4, y = bcy - 84, w = 24, h = 22, text = "F",
        color = C.sub, font_size = 18, align = airui.TEXT_ALIGN_CENTER })
    theme.icon(root, bx - 3, bcy - 52, 22, "seat", C.name)
    airui.container({ parent = root, x = bx, y = bcy - 24, w = 5, h = 150,
        color = C.track, radius = 3 })
    local fh = math.floor(150 * MOCK.cluster.fuel / 100)
    airui.container({ parent = root, x = bx, y = bcy - 24 + 150 - fh, w = 5, h = fh,
        color = theme.blend(C.cyan, C.blue, 0.4), radius = 3 })
    airui.label({ parent = root, x = bx - 4, y = bcy + 132, w = 24, h = 22, text = "E",
        color = C.sub, font_size = 18, align = airui.TEXT_ALIGN_CENTER })

    -- 主表盘（236）
    local R1, R2 = 236, 190
    local cx1 = 62 + math.floor(R1 / 2)
    local cy1 = math.floor(H / 2) - math.floor(R1 * 0.52) + math.floor(R1 / 2)
    local function dial(cx, cy, r)
        theme.shapes(root, cx - r, cy - r, 2 * r, 2 * r, {
            { type = "circle", cx = r, cy = r, r = r, color = 0x123E86, width = 1,
              fill = true, fill_color = 0x0B2559, fill_opacity = 255 },
            { type = "circle", cx = r, cy = r, r = math.floor(r * 0.52),
              color = 0x061529, width = 1, fill = true,
              fill_color = 0x061529, fill_opacity = 255 },
        })
        -- 刻度（18 根）
        local tk = {}
        for i = 0, 17 do
            local a = math.rad(i * 20)
            local r_out = r - 5
            local r_in = r - ((i % 2 == 0) and 14 or 12)
            _ln(tk, r + r_out * math.cos(a), r + r_out * math.sin(a),
                r + r_in * math.cos(a), r + r_in * math.sin(a),
                theme.blend(0xAAD2FA, 0x0B2559, 0.55), 2)
        end
        theme.shapes(root, cx - r, cy - r, 2 * r, 2 * r, tk)
    end
    dial(cx1, cy1, math.floor(R1 / 2))
    -- 高亮弧（168° 起顺时针 76°，青色渐隐）
    local arc = {}
    for k = 0, 24 do
        local a = math.rad(168 + 76 * k / 24)
        local alpha = (k < 12) and (0.15 + 0.8 * k / 12) or (0.95 - 0.8 * (k - 12) / 12)
        _ci(arc, math.floor(R1 / 2 + (R1 / 2 - 2) * math.cos(a)),
            math.floor(R1 / 2 + (R1 / 2 - 2) * math.sin(a)), 3,
            theme.blend(0x35D6E8, 0x0B2559, alpha), 255)
    end
    theme.shapes(root, cx1 - math.floor(R1 / 2), cy1 - math.floor(R1 / 2), R1, R1, arc)
    airui.label({ parent = root, x = cx1 - 80, y = cy1 - 52, w = 160, h = 92,
        text = tostring(MOCK.cluster.spd), color = C.text, font_size = 84,
        align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = root, x = cx1 - 60, y = cy1 + 42, w = 120, h = 24,
        text = "km/h", color = C.sub, font_size = 18, align = airui.TEXT_ALIGN_CENTER })

    -- 副表盘（190，弧起点 150°）
    local cx2 = W - 52 - math.floor(R2 / 2)
    local cy2 = math.floor(H / 2) - math.floor(R1 * 0.52) + math.floor(R1 / 2)
    dial(cx2, cy2, math.floor(R2 / 2))
    local arc2 = {}
    for k = 0, 20 do
        local a = math.rad(150 + 60 * k / 20)
        _ci(arc2, math.floor(R2 / 2 + (R2 / 2 - 2) * math.cos(a)),
            math.floor(R2 / 2 + (R2 / 2 - 2) * math.sin(a)), 3,
            theme.blend(0x35D6E8, 0x0B2559, 0.75), 255)
    end
    theme.shapes(root, cx2 - math.floor(R2 / 2), cy2 - math.floor(R2 / 2), R2, R2, arc2)
    airui.label({ parent = root, x = cx2 - 60, y = cy2 - 36, w = 120, h = 64,
        text = tostring(MOCK.cluster.spd2), color = C.text, font_size = 60,
        align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = root, x = cx2 - 50, y = cy2 + 30, w = 100, h = 22,
        text = "km", color = C.sub, font_size = 18, align = airui.TEXT_ALIGN_CENTER })

    -- ADAS 场景（中部：楼房剪影 + 车道线 + 小红车）
    local ax0 = cx1 + math.floor(R1 / 2) + 40
    local ax1 = cx2 - math.floor(R2 / 2) - 20
    local aw = ax1 - ax0
    local ay0 = 96
    local ay1 = H - 84
    local blds = { { 10, 120, 34, 60 }, { 52, 96, 26, 84 }, { 86, 132, 40, 48 },
                   { 136, 108, 24, 72 }, { 250, 112, 28, 68 }, { 288, 92, 34, 88 },
                   { 330, 126, 30, 54 }, { 370, 104, 26, 76 } }
    local bit = {}
    for _, b in ipairs(blds) do
        _rc(bit, math.floor(b[1] * aw / 420), math.floor(ay0 + (b[2] - 60) * (ay1 - ay0) / 240),
            math.floor(b[3] * aw / 420), math.floor(b[4] * (ay1 - ay0) / 240),
            theme.blend(0x1D5B72, C.bg, 0.35), 0)
    end
    theme.shapes(root, ax0, ay0, aw, ay1 - ay0, bit)
    local lane = {}
    _ln(lane, 0, ay1 - ay0 - 2, aw, ay1 - ay0 - 2, theme.blend(0x2E7DD8, C.bg, 0.55), 1)
    _ln(lane, math.floor(120 * aw / 420), ay1 - ay0, math.floor(200 * aw / 420),
        math.floor(180 * (ay1 - ay0) / 300), theme.blend(0xC8E4FF, C.bg, 0.55), 2)
    _ln(lane, math.floor(300 * aw / 420), ay1 - ay0, math.floor(220 * aw / 420),
        math.floor(180 * (ay1 - ay0) / 300), theme.blend(0xC8E4FF, C.bg, 0.55), 2)
    _ln(lane, math.floor(60 * aw / 420), ay1 - ay0, math.floor(150 * aw / 420),
        math.floor(180 * (ay1 - ay0) / 300), theme.blend(0xC8E4FF, C.bg, 0.22), 1)
    _ln(lane, math.floor(360 * aw / 420), ay1 - ay0, math.floor(270 * aw / 420),
        math.floor(180 * (ay1 - ay0) / 300), theme.blend(0xC8E4FF, C.bg, 0.22), 1)
    theme.shapes(root, ax0, ay0, aw, ay1 - ay0, lane)
    -- 小红车：优先贴图（code/img/car_cluster.png 104×80 透明底，车尾视角，
    -- 和空调页座椅、车辆页整车是同一套素材）；图缺失则回退到原来的 shape 车
    local carx = math.floor((ax0 + ax1) / 2 - 52)
    local cary = ay1 - 96
    local car_src = theme.img("car_cluster.png")
    local car_ok = false
    if car_src then
        local im
        local ok = pcall(function()
            im = airui.image({ parent = root, src = car_src, x = carx, y = cary,
                w = 104, h = 80 })
        end)
        car_ok = ok and im ~= nil
    end
    if not car_ok then
        theme.shapes(root, carx, cary, 104, 74, {
            { type = "rect", x = 18, y = 62, w = 68, h = 8, color = theme.blend(0x2E7DFF, C.bg, 0.55),
              width = 1, radius = 4, fill = true,
              fill_color = theme.blend(0x2E7DFF, C.bg, 0.55), fill_opacity = 255 },
            { type = "rect", x = 16, y = 40, w = 76, h = 20, color = 0xC21E33, width = 1,
              radius = 8, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
            { type = "rect", x = 34, y = 26, w = 26, h = 18, color = 0x7C1220, width = 1,
              radius = 5, fill = true, fill_color = 0x7C1220, fill_opacity = 255 },
            { type = "rect", x = 30, y = 50, w = 44, h = 4, color = 0xF0455C, width = 1,
              radius = 2, fill = true, fill_color = 0xF0455C, fill_opacity = 230 },
            { type = "circle", cx = 33, cy = 58, r = 5, color = 0x0D0F14, width = 1,
              fill = true, fill_color = 0x0D0F14, fill_opacity = 255 },
            { type = "circle", cx = 74, cy = 58, r = 5, color = 0x0D0F14, width = 1,
              fill = true, fill_color = 0x0D0F14, fill_opacity = 255 },
        })
    end

    ----------------------------------------------------------------
    -- 底栏 54：电量 / 心电 / PRND / NEOC / OK
    ----------------------------------------------------------------
    local by2 = H - 54
    theme.icon(root, 320, by2 + 19, 14, "bolt", C.name)
    airui.label({ parent = root, x = 340, y = by2 + 16, w = 50, h = 22,
        text = MOCK.cluster.bat .. "%", color = C.name, font_size = 17 })
    airui.container({ parent = root, x = 396, y = by2 + 24, w = 96, h = 7,
        color = C.track, radius = 4 })
    airui.container({ parent = root, x = 396, y = by2 + 24,
        w = math.floor(96 * MOCK.cluster.bat / 100), h = 7,
        color = theme.blend(C.cyan, C.blue, 0.4), radius = 4 })
    theme.icon(root, 520, by2 + 17, 20, "more", theme.blend(0x8FB6E0, C.bg, 0.85))
    -- PRND + 展开箭头
    local gears = { "P", "R", "N", "D", ">" }
    for i, g in ipairs(gears) do
        local gx = 556 + (i - 1) * 42   -- 右移会压到 NEOC 文案，起点左移
        local on = (MOCK.cluster.gear == g)
        airui.label({ parent = root, x = gx, y = by2 + 14, w = 30, h = 26, text = g,
            color = on and C.yellow or C.dim, font_size = 17,
            align = airui.TEXT_ALIGN_CENTER })
        local b = airui.container({ parent = root, x = gx - 8, y = by2 + 10, w = 44, h = 34,
            color = C.bg, color_opacity = 1 })
        b:set_on_click(function()
            db(function()
                if g ~= ">" then
                    MOCK.gear_pick(g)
                    theme.rerender_current()
                end
            end)
        end)
    end
    airui.label({ parent = root, x = W - 240, y = by2 + 16, w = 100, h = 22,
        text = MOCK.cluster.NEOC, color = C.sub, font_size = 16 })
    theme.icon(root, W - 122, by2 + 18, 16, "user", C.sub)
    airui.label({ parent = root, x = W - 100, y = by2 + 16, w = 60, h = 22,
        text = "OK", color = C.sub, font_size = 16 })
end)
