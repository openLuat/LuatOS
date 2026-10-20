--[[
@module  ui_widgets
@summary 通用界面组件库（面板 / 标题 / 指标卡 / 进度条 / 芯片 / 图标 / 表格 / 开关 / 分段 / 步进器）
@version 1.0.0
@date    2026.10.10
@usage
本模块只负责“画控件”，不含任何业务数据；所有颜色来自传入的主题表 T。
各视图模块复用这里的组件，保证风格统一、数据与界面解耦。
]]

local W = {}

-- 屏幕密度缩放（设计基准 1024x600）
function W.d(v)
    local s = _G.density_scale or 1
    return math.floor(v * s + 0.5)
end

-- 数值取整：AirUI 的 airui_marshal_integer 使用 lua_tointeger，
-- 对「带小数的浮点数」会返回 0，因此所有传给 airui 的坐标/尺寸必须是整数。
function W.i(v)
    return math.floor((v or 0) + 0.5)
end

-- ============ 基础 ============
-- 全局字号放大系数：设计稿按浏览器渲染选的 10~12px 在 hzfont 下偏细偏小，
-- 统一放大以提升可读性；系数在 config.text_scale 中调整。
W.text_scale = (require "config").text_scale or 1.3

-- 注意：
-- 1) AirUI 的 label 在 text 为空时不会创建文本对象，后续 set_text 无法显示，
--    故空文本统一用空格占位；
-- 2) 放大字号后同步放大文本框高度并保持原盒垂直居中，避免文字被裁切。
function W.label(parent, x, y, w, h, text, size, color, align)
    if text == nil or text == "" then text = " " end
    local fs = math.floor(size * (W.text_scale or 1) + 0.5)
    local lh = math.max(h, math.floor(fs * 1.5 + 0.5))
    local ny = y + math.floor((h - lh) / 2 + 0.5)
    -- 左边界保护：带 1px 边框的容器内容区从 1 开始，
    -- 子控件 x<1 会让 LVGL 判定可横向滚动并画出多余滚动条（保持右边界不变）
    local lx, lw = x, w
    if lx < 1 then
        lw = lw - (1 - lx)
        lx = 1
    end
    return airui.label({
        parent = parent,
        x = W.d(lx), y = W.d(ny), w = W.d(lw), h = W.d(lh),
        text = text,
        font_size = W.d(fs),
        color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 1px 分隔线
function W.divider(parent, x, y, w, color)
    return airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = 1,
        color = color,
    })
end

-- 面板：圆角 + 描边 + 右上角装饰角标（对应设计稿 .panel::after）
-- no_corner = true 时不画角标（如指标卡/统计卡）
function W.panel(parent, x, y, w, h, T, radius, no_corner)
    local c = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        color = T.panel,
        radius = W.d(radius or 7),
        border_color = T.ring,
        border_width = 1,
    })
    if not no_corner then
        -- 角标必须比面板内容区边界再内缩 2px：只要触及边界，LVGL 就会判定可滚动并画出滚动条
        airui.container({ parent = c, x = W.d(w - 14), y = 2, w = W.d(11), h = 1, color = T.accent_line })
        airui.container({ parent = c, x = W.d(w - 4), y = 2, w = 1, h = W.d(11), color = T.accent_line })
    end
    return c
end

