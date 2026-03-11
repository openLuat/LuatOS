-- GPS页面
local gps_win = {}
local exwin = require "exwin"

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
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="GPS", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 坐标显示
    airui.label({ parent = content, x=20, y=20, w=150, h=30, text="当前经纬度:", font_size=18, color=0x000000 })
    coord_label = airui.label({ parent = content, x=180, y=20, w=250, h=30, text="等待定位...", font_size=18, color=0x000000 })

    -- 更新频率设置
    airui.label({ parent = content, x=20, y=70, w=150, h=30, text="更新频率(秒):", font_size=18, color=0x000000 })
    update_interval_input = airui.textarea({
        parent = content, x=180, y=70, w=80, h=30,
        placeholder = "1",
        keyboard = { mode = "numeric" }
    })

    -- 运动传感器状态（示例）
    airui.label({ parent = content, x=20, y=120, w=150, h=30, text="运动传感器:", font_size=18, color=0x000000 })
    airui.label({ parent = content, x=180, y=120, w=100, h=30, text="静止", font_size=18, color=0x000000 })
end

function gps_win.on_create(id)
    win_id = id
    create_ui()
    -- 启动GPS定时读取
    local interval = tonumber(update_interval_input:get_text()) or 1
    gps_timer = sys.timerLoopStart(update_gps_display, interval * 1000)
end

function gps_win.on_destroy(id)
    if gps_timer then sys.timerStop(gps_timer); gps_timer = nil end
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

function gps_win.on_get_focus(id)
    -- 获得焦点时立即刷新一次
    update_gps_display()
end

function gps_win.on_lose_focus(id)
    -- 失去焦点时可不做特殊处理，定时器依然运行但 is_active 会阻止UI更新
end

local function open_handler()
    exwin.open({
        on_create = gps_win.on_create,
        on_destroy = gps_win.on_destroy,
        on_get_focus = gps_win.on_get_focus,
        on_lose_focus = gps_win.on_lose_focus,
    })
end
sys.subscribe("OPEN_GPS_WIN", open_handler)

return gps_win