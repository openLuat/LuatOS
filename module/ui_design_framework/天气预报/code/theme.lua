--[[
@module theme
@summary 天气预报大屏 - 主题配色 / 自适应布局 / 通用控件
        （Win11 天气深色风，与 preview.html 一致）
]]

local sys   = require "sys"
local exwin = require "exwin"

local theme = {}

--------------------------------------------------------------------
-- 屏幕分辨率（自适应）
--------------------------------------------------------------------
theme.W, theme.H = 1024, 600
pcall(function()
    -- display 为全局核心库，不可 require
    local w, h = display.getSize()
    if w and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 主题配色：深色（默认，Win11 天气深色版）/ 浅色，与 preview.html 一致
-- C 是"当前生效"的调色板：toggle_theme 就地覆写字段值，
-- 页面重建后所有控件自动跟随（闭包里 local C = theme.C 拿的是同一张表）
--------------------------------------------------------------------
theme.cur = "dark"
theme.PALETTES = {
    dark = {
        bg     = 0x141D33,  -- 整屏背景
        panel  = 0x1F2A47,  -- 面板底色
        card   = 0x1A2340,  -- 卡片/图表底色
        deep   = 0x22345F,  -- 更深一档（tab/胶囊/下拉面板）
        border = 0x35486F,  -- 边框 / 网格线
        accent = 0x5AA7FF,  -- 主强调色（蓝）
        on_accent = 0x0A1830, -- 强调色底上的文字/图标
        text   = 0xE8EEFC,  -- 主文字
        sub    = 0x8FA0BF,  -- 次要文字
        cloud  = 0xBFD7F2,  -- 天气图标云朵色
        yellow = 0xF5C542,
        orange = 0xF0A03C,
        green  = 0x7CC26E,
        cyan   = 0x5FD0E8,
        purple = 0x8F7FF0,
        red    = 0xE6533C,
        blue   = 0x4A90E2,
    },
    light = {
        bg     = 0xEEF1F8,
        panel  = 0xF3F5FA,
        card   = 0xFFFFFF,
        deep   = 0xE3E9F6,
        border = 0xC6D2EA,
        accent = 0x0A7CD5,
        on_accent = 0xFFFFFF,
        text   = 0x1A2437,
        sub    = 0x5A6B8C,
        cloud  = 0x9FB6D8,
        yellow = 0xD8A017,
        orange = 0xE08030,
        green  = 0x3E9E4F,
        cyan   = 0x1FA8C8,
        purple = 0x7C6AE0,
        red    = 0xD64530,
        blue   = 0x2F6FD0,
    },
}
theme.C = {}
for k, v in pairs(theme.PALETTES.dark) do theme.C[k] = v end

--------------------------------------------------------------------
-- 颜色预混合（滑动卡顿优化）：
-- "半透明色叠底色"离线算成不透明色，运行时避开 LVGL 逐像素
-- alpha 混合——全屏半透明面板是滚动时最大的性能开销
--------------------------------------------------------------------
function theme.blend(fg, bg, alpha)
    if alpha > 1 then alpha = alpha / 255 end
    if alpha > 1 then alpha = 1 end
    if alpha < 0 then alpha = 0 end
    local r = math.floor((fg >> 16 & 0xFF) * alpha + (bg >> 16 & 0xFF) * (1 - alpha) + 0.5)
    local g = math.floor((fg >> 8 & 0xFF) * alpha + (bg >> 8 & 0xFF) * (1 - alpha) + 0.5)
    local b = math.floor((fg & 0xFF) * alpha + (bg & 0xFF) * (1 - alpha) + 0.5)
    return (r << 16) | (g << 8) | b
end

local function derive_colors()
    local C = theme.C
    C.card_soft = theme.blend(C.panel, C.bg, 150 / 255)    -- 原 panel@150 半透明卡底
    C.grid      = theme.blend(C.border, C.card, 110 / 255) -- 原 border@110 网格线
    C.slider_lo = theme.blend(C.accent, C.card, 0.65)      -- 日期卡滑条旋钮以下的深色段
end
derive_colors()

-- 深浅主题切换（就地覆写 C；返回 "dark"/"light"）
function theme.toggle_theme()
    theme.cur = (theme.cur == "dark") and "light" or "dark"
    for k, v in pairs(theme.PALETTES[theme.cur]) do theme.C[k] = v end
    derive_colors()
    log.info("theme", "switch to " .. theme.cur)
    return theme.cur
end

theme.NAV_H  = 44               -- 顶部导航栏高度（字号≥16 需要更高按钮）
theme.PAD    = 6                -- 全局间距

theme.nav_names = { "当前天气", "详细信息" }

--------------------------------------------------------------------
-- 页面注册与切换（踩坑：exwin 必须"先 close 旧栈顶，再 open 新窗"，
-- 先开后关会把旧窗留在栈底，close 时焦点错乱导致白屏）
--------------------------------------------------------------------
local registry = {}
local current_win = nil

function theme.register(idx, mod)
    registry[idx] = mod
end

sys.subscribe("SWITCH_PAGE", function(idx)
    local mod = registry[idx]
    if not mod then return end
    if current_win then
        local w = current_win
        current_win = nil
        log.info("ui", "exwin.close " .. tostring(w))
        pcall(exwin.close, w)
    end
    log.info("ui", "exwin.open page " .. idx)
    current_win = mod.open()
    log.info("ui", "exwin.open done, win=" .. tostring(current_win))
end)

function theme.open_page(idx)
    sys.publish("SWITCH_PAGE", idx)
end

--------------------------------------------------------------------
-- 页面工厂（build_fn 返回 1.5s 刷新回调）
-- opts.no_nav = true 时不画顶部导航（单页长滚动布局，页面自绘顶栏）
--------------------------------------------------------------------
function theme.make_page(idx, title, build_fn, opts)
    opts = opts or {}
    local M = { idx = idx, title = title }
    local root, timer_id

    local function create_ui()
        log.info("ui", "create page " .. idx)
        root = airui.container({
            parent = airui.screen,
            x = 0, y = 0, w = theme.W, h = theme.H,
            color = theme.C.bg,
        })
        local cx, cy
        if opts.no_nav then
            cx, cy = 0, 0
        else
            theme.draw_nav(root, idx)
            cx = theme.PAD
            cy = theme.NAV_H + theme.PAD
        end
        local cw = theme.W - cx * 2
        local ch = theme.H - cy - (opts.no_nav and 0 or theme.PAD)

        local update = build_fn(root, cx, cy, cw, ch, M.rerender)
        if update then
            update()
            timer_id = sys.timerLoopStart(update, 1500)
        end

        -- 踩坑：部分固件版本的 exwin 没有 bind_root 方法，
        -- 直接调用 = attempt to call a nil value → VM exit 重启
        if exwin.bind_root then
            pcall(exwin.bind_root, root)
        end
        log.info("ui", "page " .. idx .. " ready")
    end

    -- 整页重建（主题切换用）：停刷新定时器 → 销毁旧 root → 重跑 create_ui
    -- 注意：必须在 LVGL 事件回调之外调用（页面里用 sys.timerStart 延迟）
    function M.rerender()
        if timer_id then sys.timerStop(timer_id) timer_id = nil end
        if root then pcall(root.destroy, root) root = nil end
        create_ui()
    end

    function M.open()
        return exwin.open({
            on_create  = create_ui,
            on_destroy = function()
                if timer_id then sys.timerStop(timer_id) timer_id = nil end
                if root then root:destroy() root = nil end
            end,
        })
    end

    theme.register(idx, M)
    return M
end

--------------------------------------------------------------------
-- 顶部导航栏：///装饰 + 标题 + 页面按钮 + 底部亮线
-- （天气工程不使用任何 PNG 贴图，规避单 IDAT / 预缩放两个实机坑）
--------------------------------------------------------------------
function theme.draw_nav(root, cur_idx)
    local C = theme.C
    airui.label({ parent = root, x = 8, y = 8, w = 42, h = 24,
        text = "///", color = C.accent, font_size = 16 })
    airui.container({ parent = root, x = 46, y = 9, w = 20, h = 20,
        color = C.accent, color_opacity = 36, radius = 5,
        border_color = C.accent, border_width = 1 })
    airui.label({ parent = root, x = 72, y = 7, w = 110, h = 24,
        text = "天气预报", color = C.text, font_size = 16 })

    local nav_x   = 195
    local total_w = theme.W - nav_x - theme.PAD
    local n       = #theme.nav_names
    -- 只有 2 个页面，按钮不限宽（上限 200 保持导航栏比例）
    local bw    = math.min(math.floor(total_w / n) - 4, 200)

    airui.container({ parent = root, x = 186, y = 17,
        w = nav_x - 196, h = 2, color = C.accent, color_opacity = 110 })

    for i = 1, n do
        local is_cur = (i == cur_idx)
        airui.button({
            parent = root,
            x = nav_x + (i - 1) * math.floor(total_w / n) + 2,
            y = 6, w = bw, h = theme.NAV_H - 12,
            text = theme.nav_names[i],
            font_size = 16,
            style = {
                bg_color     = is_cur and C.accent or C.panel,
                text_color   = is_cur and 0x0A1830 or C.text,
                border_color = is_cur and C.accent or C.border,
                border_width = 1,
                radius       = 4,
                pad          = 0,
            },
            on_click = function()
                if i ~= cur_idx then theme.open_page(i) end
            end,
        })
    end

    airui.container({ parent = root, x = 0, y = theme.NAV_H,
        w = theme.W, h = 2, color = C.accent, color_opacity = 150 })
end

--------------------------------------------------------------------
-- 四角括号装饰（一个 shape 画 8 条短线）
--------------------------------------------------------------------
function theme.brackets(parent, x, y, w, h, size, color, width)
    airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = {
        { type = "line", x1 = 0,       y1 = 0,       x2 = size,  y2 = 0, color = color, width = width },
        { type = "line", x1 = 0,       y1 = 0,       x2 = 0,     y2 = size, color = color, width = width },
        { type = "line", x1 = w - size, y1 = 0,      x2 = w,     y2 = 0, color = color, width = width },
        { type = "line", x1 = w,       y1 = 0,       x2 = w,     y2 = size, color = color, width = width },
        { type = "line", x1 = 0,       y1 = h - size, x2 = 0,    y2 = h, color = color, width = width },
        { type = "line", x1 = 0,       y1 = h,       x2 = size,  y2 = h, color = color, width = width },
        { type = "line", x1 = w,       y1 = h - size, x2 = w,    y2 = h, color = color, width = width },
        { type = "line", x1 = w - size, y1 = h,      x2 = w,     y2 = h, color = color, width = width },
    } })
