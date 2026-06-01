--[[
@module  camera_win
@summary 拍照页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为拍照功能页面，显示摄像头预览并提供拍照按钮。
订阅"OPEN_CAMERA_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local preview_img

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="拍照", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    preview_img = airui.image({
        parent = content, x=100, y=20, w=600, h=280,
        src = "/luadb/camera_preview.jpg"
    })

    airui.button({
        parent = content, x=340, y=320, w=120, h=50,
        text = "拍照",
        font_size = 20,
        on_click = function()
            log.info("camera", "拍照")
        end
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_CAMERA_WIN", open_handler)