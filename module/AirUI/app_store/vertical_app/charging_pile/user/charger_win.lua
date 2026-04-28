--[[
@module  charging_station_win
@summary 充电桩状态页面模块，显示充电状态、充电信息和控制按钮
@version 1.0
@date    2026.04.08
@author  LuatOS查询路由代理
]]

local win_id = nil
local main_container, status_bar, time_label
local status_image_label, status_text, battery_level_label, progress_fill
local charging_amount_label, charging_time_label, current_cost_label
local charging_power_label, real_time_voltage_label, real_time_current_label
local start_btn, stop_btn, back_button
local confirm_dialog = nil

local ChargerApp = require "charger_app"
local StatusProvider = require "status_provider_app"

-- 更新时间显示
local function update_time()
    if not time_label then return end
    local current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end


-- 时间更新事件处理
local function on_status_time_updated()
    update_time()
end


-- 显示确认消息窗
local function show_confirm_dialog(title, message, confirm_callback, cancel_callback)
    -- 关闭之前的对话框
    if confirm_dialog then
        confirm_dialog:destroy()
        confirm_dialog = nil
    end
    
    local screen_w, screen_h = 480, 800
    
    -- 创建遮罩层
    local mask = airui.container({ 
        parent = airui.screen, 
        x = 0, 
        y = 0, 
        w = screen_w, 
        h = screen_h, 
        color = 0x000000, 
        opacity = 0.5 
    })
    
    -- 创建对话框
    local dialog_w = 320
    local dialog_h = 180
    local dialog_x = (screen_w - dialog_w) / 2
    local dialog_y = (screen_h - dialog_h) / 2
    
    local dialog = airui.container({ 
        parent = mask, 
        x = dialog_x, 
        y = dialog_y, 
        w = dialog_w, 
        h = dialog_h, 
        color = 0xFFFFFF, 
        corner_radius = 10 
    })
    
    -- 标题
    airui.label({ 
        parent = dialog, 
        x = 0, 
        y = 20, 
        w = dialog_w, 
        h = 30, 
        text = title, 
        font_size = 24, 
        color = 0x333333, 
        align = airui.TEXT_ALIGN_CENTER 
    })
    
    -- 消息文本
    airui.label({ 
        parent = dialog, 
        x = 20, 
        y = 60, 
        w = dialog_w - 40, 
        h = 40, 
        text = message, 
        font_size = 18, 
        color = 0x666666, 
        align = airui.TEXT_ALIGN_CENTER 
    })
    
    -- 确认按钮
    airui.container({ 
        parent = dialog, 
        x = 20, 
        y = 120, 
        w = 130, 
        h = 40, 
        color = 0x4CAF50, 
        corner_radius = 8, 
        on_click = function() 
            if confirm_callback then confirm_callback() end
            if confirm_dialog then
                confirm_dialog:destroy()
                confirm_dialog = nil
            end
        end 
    })
    airui.label({ 
        parent = dialog, 
        x = 20, 
        y = 120, 
        w = 130, 
        h = 40, 
        text = "确认", 
        font_size = 18, 
        color = 0xFFFFFF, 
        align = airui.TEXT_ALIGN_CENTER 
    })
    
    -- 取消按钮
    airui.container({ 
        parent = dialog, 
        x = 170, 
        y = 120, 
        w = 130, 
        h = 40, 
        color = 0x9E9E9E, 
        corner_radius = 8, 
        on_click = function() 
            if cancel_callback then cancel_callback() end
            if confirm_dialog then
                confirm_dialog:destroy()
                confirm_dialog = nil
            end
        end 
    })
    airui.label({ 
        parent = dialog, 
        x = 170, 
        y = 120, 
        w = 130, 
        h = 40, 
        text = "取消", 
        font_size = 18, 
        color = 0xFFFFFF, 
        align = airui.TEXT_ALIGN_CENTER 
    })
    
    confirm_dialog = mask
end

