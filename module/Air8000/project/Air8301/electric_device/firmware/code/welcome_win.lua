--[[
@module  welcome_win
@summary 开机欢迎页面模块
@version 1.0
@date    2026.08.23
@author  嵌入式软件设计开发代理
@usage
本模块为开机欢迎页面，显示欢迎文字，1秒后自动切换到主界面（home_win）。
订阅"OPEN_WELCOME_WIN"事件打开窗口。
]]

local win_id = nil
local main_container

--[[
创建 UI：全屏显示纯色背景 + 文字

@local
@function create_ui
@return nil
]]
local function create_ui()
    -- 使用全屏容器，背景色可自定义
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0xE3F2FD -- 浅蓝色背景（浅色主题）
    })

    -- 主标题（480x272 下两行文字整体垂直居中）
    airui.label({
        parent = main_container,
        x = 0,
        y = 95,
        w = 480,
        h = 40,
        text = "智控电场发生器通讯控制板",
        font_size = 24,
        color = 0x0D47A1, -- 深蓝色文字（浅色背景下清晰）
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 副标题
    airui.label({
        parent = main_container,
        x = 0,
        y = 145,
        w = 480,
        h = 30,
        text = "正在初始化，请稍候...",
        font_size = 16,
        color = 0x666666, -- 深灰副标题
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
定时器回调：打开首页并关闭自己

@local
@function on_welcome_timeout
@return nil
]]
local function on_welcome_timeout()
    -- 关闭开机画面窗口
    if win_id then
        exwin.close(win_id)
    end
    -- 发布打开首页的消息（home_win 订阅了 OPEN_HOME_WIN）
    sys.publish("OPEN_HOME_WIN")
end

--[[
窗口创建回调

@local
@function on_create
@return nil
]]
local function on_create()
    log.info("welcome_win", "打开欢迎窗口")
    create_ui()
    -- 启动一个定时器，1秒后切换到首页
    sys.timerStart(on_welcome_timeout, 1000)
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
]]
local function on_destroy()
    sys.timerStop(on_welcome_timeout)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- 可选：获得焦点/失去焦点时不做特殊处理
local function on_get_focus() end

local function on_lose_focus() end

--[[
订阅打开开机画面的消息

@local
@function open_welcome_handler
@return nil
]]
local function open_welcome_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_WELCOME_WIN", open_welcome_handler)
