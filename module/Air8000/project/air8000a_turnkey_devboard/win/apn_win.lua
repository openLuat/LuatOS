-- APN配置页面

local win_id = nil
local main_container, content
local apn_input, user_input, pass_input

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn = airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5, text = "返回",
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="APN配置", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- APN
    airui.label({ parent = content, x=20, y=30, w=80, h=30, text="APN:", font_size=18, color=0x000000 })
    apn_input = airui.textarea({ parent = content, x=120, y=30, w=200, h=30, placeholder = "cmnet" })

    -- 账号
    airui.label({ parent = content, x=20, y=80, w=80, h=30, text="账号:", font_size=18, color=0x000000 })
    user_input = airui.textarea({ parent = content, x=120, y=80, w=200, h=30, placeholder = "optional" })

    -- 密码
    airui.label({ parent = content, x=20, y=130, w=80, h=30, text="密码:", font_size=18, color=0x000000 })
    pass_input = airui.textarea({ parent = content, x=120, y=130, w=200, h=30, placeholder = "optional" })

    -- 保存按钮
    airui.button({
        parent = content, x=190, y=190, w=100, h=40,
        text = "保存",
        on_click = function()
            -- TODO: 保存APN设置并应用到4G模块
            log.info("apn", "保存", apn_input:get_text())
        end
    })
end

function apn_win_on_create()
    
    create_ui()
    -- 可加载已保存的APN
    -- 例如: local saved = settings.get("apn")
end

function apn_win_on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

function apn_win_on_get_focus()
    -- 获得焦点时可刷新数据
end

function apn_win_on_lose_focus()
    -- 失去焦点时可暂停操作
end

-- 订阅打开APN配置页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = apn_win_on_create,
        on_destroy = apn_win_on_destroy,
        on_get_focus = apn_win_on_get_focus,
        on_lose_focus = apn_win_on_lose_focus,
    })
end
sys.subscribe("OPEN_APN_WIN", open_handler)