local function update_ui()
    if not status_text then return end
    
    local status = ChargerApp.get_status()
    
    if status == ChargerApp.STATUS_IDLE then
        if status_image_label then status_image_label:set_src("/luadb/charge_idle.png") end
        if status_text then status_text:set_text("空闲") end
        if start_btn then start_btn:set_color(0x4CAF50) end
        if stop_btn then stop_btn:set_color(0x9E9E9E) end
    elseif status == ChargerApp.STATUS_CHARGING then
        if status_image_label then status_image_label:set_src("/luadb/active_cust.png") end
        if status_text then status_text:set_text("正在充电") end
        if start_btn then start_btn:set_color(0x9E9E9E) end
        if stop_btn then stop_btn:set_color(0xF44336) end
    elseif status == ChargerApp.STATUS_FINISHED then
        if status_image_label then status_image_label:set_src("/luadb/charge_cust.png") end
        if status_text then status_text:set_text("充电完成") end
        if start_btn then start_btn:set_color(0x4CAF50) end
        if stop_btn then stop_btn:set_color(0x9E9E9E) end
    end
    
    local battery_level = ChargerApp.get_battery_level()
    if battery_level_label then battery_level_label:set_text(battery_level .. "%") end
    
    local charging_amount = ChargerApp.get_charging_amount()
    local charging_time = ChargerApp.get_charging_time()
    local charging_power = ChargerApp.get_charging_power()
    local current_cost = charging_amount * 0.8
    
    if charging_amount_label then charging_amount_label:set_text(string.format("%.2f kWh", charging_amount)) end
    if charging_time_label then charging_time_label:set_text(string.format("%.0f 分钟", charging_time)) end
    if current_cost_label then current_cost_label:set_text(string.format("%.2f元", current_cost)) end
    if charging_power_label then charging_power_label:set_text(string.format("%.1f kW", charging_power)) end
    if real_time_voltage_label then real_time_voltage_label:set_text("220.5 V") end
    if real_time_current_label then real_time_current_label:set_text("31.8 A") end
end

local function handle_start_charging()
    show_confirm_dialog("确认开始", "确定要开始充电吗？", function()
        ChargerApp.start_charging()
        update_ui()
    end)
end

