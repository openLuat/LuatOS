-- 以太网页面
local ethernet_win = {}
local exwin = require "exwin"

local win_id = nil
local main_container, content
local ip_mode_dropdown, ip_input, mask_input, gw_input, dns_input

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="以太网", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 网口类型
    airui.label({ parent = content, x=20, y=20, w=100, h=30, text="网口类型:", font_size=16, color=0x000000 })
    local type_drop = airui.dropdown({ parent = content, x=130, y=20, w=150, h=30, options = { "WAN", "LAN" } })

    -- IP模式
    airui.label({ parent = content, x=20, y=60, w=100, h=30, text="IP模式:", font_size=16, color=0x000000 })
    ip_mode_dropdown = airui.dropdown({ parent = content, x=130, y=60, w=150, h=30, options = { "自动获取", "手动设置" } })

    -- 手动IP输入（初始隐藏，但此处为简化，一直显示）
    ip_input = airui.textarea({ parent = content, x=130, y=100, w=150, h=30, placeholder = "IP地址" })
    mask_input = airui.textarea({ parent = content, x=130, y=140, w=150, h=30, placeholder = "子网掩码" })
    gw_input = airui.textarea({ parent = content, x=130, y=180, w=150, h=30, placeholder = "网关" })
    dns_input = airui.textarea({ parent = content, x=130, y=220, w=150, h=30, placeholder = "DNS" })

    -- 保存按钮
    airui.button({
        parent = content, x=350, y=200, w=80, h=40,
        text = "保存",
        on_click = function()
            -- TODO: 应用以太网配置
            log.info("eth", "保存配置")
        end
    })
end

function ethernet_win.on_create(id)
    win_id = id
    create_ui()
    -- 加载已保存配置
end

function ethernet_win.on_destroy(id)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

function ethernet_win.on_get_focus(id)
    -- 刷新
end

function ethernet_win.on_lose_focus(id)
    -- 暂停
end

local function open_handler()
    exwin.open({
        on_create = ethernet_win.on_create,
        on_destroy = ethernet_win.on_destroy,
        on_get_focus = ethernet_win.on_get_focus,
        on_lose_focus = ethernet_win.on_lose_focus,
    })
end
sys.subscribe("OPEN_ETHERNET_WIN", open_handler)

return ethernet_win