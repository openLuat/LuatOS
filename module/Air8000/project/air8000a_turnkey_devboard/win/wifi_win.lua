--[[
@module  wifi_win
@summary WiFi配置页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为WiFi配置页面，支持扫描网络、显示列表、输入密码并连接。
订阅"OPEN_WIFI_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content, scan_list, connect_btn

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、扫描按钮、WiFi列表、连接按钮和密码输入框
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })
    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 扫描按钮
    airui.button({
        parent = content, x=190, y=10, w=100, h=30,
        text = "扫描",
        on_click = function() log.info("wifi", "扫描") end
    })

    -- WiFi列表
    scan_list = airui.table({
        parent = content, x=10, y=50, w=460, h=150,
        rows = 5, cols = 2, col_width = {300, 100}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    -- 连接按钮
    connect_btn = airui.button({
        parent = content, x=190, y=210, w=100, h=40,
        text = "连接",
        on_click = function() log.info("wifi", "连接") end
    })

    -- 密码输入
    airui.textarea({ parent = content, x=10, y=210, w=150, h=30, placeholder = "密码" })
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
    -- 可在此启动定时器、订阅等
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，停止定时器
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    -- 停止定时器、取消订阅等
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 获得焦点时可刷新UI
    -- 例如更新列表
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 失去焦点时可暂停某些操作
end

-- 订阅打开WiFi页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_WIFI_WIN", open_handler)