-- 面板标题区：左侧发光竖条 + 标题 + 右侧副标题（返回副标题 label 句柄，便于动态刷新）
-- 调用方传 py=14（面板头高度 34），内部统一按「视觉中心 cy」摆放，竖条/标题/副标题三者对齐
function W.panel_title(panel, px, py, w, title, sub, T)
    local cy = py + 3
    airui.container({
        parent = panel,
        x = W.d(px), y = W.d(cy - 6),
        w = W.d(3), h = W.d(12),
        color = T.cyan, radius = W.d(2),
    })
    W.label(panel, px + 9, cy - 12, w - 100, 24, title, 13, T.text_soft)
    if sub and sub ~= "" then
        return W.label(panel, px, cy - 9, w - 18, 18, sub, 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    end
    return nil
end

-- 大数值右侧单位标签的 X 位置估算
-- 按放大后的 24*1.3≈31 号字：数字宽约 17px、小数点约 9px，末尾留 6px 间隙
function W.unit_x(valstr)
    local s = tostring(valstr or "")
    local wpx = 0
    for i = 1, #s do
        wpx = wpx + (s:sub(i, i) == "." and 9 or 17)
    end
    return 12 + wpx + 6
end

-- 水平进度条（pct 0..100）
function W.bar(parent, x, y, w, h, pct, color, bg)
    return airui.bar({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = math.max(2, W.d(h)),
        min = 0, max = 100, value = math.floor(pct + 0.5),
        radius = W.d(math.floor(h / 2)),
        border_width = 0,
        bg_color = bg,
        indicator_color = color,
    })
end

-- 芯片（带可选脉冲圆点）；on_click 为可选点击回调（如顶栏「运行中」状态组件）
function W.chip(parent, x, y, w, text, running, T, on_click)
    local c = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(28),
        radius = W.d(14),
        color = running and T.accent_soft or T.chip_bg,
        border_color = running and T.cyan or T.ring,
        border_width = 1,
        on_click = on_click,
    })
    local tx = 11
    if running then
        airui.container({
            parent = c, x = W.d(11), y = W.d(11),
            w = W.d(6), h = W.d(6), radius = W.d(3), color = T.cyan,
        })
        tx = 23
    end
    -- 文字框四周留 3px 余量，避免贴住芯片内容区边界
    W.label(c, tx, 4, w - tx - 14, 18, text, 11, running and T.cyan or T.chip_text,
        airui.TEXT_ALIGN_LEFT)
    return c
end

-- ============ 导航图标（矢量绘制，随主题变色）============
local ICON_BUILDERS = {}

ICON_BUILDERS.overview = function(c)
    local items = {}
    local pos = { {1, 1}, {11, 1}, {1, 11}, {11, 11} }
    for _, p in ipairs(pos) do
        items[#items + 1] = { type = "rect", x = p[1], y = p[2], w = 8, h = 8,
            radius = 2, color = c, width = 2 }
    end
    return items
end

ICON_BUILDERS.chrom = function(c)
    -- 折线（对应设计稿色谱波形），坐标全部取整
    local pts = { {2, 15}, {4, 15}, {6, 9}, {8, 17}, {10, 4},
                  {12, 15}, {14, 10}, {16, 13}, {18, 13} }
    local items = {}
    for i = 1, #pts - 1 do
        items[#items + 1] = { type = "line",
            x1 = pts[i][1], y1 = pts[i][2], x2 = pts[i + 1][1], y2 = pts[i + 1][2],
            color = c, width = 2, round_start = true, round_end = true }
    end
    return items
end

ICON_BUILDERS.ms = function(c)
    -- 5 根柱（对应设计稿质谱柱），间距 ≥2px 避免糊成一根
    local bars = { {2, 17, 11}, {6, 17, 6}, {10, 17, 2}, {14, 17, 8}, {18, 17, 13} }
    local items = {}
    for _, b in ipairs(bars) do
        items[#items + 1] = { type = "line", x1 = b[1], y1 = b[2], x2 = b[1], y2 = b[3],
            color = c, width = 2, round_start = true, round_end = true }
    end
    return items
end

ICON_BUILDERS.data = function(c)
    return {
        { type = "ellipse", cx = 10, cy = 4,  rx = 6, ry = 2, color = c, width = 2 },
        { type = "ellipse", cx = 10, cy = 10, rx = 6, ry = 2, color = c, width = 2 },
        { type = "ellipse", cx = 10, cy = 16, rx = 6, ry = 2, color = c, width = 2 },
        { type = "line", x1 = 4,  y1 = 4, x2 = 4,  y2 = 16, color = c, width = 2 },
        { type = "line", x1 = 16, y1 = 4, x2 = 16, y2 = 16, color = c, width = 2 },
    }
