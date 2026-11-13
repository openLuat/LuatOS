--[[
@module  page_dock
@summary 方案C · 底部 Dock 一屏流（对齐 smart_home/layouts/方案C_底部Dock一屏流.html）
@note 主色 #F59E0B；布局：房间 Tab + 气候/设备/安防三栏 + 底部场景 Dock。
      内容挂在本页内容层 ROOT 上，由 ui_page 管理器显隐轮询。
      顶栏右侧「深色/浅色」切换：AirUI 颜色创建即固化，切主题 = 销毁内容层后整体重建。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local M = {}

local C_DARK = {
    bg = 0x0D0F14, panel = 0x171B26, panel2 = 0x202636, line = 0x2A3149,
    pri = 0xF59E0B, pri2 = 0xD97706, ok = 0x3DDC84, danger = 0xFF5C5C, cool = 0x60A5FA,
    t1 = 0xF0F2F7, t2 = 0x9AA2B5, t3 = 0x69718A,
}
local C_LIGHT = {
    bg = 0xF1F3F8, panel = 0xFFFFFF, panel2 = 0xE9EDF4, line = 0xD6DCE7,
    pri = 0xE08A00, pri2 = 0xC26A00, ok = 0x16A34A, danger = 0xDC2626, cool = 0x2563EB,
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
    return airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2), border_width = 0 })
end

-- ==================== 顶栏：房间 Tab ====================
local room_tabs = {}
local function build_theme_toggle(parent, x)
    local b = panel(parent, x, 12, 88, 32, C.panel2, 16)
    dot(parent, x + 14, 24, 8, C.pri)
    W.text_mid(parent, { text = _theme == "dark" and "深色" or "浅色", x = x + 28, y = 12, w = 56, h = 32,
        size = 14, color = C.t1 })
    W.press_layer(parent, { x = x, y = 12, w = 88, h = 32, radius = 16, target = b,
        tx = x, ty = 12, on_click = function() M.set_theme() end })
end

local function build_roombar()
    local g = panel(ROOT, 16, 12, 992, 56, C.panel, 18)
    W.text(g, { text = "客厅", x = 26, y = 12, w = 180, h = 32, size = 24, color = C.t1, weight = 700 })
    build_theme_toggle(g, 580)
    local names = { "客厅", "主卧", "书房", "餐厅" }
    for i, n in ipairs(names) do
        room_tabs[i] = W.chip(g, { x = 700 + (i - 1) * 72, y = 12, w = 64, h = 32, text = n,
            off_color = 0xFFFFFF, off_opa = 10, off_tcolor = C.t2,
            on_color = C.pri, on_opa = 40, on_tcolor = C.pri, active = (i == 1) })
    end
end

-- ==================== 气候栏 ====================
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

