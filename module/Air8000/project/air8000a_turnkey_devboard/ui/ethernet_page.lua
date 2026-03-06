-- 以太网页面
local ethernet_page = {}

local main_container, content
local ip_mode_dropdown, ip_input, mask_input, gw_input, dns_input

function ethernet_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="以太网", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 网口类型
    airui.label({ parent = content, x=20, y=20, w=100, h=30, text="网口类型:", font_size=16, color=0x000000 })
    local type_drop = airui.dropdown({ parent = content, x=130, y=20, w=150, h=30, options = { "WAN", "LAN" } })

    -- IP模式
    airui.label({ parent = content, x=20, y=60, w=100, h=30, text="IP模式:", font_size=16, color=0x000000 })
    ip_mode_dropdown = airui.dropdown({ parent = content, x=130, y=60, w=150, h=30, options = { "自动获取", "手动设置" } })

    -- 手动IP输入（初始隐藏）
    ip_input = airui.textarea({ parent = content, x=130, y=100, w=150, h=30, placeholder = "IP地址" })
    mask_input = airui.textarea({ parent = content, x=130, y=140, w=150, h=30, placeholder = "子网掩码" })
    gw_input = airui.textarea({ parent = content, x=130, y=180, w=150, h=30, placeholder = "网关" })
    dns_input = airui.textarea({ parent = content, x=130, y=220, w=150, h=30, placeholder = "DNS" })

    -- 根据模式显示/隐藏
    ip_mode_dropdown:set_on_change(function(self, idx)
        local visible = (idx == 1)  -- 手动设置时显示
        -- 假设有 set_hidden 方法
        -- ip_input:set_hidden(not visible)
        -- ...
    end)

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

function ethernet_page.init()
    ethernet_page.create_ui()
end

function ethernet_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
end

return ethernet_page