end

ICON_BUILDERS.settings = function(c)
    -- 齿轮：中心圆 + 8 根短辐条
    local items = { { type = "circle", cx = 10, cy = 10, r = 3, color = c, width = 2 } }
    for k = 0, 7 do
        local a = k * math.pi / 4
        local ca, sa = math.cos(a), math.sin(a)
        items[#items + 1] = { type = "line",
            x1 = W.i(10 + ca * 5), y1 = W.i(10 + sa * 5),
            x2 = W.i(10 + ca * 7.5), y2 = W.i(10 + sa * 7.5),
            color = c, width = 2, round_start = true, round_end = true }
    end
    return items
end

-- 图标图元构造（局部坐标 0..size），供 W.icon / W.icon_set_color 复用
-- 所有图元坐标必须为整数（AirUI 对浮点取整字段会得到 0）
local function icon_items(name, size, color)
    local builder = ICON_BUILDERS[name]
    if not builder then return nil end
    local s = W.d(size) / 20
    local items = builder(color)
    for _, it in ipairs(items) do
        for k, v in pairs(it) do
            if type(v) == "number" and k ~= "color" then
                it[k] = W.i(v * s)
            end
        end
        if (it.width or 1) < 1 then it.width = 1 end
    end
    return items
end

-- 绘制导航图标（返回 shape 对象，可 destroy）
function W.icon(parent, name, x, y, size, color)
    local items = icon_items(name, size, color)
    if not items then return nil end
    return airui.shape({
        parent = parent,
        x = W.d(x), y = W.d(y),
        w = W.d(size), h = W.d(size),
        items = items,
    })
end

-- 图标原地改色：只重解析 items，不销毁/重建对象（导航激活态切换用，避免切换时白建对象）
function W.icon_set_color(shape, name, size, color)
    if not shape then return end
    local items = icon_items(name, size, color)
    if items then shape:set_items(items) end
end

-- ============ 指标卡（大数值 + 单位 + 底部进度条）============
-- opts = { label, value, unit, sub, pct, color }
-- 返回 { val, unit, bar }，视图层在数据刷新时更新
function W.metric_card(parent, x, y, w, h, opts, T)
    local card = W.panel(parent, x, y, w, h, T, nil, true)
    -- 内容块整体下移并拉开行距：标签→数值约 9px、数值→副标题约 12px，
    -- 使内容块在「卡片顶部 ~ 底部进度条」之间基本居中
    W.label(card, 12, 31, w - 26, 20, opts.label, 11, T.text_dim)
    local val = W.label(card, 12, 66, w - 26, 30, opts.value, 24, T.text_bright)
    local unit = W.label(card, W.unit_x(opts.value), 76, 48, 18, opts.unit or "", 11, T.cyan)
    W.label(card, 12, 112, w - 18, 14, opts.sub or "", 10, T.text_faint)
    -- 进度条四周内缩 2px：贴住卡片内容区边界会触发滚动条
    local bar = W.bar(card, 2, h - 6, w - 5, 3, opts.pct or 0, opts.color or T.cyan, T.bar_bg)
    return { card = card, val = val, unit = unit, bar = bar }
end

