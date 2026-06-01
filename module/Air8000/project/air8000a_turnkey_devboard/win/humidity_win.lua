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

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮和图表控件
-- 从StatusProvider获取历史数据并设置到图表
]]
local function create_ui()
    -- 使用全屏主容器布局，参考其他xx_win
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })
    
    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    airui.label({ parent = title_bar, x = 10, y = 4, w = 200, h = 32, text = "湿度历史", font_size = 24, color = 0xfefefe })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = title_bar, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 图表区域
    chart = airui.chart({
        parent = main_container,
        x = 40, y = 60, w = 400, h = 200,
        y_min = 0, y_max = 100,
        point_count = 20,
        line_color = 0x00b4ff,
        line_width = 2,
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

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI
]]
local function on_create()
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，释放资源
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    chart = nil
    win_id = nil
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus() end
-- 窗口失去焦点回调（空实现）
local function on_lose_focus() end


-- 订阅打开湿度历史窗口的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_HUM_HISTORY_WIN",open_handler)