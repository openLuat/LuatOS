-- humidity_win.lua - 湿度历史图表窗口

local win_id = nil
local chart
local StatusProvider = require "status_provider_app"

local function create_ui()
    local win2 = airui.win({
        parent = airui.screen,
        title = "湿度历史",
        w = 400, h = 300,
        close_btn = true,
        auto_center = true,
        on_close = function() if win_id then exwin.close(win_id) end  end
    })

    chart = airui.chart({
        x = 30, y = 0, w = 300, h = 170,
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
    end

    win2:add_content(chart)
    return win2
end

local function on_create()
    win_id = create_ui()
end

local function on_destroy()
    if win_id then
        win_id:close()
        win_id = nil
    end
    chart = nil
end

local function on_get_focus() end
local function on_lose_focus() end

sys.subscribe("OPEN_HUM_HISTORY_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end)