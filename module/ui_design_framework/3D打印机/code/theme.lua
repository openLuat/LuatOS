--[[
@module theme
@summary 3D 打印机 HMI - 配色 / 主题切换 / 页面工厂 / 通用控件 / 全代码绘制图标
         与 code/preview.html（1024×600）1:1 对应，工程零 PNG 贴图

         实机踩坑（Air8603 + AirUI）：
         1. shape 的 arc / ellipse 图元在实机上不渲染（牛奶盒阴影、wifi 弧、马克杯把手
            全部丢失，只剩 line/circle/rect），所以本工程只用 line/circle/rect 三种图元，
            弧线一律用多段折线 ARC() 拼接。
         2. 所有坐标/半径必须取整，小数坐标会导致图元不显示。
         3. 实心图形用 width>=1 的 circle + fill，或 width 很大的 circle 模拟实心点。
]]

local sys   = require "sys"
local exwin = require "exwin"

local theme = {}

theme.W, theme.H = 1024, 600
pcall(function()
    local w, h = display.getSize()
    if w and h and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 主题配色：深色（默认）/ 浅色
-- C 是"当前生效"的调色板：切换时就地覆写字段（不换表），
-- 页面 rebuild 后所有控件自动跟随（各文件 local C = theme.C 拿的是同一张表）
--------------------------------------------------------------------
theme.cur = "dark"
theme.PALETTES = {
    dark = {
        bg       = 0x000000,  -- 整屏黑底
        card     = 0x1C1C1C,  -- 卡片/行底
        card2    = 0x242424,  -- 方向键底
        bar      = 0x333333,  -- 滑轨
        orange   = 0xF5A81E,  -- 主强调（按钮/选中条）
        yellow   = 0xF5C033,  -- 亮黄（暂停/进度条）
        gold     = 0xF5D02E,  -- 调平选中格
        text     = 0xFFFFFF,
        sub      = 0xBDBDBD,
        dim      = 0x9A9A9A,
        gray     = 0x6A6A6A,  -- 输入框描边 / 分隔
        cyan     = 0x58C8D8,
        cyan_lt  = 0x8FE3E6,  -- 首页"准备"卡底色（固定亮色，不随主题变）
        purple   = 0xB06BE0,
        green    = 0x9FD35A,
        lime     = 0xC8E02E,
        lime2    = 0xD7E84B,  -- 首页"设置"卡底色（固定亮色）
        olive    = 0x3D4A3C,  -- 调平完成提示条
        dlg      = 0x3C3C3C,  -- 对话框底
        input    = 0x111111,  -- 数字/文字输入框底（浅色主题要反转，否则黑底黑字看不见）
        slate    = 0x8E9EAE,  -- 调平格子
        preview  = 0xD7D7D7,  -- 模型预览底
        red      = 0xE5533D,
    },
    light = {
        bg       = 0xF4F5F7,
        card     = 0xFFFFFF,
        card2    = 0xE8EAED,
        bar      = 0xD5D8DC,
        orange   = 0xE08C0C,
        yellow   = 0xE8B01A,
        gold     = 0xD9AE0F,
        text     = 0x16181C,
        sub      = 0x4A4F57,
        dim      = 0x6E747C,
        gray     = 0xB4B8BE,
        cyan     = 0x15879A,
        cyan_lt  = 0x8FE3E6,  -- 保持亮色（卡片底）
        purple   = 0x7B3FB5,
        green    = 0x3E8A26,
        lime     = 0x6C8A0C,
        lime2    = 0xD7E84B,  -- 保持亮色（卡片底）
        olive    = 0xDCE8DA,
        dlg      = 0xFFFFFF,
        input    = 0xFFFFFF,
        slate    = 0xA7B4C2,
        preview  = 0xDCDEE2,
        red      = 0xC3352A,
    },
}
theme.C = {}
for k, v in pairs(theme.PALETTES.dark) do theme.C[k] = v end

-- 切换主题（就地覆写 C），返回新的主题名
function theme.toggle_theme()
    theme.cur = (theme.cur == "dark") and "light" or "dark"
    for k, v in pairs(theme.PALETTES[theme.cur]) do theme.C[k] = v end
    log.info("theme", "switch to " .. theme.cur)
    return theme.cur
end

function theme.set_theme(name)
    if not theme.PALETTES[name] then return end
    theme.cur = name
    for k, v in pairs(theme.PALETTES[name]) do theme.C[k] = v end
end

local C = theme.C

theme.TOP_H = 62

--------------------------------------------------------------------
-- 基础控件封装
--------------------------------------------------------------------
function theme.box(parent, x, y, w, h, color, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0 })
end

