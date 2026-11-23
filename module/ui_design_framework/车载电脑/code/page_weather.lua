-- 天气页主文件
-- 图元辅助函数（wx_icon / spark / ring）直接内联在本文件里：
-- 之前拆到 wx_kit.lua 后，量产工具合并不认额外模块（报「缺少 wx_kit.lua 请添加」），
-- 本工程其余页面也全是单文件，这里统一回到单文件，不再 require 子模块。
local sys = require "sys"
local theme = require "theme"
require "mock"

local W, H = theme.W, theme.H

--------------------------------------------------------------------
-- 天气图标（纯 shape；图元全部落在画布内）
--------------------------------------------------------------------
local function wx_icon(parent, x, y, s, kind, opts)
    local C = theme.C
    opts = opts or {}
    local cloud = opts.cloud or C.cloud
    local sun   = opts.sun or C.yellow
    local rainc = opts.rain or C.rain
    local bgc   = opts.bg or C.card
    local items = {}
    local ci, ln, rc = theme._ci, theme._ln, theme._rc
    local function rays(cx, cy, r0, r1)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            ln(items, cx + r0 * math.cos(a), cy + r0 * math.sin(a),
                        cx + r1 * math.cos(a), cy + r1 * math.sin(a), sun, 2)
        end
    end
    local function cloud_at(cx, cy, k)
        ci(items, cx - 0.17 * s * k, cy, 0.15 * s * k, cloud, 250)
        ci(items, cx, cy - 0.09 * s * k, 0.20 * s * k, cloud, 255)
        ci(items, cx + 0.18 * s * k, cy + 0.02 * s * k, 0.14 * s * k, cloud, 250)
        local rw = 0.60 * s * k
        local rx = cx - rw / 2
        if rx < 0 then rx = 0 end
        if rx + rw > s then rw = s - rx end
        rc(items, rx, cy - 0.01 * s * k, rw, 0.18 * s * k, cloud, math.floor(0.07 * s * k))
    end
    if kind == "sun" then
        ci(items, 0.5 * s, 0.5 * s, 0.21 * s, sun, 255)
        rays(0.5 * s, 0.5 * s, 0.28 * s, 0.38 * s)
    elseif kind == "moon" then
        ci(items, 0.46 * s, 0.46 * s, 0.24 * s, 0xCBD8F0, 255)
        ci(items, 0.56 * s, 0.38 * s, 0.21 * s, bgc, 255)
    elseif kind == "rain" then
        cloud_at(0.5 * s, 0.44 * s, 0.86)
        ln(items, 0.34 * s, 0.70 * s, 0.29 * s, 0.86 * s, rainc, 2)
        ln(items, 0.50 * s, 0.70 * s, 0.45 * s, 0.88 * s, rainc, 2)
        ln(items, 0.66 * s, 0.70 * s, 0.61 * s, 0.86 * s, rainc, 2)
    elseif kind == "partly" then
        ci(items, 0.34 * s, 0.32 * s, 0.14 * s, sun, 255)
        rays(0.34 * s, 0.32 * s, 0.19 * s, 0.26 * s)
        cloud_at(0.56 * s, 0.66 * s, 0.72)
    else
        cloud_at(0.5 * s, 0.54 * s, 1)
    end
    theme.shapes(parent, x, y, s, s, items)
end

--------------------------------------------------------------------
-- 迷你折线（详情卡用）
--------------------------------------------------------------------
local function spark(parent, x, y, w, h, col, vals, lo, hi)
    local n = #vals
    if n < 2 then return end
    if hi - lo <= 0 then hi = lo + 1 end
    local items = {}
    local px, py
    for i = 1, n do
        local k = (vals[i] - lo) / (hi - lo)
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        local cx = math.floor((i - 1) * w / (n - 1) + 0.5)
        local cy = math.floor(h - k * h + 0.5)
        if px then theme._ln(items, px, py, cx, cy, col, 2) end
        px, py = cx, cy
    end
    theme.shapes(parent, x, y, w, h, items)
end

--------------------------------------------------------------------
-- 珠链圆环（紫外线 / AQI 用）
--------------------------------------------------------------------
local function ring(parent, cx, cy, r, segs)
    local items = {}
    local total = 0
    for _, s in ipairs(segs) do total = total + s.f end
    if total <= 0 then return end
    local beads, acc = 30, 0
    for _, s in ipairs(segs) do
        local n = math.max(0, math.floor(beads * s.f / total + 0.5))
        for _ = 1, n do
            local a = (acc / beads) * math.pi * 2 - math.pi / 2
            local bx = math.floor(math.cos(a) * r + 0.5)
            local by = math.floor(math.sin(a) * r + 0.5)
            theme._ci(items, bx + r + 3, by + r + 3, 2, s.color, 255)
            acc = acc + 1
        end
    end
    theme.shapes(parent, cx - r - 3, cy - r - 3, r * 2 + 6, r * 2 + 6, items)
end

local PX = 12

