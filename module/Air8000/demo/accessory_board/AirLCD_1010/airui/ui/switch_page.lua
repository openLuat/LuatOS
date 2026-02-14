--[[
@module  switch_page
@summary 开关组件演示页面
@version 2.0.0
@date    2026.01.30
@author  江访
@usage
本文件展示开关组件的基本用法和常见场景。
]]

local switch_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function switch_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x00BCD4,
    })

    airui.label({
        parent = title_bar,
        text = "开关组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        radius = 5,
        on_click = function()
            go_back()
        end
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 430,
        color = 0xF5F5F5,
    })


    airui.label({
        parent = main_container,
        text = "设置选项",
        x = 10,
        y = 60,
        w = 280,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })

    -- 第一行
    local switch_wifi = airui.switch({
        parent = main_container,
        x = 20,
        y = 90,
        w = 50,
        h = 25,
        checked = true,
        on_change = function(state)
            log.info("WiFi", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "WiFi",
        x = 80,
        y = 92,
        w = 100,
        h = 20,
    })

    local switch_bluetooth = airui.switch({
        parent = main_container,
        x = 160,
        y = 90,
        w = 50,
        h = 25,
        checked = false,
        on_change = function(state)
            log.info("蓝牙", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "蓝牙",
        x = 220,
        y = 92,
        w = 100,
        h = 20,
    })

    -- 第二行
    local switch_data = airui.switch({
        parent = main_container,
        x = 20,
        y = 135,
        w = 50,
        h = 25,
        checked = false,
        on_change = function(state)
            log.info("移动数据", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "移动数据",
        x = 80,
        y = 137,
        w = 100,
        h = 20,
    })

    local switch_gps = airui.switch({
        parent = main_container,
        x = 160,
        y = 135,
        w = 50,
        h = 25,
        checked = true,
        on_change = function(state)
            log.info("GPS", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "GPS定位",
        x = 220,
        y = 137,
        w = 100,
        h = 20,
    })

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "开关组件：点击切换状态，支持程序控制",
        x = 10,
        y = 450,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

-- 初始化页面
function switch_page.init(params)
    switch_page.create_ui()
end

-- 清理页面
function switch_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return switch_page