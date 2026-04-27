-- bluetooth_win.lua - 蓝牙页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container, content
local scan_list, scan_btn

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "蓝牙", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 扫描按钮
    scan_btn = airui.button({
        parent = content, x = 450, y = 20, w = 150, h = 50,
        text = "扫描",
        on_click = function()
            -- TODO: 开始扫描蓝牙设备
            log.info("bluetooth", "扫描")
        end
    })

    -- 设备列表（简单表格）
    scan_list = airui.table({
        parent = content, x = 100, y = 100, w = 824, h = 300,
        rows = 5, cols = 2,
        col_width = {400, 400},
        border_color = 0xcccccc,
        font_size = 24
    })
    -- 示例填充
    scan_list:set_cell_text(0, 0, "设备1")
    scan_list:set_cell_text(0, 1, "信号")
end

local function on_create()
    win_id = create_ui()
    -- TODO: 初始化蓝牙
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 停止扫描等
end

local function on_get_focus()
    -- 刷新列表等
end

local function on_lose_focus()
    -- 暂停扫描
end

sys.subscribe("OPEN_BLUETOOTH_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
    end
end)
