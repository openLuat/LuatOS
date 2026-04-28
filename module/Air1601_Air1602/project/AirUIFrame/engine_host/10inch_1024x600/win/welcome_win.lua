--[[
@module  welcome_win
@summary 开机欢迎页面模块
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container
local screen_w, screen_h

local function create_ui()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_h, screen_w = phys_w, phys_h
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0x3F51B5
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = screen_h/2,          -- 垂直居中
        w = screen_w,
        h = 80,
        text = "欢迎使用合宙Air8101 UI畅玩板",
        font_size = 28,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_welcome_timeout()
    if win_id then
        exwin.close(win_id)
    end
    sys.publish("OPEN_IDLE_WIN")
end

local function on_create()
    create_ui()
    sys.timerStart(on_welcome_timeout, 3000)
end

local function on_destroy()
    sys.timerStop(on_welcome_timeout)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_welcome_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_WELCOME_WIN", open_welcome_handler)