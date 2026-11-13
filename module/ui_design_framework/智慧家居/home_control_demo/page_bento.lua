--[[
@module  page_bento
@summary 方案B · Bento 磁贴（对齐 smart_home/layouts/方案B_Bento磁贴.html）
@note 主色 #5EEAD4；12 列 × 6 行磁贴网格：空调大磁贴 + 灯光/安防/场景/环境。
      内容挂在本页内容层 ROOT 上，由 ui_page 管理器显隐轮询。
      顶栏右侧「深色/浅色」切换：AirUI 颜色创建即固化，切主题 = 销毁内容层后整体重建。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local M = {}

local C_DARK = {
    bg = 0x0B0D12, panel = 0x161A24, panel2 = 0x1E2331, line = 0x272E42,
    pri = 0x5EEAD4, pri2 = 0x14B8A6, ok = 0x3DDC84, warn = 0xF5A623, danger = 0xFF5C5C,
    t1 = 0xEDF1F6, t2 = 0x98A0B3, t3 = 0x67708A,
}
local C_LIGHT = {
    bg = 0xF1F3F8, panel = 0xFFFFFF, panel2 = 0xE9EDF4, line = 0xD6DCE7,
    pri = 0x0D9488, pri2 = 0x0F766E, ok = 0x16A34A, warn = 0xE08A00, danger = 0xDC2626,
    t1 = 0x1A2233, t2 = 0x4B5568, t3 = 0x8A93A6,
}
local C = C_DARK                                  -- 当前主题色表（切主题时整体替换此 upvalue）

local ROOT                                        -- 内容层：所有控件的父容器
local PAGE_ROOT                                   -- ui_page 传入的整页根容器
local _theme = "dark"                             -- 仅内存态，每次开机默认暗色
local GW, GH = 68, 70                             -- 列宽/行高（12 列 6 行，间距 16）
local function tile(col, row, cs, rs)
    return { x = 16 + (col - 1) * (GW + 16), y = 80 + (row - 1) * (GH + 16),
        w = cs * GW + (cs - 1) * 16, h = rs * GH + (rs - 1) * 16 }
end
local function panel(parent, x, y, w, h, color, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel, radius = radius or 18, border_width = 0 })
end
local function dot(parent, x, y, d, color)
    return airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2), border_width = 0 })
end

-- ==================== 顶栏 ====================
local function build_theme_toggle(parent, x)
    local b = panel(parent, x, 12, 88, 32, C.panel2, 16)
    dot(parent, x + 14, 24, 8, C.pri)
    W.text_mid(parent, { text = _theme == "dark" and "深色" or "浅色", x = x + 28, y = 12, w = 56, h = 32,
        size = 14, color = C.t1 })
    W.press_layer(parent, { x = x, y = 12, w = 88, h = 32, radius = 16, target = b,
        tx = x, ty = 12, on_click = function() M.set_theme() end })
end

local function build_topbar()
    local g = panel(ROOT, 16, 12, 992, 56, C.panel, 18)
    W.text_mid(g, { text = "20:30", x = 24, y = 0, w = 160, h = 56, size = 26,
        color = C.t1, weight = 700 })
    W.text_mid(g, { text = "11月13日 · 周五", x = 190, y = 0, w = 260, h = 56, size = 15,
        color = C.t3 })
    build_theme_toggle(g, 700)
    W.text_mid(g, { text = "晴 22°C", x = 820, y = 0, w = 150, h = 56, size = 16,
        color = C.t2, align = airui.TEXT_ALIGN_RIGHT })
end

