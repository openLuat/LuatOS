--[[
@module  network_select_win
@summary 联网选择页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为联网选择页面，可设置联网优先级（4G/WiFi/以太网）并保存。
订阅"OPEN_NETWORK_SELECT_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local priority_dropdown

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、优先级下拉框和保存按钮
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

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="联网选择", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 优先级下拉框
    airui.label({ parent = content, x=20, y=20, w=150, h=30, text="联网优先级:", font_size=18, color=0x000000 })
    priority_dropdown = airui.dropdown({
        parent = content, x=180, y=20, w=150, h=30,
        options = { "4G优先", "WiFi优先", "以太网优先" },
        default_index = 0,
        on_change = function(self, idx)
            -- TODO: 保存设置，并通知网络管理模块
            log.info("network", "优先级设为", idx)
        end
    })

    -- 保存按钮
    airui.button({
        parent = content, x=190, y=200, w=100, h=40,
        text = "保存",
        on_click = function()
            -- TODO: 应用网络优先级
            log.info("network", "保存设置")
        end
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并加载当前设置
]]
local function on_create()
    
    create_ui()
    -- TODO: 读取当前设置，初始化下拉框
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
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 刷新
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 暂停
end

-- 订阅打开联网选择页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_NETWORK_SELECT_WIN", open_handler)