--[[
@module  win_main
@summary 主窗口模块，包含4个按钮分别导航到4个不同颜色的子窗口
@version 1.0.0
@date    2026.06.03
@author  合宙
@usage
本文件为主窗口业务逻辑模块，核心功能为：
1、订阅 "OPEN_MAIN_WIN" 消息，收到消息后创建主窗口
2、主窗口包含4个按钮，分别发布消息打开子窗口1-4
3、主窗口作为基底窗口保持打开，子窗口在其上方显示
4、子窗口关闭后主窗口自然可见，无需重新创建

按钮布局：
- 按钮1 "窗口1(红)" → publish "OPEN_SUB_WIN_1"
- 按钮2 "窗口2(绿)" → publish "OPEN_SUB_WIN_2"
- 按钮3 "窗口3(蓝)" → publish "OPEN_SUB_WIN_3"
- 按钮4 "窗口4(黄)" → publish "OPEN_SUB_WIN_4"
]]

local win_id = nil
local main_container = nil

local function on_click_sub_1()
    sys.publish("OPEN_SUB_WIN_1")
end

local function on_click_sub_2()
    sys.publish("OPEN_SUB_WIN_2")
end

local function on_click_sub_3()
    sys.publish("OPEN_SUB_WIN_3")
end

local function on_click_sub_4()
    sys.publish("OPEN_SUB_WIN_4")
end

local function on_click_close()
    exwin.close(win_id)
end

local function create_ui()
    -- 创建主窗口容器，使用中性灰色背景
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x333333
    })

    -- 标题文字
    airui.label({
        parent = main_container,
        x = 140, y = 100, w = 200, h = 40,
        text = "主窗口",
        color = 0xFFFFFF,
        font_size = 20
    })

    -- 按钮1：导航到红色子窗口
    airui.button({
        parent = main_container,
        x = 140, y = 220, w = 200, h = 50,
        text = "窗口1(红)",
        on_click = on_click_sub_1
    })

    -- 按钮2：导航到绿色子窗口
    airui.button({
        parent = main_container,
        x = 140, y = 290, w = 200, h = 50,
        text = "窗口2(绿)",
        on_click = on_click_sub_2
    })

    -- 按钮3：导航到蓝色子窗口
    airui.button({
        parent = main_container,
        x = 140, y = 360, w = 200, h = 50,
        text = "窗口3(蓝)",
        on_click = on_click_sub_3
    })

    -- 按钮4：导航到黄色子窗口
    airui.button({
        parent = main_container,
        x = 140, y = 430, w = 200, h = 50,
        text = "窗口4(黄)",
        on_click = on_click_sub_4
    })

    -- 关闭按钮，退出整个应用
    airui.button({
        parent = main_container,
        x = 190, y = 530, w = 100, h = 50,
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
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy
    })
end

sys.subscribe("OPEN_MAIN_WIN", open_handler)
