-- lua - WiFi页面

local win_id = nil
local main_container, content, scan_list, connect_btn

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })
    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="WiFi", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 扫描按钮
    airui.button({
        parent = content, x=190, y=10, w=100, h=30,
        text = "扫描",
        on_click = function() log.info("wifi", "扫描") end
    })

    -- WiFi列表
    scan_list = airui.table({
        parent = content, x=10, y=50, w=460, h=150,
        rows = 5, cols = 2, col_width = {300, 100}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "ChinaNet-123")
    scan_list:set_cell_text(0, 1, "-45dBm")

    -- 连接按钮
    connect_btn = airui.button({
        parent = content, x=190, y=210, w=100, h=40,
        text = "连接",
        on_click = function() log.info("wifi", "连接") end
    })

    -- 密码输入
    airui.textarea({ parent = content, x=10, y=210, w=150, h=30, placeholder = "密码" })
end

local function on_create()
    
    create_ui()
    -- 可在此启动定时器、订阅等
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    -- 停止定时器、取消订阅等
end

local function on_get_focus()
    -- 获得焦点时可刷新UI
    -- 例如更新列表
end

local function on_lose_focus()
    -- 失去焦点时可暂停某些操作
end

-- 订阅打开WiFi页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_WIFI_WIN", open_handler)