end

--------------------------------------------------------------------
-- 面板：圆角卡片 + 四角括号 + 标题带 + 虚线分隔
--------------------------------------------------------------------
function theme.panel(parent, r, title)
    local C = theme.C
    log.info("ui", "panel " .. title)
    airui.container({
        parent = parent,
        x = r.x, y = r.y, w = r.w, h = r.h,
        color = C.panel, color_opacity = 150,
        border_color = C.border, border_width = 1,
        radius = 8,
    })
    theme.brackets(parent, r.x, r.y, r.w, r.h, 9, C.accent, 2)
    airui.container({ parent = parent, x = r.x + 8, y = r.y + 5,
        w = r.w - 16, h = 22, color = C.accent, color_opacity = 42, radius = 11 })
    airui.label({ parent = parent, x = r.x + 18, y = r.y + 6,
        w = r.w - 24, h = 20, text = title, color = C.text, font_size = 16 })
    airui.shape({ parent = parent, x = r.x + 10, y = r.y + 27,
        w = r.w - 20, h = 1, items = { { type = "line", x1 = 0, y1 = 0,
            x2 = r.w - 20, y2 = 0, color = C.accent, width = 1,
            opacity = 110, dash_width = 4, dash_gap = 3 } } })
    return { x = r.x + 8, y = r.y + 31, w = r.w - 16, h = r.h - 36 }
