--[[
@module qrcode_page
@summary 二维码组件演示
@version 1.0
@date 2026.03.09
@author 江访
@usage
本文件演示airui.qrcode组件的用法，展示二维码生成。
]]

local airui_qecode = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function airui_qecode.create_ui()
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
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "二维码组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 创建二维码
    local qrcode = airui.qrcode({
        x = 330,
        y = 100,
        size = 360,                     -- 正方形尺寸
        data = "https://docs.openluat.com/",    -- 二维码内容
        dark_color = 0x000000,          -- 深色模块颜色
        light_color = 0xFFFFFF,         -- 浅色模块颜色
        quiet_zone = true                -- 四周留白
    })

    if not qrcode then
        log.error("qrcode", "创建二维码失败")
        return
    end

    -- 添加一个标签说明
    airui.label({
        x = 300,
        y = 468,
        w = 720,
        h = 40,
        text = "扫描上方二维码访问 LuatOS 官网",
        font_size = 28,
        color = 0x333333
    })
    
end

-- 初始化页面
function airui_qecode.init(params)
    airui_qecode.create_ui()
end

-- 清理页面
function airui_qecode.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_qecode