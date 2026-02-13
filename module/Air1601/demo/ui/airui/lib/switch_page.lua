--[[
@module  switch_page
@summary 开关组件演示页面
@version 1.0.0
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
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x00BCD4,
    })

    airui.label({
        parent = title_bar,
        text = "开关组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        radius = 6,
        on_click = function()
            go_back()
        end
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题
    airui.label({
        parent = content,
        text = "系统设置选项",
        x = 20,
        y = 20,
        w = 300,
        h = 35,
        size = 20,
        color = 0x333333,
    })

    -- 设置选项容器
    local settings_container = airui.container({
        parent = content,
        x = 20,
        y = 70,
        w = 984,
        h = 380,
        color = 0xFFFFFF,
        radius = 12,
    })

    -- 网络设置部分
    airui.label({
        parent = settings_container,
        text = "网络设置",
        x = 30,
        y = 30,
        w = 200,
        h = 30,
        size = 18,
        color = 0x333333,
    })

    -- 第一行：WiFi和蓝牙
    local switch_wifi = airui.switch({
        parent = settings_container,
        x = 300,
        y = 30,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("WiFi", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "WiFi",
        x = 400,
        y = 32,
        w = 150,
        h = 30,
        size = 16,
    })

    local switch_bluetooth = airui.switch({
        parent = settings_container,
        x = 600,
        y = 30,
        w = 80,
        h = 35,
        checked = false,
        on_change = function(state)
            log.info("蓝牙", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "蓝牙",
        x = 700,
        y = 32,
        w = 150,
        h = 30,
        size = 16,
    })

    -- 第二行：移动数据和GPS
    airui.label({
        parent = settings_container,
        text = "位置服务",
        x = 30,
        y = 90,
        w = 200,
        h = 30,
        size = 18,
        color = 0x333333,
    })

    local switch_data = airui.switch({
        parent = settings_container,
        x = 300,
        y = 90,
        w = 80,
        h = 35,
        checked = false,
        on_change = function(state)
            log.info("移动数据", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "移动数据",
        x = 400,
        y = 92,
        w = 150,
        h = 30,
        size = 16,
    })

    local switch_gps = airui.switch({
        parent = settings_container,
        x = 600,
        y = 90,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("GPS", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "GPS定位",
        x = 700,
        y = 92,
        w = 150,
        h = 30,
        size = 16,
    })

    -- 第三行：通知和自动更新
    airui.label({
        parent = settings_container,
        text = "系统通知",
        x = 30,
        y = 150,
        w = 200,
        h = 30,
        size = 18,
        color = 0x333333,
    })

    local switch_notification = airui.switch({
        parent = settings_container,
        x = 300,
        y = 150,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("通知", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "通知提醒",
        x = 400,
        y = 152,
        w = 150,
        h = 30,
        size = 16,
    })

    local switch_auto_update = airui.switch({
        parent = settings_container,
        x = 600,
        y = 150,
        w = 80,
        h = 35,
        checked = false,
        on_change = function(state)
            log.info("自动更新", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "自动更新",
        x = 700,
        y = 152,
        w = 150,
        h = 30,
        size = 16,
    })

    -- 第四行：声音和振动
    airui.label({
        parent = settings_container,
        text = "声音设置",
        x = 30,
        y = 210,
        w = 200,
        h = 30,
        size = 18,
        color = 0x333333,
    })

    local switch_sound = airui.switch({
        parent = settings_container,
        x = 300,
        y = 210,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("声音", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "系统声音",
        x = 400,
        y = 212,
        w = 150,
        h = 30,
        size = 16,
    })

    local switch_vibration = airui.switch({
        parent = settings_container,
        x = 600,
        y = 210,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("振动", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "振动反馈",
        x = 700,
        y = 212,
        w = 150,
        h = 30,
        size = 16,
    })

    -- 第五行：深色模式和自动亮度
    airui.label({
        parent = settings_container,
        text = "显示设置",
        x = 30,
        y = 270,
        w = 200,
        h = 30,
        size = 18,
        color = 0x333333,
    })

    local switch_dark_mode = airui.switch({
        parent = settings_container,
        x = 300,
        y = 270,
        w = 80,
        h = 35,
        checked = false,
        on_change = function(state)
            log.info("深色模式", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "深色模式",
        x = 400,
        y = 272,
        w = 150,
        h = 30,
        size = 16,
    })

    local switch_auto_brightness = airui.switch({
        parent = settings_container,
        x = 600,
        y = 270,
        w = 80,
        h = 35,
        checked = true,
        on_change = function(state)
            log.info("自动亮度", state and "开启" or "关闭")
        end
    })

    airui.label({
        parent = settings_container,
        text = "自动亮度",
        x = 700,
        y = 272,
        w = 150,
        h = 30,
        size = 16,
    })

    -- 控制按钮区域
    local control_container = airui.container({
        parent = content,
        x = 20,
        y = 460,
        w = 984,
        h = 80,
        color = 0xE0F7FA,
        radius = 10,
    })

    local select_all_btn = airui.button({
        parent = control_container,
        x = 100,
        y = 20,
        w = 150,
        h = 45,
        text = "全部开启",
        size = 16,
        on_click = function()
            log.info("switch", "全部开启")
        end
    })

    local deselect_all_btn = airui.button({
        parent = control_container,
        x = 300,
        y = 20,
        w = 150,
        h = 45,
        text = "全部关闭",
        size = 16,
        on_click = function()
            log.info("switch", "全部关闭")
        end
    })

    local reset_btn = airui.button({
        parent = control_container,
        x = 500,
        y = 20,
        w = 150,
        h = 45,
        text = "重置设置",
        size = 16,
        on_click = function()
            log.info("switch", "重置所有开关")
        end
    })

    -- 状态显示
    local status_label = airui.label({
        parent = control_container,
        text = "已开启: 4项 | 已关闭: 4项",
        x = 700,
        y = 22,
        w = 200,
        h = 40,
        size = 14,
        color = 0x666666,
    })

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "开关组件：点击切换状态，支持程序控制和状态反馈",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        color = 0x666666,
        size = 14,
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