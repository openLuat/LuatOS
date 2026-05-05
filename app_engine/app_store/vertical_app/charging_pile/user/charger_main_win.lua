--[[
@module  charging_station_main_win
@summary 充电桩主页面模块，显示充电桩首页和导航到充电状态
@version 1.0
@date    2026.04.08
@author  LuatOS查询路由代理
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local win_id = nil
local main_container, status_bar, time_label
local back_button, qrcode_img, status_button
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



local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })

    status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    time_label = airui.label({ parent = status_bar, x = 140, y = 10, w = 200, h = 48, text = StatusProvider.get_time(), font_size = 40, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    back_button = airui.container({ parent = status_bar, x = 20, y = 10, w = 100, h = 40, color = 0x38bdf8, radius = 8,
        on_click = function() 
            log.info("CHARGER_MAIN_WIN", "Return button clicked")
            if win_id then 
                exwin.close(win_id) 
            end 
        end
    })
    airui.label({ parent = back_button, x = 20, y = 10, w = 60, h = 20, text = "返回", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 480, h = 740, color = 0xF3F4F6 })

    local title = airui.label({
        parent = content,
        x = 0,
        y = 20,
        w = 480,
        h = 50,
        text = "充电桩",
        font_size = 40,
        color = 0x3F51B5,
        align = airui.TEXT_ALIGN_CENTER
    })

    local welcome_text1 = airui.label({
        parent = content,
        x = 0,
        y = 75,
        w = 480,
        h = 30,
        text = "欢迎使用智能充电桩系统",
        font_size = 20,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    local welcome_text2 = airui.label({
        parent = content,
        x = 0,
        y = 100,
        w = 480,
        h = 30,
        text = "扫描二维码开始充电",
        font_size = 20,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    local qrcode_container = airui.container({ parent = content, x = 40, y = 140, w = 400, h = 330, color = 0xFFFFFF, corner_radius = 15 })
    
    local qrcode_title = airui.label({
        parent = qrcode_container,
        x = 0,
        y = 20,
        w = 400,
        h = 40,
        text = "扫描充电",
        font_size = 26,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    qrcode_img = airui.qrcode({
        parent = qrcode_container,
        x = 80,
        y = 70,
        size = 240,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    status_button = airui.container({ 
        parent = content, 
        x = 40, 
        y = 470, 
        w = 400, 
        h = 90, 
        color = 0xFFFFFF, 
        corner_radius = 15,
        on_click = function() sys.publish("OPEN_CHARGER_WIN") end
    })

    local button_icon = airui.container({ 
        parent = status_button, 
        x = 20, 
        y = 20, 
        w = 60, 
        h = 60, 
        color = 0x4CAF50, 
        corner_radius = 10 
    })
    airui.image({ 
        parent = button_icon, 
        x = 15, 
        y = 15, 
        w = 30, 
        h = 30, 
        src = "/luadb/charge_cust.png" 
    })

    local button_title = airui.label({
        parent = status_button,
        x = 100,
        y = 20,
        w = 200,
        h = 35,
        text = "充电状态",
        font_size = 28,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local button_desc = airui.label({
        parent = status_button,
        x = 100,
        y = 55,
        w = 200,
        h = 25,
        text = "查看充电详情",
        font_size = 18,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({ parent = status_button, x = 360, y = 38, w = 30, h = 24, text = ">", font_size = 24, color = 0x9E9E9E, align = airui.TEXT_ALIGN_CENTER })

    local info_card1 = airui.container({ parent = content, x = 40, y = 570, w = 400, h = 45, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card1, x = 20, y = 12, w = 200, h = 20, text = "当前可用充电桩", font_size = 18, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = info_card1, x = 300, y = 12, w = 80, h = 20, text = "5个", font_size = 20, color = 0x333333, align = airui.TEXT_ALIGN_RIGHT })

    local info_card2 = airui.container({ parent = content, x = 40, y = 620, w = 400, h = 45, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card2, x = 20, y = 12, w = 200, h = 20, text = "今日总充电量", font_size = 18, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = info_card2, x = 280, y = 12, w = 100, h = 20, text = "125.5 kWh", font_size = 20, color = 0x333333, align = airui.TEXT_ALIGN_RIGHT })

    local info_card3 = airui.container({ parent = content, x = 40, y = 670, w = 400, h = 45, color = 0xFFFFFF, corner_radius = 15 })
    airui.label({ parent = info_card3, x = 20, y = 12, w = 200, h = 20, text = "系统运行时间", font_size = 18, color = 0x666666, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = info_card3, x = 300, y = 12, w = 80, h = 20, text = "24小时", font_size = 20, color = 0x333333, align = airui.TEXT_ALIGN_RIGHT })
end

local function on_create()
    create_ui()
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
    time_label = nil -- 清理时间标签
    win_id = nil
end

local function on_get_focus()
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

sys.subscribe("OPEN_CHARGER_MAIN_WIN", open_handler)