-- ============ 表格（# / 次列 / 名称 / 末列）============
-- head = {"#", "RT", "组分", "匹配"}
-- rows = { {c1=.., c2=.., c3=.., c4=.., level="high|mid|low"}, ... }
function W.table(parent, x, y, w, h, head, rows, T)
    local idx_w, c2_w, c4_w = 26, 50, 46
    local hx = x + 12
    local hw = w - 24
    W.label(parent, hx, y, hw, 16, head[1], 10, T.head_text)
    W.label(parent, hx + idx_w, y, c2_w, 16, head[2], 10, T.head_text)
    W.label(parent, hx + idx_w + c2_w, y, hw - idx_w - c2_w - c4_w, 16, head[3], 10, T.head_text)
    W.label(parent, hx, y, hw, 16, head[4], 10, T.head_text, airui.TEXT_ALIGN_RIGHT)
    W.divider(parent, hx, y + 20, hw, T.ring)

    local level_color = { high = T.cyan, mid = T.amber, low = T.text_dim }
    for i, r in ipairs(rows) do
        -- 行距 36（原 31）：表格更透气，且末行仍在面板内
        local ry = y + 28 + (i - 1) * 36
        W.label(parent, hx, ry, idx_w, 20, tostring(r[1]), 11, T.text_dim)
        W.label(parent, hx + idx_w, ry, c2_w, 20, tostring(r[2]), 11, T.text_soft)
        W.label(parent, hx + idx_w + c2_w, ry, hw - idx_w - c2_w - c4_w, 20, tostring(r[3]), 11.5, T.text_bright)
        W.label(parent, hx, ry, hw, 20, tostring(r[4]), 11.5,
            level_color[r.level] or T.cyan, airui.TEXT_ALIGN_RIGHT)
        W.divider(parent, hx, ry + 28, hw, T.ring)
    end
end

-- ============ 手动开关（42x22，匹配设计稿）============
function W.toggle(parent, x, y, checked, on_change, T)
    local state = { on = checked and true or false, knob = nil, track = nil }

    local function apply()
        local on = state.on
        state.track:set_color(on and T.accent_soft or T.toggle_off, 255)
        state.track:set_border_color(on and T.cyan or T.ring, 1)
        state.knob:set_color(on and T.cyan or T.toggle_knob, 255)
        state.knob:set_pos(W.d(on and 24 or 2), W.d(2))
    end

    state.track = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(42), h = W.d(22),
        radius = W.d(11),
        color = T.toggle_off,
        border_color = T.ring,
        border_width = 1,
        on_click = function()
            state.on = not state.on
            apply()
            if on_change then on_change(state.on) end
        end,
    })
    state.knob = airui.container({
        parent = state.track,
        x = W.d(2), y = W.d(2), w = W.d(16), h = W.d(16),
        radius = W.d(8),
        color = T.toggle_knob,
    })
    apply()

    return {
        set = function(v) state.on = v and true or false; apply() end,
        get = function() return state.on end,
    }
end

-- ============ 分段选择（2 个及以上选项）============
function W.seg(parent, x, y, w, h, options, active, on_change, T)
    -- 留 4px 余量（左右各 1px 边框 + 2px 富余），避免选项超出容器触发滚动条
    local ow = math.floor((w - 4) / #options)
    local holders, labels = {}, {}
    local current = active

    local function apply()
        for i = 1, #options do
            local on = (i == current)
            holders[i]:set_color(on and T.accent_soft or T.panel, 255)
            labels[i]:set_color(on and T.cyan or T.text_dim)
        end
    end

    local outer = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        radius = W.d(6),
        color = T.panel,
        border_color = T.ring,
        border_width = 1,
    })
    for i, opt in ipairs(options) do
        local ox = 1 + (i - 1) * ow
        local holder = airui.container({
            parent = outer,
            x = W.d(ox), y = 2,
            w = W.d(ow), h = W.d(h - 6),
            color = T.panel,
            on_click = function()
                current = i
                apply()
                if on_change then on_change(i, opt) end
            end,
        })
        local lbl = W.label(holder, 1, 4, ow - 3, 22, opt, 11.5, T.text_dim, airui.TEXT_ALIGN_CENTER)
        holders[i] = holder
        labels[i] = lbl
    end
    apply()

    return {
        set = function(i)
            if i >= 1 and i <= #options then current = i; apply() end
        end,
    }
end