-- ==================== 空调大磁贴 ====================
local function build_ac()
    local t = tile(1, 1, 5, 6)
    local p = panel(ROOT, t.x, t.y, t.w, t.h)
    W.text(p, { text = "空调", x = 18, y = 14, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    local room = S.room()
    local sync_temp
    -- 环形表盘
    local dx, dy, dd = (t.w - 220) / 2, 74, 220
    W.shape(p, { x = dx, y = dy, w = dd, h = dd, items = {
        { type = "circle", cx = 110, cy = 110, r = 98, color = C.pri, width = 14, opacity = 255, fill = false },
        { type = "circle", cx = 110, cy = 110, r = 82, color = C.pri, fill = true, fill_color = C.pri, fill_opacity = 16 },
    } })
    local temp_lbl = W.text_mid(p, { text = room.ac_t .. "°C", x = dx, y = dy, w = dd, h = dd, size = 46,
        color = C.t1, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(p, { text = room.ac_mode .. " · 自动风", x = dx, y = dy + 196, w = dd, h = 26,
        size = 15, color = C.t2, align = airui.TEXT_ALIGN_CENTER })
    sync_temp = function()
        pcall(function() temp_lbl:set_text(room.ac_t .. "°C") end)
    end
    local btn = function(bx, txt, cb)
        local b = panel(p, bx, t.h - 96, 56, 56, C.panel2, 28)
        W.text_mid(p, { text = txt, x = bx, y = t.h - 96, w = 56, h = 56, size = 26,
            color = C.t1, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(p, { x = bx, y = t.h - 96, w = 56, h = 56, radius = 28, target = b,
            tx = bx, ty = t.h - 96, on_click = cb })
    end
    btn((t.w - 200) / 2, "-", function() S.ac_delta(room, -1) sync_temp() end)
    btn((t.w - 200) / 2 + 144, "+", function() S.ac_delta(room, 1) sync_temp() end)
end

-- ==================== 灯光磁贴 ====================
local function build_lights()
    local t = tile(6, 1, 4, 3)
    local p = panel(ROOT, t.x, t.y, t.w, t.h)
    W.text(p, { text = "灯光", x = 18, y = 14, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    local lights = { { "客厅主灯", true }, { "餐厅吊灯", true }, { "卧室壁灯", false }, { "书房台灯", true } }
    for i, l in ipairs(lights) do
        local cx = 16 + ((i - 1) % 2) * 148
        local cy = 52 + math.floor((i - 1) / 2) * 92
        dot(p, cx, cy + 6, 8, l[2] and C.pri or C.t3)
        W.text(p, { text = l[1], x = cx + 16, y = cy, w = 120, h = 26, size = 15, color = C.t1 })
        W.switch(p, { x = cx, y = cy + 34, w = 52, h = 26, on = l[2], on_color = C.pri })
    end
end

-- ==================== 安防磁贴 ====================
local function build_security()
    local t = tile(10, 1, 3, 3)
    local p = panel(ROOT, t.x, t.y, t.w, t.h)
    W.text(p, { text = "安防", x = 18, y = 14, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    local rows = { { "门锁", "上锁", C.ok }, { "窗户", "1 处", C.warn }, { "摄像头", "在线", C.ok } }
    for i, r in ipairs(rows) do
        local y = 54 + (i - 1) * 60
        dot(p, 18, y + 8, 8, r[3])
        W.text(p, { text = r[1], x = 34, y = y, w = 80, h = 26, size = 15, color = C.t1 })
        W.text(p, { text = r[2], x = 100, y = y, w = t.w - 118, h = 26, size = 13,
            color = C.t2, align = airui.TEXT_ALIGN_RIGHT })
    end
end

-- ==================== 场景磁贴 ====================
local function build_scenes()
    local t = tile(6, 4, 4, 3)
    local p = panel(ROOT, t.x, t.y, t.w, t.h)
    W.text(p, { text = "场景", x = 18, y = 14, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    local names = { "回家", "离家", "睡眠", "观影", "起床", "会客" }
    for i, n in ipairs(names) do
        local cx = 16 + ((i - 1) % 3) * 100
        local cy = 52 + math.floor((i - 1) / 3) * 92
        local b = panel(p, cx, cy, 88, 80, C.panel2, 12)
        dot(b, 12, 14, 10, C.pri)
        W.text_mid(p, { text = n, x = cx, y = cy + 40, w = 88, h = 30, size = 14,
            color = C.t1, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(p, { x = cx, y = cy, w = 88, h = 80, radius = 12, target = b,
            tx = cx, ty = cy })
    end
end

-- ==================== 环境磁贴 ====================
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
    local t = tile(10, 4, 3, 3)
    local p = panel(ROOT, t.x, t.y, t.w, t.h)
    W.text(p, { text = "环境", x = 18, y = 14, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    local items = {
        { "温度", "24°C", C.pri, { 4, 8, 5, 11, 7, 13 } },
        { "湿度", "48%", C.ok,  { 3, 6, 9, 5, 10, 8 } },
        { "CO2",  "620", C.warn,{ 8, 5, 7, 4, 9, 6 } },
    }
    for i, it in ipairs(items) do
        local y = 52 + (i - 1) * 62
        W.text(p, { text = it[1], x = 18, y = y, w = 52, h = 22, size = 13, color = C.t3 })
        W.text(p, { text = it[2], x = 18, y = y + 22, w = 70, h = 28, size = 20, color = C.t1, weight = 700 })
        spark(p, 90, y + 6, t.w - 108, 40, it[3], it[4])
    end
end

local function _build()
    C = (_theme == "dark") and C_DARK or C_LIGHT
    ROOT = airui.container({ parent = PAGE_ROOT, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, color = -1, border_width = 0 })
    panel(ROOT, 0, 0, T.screen.w, T.screen.h, C.bg, 0)
    build_topbar()
    build_ac()
    build_lights()
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
        log.info("page_bento", "主题切换为", _theme)
    end, 5)
end

function M.create(root)
    PAGE_ROOT = root or airui.screen
    _theme = "dark"
    _build()
    log.info("page_bento", "方案B Bento磁贴页已创建")
end

return M
