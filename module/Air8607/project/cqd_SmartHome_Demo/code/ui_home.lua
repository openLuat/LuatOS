--[[
@module ui_home
@summary 全屋智能中控主界面（两房一厅：客厅 / 主卧 / 次卧，每间房一张毛玻璃卡片）
@version 1.0
@usage
界面结构：
  [顶部栏] 标题 + 实时时间 + 提示条 + 全屋平均温度
  [客厅]  [主卧]  [次卧]  三张半透明毛玻璃卡片，每张卡片包含：
        温湿度读数 / 灯光开关 / 窗帘开关 / 空调开关 + 温度加减 + 风速档位
适配屏幕：1024x600（Air8601 标配 7 寸屏）
]]

local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"

local M = {}

local SW, SH   = T.screen.w, T.screen.h
local CARD_W   = 306
local CARD_H   = 474
local CARD_Y   = 102
local CARD_X   = { 29, 359, 689 }

local cards     = {}
local lbl_clock = nil
local lbl_avg   = nil
local lbl_toast = nil
local toast_seq = 0

--------------------------------------------------------------------
-- 顶部提示条
--------------------------------------------------------------------
local function toast(msg)
    if not lbl_toast then return end
    toast_seq = toast_seq + 1
    local seq = toast_seq
    pcall(function() lbl_toast:set_text(msg) end)
    sys.timerStart(function()
        if seq == toast_seq and lbl_toast then
            pcall(function() lbl_toast:set_text("") end)
        end
    end, 4000)
end

