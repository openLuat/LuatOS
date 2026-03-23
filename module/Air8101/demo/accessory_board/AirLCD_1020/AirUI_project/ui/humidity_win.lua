--[[
@module  humidity_win
@summary 湿度历史图表窗口模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为湿度历史图表窗口，显示历史湿度数据折线图。
订阅"OPEN_HUM_HISTORY_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, chart
local StatusProvider = require "status_provider_app"

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 800, h = 480, color = 0xF8F9FA, parent = airui.screen })
    
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 800, h = 60, color = 0x3F51B5 })
    airui.label({ parent = title_bar, x = 10, y = 12, w = 300, h = 40, text = "湿度历史", font_size = 32, color = 0xfefefe })
    
    local back_btn = airui.container({ parent = title_bar, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    chart = airui.chart({
        parent = main_container,
        x = 80, y = 90, w = 640, h = 300,
        y_min = 0, y_max = 100,
        point_count = 20,
        line_color = 0x00b4ff,
        line_width = 3,
        hdiv = 5, vdiv = 5,
        legend = false,
        update_mode = "shift",
        x_axis = { enable = true, min = 0, max = 20, ticks = 5, unit = "次" },
        y_axis = { enable = true, min = 0, max = 100, ticks = 5, unit = "%" }
    })

    local history = StatusProvider.get_history("humidity")
    if #history > 0 then
        chart:set_values(1, history)
    else
        log.info("humidity_win", "没有历史数据")
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    chart = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_HUM_HISTORY_WIN",open_handler)