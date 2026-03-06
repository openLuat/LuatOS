-- 联网选择页面
local network_select_page = {}

local main_container, content
local priority_dropdown

function network_select_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="联网选择", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 优先级下拉框
    airui.label({ parent = content, x=20, y=20, w=150, h=30, text="联网优先级:", font_size=18, color=0x000000 })
    priority_dropdown = airui.dropdown({
        parent = content, x=180, y=20, w=150, h=30,
        options = { "4G优先", "WiFi优先", "以太网优先" },
        default_index = 0,
        on_change = function(self, idx)
            -- TODO: 保存设置，并通知网络管理模块
            log.info("network", "优先级设为", idx)
        end
    })

    -- 保存按钮
    airui.button({
        parent = content, x=190, y=200, w=100, h=40,
        text = "保存",
        on_click = function()
            -- TODO: 应用网络优先级
            log.info("network", "保存设置")
        end
    })
end

function network_select_page.init()
    network_select_page.create_ui()
    -- TODO: 读取当前设置，初始化下拉框
end

function network_select_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
end

return network_select_page