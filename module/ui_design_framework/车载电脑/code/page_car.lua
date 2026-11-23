--[[
@module page_car
@summary 车辆页：车名 / 六边形光环 + SUV 侧视图 / 左右驱动模式胶囊 / 环温滑条 / 三张数据卡
布局与 preview.html 对应：car-cards 148 高三卡 / car-stage 居中舞台
]]

local theme = require "theme"
local _ln, _ci, _rc = theme._ln, theme._ci, theme._rc
local W, H, TOP = theme.W, theme.H, theme.TOP_H

theme.make_page("car", function(root, M)
    local C = theme.C
    local db = theme.debounce()

    theme.topbar(root, "back", false)

    ----------------------------------------------------------------
    -- 车名行 + 返回键
    ----------------------------------------------------------------
    -- 行高按 1.35×字号给足（22→30、16→22），否则中文字下缘会被裁
    airui.label({ parent = root, x = 16, y = TOP + 2, w = 260, h = 30,
        text = MOCK.car.name, color = C.text, font_size = 22 })
    airui.label({ parent = root, x = 16, y = TOP + 30, w = 260, h = 22,
        text = MOCK.car.sub, color = C.sub, font_size = 16 })
    -- 右上角原来又画了一个返回键，和顶栏的宫格钮位置重叠（两个圆压在一起），
    -- 返回键统一交给顶栏，这里只留车名信息

    ----------------------------------------------------------------
    -- 舞台（y 90..440）：六边形光环 + SUV + 左右模式列 + 环温滑条
    ----------------------------------------------------------------
    local sy = TOP + 44
    local sh = 440 - sy
    local cx = math.floor(W / 2)
    local cy = sy + math.floor(sh / 2)

    -- 光晕：半径 320 的圆一定超出 350 高的画布（顶到负坐标 → 巨大色块），改用画布内矩形
    -- 0.14 太淡，舞台上半看起来是黑底、下半才偏蓝（「上黑下蓝」）；提高到明显蓝色
    theme.shapes(root, 0, sy, W, sh, {
        { type = "rect", x = 0, y = 0, w = W, h = sh,
          color = theme.blend(0x2E7DFF, C.bg, 0.40), width = 1, radius = 0,
          fill = true, fill_color = theme.blend(0x2E7DFF, C.bg, 0.40),
          fill_opacity = 255 },
    })
    -- 六边形描边（渐变 → 每边取渐变色近似）+ 内圈
    local hexw, hexh = 600, 246
    local hx = cx - 300
    local hy0 = cy - math.floor(hexh / 2)
    local function hexedge(items, x1, y1, x2, y2, t)
        _ln(items, x1, y1, x2, y2,
            theme.blend(0x2E7DFF, 0xF43F6E, t), 3)
    end
    local hxi = cx - 300   -- 内圈 x 会到 cx-284，画布必须从 cx-300 起，否则左边缘出界
    local hyi = cy - math.floor(hexh / 2) + 14
    local function hexpts(ox, oy, w2, h2)
        -- 中心对称六边形顶点
        return {
            { ox - w2 + 50, oy }, { ox + w2 - 50, oy },
            { ox + w2, oy + h2 * 0.3 }, { ox + w2, oy + h2 * 0.72 },
            { ox + w2 - 50, oy + h2 }, { ox - w2 + 50, oy + h2 },
            { ox - w2, oy + h2 * 0.72 }, { ox - w2, oy + h2 * 0.3 },
        }
    end
    local outer = hexpts(cx, hy0, 250, hexh)
    local it1 = {}
    for i = 1, 8 do
        local a, b = outer[i], outer[i < 8 and i + 1 or 1]
        hexedge(it1, a[1] - hx, a[2] - hy0, b[1] - hx, b[2] - hy0, (i - 1) / 7)
    end
    theme.shapes(root, hx, hy0, 600, hexh, it1)
    local inner = hexpts(cx, hyi, 234, hexh - 28)
    local it2 = {}
    for i = 1, 8 do
        local a, b = inner[i], inner[i < 8 and i + 1 or 1]
        _ln(it2, a[1] - hxi, a[2] - hyi, b[1] - hxi, b[2] - hyi,
            theme.blend(0x2E7DFF, 0xF43F6E, (i - 1) / 7), 1)
    end
    theme.shapes(root, hxi, hyi, 600, hexh, it2)

    -- 整车：优先贴图（code/img/car_side_big.png 420×178 透明底，侧视 SUV，
    -- 车头朝左、四个轮子完整）。阴影是单独按亮度抠掉的，不是裁切——
    -- 之前裁到轮子中间，轮胎底部被切平了一道。
    local svx, svy = cx - 260, cy - 78
    local car_big = theme.img("car_side_big.png")
    local car_ok = false
    if car_big then
        local im
        local ok = pcall(function()
            im = airui.image({ parent = root, src = car_big,
                x = cx - 210, y = cy - 89, w = 420, h = 178 })
        end)
        car_ok = ok and im ~= nil
    end
    if not car_ok then
        theme.shapes(root, svx, svy, 520, 200, {
            -- 地面阴影
            { type = "rect", x = 64, y = 168, w = 392, h = 16, color = C.shadow, width = 1,
              radius = 8, fill = true, fill_color = C.shadow, fill_opacity = 140 },
            -- 车身（上红渐变 → 用两段色近似）
            { type = "rect", x = 62, y = 92, w = 408, h = 52, color = 0xC21E33, width = 1,
              radius = 20, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
            { type = "rect", x = 62, y = 122, w = 408, h = 24, color = 0x8E1626, width = 1,
              radius = 10, fill = true, fill_color = 0x8E1626, fill_opacity = 200 },
            -- 车顶
            { type = "rect", x = 150, y = 64, w = 230, h = 34, color = 0xC21E33, width = 1,
              radius = 14, fill = true, fill_color = 0xC21E33, fill_opacity = 255 },
            -- 车窗
            { type = "rect", x = 160, y = 70, w = 100, h = 24, color = 0x46586E, width = 1,
              radius = 6, fill = true, fill_color = 0x46586E, fill_opacity = 230 },
            { type = "rect", x = 268, y = 70, w = 100, h = 24, color = 0x3A4C62, width = 1,
              radius = 6, fill = true, fill_color = 0x3A4C62, fill_opacity = 210 },
            -- 车轮
            { type = "circle", cx = 156, cy = 146, r = 26, color = 0x0D0F14, width = 1,
              fill = true, fill_color = 0x0D0F14, fill_opacity = 255 },
            { type = "circle", cx = 156, cy = 146, r = 12, color = 0x46505E, width = 1,
              fill = true, fill_color = 0x46505E, fill_opacity = 255 },
            { type = "circle", cx = 156, cy = 146, r = 5, color = 0x98A5B5, width = 1,
              fill = true, fill_color = 0x98A5B5, fill_opacity = 255 },
            { type = "circle", cx = 386, cy = 146, r = 26, color = 0x0D0F14, width = 1,
              fill = true, fill_color = 0x0D0F14, fill_opacity = 255 },
            { type = "circle", cx = 386, cy = 146, r = 12, color = 0x46505E, width = 1,
              fill = true, fill_color = 0x46505E, fill_opacity = 255 },
            { type = "circle", cx = 386, cy = 146, r = 5, color = 0x98A5B5, width = 1,
              fill = true, fill_color = 0x98A5B5, fill_opacity = 255 },
        })
    end

    -- 左右模式列（118 宽）
    local function modecol(side)
        local px = (side == "l") and 22 or (W - 16 - 6 - 118)
        local icon = (side == "l") and "bolt" or "heater"
        local col = (side == "l") and C.blue2 or C.pink
        theme.icon(root, px + 46, cy - 108, 26, icon, col)
        local pct = airui.label({ parent = root, x = px, y = cy - 78, w = 118, h = 42,
            text = (side == "l") and (MOCK.car.ev .. "%") or (MOCK.car.hev .. "%"),
            color = col, font_size = 30, align = airui.TEXT_ALIGN_CENTER })
        local modes = (side == "l") and MOCK.car.lmodes or MOCK.car.rmodes
        for i, m in ipairs(modes) do
            local on = (MOCK.car.mode[side] == i)
            local yy = cy - 32 + (i - 1) * 36
            theme.pill(root, { x = px, y = yy, w = 118, h = 28, radius = 12 }, m,
                { bg = on and theme.blend(col, C.card, 0.24) or C.sel,
                  color = on and C.bright or C.sub,
                  border = on and col or C.line2 })
            -- 走 theme.click：透明容器 + set_on_click 在部分固件收不到点击
            local mname = m
            theme.click(root, px, yy, 118, 28, function()
                MOCK.car_pick(side, i)
                theme.rerender_current()
                -- 整页重建后再弹提示：立即调用会挂到刚被销毁的旧 root 上
                sys.timerStart(function() theme.toast(mname .. " 已启用") end, 60)
            end, 12)
        end
    end
    modecol("l")
    modecol("r")

    -- 环温滑条（520 宽，底部 6）
    local sw = 520
    local sx0 = cx - 260
    airui.label({ parent = root, x = cx - 40, y = 440 - 48, w = 80, h = 22,
        text = "360°C", color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_CENTER })
    -- 渐变轨道（4 段近似）+ 旋钮
    local segs_col = { theme.blend(C.blue, C.card, 0.10), theme.blend(C.blue, C.card, 0.55),
                       theme.blend(C.pink, C.card, 0.55), theme.blend(C.pink, C.card, 0.10) }
    for i = 1, 4 do
        airui.container({ parent = root, x = sx0 + (i - 1) * 130, y = 440 - 24,
            w = 130, h = 3, color = segs_col[i], radius = 2 })
    end
    theme.shapes(root, sx0, 440 - 33, 520, 23, {
        { type = "circle", cx = 234, cy = 12, r = 7, color = C.knob, width = 1,
          fill = true, fill_color = C.knob, fill_opacity = 255 },
        { type = "circle", cx = 234, cy = 12, r = 11, color = C.blue2, width = 1,
          fill = false },
    })

    ----------------------------------------------------------------
    -- 三张数据卡（148 高）
    ----------------------------------------------------------------
    local ky = 440
    local kh = 148
    local kw = math.floor((W - 32 - 24) / 3)
    local heads = { { "电池详细数据", "更新 6/10" }, { "能源使用数据", "更新 6/10" },
                    { "行驶里程数据", "更新 6/10" } }
    for i = 1, 3 do
        local x = 16 + (i - 1) * (kw + 12)
        theme.card(root, { x = x, y = ky, w = kw, h = kh })
        theme.card_head(root, { x = x, y = ky, w = kw, h = 30 }, heads[i][1], heads[i][2])
    end

    -- 卡1：电池 + 迷你柱状图
    local x1 = 16
    theme.shapes(root, x1 + 14, ky + 38, 40, 72, {
        { type = "rect", x = 6, y = 8, w = 28, h = 58, color = 0x4E6E92, width = 2,
          radius = 5, fill = false },
        { type = "rect", x = 9, y = 36, w = 22, h = 27, color = C.cyan, width = 1,
          radius = 3, fill = true, fill_color = C.cyan, fill_opacity = 255 },
        { type = "rect", x = 14, y = 2, w = 12, h = 6, color = 0x4E6E92, width = 1,
          radius = 2, fill = true, fill_color = 0x4E6E92, fill_opacity = 255 },
    })
    local bars = MOCK.car.bat_small
    local bw0 = x1 + 64
    local bw = math.floor((kw - 64 - 24 - 11 * 3) / 12)
    for i, hgt in ipairs(bars) do
        local bh = math.floor(64 * hgt / 100)
        airui.container({ parent = root, x = bw0 + (i - 1) * (bw + 3),
            y = ky + 38 + 72 - bh, w = bw, h = bh,
            color = theme.blend(0x5AE0F0, C.blue, 0.4), radius = 2 })
    end
    airui.label({ parent = root, x = x1 + 12, y = ky + kh - 32, w = kw - 24, h = 22,
        text = "30min · 3.3度每百公里 · 3.38元每公里", color = C.dim, font_size = 16 })

    -- 卡2：两个能量环（.ring2 .r{flex:1} → 两格均分，环在格内居中）
    local x2 = 16 + kw + 12
    local cell = math.floor((kw - 24 - 10) / 2)
    local rcy = ky + 76                      -- 环心（卡内 38 起 + 半径 38）
    local function ring(cx0, frac, col, track_col, v, unit)
        theme.arc_ring(root, cx0, rcy, 30, {
            { f = frac, color = col }, { f = 1 - frac, color = track_col },
        }, -90, 4)
        -- 珠环 r=30、珠子半径 4 → 环内沿只到 r-4 = 26。
        -- 原来数值 17 号、"3.3" 占 ±15，纵向又在 -26..0，四角正好压到珠子上
        -- （用户反馈「3.3 度和 5.3L 和外面的圆弧重叠」）。
        -- 数值缩到 15 号并上移（墨迹落在 -20..-4），单位缩到 14 号，
        -- 这样文字全部待在 r=26 的内圈里。
        airui.label({ parent = root, x = cx0 - 38, y = rcy - 24, w = 76, h = 24, text = v,
            color = C.text, font_size = 15, align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = root, x = cx0 - 38, y = rcy + 1, w = 76, h = 20, text = unit,
            color = C.sub, font_size = 14, align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = root, x = cx0 - 48, y = rcy + 40, w = 96, h = 22,
            text = "每百公里", color = C.dim, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
    end
    ring(x2 + 12 + math.floor(cell / 2), 0.79, C.cyan, C.track, "3.3", "度")
    ring(x2 + 12 + cell + 10 + math.floor(cell / 2), 0.63, C.pink,
        theme.blend(C.pink, C.card, 0.15), "5.3", "L")

    -- 卡3：里程曲线
    local x3 = 16 + 2 * (kw + 12)
    local pts = { { 0, 66 }, { 37, 60 }, { 74, 48 }, { 114, 34 }, { 160, 22 },
                  { 204, 30 }, { 240, 26 }, { 259, 28 } }
    local it = {}
    for i = 1, #pts - 1 do
        _ln(it, pts[i][1] * (kw - 40) / 259, pts[i][2], pts[i + 1][1] * (kw - 40) / 259,
            pts[i + 1][2], C.blue2, 2)
    end
    -- 曲线画布收在 82 高（底 = ky+120），下方才能放得下 22 高的里程标签
    theme.shapes(root, x3 + 12, ky + 38, kw - 24, 82, it)
    theme.shapes(root, x3 + 12, ky + 38, kw - 24, 82, {
        { type = "circle", cx = math.floor(140 * (kw - 40) / 259), cy = 20, r = 4,
          color = C.bright, width = 1, fill = true,
          fill_color = C.bright, fill_opacity = 255 },
    })
    local mw = math.floor((kw - 24) / 3)
    for i, m in ipairs(MOCK.car.mile) do
        airui.label({ parent = root, x = x3 + 12 + (i - 1) * mw,
            y = ky + kh - 30, w = mw, h = 22, text = m,
            color = C.dim, font_size = 16,
            align = (i == 1) and airui.TEXT_ALIGN_LEFT
                or ((i == 3) and airui.TEXT_ALIGN_RIGHT or airui.TEXT_ALIGN_CENTER) })
    end
end)
