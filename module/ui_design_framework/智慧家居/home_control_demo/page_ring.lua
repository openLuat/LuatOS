--[[
@module  page_ring
@summary 方案A · 环形中枢（对齐 smart_home/layouts/方案A_环形中枢.html）
@note 主色 #4DA3FF；布局：顶栏 + 左灯光/中空调大环/右安防场景三栏 + 底部环境条。
      内容挂在本页内容层 ROOT 上，由 ui_page 管理器显隐轮询。
      顶栏右侧「深色/浅色」切换：AirUI 颜色创建即固化，切主题 = 销毁内容层后整体重建
      （container:destroy 会级联删除子对象并失效引用，shape/switch/chip 一并随新主题重建）。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local M = {}

local C_DARK = {
    bg = 0x0C0E13, panel = 0x151823, panel2 = 0x1C2030, line = 0x242A3C,
    pri = 0x4DA3FF, ok = 0x3DDC84, warn = 0xF5A623, danger = 0xFF5C5C,
    t1 = 0xEEF1F7, t2 = 0x9AA1B3, t3 = 0x6B7284,
}
local C_LIGHT = {
    bg = 0xF1F3F8, panel = 0xFFFFFF, panel2 = 0xE9EDF4, line = 0xD6DCE7,
    pri = 0x1D6FE0, ok = 0x16A34A, warn = 0xE08A00, danger = 0xDC2626,
    t1 = 0x1A2233, t2 = 0x4B5568, t3 = 0x8A93A6,
}
local C = C_DARK                                  -- 当前主题色表（切主题时整体替换此 upvalue）

local ROOT                                        -- 内容层：所有控件的父容器
local PAGE_ROOT                                   -- ui_page 传入的整页根容器
local _theme = "dark"                             -- 仅内存态，每次开机默认暗色
local function panel(parent, x, y, w, h, color, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel, radius = radius or 16, border_width = 0 })
end

local function dot(parent, x, y, d, color)
    local o = airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2), border_width = 0 })
    return o
end

local function title(parent, x, y, txt, color)
    W.text(parent, { text = txt, x = x, y = y, w = 160, h = 28, size = 18,
        color = color or C.t1, weight = 700 })
end

-- ==================== 顶栏 ====================
local function status_chip(parent, x, name, txt, color)
    local box = panel(parent, x, 22, 150, 32, C.panel2, 16)
    dot(parent, x + 12, 34, 8, color)
    W.text_mid(parent, { text = name .. " " .. txt, x = x + 26, y = 22, w = 120, h = 32,
        size = 14, color = C.t2 })
end

local function build_theme_toggle(parent, x)
    local b = panel(parent, x, 22, 88, 32, C.panel2, 16)
    dot(parent, x + 14, 34, 8, C.pri)
    W.text_mid(parent, { text = _theme == "dark" and "深色" or "浅色", x = x + 28, y = 22, w = 56, h = 32,
        size = 14, color = C.t1 })
    W.press_layer(parent, { x = x, y = 22, w = 88, h = 32, radius = 16, target = b,
        tx = x, ty = 22, on_click = function() M.set_theme() end })
end

local function build_topbar()
    local g = panel(ROOT, 16, 12, 992, 56, C.panel, 18)
    W.text(g, { text = "HOME", x = 26, y = 14, w = 140, h = 30, size = 22,
        color = C.pri, weight = 700 })
    status_chip(g, 200, "安防", "布防", C.ok)
    status_chip(g, 360, "门锁", "上锁", C.ok)
    status_chip(g, 520, "窗户", "1 处", C.warn)
    build_theme_toggle(g, 888)
end

-- ==================== 左栏：灯光 ====================
local function light_row(parent, x, y, w, name, sub, on)
    local box = panel(parent, x, y, w, 82, C.panel2, 12)
    local ic = panel(box, 12, 21, 40, 40, C.panel, 12)
    dot(ic, 15, 15, 10, on and C.pri or C.t3)
    W.text(box, { text = name, x = 62, y = 12, w = 100, h = 26, size = 16, color = C.t1 })
    W.text(box, { text = sub, x = 62, y = 44, w = 100, h = 22, size = 13, color = C.t3 })
    W.switch(parent, { x = x + w - 72, y = y + 27, w = 56, h = 28, on = on, on_color = C.pri })
end

local function build_lights()
    local p = panel(ROOT, 16, 84, 264, 416)
    title(p, 16, 16, "灯光")
    local rows = { { "客厅主灯", "亮度 60%", true }, { "餐厅吊灯", "亮度 80%", true },
        { "卧室壁灯", "亮度 30%", false }, { "书房台灯", "亮度 55%", true } }
    for i, r in ipairs(rows) do
        light_row(p, 16, 52 + (i - 1) * 90, 232, r[1], r[2], r[3])
    end
end

