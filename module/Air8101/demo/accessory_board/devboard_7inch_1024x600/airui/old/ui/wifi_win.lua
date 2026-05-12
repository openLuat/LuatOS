--[[
@module  wifi_win
@summary WiFi配置页面模块
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container, content, scan_list, connect_btn

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=1024, h=600, color=0xF8F9FA })
    local header = airui.container({ parent = main_container, x=0, y=0, w=1024, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 934, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 0, y = 12, w = 1024, h = 40, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=1024, h=540, color=0xF3F4F6 })

    airui.button({
        parent = content, x=452, y=20, w=120, h=50,
        text = "扫描",
        font_size = 20,
        on_click = function() log.info("wifi", "扫描") end
    })

    scan_list = airui.table({
        parent = content, x=20, y=90, w=984, h=200,
        rows = 5, cols = 2, col_width = {600, 100}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    connect_btn = airui.button({
        parent = content, x=452, y=310, w=120, h=50,
        text = "连接",
        font_size = 20,
        on_click = function() log.info("wifi", "连接") end
    })

    airui.textarea({ parent = content, x=20, y=310, w=400, h=40, placeholder = "密码", font_size=18 })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
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