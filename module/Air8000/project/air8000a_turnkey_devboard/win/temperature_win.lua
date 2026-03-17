-- temperature_win.lua - 温度历史图表窗口

local win_id = nil
local main_container, chart
local StatusProvider = require "status_provider_app"

-- 创建UI
local function create_ui()
    -- 使用全屏主容器布局，参考其他xx_win
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })
    
    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    airui.label({ parent = title_bar, x = 10, y = 4, w = 200, h = 32, text = "温度历史", font_size = 24, color = 0xfefefe })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = title_bar, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 图表区域
    chart = airui.chart({
        parent = main_container,
        x = 40, y = 60, w = 400, h = 200,
        y_min = 0, y_max = 50,
        point_count = 20,
        line_color = 0x00b4ff,
        line_width = 2,
        hdiv = 5, vdiv = 5,
        legend = false,
        update_mode = "shift",
        x_axis = { enable = true, min = 0, max = 20, ticks = 5, unit = "次" },
        y_axis = { enable = true, min = 0, max = 50, ticks = 5, unit = "℃" }
    })

    -- 获取历史数据并设置
    local history = StatusProvider.get_history("temperature")
    if #history > 0 then
        chart:set_values(1, history)
    else
        log.info("temperature_win", "没有历史数据")
    end
end

-- 生命周期：创建窗口
local function on_create()
    create_ui()
    -- 由于图表是静态的，不需要订阅实时更新；若需要动态追加，可订阅 STATUS_SENSOR_UPDATED 并更新图表
    -- 这里保持简单，只显示打开时的历史数据
end

-- 生命周期：销毁窗口
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    chart = nil
    win_id = nil
end

-- 生命周期：获得焦点（可考虑刷新数据，但此处简单处理，不刷新）
local function on_get_focus()
    -- 如果需要刷新，可以重新获取历史数据并更新图表
    -- 但为避免闪烁，这里不自动刷新，用户关闭再打开即可看到最新
end

-- 生命周期：失去焦点
local function on_lose_focus()
    -- do nothing
end

-- 订阅打开温度历史窗口的消息
sys.subscribe("OPEN_TEMP_HISTORY_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end)