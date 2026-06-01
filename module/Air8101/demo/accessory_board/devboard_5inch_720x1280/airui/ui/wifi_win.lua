-- wifi_win.lua
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
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=720, h=1280, color=0xF8F9FA })
    local header = airui.container({ parent = main_container, x=0, y=0, w=720, h=80, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 630, y = 20, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 8, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 0, y = 20, w = 720, h = 48, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=36, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=80, w=720, h=1120, color=0xF3F4F6 })

    airui.button({
        parent = content, x=300, y=30, w=120, h=56,
        text = "扫描",
        font_size = 24,
        on_click = function() log.info("wifi", "扫描") end
    })

    scan_list = airui.table({
        parent = content, x=20, y=110, w=680, h=360,
        rows = 6, cols = 2, col_width = {540, 100}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    airui.textarea({ parent = content, x=20, y=500, w=400, h=48, placeholder = "密码", font_size=24 })

    connect_btn = airui.button({
        parent = content, x=460, y=500, w=120, h=56,
        text = "连接",
        font_size = 24,
        on_click = function() log.info("wifi", "连接") end
    })
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