end

--------------------------------------------------------------------
-- 图表：折线（渐变填充）/ 柱状
-- cfg = { type, y_min, y_max, points, color, ulabel, cats }
-- 踩坑：C chart 自带 x_axis/y_axis/legend 坐标不受控（画出面板外），
--       全部禁用，Y 轴刻度/单位/时间轴改为自绘 label
--------------------------------------------------------------------
function theme.chart(parent, a, cfg)
    cfg = cfg or {}
    local C = theme.C
    log.info("ui", "chart " .. tostring(cfg.ulabel or cfg.type or "line"))
    local y, h = a.y, a.h
    if cfg.ulabel then
        airui.label({ parent = parent, x = a.x, y = a.y, w = 170, h = 20,
            text = cfg.ulabel, color = C.sub, font_size = 16 })
        y = a.y + 22
        h = a.h - 22
    end
    if cfg.cats then h = h - 18 end
    local px, pw = a.x + 44, a.w - 48   -- 绘图区

    -- 自绘 Y 轴刻度（右对齐贴绘图区左缘；label 宽度给足防折行）
    -- cfg.ylab = false 可关闭（小尺寸嵌入式图表）
    local ymax = cfg.y_max or 100
    local ymin = cfg.y_min or 0
    if cfg.ylab ~= false then
        for i = 0, 4 do
            local v = ymin + (ymax - ymin) * i / 4
            airui.label({ parent = parent,
                x = a.x, y = y + h - 18 - math.floor((h - 18) * i / 4),
                w = 40, h = 18, text = tostring(math.floor(v + 0.5)),
                color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_RIGHT })
        end
    end

    local ch = airui.chart({
        parent       = parent,
        x = px, y = y, w = pw, h = h,
        type         = cfg.type or "line",
        y_min        = ymin,
        y_max        = ymax,
        point_count  = cfg.points or 24,
        update_mode  = "shift",
        line_color   = cfg.color or C.accent,
        line_width   = (cfg.type == "bar") and 2 or 3,
        point_radius = (cfg.type == "bar") and 0 or 3,
        -- 踩坑：渐变填充必须用 fill={enable,opa_start,opa_end}，
        --       fill_fade 在部分固件上不生效
        -- 性能：渐变填充=全图逐像素混合，cfg.fill=false 可关（非概览 tab 已关）
        fill         = (cfg.type == "line" and cfg.fill ~= false) and
            { enable = true, color = cfg.color or C.accent,
              opa_start = 150, opa_end = 0 } or nil,
        legend       = false,
        bg_color     = C.card,
        bg_opa       = 255,
        grid_color   = C.grid,
        grid_opa     = 255,
        hdiv         = cfg.hdiv or 2,
        vdiv         = cfg.vdiv or 4,
        bar_radius      = cfg.bar_radius or 3,
        bar_series_gap  = 4,
        bar_group_gap   = 8,
        x_axis       = { enable = false },
        y_axis       = { enable = false },
    })
    if cfg.cats then
        local n = #cfg.cats
        for i, cname in ipairs(cfg.cats) do
            airui.label({ parent = parent,
                x = px + math.floor(pw * (i - 0.5) / n) - 36,
                y = y + h + 1, w = 72, h = 18,
                text = cname, color = C.sub, font_size = 16,
                align = airui.TEXT_ALIGN_CENTER })
        end
    end
    return ch
