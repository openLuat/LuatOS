--[[
@module  win_sub_1
@summary 子窗口1（红色），仅包含关闭按钮，关闭后主窗口自动显示
@version 1.0.0
@date    2026.06.03
@author  合宙
@usage
本文件为子窗口1业务逻辑模块，核心功能为：
1、订阅 "OPEN_SUB_WIN_1" 消息，收到消息后创建红色子窗口
2、窗口内仅包含一个关闭按钮
3、点击关闭按钮关闭当前窗口，主窗口自动显示（图层式，上层关闭下层可见）
]]

local WIN_COLOR = 0xFF0000  -- 红色

local win_id = nil
local main_container = nil

local function on_click_close()
    exwin.close(win_id)
end

local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = WIN_COLOR
    })

    -- 窗口标题
    airui.label({
        parent = main_container,
        x = 140, y = 100, w = 200, h = 40,
        text = "子窗口1",
        color = 0xFFFFFF,
        font_size = 20
    })

    -- 关闭按钮，关闭后主窗口自动显示
    airui.button({
        parent = main_container,
        x = 190, y = 375, w = 100, h = 50,
        text = "关闭",
        on_click = on_click_close
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    -- 严格顺序：先取消触摸 → 再销毁容器
    if airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    -- 子窗口关闭后主窗口自动显示，无需 publish 消息
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy
    })
end

sys.subscribe("OPEN_SUB_WIN_1", open_handler)