local function handle_stop_charging()
    show_confirm_dialog("确认停止", "确定要停止充电吗？", function()
        ChargerApp.stop_charging()
        update_ui()
    end)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })

    status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    
    back_button = airui.container({ parent = status_bar, x = 20, y = 10, w = 100, h = 40, color = 0x38bdf8, radius = 8,
        on_click = function() 
            log.info("CHARGER_WIN", "Return button clicked")
            if win_id then 
                exwin.close(win_id) 
            end 
        end
    })
    airui.label({ parent = back_button, x = 20, y = 10, w = 60, h = 20, text = "返回", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    time_label = airui.label({ parent = status_bar, x = 140, y = 10, w = 200, h = 48, text = StatusProvider.get_time(), font_size = 40, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 480, h = 740, color = 0xF3F4F6 })

    local title = airui.label({
        parent = content,
        x = 0,
        y = 20,
        w = 480,
        h = 50,
        text = "充电桩",
        font_size = 38,
        color = 0x3F51B5,
        align = airui.TEXT_ALIGN_CENTER
    })

    local status_card = airui.container({ parent = content, x = 40, y = 80, w = 400, h = 180, color = 0xFFFFFF, corner_radius = 15 })
    
    local status_display = airui.container({ parent = status_card, x = 0, y = 0, w = 400, h = 100 })
    
    local status_image = airui.container({ 
        parent = status_display, 
        x = 20, 
        y = 20, 
        w = 70, 
        h = 70, 
        color = 0x4CAF50, 
        corner_radius = 35 
    })
    status_image_label = airui.image({ 
        parent = status_image, 
        x = 14, 
        y = 14, 
        w = 42, 
        h = 42, 
        src = "/luadb/charge_idle.png" 
    })
    
    status_text = airui.label({
        parent = status_display,
        x = 103,
        y = 20,
        w = 277,
        h = 65,
        text = "空闲",
        font_size = 28,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local battery_container = airui.container({ parent = status_card, x = 20, y = 100, w = 360, h = 60, color = 0xF5F5F5, corner_radius = 10 })
    airui.label({ parent = battery_container, x = 10, y = 15, w = 100, h = 30, text = "电量", font_size = 18, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    battery_level_label = airui.label({
        parent = battery_container,
        x = 260,
        y = 10,
        w = 90,
        h = 40,
        text = "0%",
        font_size = 28,
        color = 0x4CAF50,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    local progress_bar = airui.container({ parent = battery_container, x = 10, y = 40, w = 340, h = 10, color = 0xE0E0E0, corner_radius = 5 })
    progress_fill = airui.container({ parent = progress_bar, x = 0, y = 0, w = 0, h = 10, color = 0x4CAF50, corner_radius = 5 })

    local info_container = airui.container({ parent = content, x = 40, y = 240, w = 400, h = 300 })
    
    local info_card1 = airui.container({ parent = info_container, x = 0, y = 0, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card1, x = 15, y = 15, w = 162, h = 25, text = "充电量", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    charging_amount_label = airui.label({
        parent = info_card1,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0.00 kWh",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local info_card2 = airui.container({ parent = info_container, x = 208, y = 0, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card2, x = 15, y = 15, w = 162, h = 25, text = "充电时间", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    charging_time_label = airui.label({
        parent = info_card2,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0 分钟",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local info_card3 = airui.container({ parent = info_container, x = 0, y = 100, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card3, x = 15, y = 15, w = 162, h = 25, text = "当前费用", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    current_cost_label = airui.label({
        parent = info_card3,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0.00元",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local info_card4 = airui.container({ parent = info_container, x = 208, y = 100, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card4, x = 15, y = 15, w = 162, h = 25, text = "充电功率", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    charging_power_label = airui.label({
        parent = info_card4,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0 kW",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local info_card5 = airui.container({ parent = info_container, x = 0, y = 200, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card5, x = 15, y = 15, w = 162, h = 25, text = "实时电压", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    real_time_voltage_label = airui.label({
        parent = info_card5,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0 V",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local info_card6 = airui.container({ parent = info_container, x = 208, y = 200, w = 192, h = 90, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card6, x = 15, y = 15, w = 162, h = 25, text = "实时电流", font_size = 17, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    real_time_current_label = airui.label({
        parent = info_card6,
        x = 15,
        y = 45,
        w = 162,
        h = 30,
        text = "0 A",
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local control_container = airui.container({ parent = content, x = 40, y = 550, w = 400, h = 120, color = 0xFFFFFF, corner_radius = 15 })

    start_btn = airui.container({
        parent = control_container,
        x = 40,
        y = 20,
        w = 140,
        h = 80,
        color = 0x4CAF50,
        corner_radius = 15,
        on_click = handle_start_charging
    })
    airui.label({ parent = start_btn, x = 0, y = 26, w = 140, h = 28, text = "开始", font_size = 28, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })

    stop_btn = airui.container({
        parent = control_container,
        x = 220,
        y = 20,
        w = 140,
        h = 80,
        color = 0x9E9E9E,
        corner_radius = 15,
        on_click = handle_stop_charging
    })
    airui.label({ parent = stop_btn, x = 0, y = 26, w = 140, h = 28, text = "停止", font_size = 28, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
end

local function on_create()
    create_ui()
    update_ui()
    update_time() -- 初始化时间显示
    sys.timerLoopStart(update_time, 1000) -- 启动定时器，每秒更新时间
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated) -- 订阅时间更新事件
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated) -- 订阅信号更新事件
end

local function on_destroy()
    sys.timerStop(update_time) -- 停止定时器

    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_image_label, status_text, battery_level_label, progress_fill = nil, nil, nil, nil
    charging_amount_label, charging_time_label, current_cost_label = nil, nil, nil
    charging_power_label, real_time_voltage_label, real_time_current_label = nil, nil, nil
    start_btn, stop_btn, back_button = nil, nil, nil
    time_label = nil -- 清理时间标签
    win_id = nil -- 清理窗口ID标签
end

local function on_get_focus()
    update_ui()
    update_time() -- 获取焦点时更新时间显示
end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
        scroll = false
    })
end

sys.subscribe("OPEN_CHARGER_WIN", open_handler)
