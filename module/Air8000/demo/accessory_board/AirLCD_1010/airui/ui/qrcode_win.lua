--[[
@module     qrcode_win
@summary    二维码组件演示窗口
@version    1.1.0
@date       2026.03.17
@author     江访
@usage      本文件是二维码组件的演示窗口，采用exwin窗口管理扩展库。
            展示二维码的生成与动态更新，通过消息机制打开和关闭。
]]

-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container   = nil
local scroll_container = nil
local qrcode           = nil          -- 二维码对象


-- 辅助函数：创建带标题的容器

local function create_demo_container(parent, title, x, y, width, height)
    local container = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 8,
    })

    airui.label({
        parent = container,
        text = title,
        x = 10,
        y = 5,
        w = width - 20,
        h = 25,
        color = 0x333333,
        font_size = 14,
    })

    return container
end


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
        color = 0x673AB7,
    })

    airui.label({
        parent = title_bar,
        text = "二维码演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
    local back_btn = airui.button({
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

    -- 滚动容器
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 420,
        color = 0xF5F5F5,
    })

    local current_y = 10

    ----
    -- 示例1: 基本二维码
    ----
    local demo1_container = create_demo_container(scroll_container, "示例1: 基本二维码", 10, current_y, 300, 220)
    current_y = current_y + 220 + 10

    airui.label({
        parent = demo1_container,
        text = "显示一个简单的二维码（URL）",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })

    qrcode = airui.qrcode({
        parent = demo1_container,
        x = 60,
        y = 60,
        size = 160,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    if not qrcode then
        airui.label({
            parent = demo1_container,
            text = "二维码创建失败！",
            x = 80,
            y = 140,
            w = 140,
            h = 20,
            color = 0xFF0000,
            font_size = 14,
        })
    end

    ----
    -- 示例2: 动态更新数据
    ----
    local demo2_container = create_demo_container(scroll_container, "示例2: 动态更新数据", 10, current_y, 300, 240)
    current_y = current_y + 220 + 10

    airui.label({
        parent = demo2_container,
        text = "点击按钮更新二维码内容",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })

    local dynamic_qrcode = airui.qrcode({
        parent = demo2_container,
        x = 60,
        y = 60,
        size = 140,
        data = "初始数据",
        dark_color = 0x0B3D91,
        light_color = 0xF4F8FF,
    })

    -- 显示当前数据
    local data_label = airui.label({
        parent = demo2_container,
        text = "当前数据: 初始数据",
        x = 10,
        y = 190,
        w = 280,
        h = 20,
        color = 0x333333,
        font_size = 12,
    })

    -- 按钮：更新为URL
    airui.button({
        parent = demo2_container,
        x = 20,
        y = 210,
        w = 80,
        h = 30,
        text = "设为URL",
        on_click = function()
            local ok = dynamic_qrcode:set_data("https://docs.openluat.com/")
            if ok then
                data_label:set_text("当前数据: https://docs.openluat.com/")
            else
                data_label:set_text("设置失败(数据过长?)")
            end
        end
    })

    -- 按钮：更新为WiFi配置
    airui.button({
        parent = demo2_container,
        x = 110,
        y = 210,
        w = 80,
        h = 30,
        text = "设为WiFi",
        on_click = function()
            local wifi_str = "WIFI:T:WPA;S:LuatOS_AP;P:12345678;;"
            local ok = dynamic_qrcode:set_data(wifi_str)
            if ok then
                data_label:set_text("当前数据: WiFi配置")
            else
                data_label:set_text("设置失败(数据过长?)")
            end
        end
    })

    -- 按钮：更新为文本
    airui.button({
        parent = demo2_container,
        x = 200,
        y = 210,
        w = 80,
        h = 30,
        text = "设为文本",
        on_click = function()
            local ok = dynamic_qrcode:set_data("Hello QR")
            if ok then
                data_label:set_text("当前数据: Hello QR")
            else
                data_label:set_text("设置失败")
            end
        end
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
        scroll_container = nil
        qrcode = nil
    end
    win_id = nil
    log.info("qrcode_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("qrcode_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("qrcode_win", "窗口失去焦点")
end

-- 订阅打开二维码窗口消息
sys.subscribe("OPEN_QRCODE_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("qrcode_win", "窗口打开，ID:", win_id)
    end
end)