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

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、预览区域和拍照按钮
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="拍照", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

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

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并初始化摄像头（TODO）
]]
local function on_create()
    
    create_ui()
    -- TODO: 初始化摄像头
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，释放摄像头资源
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 释放摄像头资源
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 恢复预览
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 暂停预览
end

-- 订阅打开拍照页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_CAMERA_WIN", open_handler)