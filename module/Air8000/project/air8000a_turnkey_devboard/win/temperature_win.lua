-- temperature_win.lua - 温度历史图表窗口

local win_id = nil
local chart
local StatusProvider = require "status_provider_app"

-- 创建UI
local function create_ui()
    local win3 = airui.win({
        parent = airui.screen,
        title = "温度历史",
        w = 400, h = 300,
        close_btn = true,
        auto_center = true,
        on_close = function() if win_id then exwin.close(win_id) end  end
    })

    chart = airui.chart({
        x = 30, y = 0, w = 300, h = 170,
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
    end

    win3:add_content(chart)
    return win3
end

-- 生命周期：创建窗口
local function on_create()
    win_id = create_ui()
    -- 由于图表是静态的，不需要订阅实时更新；若需要动态追加，可订阅 STATUS_SENSOR_UPDATED 并更新图表
    -- 这里保持简单，只显示打开时的历史数据
end

-- 生命周期：销毁窗口
local function on_destroy()
    if win_id then
        win_id:close()
        win_id = nil
    end
    chart = nil
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