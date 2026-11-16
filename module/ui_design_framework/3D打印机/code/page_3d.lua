--[[
@module page_3d
@summary 3D 打印机 HMI 主页面（与 code/preview.html 1:1 对应）
         单 exwin 页 + 内部切屏：首页 / 打印(文件列表·打印中) / 准备(移动轴·进退料)
         / 设置(配置·系统设置·关于·调平) / WiFi / 软键盘，全局数字键盘与对话框浮层
]]

local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

local C  = theme.C
local W, H = theme.W, theme.H

-- 前向声明（避免全局变量互相引用）
local rebuild, nav, build_screen
local start_print, stop_print, update_prog

--------------------------------------------------------------------
-- 全局状态（对应 preview.html 里的 S 对象）
--------------------------------------------------------------------
local S = {
    screen = "home",
    page = 1, sel = 2,                       -- 文件列表页/选中项
    unit = 0.1,                              -- 移动轴步进
    pos = { x = 49.4, y = 49.8, z = 49.6 },
    prog = 0, printing = false,             -- 打印进度
    wifiName = "LEVETOP", wifiPass = "12345PUD",
    plaTemp = 180, absTemp = 180,
    light = false, sound = false,
    bri = 60, spd = 100,
    fan = false, cool = true,
    lvNext = 1,                              -- 调平：当前该点的序号
    feedIn = 85.0, feedOut = 95.0,
    nozzle = 33,
    kbTarget = "name", kbText = "", caps = false,
    aboutSel = 2,
}

local root, body, overlay
local refs = {}                              -- 需要原地更新的控件

local function defer(fn) sys.timerStart(fn, 30) end

