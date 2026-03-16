-- air_win.lua - 空气质量历史图表窗口

local win_id = nil
local main_container, chart
local StatusProvider = require "status_provider_app"

local function create_ui()
    -- 使用全屏主容器布局，参考其他xx_win
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    airui.label({ parent = title_bar, x = 10, y = 4, w = 200, h = 32, text = "空气质量历史", font_size = 24, color = 0xfefefe })

    -- 返回按钮
    local back_btn = airui.container({
        parent = title_bar,
        x = 400,
        y = 5,
        w = 70,
        h = 30,
        color = 0x2195F6,
        radius = 5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align =
    airui.TEXT_ALIGN_CENTER })

    -- 图表区域
    chart = airui.chart({
        parent = main_container,
        x = 40,
        y = 60,
        w = 400,
        h = 200,
        y_min = 0,
        y_max = 1000,
        point_count = 20,
        line_color = 0x00b4ff,
        line_width = 2,
        hdiv = 5,
        vdiv = 5,
        legend = false,
        update_mode = "shift",
        x_axis = { enable = true, min = 0, max = 20, ticks = 5, unit = "次" },
        y_axis = { enable = true, min = 0, max = 1000, ticks = 5, unit = "ppb" }
    })

    local history = StatusProvider.get_history("air")
    if #history > 0 then
        chart:set_values(1, history)
    else
        log.info("air_win", "没有历史数据")
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

sys.subscribe("OPEN_AIR_HISTORY_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end)
