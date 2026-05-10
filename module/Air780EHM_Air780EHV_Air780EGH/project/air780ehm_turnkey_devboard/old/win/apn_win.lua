--[[
@module  apn_win
@summary APN配置页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为APN配置页面，允许用户设置APN、账号、密码并保存。
订阅"OPEN_APN_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local apn_input, user_input, pass_input

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、输入框和保存按钮
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text = "APN配置", font_size = 24, color = 0xffffff })

    content = airui.container({ parent = main_container, x = 0, y = 40, w = 480, h = 280, color = 0xF3F4F6 })

    content = airui.container({ parent = main_container, x = 0, y = 50, w = 480, h = 270, color = 0xF3F4F6 })

    -- APN
    airui.label({ parent = content, x = 20, y = 30, w = 80, h = 30, text = "APN:", font_size = 18, color = 0x000000 })
    apn_input = airui.textarea({ parent = content, x = 120, y = 30, w = 200, h = 30, placeholder = "cmnet" })

    -- 账号
    airui.label({ parent = content, x = 20, y = 80, w = 80, h = 30, text = "账号:", font_size = 18, color = 0x000000 })
    user_input = airui.textarea({ parent = content, x = 120, y = 80, w = 200, h = 30, placeholder = "optional" })

    -- 密码
    airui.label({ parent = content, x = 20, y = 130, w = 80, h = 30, text = "密码:", font_size = 18, color = 0x000000 })
    pass_input = airui.textarea({ parent = content, x = 120, y = 130, w = 200, h = 30, placeholder = "optional" })

    -- 保存按钮
    airui.button({
        parent = content,
        x = 190,
        y = 190,
        w = 100,
        h = 40,
        text = "保存",
        on_click = function()
            -- TODO: 保存APN设置并应用到4G模块
            log.info("apn", "保存", apn_input:get_text())
        end
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并加载已保存配置（TODO）
]]
local function on_create()
    create_ui()
    -- 可加载已保存的APN
    -- 例如: local saved = settings.get("apn")
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，释放资源
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 获得焦点时可刷新数据
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 失去焦点时可暂停操作
end

-- 订阅打开APN配置页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_APN_WIN", open_handler)