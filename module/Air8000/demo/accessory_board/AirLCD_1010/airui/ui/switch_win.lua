--[[
@module  switch_win
@summary 开关组件演示窗口
@version 1.1.0
@date    2026.03.17
@author  江访
@usage
本文件展示开关组件的基本用法和常见场景，采用exwin窗口管理扩展库。
]]



-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container = nil

-- 创建UI
local function create_ui()
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
        color = 0xFFFFFF,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function(self)
            exwin.close(win_id)
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
        on_change = function(self)
            log.info("WiFi", self:get_state() and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "WiFi",
        x = 80,
        y = 92,
        w = 100,
        h = 20,
        font_size = 14,
    })

    local switch_bluetooth = airui.switch({
        parent = main_container,
        x = 160,
        y = 90,
        w = 50,
        h = 25,
        checked = false,
        on_change = function(self)
            log.info("蓝牙", self:get_state() and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "蓝牙",
        x = 220,
        y = 92,
        w = 100,
        h = 20,
        font_size = 14,
    })

    -- 第二行
    local switch_data = airui.switch({
        parent = main_container,
        x = 20,
        y = 135,
        w = 50,
        h = 25,
        checked = false,
        on_change = function(self)
            log.info("移动数据", self:get_state() and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "移动数据",
        x = 80,
        y = 137,
        w = 100,
        h = 20,
        font_size = 14,
    })

    local switch_gps = airui.switch({
        parent = main_container,
        x = 160,
        y = 135,
        w = 50,
        h = 25,
        checked = true,
        on_change = function(self)
            log.info("GPS", self:get_state() and "开启" or "关闭")
        end
    })

    airui.label({
        parent = main_container,
        text = "GPS定位",
        x = 220,
        y = 137,
        w = 100,
        h = 20,
        font_size = 14,
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

-- 窗口创建回调
local function on_create()
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    log.info("switch_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("switch_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("switch_win", "窗口失去焦点")
end

-- 订阅打开开关窗口消息
sys.subscribe("OPEN_SWITCH_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("switch_win", "窗口打开，ID:", win_id)
    end
end)