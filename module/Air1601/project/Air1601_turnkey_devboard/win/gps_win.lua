-- gps_win.lua - GPS定位页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container, content
local coord_label, update_interval_input
local gps_timer = nil

local function update_gps_display()
    if not exwin.is_active(win_id) then return end
    -- TODO: 读取GPS并更新 coord_label
    -- 示例：coord_label:set_text("31.1234,121.5678")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "GPS定位", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 坐标显示
    airui.label({ parent = content, x = 200, y = 100, w = 200, h = 40, text = "当前经纬度:", font_size = 24, color = 0x000000 })
    coord_label = airui.label({ parent = content, x = 400, y = 100, w = 400, h = 40, text = "等待定位...", font_size = 24, color = 0x000000 })

    -- 更新频率设置
    airui.label({ parent = content, x = 200, y = 180, w = 200, h = 40, text = "更新频率(秒):", font_size = 24, color = 0x000000 })
    update_interval_input = airui.textarea({
        parent = content, x = 400, y = 180, w = 120, h = 40,
        placeholder = "1",
        keyboard = { mode = "numeric" }
    })

    -- 运动传感器状态（示例）
    airui.label({ parent = content, x = 200, y = 260, w = 200, h = 40, text = "运动传感器:", font_size = 24, color = 0x000000 })
    airui.label({ parent = content, x = 400, y = 260, w = 200, h = 40, text = "静止", font_size = 24, color = 0x000000 })
end

local function on_create()
    win_id = create_ui()
    -- 启动GPS定时读取
    if update_interval_input then
        local interval = tonumber(update_interval_input:get_text()) or 1
        gps_timer = sys.timerLoopStart(update_gps_display, interval * 1000)
    end
end

local function on_destroy()
    if gps_timer then sys.timerStop(gps_timer); gps_timer = nil end
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus()
    -- 获得焦点时立即刷新一次
    update_gps_display()
end

local function on_lose_focus()
    -- 失去焦点时可不做特殊处理，定时器依然运行但 is_active 会阻止UI更新
end

sys.subscribe("OPEN_GPS_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
    end
end)