theme.make_page("weather", function(root, M)
    local C = theme.C
    local wth = MOCK.weather
    local anchor, redraw, head, ov, bd
    local CW = W - PX * 2
    -- airui 的 container 不保存 .w/.h（返回的表里没有这两个字段），
    -- 所以锚点宽度必须自己用一个数记住。原来代码写 anchor.w，
    -- nil 参与减法直接抛错 → draw_switch 中断 → 日期条和图表整块空白
    -- （即用户截图里「七日预报」卡只有标题、下面什么都没有）。
    local AW = CW - 4

    if not MOCK.wx_cities then
        MOCK.wx_cities = { "杭州市,西湖区", "上海市,浦东新区", "南京市,玄武区", "苏州市,姑苏区" }
    end
    wth.sw = wth.sw or {}
    wth.detail = wth.detail or false
    wth.view = wth.view or "chart"
    wth.tab_idx = wth.tab_idx or 1
    wth.det = wth.det or {
        uv = 6, aqi = 72, vis = 2.6, press = 1020, cloud = 62,
        wind = 9, hum = 93, moon = "上弦月", sunrise = "06:32", sunset = "17:12",
    }

    ----------------------------------------------------------------
    -- 9 个指标 tab（与「天气预报」一致）
    ----------------------------------------------------------------
    local TABS = {
        { name = "概览", ulabel = "温度(°C)", color = C.yellow, type = "line",
          ymin = 10, ymax = 35, icons = true, sw = "体感温度", swkey = "feel", fill = true },
        { name = "降水", ulabel = "降水概率(%)", color = C.cyan, type = "bar", ymin = 0, ymax = 100,
          legend = { { "雨", C.blue }, { "阵雨", C.cyan }, { "雨雪", 0xAFC8E8 } } },
        -- nosw = 不画右上角的「阵风」开关（用户要求去掉），阵风那条副线仍画
        { name = "风速", ulabel = "风速(km/h)", color = C.cyan, type = "line", ymin = 0, ymax = 40,
          arrows = true, sw = "阵风", swkey = "gust", nosw = true,
          legend = { { "风速", C.cyan }, { "阵风", C.blue } } },
        -- nosw = 不画右上角的「露点」开关（用户要求去掉），露点那条副线仍画
        { name = "湿度", ulabel = "湿度(%)", color = C.blue2, type = "line", ymin = 40, ymax = 100,
          fill = true, sw = "露点", swkey = "dew", nosw = true,
          legend = { { "湿度", C.blue2 }, { "露点", C.cyan } } },
        { name = "云量", ulabel = "云量(%)", color = C.blue, type = "bar", ymin = 0, ymax = 100,
          bar_r = 8, legend = { { "晴朗", 0x3D6FD0 }, { "局部多云", 0x8FC3F5 }, { "多云", 0xC8DCF5 } } },
        { name = "气压", ulabel = "气压(hPa)", color = C.purple, type = "line",
          ymin = 1000, ymax = 1030, fill = true, legend = { { "气压", C.purple } } },
        { name = "紫外线", ulabel = "紫外线指数", color = 0xF08A3C, type = "bar", ymin = 0, ymax = 12,
          legend = { { "非常高", C.pink }, { "高", 0xF08A3C }, { "中等", C.yellow }, { "低", C.green } } },
        { name = "可见度", ulabel = "可见度(公里)", color = C.green, type = "line", ymin = 0, ymax = 25,
          fill = true, legend = { { "可见度", C.green } } },
        { name = "体感温度", ulabel = "体感温度(°C)", color = C.yellow, type = "line",
          ymin = 10, ymax = 38, fill = true, sw = "温度", swkey = "ftemp",
          -- nosw = 不画右上角的「温度」开关（用户要求去掉），
          -- 第二条温度线仍然画、图例也仍在
          nosw = true,
          legend = { { "体感温度", C.yellow }, { "温度", C.orange } } },
    }
    local ICON_TEXT = { sun = "晴朗", moon = "夜间晴朗", cloud = "多云",
        partly = "局部晴朗", rain = "降雨", thunder = "雷阵雨" }
    local DIRS = { "东北风", "东风", "东南风", "南风" }

    ---------------------------------------------------------------- 顶栏
    airui.shape({ parent = root, x = PX, y = 9, w = 34, h = 34, items = {
        { type = "circle", cx = 17, cy = 17, r = 16, color = C.line, width = 1,
          fill = true, fill_color = C.card2, fill_opacity = 255 } } })
    theme.icon(root, PX + 8, 17, 18, "left", C.bright)
    theme.click(root, PX, 9, 34, 34, function() theme.back_defer() end, 17)

    airui.label({ parent = root, x = PX + 46, y = 4, w = 230, h = 30,
        text = "当前天气", color = C.title, font_size = 22 })
    airui.label({ parent = root, x = PX + 48, y = 33, w = 240, h = 20,
        text = wth.date or "", color = C.sub, font_size = 16 })

    -- 城市切换键挪进天气卡贴温度放（原来在右上角）；
    -- 「详细信息」按钮及二级页面按用户要求整块去掉。

    -- 城市下拉弹层
    local ddl
    local function close_dd()
        if ddl then pcall(function() ddl:destroy() end) ddl = nil end
    end
    local function open_dd()
        if ddl then close_dd() return end
        -- 对照参考图：面板挂在城市键下面，标题「我的位置」，
        -- 每行 = 区县名 / 省市全称 + 天气图标 + 温度，选中行加蓝边
        local cw, ch = 340, 272
        local cx, cy = PX + 14, 96
        ddl = airui.container({ parent = root, x = 0, y = 0, w = W, h = H,
            color = C.bg, color_opacity = 1 })
        theme.click(ddl, 0, 0, W, H, close_dd)
        theme.card(ddl, { x = cx, y = cy, w = cw, h = ch }, { radius = 14 })
        theme.click(ddl, cx, cy, cw, ch, function() end, 14)
        airui.label({ parent = ddl, x = cx + 14, y = cy + 12, w = cw - 28, h = 22,
            text = "我的位置", color = C.sub, font_size = 16 })
        for i, name in ipairs(MOCK.wx_cities) do
            local ry = cy + 42 + (i - 1) * 54
            local sel = (name == wth.area)
            local drow = wth.days[i] or {}
            local short = name:match("([^,]+)$") or name
            airui.container({ parent = ddl, x = cx + 10, y = ry, w = cw - 20, h = 50,
                color = sel and C.sel_str or C.deep, radius = 10,
                border_color = sel and C.blue2 or C.line,
                border_width = sel and 2 or 1 })
            airui.label({ parent = ddl, x = cx + 22, y = ry + 5, w = cw - 150, h = 22,
                text = short, color = C.text, font_size = 16 })
            airui.label({ parent = ddl, x = cx + 22, y = ry + 26, w = cw - 150, h = 20,
                text = name, color = C.sub, font_size = 14 })
            wx_icon(ddl, cx + cw - 134, ry + 12, 26, drow.ic or "sun",
                { bg = sel and C.sel_str or C.deep })
            airui.label({ parent = ddl, x = cx + cw - 98, y = ry + 14, w = 60, h = 24,
                text = tostring(drow.hi or 20) .. "°", color = C.text, font_size = 18,
                align = airui.TEXT_ALIGN_RIGHT })
            local nm = name
            theme.click(ddl, cx + 10, ry, cw - 20, 50, function()
                wth.area = nm
                wth.city = nm:match("^([^,]+)") or nm
                close_dd()
                theme.toast("已切换到 " .. nm)
                theme.rerender_current()
            end, 10)
        end
    end
    ---------------------------------------------------------------- 数据
    local function hour_vals(ti, sw)
        local hs = wth.hours
        local t = {}
        for i = 1, #hs do
            local h = hs[i]
            local v
            if ti == 1 then v = sw and h.fv or h.v
            elseif ti == 2 then v = h.p
            elseif ti == 3 then v = sw and (h.v * 1.8 + 8) or (h.v * 1.2 + 5)
            elseif ti == 4 then v = sw and (h.v + 13) or (52 + (h.p * 3 + i * 5) % 43)
            elseif ti == 5 then v = 25 + (h.p + i * 7) % 66
            elseif ti == 6 then v = 1006 + (h.v * 2 + i) % 20
            elseif ti == 7 then
                local hh = (17 + i * 2) % 24
                v = (hh >= 6 and hh <= 18)
                    and math.floor(11 * math.sin(math.pi * (hh - 6) / 12) + 0.5) or 0
            elseif ti == 8 then v = 5 + (h.p + i * 11) % 16
            else v = sw and h.v or h.fv end
            t[i] = math.floor(v + 0.5)
        end
        return t
    end

    ---------------------------------------------------------------- 风向箭头
    -- 原来是三条 2px 细线按任意角度拼的箭头，7~12 个排一行就是一排斜杠
    -- （用户反馈「风速页像条形码」）。这里把角度量化到 45° 的整数倍，
    -- 杆 + 两侧箭头收成干净的小箭头，任何尺寸都不会糊。
    local WIND_DIRS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
                        { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
    local function wind_arrow(parent, cx, cy, size, deg, col)
        local k = math.floor(((deg % 360) + 22.5) / 45) % 8 + 1
        local dx, dy = WIND_DIRS[k][1], WIND_DIRS[k][2]
        local ox = cx - math.floor(size / 2)
        local oy = cy - math.floor(size / 2)
        local L  = math.floor(size * 0.42)              -- 杆半长
        local hl = math.max(3, math.floor(size * 0.22)) -- 箭头长度
        local hw = math.max(3, math.floor(size * 0.20)) -- 箭头半宽
        local tx, ty = cx + dx * L, cy + dy * L          -- 尖端
        local bx, by = tx - dx * hl, ty - dy * hl        -- 箭头根部
        local nx, ny = -dy, dx                           -- 垂直法线
        theme.shapes(parent, ox, oy, size, size, {
            { type = "line", x1 = cx - dx * L, y1 = cy - dy * L,
              x2 = tx, y2 = ty, color = col, width = 2 },
            { type = "line", x1 = tx, y1 = ty,
              x2 = bx + nx * hw, y2 = by + ny * hw, color = col, width = 2 },
            { type = "line", x1 = tx, y1 = ty,
              x2 = bx - nx * hw, y2 = by - ny * hw, color = col, width = 2 },
        })
    end

    -- 日期卡上的指标数值（概览用图标+高低温，其它 tab 用数值 + 右侧迷你图形）
    local function dayval(tab, i)
        local d = wth.days[i] or wth.days[1]
        local k = (i * 13) % 70
        local nm = tab.name
        if nm == "降水" then
            return { v1 = k .. "%", v2 = "概率 " .. (((i * 7) % 40) + 10) .. "%",
                knob = k / 100, kind = "drop" }
        elseif nm == "风速" then
            local sp = 6 + (i * 5) % 18
            -- 卡内右侧统一用「竖向滑条 + 圆点」（和湿度/云量一致，对照示例图），
            -- 风向不再画在卡里，改成图表上方一行对齐日期卡的箭头
            return { v1 = sp .. " km/h", v2 = (sp + 6) .. " 阵风",
                knob = sp / 30, kind = "bar", color = C.cyan, deg = i * 45 }
        elseif nm == "湿度" then
            local hum = 55 + (i * 7) % 40
            return { v1 = hum .. "%", v2 = "露点 " .. (d.lo - 2) .. "°",
                knob = hum / 100, kind = "bar", color = C.blue2 }
        elseif nm == "云量" then
            local cl = 30 + (i * 9) % 62
            return { v1 = cl .. "%", v2 = d.cond, knob = cl / 100,
                kind = "bar", color = C.blue }
        elseif nm == "气压" then
            local pr = 1012 + i
            return { v1 = pr .. " hPa", v2 = "稳定", knob = (pr - 1000) / 30,
                kind = "bar", color = C.purple }
        elseif nm == "紫外线" then
            local uv = 2 + (i * 5) % 9
            return { v1 = "指数 " .. uv, v2 = uv >= 8 and "非常高" or (uv >= 6 and "高" or "中等"),
                knob = uv / 11, kind = "bar", color = 0xF08A3C }
        elseif nm == "可见度" then
            local vi = 8 + (i * 5) % 12
            return { v1 = vi .. " 公里", v2 = vi >= 15 and "极佳" or "良好",
                knob = vi / 20, kind = "bar", color = C.green }
        else
            return { v1 = (d.hi - 2) .. "°", v2 = (d.hi - 4) .. "°",
                knob = (d.hi - 4) / 40, kind = "bar", color = C.yellow }
        end
    end

    ---------------------------------------------------------------- 日期条
    local function draw_strip(tab, ti)
        local dw, dgap, sy, sh = 132, 8, 30, 84
        for i = 1, 7 do
            local d = wth.days[i] or wth.days[1]
            local x = 12 + (i - 1) * (dw + dgap)
            local sel = (i == (wth.cur or 1))
            local bgc = sel and C.sel_str or C.deep
            airui.container({ parent = anchor, x = x, y = sy, w = dw, h = sh,
                color = bgc, radius = 12,
                border_color = sel and C.blue2 or C.line, border_width = 1 })
            airui.label({ parent = anchor, x = x, y = sy + 4, w = dw, h = 22,
                text = d.w, color = sel and C.text or C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            if ti == 1 then
                wx_icon(anchor, x + math.floor(dw / 2) - 17, sy + 26, 34, d.ic, { bg = bgc })
                airui.label({ parent = anchor, x = x, y = sy + 60, w = dw, h = 22,
                    text = d.hi .. "° / " .. d.lo .. "°",
                    color = sel and C.text or C.sub, font_size = 16,
                    align = airui.TEXT_ALIGN_CENTER })
            else
                local v = dayval(tab, i)
                airui.label({ parent = anchor, x = x + 10, y = sy + 24, w = dw - 46, h = 22,
                    text = v.v1, color = sel and C.text or C.sub, font_size = 16 })
                airui.label({ parent = anchor, x = x + 10, y = sy + 50, w = dw - 46, h = 22,
                    text = v.v2, color = C.dim, font_size = 16 })
                local gx = x + dw - 26
                if v.kind == "drop" then
                    -- 雨滴：原来是「一个圆 + 两条斜线」，像只小虫子（用户反馈太丑）。
                    -- 改成标准水滴：上部三角逐行收窄 + 下部实心圆，中间自然衔接，
                    -- 再从参考图里借一个浅色高光点。填充浓度仍跟降水概率走。
                    local col = C.cyan
                    local op = 60 + math.floor(v.knob * 195)
                    local items = {}
                    local cxd, cyc, rr = 13, 38, 8
                    for k = 0, 24 do
                        local t = (k + 1) / 25
                        local ww = math.max(1, math.floor(rr * 2 * t))
                        items[#items + 1] = { type = "rect",
                            x = cxd - math.floor(ww / 2), y = 10 + k, w = ww, h = 1,
                            color = col, width = 1, radius = 0,
                            fill = true, fill_color = col, fill_opacity = op }
                    end
                    items[#items + 1] = { type = "circle", cx = cxd, cy = cyc, r = rr,
                        color = col, width = 1,
                        fill = true, fill_color = col, fill_opacity = op }
                    items[#items + 1] = { type = "circle", cx = cxd - 3, cy = cyc - 2, r = 2,
                        color = 0xFFFFFF, width = 1,
                        fill = true, fill_color = 0xFFFFFF, fill_opacity = 150 }
                    theme.shapes(anchor, gx, sy + 22, 26, 52, items)
                else
                    -- 迷你竖向滑条：浅色轨道 + 圆点 + 圆点以下的实心填充（对照示例图）
                    -- 踩坑：shape 内图元坐标是相对 (gx, ty) 的，原来填充柱和圆点
                    -- 直接写了绝对的 ky，等于整体又下移了一个 ty —— 圆点被挤出
                    -- 可视区裁掉，所以每个 tab 的「蓝点」都不见了（用户反馈）
                    local col = v.color or C.blue2
                    local ty, th2 = sy + 22, 48
                    local tH = math.min(1, math.max(0, v.knob or 0))
                    local kyy = 5 + math.floor((1 - tH) * (th2 - 10))   -- 圆点圆心
                    theme.shapes(anchor, gx, ty, 26, th2, {
                        { type = "rect", x = 10, y = 0, w = 6, h = th2,
                          color = C.track, radius = 3,
                          fill = true, fill_color = C.track, fill_opacity = 255 },
                        { type = "rect", x = 10, y = kyy, w = 6, h = th2 - kyy,
                          color = col, radius = 3,
                          fill = true, fill_color = col, fill_opacity = 255 },
                        { type = "circle", cx = 13, cy = kyy, r = 5,
                          color = col, width = 1, fill = true, fill_color = col,
                          fill_opacity = 255 },
                    })
                end
            end
            local idx = i
            theme.click(anchor, x, sy, dw, sh, function()
                MOCK.weather_select(idx)
                redraw()
            end, 12)
        end
    end

    ---------------------------------------------------------------- 附加线开关（mkswitch）
    local function draw_switch(tab)
        -- nosw：只保留第二条线的显示状态，不画开关（体感温度 tab 已去掉）
        if not tab.sw or tab.nosw then return end
        local on
        if tab.swkey == "feel" then on = wth.feel else on = wth.sw[tab.swkey] end
        local sw_w, sw_h = 56, 26
        local lw = 110
        local lx = AW - 12 - sw_w - lw
        airui.label({ parent = anchor, x = lx, y = 4, w = lw, h = 22,
            text = tab.sw, color = C.sub, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
        local x = AW - 12 - sw_w
        airui.container({ parent = anchor, x = x, y = 2, w = sw_w, h = sw_h,
            color = on and C.sel_str or C.track, radius = math.floor(sw_h / 2),
            border_color = on and C.blue2 or C.line, border_width = 1 })
        local kd = 24
        airui.shape({ parent = anchor, x = on and (x + sw_w - kd - 1) or (x + 1), y = 3,
            w = kd, h = kd, items = {
                { type = "circle", cx = kd / 2, cy = kd / 2, r = 11,
                  color = on and C.bright or C.knob, width = 1,
                  fill = true, fill_color = on and C.bright or C.knob, fill_opacity = 255 } } })
        theme.click(anchor, x, 2, sw_w, sw_h, function()
            if tab.swkey == "feel" then
                wth.feel = not wth.feel
            else
                wth.sw[tab.swkey] = not wth.sw[tab.swkey]
            end
            redraw()
        end, 4)
    end

    ---------------------------------------------------------------- 图表
    local function draw_chart(tab, ti)
        local icons = tab.icons or tab.arrows
        local ic_h = icons and 44 or 0
        -- 图例文字已全部去掉，图表高度补回原图例那 20px，下方只留时间轴
        local a = { x = 2, y = ic_h, w = AW - 6, h = 216 - ic_h - 30 }
        local px, pw = a.x + 40, a.w - 44
        local vals = hour_vals(ti, ti == 1 and wth.feel or wth.sw[tab.swkey or ""])
        local step = pw / 11

        if tab.icons then
            for i = 1, 12 do
                local h = wth.hours[i]
                local cx = math.floor(px + (i - 1) * step + 0.5)
                wx_icon(anchor, cx - 11, 0, 22, h.ic, { bg = C.card })
                airui.label({ parent = anchor, x = cx - 20, y = 24, w = 40, h = 20,
                    text = tostring(h.v), color = C.sub, font_size = 16,
                    align = airui.TEXT_ALIGN_CENTER })
            end
        elseif tab.arrows then
            -- 风向行：与上面 7 张日期卡一一对齐（卡中心 x = 78 + (i-1)*140），
            -- 原来这里是 12 个任意角度的细线箭头，横跨图表区像一排乱斜杠
            for i = 1, 7 do
                wind_arrow(anchor, 78 + (i - 1) * 140, 20, 26,
                    (i * 45 + 30) % 360, C.cyan)
            end
        end

        local ch = theme.chart(anchor, a, {
            type = tab.type or "line",
            color = tab.color,
            y_min = tab.ymin, y_max = tab.ymax,
            fill = tab.fill, points = 12, bar_radius = tab.bar_r or 3,
            hdiv = 2, vdiv = 4,
        })
        if ch then
            theme.set_chart(ch, vals)
            -- 附加线（第二个 series）：体感/阵风/露点/温度
            if tab.sw and (ti == 1 and wth.feel or wth.sw[tab.swkey]) then
                local second = hour_vals(ti == 1 and 9 or ti, true)
                if ti == 3 then
                    for i = 1, #second do second[i] = math.floor(vals[i] * 1.6 + 4) end
                elseif ti == 4 then
                    for i = 1, #second do second[i] = math.max(0, vals[i] - 13) end
                elseif ti == 9 then
                    for i = 1, #second do second[i] = wth.hours[i].v end
                end
                local col2 = (tab.legend and tab.legend[2]) and tab.legend[2][2] or C.cyan
                pcall(function()
                    ch:add_series({ color = col2, name = "次", fill = false })
                end)
                pcall(function() ch:set_values(2, second) end)
            end
        end

        -- 时间轴
        for i = 1, 12, 2 do
            local cx = math.floor(px + (i - 1) * step + 0.5)
            airui.label({ parent = anchor, x = cx - 26, y = ic_h + a.h + 2, w = 52, h = 20,
                text = wth.hours[i].t, color = C.dim, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
        end

        -- 图例文字全部去掉（用户要求）：风速/阵风、湿度/露点、气压、可见度、
        -- 体感温度这些行下方不再有彩色说明字；tab.legend 数据保留，
        -- 第二条 series 还靠它取颜色
    end

    ---------------------------------------------------------------- 列表（横向滑动小时卡）
    local function draw_list(tab, ti)
        local card_w, gapc, card_h = 118, 10, 200
        local strip = airui.container({ parent = anchor, x = 2, y = 0,
            w = AW - 6, h = 210, color = C.card, color_opacity = 1, scrollable = true })
        for i = 1, 12 do
            local h = wth.hours[i]
            local x = (i - 1) * (card_w + gapc)
            local sel = (i == 2)
            airui.container({ parent = strip, x = x, y = 0, w = card_w, h = card_h,
                color = sel and C.sel_str or C.deep, radius = 12,
                border_color = sel and C.blue2 or C.line, border_width = 1 })
            airui.label({ parent = strip, x = x, y = 6, w = card_w, h = 22,
                text = h.t, color = sel and C.text or C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            wx_icon(strip, x + math.floor(card_w / 2) - 16, 30, 32, h.ic,
                { bg = sel and C.sel_str or C.deep })
            airui.label({ parent = strip, x = x, y = 66, w = card_w, h = 34,
                text = h.v .. "°", color = C.title, font_size = 26,
                align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = strip, x = x, y = 102, w = card_w, h = 22,
                text = h.cond or "", color = C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = strip, x = x, y = 128, w = card_w, h = 20,
                text = "体感 " .. h.fv .. "°", color = C.dim, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = strip, x = x, y = 150, w = card_w, h = 20,
                text = "降水 " .. h.p .. "%", color = C.cyan, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
            theme.click(strip, x, 0, card_w, card_h, function()
                theme.toast(h.t .. " · " .. (h.cond or "") .. " " .. h.v .. "°")
            end, 10)
        end
    end
    ---------------------------------------------------------------- 天气详细信息 12 卡
    local PWD, PHD, GAP = 246, 166, 8
    local function cell(i, title, val, vcol)
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = PX + col * (PWD + GAP)
        local y = 58 + row * (PHD + GAP)
        airui.container({ parent = root, x = x, y = y, w = PWD, h = PHD,
            color = C.card, radius = 14, border_color = C.line, border_width = 1 })
        airui.label({ parent = root, x = x + 12, y = y + 10, w = PWD - 100, h = 22,
            text = title, color = C.sub, font_size = 16 })
        if val then
            airui.label({ parent = root, x = x + PWD - 122, y = y + 8, w = 110, h = 26,
                text = val, color = vcol or C.title, font_size = 18,
                align = airui.TEXT_ALIGN_RIGHT })
        end
        return x, y
    end

    local function draw_detail()
        local T = {}
        for ti = 1, 9 do T[ti] = hour_vals(ti, false) end
        local d = wth.det
        local d1 = wth.days[1] or {}

        -- 1 温度
        local x, y = cell(1, "温度", (wth.temp or "--") .. "°", C.yellow)
        spark(root, x + 12, y + 44, PWD - 24, 52, C.yellow, T[1], 10, 35)
        airui.label({ parent = root, x = x + 12, y = y + 128, w = PWD - 24, h = 22,
            text = "最高 " .. (d1.hi or 0) .. "°   最低 " .. (d1.lo or 0) .. "°",
            color = C.sub, font_size = 16 })

        -- 2 体感温度
        x, y = cell(2, "体感温度", (wth.feels or wth.temp or "--") .. "°", C.orange)
        spark(root, x + 12, y + 44, PWD - 24, 52, C.orange, T[9], 10, 38)
        airui.label({ parent = root, x = x + 12, y = y + 128, w = PWD - 24, h = 22,
            text = "比气温略高，体感偏闷", color = C.sub, font_size = 16 })

        -- 3 云量
        x, y = cell(3, "云量", (d.cloud or 0) .. "%")
        wx_icon(root, x + 16, y + 42, 46, "cloud")
        airui.label({ parent = root, x = x + 74, y = y + 54, w = PWD - 86, h = 22,
            text = (wth.cond or "多云") .. "，短时转晴", color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = x + 74, y = y + 80, w = PWD - 86, h = 22,
            text = "今日云层较厚", color = C.dim, font_size = 16 })

        -- 4 降水
        x, y = cell(4, "降水", "1.2 mm", C.cyan)
        wx_icon(root, x + 16, y + 42, 46, "rain")
        airui.label({ parent = root, x = x + 74, y = y + 54, w = PWD - 86, h = 22,
            text = "短时有雨，带伞", color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = x + 74, y = y + 80, w = PWD - 86, h = 22,
            text = "降雨概率 40%", color = C.dim, font_size = 16 })

        -- 5 风速罗盘
        x, y = cell(5, "风速", (d.wind or 0) .. " km/h", C.cyan)
        local rcx, rcy = x + 58, y + 96
        theme.shapes(root, x + 18, y + 46, 80, 80, {
            { type = "circle", cx = 40, cy = 40, r = 36, color = C.line, width = 1 },
            { type = "line", x1 = 40, y1 = 4, x2 = 40, y2 = 14, color = C.sub, width = 2 },
            { type = "line", x1 = 40, y1 = 76, x2 = 40, y2 = 66, color = C.sub, width = 2 },
            { type = "line", x1 = 4, y1 = 40, x2 = 14, y2 = 40, color = C.sub, width = 2 },
            { type = "line", x1 = 76, y1 = 40, x2 = 66, y2 = 40, color = C.sub, width = 2 },
            { type = "line", x1 = 40, y1 = 40, x2 = 54, y2 = 26, color = C.cyan, width = 3 },
            { type = "circle", cx = 40, cy = 40, r = 4, color = C.cyan, width = 1,
              fill = true, fill_color = C.cyan, fill_opacity = 255 },
        })
        airui.label({ parent = root, x = x + 112, y = y + 64, w = PWD - 124, h = 22,
            text = "东风 2 级", color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = x + 112, y = y + 90, w = PWD - 124, h = 22,
            text = "阵风 4 级", color = C.dim, font_size = 16 })

        -- 6 湿度迷你柱
        x, y = cell(6, "湿度", (d.hum or 0) .. "%", C.blue2)
        local bars = {}
        for i = 1, 8 do
            local v = T[4][i] or 60
            local bh2 = math.floor(16 + v * 0.5)
            bars[#bars + 1] = { type = "rect", x = (i - 1) * 26 + 6, y = 62 - bh2,
                w = 14, h = bh2, color = C.blue2, radius = 4 }
        end
        theme.shapes(root, x + 12, y + 46, PWD - 24, 66, bars)
        airui.label({ parent = root, x = x + 12, y = y + 124, w = PWD - 24, h = 22,
            text = "露点 17°，体感潮湿", color = C.sub, font_size = 16 })

        -- 7 紫外线珠环
        x, y = cell(7, "紫外线", (d.uv or 0) .. " / 11", 0xF08A3C)
        local r7 = 30
        ring(root, x + PWD / 2, y + 92, r7, {
            { f = (d.uv or 0), color = 0xF08A3C },
            { f = math.max(0, 11 - (d.uv or 0)), color = C.track },
        })
        airui.label({ parent = root, x = x + PWD / 2 - 40, y = y + 82, w = 80, h = 24,
            text = tostring(d.uv or 0), color = C.title, font_size = 18,
            align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = root, x = x + 12, y = y + 130, w = PWD - 24, h = 22,
            text = "外出建议涂抹防晒", color = C.sub, font_size = 16 })

        -- 8 空气质量环
        x, y = cell(8, "空气质量指数", tostring(d.aqi or 0), C.green)
        local aqi = tonumber(d.aqi) or 0
        ring(root, x + PWD / 2, y + 92, r7, {
            { f = math.min(100, aqi), color = C.green },
            { f = math.max(0, 100 - aqi), color = C.track },
        })
        airui.label({ parent = root, x = x + PWD / 2 - 40, y = y + 82, w = 80, h = 24,
            text = tostring(aqi), color = C.green, font_size = 18,
            align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = root, x = x + 12, y = y + 130, w = PWD - 24, h = 22,
            text = "空气良，可开窗通风", color = C.sub, font_size = 16 })

        -- 9 能见度珠条
        x, y = cell(9, "能见度", tostring(d.vis) .. " 公里", C.green)
        local on = math.floor((d.vis or 0) / 25 * 30 + 0.5)
        local beads = {}
        for k = 1, 30 do
            local col = (k <= on) and C.green or C.track
            beads[#beads + 1] = { type = "circle",
                cx = ((k - 1) % 6) * 30 + 6, cy = math.floor((k - 1) / 6) * 12 + 6,
                r = 4, color = col, width = 1, fill = true, fill_color = col,
                fill_opacity = 255 }
        end
        theme.shapes(root, x + 14, y + 48, 184, 68, beads)
        airui.label({ parent = root, x = x + 12, y = y + 124, w = PWD - 24, h = 22,
            text = "有薄雾，注意保持车距", color = C.sub, font_size = 16 })

        -- 10 气压曲线
        x, y = cell(10, "气压", (d.press or 0) .. " hPa", C.purple)
        spark(root, x + 12, y + 44, PWD - 24, 52, C.purple, T[6], 1000, 1030)
        airui.label({ parent = root, x = x + 12, y = y + 128, w = PWD - 24, h = 22,
            text = "气压平稳，无明显变化", color = C.sub, font_size = 16 })

        -- 11 太阳弧
        x, y = cell(11, "日出日落")
        local arc = {}
        for k = 0, 16 do
            local a = math.pi + math.pi * k / 16
            local bx = math.floor(100 + math.cos(a) * 72 + 0.5)
            local by = math.floor(66 + math.sin(a) * 56 + 0.5)
            local col = (k < 8) and C.cyan or C.yellow
            arc[#arc + 1] = { type = "circle", cx = bx, cy = by, r = 3, color = col,
                width = 1, fill = true, fill_color = col, fill_opacity = 255 }
        end
        arc[#arc + 1] = { type = "line", x1 = 14, y1 = 66, x2 = 186, y2 = 66,
            color = C.line, width = 2 }
        theme.shapes(root, x + 24, y + 40, 200, 70, arc)
        airui.label({ parent = root, x = x + 12, y = y + 118, w = 100, h = 20,
            text = "日出 " .. (d.sunrise or ""), color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = x + PWD - 112, y = y + 118, w = 100, h = 20,
            text = "日落 " .. (d.sunset or ""), color = C.sub, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
        airui.label({ parent = root, x = x + 12, y = y + 140, w = PWD - 24, h = 20,
            text = "今日日照 10 小时 40 分", color = C.dim, font_size = 16 })

        -- 12 月相
        x, y = cell(12, "月相", d.moon or "")
        wx_icon(root, x + 16, y + 42, 56, "moon")
        airui.label({ parent = root, x = x + 84, y = y + 56, w = PWD - 96, h = 22,
            text = "月出 13:20", color = C.sub, font_size = 16 })
        airui.label({ parent = root, x = x + 84, y = y + 82, w = PWD - 96, h = 22,
            text = "月落 23:40", color = C.dim, font_size = 16 })
        airui.label({ parent = root, x = x + 16, y = y + 118, w = PWD - 32, h = 22,
            text = "今夜可见度较好", color = C.sub, font_size = 16 })
    end
    ---------------------------------------------------------------- 头部（tab + 图表/列表）
    local function draw_head()
        head = airui.container({ parent = root, x = 0, y = 202, w = W, h = 40,
            color = C.bg, color_opacity = 1 })
        airui.label({ parent = head, x = PX + 2, y = 6, w = 104, h = 24,
            text = "每小时预报", color = C.title, font_size = 16 })
        local widths = { 56, 56, 56, 56, 56, 56, 64, 64, 76 }
        local px = 118
        for i, t in ipairs(TABS) do
            local bw = widths[i] or 60
            local sel = (i == wth.tab_idx)
            theme.pill(head, { x = px, y = 4, w = bw, h = 30 }, t.name,
                { bg = sel and C.sel_str or C.deep, color = sel and C.text or C.sub,
                  border = sel and C.blue2 or C.line, font = 16 })
            local idx = i
            theme.click(head, px, 4, bw, 30, function()
                wth.tab_idx = idx
                redraw()
            end, 8)
            px = px + bw + 8
        end
        local VW = { { "图表", "chart" }, { "列表", "list" } }
        for j = 1, 2 do
            local bx = W - PX - 140 + (j - 1) * 72
            local sel = (wth.view == VW[j][2])
            theme.pill(head, { x = bx, y = 4, w = 66, h = 30 }, VW[j][1],
                { bg = sel and C.sel_str or C.deep, color = sel and C.text or C.sub,
                  border = sel and C.blue2 or C.line, font = 16 })
            local key = VW[j][2]
            theme.click(head, bx, 4, 66, 30, function()
                wth.view = key
                redraw()
            end, 8)
        end
    end

    ---------------------------------------------------------------- 内容卡
    ---------------------------------------------------------------- 内容卡（标题 + 开关 + 日期条 + 图表/列表）
    local function draw_ov()
        ov = airui.container({ parent = root, x = PX, y = 244, w = CW, h = 348,
            color = C.card, radius = 14, border_color = C.line, border_width = 1 })
        anchor = airui.container({ parent = ov, x = 2, y = 2, w = CW - 4, h = 344,
            color = C.card, color_opacity = 1 })
        local tab = TABS[wth.tab_idx] or TABS[1]
        airui.label({ parent = anchor, x = 12, y = 6, w = 240, h = 22,
            text = "七日预报 · " .. tab.name, color = C.title, font_size = 16 })
        draw_switch(tab)
        draw_strip(tab, wth.tab_idx)
        bd = airui.container({ parent = anchor, x = 0, y = 120, w = CW - 4, h = 216,
            color = C.card, color_opacity = 1 })
        -- 图表/列表的坐标都从 body 顶算起：临时把 anchor 指过去，
        -- 这样 draw_chart / draw_list 里写的 y=0 不会盖住日期条
        local save = anchor
        anchor = bd
        if wth.view == "list" then
            draw_list(tab, wth.tab_idx)
        else
            draw_chart(tab, wth.tab_idx)
        end
        anchor = save
    end

    redraw = function()
        pcall(function() if head then head:destroy() end end)
        pcall(function() if ov then ov:destroy() end end)
        head, ov, bd, anchor = nil, nil, nil, nil
        draw_head()
        draw_ov()
    end

    ---------------------------------------------------------------- Hero
    local d0 = wth.days[wth.cur or 1] or wth.days[1] or {}
    theme.card(root, { x = PX, y = 58, w = CW, h = 140 }, { radius = 16 })

    -- 城市切换键：跟温度放一起（原来挂右上角，用户要求挪进卡片）
    local city_w, city_h = 216, 28
    airui.container({ parent = root, x = PX + 14, y = 64, w = city_w, h = city_h,
        color = C.deep, radius = 14, border_color = C.line, border_width = 1 })
    airui.label({ parent = root, x = PX + 14, y = 67, w = city_w - 26, h = 22,
        text = wth.area, color = C.sub, font_size = 16,
        align = airui.TEXT_ALIGN_CENTER })
    theme.shapes(root, PX + 14 + city_w - 24, 72, 12, 12, {
        { type = "line", x1 = 1, y1 = 4, x2 = 6, y2 = 9, color = C.sub, width = 2 },
        { type = "line", x1 = 6, y1 = 9, x2 = 11, y2 = 4, color = C.sub, width = 2 } })
    theme.click(root, PX + 14, 64, city_w, city_h, open_dd, 10)

    wx_icon(root, PX + 14, 96, 56, d0.ic or "rain")
    airui.label({ parent = root, x = PX + 82, y = 96, w = 150, h = 56,
        text = tostring(wth.temp or "--"), color = C.title, font_size = 44 })
    airui.label({ parent = root, x = PX + 152, y = 102, w = 46, h = 24,
        text = "°C", color = C.sub, font_size = 18 })
    airui.label({ parent = root, x = PX + 226, y = 96, w = 200, h = 28,
        text = wth.cond or "", color = C.text, font_size = 20 })
    airui.label({ parent = root, x = PX + 228, y = 124, w = 200, h = 22,
        text = "体感 " .. tostring(wth.feels or "--") .. "°", color = C.sub,
        font_size = 16 })
    airui.label({ parent = root, x = PX + 380, y = 100, w = CW - 400, h = 22,
        text = wth.tip or "", color = C.dim, font_size = 16 })
    for i, s in ipairs(wth.chips or {}) do
        local cw = math.floor((CW - 24 - 5 * 8) / 6)
        theme.pill(root, { x = PX + 12 + (i - 1) * (cw + 8), y = 160, w = cw, h = 26 },
            s, { bg = C.deep, color = C.sub, border = C.line, font = 16 })
    end
    draw_head()
    draw_ov()

    return function()
        -- 天气模拟数据是静态的，1.5s 刷新不需要动作；
        -- 保留返回函数是因为 theme.make_page 约定 build 可返回 update 回调
    end
end)