function theme.box_b(parent, x, y, w, h, color, radius, bcol, bw)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0,
        border_color = bcol or C.gray, border_width = bw or 2 })
end

function theme.txt(parent, x, y, w, h, text, color, size, align)
    return airui.label({ parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", color = color or C.text,
        font_size = size or 22, align = align })
end

-- 实心/描边按钮（pad=0 保证文字居中不撑开）
function theme.btn(parent, x, y, w, h, text, bg, fg, bcol, bw, radius, on_click)
    return airui.button({ parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = 22,
        style = {
            bg_color     = bg or C.card,
            text_color   = fg or C.text,
            border_color = bcol or bg or C.card,
            border_width = bw or 0,
            radius       = radius or 0,
            pad          = 0,
        },
        on_click = on_click })
end

-- 无框文字（面包屑）：纯 label，可点击但没有任何背景/边框
function theme.link(parent, x, y, w, h, text, color, size, on_click)
    local l = airui.label({ parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", color = color or C.text, font_size = size or 22 })
    if on_click and l.set_on_click then l:set_on_click(on_click) end
    return l
end

-- 透明点击热区：盖在图标/文字/卡片上面接收触摸（不遮挡画面）
function theme.hit(parent, x, y, w, h, on_click)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.bg, radius = 0 })
    pcall(o.set_color, o, C.bg, 0)
    if on_click then
        if o.set_on_click then o:set_on_click(on_click) end
    end
    return o
end

-- 可点击卡片容器（先建卡再往卡里放内容；子 label/shape 会拦触摸，
-- 所以画完内容后要在卡片上压一层 theme.hit 透明热区，否则会出现"要点两下"）
function theme.card(parent, x, y, w, h, color, radius, on_click)
    local c = theme.box(parent, x, y, w, h, color, radius)
    if on_click and c.set_on_click then c:set_on_click(on_click) end
    return c
end

-- 滑块（airui.slider 封装：深色轨道 + 橙色进度 + 黄色旋钮）
function theme.slider(parent, x, y, w, h, min, max, val, on_change)
    local r = math.floor((h or 24) / 2)
    return airui.slider({
        parent = parent, x = x, y = y, w = w, h = h or 24,
        min = min or 0, max = max or 100, value = val or 0,
        style = {
            bg_color = C.bar, bg_opa = 255,
            radius = r, pad = 0, border_width = 0,
            indicator_color = C.orange, indicator_opa = 255,
            knob_color = C.yellow, knob_opa = 255,
            knob_border_color = C.yellow, knob_border_width = 0,
        },
        on_change = on_change,
    })
end

--------------------------------------------------------------------
-- 页面工厂（单页 exwin，页面内部自行切屏）
-- build_fn 返回 update, interval(ms) 时按 interval 起刷新定时器
--------------------------------------------------------------------
local registry, current_win = {}, nil

function theme.register(idx, mod) registry[idx] = mod end

sys.subscribe("SWITCH_PAGE", function(idx)
    local mod = registry[idx]
    if not mod then return end
    if current_win then
        local w = current_win
        current_win = nil
        pcall(exwin.close, w)
    end
    current_win = mod.open()
end)

function theme.open_page(idx) sys.publish("SWITCH_PAGE", idx) end

function theme.make_page(idx, title, build_fn)
    local M = { idx = idx, title = title }
    local root, timer_id

    local function create_ui()
        root = airui.container({ parent = airui.screen, x = 0, y = 0,
            w = theme.W, h = theme.H, color = C.bg })
        local update, interval = build_fn(root)
        if update then
            timer_id = sys.timerLoopStart(update, interval or 1000)
        end
        if exwin.bind_root then pcall(exwin.bind_root, root) end
    end

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
-- 图标：全部 shape 线/圆/矩形绘制（零贴图）
-- 坐标按 100×100 设计稿，按 s 缩放；圆心/端点一律取整
-- 只用 line / circle / rect；弧形用多段折线 ARC 近似（arc 图元实机不渲染）
--------------------------------------------------------------------
local function add_line(items, x1, y1, x2, y2, col, w)
    items[#items + 1] = { type = "line",
        x1 = math.floor(x1 + 0.5), y1 = math.floor(y1 + 0.5),
        x2 = math.floor(x2 + 0.5), y2 = math.floor(y2 + 0.5),
        color = col, width = math.max(1, math.floor(w + 0.5)) }
end

local function add_circle(items, cx, cy, r, col, w, fill)
    items[#items + 1] = { type = "circle",
        cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5),
        r = math.max(1, math.floor(r + 0.5)),
        color = col, width = math.max(1, math.floor((w or 1) + 0.5)),
        fill = fill and true or false,
        fill_color = fill and col or nil,
        fill_opacity = fill and 255 or nil }