end

--------------------------------------------------------------------
-- 踩坑1：chart 数据点数量必须设为实际长度，否则曲线挤在绘图区左侧
-- 踩坑2：set_values 只支持整数，小数点会不显示（曲线断断续续），必须取整
--------------------------------------------------------------------
function theme.set_chart(ch, vals)
    pcall(ch.set_point_count, ch, #vals)
    for k, v in ipairs(vals) do
        vals[k] = math.floor(v + 0.5)
    end
    ch:set_values(1, vals)
end

--------------------------------------------------------------------
-- 雨滴动画（html 同款：下雨的雨在动）
-- wicon 的 rain/thunder 雨滴/闪电画在独立 shape 上，
-- 全局 200ms 定时器用 set_items 轮换 3 个相位（下落 0/3/6px 循环）。
-- 切主题/切视图重建后，已销毁的 shape 会在下个 tick 自动剔除
--------------------------------------------------------------------
theme._rain = {}
theme._rain_timer = nil

function theme._rain_reg(shp, base, mode, flash_col)
    theme._rain[#theme._rain + 1] = { shp = shp, base = base, ph = 0,
        mode = mode or "rain", flash_col = flash_col }
    if not theme._rain_timer then
        theme._rain_timer = sys.timerLoopStart(theme.anim_rain, 100)
    end
end

function theme.anim_rain()
    for i = #theme._rain, 1, -1 do
        local e = theme._rain[i]
        local ok = pcall(function()
            if e.shp:is_destroyed() then error("gone") end
            e.ph = (e.ph + 1) % 12
            local items = {}
            if e.mode == "flash" then
                -- 闪电：不位移，原地明暗闪烁（html 同款闪现效果；
                -- 之前跟着雨滴上下平移，观感很怪）
                local on = (e.ph % 4) < 2
                for _, it in ipairs(e.base) do
                    items[#items + 1] = { type = "line",
                        x1 = it.x1, y1 = it.y1,
                        x2 = it.x2, y2 = it.y2,
                        color = on and it.color or (e.flash_col or it.color),
                        width = it.width }
                end
            else
                -- 雨滴：每滴错开相位、连续下落（html 同款雨丝流动感）
                for k, it in ipairs(e.base) do
                    local p = (e.ph + k * 2) % 6
                    local dy = p * 2
                    items[#items + 1] = { type = "line",
                        x1 = it.x1, y1 = it.y1 + dy,
                        x2 = it.x2, y2 = it.y2 + dy,
                        color = it.color, width = it.width }
                end
            end
            e.shp:set_items(items)
        end)
        if not ok then table.remove(theme._rain, i) end
    end
end

--------------------------------------------------------------------
-- 天气图标：纯 shape 绘制（太阳/月亮/云/局部晴/雨/雷阵雨）
-- 踩坑规避：不用 PNG（单IDAT/预缩放）；实心圆必须 width>=1；
--           所有圆心/半径四舍五入取整（小数坐标固件解析失败图元消失）
-- kind: sun / moon / cloud / partly / rain / thunder
-- bgcol: 月亮缺口覆盖色（传所在卡片底色）
--------------------------------------------------------------------
function theme.wicon(parent, x, y, s, kind, bgcol)
    local SUN, CLOUD, RAINC = 0xF5C542, theme.C.cloud or 0xBFD7F2, 0x5FA8E8
    local DK = bgcol or 0x16203A
    local items, drops = {}, {}   -- drops: 雨滴/闪电（可动画部分，独立 shape）
    local function c(cx, cy, r, col, opa)
        items[#items + 1] = { type = "circle",
            cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5),
            r = math.floor(r + 0.5), color = col, width = 1,
            fill = true, fill_color = col, fill_opacity = opa or 255 }
    end
    local function ln(x1, y1, x2, y2, col, w, tgt)
        local t = tgt or items
        t[#t + 1] = { type = "line",
            x1 = math.floor(x1), y1 = math.floor(y1),
            x2 = math.floor(x2), y2 = math.floor(y2), color = col, width = w }
    end
    local function rays(cx, cy, r1, r2, n, col, w)
        for i = 0, n - 1 do
            local a = math.rad(i * 360 / n - 90)
            ln(cx + r1 * math.cos(a), cy + r1 * math.sin(a),
               cx + r2 * math.cos(a), cy + r2 * math.sin(a), col, w)
        end
    end
    local function cloud(ox, cy, sc, col)
        c(ox + 0.36 * s * sc, cy + 0.10 * s * sc, 0.16 * s * sc, col)
        c(ox + 0.55 * s * sc, cy,             0.20 * s * sc, col)
        c(ox + 0.72 * s * sc, cy + 0.10 * s * sc, 0.15 * s * sc, col)
    end
    if kind == "sun" then
        c(0.50 * s, 0.50 * s, 0.24 * s, SUN)
        rays(0.50 * s, 0.50 * s, 0.32 * s, 0.44 * s, 8, SUN, 2)
    elseif kind == "moon" then
        c(0.50 * s, 0.50 * s, 0.28 * s, SUN)
        c(0.70 * s, 0.36 * s, 0.24 * s, DK)
    elseif kind == "cloud" then
        cloud(0, 0.52 * s, 1, CLOUD)
    elseif kind == "partly" then
        c(0.66 * s, 0.30 * s, 0.14 * s, SUN)
        rays(0.66 * s, 0.30 * s, 0.19 * s, 0.26 * s, 6, SUN, 2)
        cloud(-0.10 * s, 0.62 * s, 0.8, CLOUD)
    elseif kind == "rain" then
        cloud(0, 0.42 * s, 0.95, CLOUD)
        ln(0.34 * s, 0.64 * s, 0.30 * s, 0.80 * s, RAINC, 2, drops)
        ln(0.50 * s, 0.64 * s, 0.46 * s, 0.84 * s, RAINC, 2, drops)
        ln(0.66 * s, 0.64 * s, 0.62 * s, 0.80 * s, RAINC, 2, drops)
    elseif kind == "thunder" then
        cloud(0, 0.40 * s, 0.95, CLOUD)
        ln(0.52 * s, 0.58 * s, 0.42 * s, 0.72 * s, SUN, 3, drops)
        ln(0.42 * s, 0.72 * s, 0.52 * s, 0.72 * s, SUN, 3, drops)
        ln(0.52 * s, 0.72 * s, 0.44 * s, 0.86 * s, SUN, 3, drops)
    end
    airui.shape({ parent = parent, x = x, y = y,
        w = math.floor(s), h = math.floor(s), items = items })
    if #drops > 0 then
        -- 雨滴/闪电画在独立 shape 上，由 anim_rain 驱动（html 同款）：
        -- rain=雨滴错相位下落；thunder=闪电原地明暗闪烁，不位移
        local shp = airui.shape({ parent = parent, x = x, y = y,
            w = math.floor(s), h = math.floor(s) + 14, items = drops })
        if kind == "thunder" then
            theme._rain_reg(shp, drops, "flash", theme.blend(SUN, DK, 0.3))
        else
            theme._rain_reg(shp, drops)
        end
    end
