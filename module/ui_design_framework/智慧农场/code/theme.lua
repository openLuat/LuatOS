--[[
@module theme
@summary 主题配色 / 自适应布局 / 通用控件（青绿科技风，与 preview.html 一致）
]]

local sys   = require "sys"
local exwin = require "exwin"

local theme = {}

--------------------------------------------------------------------
-- 屏幕分辨率（自适应）
--------------------------------------------------------------------
theme.W, theme.H = 1024, 600   -- Air8603 10寸 RGB 屏（main.lua display.init 后由 display.getSize 覆盖）
pcall(function()
    -- RGB 屏走 display 核心库（lcd 库不感知 RGB 帧缓冲）；display 为全局核心库，不可 require
    local w, h = display.getSize()
    if w and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 主题配色（青绿科技风，与 preview.html 完全一致）
--------------------------------------------------------------------
theme.C = {
    bg     = 0x1C6248,  -- 整屏背景
    panel  = 0x0A3B2A,  -- 面板底色（半透明）
    card   = 0x083022,  -- 卡片/图表底色
    border = 0x36B583,  -- 面板边框 / 网格线
    accent = 0x4EE6B0,  -- 薄荷绿主强调色
    mint2  = 0x23C98A,
    text   = 0xF2FFF9,  -- 主文字
    sub    = 0x9ED4BC,  -- 次要文字
    orange = 0xFFA14A,
    pink   = 0xFF4FA0,
    yellow = 0xFFD34D,
    blue   = 0x4F8CFF,
    purple = 0x8B7BFF,
    cyan   = 0x35D0E0,
    red    = 0xFF6B6B,
}

theme.NAV_H  = 44               -- 顶部导航栏高度（字号≥16 需要更高按钮）
theme.PAD    = 6                -- 全局间距
theme.IMGDIR = "/luadb/img/"    -- 贴图资源目录

-- 贴图路径解析：自动探测目录 + 存在性检查
-- Luatools 保留子目录时 PNG 在 /luadb/img/；不保留时在 /luadb/；
-- 文件不存在时返回 nil（跳过图片显示，避免 LVGL 加载失败直接死机）
local _imgdir
function theme.img(name)
    if _imgdir == nil then
        for _, d in ipairs({ "/luadb/img/", "/luadb/", "/img/" }) do
            if io.exists(d .. "ic_grain.png") then
                _imgdir = d
                break
            end
        end
        if _imgdir == nil then
            log.warn("theme", "img dir not found, all icons disabled")
            _imgdir = false
        else
            log.info("theme", "img dir = " .. _imgdir)
        end
    end
    if _imgdir == false then return nil end
    local p = _imgdir .. name
    if not io.exists(p) then
        log.warn("theme", "img missing: " .. p)
        return nil
    end
    return p
end

theme.nav_names = {
    "农场总览", "作物监测", "环境监测", "资源优化",
    "智能设备", "生产运营", "市场销售", "质量追溯",
}

--------------------------------------------------------------------
-- 页面注册与切换
--------------------------------------------------------------------
local registry = {}
local current_win = nil

function theme.register(idx, mod)
    registry[idx] = mod
end

sys.subscribe("SWITCH_PAGE", function(idx)
    local mod = registry[idx]
    if not mod then return end
    -- exwin 是窗口栈：必须先 close 当前栈顶窗口，再 open 新窗口；
    -- 先开后关会把旧窗留在栈底，close 时焦点处理错乱导致白屏
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
-- 页面工厂
--------------------------------------------------------------------
function theme.make_page(idx, title, build_fn)
    local M = { idx = idx, title = title }
    local root, timer_id

    local function create_ui()
        log.info("ui", "create page " .. idx)
        root = airui.container({
            parent = airui.screen,
            x = 0, y = 0, w = theme.W, h = theme.H,
            color = theme.C.bg,
        })
        theme.draw_nav(root, idx)
        log.info("ui", "nav done")

        local cx = theme.PAD
        local cy = theme.NAV_H + theme.PAD
        local cw = theme.W - theme.PAD * 2
        local ch = theme.H - cy - theme.PAD

        local update = build_fn(root, cx, cy, cw, ch)
        if update then
            update()
            timer_id = sys.timerLoopStart(update, 1500)
        end

        exwin.bind_root(root)
        log.info("ui", "page " .. idx .. " ready")
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
-- 顶部导航栏：///装饰 + 图标徽章 + 标题 + 8个页面按钮 + 底部亮线
--------------------------------------------------------------------
function theme.draw_nav(root, cur_idx)
    local C = theme.C
    log.info("nav", "1 label")
    airui.label({ parent = root, x = 8, y = 8, w = 42, h = 24,
        text = "///", color = C.accent, font_size = 16 })
    log.info("nav", "2 badge")
    airui.container({ parent = root, x = 46, y = 9, w = 20, h = 20,
        color = C.accent, color_opacity = 36, radius = 5,
        border_color = C.accent, border_width = 1 })
    local logo = theme.img("ic_grain.png")
    log.info("nav", "3 logo=" .. tostring(logo))
    if logo then
        airui.image({ parent = root, src = logo,
            x = 48, y = 11, w = 16, h = 16 })
    end
    log.info("nav", "4 title")
    airui.label({ parent = root, x = 72, y = 7, w = 110, h = 24,
        text = "智慧农场", color = C.text, font_size = 17 })

    local nav_x   = 195
    local total_w = theme.W - nav_x - theme.PAD
    local n       = #theme.nav_names
    local bw      = math.floor(total_w / n) - 4

    log.info("nav", "5 line")
    airui.container({ parent = root, x = 186, y = 17,
        w = nav_x - 196, h = 2, color = C.accent, color_opacity = 110 })

    log.info("nav", "6 buttons")
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
                text_color   = is_cur and 0x062E1E or C.text,
                border_color = is_cur and C.accent or C.border,
                border_width = 1,
                radius       = 4,
                pad          = 0,
            },
            on_click = function()
                if i ~= cur_idx then theme.open_page(i) end
            end,
        })
        log.info("nav", "  btn" .. i)
    end

    log.info("nav", "7 bottom line")
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
-- 面板：圆角卡片 + 四角括号 + 图标标题带 + 虚线分隔
--------------------------------------------------------------------
function theme.panel(parent, r, title, icon)
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
    if icon then
        local ip = theme.img(icon)
        if ip then
            airui.image({ parent = parent, src = ip,
                x = r.x + 15, y = r.y + 8, w = 16, h = 16 })
        end
    end
    airui.label({ parent = parent, x = r.x + 36, y = r.y + 6,
        w = r.w - 42, h = 20, text = title, color = C.text, font_size = 16 })
    airui.shape({ parent = parent, x = r.x + 10, y = r.y + 27,
        w = r.w - 20, h = 1, items = { { type = "line", x1 = 0, y1 = 0,
            x2 = r.w - 20, y2 = 0, color = C.accent, width = 1,
            opacity = 110, dash_width = 4, dash_gap = 3 } } })
    return { x = r.x + 8, y = r.y + 31, w = r.w - 16, h = r.h - 36 }
