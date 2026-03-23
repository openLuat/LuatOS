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

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })
    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    airui.button({
        parent = content, x=340, y=20, w=120, h=50,
        text = "扫描",
        font_size = 20,
        on_click = function() log.info("wifi", "扫描") end
    })

    scan_list = airui.table({
        parent = content, x=20, y=90, w=760, h=200,
        rows = 5, cols = 2, col_width = {500, 200}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    connect_btn = airui.button({
        parent = content, x=340, y=310, w=120, h=50,
        text = "连接",
        font_size = 20,
        on_click = function() log.info("wifi", "连接") end
    })

    airui.textarea({ parent = content, x=20, y=310, w=280, h=40, placeholder = "密码", font_size=18 })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_WIFI_WIN", open_handler)