end

--------------------------------------------------------------------
-- 平滑圆环（农场实机验证方案：沿圆周密集彩色小圆拼接，相邻珠高度重叠成实心环）
-- segs = { {f=0.5, color=..}, ... } 按占比从12点方向顺时针排布
--------------------------------------------------------------------
function theme.ring(parent, cx, cy, r, segs)
    cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
    local total = 0
    for _, s in ipairs(segs) do total = total + s.f end

    -- 珠径固定 5（环粗不变）；珠数按弧长自适应：珠心距 ≈3.5px，
    -- 相邻珠高度重叠（原来 20 珠、间距 9.4px 几乎相切，看上去是一串点），
    -- 现在连成平滑实心的圆环（对齐农场的平滑效果）
    local br = 5
    local N  = math.floor(2 * math.pi * r / 3.5 + 0.5)
    if N < 24 then N = 24 elseif N > 72 then N = 72 end

    local ox, oy = r + 8, r + 8                       -- 圆心（shape 容器内坐标）
    local sx, sy = cx - r - 8, cy - r - 8             -- 容器左上角（屏幕坐标）
    local items = { { type = "circle", cx = ox, cy = oy, r = r,
        color = theme.C.border, width = 1, fill = false, opacity = 120 } }

    for k = 0, N - 1 do
        local frac = (k + 0.5) / N
        local col = segs[#segs].color
        local acc = 0
        for _, s in ipairs(segs) do
            acc = acc + s.f / total
            if frac <= acc then col = s.color break end
        end
        local a = math.rad(-90 + 360 * frac)
        items[#items + 1] = { type = "circle",
            cx = math.floor(ox + r * math.cos(a) + 0.5),
            cy = math.floor(oy + r * math.sin(a) + 0.5),
            r = br, color = col, width = 1,
            fill = true, fill_color = col, fill_opacity = 255 }
        -- 单个 shape 图元过多会被固件丢弃，按 32 个一批分开建（农场实机验证）
        if #items >= 32 then
            airui.shape({ parent = parent, x = sx, y = sy,
                w = 2 * r + 16, h = 2 * r + 16, items = items })
            items = {}
        end
    end
    if #items > 0 then
        airui.shape({ parent = parent, x = sx, y = sy,
            w = 2 * r + 16, h = 2 * r + 16, items = items })
    end
end

--------------------------------------------------------------------
-- 迷你曲线（shape 折线段 + 末端圆点；线宽3，规避粗描边畸形坑）
-- pts=整数数组, ymin/ymax 数据量程
--------------------------------------------------------------------
function theme.spark(parent, x, y, w, h, color, pts, ymin, ymax)
    local n = #pts
    if n < 2 then return end
    local items, P = {}, {}
    for i = 1, n do
        local fy = 1 - (pts[i] - ymin) / (ymax - ymin)
        if fy < 0 then fy = 0 end
        if fy > 1 then fy = 1 end
        P[i] = { x = math.floor(w * (i - 1) / (n - 1) + 0.5),
                 y = math.floor(h * fy + 0.5) }
    end
    for i = 2, n do
        items[#items + 1] = { type = "line", x1 = P[i-1].x, y1 = P[i-1].y,
            x2 = P[i].x, y2 = P[i].y, color = color, width = 3 }
    end
    items[#items + 1] = { type = "circle", cx = P[n].x, cy = P[n].y, r = 4,
        color = color, width = 1, fill = true, fill_color = color, fill_opacity = 255 }
    airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = items })
end

return theme