end

local function add_rect(items, x, y, w, h, col, r, lw, fill)
    items[#items + 1] = { type = "rect",
        x = math.floor(x + 0.5), y = math.floor(y + 0.5),
        w = math.max(1, math.floor(w + 0.5)), h = math.max(1, math.floor(h + 0.5)),
        radius = math.floor((r or 0) + 0.5),
        color = col, width = math.max(1, math.floor((lw or 1) + 0.5)),
        fill = fill and true or false,
        fill_color = fill and col or nil,
        fill_opacity = fill and 255 or nil }
end

-- kind: home homepos wifi gear printer sliders move nozzle fan water bulb bell
--       sun moon speed reboot pid info check lock
--       arrow_up/down/left/right back
function theme.icon(parent, x, y, s, kind, col, col2)
    col  = col or C.text
    col2 = col2 or col
    local k  = s / 100
    -- lw 必须用"100 网格单位"表示：L/O/R 内部都会再乘 k，
    -- 若直接放像素值会被缩掉一次（34px 图标只剩 1px 线，实机看就是"细线房子"）
    local lw = math.max(2, s / 12) / k
    local it = {}
    local function L(x1, y1, x2, y2, c, w) add_line(it, x1 * k, y1 * k, x2 * k, y2 * k, c or col, (w or lw) * k) end
    local function O(cx, cy, r, c, w) add_circle(it, cx * k, cy * k, r * k, c or col, (w or lw) * k, false) end
    local function F(cx, cy, r, c) add_circle(it, cx * k, cy * k, r * k, c or col, 1, true) end
    local function R(rx, ry, rw, rh, c, rr, w, fill)
        add_rect(it, rx * k, ry * k, rw * k, rh * k, c or col, (rr or 0) * k, (w or lw) * k, fill)
    end
    -- 圆弧折线（角度制，0=右，90=下；n 段直线近似）
    local function ARC(cx, cy, r, a0, a1, c, w)
        local n = math.max(3, math.floor(math.abs(a1 - a0) / 9 + 0.5))
        local px, py
        for i = 0, n do
            local a = math.rad(a0 + (a1 - a0) * i / n)
            local x, y = cx + r * math.cos(a), cy + r * math.sin(a)
            if i > 0 then L(px, py, x, y, c, w) end
            px, py = x, y
        end
    end

    if kind == "home" then
        -- 与 html 的 path "M16 4 L28 15 H24 V27 H19 V19 H13 V27 H8 V15 H4 Z" 一一对应
        -- 特征：屋顶两端有屋檐伸出、底部中间留门洞（之前画成了没有门洞的细线方房子）
        local w = 7.5                      -- 设计稿 stroke-width 2.4 / 32 × 100
        L(50, 13, 88, 47, col, w)          -- 顶点 → 右屋檐外沿
        L(88, 47, 75, 47, col, w)          -- 右屋檐
        L(75, 47, 75, 84, col, w)          -- 右墙
        L(75, 84, 59, 84, col, w)          -- 底边右段
        L(59, 84, 59, 59, col, w)          -- 门洞右
        L(59, 59, 41, 59, col, w)          -- 门洞顶
        L(41, 59, 41, 84, col, w)          -- 门洞左
        L(41, 84, 25, 84, col, w)          -- 底边左段
        L(25, 84, 25, 47, col, w)          -- 左墙
        L(25, 47, 13, 47, col, w)          -- 左屋檐
        L(13, 47, 50, 13, col, w)          -- 左屋檐外沿 → 顶点
    elseif kind == "homepos" then
        -- 对应移动轴原位键：path "M15 4 L26 13 H22 V23 H8 V13 H4 Z"（无门洞）
        local w = 7.3
        L(50, 15, 87, 50, col, w)
        L(87, 50, 73, 50, col, w)
        L(73, 50, 73, 88, col, w)
        L(73, 88, 27, 88, col, w)
        L(27, 88, 27, 50, col, w)
        L(27, 50, 13, 50, col, w)
        L(13, 50, 50, 15, col, w)
    elseif kind == "wifi" then
        -- 视觉重心收在 (50,51)，避免与旁边图标/文字错位
        F(50, 76, 5)                                -- 底部圆点
        ARC(50, 70, 16, 208, 332)                   -- 内弧
        ARC(50, 70, 30, 208, 332)                   -- 中弧
        ARC(50, 70, 44, 208, 332)                   -- 外弧
    elseif kind == "gear" then
        O(50, 50, 26)
        O(50, 50, 11)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            L(50 + 28 * math.cos(a), 50 + 28 * math.sin(a),
              50 + 38 * math.cos(a), 50 + 38 * math.sin(a))
        end
    elseif kind == "printer" then
        R(22, 12, 56, 38, col, 6)
        R(30, 22, 40, 18, col, 2, lw, true)
        R(12, 56, 76, 30, col, 6)
        F(34, 50, 4); F(50, 50, 4); F(66, 50, 4)
    elseif kind == "sliders" then
        L(12, 16, 74, 16); O(32, 16, 13)
        L(26, 50, 88, 50); O(62, 50, 13)
        L(12, 84, 74, 84); O(32, 84, 13)
    elseif kind == "move" then
        L(50, 10, 50, 90); L(10, 50, 90, 50)
        L(50, 10, 38, 24); L(50, 10, 62, 24)
        L(50, 90, 38, 76); L(50, 90, 62, 76)
        L(10, 50, 24, 38); L(10, 50, 24, 62)
        L(90, 50, 76, 38); L(90, 50, 76, 62)
    elseif kind == "nozzle" then
        L(34, 12, 66, 12); L(34, 12, 40, 44); L(66, 12, 60, 44)
        L(40, 44, 60, 44)
        L(48, 44, 48, 64); L(52, 44, 52, 64)
        L(30, 64, 70, 64)
    elseif kind == "fan" then
        O(50, 50, 12)
        ARC(50, 50, 34, 20, 100)
        ARC(50, 50, 34, 140, 220)
        ARC(50, 50, 34, 260, 340)
    elseif kind == "water" then
        L(50, 12, 76, 52); L(76, 52, 50, 84); L(50, 84, 24, 52); L(24, 52, 50, 12)
        L(38, 58, 50, 70); L(50, 70, 62, 58)
    elseif kind == "bulb" then
        ARC(50, 40, 22, 150, 390)
        L(38, 62, 38, 68); L(62, 62, 62, 68)
        L(38, 68, 62, 68)
        L(42, 78, 58, 78); L(46, 88, 54, 88)
        L(50, 4, 50, 10); L(16, 40, 24, 40); L(76, 40, 84, 40)
    elseif kind == "bell" then
        ARC(50, 52, 26, 180, 360)
        L(24, 52, 24, 74); L(76, 52, 76, 74)
        L(16, 74, 84, 74)
        ARC(50, 74, 9, 0, 180)
    elseif kind == "sun" then
        F(50, 50, 20, col)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            L(50 + 28 * math.cos(a), 50 + 28 * math.sin(a),
              50 + 40 * math.cos(a), 50 + 40 * math.sin(a))
        end
    elseif kind == "moon" then
        F(48, 50, 30, col)
        F(62, 41, 27, col2)                     -- 用底色盖出月牙（重心对到 50,51）
    elseif kind == "speed" then
        O(50, 50, 34)
        L(50, 50, 50, 24)
        L(50, 50, 68, 62)
    elseif kind == "reboot" then
        ARC(50, 50, 30, 40, 340)
        L(72, 26, 84, 40); L(84, 40, 66, 44)
    elseif kind == "pid" then
        O(50, 50, 34)
        R(36, 48, 7, 16, col, 0, 1, true)
        R(47, 38, 7, 26, col, 0, 1, true)
        R(58, 44, 7, 20, col, 0, 1, true)
    elseif kind == "info" then
        O(50, 50, 34)
        R(47, 30, 6, 8, col, 3, 0, true)
        R(47, 44, 6, 26, col, 3, 0, true)
    elseif kind == "check" then
        O(50, 50, 40, col, lw * 1.2)
        L(30, 52, 44, 66, col, lw * 1.2)
        L(44, 66, 72, 34, col, lw * 1.2)
    elseif kind == "lock" then
        R(20, 40, 60, 40, col, 6)
        ARC(50, 40, 16, 180, 360)
    elseif kind == "close" then
        L(30, 30, 70, 70)
        L(70, 30, 30, 70)
    elseif kind == "arrow_up" then
        L(50, 80, 50, 24); L(50, 24, 30, 46); L(50, 24, 70, 46)
    elseif kind == "arrow_down" then
        L(50, 20, 50, 76); L(50, 76, 30, 54); L(50, 76, 70, 54)
    elseif kind == "arrow_left" then
        L(24, 50, 78, 50); L(24, 50, 44, 30); L(24, 50, 44, 70)
    elseif kind == "arrow_right" then
        L(22, 50, 76, 50); L(76, 50, 56, 30); L(76, 50, 56, 70)
    elseif kind == "back" then
        L(70, 24, 34, 50); L(34, 50, 70, 76)
    end

    if #it == 0 then return nil end
    return airui.shape({ parent = parent, x = x, y = y,
        w = math.floor(s), h = math.floor(s), items = it })
end

return theme
