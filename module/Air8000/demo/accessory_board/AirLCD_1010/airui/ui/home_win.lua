--[[
@module  home_win
@summary AirUI演示系统主窗口
@version 1.1.0
@date    2026.03.17
@author  江访
@usage
本文件是AirUI演示系统的主窗口，采用exwin窗口管理扩展库。
提供所有功能演示的入口，通过消息机制打开其他窗口。
]]


-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container = nil
local scroll_container = nil

-- 演示模块列表
local demos = {
    -- AirUI组件演示
    { name = "所有组件演示", icon = airui.SYMBOL_OK, win = "all_component", color = 0x007AFF },
    { name = "标签组件", icon = airui.SYMBOL_REFRESH, win = "label", color = 0x4CAF50 },
    { name = "按钮组件", icon = airui.SYMBOL_LOOP, win = "button", color = 0xF44336 },
    { name = "容器组件", icon = airui.SYMBOL_SD_CARD, win = "container", color = 0xFF9800 },
    { name = "进度条组件", icon = airui.SYMBOL_SHUFFLE, win = "bar", color = 0x9C27B0 },
    { name = "开关组件", icon = airui.SYMBOL_COPY, win = "switch", color = 0x00BCD4 },
    { name = "下拉框组件", icon = airui.SYMBOL_DOWN, win = "dropdown", color = 0x795548 },
    { name = "表格组件", icon = airui.SYMBOL_LIST, win = "table", color = 0x607D8B },
    { name = "输入框组件", icon = airui.SYMBOL_KEYBOARD, win = "input", color = 0x3F51B5 },
    { name = "消息框组件", icon = airui.SYMBOL_CALL, win = "msgbox", color = 0xE91E63 },
    { name = "图片组件", icon = airui.SYMBOL_IMAGE, win = "image", color = 0x8BC34A },
    { name = "选项卡组件", icon = airui.SYMBOL_PASTE, win = "tabview", color = 0xFF5722 },
    { name = "曲线图演示", icon = airui.SYMBOL_EDIT, win = "chart", color = 0x007AFF },
    { name = "窗口组件", icon = airui.SYMBOL_BELL, win = "win", color = 0x009688 },
    { name = "窗口切换演示", icon = airui.SYMBOL_LEFT, win = "switch_demo", color = 0x673AB7 },
    { name = "矢量字体演示", icon = airui.SYMBOL_EYE_OPEN, win = "hzfont", color = 0x2196F3 },
    { name = "俄罗斯方块游戏", icon = airui.SYMBOL_WARNING, win = "game", color = 0xFF4081 },
    { name = "二维码演示", icon = airui.SYMBOL_IMAGE, win = "qrcode", color = 0x673AB7 },
}

-- 创建主窗口UI
local function create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF8F9FA,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x007AFF,
    })

    airui.label({
        parent = title_bar,
        text = "AirUI演示系统 (exwin)",
        x = 10,
        y = 20,
        w = 300,
        h = 30,
    })

    -- 滚动容器
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 360,
        color = 0xF8F9FA,
    })

    -- 创建网格布局的演示按钮
    local button_width = 140
    local button_height = 70
    local columns = 2
    local padding = 10
    local y_offset = 0

    for i, demo in ipairs(demos) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)

        local x = padding + col * (button_width + padding)
        local y = y_offset + row * (button_height + padding)

        -- 创建按钮容器（卡片样式）
        local card = airui.container({
            parent = scroll_container,
            x = x,
            y = y,
            w = button_width,
            h = button_height,
            color = demo.color,
            radius = 8,
            on_click = function()
                -- 发布打开对应窗口的消息
                local msg_name = "OPEN_" .. string.upper(demo.win) .. "_WIN"
                sys.publish(msg_name)
                log.info("home_win", "发布消息:", msg_name)
            end
        })

        -- 图标标签
        airui.label({
            parent = card,
            text = demo.icon,
            x = 10,
            y = 15,
            w = 30,
            h = 50,
        })

        -- 演示名称标签
        airui.label({
            parent = card,
            text = demo.name,
            x = 50,
            y = 15,
            w = button_width - 60,
            h = 50,
        })
    end

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 440,
        w = 320,
        h = 40,
        color = 0xCFCFCF,
    })

    airui.label({
        parent = status_bar,
        text = string.format("共%d个演示 - AirUI v1.1.0", #demos),
        x = 10,
        y = 12,
        w = 300,
        h = 16,
    })
end

-- 窗口创建回调
local function on_create()
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    -- 清理UI元素
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    scroll_container = nil
    win_id = nil
    log.info("home_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("home_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("home_win", "窗口失去焦点")
end

-- 订阅打开主窗口消息
sys.subscribe("OPEN_HOME_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("home_win", "窗口打开，ID:", win_id)
    end
end)
