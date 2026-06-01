--[[
@module  ethernet_win
@summary 以太网配置页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为以太网配置页面，支持设置网口类型、IP模式及手动IP参数。
订阅"OPEN_ETHERNET_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local ip_mode_dropdown, ip_input, mask_input, gw_input, dns_input

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="以太网", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    airui.label({ parent = content, x=50, y=40, w=150, h=40, text="网口类型:", font_size=24, color=0x000000 })
    local type_drop = airui.dropdown({ parent = content, x=210, y=40, w=200, h=40, options = { "WAN", "LAN" } })

    airui.label({ parent = content, x=50, y=100, w=150, h=40, text="IP模式:", font_size=24, color=0x000000 })
    ip_mode_dropdown = airui.dropdown({ parent = content, x=210, y=100, w=200, h=40, options = { "自动获取", "手动设置" } })

    ip_input = airui.textarea({ parent = content, x=210, y=160, w=250, h=40, placeholder = "IP地址", font_size=20 })
    mask_input = airui.textarea({ parent = content, x=210, y=220, w=250, h=40, placeholder = "子网掩码", font_size=20 })
    gw_input = airui.textarea({ parent = content, x=210, y=280, w=250, h=40, placeholder = "网关", font_size=20 })
    dns_input = airui.textarea({ parent = content, x=210, y=340, w=250, h=40, placeholder = "DNS", font_size=20 })

    airui.button({
        parent = content, x=560, y=340, w=120, h=50,
        text = "保存",
        font_size = 20,
        on_click = function()
            log.info("eth", "保存配置")
        end
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
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_ETHERNET_WIN", open_handler)