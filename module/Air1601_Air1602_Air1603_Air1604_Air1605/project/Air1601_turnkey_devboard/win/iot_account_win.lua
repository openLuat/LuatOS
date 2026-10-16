-- IoT账户页面

local win_id = nil
local main_container, content
local server_input, user_input, pass_input
local login_btn

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "IoT账户", font_size = 36, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 服务器地址
    airui.label({ parent = content, x = 100, y = 80, w = 200, h = 50, text = "服务器:", font_size = 32, color = 0x000000 })
    server_input = airui.textarea({ parent = content, x = 300, y = 80, w = 624, h = 60, placeholder = "mqtt://iot.com", font_size = 28 })

    -- 账号
    airui.label({ parent = content, x = 100, y = 160, w = 200, h = 50, text = "账号:", font_size = 32, color = 0x000000 })
    user_input = airui.textarea({ parent = content, x = 300, y = 160, w = 624, h = 60, placeholder = "username", font_size = 28 })

    -- 密码
    airui.label({ parent = content, x = 100, y = 240, w = 200, h = 50, text = "密码:", font_size = 32, color = 0x000000 })
    pass_input = airui.textarea({ parent = content, x = 300, y = 240, w = 624, h = 60, placeholder = "password", font_size = 28 })

    -- 登录按钮
    login_btn = airui.button({
        parent = content, x = 450, y = 320, w = 150, h = 60,
        text = "登录",
        font_size = 24,
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
        parent = content, x = 300, y = 400, w = 200, h = 60,
        text = "上传数据",
        font_size = 24,
        on_click = function()
            -- TODO: 上传当前传感器数据
            log.info("iot", "上传数据")
        end
    })

    -- 获取历史数据按钮
    airui.button({
        parent = content, x = 524, y = 400, w = 200, h = 60,
        text = "获取历史",
        font_size = 24,
        on_click = function()
            -- TODO: 请求云端历史数据
            log.info("iot", "获取历史")
        end
    })
end

local function on_create()
    
    create_ui()
    -- TODO: 加载已保存的配置
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 断开MQTT连接等
end

local function on_get_focus()
    -- 刷新
end

local function on_lose_focus()
    -- 暂停可能的上传
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_IOT_ACCOUNT_WIN", open_handler)