-- ============ 步进器（- 数值 +）============
-- spec = { min, max, step, unit }；on_step(dir) -> dir=1/-1
-- 注意：减号用 ASCII "-"（hzfont 不含 U+2212 数学减号，会显示成方框）
function W.stepper(parent, x, y, spec, value, on_step, T)
    local function fmt(v)
        local txt
        if spec.step < 1 then txt = string.format("%.1f", v) else txt = string.format("%d", math.floor(v + 0.5)) end
        return txt .. " " .. (spec.unit or "")
    end

    local btn_style = {
        bg_color = T.panel, border_color = T.ring, border_width = 1,
        radius = W.d(5), text_color = T.text_soft, pressed_bg_color = T.accent_soft,
    }
    airui.button({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(22), h = W.d(22),
        text = "-", font_size = W.d(17),
        style = btn_style,
        on_click = function() if on_step then on_step(-1) end end,
    })
    -- 数值框放宽到 88：放大字号后 “8 °C/min” 这类最长文本才不会折行
    local val = W.label(parent, x + 29, y + 1, 88, 20, fmt(value), 13, T.text_bright, airui.TEXT_ALIGN_RIGHT)
    local p = x + 29 + 88 + 7
    airui.button({
        parent = parent,
        x = W.d(p), y = W.d(y), w = W.d(22), h = W.d(22),
        text = "+", font_size = W.d(17),
        style = btn_style,
        on_click = function() if on_step then on_step(1) end end,
    })

    return {
        set = function(v) val:set_text(fmt(v)) end,
    }
end

-- ============ 绘图组件 ============
-- 局部坐标换算
local function o(v) return W.d(v) end

