--[[
@module  settings_win
@summary 设置界面窗口模块（WiFi设置 / 服务器设置菜单）
@version 1.0
@date    2026.08.26
@author  嵌入式软件设计开发代理
@usage
本模块为设置界面（settings_win），提供两个设置入口：
1、WiFi设置：进入 WiFi 设置界面（wifi_win），功能与原有 WiFi 设置保持一致；
2、服务器设置：进入服务器设置界面（server_win），支持默认AirCloud / 自定义TCP服务器单选配置（fskv 持久化）。

订阅消息：
- "OPEN_SETTINGS_WIN"    -- 打开设置窗口

发布消息：
- "OPEN_WIFI_WIN"        -- 打开 WiFi 设置窗口
- "OPEN_SERVER_WIN"      -- 打开服务器设置窗口
- "OPEN_HOME_WIN"        -- 返回主界面
]]

local win_id = nil
local main_container = nil

--[[
返回按钮回调：关闭设置窗口并打开主界面

@local
@function on_back
@return nil
]]
local function on_back()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    sys.publish("OPEN_HOME_WIN")
end

--[[
WiFi设置菜单点击回调：关闭设置窗口并打开 WiFi 设置界面

@local
@function on_wifi_menu_click
@return nil
]]
local function on_wifi_menu_click()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    sys.publish("OPEN_WIFI_WIN")
end

--[[
服务器设置菜单点击回调：关闭设置窗口并打开服务器设置界面

@local
@function on_server_menu_click
@return nil
]]
local function on_server_menu_click()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    sys.publish("OPEN_SERVER_WIN")
end

--[[
创建 UI：设置界面布局（480x272）

@local
@function create_ui
@return nil
]]
local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0xFFFFFF -- 白色背景（浅色主题）
    })
    -- 标题栏（浅蓝色）
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 45,
        color = 0x64B5F6
    })
    airui.button({
        parent = title_bar,
        x = 10,
        y = 8,
        w = 50,
        h = 30,
        text = "←",
        font_size = 18,
        style = {
            bg_color = 0xFFFFFF,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_back
    })
    airui.label({
        parent = title_bar,
        x = 60,
        y = 10,
        w = 360,
        h = 25,
        text = "设 置",
        font_size = 20,
        color = 0x0D47A1,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 菜单项：WiFi设置（功能与原有 WiFi 设置一致；480x272 下居中排列；浅蓝底深蓝字卡片风格）
    airui.button({
        parent = main_container,
        x = 20,
        y = 65,
        w = 440,
        h = 60,
        text = "WiFi设置",
        font_size = 16,
        style = {
            bg_color = 0xE3F2FD,
            text_color = 0x1565C0,
            radius = 8,
        },
        on_click = on_wifi_menu_click
    })
    -- 菜单项：服务器设置
    airui.button({
        parent = main_container,
        x = 20,
        y = 140,
        w = 440,
        h = 60,
        text = "服务器设置",
        font_size = 16,
        style = {
            bg_color = 0xE3F2FD,
            text_color = 0x1565C0,
            radius = 8,
        },
        on_click = on_server_menu_click
    })
    -- 底部说明
    airui.label({
        parent = main_container,
        x = 20,
        y = 220,
        w = 440,
        h = 16,
        text = "服务器设置: 默认AirCloud / 自定义TCP服务器",
        font_size = 12,
        color = 0x8C8C8C,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
]]
local function on_create()
    log.info("settings_win", "打开设置窗口")
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

--[[
打开设置窗口

@local
@function open_settings_win
@return nil
]]
local function open_settings_win()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end
sys.subscribe("OPEN_SETTINGS_WIN", open_settings_win)
