--[[
@module  modbus_win
@summary Modbus 寄存器监视页面（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
展示从站寄存器映射表的关键点位当前值（继电器状态、CPU温度、VBAT、信号强度、时间戳等）。
每 2 秒自动刷新一次；订阅 RELAY_STATUS_UPDATE / TEMP_HUMIDITY_UPDATE 及时更新。
]]

local win_id = nil
local main_container, content
local relay_label, cpu_label, vbat_label, signal_label, temp_label, time_label

-- 自动刷新定时器
local refresh_timer = nil

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
刷新寄存器显示

@local
@function refresh_regs
]]
local function refresh_regs()
    if not exwin.is_active(win_id) then return end

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
    if not exwin.is_active(win_id) then return end
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
    if not exwin.is_active(win_id) then return end
    if relay_label and type(state) == "table" then
        relay_label:set_text(table.concat(state, ", "))
    end
end

--[[
创建寄存器监视 UI

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "Modbus 寄存器", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    local _, _, relay_content = T.info_card(content, 6, 44, "0x0000-04  继电器状态", "读取中...")
    relay_label = relay_content

    local _, _, temp_content = T.info_card(content, 56, 44, "0x0020  网口TCP温湿度", "-- / --")
    temp_label = temp_content

    local _, _, cpu_content = T.info_card(content, 106, 44, "0x0005-06  CPU温度", "--")
    cpu_label = cpu_content

    local _, _, vbat_content = T.info_card(content, 156, 44, "0x0007-08  VBAT电压", "--")
    vbat_label = vbat_content

    local _, _, sig_content = T.info_card(content, 6, 44, "0x001D  4G信号强度", "--")
    sig_content:set_pos(240, 6)
    signal_label = sig_content

    -- 右上角补充：时间戳（覆盖在原卡片右侧）
    local time_card = airui.container({
        parent = content, x = 240, y = 156, w = 230, h = 44,
        color = T.COLOR_CARD, radius = T.CARD_RADIUS,
    })
    airui.label({
        parent = time_card, x = 10, y = 4, w = 210, h = 20,
        text = "0x0038-39  时间戳",
        font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    time_label = airui.label({
        parent = time_card, x = 10, y = 24, w = 210, h = 18,
        text = "--",
        font_size = T.FONT_SMALL, color = T.COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })

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
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_regs()
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_MODBUS_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_MODBUS_WIN", open_handler)
