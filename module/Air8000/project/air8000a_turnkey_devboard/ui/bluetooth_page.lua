-- 蓝牙页面
local bluetooth_page = {}

local main_container, content
local scan_list, scan_btn

function bluetooth_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="蓝牙", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 扫描按钮
    scan_btn = airui.button({
        parent = content, x=190, y=10, w=100, h=40,
        text = "扫描",
        on_click = function()
            -- TODO: 开始扫描蓝牙设备
            log.info("bluetooth", "扫描")
        end
    })

    -- 设备列表（简单表格）
    scan_list = airui.table({
        parent = content, x=10, y=60, w=460, h=150,
        rows = 5, cols = 2,
        col_width = {200, 200},
        border_color = 0xcccccc
    })
    -- 示例填充
    scan_list:set_cell_text(0, 0, "设备1")
    scan_list:set_cell_text(0, 1, "信号")
    -- 更多操作...
end

function bluetooth_page.init()
    bluetooth_page.create_ui()
    -- TODO: 初始化蓝牙
end

function bluetooth_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
end

return bluetooth_page