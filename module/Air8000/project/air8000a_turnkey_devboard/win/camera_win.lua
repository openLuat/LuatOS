-- 拍照页面
local camera_win = {}
local exwin = require "exwin"

local win_id = nil
local main_container, content
local preview_img

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="拍照", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 预览区域（实际应显示摄像头图像）
    preview_img = airui.image({
        parent = content, x=40, y=10, w=400, h=180,
        src = "/luadb/camera_preview.jpg" -- 占位图
    })

    -- 拍照按钮
    airui.button({
        parent = content, x=190, y=200, w=100, h=40,
        text = "拍照",
        on_click = function()
            -- TODO: 调用摄像头拍照，保存图片，可能上传
            log.info("camera", "拍照")
        end
    })
end

function camera_win.on_create(id)
    win_id = id
    create_ui()
    -- TODO: 初始化摄像头
end

function camera_win.on_destroy(id)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 释放摄像头资源
end

function camera_win.on_get_focus(id)
    -- 恢复预览
end

function camera_win.on_lose_focus(id)
    -- 暂停预览
end

local function open_handler()
    exwin.open({
        on_create = camera_win.on_create,
        on_destroy = camera_win.on_destroy,
        on_get_focus = camera_win.on_get_focus,
        on_lose_focus = camera_win.on_lose_focus,
    })
end
sys.subscribe("OPEN_CAMERA_WIN", open_handler)

return camera_win