-- network_select_win.lua - 网络选择页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 36, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 350, y = 10, w = 324, h = 40, text = "多网融合", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    airui.label({ parent = content, x = 0, y = 40, w = 1024, h = 60, text = "网络连接方式", font_size = 32, color = 0x333333, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = content, x = 0, y = 110, w = 1024, h = 40, text = "当前网络: AirLink (连接Air780EPM)", font_size = 20, color = 0x666666, align = airui.TEXT_ALIGN_CENTER })

    local function create_network_option(x, y, title, desc, icon, callback)
        local option = airui.container({ parent = content, x = x, y = y, w = 300, h = 180, color = 0xffffff, radius = 10 })
        airui.image({ parent = option, x = 20, y = 20, w = 60, h = 60, src = icon })
        airui.label({ parent = option, x = 100, y = 20, w = 180, h = 40, text = title, font_size = 30, color = 0x000000 })
        airui.label({ parent = option, x = 100, y = 60, w = 180, h = 60, text = desc, font_size = 20, color = 0x666666 })
        airui.button({ parent = option, x = 60, y = 130, w = 180, h = 40, text = "选择", on_click = callback })
        return option
    end

    create_network_option(31, 180, "4G (AirLink)", "通过Air780EPM实现4G联网", "/luadb/4Gxinhao4.png", function()
        log.info("network", "选择4G网络")
        -- 这里可以添加切换到4G网络的逻辑
    end)

    create_network_option(362, 180, "以太网", "通过CH390H实现以太网联网", "/luadb/yitaiwang.png", function()
        log.info("network", "选择以太网")
        -- 这里可以添加切换到以太网的逻辑
    end)

    create_network_option(693, 180, "WiFi", "通过Air6205模块实现无线网络", "/luadb/wifi.png", function()
        log.info("network", "选择WiFi")
        -- 这里可以添加切换到WiFi的逻辑
    end)

    airui.button({ parent = content, x = 400, y = 420, w = 224, h = 60, text = "刷新网络状态", on_click = function()
        log.info("network", "刷新网络状态")
    end})
end

local function on_create()
    win_id = create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

sys.subscribe("OPEN_NETWORK_SELECT_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
    end
end)