--------------------------------------------------------------------
-- 顶栏：home + 面包屑 + WiFi
--------------------------------------------------------------------
local function topbar(crumbs)
    -- 全部无框：图形/文字直接画在 body 上，热区最后压上去（透明 container）
    -- 这样既没有按钮底色/边框，又能正常点击（对应 html 的 span.link）
    -- 22 号文字可见中心 ≈ y+14 = 30；房子图形重心在 100 网格的 48.5
    -- → 图标 y = 30 - 34*0.485 ≈ 14（与 html 的 .home top:14px 一致）
    theme.icon(body, 24, 14, 34, "home", C.orange)
    theme.hit(body, 18, 8, 48, 48, function() defer(function() nav("home") end) end)

    local x = 72
    for i, it in ipairs(crumbs) do
        local txt, target = it[1], it[2]
        -- 中文是 3 字节/字，按 #txt 直接算会多出一倍空白，把 ">" 推得很远
        local n = math.max(1, math.floor((#txt + 2) / 3))
        local w = n * 22 + 2
        if target then
            theme.link(body, x, 16, w, 32, txt, C.text, 22,
                function() defer(function() nav(target) end) end)
        else
            theme.txt(body, x, 16, w, 32, txt, C.text, 22)
        end
        x = x + w
        if i < #crumbs then
            theme.txt(body, x + 6, 16, 20, 32, ">", 0x8A8A8A, 22)
            x = x + 32
        end
    end

    -- 主题切换（深色显示太阳 / 浅色显示月亮）；重心 50 → y = 30 - 32*0.5 = 14
    theme.icon(body, W - 104, 14, 32, (theme.cur == "dark") and "sun" or "moon",
        C.text, C.bg)
    theme.hit(body, W - 110, 8, 44, 46, function()
        theme.toggle_theme()
        defer(rebuild)
    end)

    -- WiFi
    theme.icon(body, W - 58, 14, 32, "wifi", C.text)
    theme.hit(body, W - 64, 8, 44, 46, function() defer(function() nav("wifi") end) end)
end

--------------------------------------------------------------------
-- 模型预览图（与 HTML 里的 SVG 对应，纯 shape 绘制）
--------------------------------------------------------------------
local MODEL_PAL = {
    milk   = 0xF2F5F8, bunny = 0xF6F6F3, mug = 0xE9EEF2, sun = 0xF7C531,
    house  = 0xF0A3B8, cake = 0x5A3626, gear = 0xC9CED4, vase = 0x8FD0C9,
    duck   = 0xF7D64A, bear = 0xC48A5F, rocket = 0xE8EDF2, pen = 0x9FB8D8,
    cat    = 0xE6E6E6, planet = 0xB06BE0, cookie = 0xD9A25F,
}

local function draw_model(parent, x, y, s, kind)
    local it = {}
    local k = s / 100
    local function R(rx, ry, rw, rh, col, rr, fill, lw)
        it[#it + 1] = { type = "rect",
            x = math.floor(rx * k), y = math.floor(ry * k),
            w = math.floor(rw * k), h = math.floor(rh * k),
            radius = math.floor((rr or 0) * k),
            color = col, width = math.max(1, math.floor((lw or 1) * k)),
            fill = fill ~= false, fill_color = col, fill_opacity = 255 }
    end
    local function Ci(cx, cy, r, col, fill, lw)
        it[#it + 1] = { type = "circle",
            cx = math.floor(cx * k), cy = math.floor(cy * k),
            r = math.floor(r * k), color = col,
            width = math.max(1, math.floor((lw or 1) * k)),
            fill = fill ~= false, fill_color = col, fill_opacity = 255 }
    end
    local function L(x1, y1, x2, y2, col, w)
        it[#it + 1] = { type = "line",
            x1 = math.floor(x1 * k), y1 = math.floor(y1 * k),
            x2 = math.floor(x2 * k), y2 = math.floor(y2 * k),
            color = col, width = math.max(1, math.floor((w or 2) * k)) }
    end
    -- 辅助：椭圆环折线（ellipse 图元实机不渲染，一律折线近似）
    local function ELL(cx, cy, rx, ry, col, w)
        local n = 24
        local px, py
        for i = 0, n do
            local a = math.rad(360 * i / n)
            local xx, yy = cx + rx * math.cos(a), cy + ry * math.sin(a)
            if i > 0 then L(px, py, xx, yy, col, w) end
            px, py = xx, yy
        end
    end
    -- 辅助：圆弧折线（0=右 90=下）
    local function ARC(cx, cy, r, a0, a1, col, w)
        local n = math.max(3, math.floor(math.abs(a1 - a0) / 10 + 0.5))
        local px, py
        for i = 0, n do
            local a = math.rad(a0 + (a1 - a0) * i / n)
            local xx, yy = cx + r * math.cos(a), cy + r * math.sin(a)
            if i > 0 then L(px, py, xx, yy, col, w) end
            px, py = xx, yy
        end
    end
    local col = MODEL_PAL[kind] or 0xE0E0E0

    -- 影子（所有模型通用，扁圆角矩形代替 ellipse → 实机可见）
    R(24, 84, 52, 9, 0xB9B9B9, 5, true)

    if kind == "bunny" then
        R(24, 44, 52, 40, col, 10, true)
        R(30, 22, 12, 24, col, 5, true)
        R(58, 22, 12, 24, col, 5, true)
        Ci(40, 62, 3, 0x222222, true)
        Ci(60, 62, 3, 0x222222, true)
    elseif kind == "sun" or kind == "cookie" then
        Ci(50, 54, 26, col, true)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            L(50 + 28 * math.cos(a), 54 + 28 * math.sin(a),
              50 + 40 * math.cos(a), 54 + 40 * math.sin(a), col, 4)
        end
        Ci(42, 50, 3, 0x222222, true)
        Ci(58, 50, 3, 0x222222, true)
    elseif kind == "milk" then
        R(32, 30, 36, 56, col, 2, true)
        R(32, 46, 36, 14, 0x7FB2D8, 0, true)
        L(32, 30, 42, 18, 0xDFE8F0, 3); L(68, 30, 78, 18, 0xDFE8F0, 3)
        L(42, 18, 78, 18, 0xDFE8F0, 3)
    elseif kind == "mug" then
        Ci(48, 72, 20, col, true)                    -- 杯身下半圆
        R(28, 30, 40, 42, col, 2, true)              -- 杯身
        R(28, 28, 40, 9, 0xCFD8E0, 4, true)          -- 杯口
        ARC(70, 50, 14, -90, 90, col, 7)             -- 把手（折线弧）
    elseif kind == "house" then
        R(22, 48, 56, 36, col, 2, true)
        L(14, 50, 50, 18, 0xE07A97, 6); L(50, 18, 86, 50, 0xE07A97, 6)
        R(42, 60, 16, 24, 0xFFF2F5, 0, true)
    elseif kind == "cake" then
        R(24, 52, 52, 34, col, 6, true)
        R(24, 42, 52, 12, 0x7B4A33, 6, true)
        Ci(50, 33, 8, 0xD63B3B, true)
    elseif kind == "gear" then
        Ci(50, 52, 20, col, true)
        Ci(50, 52, 8, 0xFFFFFF, true)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            L(50 + 20 * math.cos(a), 52 + 20 * math.sin(a),
              50 + 32 * math.cos(a), 52 + 32 * math.sin(a), col, 6)
        end
    elseif kind == "vase" then
        Ci(50, 62, 20, col, true)                    -- 瓶身（圆代替椭圆）
        R(38, 24, 24, 22, col, 8, true)              -- 瓶颈
    elseif kind == "duck" then
        R(22, 50, 56, 32, col, 15, true)             -- 身体
        Ci(64, 33, 14, col, true)                    -- 头
        Ci(68, 29, 3, 0x222222, true)
        L(78, 33, 92, 38, 0xF08A2C, 5); L(92, 38, 78, 43, 0xF08A2C, 5)
    elseif kind == "bear" then
        Ci(32, 32, 10, col, true); Ci(68, 32, 10, col, true)
        Ci(50, 54, 26, col, true)
        Ci(41, 50, 3, 0x222222, true); Ci(59, 50, 3, 0x222222, true)
        Ci(50, 60, 6, 0xF0DCC8, true)
    elseif kind == "rocket" then
        R(42, 16, 16, 46, col, 8, true)
        Ci(50, 40, 7, 0x58C8D8, true)
        L(42, 56, 32, 74, 0xF5A81E, 6); L(58, 56, 68, 74, 0xF5A81E, 6)
        L(44, 62, 56, 62, 0xF5A81E, 4)
    elseif kind == "pen" then
        R(32, 30, 36, 52, col, 2, true)
        R(44, 12, 5, 18, 0xF5C033, 2, true)
        R(54, 18, 5, 12, 0xE5533D, 2, true)
    elseif kind == "cat" then
        Ci(50, 54, 26, col, true)
        L(30, 32, 34, 50, col, 5); L(70, 32, 66, 50, col, 5)
        Ci(41, 52, 3, 0x222222, true); Ci(59, 52, 3, 0x222222, true)
    elseif kind == "planet" then
        Ci(50, 52, 24, col, true)
        ELL(50, 54, 40, 10, 0xF5C033, 5)             -- 光环（折线椭圆）
    else
        R(30, 34, 40, 46, col, 6, true)
    end

    return airui.shape({ parent = parent, x = x, y = y,
        w = math.floor(s), h = math.floor(s), items = it })
end

--------------------------------------------------------------------
-- 重建当前屏（对应 preview.html 的 go()）
--------------------------------------------------------------------
build_screen = {}

function nav(name)
    S.screen = name
    if name == "level" then
        S.lvNext = 1                     -- 每次进入调平重置
    end
    defer(rebuild)
end

local function clear_overlay()
    if overlay then pcall(overlay.destroy, overlay) overlay = nil end
end

--------------------------------------------------------------------
-- 弹窗（是/否 或 单个确定）
--------------------------------------------------------------------
local function dialog(title, yes_text, on_yes, no_text, on_no, icon, wide)
    clear_overlay()
    overlay = theme.box(root, 0, 0, W, H, C.bg, 0)
    overlay:set_color(0x000000, 160)
    local dw = wide or 600
    -- 标题按 \n 拆成多行（单个 label 只显示一行，多行文案会被裁掉）
    local lines = {}
    for s in string.gmatch(tostring(title), "[^\r\n]+") do lines[#lines + 1] = s end
    if #lines == 0 then lines[1] = "" end
    local lh = 44
    local nh = #lines * lh
    local bh = 66
    local dh = 34 + nh + 34 + bh + 26
    local dx = math.floor((W - dw) / 2)
    local dy = math.floor((H - dh) / 2)
    local d = theme.box(overlay, dx, dy, dw, dh, C.dlg, 8)

    if icon then
        theme.icon(d, 30, math.floor((nh - 60) / 2) + 34, 60, icon, C.yellow)
        for i, s in ipairs(lines) do
            theme.txt(d, 104, 34 + (i - 1) * lh, dw - 130, lh, s, C.text, 30)
        end
    else
        for i, s in ipairs(lines) do
            theme.txt(d, 20, 34 + (i - 1) * lh, dw - 40, lh, s, C.text, 30,
                airui.TEXT_ALIGN_CENTER)
        end
    end

    local by = 34 + nh + 34
    if no_text then
        local gap = 60
        local total = 200 * 2 + gap
        local bx = math.floor((dw - total) / 2)
        theme.btn(d, bx, by, 200, bh, yes_text or "是",
            C.yellow, 0x000000, C.yellow, 0, 6, function()
                clear_overlay()
                if on_yes then on_yes() end
            end)
        theme.btn(d, bx + 200 + gap, by, 200, bh, no_text or "否",
            C.dlg, C.orange, C.orange, 2, 6, function()
                clear_overlay()
                if on_no then on_no() end
            end)
    else
        theme.btn(d, math.floor((dw - 200) / 2), by, 200, bh, yes_text or "确定",
            C.yellow, 0x000000, C.yellow, 0, 6, function()
                clear_overlay()
                if on_yes then on_yes() end
            end)
    end
    -- 遮罩本身可点（点空白处不误触下层）
    if overlay.set_on_click then overlay:set_on_click(function() end) end
    return d
end

--------------------------------------------------------------------
-- 带滑块的弹窗（亮度 / 打印速度，对应 html 的 .dlg .sl）
--------------------------------------------------------------------
local function dialog_slider(title, minv, maxv, val, suffix, on_change, on_ok)
    clear_overlay()
    overlay = theme.box(root, 0, 0, W, H, C.bg, 0)
    overlay:set_color(0x000000, 160)
    local dw, dh = 640, 320
    local dx = math.floor((W - dw) / 2)
    local dy = math.floor((H - dh) / 2)
    local d = theme.box(overlay, dx, dy, dw, dh, C.dlg, 8)

    theme.txt(d, 0, 28, dw, 44, title, C.text, 26, airui.TEXT_ALIGN_CENTER)
    local vlab                      -- 需先声明，滑块回调里当 upvalue 用
    theme.slider(d, 40, 112, dw - 80, 30, minv, maxv, val, function(self)
        local v = self:get_value()
        pcall(vlab.set_text, vlab, v .. (suffix or ""))
        if on_change then on_change(v) end
    end)
    -- 读数放在滑块下方、按钮上方（原来和"确定"重叠，102% 被挡住）
    vlab = theme.txt(d, 0, 158, dw, 36, tostring(val) .. (suffix or ""),
        C.text, 22, airui.TEXT_ALIGN_CENTER)
    theme.btn(d, math.floor((dw - 200) / 2), 210, 200, 66, "确定",
        C.yellow, 0x000000, C.yellow, 0, 6, function()
            clear_overlay()
            if on_ok then on_ok() end
        end)
    if overlay.set_on_click then overlay:set_on_click(function() end) end
    return d
end

--------------------------------------------------------------------
-- 全局数字键盘（进料/出料/PLA/ABS 共用）
--------------------------------------------------------------------
local np_buf = ""
local np_target = nil

local function np_redraw()
    -- 显示区是 label（container 没有 set_text）
    if refs.nplabel then pcall(refs.nplabel.set_text, refs.nplabel, np_buf) end
end

local function close_np()
    clear_overlay()
    np_buf = ""
end

local function open_np(target)
    -- 与 html 一致：打开时显示区为空，用户从头输入（也避免 95.000000 这类浮点串）
    np_target = target
    np_buf = ""
    clear_overlay()
    overlay = theme.box(root, 0, 0, W, H, C.bg, 0)
    overlay:set_color(0x000000, 120)

    local pw, ph = 520, 340
    local px, py = math.floor((W - pw) / 2), math.floor((H - ph) / 2)
    local p = theme.box(overlay, px, py, pw, ph, C.dlg, 8)

    -- 显示区底色跟随主题（之前固定 0x111111，浅色主题下 C.text 变成黑字 → 看不见输入）
    local disp = theme.box(p, 16, 16, pw - 128, 58, C.input, 6)
    refs.nplabel = theme.txt(disp, 12, 10, pw - 160, 40, np_buf, C.text, 28)

    theme.btn(p, pw - 108, 16, 92, 58, "X", C.orange, 0x000000, C.orange, 0, 6, close_np)
    theme.btn(p, pw - 108, 82, 92, 58, "Del", C.orange, 0x000000, C.orange, 0, 6, function()
        np_buf = string.sub(np_buf, 1, math.max(0, #np_buf - 1)); np_redraw()
    end)
    theme.btn(p, pw - 108, 148, 92, 58, "确定", C.orange, 0x000000, C.orange, 0, 6, function()
        local v = tonumber(np_buf)
        if v then
            if np_target == "in"  then S.feedIn = v end
            if np_target == "out" then S.feedOut = v end
            if np_target == "pla" then S.plaTemp = math.floor(v + 0.5) end
            if np_target == "abs" then S.absTemp = math.floor(v + 0.5) end
            if np_target == "bri" then S.bri = math.min(100, math.max(0, math.floor(v))) end
            if np_target == "spd" then S.spd = math.min(200, math.max(0, math.floor(v))) end
            if np_target == "nozzle" then S.nozzle = math.floor(v + 0.5) end
        end
        close_np()
        defer(rebuild)
    end)

    local keys = { "1", "2", "3", "-", "4", "5", "6", ".", "7", "8", "9", "0" }
    for i, k in ipairs(keys) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        theme.btn(p, 16 + col * 92, 82 + row * 66, 86, 58, k,
            C.orange, 0x000000, C.orange, 0, 6, function()
                if #np_buf < 8 then np_buf = np_buf .. k; np_redraw() end
            end)
    end
end

--------------------------------------------------------------------
-- 软键盘（WiFi 名称/密码）
--------------------------------------------------------------------
local KB_ROWS = {
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "Q", "W", "E", "U", "R", "T", "Y", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    { "Z", "X", "C", "V", "B", "N", "M" },
    { ".", "-", "=", "/", " ", "[", "]" },
}

local function kbd_redraw()
    if refs.kbdtext then
        pcall(refs.kbdtext.set_text, refs.kbdtext, S.kbText)
    end
end

local function kbd_key(ch)
    local c = ch
    if S.caps and ch:match("%a") then c = string.upper(ch) end
    S.kbText = S.kbText .. c
    if #S.kbText > 24 then S.kbText = string.sub(S.kbText, 1, 24) end
    kbd_redraw()
end

local function kbd_save()
    if S.kbTarget == "name" then S.wifiName = S.kbText else S.wifiPass = S.kbText end
    defer(function() nav("wifi") end)
end

--------------------------------------------------------------------
-- 各屏构建
--------------------------------------------------------------------
-- 设置页左侧竖排菜单（纯文字 + 选中左竖条，无按钮边框）
local MENU = { { "配置", "set" }, { "系统设置", "sys" }, { "关于", "about" } }
local function side_menu(cur)
    for i, m in ipairs(MENU) do
        local y = 84 + (i - 1) * 78
        local on = (m[2] == cur)
        if on then theme.box(body, 26, y + 12, 4, 54, C.orange, 2) end
        theme.txt(body, 48, y + 22, 150, 36, m[1], on and C.orange or C.sub, 26)
        if not on then
            theme.hit(body, 26, y, 170, 78, function()
                defer(function() nav(m[2]) end)
            end)
        end
    end
end

-- 1 首页
build_screen.home = function()
    topbar({})                        -- 首页无面包屑，只有 home + wifi
    local cw, ch = 214, 262
    local gap = 46
    local x = math.floor((W - (cw * 3 + gap * 2)) / 2)
    local y = theme.TOP_H + math.floor((538 - ch) / 2)

    local cards = {
        { bg = C.orange,  icon = "printer", text = "打印", target = "files" },
        { bg = C.cyan_lt, icon = "sliders", text = "准备", target = "prep"  },
        { bg = C.lime2,   icon = "gear",    text = "设置", target = "set"   },
    }
    for i, c in ipairs(cards) do
        local bx = x + (i - 1) * (cw + gap)
        local card = theme.card(body, bx, y, cw, ch, c.bg, 10)
        theme.icon(card, 59, 46, 96, c.icon, 0x000000)
        theme.txt(card, 0, 168, cw, 40, c.text, 0x000000, 30, airui.TEXT_ALIGN_CENTER)
        theme.hit(card, 0, 0, cw, ch, function() defer(function() nav(c.target) end) end)
    end
end

-- 2 打印：文件列表
build_screen.files = function()
    topbar({ { "首页", "home" }, { "打印" } })

    local list = mock.FILES[S.page]
    -- 列表外框：把整列文件名都包起来（左右各留 10，上留 10，下留 10）
    theme.box_b(body, 30, 68, 520, #list * 58 + 14, C.bg, 8, C.gray, 2)
    for i = 1, #list do
        local f = list[i]
        local y = 78 + (i - 1) * 58
        local on = (i == S.sel)
        -- 行底用 shape 画圆角卡片（对齐参考稿的卡片风格：纯圆角块、无描边）。
        -- 不用 container 装文字：容器内容判定溢出会画出滚动条，实机表现为行底一条灰线。
        local col = on and C.orange or C.card
        airui.shape({ parent = body, x = 40, y = y, w = 500, h = 52, items = {
            { type = "rect", x = 0, y = 0, w = 500, h = 52, radius = 10,
              color = col, width = 1, fill = true, fill_color = col, fill_opacity = 255 },
        } })
        theme.txt(body, 56, y + 13, 460, 30, f.name .. ".obj",
            on and 0x000000 or C.text, 22)
        theme.hit(body, 40, y, 500, 52, function() S.sel = i defer(rebuild) end)
    end

    -- 分页（纯文字，无框，热区扩大）：紧贴列表外框下方，不再钉在屏幕底部
    local px = 60
    local py = 68 + (#list * 58 + 14) + 26
    local function pbtn(text, fn)
        theme.txt(body, px, py + 6, 44, 34, text, C.text, 24)
        theme.hit(body, px, py, 44, 44, fn)
        px = px + 50
    end
    pbtn("|<", function() S.page = 1 S.sel = 1 defer(rebuild) end)
    pbtn("<",  function() if S.page > 1 then S.page = S.page - 1 S.sel = 1 defer(rebuild) end end)
    theme.txt(body, px - 6, py + 8, 56, 30, S.page .. "/" .. mock.PAGE_N, C.sub or C.text, 20)
    px = px + 56
    pbtn(">",  function() if S.page < mock.PAGE_N then S.page = S.page + 1 S.sel = 1 defer(rebuild) end end)
    pbtn(">|", function() S.page = mock.PAGE_N S.sel = 1 defer(rebuild) end)

    -- 预览
    local f = list[S.sel] or list[1]
    local pv = theme.box(body, 600, 78, 336, 224, C.preview, 8)
    draw_model(pv, 93, 37, 150, f.kind)
    -- 预览外框：用 shape 描边（container 的 border 在部分固件上不渲染，shape 描边实测稳定）
    airui.shape({ parent = body, x = 600, y = 78, w = 336, h = 224, items = {
        { type = "rect", x = 1, y = 1, w = 334, h = 222, radius = 8,
          color = C.orange, width = 2, fill = false },
    } })
    theme.txt(body, 600, 316, 336, 30, f.name, C.text, 24, airui.TEXT_ALIGN_CENTER)
    theme.txt(body, 600, 350, 336, 26, f.date, C.sub, 18, airui.TEXT_ALIGN_CENTER)
    theme.btn(body, 668, 486, 200, 62, "打印", C.orange, 0x000000, C.orange, 0, 8, function()
        start_print()
    end)
end

-- 3 打印中
build_screen.printing = function()
    topbar({ { "首页", "home" }, { "打印", "files" }, { "打印中" } })

    local job = mock.get(S.page, S.sel)
    local pv = theme.box(body, 44, 78, 300, 206, C.preview, 8)
    draw_model(pv, 75, 28, 150, job.kind)
    -- 预览外框：与文件列表页同款（shape 描边，container 的 border 在部分固件不渲染）
    airui.shape({ parent = body, x = 44, y = 78, w = 300, h = 206, items = {
        { type = "rect", x = 1, y = 1, w = 298, h = 204, radius = 8,
          color = C.orange, width = 2, fill = false },
    } })
    theme.txt(body, 44, 294, 300, 30, job.name, C.text, 24, airui.TEXT_ALIGN_CENTER)
    theme.txt(body, 44, 326, 300, 26, job.date, C.sub, 18, airui.TEXT_ALIGN_CENTER)

    -- 2×2 指标
    local ms = {
        { icon = "nozzle", col = C.orange, val = tostring(mock.PARAM.nozzle), unit = mock.PARAM.nozzle_max .. "°C" },
        { icon = "fan",    col = C.green,  val = tostring(mock.PARAM.fan),    unit = "%" },
        { icon = "water",  col = C.purple, val = tostring(mock.PARAM.bed),    unit = mock.PARAM.bed_max .. "°C" },
        { icon = "move",   col = C.cyan,   val = "0.1",                       unit = "MM" },
    }
    for i, m in ipairs(ms) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 392 + col * 300
        local y = 76 + row * 84
        -- 图标放大到 68（原来 34 太小），垂直中心与数字对齐：y + 23 - 34
        theme.icon(body, x, y - 11, 68, m.icon, m.col)
        -- 32 号数字实际宽约 20px/字符；框必须给足，否则 "60" 会折行（第二行只露出半个字）
        local vw = #m.val * 20
        theme.txt(body, x + 76, y, vw + 4, 46, m.val, C.text, 32)
        theme.txt(body, x + 76 + vw + 6, y + 13, 110, 30, m.unit, C.sub, 20)
    end

    -- 停止 / 暂停
    theme.btn(body, 470, 330, 220, 64, "停止", C.bg, C.orange, C.orange, 2, 8, function()
        dialog("是否停止打印?", "是", function()
            stop_print(); defer(function() nav("files") end)
        end, "否", function() end)
    end)
    theme.btn(body, 736, 330, 220, 64, "暂停", C.yellow, 0x000000, C.yellow, 0, 8, function()
        S.printing = false
        dialog("已加载\n是否继续或停止打印?", "是", function()
            S.printing = true                      -- 继续：保持当前进度
        end, "否", function()
            -- 否 = 重新开始打印：进度归零后继续跑，停留在本页（绝不回文件列表）
            -- 这里只就地重画进度（不重建整页），避免任何销毁/重建带来的跳页风险
            S.screen   = "printing"
            S.prog     = 0
            S.printing = true
            update_prog()
        end)
    end)

    -- 进度（填充要严格贴住轨道内区：轨道 44,508,940x26 边框 2 → 内区 46,510,936x22）
    theme.txt(body, 44, 470, 300, 30, "打印进度", C.text, 24)
    refs.pct = theme.txt(body, W - 140, 470, 100, 30, S.prog .. " %", C.yellow, 24,
        airui.TEXT_ALIGN_RIGHT)
    theme.box_b(body, 44, 508, 940, 26, C.bg, 13, C.orange, 2)
    refs.fill = airui.shape({ parent = body, x = 46, y = 510, w = 936, h = 22, items = {} })
    update_prog()
end

-- 4 准备
build_screen.prep = function()
    topbar({ { "首页", "home" }, { "准备" } })
    local cards = {
        { icon = "move",   bg = C.gold,    name = "移动轴", target = "move" },
        { icon = "nozzle", bg = C.orange,  name = "进退料", target = "feed" },
        { icon = "fan",    bg = C.purple,  name = "风扇",   value = S.fan and "ON" or "OFF",
          toggle = function() S.fan = not S.fan defer(rebuild) end },
        { icon = "water",  bg = C.cyan,    name = "冷却",   value = S.cool and "ON" or "OFF",
          toggle = function() S.cool = not S.cool defer(rebuild) end },
        { icon = "info",   bg = C.gold,    name = "说明",   help = true },
    }
    for i, c in ipairs(cards) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 40 + col * 484
        local y = 84 + row * 140
        local card = theme.card(body, x, y, 460, 116, C.card, 8)
        local sq = theme.box(card, 22, 27, 62, 62, c.bg, 8)
        theme.icon(sq, 11, 11, 40, c.icon, 0x000000)
        theme.txt(card, 104, 40, 200, 36, c.name, C.text, 26)
        if c.value then
            theme.txt(card, 320, 40, 120, 36, c.value,
                (c.value == "ON") and C.text or C.purple, 26, airui.TEXT_ALIGN_RIGHT)
        elseif c.target or c.help then
            theme.txt(card, 400, 40, 40, 36, ">", C.dim, 26, airui.TEXT_ALIGN_RIGHT)
        end
        theme.hit(card, 0, 0, 460, 116, function()
            if c.target then defer(function() nav(c.target) end)
            elseif c.toggle then c.toggle()
            elseif c.help then
                dialog("操作说明\n磨损喷嘴请及时更换\n移动轴前请先归零", "确定", function() end)
            end
        end)
    end
end

-- 5 移动轴
build_screen.move = function()
    topbar({ { "首页", "home" }, { "准备", "prep" }, { "移动轴" } })

    theme.txt(body, 44, 88, 120, 34, "单位:MM", C.text, 24)
    local units = { { 0.1, "0.1 MM" }, { 1, "1MM" }, { 10, "10MM" } }
    theme.box_b(body, 168, 82, 560, 56, C.bg, 28, C.orange, 2)
    for i, u in ipairs(units) do
        local on = (S.unit == u[1])
        theme.btn(body, 172 + (i - 1) * 185, 86, 183, 48, u[2],
            on and C.yellow or C.bg, on and 0x000000 or C.text,
            on and C.yellow or C.bg, 0, 24, function()
                S.unit = u[1]
                if u[1] == 0.1 then
                    S.pos = { x = 49.4, y = 49.8, z = 49.6 }
                else
                    S.pos = { x = 50.0, y = 50.0, z = 50.0 }
                end
                defer(rebuild)
            end)
    end

    local axes = { { "X", S.pos.x }, { "Y", S.pos.y }, { "Z", S.pos.z } }
    for i, a in ipairs(axes) do
        local y = 168 + (i - 1) * 80
        theme.txt(body, 44, y + 14, 40, 32, a[1] .. ":", C.cyan, 26)
        theme.box_b(body, 88, y, 150, 58, C.bg, 6, C.gray, 2)
        theme.txt(body, 88, y + 14, 150, 32, string.format("%.1f", a[2]), C.text, 26,
            airui.TEXT_ALIGN_CENTER)
    end

    -- 方向键：竖排（图标上 + 轴名下），与 html 的 .dbtn 一致
    local function dir_btn(x, y, icon, label, fn)
        local b = theme.card(body, x, y, 88, 82, C.card2, 8)
        if label then
            theme.icon(b, 29, 12, 30, icon, C.cyan)
            theme.txt(b, 0, 48, 88, 24, label, C.cyan, 20, airui.TEXT_ALIGN_CENTER)
        else
            theme.icon(b, 29, 26, 30, icon, C.cyan)
        end
        theme.hit(b, 0, 0, 88, 82, function() fn(); defer(rebuild) end)
    end
    -- 左右键：横排（html 的 .dbtn.flat）
    local function dir_flat(x, y, dir, fn)
        local b = theme.card(body, x, y, 88, 82, C.card2, 8)
        if dir < 0 then
            theme.icon(b, 10, 26, 30, "arrow_left", C.cyan)
            theme.txt(b, 44, 30, 36, 24, "X", C.cyan, 20, airui.TEXT_ALIGN_CENTER)
        else
            theme.txt(b, 8, 30, 36, 24, "X", C.cyan, 20, airui.TEXT_ALIGN_CENTER)
            theme.icon(b, 48, 26, 30, "arrow_right", C.cyan)
        end
        theme.hit(b, 0, 0, 88, 82, function() fn(); defer(rebuild) end)
    end

    dir_btn(446, 168, "arrow_up", "Y", function() S.pos.y = S.pos.y + S.unit end)
    dir_flat(340, 264, -1, function() S.pos.x = S.pos.x - S.unit end)
    dir_btn(446, 264, "homepos", nil, function()
        S.pos.x, S.pos.y, S.pos.z = 0, 0, 0
    end)                                                 -- 原点（XY 一起归零）
    dir_flat(552, 264, 1, function() S.pos.x = S.pos.x + S.unit end)
    dir_btn(446, 360, "arrow_down", "Y", function() S.pos.y = S.pos.y - S.unit end)

    -- 右侧 Z 列（带 Z 标签，之前漏了导致"Z 不见了"）
    local function zbtn(y, icon, label, fn)
        local b = theme.card(body, 760, y, 92, 84, C.card2, 8)
        if label then
            theme.icon(b, 31, 12, 30, icon, C.cyan)
            theme.txt(b, 0, 48, 92, 24, label, C.cyan, 20, airui.TEXT_ALIGN_CENTER)
        else
            theme.icon(b, 31, 27, 30, icon, C.cyan)
        end
        theme.hit(b, 0, 0, 92, 84, function() fn(); defer(rebuild) end)
    end
    zbtn(168, "arrow_up", "Z", function() S.pos.z = S.pos.z + S.unit end)
    zbtn(268, "homepos", nil, function() S.pos.z = 0 end)
    zbtn(368, "arrow_down", "Z", function() S.pos.z = S.pos.z - S.unit end)
end

-- 6 进退料
build_screen.feed = function()
    topbar({ { "首页", "home" }, { "准备", "prep" }, { "进退料" } })

    local card = theme.box(body, 44, 84, 936, 170, C.card, 8)
    theme.icon(card, 22, 16, 38, "nozzle", C.orange)
    theme.txt(card, 70, 18, 240, 34, "喷头温度", C.text, 24)

    -- 喷头温度：真滑块（可拖动，对应 html 的 .slider），拖完即时刷新读数
    local nv = theme.txt(card, 600, 106, 300, 40, S.nozzle .. " °C", C.text, 26,
        airui.TEXT_ALIGN_RIGHT)
    theme.slider(card, 22, 62, 892, 30, 0, 260, S.nozzle, function(self)
        S.nozzle = self:get_value()
        pcall(nv.set_text, nv, S.nozzle .. " °C")
    end)

    local rows = {
        { y = 272, icon = "arrow_down", col = C.lime, name = "进料", val = S.feedIn, target = "in" },
        { y = 384, icon = "arrow_up",   col = C.cyan, name = "出料", val = S.feedOut, target = "out" },
    }
    for _, r in ipairs(rows) do
        local row = theme.card(body, 44, r.y, 936, 96, C.card, 8)
        theme.icon(row, 22, 28, 40, r.icon, r.col)
        theme.txt(row, 76, 30, 200, 36, r.name, C.text, 26)
        theme.txt(row, 600, 30, 300, 36, string.format("%.1f", r.val) .. "MM",
            C.text, 26, airui.TEXT_ALIGN_RIGHT)
        -- 进料 / 出料都弹数字键盘（对应 html 的 openNp('in') / openNp('out')）
        theme.hit(row, 0, 0, 936, 96, function()
            defer(function() open_np(r.target) end)
        end)
    end
end

-- 7 设置-配置
build_screen.set = function()
    topbar({ { "首页", "home" }, { "设置" } })
    side_menu("set")

    local cards = {
        { badge = "PLA", bcol = C.gold,   name = "PLA温度设置", val = S.plaTemp .. "°C",
          act = function() defer(function() open_np("pla") end) end },
        { badge = "ABS", bcol = C.orange, name = "ABS温度设置", val = S.absTemp .. "°C",
          act = function() defer(function() open_np("abs") end) end },
        { icon = "sliders", icol = C.purple, name = "调平", arrow = true,
          act = function() defer(function() nav("level") end) end },
        { icon = "bulb", icol = C.cyan, name = "灯光", val = S.light and "ON" or "OFF",
          act = function() S.light = not S.light defer(rebuild) end },
        { icon = "bell", icol = C.orange, name = "声音", val = S.sound and "ON" or "OFF",
          act = function() S.sound = not S.sound defer(rebuild) end },
        { icon = "sun", icol = C.gold, name = "亮度", arrow = true,
          act = function()
              dialog_slider("亮度调节", 0, 100, S.bri, " %", function(v)
                  S.bri = v
              end, function() defer(rebuild) end)
          end },
    }
    for i, c in ipairs(cards) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 230 + col * 392
        local y = 84 + row * 152
        local card = theme.card(body, x, y, 372, 132, C.card, 8)
        if c.badge then
            local bd = theme.box(card, 18, 35, 62, 62, c.bcol, 31)
            theme.txt(bd, 0, 20, 62, 24, c.badge, 0x000000, 18, airui.TEXT_ALIGN_CENTER)
        else
            local bd = theme.box(card, 18, 35, 62, 62, c.icol, 31)
            theme.icon(bd, 14, 14, 34, c.icon, 0x000000)
        end
        theme.txt(card, 96, 42, 200, 32, c.name, C.text, 22)
        if c.badge then
            -- PLA / ABS：温度值在名称下方
            theme.txt(card, 96, 76, 200, 30, c.val, C.orange, 20)
        elseif c.arrow then
            theme.txt(card, 320, 50, 40, 32, ">", C.dim, 24, airui.TEXT_ALIGN_RIGHT)
        elseif c.val then
            -- 灯光 / 声音：右侧 ON / OFF
            theme.txt(card, 232, 50, 128, 32, c.val,
                (c.val == "ON") and C.text or C.orange, 24, airui.TEXT_ALIGN_RIGHT)
        end
        theme.hit(card, 0, 0, 372, 132, c.act)
    end
end

-- 8 设置-系统设置
build_screen.sys = function()
    topbar({ { "首页", "home" }, { "设置", "set" } })
    side_menu("sys")

    local cards = {
        { name = "WIFI",     icon = "wifi",   col = C.green,  bgb = 0x0E2A1C, act = "wifi" },
        { name = "速度",     icon = "speed",  col = C.yellow, bgb = 0x3A2C05, act = "speed" },
        { name = "回零",     icon = "reboot", col = C.purple, bgb = 0x2A0F2A, act = "home" },
        { name = "一键调温", icon = "pid",    col = C.cyan,   bgb = 0x06282A, act = "pid" },
    }
    for i, c in ipairs(cards) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 236 + col * 386
        local y = 96 + row * 170
        local card = theme.card(body, x, y, 366, 150, C.card, 8)
        local bi = theme.box(card, 20, 43, 64, 64, c.bgb, 32)
        theme.icon(bi, 15, 15, 34, c.icon, c.col)
        theme.txt(card, 100, 58, 180, 36, c.name, C.text, 26)
        theme.txt(card, 300, 58, 46, 36, ">", C.sub, 26, airui.TEXT_ALIGN_RIGHT)
        theme.hit(card, 0, 0, 366, 150, function()
            if c.act == "wifi" then
                defer(function() nav("wifi") end)
            elseif c.act == "speed" then
                dialog_slider("打印速度", 0, 200, S.spd, " %", function(v)
                    S.spd = v
                end, function() defer(rebuild) end)
            elseif c.act == "home" then
                dialog("是否执行回零?", "是", function()
                    S.pos = { x = 0, y = 0, z = 0 }
                    defer(rebuild)
                end, "否", function() end)
            else
                dialog("已开始一键调温", "确定", function() end)
            end
        end)
    end
end

-- 9 设置-关于
build_screen.about = function()
    topbar({ { "首页", "home" }, { "设置", "set" } })
    side_menu("about")

    local rows = {
        { "设备名称", "LEVETOP" },
        { "设备型号", "LEVETOP-10 Smart" },
        { "版本号",   "V0.1.9" },
        { "打印尺寸", "300x300x300" },
        { "公司网站", "http://www.levetop.cn/" },
    }
    for i, r in ipairs(rows) do
        local y = 84 + (i - 1) * 62
        local on = (i == S.aboutSel)
        local row = theme.card(body, 236, y, 752, 62, on and C.orange or C.bg, 6)
        theme.txt(row, 20, 16, 300, 32, r[1], on and 0x000000 or C.text, 22)
        theme.txt(row, 300, 16, 420, 32, r[2], on and 0x000000 or C.text, 22,
            airui.TEXT_ALIGN_RIGHT)
        theme.hit(row, 0, 0, 752, 62, function() S.aboutSel = i defer(rebuild) end)
    end
end

-- 10 调平
build_screen.level = function()
    topbar({ { "首页", "home" }, { "设置", "set" }, { "调平" } })

    -- 布局与视频一致：上行 3 4 / 中行 5 / 下行 1 2
    local LV = { { 3, 4, 0 }, { 5, 0, 0 }, { 1, 2, 0 } }
    for r = 1, 3 do
        for c = 1, 3 do
            local n = LV[r][c]
            local x = 52 + (c - 1) * 132
            local y = 96 + (r - 1) * 120
            local on = (n ~= 0 and n == S.lvNext)
            local cell = theme.card(body, x, y, 118, 106, on and C.gold or C.slate, 6)
            if n ~= 0 then
                theme.txt(cell, 0, 34, 118, 44, tostring(n),
                    on and 0x000000 or C.text, 30, airui.TEXT_ALIGN_CENTER)
                if n == S.lvNext then
                    theme.hit(cell, 0, 0, 118, 106, function()
                        S.lvNext = n + 1
                        if S.lvNext > 5 then
                            S.lvNext = 0
                            defer(function()
                                dialog("已完成手动调平", "确定", function()
                                    S.lvNext = 1
                                    defer(function() nav("set") end)
                                end, nil, nil, "check", 900)
                            end)
                        else
                            defer(rebuild)
                        end
                    end)
                end
            end
        end
    end

    theme.txt(body, 480, 176, 480, 50, "请点击数字", C.text, 34)
    theme.txt(body, 480, 236, 480, 50, "进行辅助调平", C.text, 34)
end

-- 11 WiFi
build_screen.wifi = function()
    topbar({ { "首页", "home" }, { "设置", "set" }, { "网络" } })

    -- 对话框压到 300 高并贴住顶栏，把屏幕下部 200px 让给原生键盘（62+300+200 < 600）
    local dw, dh = 640, 300
    local dx, dy = math.floor((W - dw) / 2), 68
    local d = theme.box(body, dx, dy, dw, dh, C.dlg, 8)

    -- 右上关闭：用两条等宽斜线画，比字体里的 X 干净（对应 html 的 .wclose）
    theme.icon(d, dw - 52, 14, 24, "close", C.orange)
    theme.hit(d, dw - 66, 4, 60, 50, function() defer(function() nav("sys") end) end)

    --[[ 输入框照搬 Air8603 factory：卡片（细边）+ 内嵌原生 airui.textarea。
    原生 textarea 才有中文拼音输入、光标移动/选中、密码掩码这些能力，
    自绘 shape + label 只能显示字符串，功能上少了输入法这一整块。]]
    local function input_card(y, label, icon, color, text, placeholder, password)
        theme.icon(d, 30, y - 32, 24, icon, color)
        theme.txt(d, 62, y - 34, 300, 30, label, C.text, 22)
        theme.box_b(d, 30, y, dw - 60, 60, C.input, 8, C.gray, 1)
        local st = { radius = 6, bg_color = C.input, text_color = C.text, font_size = 24 }
        -- textarea 铺满卡片内区（只留 2px 露出卡片描边），避免出现"框里还有一个框"
        local ta = airui.textarea({
            parent = d, x = 32, y = y + 2, w = dw - 64, h = 56,
            text = text, placeholder = placeholder, max_len = 32,
            mode = password and "password" or "normal",
            style = st,
        })
        -- 部分固件创建期不解析 style（textarea 会留 LVGL 默认白底），建完再设一次
        pcall(ta.set_style, ta, st)
        return ta
    end

    refs.wname = input_card(50,  "WiFi 名称", "wifi", C.text,   S.wifiName, "请输入WiFi名称", false)
    refs.wpass = input_card(154, "WiFi 密码", "lock", C.orange, S.wifiPass, "请输入WiFi密码", true)

    theme.btn(d, 30, dh - 62, dw - 60, 50, "确定", C.orange, 0x000000, C.orange, 0, 6,
        function()
            -- 原生控件里的文本要主动取回（没有 on_change 也能在离开页面前读到最终值）
            if refs.wname then S.wifiName = refs.wname:get_text() end
            if refs.wpass then S.wifiPass = refs.wpass:get_text() end
            defer(function() nav("sys") end)
        end)

    --[[ 原生键盘：必须建在本页最后（创建顺序 = z-order），且「先建键盘，再逐个 attach」。
    factory 踩过的坑：创建 textarea 时传 keyboard= 那一刻键盘还不存在（nil），
    C 侧只在 textarea 创建那一瞬读该字段 → 输入框能聚焦但键盘永远不弹；
    共享键盘的正确姿势就是 attach_keyboard，聚焦/失焦事件会自动切目标。]]
    -- ✓（完成）键提交后收起键盘：factory 的 on_commit 就是 self:hide()
    local function kb_commit(self)
        if self and self.hide then self:hide() end
    end

    local kb = airui.keyboard({
        parent = body, w = W, h = 200,
        mode = "pinyin_26",                    -- 26 键拼音：中英文都能输（"text" 只有英文）
        auto_hide = true,
        preview = false,                       -- 关掉输入预览框（那是一条白框）
        font_size = 20,
        -- 配色照抄 Air8603 factory：浅灰键盘底 + 白键 + 深色文字
        bg_color = 0xE9E9E9,
        key_bg_color = 0xFFFFFF,
        key_text_color = 0x222222,
        key_pressed_bg_color = C.orange,
        key_pressed_text_color = 0x000000,
        key_border_color = 0xD0D0D0,
        text_color = 0x222222,
        border_color = 0xD0D0D0,
        cand_text_color = 0x222222,
        style = {
            bg_color = 0xFFFFFF, text_color = 0x222222,
            border_color = 0xD0D0D0, border_width = 1, radius = 6,
            pressed_bg_color = C.orange, pressed_text_color = 0x000000,
        },
        on_commit = kb_commit,
    })
    -- 部分固件创建期不解析 on_commit / style，建完再挂一次
    if kb and kb.set_on_commit then pcall(kb.set_on_commit, kb, kb_commit) end
    if kb and kb.set_style then
        pcall(kb.set_style, kb, {
            bg_color = 0xFFFFFF, text_color = 0x222222,
            border_color = 0xD0D0D0, border_width = 1, radius = 6,
            pressed_bg_color = C.orange, pressed_text_color = 0x000000,
        })
    end
    for _, ta in ipairs({ refs.wname, refs.wpass }) do
        if ta and ta.attach_keyboard then ta:attach_keyboard(kb) end
    end
end

-- 12 软键盘
build_screen.kbd = function()
    topbar({ { "设置", "set" }, { "网络", "wifi" }, { "输入" } })
    local px, py, pw, ph = 40, 78, 944, 470
    -- 键盘底：深色面板 + 1px 细边（对齐 Air8603 factory 的键盘样式，不再是整块白板）
    theme.box_b(body, px, py, pw, ph, C.card, 10, C.gray, 1)

    -- 输入行 + 退格（暗底细边，与 WiFi 页输入框同一套样式）
    theme.box_b(body, px + 8, py + 8, pw - 120, 58, C.input, 8, C.gray, 1)
    refs.kbdtext = theme.txt(body, px + 22, py + 18, pw - 144, 38, S.kbText, C.text, 30)
    theme.btn(body, px + pw - 104, py + 8, 96, 58, "DEL", C.card2, C.text, C.gray, 1, 8,
        function()
            S.kbText = string.sub(S.kbText, 1, math.max(0, #S.kbText - 1))
            kbd_redraw()
        end)

    -- 键区
    local key_h, gap = 56, 6
    local area_w = pw - 16 - 152 - gap
    for r, row in ipairs(KB_ROWS) do
        local n = #row
        local kw = math.floor((area_w - gap * (n - 1)) / n)
        for i, k in ipairs(row) do
            local x = px + 8 + (i - 1) * (kw + gap)
            local y = py + 76 + (r - 1) * (key_h + gap)
            local label = k
            if k == " " then label = "" end
            if S.caps and k:match("%a") then label = string.upper(k) end
            local w = kw
            if k == " " then w = kw * 3 + gap * 2 end
            theme.btn(body, x, y, w, key_h, label, C.card2, C.text, C.gray, 1, 8,
                function() kbd_key(k) end)
        end
    end

    -- 右列功能键（白底深字，Caps 青色；对应 html 的 .key.side / .key.caps）
    local rx = px + pw - 152
    local side = {
        { "X",         function() defer(function() nav("wifi") end) end },
        { "Caps",      function() S.caps = not S.caps defer(rebuild) end },
        { "Enter",     function() kbd_save() end },
        { "Backspace", function()
            S.kbText = string.sub(S.kbText, 1, math.max(0, #S.kbText - 1)); kbd_redraw()
        end },
        { "Hide",      function() defer(function() nav("wifi") end) end },
    }
    for i, k in ipairs(side) do
        local is_caps = (i == 2)
        theme.btn(body, rx, py + 76 + (i - 1) * (key_h + gap), 146, key_h, k[1],
            is_caps and C.orange or C.card2,
            is_caps and 0x000000 or C.text,
            is_caps and C.orange or C.gray, 1, 8, k[2])
    end
end

--------------------------------------------------------------------
-- 打印流程
--------------------------------------------------------------------
function start_print()
    S.prog = 0
    S.printing = true
    nav("printing")
end

function stop_print()
    S.printing = false
    S.prog = 0
end

function update_prog()
    if refs.pct and not refs.pct:is_destroyed() then
        pcall(refs.pct.set_text, refs.pct, S.prog .. " %")
    end
    if refs.fill and not refs.fill:is_destroyed() then
        local w = math.floor(936 * S.prog / 100)
        local items = {}
        if w > 2 then
            -- 圆角取与轨道内圆角一致的 h/2（11），否则左端上下会留出缝隙
            items[1] = { type = "rect", x = 0, y = 0, w = w, h = 22,
                radius = math.min(11, math.floor(w / 2)),
                color = C.yellow, width = 1, fill = true,
                fill_color = C.yellow, fill_opacity = 255 }
        end
        pcall(refs.fill.set_items, refs.fill, items)
    end
end

--------------------------------------------------------------------
-- 主入口
--------------------------------------------------------------------
local function build(root_in)
    root = root_in

    rebuild = function()
        clear_overlay()
        if body then pcall(body.destroy, body) body = nil end
        refs = {}
        body = theme.box(root, 0, 0, W, H, C.bg, 0)
        local fn = build_screen[S.screen] or build_screen.home
        local ok, err = pcall(fn)
        if not ok then
            log.error("page3d", "build " .. tostring(S.screen) .. " fail: " .. tostring(err))
            theme.txt(body, 40, 300, 900, 40, "页面构建失败: " .. tostring(err), C.red, 20)
        end
    end

    rebuild()

    -- 打印进度驱动：120ms 一步 × 1%（≈12 秒走完，与 html 的 setInterval 120ms 一致）
    -- make_page 支持 (fn, interval)，进度条因此每 120ms 前进一格，观感连续而非 1s 跳一次
    return function()
        if S.printing and S.screen == "printing" then
            S.prog = math.min(100, S.prog + 1)
            if S.prog >= 100 then
                S.printing = false
                update_prog()
                dialog("打印完成!", "是", function()
                    defer(function() nav("files") end)
                end, "否", function()
                    defer(function() nav("files") end)
                end)
            else
                update_prog()
            end
        end
    end, 120
end

theme.make_page(1, "3D打印机", build)
