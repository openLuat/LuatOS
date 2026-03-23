-- welcome_win.lua - 开机欢迎页面(Air1601版本，适配1024x600分辨率)

local win_id = nil

local function create_ui()
    -- 创建主容器
    local container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = 1024, h = 600,
        color = 0x000000
    })

    -- 标题
    airui.label({
        parent = container,
        x = 0, y = 180,
        w = 1024, h = 80,
        text = "Air1601 Turnkey Devboard",
        font_size = 48,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 副标题
    airui.label({
        parent = container,
        x = 0, y = 280,
        w = 1024, h = 40,
        text = "欢迎使用",
        font_size = 24,
        color = 0xAAAAAA,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 版本信息
    airui.label({
        parent = container,
        x = 0, y = 500,
        w = 1024, h = 30,
        text = "Version: " .. VERSION,
        font_size = 16,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    return container
end

local container = nil

local function on_create()
    container = create_ui()
    -- 3秒后自动跳转到Idle页面
    sys.timerStart(function()
        if win_id then
            exwin.close(win_id)
            win_id = nil
        end
        sys.publish("OPEN_IDLE_WIN")
    end, 3000)
end

local function on_destroy()
    if container then
        container:destroy()
        container = nil
    end
    win_id = nil
end

sys.subscribe("OPEN_WELCOME_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
        })
    end
end)