-- ==================== 中栏：空调大环 ====================
local function build_ac()
    local p = panel(ROOT, 296, 84, 432, 416)
    title(p, 16, 16, "空调")
    W.chip(p, { x = 344, y = 14, w = 72, h = 30, text = "制冷",
        off_color = C.pri, off_opa = 30, off_tcolor = C.pri,
        on_color = C.pri, on_opa = 30, on_tcolor = C.pri, active = true })
    -- 环形表盘：整圆 stroke = 圆环，内圈淡青填充
    W.shape(p, { x = 116, y = 70, w = 200, h = 200, items = {
        { type = "circle", cx = 100, cy = 100, r = 90, color = C.pri, width = 12, opacity = 255, fill = false },
        { type = "circle", cx = 100, cy = 100, r = 76, color = C.pri, fill = true, fill_color = C.pri, fill_opacity = 14 },
    } })
    local room = S.room()
    local temp_lbl = W.text_mid(p, { text = room.ac_t .. "°C", x = 116, y = 70, w = 200, h = 200,
        size = 46, color = C.t1, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(p, { text = room.ac_mode .. " · 自动风", x = 116, y = 272, w = 200, h = 28,
        size = 15, color = C.t2, align = airui.TEXT_ALIGN_CENTER })
    local sync_temp = function()
        pcall(function() temp_lbl:set_text(room.ac_t .. "°C") end)
    end
    -- 控制行
    local btn = function(bx, txt, cb)
        local b = panel(p, bx, 316, 56, 56, C.panel2, 28)
        W.text_mid(p, { text = txt, x = bx, y = 316, w = 56, h = 56, size = 26,
            color = C.t1, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(p, { x = bx, y = 316, w = 56, h = 56, radius = 28, target = b,
            tx = bx, ty = 316, on_click = cb })
    end
    btn(128, "-", function() S.ac_delta(room, -1) sync_temp() end)
    btn(248, "+", function() S.ac_delta(room, 1) sync_temp() end)
    local pw = panel(p, 150, 384, 132, 32, C.danger, 16)
    W.text_mid(p, { text = "电源", x = 150, y = 384, w = 132, h = 32, size = 16,
        color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(p, { x = 150, y = 384, w = 132, h = 32, radius = 16, target = pw,
        tx = 150, ty = 384 })
end

-- ==================== 右栏：安防 + 场景 ====================
local function build_security()
    local p = panel(ROOT, 744, 84, 264, 200)
    title(p, 16, 16, "安防")
    local rows = { { "门锁", "已上锁", C.ok }, { "窗户", "1 处未关", C.warn }, { "摄像头", "在线", C.ok } }
    for i, r in ipairs(rows) do
        local y = 56 + (i - 1) * 46
        dot(p, 18, y + 10, 8, r[3])
        W.text(p, { text = r[1], x = 34, y = y, w = 80, h = 28, size = 16, color = C.t1 })
        W.text(p, { text = r[2], x = 110, y = y, w = 138, h = 28, size = 14,
            color = C.t2, align = airui.TEXT_ALIGN_RIGHT })
    end
end

local function build_scenes()
    local p = panel(ROOT, 744, 300, 264, 200)
    title(p, 16, 16, "场景")
    local names = { "回家", "离家", "睡眠", "观影" }
    for i, n in ipairs(names) do
        local cx = 16 + ((i - 1) % 2) * 120
        local cy = 54 + math.floor((i - 1) / 2) * 66
        local b = panel(p, cx, cy, 112, 56, C.panel2, 12)
        dot(b, 10, 22, 10, C.pri)
        W.text_mid(p, { text = n, x = cx, y = cy, w = 112, h = 56, size = 15,
            color = C.t1, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(p, { x = cx, y = cy, w = 112, h = 56, radius = 12, target = b,
            tx = cx, ty = cy })
    end
end

-- ==================== 底部环境条 ====================
local function spark(parent, x, y, w, h, color, pts)
    local items = {}
    for i = 1, #pts - 1 do
        items[#items + 1] = { type = "line",
            x1 = (i - 1) * (w / (#pts - 1)), y1 = h - pts[i],
            x2 = i * (w / (#pts - 1)), y2 = h - pts[i + 1],
            color = color, width = 2, opacity = 220 }
    end
    return W.shape(parent, { x = x, y = y, w = w, h = h, items = items })
end

local function build_env()
    local items = {
        { "温度", "24.0°C", C.pri, { 4, 8, 5, 11, 7, 13 } },
        { "湿度", "48%",   C.ok,  { 3, 6, 9, 5, 10, 8 } },
        { "CO2",  "620ppm",C.warn,{ 8, 5, 7, 4, 9, 6 } },
        { "空气", "优",     C.ok,  { 5, 4, 6, 3, 5, 2 } },
    }
    for i, it in ipairs(items) do
        local x = 16 + (i - 1) * 252
        local p = panel(ROOT, x, 516, 236, 64, C.panel, 14)
        W.text(p, { text = it[1], x = 14, y = 8, w = 60, h = 20, size = 13, color = C.t3 })
        W.text(p, { text = it[2], x = 14, y = 30, w = 110, h = 28, size = 20, color = C.t1, weight = 700 })
        spark(p, 120, 16, 102, 32, it[3], it[4])
    end
end

local function _build()
    C = (_theme == "dark") and C_DARK or C_LIGHT
    ROOT = airui.container({ parent = PAGE_ROOT, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, color = -1, border_width = 0 })
    panel(ROOT, 0, 0, T.screen.w, T.screen.h, C.bg, 0)
    build_topbar()
    build_lights()
    build_ac()
    build_security()
    build_scenes()
    build_env()
end

function M.set_theme(name)
    _theme = (name == "light") and "light" or (name == "dark") and "dark"
        or (_theme == "dark" and "light" or "dark")
    -- 延迟销毁重建：不能在 LVGL 点击事件回调内同步删除事件源对象
    sys.timerStart(function()
        if ROOT then pcall(function() ROOT:destroy() end) end
        _build()
        log.info("page_ring", "主题切换为", _theme)
    end, 5)
end

function M.create(root)
    PAGE_ROOT = root or airui.screen
    _theme = "dark"
    _build()
    log.info("page_ring", "方案A 环形中枢页已创建")
end

return M
