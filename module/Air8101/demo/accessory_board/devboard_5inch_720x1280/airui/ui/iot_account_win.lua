-- iot_account_win.lua
--[[
@module  iot_account_win
@summary IoT账户配置页面模块
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container, content
local server_input, user_input, pass_input
local login_btn

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=720, h=1280, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=720, h=80, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 630, y = 20, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 8, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 0, y = 20, w = 720, h = 48, align = airui.TEXT_ALIGN_CENTER, text="IoT账户", font_size=36, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=80, w=720, h=1120, color=0xF3F4F6 })

    airui.label({ parent = content, x=30, y=80, w=120, h=48, text="服务器:", font_size=28, color=0x000000 })
    server_input = airui.textarea({ parent = content, x=160, y=80, w=520, h=48, placeholder = "mqtt://iot.com", font_size=24 })

    airui.label({ parent = content, x=30, y=160, w=120, h=48, text="账号:", font_size=28, color=0x000000 })
    user_input = airui.textarea({ parent = content, x=160, y=160, w=520, h=48, placeholder = "username", font_size=24 })

    airui.label({ parent = content, x=30, y=240, w=120, h=48, text="密码:", font_size=28, color=0x000000 })
    pass_input = airui.textarea({ parent = content, x=160, y=240, w=520, h=48, placeholder = "password", font_size=24 })

    login_btn = airui.button({
        parent = content, x=300, y=340, w=120, h=56,
        text = "登录",
        font_size = 24,
        on_click = function()
            local server = server_input:get_text()
            local user = user_input:get_text()
            local pass = pass_input:get_text()
            log.info("iot", "登录", server, user, pass)
        end
    })

    airui.button({
        parent = content, x=180, y=440, w=160, h=56,
        text = "上传数据",
        font_size = 24,
        on_click = function()
            log.info("iot", "上传数据")
        end
    })

    airui.button({
        parent = content, x=380, y=440, w=160, h=56,
        text = "获取历史",
        font_size = 24,
        on_click = function()
            log.info("iot", "获取历史")
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
sys.subscribe("OPEN_IOT_ACCOUNT_WIN", open_handler)