end

--------------------------------------------------------------------
-- 面板栅格：2列×3行（i = 1..6）
--------------------------------------------------------------------
function theme.cell(cx, cy, cw, ch, i)
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local pw  = math.floor((cw - theme.PAD) / 2)
    local ph  = math.floor((ch - theme.PAD * 2) / 3)
    return {
        x = cx + col * (pw + theme.PAD),
        y = cy + row * (ph + theme.PAD),
        w = pw, h = ph,
    }
end
--------------------------------------------------------------------
-- 指标卡组（带图标 + 四角括号；ncol=2 横向小卡，ncol=3 竖排大卡）
--------------------------------------------------------------------
function theme.metrics(parent, a, items, ncol)
    ncol = ncol or 3
    local C    = theme.C
    log.info("ui", "metrics x" .. #items)
    local rows = math.ceil(#items / ncol)
    local cw   = math.floor(a.w / ncol)
    local ch   = math.floor(a.h / rows)
    local out  = {}
    for i, it in ipairs(items) do
        local col = (i - 1) % ncol
        local row = math.floor((i - 1) / ncol)
        local mx  = a.x + col * cw
        local my  = a.y + row * ch
        airui.container({ parent = parent, x = mx + 2, y = my + 2,
            w = cw - 4, h = ch - 4, color = C.card, color_opacity = 170,
            border_color = C.border, border_width = 1, radius = 5 })
        theme.brackets(parent, mx + 2, my + 2, cw - 4, ch - 4, 6, C.accent, 2)
        local h = {}
        -- 统一居中卡片样式（对齐 html 设计稿）：圆形图标居中在上，名称/数值居中在下
        local ccx = mx + math.floor(cw / 2)
        local y0  = (rows > 1) and 2 or 8   -- 两行卡片高度减半，用紧凑间距
        airui.shape({ parent = parent, x = ccx - 14, y = my + y0, w = 28, h = 28,
            items = { { type = "circle", cx = 14, cy = 14, r = 13,
                color = C.accent, width = 2,
                fill = true, fill_color = C.accent, fill_opacity = 40 } } })
        if it.icon then
            local ip = theme.img(it.icon)
            if ip then
                airui.image({ parent = parent, src = ip,
                    x = ccx - 8, y = my + y0 + 6, w = 16, h = 16 })
            end
        end
        airui.label({ parent = parent, x = mx + 4, y = my + y0 + 28,
            w = cw - 8, h = 20, text = it.name,
            color = C.sub, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        h.lbl = airui.label({ parent = parent, x = mx + 4, y = my + y0 + 48,
            w = cw - 8, h = ch - y0 - 50, text = "--",
            color = it.color or C.accent, font_size = (rows > 1) and 16 or 21,
            align = airui.TEXT_ALIGN_CENTER })
        h.unit = it.unit or ""
        out[i] = h
    end
    return out
end

function theme.set_metric(h, v, dec)
    h.lbl:set_text(string.format("%." .. (dec or 1) .. "f", v) .. h.unit)
end

--------------------------------------------------------------------
-- 告警/状态列表（薄荷绿左竖条 + 半透明行）
--------------------------------------------------------------------
function theme.list(parent, a, rows, colors)
    local C   = theme.C
    local n   = #rows
    log.info("ui", "list x" .. n)
    local rh  = math.floor(a.h / n)
    local out = {}
    for i, name in ipairs(rows) do
        local ly = a.y + (i - 1) * rh
        airui.container({ parent = parent, x = a.x, y = ly,
            w = a.w, h = rh - 3, color = C.accent, color_opacity = 34, radius = 4 })
        airui.container({ parent = parent, x = a.x, y = ly,
            w = 3, h = rh - 3, color = C.accent })
        airui.label({ parent = parent, x = a.x + 10, y = ly + 1,
            w = math.floor(a.w / 2), h = rh - 6,
            text = name, color = C.text, font_size = 16 })
        out[i] = { lbl = airui.label({ parent = parent,
            x = a.x + math.floor(a.w / 2), y = ly + 1,
            w = math.floor(a.w / 2) - 10, h = rh - 6,
            text = "--", font_size = 16,
            color = (colors and colors[i]) or C.sub,
            align = airui.TEXT_ALIGN_RIGHT }) }
    end
    return out
end

function theme.set_val(h, text)
    h.lbl:set_text(text)
end
--------------------------------------------------------------------
-- 图表：折线（渐变填充+数据点）/ 柱状（圆角+多系列+图例）
-- cfg = { type, y_max, series={{name,color}..} 或 color=, points=,
--         ulabel="产量(吨)", cats={"水稻"..}, y_unit= }
--------------------------------------------------------------------
function theme.chart(parent, a, cfg)
    cfg = cfg or {}
    local C = theme.C
    log.info("ui", "chart " .. tostring(cfg.ulabel or cfg.type or "line"))
    local series = cfg.series or { { color = cfg.color or C.accent } }
    -- 布局：左留44px 自绘Y轴刻度，下留18px 自绘分类名，上留22px 自绘单位标签
    -- （C 组件自带的 x_axis/y_axis 刻度标签与 legend 坐标不受控，会画出面板外，全部禁用）
    local y, h = a.y, a.h
    if cfg.ulabel then
        airui.label({ parent = parent, x = a.x, y = a.y, w = 160, h = 20,
            text = cfg.ulabel, color = 0xCFEBDC, font_size = 16 })
        y = a.y + 22
        h = a.h - 22
    end
    if cfg.cats then h = h - 18 end
    local px, pw = a.x + 44, a.w - 48   -- 绘图区

    -- 自绘 Y 轴刻度（右对齐贴绘图区左缘）
    local ymax = cfg.y_max or 100
    for i = 0, 4 do
        airui.label({ parent = parent,
            x = a.x, y = y + h - 18 - math.floor((h - 18) * i / 4),
            w = 40, h = 18, text = tostring(math.floor(ymax * i / 4 + 0.5)),
            color = C.sub, font_size = 16, align = airui.TEXT_ALIGN_RIGHT })
    end

    -- 自绘图例（圆点 + 名称，右对齐在单位标签行）
    if #series > 1 then
        local lw = 84
        for i = 1, #series do
            local lx = px + pw - (#series - i) * lw - lw + 4
            airui.shape({ parent = parent, x = lx, y = a.y + 6, w = 10, h = 10,
                items = { { type = "circle", cx = 5, cy = 5, r = 5,
                    color = series[i].color,
                    fill = true, fill_color = series[i].color, fill_opacity = 255 } } })
            airui.label({ parent = parent, x = lx + 13, y = a.y + 1,
                w = lw - 15, h = 20, text = series[i].name or "",
                color = C.sub, font_size = 16 })
        end
    end

    local first = series[1]
    local ch = airui.chart({
        parent       = parent,
        x = px, y = y, w = pw, h = h,
        type         = cfg.type or "line",
        y_min        = cfg.y_min or 0,
        y_max        = cfg.y_max or 100,
        point_count  = cfg.points or 24,
        update_mode  = "shift",
        line_color   = first.color,
        line_width   = (cfg.type == "bar") and 2 or 3,
        point_radius = (cfg.type == "bar") and 0 or 3,
        fill         = (cfg.type == "line") and
            { enable = true, color = first.color, opa_start = 150, opa_end = 0 } or nil,
        hdiv         = 3,
        vdiv         = 6,
        legend       = false,
        bg_color     = C.card,
        bg_opa       = 200,
        grid_color   = C.border,
        grid_opa     = 110,
        bar_radius      = 3,
        bar_series_gap  = 4,
        bar_group_gap   = 8,
        x_axis       = { enable = false },
        y_axis       = { enable = false },
    })
    if #series > 1 then
        for i = 2, #series do
            ch:add_series({ color = series[i].color, name = series[i].name or "" })
        end
    end
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

function theme.set_chart(ch, ...)
    local vals = { ... }
    -- 关键1：把数据点数量设为实际数据长度，否则柱状图只在绘图区前段占位
    -- 关键2：set_values 只支持整数，小数点会不显示（曲线断断续续），必须取整
    pcall(ch.set_point_count, ch, #vals[1])
    for i = 1, #vals do
        for k, v in ipairs(vals[i]) do
            vals[i][k] = math.floor(v + 0.5)
        end
        ch:set_values(i, vals[i])
    end
end
--------------------------------------------------------------------
-- 环形图（纯 AirUI 组件绘制：圆头弦线拼分段圆环 + 图例 + 中心数值）
-- 图例 val 支持 "31.84%" 或 "68" 两种写法，按数值占比分配弧长
--------------------------------------------------------------------
function theme.donut(parent, a, img, legend, center_v, center_n)
    local C  = theme.C
    log.info("ui", "donut (shape) x" .. #legend)
    local n  = #legend
    local rh = math.floor(a.h / n)

    -- ① 分段圆环：shape 没有 arc 图元，且固件对粗描边 line 渲染不可靠；
    --    circle 图元渲染稳定，故用沿圆周等距分布的彩色圆点串成"珠链圆环"，
    --    每个分段按数值占比点亮对应数量的珠子，从 12 点钟方向顺时针排布
    local cx, cy = math.floor(a.h / 2), math.floor(a.h / 2)  -- 相对 shape 容器
    local R      = math.floor(a.h / 2) - 13                  -- 珠链半径
    local total  = 0
    local vals   = {}
    for i = 1, n do
        -- 注意：gsub 返回 (结果, 次数) 两个值，必须先赋值取第一个，
        -- 否则次数会传进 tonumber 的 base 参数直接抛错，拖垮整个页面构建
        local sv = string.gsub(tostring(legend[i].val), "%%", "")
        vals[i] = tonumber(sv) or 1
        total   = total + vals[i]
    end
    -- pcall 保护：圆环绘制异常时不中断页面构建（图例/中心文字仍正常）
    pcall(function()
        -- 累计占比，用于把角度映射到分段
        local cum, acc = {}, 0
        for i = 1, n do
            acc = acc + vals[i] / total
            cum[i] = acc
        end
        -- ① 描边圈 + 底环（实机验证 fill=false 的 circle 一定能渲染）
        airui.shape({ parent = parent, x = a.x, y = a.y, w = a.h, h = a.h,
            items = {
                { type = "circle", cx = cx, cy = cy,
                  r = R + 11, color = C.border, width = 1, fill = false, opacity = 80 },
                { type = "circle", cx = cx, cy = cy,
                  r = R - 10, color = C.border, width = 1, fill = false, opacity = 60 },
                { type = "circle", cx = cx, cy = cy, r = R,
                  color = C.mint2, width = 4, fill = false, opacity = 110 },
            } })
        -- ② 彩色珠链：每 5° 一颗、珠芯 r=7 相邻重叠 ~9px，视觉近似连续实心环
        --    注意1：固件会丢弃 width=0 的图元，实心圆必须带 width>=1（实机踩坑）
        --    注意2：固件解析 circle 的 cx/cy 不接受小数（解析失败归 0），
        --           三角函数坐标必须四舍五入取整，否则整批图元消失（实机踩坑）
        --    注意3：分两个 shape 各画一半，防止单 shape 图元数量上限吞掉后半段
        local N = 96
        local items = {}
        for k = 0, N - 1 do
            local adeg = -90 + 360 * (k + 0.5) / N
            local frac = (adeg + 90) / 360
            local seg = n
            for i = 1, n do
                if frac < cum[i] then seg = i break end
            end
            local ar = math.rad(adeg)
            local bx  = math.floor(cx + R * math.cos(ar) + 0.5)
            local by  = math.floor(cy + R * math.sin(ar) + 0.5)
            local col = legend[seg].color
            items[#items + 1] = { type = "circle", cx = bx, cy = by, r = 8,
                color = col, width = 2, fill = true,
                fill_color = col, fill_opacity = 255 }
            if #items == 32 then
                airui.shape({ parent = parent, x = a.x, y = a.y, w = a.h, h = a.h,
                    items = items })
                items = {}
            end
        end
        if #items > 0 then
            airui.shape({ parent = parent, x = a.x, y = a.y, w = a.h, h = a.h,
                items = items })
        end
    end)

    -- ② 中心数值 + 名称（居中于圆环）
    local out = {}
    out.v = airui.label({ parent = parent,
        x = a.x + cx - 60, y = a.y + cy - 28, w = 120, h = 30,
        text = center_v or "", color = C.text, font_size = 24,
        align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = parent,
        x = a.x + cx - 60, y = a.y + cy + 4, w = 120, h = 20,
        text = center_n or "", color = C.sub, font_size = 16,
        align = airui.TEXT_ALIGN_CENTER })

    -- ③ 图例（圆点 + 名称 + 数值，字体16）
    -- 行距按 html 收紧（上限 28px），整块在内容区垂直居中
    local rh   = math.min(math.floor(a.h / n), 28)
    local yoff = math.floor((a.h - n * rh) / 2)
    local lw   = a.w - a.h - 12
    local lx   = a.x + a.h + 10
    -- 布局对齐 html：圆点固定一列、名称固定一列（同一 x 起点，天然严格对齐），
    -- 列位置放在图例区中部偏左（html 同款），数值右对齐到面板右缘
    local name_x = math.max(math.floor(lw * 0.30), 56)  -- 名称列起点（相对 lx）
    local dot_cx = math.max(name_x - 22, 6)             -- 圆点列（圆心）
    local dots = {}
    for i = 1, n do
        -- 圆点 cx/cy 必须取整：固件解析小数坐标会失败丢弃图元（实机踩坑）
        dots[i] = { type = "circle",
            cx = dot_cx,
            cy = yoff + math.floor(rh / 2) + (i - 1) * rh,
            r = 5, color = legend[i].color,
            fill = true, fill_color = legend[i].color, fill_opacity = 255 }
    end
    -- 容器宽度必须是整个图例区：圆点 cx 超出 shape 容器范围会被裁剪
    airui.shape({ parent = parent, x = lx, y = a.y, w = lw, h = a.h, items = dots })
    for i = 1, n do
        -- 关键：ly 是内容区相对坐标，必须加 a.y 才是根容器绝对坐标
        -- 文字框在行内精确居中（(rh-20)/2），使文字中心 = 圆点圆心
        local ly = a.y + yoff + (i - 1) * rh + math.floor((rh - 20) / 2)
        airui.label({ parent = parent, x = lx + name_x, y = ly,
            w = lw - name_x - 94, h = 20, text = legend[i].name,
            color = C.text, font_size = 16 })
        airui.label({ parent = parent, x = lx + lw - 84, y = ly,
            w = 80, h = 20, text = legend[i].val,
            color = C.text, font_size = 16, align = airui.TEXT_ALIGN_RIGHT })
    end
    return out
end

--------------------------------------------------------------------
-- 雷达图（3帧贴图轮播 + 图例）
--------------------------------------------------------------------
function theme.radar(parent, a, legend)
    local C  = theme.C
    log.info("ui", "radar")
    local iw = math.floor(math.min(a.h * 2, a.w * 0.62))
    local frames = {}
    for _, f in ipairs({ "radar1.png", "radar2.png", "radar3.png" }) do
        local p = theme.img(f)
        if p then frames[#frames + 1] = p end
    end
    if #frames >= 2 then
        airui.animimg({ parent = parent, x = a.x, y = a.y, w = iw, h = a.h,
            frames = frames, duration = 6000, loop = true, auto_play = true })
    end
    local lx = a.x + iw + 8
    local lw = a.x + a.w - lx
    local n  = #legend
    -- 行距按 html 收紧（上限 28px），整块在内容区垂直居中
    local rh   = math.min(math.floor(a.h / n), 28)
    local yoff = math.floor((a.h - n * rh) / 2)
    local dots = {}
    for i = 1, n do
        -- 圆点 cy 必须取整：固件解析小数坐标会失败丢弃图元（实机踩坑）
        dots[i] = { type = "circle", cx = 5,
            cy = yoff + math.floor(rh / 2) + (i - 1) * rh,
            r = 5, color = legend[i].color,
            fill = true, fill_color = legend[i].color, fill_opacity = 255 }
    end
    airui.shape({ parent = parent, x = lx, y = a.y, w = 10, h = a.h, items = dots })
    for i = 1, n do
        -- 同 donut：文字框在行内精确居中（(rh-20)/2），使文字中心 = 圆点圆心
        local ly = a.y + yoff + (i - 1) * rh + math.floor((rh - 20) / 2)
        airui.label({ parent = parent, x = lx + 14, y = ly,
            w = lw - 14, h = 20, text = legend[i].name,
            color = C.text, font_size = 16 })
    end
end

--------------------------------------------------------------------
-- 进度条组（动态 shape 重绘），用 theme.set_progress(h, pct) 更新
--------------------------------------------------------------------
function theme.progress(parent, a, rows)
    local C   = theme.C
    local n   = #rows
    log.info("ui", "progress x" .. n)
    local rh  = math.floor(a.h / n)
    local out = {}
    for i, row in ipairs(rows) do
        local ry = a.y + (i - 1) * rh
        airui.container({ parent = parent, x = a.x,
            y = ry + math.floor(rh / 2) - 5, w = 10, h = 10,
            color = row.color, radius = 2 })
        airui.label({ parent = parent, x = a.x + 18, y = ry,
            w = 80, h = rh, text = row.name, color = C.text, font_size = 16 })
        local pct = airui.label({ parent = parent, x = a.x + 98, y = ry,
            w = 52, h = rh, text = "--", color = row.color, font_size = 16 })
        local tw = a.w - 158
        local sh = airui.shape({ parent = parent, x = a.x + 152, y = ry,
            w = tw, h = rh, items = {
                { type = "rect", x = 0, y = math.floor(rh / 2) - 3,
                  w = tw, h = 7, radius = 3, color = 0x052A1C, width = 1,
                  fill = true, fill_color = 0x052A1C, fill_opacity = 220 } } })
        out[i] = { pct = pct, sh = sh, tw = tw, rh = rh,
            color = row.color, pc = row.pc or 0 }
    end
    return out
end

function theme.set_progress(h, pct)
    pct = math.max(0, math.min(100, pct))
    h.pct:set_text(pct .. "%")
    local bw = math.max(math.floor(h.tw * pct / 100), 2)
    local my = math.floor(h.rh / 2)
    h.sh:set_items({
        { type = "rect", x = 0, y = my - 3, w = h.tw, h = 7, radius = 3,
          color = 0x052A1C, width = 1,
          fill = true, fill_color = 0x052A1C, fill_opacity = 220 },
        { type = "rect", x = 0, y = my - 3, w = bw, h = 7, radius = 3,
          color = h.color, width = 0,
          fill = true, fill_color = h.color, fill_opacity = 230 },
        { type = "circle", cx = bw, cy = my, r = 4,
          color = 0xFFFFFF, width = 0,
          fill = true, fill_color = 0xFFFFFF, fill_opacity = 255 },
    })
end

return theme