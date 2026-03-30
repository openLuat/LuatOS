--[[
@module  gps_win
@summary GPS定位页面模块
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container, content
local coord_label, update_interval_input
local gps_timer = nil

local function update_gps_display()
    if not exwin.is_active(win_id) then return end
    -- TODO: 读取GPS并更新 coord_label
end

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 390, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 460, h = 40, align = airui.TEXT_ALIGN_CENTER, text="GPS", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=480, h=740, color=0xF3F4F6 })

    airui.label({ parent = content, x=30, y=40, w=150, h=40, text="当前经纬度:", font_size=24, color=0x000000 })
    coord_label = airui.label({ parent = content, x=180, y=40, w=270, h=40, text="等待定位...", font_size=24, color=0x000000 })

    airui.label({ parent = content, x=30, y=100, w=150, h=40, text="更新频率(秒):", font_size=24, color=0x000000 })
    update_interval_input = airui.textarea({
        parent = content, x=180, y=100, w=100, h=40,
        placeholder = "1",
        font_size = 24,
        keyboard = { mode = "numeric" }
    })

    airui.label({ parent = content, x=30, y=170, w=150, h=40, text="运动传感器:", font_size=24, color=0x000000 })
    airui.label({ parent = content, x=180, y=170, w=200, h=40, text="静止", font_size=24, color=0x000000 })
end

local function on_create()
    create_ui()
    local interval = tonumber(update_interval_input:get_text()) or 1
    gps_timer = sys.timerLoopStart(update_gps_display, interval * 1000)
end

local function on_destroy()
    if gps_timer then sys.timerStop(gps_timer); gps_timer = nil end
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus()
    update_gps_display()
end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_GPS_WIN", open_handler)