local function build_climate()
    local p = panel(ROOT, 16, 84, 300, 396)
    local room = S.room()
    W.text(p, { text = "气候", x = 18, y = 16, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    W.text(p, { text = room.temp .. "°C", x = 18, y = 58, w = 200, h = 54, size = 44,
        color = C.t1, weight = 700 })
    W.text(p, { text = "湿度 " .. room.humi .. "%", x = 18, y = 144, w = 200, h = 26,
        size = 15, color = C.t2 })
    spark(p, 18, 178, 264, 60, C.pri, { 10, 6, 14, 8, 18, 12, 20 })
    -- 空调
    local ac = panel(p, 18, 244, 264, 128, C.panel2, 12)
    dot(ac, 16, 20, 10, C.pri)
    W.text(ac, { text = "空调", x = 34, y = 12, w = 100, h = 26, size = 16, color = C.t1 })
    W.text(ac, { text = room.ac_mode, x = 34, y = 42, w = 140, h = 24, size = 14, color = C.t2 })
    W.text(ac, { text = room.ac_t .. "°C", x = 150, y = 12, w = 100, h = 54, size = 30,
        color = C.pri, align = airui.TEXT_ALIGN_RIGHT, weight = 700 })
    W.chip(ac, { x = 16, y = 82, w = 232, h = 34, text = "制冷 · 自动风",
        off_color = C.pri, off_opa = 26, off_tcolor = C.pri,
        on_color = C.pri, on_opa = 26, on_tcolor = C.pri, active = true })
end

-- ==================== 设备栏 ====================
local function build_devices()
    local p = panel(ROOT, 332, 84, 392, 396)
    local room = S.room()
    W.text(p, { text = "设备", x = 18, y = 16, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    W.text(p, { text = "共 " .. S.dev_on_count(room) .. " 台运行中", x = 150, y = 20, w = 224, h = 24,
        size = 13, color = C.t3, align = airui.TEXT_ALIGN_RIGHT })
    local devs = room.devs or {}
    for i = 1, math.min(6, #devs) do
        local d = devs[i]
        local cx = 18 + ((i - 1) % 2) * 184
        local cy = 56 + math.floor((i - 1) / 2) * 108
        local on = d.on and true or false
        local b = panel(p, cx, cy, 176, 96, C.panel2, 12)
        dot(b, 14, 16, 8, on and C.pri or C.t3)
        W.text(b, { text = d.nm or "设备", x = 28, y = 8, w = 130, h = 26, size = 16, color = C.t1 })
        W.text(b, { text = (d.ds or "") .. (d.val or ""), x = 28, y = 38, w = 130, h = 24, size = 14, color = C.t2 })
        W.switch(p, { x = cx + 118, y = cy + 58, w = 48, h = 26, on = on, on_color = C.pri })
    end
end

-- ==================== 安防栏 ====================
local function build_security()
    local p = panel(ROOT, 740, 84, 268, 396)
    W.text(p, { text = "安防", x = 18, y = 16, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    -- 布防总览
    local st = panel(p, 18, 56, 232, 120, C.panel2, 12)
    dot(st, 16, 18, 10, S.security.armed and C.pri or C.t3)
    W.text(st, { text = "已布防", x = 34, y = 10, w = 120, h = 28, size = 18, color = C.t1, weight = 700 })
    W.text(st, { text = "离家模式 · 已启用", x = 34, y = 44, w = 180, h = 24, size = 13, color = C.t2 })
    W.chip(st, { x = 16, y = 80, w = 200, h = 30, text = "一键撤防",
        off_color = C.pri, off_opa = 40, off_tcolor = C.pri,
        on_color = C.pri, on_opa = 40, on_tcolor = C.pri, active = true })
    -- 状态行
    local rows = { { "门锁", "上锁", C.ok }, { "窗户", "1 处", C.danger }, { "摄像头", "在线", C.ok } }
    for i, r in ipairs(rows) do
        local y = 196 + (i - 1) * 56
        dot(p, 18, y + 10, 8, r[3])
        W.text(p, { text = r[1], x = 34, y = y, w = 90, h = 28, size = 16, color = C.t1 })
        W.text(p, { text = r[2], x = 110, y = y, w = 140, h = 28, size = 14,
            color = C.t2, align = airui.TEXT_ALIGN_RIGHT })
    end
end

-- ==================== 底部 Dock ====================
local function build_dock()
    local g = panel(ROOT, 16, 496, 992, 92, C.panel, 20)
    local names = { "回家", "离家", "睡眠", "观影", "起床", "会客" }
    for i, n in ipairs(names) do
        local w = 150
        local x = 16 + (i - 1) * (w + 8)
        local b = panel(g, x, 14, w, 64, C.panel2, 12)
        dot(b, 20, 16, 8, C.pri)
        W.text_mid(g, { text = n, x = x, y = 44, w = w, h = 28, size = 15,
            color = C.t1, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(g, { x = x, y = 14, w = w, h = 64, radius = 12, target = b,
            tx = x, ty = 14 })
    end
end

local function _build()
    C = (_theme == "dark") and C_DARK or C_LIGHT
    ROOT = airui.container({ parent = PAGE_ROOT, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, color = -1, border_width = 0 })
    room_tabs = {}
    panel(ROOT, 0, 0, T.screen.w, T.screen.h, C.bg, 0)
    build_roombar()
    build_climate()
    build_devices()
    build_security()
    build_dock()
end

function M.set_theme(name)
    _theme = (name == "light") and "light" or (name == "dark") and "dark"
        or (_theme == "dark" and "light" or "dark")
    -- 延迟销毁重建：不能在 LVGL 点击事件回调内同步删除事件源对象
    sys.timerStart(function()
        if ROOT then pcall(function() ROOT:destroy() end) end
        _build()
        log.info("page_dock", "主题切换为", _theme)
    end, 5)
end

function M.create(root)
    PAGE_ROOT = root or airui.screen
    _theme = "dark"
    _build()
    log.info("page_dock", "方案C 底部Dock页已创建")
end

return M