--------------------------------------------------------------------
-- 顶部栏
--------------------------------------------------------------------
local function build_topbar()
    local bar = airui.container({
        parent = airui.screen, x = 0, y = 0, w = SW, h = 86,
        color = 0xFFFFFF, radius = 0,
    })
    W.glass(bar, 0xFFFFFF, T.o.topbar)

    W.text(bar, {
        text = "全屋智能中控", x = 32, y = 12, w = 340, h = 46,
        size = T.f.h1, color = T.c.text, weight = 700,
    })

    lbl_clock = W.text(bar, {
        text = "", x = 34, y = 58, w = 340, h = 22,
        size = T.f.sub, color = T.c.text_sub,
    })

    lbl_toast = W.text_mid(bar, {
        text = "", x = 380, y = 28, w = 280, h = 30,
        size = 16, color = T.c.amber,
        align = airui.TEXT_ALIGN_CENTER,
    })

    lbl_avg = W.text_mid(bar, {
        text = "", x = 660, y = 22, w = 332, h = 44,
        size = 26, color = T.c.text, weight = 700,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 顶栏底部一条暖色装饰线
    W.line(airui.screen, 0, 86, SW, 2, T.c.amber_lt, 120)
end

--------------------------------------------------------------------
-- 单张房间卡片
--------------------------------------------------------------------
local function build_card(room, idx)
    local x = CARD_X[idx]
    local c = { room = room }

    -- 半透明毛玻璃卡片
    c.card = W.card({ parent = airui.screen, x = x, y = CARD_Y, w = CARD_W, h = CARD_H })

    -- 房间名 / 副标题 / 在线状态
    W.text(c.card, {
        text = room.name, x = 22, y = 14, w = 200, h = 42,
        size = T.f.title, color = T.c.text, weight = 700,
    })
    W.text(c.card, {
        text = room.en, x = 22, y = 58, w = 220, h = 20,
        size = T.f.mini, color = T.c.text_dim,
    })
    W.dot(c.card, CARD_W - 32, 28, 9, T.c.green)

    W.line(c.card, 22, 88, CARD_W - 44, 1)

    -- 温湿度读数
    c.lbl_temp = W.text(c.card, {
        text = "", x = 20, y = 94, w = 250, h = 68,
        size = T.f.temp, color = T.c.text, weight = 700,
    })
    c.lbl_humi = W.text(c.card, {
        text = "", x = 22, y = 166, w = 150, h = 24,
        size = 16, color = T.c.text_sub,
    })
    c.lbl_ac_state = W.text(c.card, {
        text = "", x = 156, y = 166, w = 128, h = 24,
        size = T.f.mini, color = T.c.amber,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 灯光开关
    W.text_mid(c.card, {
        text = room.light.label, x = 22, y = 200, w = 150, h = 34,
        size = T.f.body, color = T.c.text,
    })
    c.light_sw = W.switch(c.card, {
        x = CARD_W - 84, y = 200, w = 62, h = 32,
        on = room.light.on, on_color = T.c.sw_on,
        on_change = function(on)
            room.light.on = on
            log.info("ui_home", room.light.label, on and "ON" or "OFF")
            toast(room.light.label .. (on and " 已打开" or " 已关闭"))
            c.update()
        end,
    })

    -- 窗帘开关
    W.text_mid(c.card, {
        text = room.curtain.label, x = 22, y = 248, w = 150, h = 34,
        size = T.f.body, color = T.c.text,
    })
    c.curtain_sw = W.switch(c.card, {
        x = CARD_W - 84, y = 248, w = 62, h = 32,
        on = room.curtain.on, on_color = T.c.clay,
        on_change = function(on)
            room.curtain.on = on
            log.info("ui_home", room.curtain.label, on and "OPEN" or "CLOSE")
            toast(room.curtain.label .. (on and " 已拉开" or " 已拉上"))
            c.update()
        end,
    })

    -- ==================== 空调控制面板 ====================
    local panel_w = CARD_W - 32          -- 274
    local panel = airui.container({
        parent = c.card, x = 16, y = 294, w = panel_w, h = 160,
        color = T.c.panel, radius = T.r.panel,
    })
    W.glass(panel, T.c.panel, T.o.panel)
    W.border(panel, T.c.card_edge, 1)

    W.text(panel, {
        text = "空调", x = 18, y = 12, w = 90, h = 28,
        size = T.f.body, color = T.c.text, weight = 700,
    })

    -- 空调开关
    c.ac_sw = W.switch(panel, {
        x = panel_w - 20 - 62, y = 10, w = 62, h = 30,
        on = room.ac.on, on_color = T.c.amber,
        on_change = function(on)
            room.ac.on = on
            log.info("ui_home", room.name .. "空调", on and "ON" or "OFF")
            toast(room.name .. "空调" .. (on and " 已开启" or " 已关闭"))
            c.update()
        end,
    })

    -- 温度：－  26°C  ＋
    W.button(panel, {
        parent = panel, x = 18, y = 50, w = 44, h = 44,
        text = "-", size = 26, color = T.c.amber,
        on_click = function()
            S.ac_temp_delta(room, -1)
            room.ac.on = true
            toast(room.name .. "空调 " .. room.ac.temp .. "°C")
            c.update()
        end,
    })

    c.lbl_ac_temp = W.text_mid(panel, {
        text = "", x = 66, y = 50, w = 142, h = 44,
        size = T.f.ac, color = T.c.text, weight = 700,
        align = airui.TEXT_ALIGN_CENTER,
    })

    W.button(panel, {
        parent = panel, x = panel_w - 18 - 44, y = 50, w = 44, h = 44,
        text = "+", size = 26, color = T.c.amber,
        on_click = function()
            S.ac_temp_delta(room, 1)
            room.ac.on = true
            toast(room.name .. "空调 " .. room.ac.temp .. "°C")
            c.update()
        end,
    })

    -- 风速档位：低 / 中 / 高
    W.text_mid(panel, {
        text = "风速", x = 18, y = 106, w = 40, h = 32,
        size = T.f.sub, color = T.c.text_sub,
    })

    c.fan_chips = {}
    for i = 1, 3 do
        local chip_x = 64 + (i - 1) * 65
        c.fan_chips[i] = W.chip(panel, {
            x = chip_x, y = 106, w = 60, h = 32,
            text = S.fan_label(i),
            on_click = function()
                room.ac.fan = i
                room.ac.on = true
                log.info("ui_home", room.name .. "风速", S.fan_label(i))
                toast(room.name .. "风速 已调至 " .. S.fan_label(i) .. "档")
                c.update()
            end,
        })
    end

    -- 局部的刷新函数：只更新这张卡片上的动态内容
    function c.update()
        pcall(function()
            c.lbl_temp:set_text(S.fmt_temp(room.temp) .. "°C")
            c.lbl_humi:set_text("湿度 " .. room.humi .. "%RH")
            c.lbl_ac_state:set_text(room.ac.on and "制冷中" or "待机")
            c.lbl_ac_temp:set_text(room.ac.temp .. "°C")
        end)
        c.light_sw.set(room.light.on, false)
        c.curtain_sw.set(room.curtain.on, false)
        c.ac_sw.set(room.ac.on, false)
        for i, chip in ipairs(c.fan_chips) do
            chip.set_active(i == room.ac.fan)
        end
    end

    cards[idx] = c
    c.update()
    return c
end

--------------------------------------------------------------------
-- 全屋数据变化时统一刷新
--------------------------------------------------------------------
function M.refresh_all()
    for _, c in ipairs(cards) do
        c.update()
    end
    if lbl_avg then
        pcall(function()
            lbl_avg:set_text("全屋 " .. S.fmt_temp(S.avg_temp()) .. "°C")
        end)
    end
end

--------------------------------------------------------------------
-- 时钟
--------------------------------------------------------------------
local function update_clock()
    local t = os.time()
    local txt
    if t and t > 1700000000 then
        txt = os.date("%Y-%m-%d  %H:%M", t)
    else
        txt = "系统时间等待同步"
    end
    if lbl_clock then
        pcall(function() lbl_clock:set_text(txt) end)
    end
end

--------------------------------------------------------------------
-- 界面构建入口
--------------------------------------------------------------------
function M.create()
    -- 1) 暖色调背景照片（1024x600，JPG）
    local bg
    local ok = pcall(function()
        bg = airui.image({
            parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
            src = "/luadb/bg_warm.jpg",
        })
    end)
    if not ok or not bg then
        log.warn("ui_home", "背景图加载失败，使用纯色兜底")
        airui.container({
            parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
            color = 0xF6D8B4,
        })
    end

    -- 2) 顶部栏
    build_topbar()

    -- 3) 三个房间卡片
    for i, room in ipairs(S.rooms) do
        if i <= #CARD_X then
            build_card(room, i)
        end
    end

    -- 4) 首帧数据
    M.refresh_all()
    update_clock()

    -- 5) 温湿度实时漂移 + 时钟
    S.start_sim()
    sys.timerLoopStart(function()
        M.refresh_all()
    end, 5000)
    sys.timerLoopStart(update_clock, 20000)

    log.info("ui_home", "全屋智能中控界面已创建")
end

return M
