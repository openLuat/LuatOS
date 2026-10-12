--[[
@module  modbus_win
@summary Modbus 寄存器监视页面（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
展示从站寄存器映射表的关键点位当前值（继电器状态、CPU温度、VBAT、信号强度、时间戳等）。
每 2 秒自动刷新一次；订阅 RELAY_STATUS_UPDATE / TEMP_HUMIDITY_UPDATE 及时更新。

视觉：ui_theme 深色玻璃态（2列×3行 点位卡片，标签弱化 + 数值突出）。
]]

local theme = require "ui_theme"

local W                        -- 窗口控制器（文件末尾由 theme.win 建立）
local main_container, content
local relay_label, cpu_label, vbat_label, signal_label, temp_label, time_label

-- 自动刷新定时器
local refresh_timer = nil

-- 布局常量（内容区 464×210）
local CARD_W   = 228
local CARD_H   = 64
local CARD_GAP = 6

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not W:is_active() then return end
    exwin.close(W.id)
end

--[[
刷新寄存器显示

@local
@function refresh_regs
]]
local function refresh_regs()
    if not W:is_active() then return end

    -- 继电器状态（从 relay_ctrl 缓存读取）
    local relay_ctrl = require "relay_ctrl"
    local st = relay_ctrl.get_state() or {}
    if relay_label then
        relay_label:set_text(table.concat(st, ", "))
    end

    -- 系统数据
    if cpu_label then
        adc.open(adc.CH_CPU)
        local t = (adc.get(adc.CH_CPU) or 0) / 1000
        adc.close(adc.CH_CPU)
        cpu_label:set_text(string.format("%.1f ℃", t))
    end
    if vbat_label then
        adc.open(adc.CH_VBAT)
        local v = (adc.get(adc.CH_VBAT) or 0) / 1000
        adc.close(adc.CH_VBAT)
        vbat_label:set_text(string.format("%.2f V", v))
    end
    if signal_label then
        signal_label:set_text(tostring(mobile.csq() or 0) .. " dBm")
    end
    if time_label then
        time_label:set_text(os.date("%Y-%m-%d %H:%M:%S"))
    end
end

--[[
温湿度更新回调

@local
@function on_temp_humidity_update
@param temp number 温度
@param humi number 湿度
]]
local function on_temp_humidity_update(temp, humi)
    if not W:is_active() then return end
    if temp_label then
        temp_label:set_text(string.format("%.1f ℃ / %.1f %%RH", temp or 0, humi or 0))
    end
end

--[[
继电器状态更新回调

@local
@function on_relay_status_update
@param state table 继电器状态数组
]]
local function on_relay_status_update(state)
    if not W:is_active() then return end
    if relay_label and type(state) == "table" then
        relay_label:set_text(table.concat(state, ", "))
    end
end

--[[
创建一个寄存器点位卡片（标签 + 数值）

@local
@function create_point_card
@param userdata parent 父容器
@param number   x,y    位置
@param string   label  点位标签（含寄存器地址）
@param string   value  初始数值
@return userdata value_label 数值 label
]]
local function create_point_card(parent, x, y, label, value)
    local card = theme.card(parent, { x = x, y = y, w = CARD_W, h = CARD_H })
    theme.label(card, {
        x = 10, y = 6, w = CARD_W - 20, h = 19,
        text = label, px_size = 16, color = theme.C.t3 })
    return theme.label(card, {
        x = 10, y = 30, w = CARD_W - 20, h = 21,
        text = value, px_size = 18, color = theme.C.t1 })
end

--[[
创建寄存器监视 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "Modbus 寄存器", on_back = on_back_click })
    main_container = ctx.base

    local x1 = ctx.x
    local x2 = ctx.x + CARD_W + CARD_GAP
    local y1 = ctx.y
    local y2 = ctx.y + CARD_H + CARD_GAP
    local y3 = ctx.y + 2 * (CARD_H + CARD_GAP)

    relay_label  = create_point_card(ctx.base, x1, y1, "0x0000-04  继电器状态", "读取中...")
    temp_label   = create_point_card(ctx.base, x2, y1, "0x0020  网口TCP温湿度", "-- / --")
    cpu_label    = create_point_card(ctx.base, x1, y2, "0x0005-06  CPU温度", "--")
    vbat_label   = create_point_card(ctx.base, x2, y2, "0x0007-08  VBAT电压", "--")
    signal_label = create_point_card(ctx.base, x1, y3, "0x001D  4G信号强度", "--")
    time_label   = create_point_card(ctx.base, x2, y3, "0x0038-39  时间戳", "--")

    refresh_regs()
end

-- 自动刷新回调
local function refresh_timer_cb()
    refresh_regs()
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)
    sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    if not refresh_timer then
        refresh_timer = sys.timerLoopStart(refresh_timer_cb, 2000)
    end
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if refresh_timer then
        sys.timerStop(refresh_timer)
        refresh_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    relay_label = nil
    cpu_label = nil
    vbat_label = nil
    signal_label = nil
    temp_label = nil
    time_label = nil
    sys.unsubscribe("TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_regs()
end

--[[窗口控制器（公共样板 theme.win）
单实例保护（replace = true：本页已有非活动实例时先回收再新建），销毁时自动清空窗口 id。]]
W = theme.win({
    open = "OPEN_MODBUS_WIN",
    replace = true,
    on_create = on_create,
    on_destroy = on_destroy,
    on_get_focus = on_get_focus,
})