-- 实时 TIC 色谱图：折线 + 渐变填充 + 峰位标注
-- (x,y,w,h) 为 chart 控件矩形；返回 handle:update(chrom, peaks)
function W.tic_chart(parent, x, y, w, h, T)
    local chart = airui.chart({
        parent = parent,
        x = o(x), y = o(y), w = o(w), h = o(h),
        type = "line",
        y_min = 0, y_max = 1000,
        point_count = 180,
        update_mode = "shift",
        line_color = T.cyan, line_width = 2, point_radius = 0,
        bg_opa = 0, border_width = 0,
        hdiv = 5, vdiv = 6,
        grid_color = T.ring, grid_opa = 110,
        fill = { enable = true, color = T.cyan, opa_start = 150, opa_end = 0 },
        x_axis = { enable = true, min = 0, max = 12, ticks = 7 },
        -- 关掉内置 Y 轴数字（设计稿为相对强度 1.0~0.0，内置标签无法格式化），
        -- 网格线由 hdiv/vdiv 绘制，不受影响；刻度文字自行绘制。
        y_axis = { enable = false },
    })

    -- 自绘 Y 轴刻度：1.0 / 0.8 / 0.6 / 0.4 / 0.2 / 0.0
    for i = 0, 5 do
        W.label(parent, x - 36, y + h * i / 5 - 8, 30, 16,
            string.format("%.1f", 1.0 - i * 0.2), 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    end

    -- 峰位圆点 + 名称（叠在曲线之上）
    local shape = airui.shape({
        parent = parent, x = o(x), y = o(y), w = o(w), h = o(h), items = {},
    })
    local labels = {}
    local handle = { chart = chart, shape = shape }

    function handle.update(chrom, peaks)
        chart:set_values(1, chrom)
        local items, li = {}, 0
        for i = 1, #peaks do
            local p = peaks[i]
            if p.name then
                local px = W.i(w * p.x)
                local py = W.i(h * (1 - math.min(p.h * 0.94, 1)))
                items[#items + 1] = { type = "circle", cx = px, cy = py, r = 3,
                    color = T.text_bright, width = 1,
                    fill = true, fill_color = T.text_bright, fill_opacity = 255 }
                li = li + 1
                if not labels[li] then
                    labels[li] = W.label(parent, x + px - 26, y + py - 20, 52, 16, p.name,
                        11, T.text_soft, airui.TEXT_ALIGN_CENTER)
                else
                    labels[li]:set_text(p.name)
                    labels[li]:set_pos(o(x + px - 26), o(y + py - 20))
                end
            end
        end
        shape:set_items(items)
    end
    return handle
end

-- 质谱柱状图（shape 绘制，含网格/坐标轴/刻度）
-- (x,y,w,h) 为画布矩形；返回 handle:update(bars)
-- 注意：所有图元坐标必须为整数，否则 AirUI 侧会取到 0（柱子消失）
function W.spectrum(parent, x, y, w, h, T)
    local padL, padR, padT, padB = 34, 10, 16, 24
    local plotL, plotT = padL, padT
    local plotW, plotH = w - padL - padR, h - padT - padB
    local baseY = plotT + plotH

    -- 画布矩形再各内缩 3px：贴住面板内容区边界会让面板出现滚动条
    local shape = airui.shape({
        parent = parent, x = o(x), y = o(y), w = o(w - 3), h = o(h - 3), items = {},
    })

    -- 静态层：网格 + 坐标轴 + m/z 78 标记
    local stat = {}
    for i = 1, 3 do
        local yy = W.i(plotT + plotH * i / 4)
        stat[#stat + 1] = { type = "line", x1 = plotL, y1 = yy, x2 = plotL + plotW, y2 = yy,
            color = T.ring, width = 1, dash_width = 2, dash_gap = 5 }
    end
    for j = 1, 4 do
        local xx = W.i(plotL + plotW * j / 5)
        stat[#stat + 1] = { type = "line", x1 = xx, y1 = plotT, x2 = xx, y2 = baseY,
            color = T.ring, width = 1, dash_width = 2, dash_gap = 5 }
    end
    stat[#stat + 1] = { type = "line", x1 = plotL, y1 = plotT, x2 = plotL, y2 = baseY,
        color = T.axis, width = 1 }
    stat[#stat + 1] = { type = "line", x1 = plotL, y1 = baseY, x2 = plotL + plotW, y2 = baseY,
        color = T.axis, width = 1 }

    local mx = W.i(plotL + plotW * (78 - 10) / 120)
    local mTop = W.i(baseY - plotH * 0.92)
    stat[#stat + 1] = { type = "line", x1 = mx, y1 = mTop - 5, x2 = mx, y2 = plotT + 2,
        color = T.axis, width = 1, dash_width = 2, dash_gap = 3 }

    -- 刻度文字（文本框留足，避免放大后被裁切或换行）
    W.label(parent, x + padL - 36, y + plotT - 3, 32, 14, "100", 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    W.label(parent, x + padL - 36, y + plotT + plotH / 2 - 7, 32, 14, "50", 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    W.label(parent, x + padL - 36, y + baseY - 11, 32, 14, "0", 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    for k = 0, 5 do
        local mz = 10 + 120 * k / 5
        -- 端点刻度标签夹在画布内，避免越界被相邻面板遮住
        local lx = x + plotL + plotW * k / 5 - 20
        if lx < x then lx = x end
        if lx > x + w - 44 then lx = x + w - 44 end
        W.label(parent, lx, y + baseY + 6, 40, 14,
            string.format("%d", math.floor(mz + 0.5)), 10, T.text_dim, airui.TEXT_ALIGN_CENTER)
    end
    W.label(parent, x + mx + 5, y + plotT - 2, 60, 14, "m/z 78", 10, T.cyan)

    local handle = { shape = shape }
    function handle.update(bars)
        local items = {}
        for i = 1, #stat do items[#items + 1] = stat[i] end
        -- 柱宽：目标「有效宽度(含 1px 描边)」约为格距的 0.8 倍
        local pitch = plotW / 120
        local bw = W.i(pitch * 0.8) - 2
        if bw < 1 then bw = 1 end
        for i = 1, #bars do
            local b = bars[i]
            local bh = W.i(b.v * plotH * 0.92)
            if bh >= 1 then
                local by = baseY - bh
                local bx = W.i(plotL + plotW * (b.mz - 10) / 120) - math.floor(bw / 2)
                local col, opa
                if b.v > 0.7 then
                    col, opa = T.cyan, 255
                elseif b.v > 0.3 then
                    col, opa = T.cyan, 205
                else
                    col, opa = T.blue, 150
                end
                items[#items + 1] = { type = "rect", x = bx, y = by, w = bw, h = bh,
                    color = col, width = 1, fill = true, fill_color = col, fill_opacity = opa }
            end
        end
        shape:set_items(items)
    end
    return handle
end

-- 浓度趋势图（多系列折线 + 面积），图例由调用方另行绘制
-- 返回 handle:update(trend)
function W.trend_chart(parent, x, y, w, h, T, series_names)
    local chart = airui.chart({
        parent = parent,
        x = o(x), y = o(y), w = o(w), h = o(h),
        type = "line",
        y_min = 0, y_max = 24,
        point_count = 60,
        update_mode = "shift",
        line_color = T.cyan, line_width = 2, point_radius = 0,
        bg_opa = 0, border_width = 0,
        hdiv = 4, vdiv = 4,
        grid_color = T.ring, grid_opa = 110,
        -- 不指定 color 时，每条曲线的填充色取该系列自身的线色
        fill = { enable = true, opa_start = 70, opa_end = 0 },
        -- 不设置 unit：AirUI 生成的轴单位标签会贴到父容器内容区边界，导致面板出现横向滚动条
        x_axis = { enable = true, min = -60, max = 0, ticks = 5 },
        y_axis = { enable = true, min = 0, max = 24, ticks = 5 },
    })
    local ids = { 1 }
    chart:set_series_name(1, series_names[1])
    chart:set_line_color(1, T.cyan)
    ids[2] = chart:add_series({ color = T.blue, name = series_names[2] })
    ids[3] = chart:add_series({ color = T.amber, name = series_names[3] })

    local dbg = (require "config").debug or {}
    local dbg_n = 0

    -- 范围自检：三条系列固定为 y_max / y_max/2 / y_min 三条水平线。
    -- 用于区分“数据太小”与“固件没应用 y_min/y_max”这两种都会造成曲线贴底的原因。
    local probe
    if dbg.chart_range_probe then
        probe = {}
        local vals = { 24, 12, 0 }
        for si = 1, 3 do
            local data = {}
            for i = 1, 60 do data[i] = vals[si] end
            probe[si] = { name = series_names[si], data = data }
        end
        log.info("trend_chart", "范围自检：曲线固定为 24/12/0",
            "若 24 未画在绘图区顶边，说明固件未应用 y_min/y_max")
    end

    local handle = { chart = chart }
    function handle.update(trend)
        if probe then trend = probe end
        for i = 1, #trend do
            if ids[i] then chart:set_values(ids[i], trend[i].data) end
        end

        -- 数据诊断：确认真正下发给 chart 的点数量级（应始终落在 2..19 整数区间）
        if dbg.trend_data_log then
            dbg_n = dbg_n + 1
            if dbg_n <= 3 or dbg_n % 20 == 0 then
                local parts = {}
                for i = 1, #trend do
                    local d = trend[i].data
                    local mn, mx
                    for k = 1, #d do
                        local v = d[k]
                        if mn == nil or v < mn then mn = v end
                        if mx == nil or v > mx then mx = v end
                    end
                    parts[#parts + 1] = string.format("%s len=%d min=%s max=%s 首=%s 末=%s",
                        series_names[i], #d, tostring(mn), tostring(mx),
                        tostring(d[1]), tostring(d[#d]))
                end
                log.info("trend_data", table.concat(parts, " | "))
            end
        end
    end
    return handle
end

return W
