--[[
@module  iot_account_win
@summary IoT账户配置页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为IoT账户配置页面，可设置服务器地址、账号、密码，并提供登录、上传数据、获取历史按钮。
订阅"OPEN_IOT_ACCOUNT_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local server_input, user_input, pass_input
local login_btn

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、输入框和操作按钮
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

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="IoT账户", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 服务器地址
    airui.label({ parent = content, x=20, y=20, w=100, h=30, text="服务器:", font_size=18, color=0x000000 })
    server_input = airui.textarea({ parent = content, x=130, y=20, w=200, h=30, placeholder = "mqtt://iot.com" })

    -- 账号
    airui.label({ parent = content, x=20, y=60, w=100, h=30, text="账号:", font_size=18, color=0x000000 })
    user_input = airui.textarea({ parent = content, x=130, y=60, w=200, h=30, placeholder = "username" })

    -- 密码
    airui.label({ parent = content, x=20, y=100, w=100, h=30, text="密码:", font_size=18, color=0x000000 })
    pass_input = airui.textarea({ parent = content, x=130, y=100, w=200, h=30, placeholder = "password" })

    -- 登录按钮
    login_btn = airui.button({
        parent = content, x=190, y=150, w=100, h=40,
        text = "登录",
        on_click = function()
            local server = server_input:get_text()
            local user = user_input:get_text()
            local pass = pass_input:get_text()
            -- TODO: 发起MQTT连接
            log.info("iot", "登录", server, user, pass)
        end
    })

    -- 上传数据按钮
    airui.button({
        parent = content, x=50, y=200, w=120, h=40,
        text = "上传数据",
        on_click = function()
            -- TODO: 上传当前传感器数据
            log.info("iot", "上传数据")
        end
    })

    -- 获取历史数据按钮
    airui.button({
        parent = content, x=200, y=200, w=120, h=40,
        text = "获取历史",
        on_click = function()
            -- TODO: 请求云端历史数据
            log.info("iot", "获取历史")
        end
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并加载已保存配置
]]
local function on_create()
    
    create_ui()
    -- TODO: 加载已保存的配置
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，断开MQTT连接等
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 断开MQTT连接等
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 刷新
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 暂停可能的上传
end

-- 订阅打开IoT账户页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_IOT_ACCOUNT_WIN", open_handler)