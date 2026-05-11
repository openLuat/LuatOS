--[[
@module  gps_win
@summary GPS定位页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为GPS定位页面，显示当前经纬度、更新频率设置和运动传感器状态。
订阅"OPEN_GPS_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local coord_label, update_interval_input
local gps_timer = nil

--[[
更新GPS显示

@local
@function update_gps_display
@return nil
@usage
-- 定时调用，读取GPS数据并更新坐标标签（TODO）
-- 仅当窗口活跃时才实际更新UI
]]
local function update_gps_display()
    if not exwin.is_active(win_id) then return end
    -- TODO: 读取GPS并更新 coord_label
    -- 示例：coord_label:set_text("31.1234,121.5678")
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、坐标标签、输入框和状态标签
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="GPS", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

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

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并启动GPS定时读取
]]
local function on_create()
    
    create_ui()
    -- 启动GPS定时读取
    local interval = tonumber(update_interval_input:get_text()) or 1
    gps_timer = sys.timerLoopStart(update_gps_display, interval * 1000)
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，停止定时器，销毁容器
]]
local function on_destroy()
    if gps_timer then sys.timerStop(gps_timer); gps_timer = nil end
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 获得焦点时立即刷新一次
    update_gps_display()
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 失去焦点时可不做特殊处理，定时器依然运行但 is_active 会阻止UI更新
end

-- 订阅打开GPS页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_GPS_WIN", open_handler)