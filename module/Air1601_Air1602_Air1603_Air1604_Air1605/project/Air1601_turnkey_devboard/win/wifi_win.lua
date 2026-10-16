-- wifi_win.lua - WiFi页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container, content, scan_list, connect_btn

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "WiFi", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 扫描按钮
    airui.button({
        parent = content, x = 450, y = 20, w = 150, h = 50,
        text = "扫描",
        on_click = function() log.info("wifi", "扫描") end
    })

    -- WiFi列表
    scan_list = airui.table({
        parent = content, x = 100, y = 100, w = 824, h = 300,
        rows = 5, cols = 2, col_width = {600, 200}, border_color = 0xcccccc
    })
    scan_list:set_cell_text(0, 0, "降功耗,找合宙!")
    scan_list:set_cell_text(0, 1, "-45dBm")

    -- 密码输入
    airui.textarea({ parent = content, x = 250, y = 450, w = 300, h = 50, placeholder = "密码" })

    -- 连接按钮
    connect_btn = airui.button({
        parent = content, x = 570, y = 450, w = 150, h = 50,
        text = "连接",
        on_click = function() log.info("wifi", "连接") end
    })
end

local function on_create()
    win_id = create_ui()
    -- 可在此启动定时器、订阅等
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
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
sys.subscribe("OPEN_WIFI_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_lose_focus = on_lose_focus,
            on_get_focus = on_get_focus
        })
    end
end)
