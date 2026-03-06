-- IoT账户页面
local iot_account_page = {}

local main_container, content
local server_input, user_input, pass_input
local login_btn

function iot_account_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="IoT账户", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

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

function iot_account_page.init()
    iot_account_page.create_ui()
    -- TODO: 加载已保存的配置
end

function iot_account_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
    -- 断开MQTT连接等
end

return iot_account_page