-- camera_win.lua - 摄像头页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 36, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "摄像头", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    airui.label({ parent = content, x = 0, y = 200, w = 1024, h = 60, text = "摄像头功能", font_size = 48, color = 0x333333, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = content, x = 0, y = 270, w = 1024, h = 40, text = "支持USB摄像头", font_size = 30, color = 0x666666, align = airui.TEXT_ALIGN_CENTER })

    -- 拍照按钮
    airui.button({ 
        parent = content, x = 450, y = 350, w = 150, h = 60, 
        text = "拍照", 
        color = 0x2196F3, 
        text_color = 0xffffff, 
        font_size = 48,
        on_click = function()
            log.info("camera", "拍照")
            -- 这里可以添加拍照的逻辑
        end
    })
end

local function on_create()
    win_id = create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

sys.subscribe("OPEN_CAMERA_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
    end
end)
