-- WiFi页面
local wifi_page = {}

local main_container, content
local scan_list, connect_btn

function wifi_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 扫描按钮
    airui.button({
        parent = content, x=190, y=10, w=100, h=30,
        text = "扫描",
        on_click = function()
            -- TODO: 扫描WiFi
            log.info("wifi", "扫描")
        end
    })

    -- WiFi列表
    scan_list = airui.table({
        parent = content, x=10, y=50, w=460, h=150,
        rows = 5, cols = 2,
        col_width = {300, 100},
        border_color = 0xcccccc
    })
    -- 示例填充
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    -- 连接按钮
    connect_btn = airui.button({
        parent = content, x=190, y=210, w=100, h=40,
        text = "连接",
        on_click = function()
            -- TODO: 连接选中的WiFi
            log.info("wifi", "连接")
        end
    })

    -- 密码输入
    local pass_input = airui.textarea({
        parent = content, x=10, y=210, w=150, h=30,
        placeholder = "密码"
    })
end

function wifi_page.init()
    wifi_page.create_ui()
    -- TODO: 自动连接已保存网络
end

function wifi_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
end

return wifi_page