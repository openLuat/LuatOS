--[[
@module  water_home_win
@summary 智能水雾系统主页模块
@version 1.0
@date    2026.04.17
@author  AI Assistant
]]

-- 引入子模块
require "water_detail_win"
require "water_config_win"

local win_id = nil
local main_container = nil
local screen_w, screen_h = 480, 800

-- 页面状态
local current_page = "home"

-- 颜色常量
local COLOR_PRIMARY = 0x3F51B5
local COLOR_BG = 0xF8F9FA
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_TEXT_SECONDARY = 0x666666
local COLOR_SUCCESS = 0x27AE60
local COLOR_WARNING = 0xF39C12
local COLOR_ERROR = 0xE74C3C
local COLOR_INFO = 0x3498DB

-- 支路数据
local branch_data = {
    { name = "第一路", humidity = "45.0%", temperature = "25.5°C", status = "系统停止", status_color = COLOR_ERROR, switch = true },
    { name = "第二路", humidity = "88.0%", temperature = "24.8°C", status = "自动喷雾", status_color = COLOR_SUCCESS, switch = false },
    { name = "第三路", humidity = "88.0%", temperature = "25.2°C", status = "自动停止", status_color = COLOR_ERROR, switch = false },
    { name = "第四路", humidity = "88.0%", temperature = "26.1°C", status = "系统暂停", status_color = COLOR_WARNING, switch = true },
    { name = "第五路", humidity = "33.0%", temperature = "25.8°C", status = "水箱缺水", status_color = COLOR_ERROR, switch = false },
    { name = "第六路", humidity = "88.0%", temperature = "24.9°C", status = "药箱缺药", status_color = COLOR_ERROR, switch = false },
    { name = "第七路", humidity = "65.0%", temperature = "27.3°C", status = "自动运行", status_color = COLOR_SUCCESS, switch = true },
    { name = "第八路", humidity = "78.0%", temperature = "26.8°C", status = "系统停止", status_color = COLOR_ERROR, switch = false },
}

-------------------------------------------------------------------------------
-- 创建首页 UI
-------------------------------------------------------------------------------
function create_home_page(parent)
    -- 清除所有子组件
    if parent then
        -- 直接重新创建容器
        parent:destroy()
        main_container = airui.container({
            parent = airui.screen,
            x = 0,
            y = 0,
            w = screen_w,
            h = screen_h,
            color = 0xFFFFFF
        })
        parent = main_container
    end

    -- 顶部栏
    local header = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = screen_w,
        h = 60,
        color = COLOR_PRIMARY
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = 10,
        y = 10,
        w = 60,
        h = 40,
        text = "返回",
        font_size = 18,
        color = 0xFFFFFF,
        bg_color = 0x808080,
        radius = 8,
        on_click = function()
            log.info("WATER_HOME_WIN", "Return button clicked, win_id:", win_id)
            if win_id then 
                local close_result = exwin.close(win_id)
                log.info("WATER_HOME_WIN", "exwin.close result:", close_result)
                -- 确保窗口ID被重置
                win_id = nil
            else
                log.warn("WATER_HOME_WIN", "Return button clicked but win_id is nil")
            end 
        end
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = (screen_w - 200) / 2,
        y = 15,
        w = 200,
        h = 30,
        text = "智能水雾系统",
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 时间显示（中文）
    local weekdays = {"周日", "周一", "周二", "周三", "周四", "周五", "周六"}
    local current_time = os.date("%Y年%m月%d日 " .. weekdays[os.date("%w") + 1] .. " %H:%M")
    airui.label({
        parent = header,
        x = screen_w - 170, -- 调整位置，增加与标题的间距
        y = 15,
        w = 160, -- 增加宽度，防止周一换行
        h = 30,
        text = current_time,
        font_size = 13, -- 稍微减小字体大小，防止换行
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 主内容区域
    local container = airui.container({
        parent = parent,
        x = 0,
        y = 60,
        w = screen_w,
        h = screen_h - 60,
        color = 0xF5F7FA -- 更优雅的背景色
    })

    -- 状态面板
    local status_width = screen_w - 24 -- 增加边框宽度的计算
    local status_height = 480
    local status_container = airui.container({
        parent = container,
        x = 10,
        y = 10,
        w = status_width, -- 使用提前计算好的宽度
        h = status_height,
        color = 0xFFFFFF,
        radius = 16, -- 更大的圆角
        border_width = 1,
        border_color = 0xE2E8F0, -- 边框颜色
        shadow_color = 0x4A5568, -- 阴影颜色
        shadow_blur = 8, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2, -- 阴影偏移
        scroll_x = false, -- 禁止水平滚动
        scroll_y = false -- 禁止垂直滚动
    })

    -- 运行时间
    local child_width = (status_width - 30) / 2 -- 使用提前计算好的宽度
    airui.container({
        parent = status_container,
        x = 10,
        y = 10,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x2196F3, -- 蓝色边框
        shadow_color = 0x2196F3, -- 蓝色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = 20,
        y = 25,
        w = 40,
        h = 40,
        src = "/luadb/clock.png"
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 20,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "运行时间",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 45,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "运行:80H",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 电机状态
    airui.container({
        parent = status_container,
        x = child_width + 20, -- 使用计算好的间距
        y = 10,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x4CAF50, -- 绿色边框
        shadow_color = 0x4CAF50, -- 绿色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = (screen_w - 40) / 2 + 30,
        y = 25,
        w = 40,
        h = 40,
        src = "/luadb/motor.png"
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 20,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "电机状态",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 45,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "电机:正常",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 泵状态
    airui.container({
        parent = status_container,
        x = 10,
        y = 100,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0xFF9800, -- 橙色边框
        shadow_color = 0xFF9800, -- 橙色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = 20,
        y = 115,
        w = 40,
        h = 40,
        src = "/luadb/pump.png"
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 110,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "泵状态",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 135,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "压力:正常",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 水质状态
    airui.container({
        parent = status_container,
        x = child_width + 20, -- 使用计算好的间距
        y = 100,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x00BCD4, -- 青色边框
        shadow_color = 0x00BCD4, -- 青色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = (screen_w - 40) / 2 + 30,
        y = 115,
        w = 40,
        h = 40,
        src = "/luadb/water.png"
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 110,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "水质状态",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 135,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "水质:良好",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 滤芯状态
    airui.container({
        parent = status_container,
        x = 10,
        y = 190,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x9C27B0, -- 紫色边框
        shadow_color = 0x9C27B0, -- 紫色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = 20,
        y = 205,
        w = 40,
        h = 40,
        src = "/luadb/filter.png"
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 200,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "滤芯状态",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 225,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "滤芯:正常",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 泵油状态
    airui.container({
        parent = status_container,
        x = child_width + 20, -- 使用计算好的间距
        y = 190,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x4CAF50, -- 绿色边框
        shadow_color = 0x4CAF50, -- 绿色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = (screen_w - 40) / 2 + 30,
        y = 205,
        w = 40,
        h = 40,
        src = "/luadb/oil.png"
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 200,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "泵油状态",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 225,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "泵油:正常",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 环境温度
    airui.container({
        parent = status_container,
        x = 10,
        y = 280,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0xFF5722, -- 红色边框
        shadow_color = 0xFF5722, -- 红色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = 20,
        y = 295,
        w = 40,
        h = 40,
        src = "/luadb/temperature.png"
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 290,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "环境温度",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 315,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "25.5°C",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 环境湿度
    airui.container({
        parent = status_container,
        x = child_width + 20, -- 使用计算好的间距
        y = 280,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x00BCD4, -- 青色边框
        shadow_color = 0x00BCD4, -- 青色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = (screen_w - 40) / 2 + 30,
        y = 295,
        w = 40,
        h = 40,
        src = "/luadb/humidity.png"
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 290,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "环境湿度",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 315,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "45.0%",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 电压监测
    airui.container({
        parent = status_container,
        x = 10,
        y = 370,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0x4CAF50, -- 绿色边框
        shadow_color = 0x4CAF50, -- 绿色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = 20,
        y = 385,
        w = 40,
        h = 40,
        src = "/luadb/voltage.png"
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 380,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "电压监测",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = 70,
        y = 405,
        w = (screen_w - 40) / 2 - 80,
        h = 30,
        text = "220V",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 电流监测
    airui.container({
        parent = status_container,
        x = child_width + 20, -- 使用计算好的间距
        y = 370,
        w = child_width, -- 使用计算好的宽度
        h = 80,
        color = 0xFFFFFF,
        radius = 12, -- 更大的圆角
        border_width = 1,
        border_color = 0xFF5722, -- 红色边框
        shadow_color = 0xFF5722, -- 红色阴影
        shadow_blur = 4, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 2 -- 阴影偏移
    })
    airui.image({
        parent = status_container,
        x = (screen_w - 40) / 2 + 30,
        y = 385,
        w = 40,
        h = 40,
        src = "/luadb/current.png"
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 380,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "电流监测",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY
    })
    airui.label({
        parent = status_container,
        x = (screen_w - 40) / 2 + 80,
        y = 405,
        w = (screen_w - 40) / 2 - 90,
        h = 30,
        text = "1.2A",
        font_size = 18,
        color = COLOR_SUCCESS
    })

    -- 详细信息按钮
    airui.button({
        parent = container,
        x = (screen_w - 200) / 2,
        y = 510,
        w = 200,
        h = 60,
        text = "详细信息",
        font_size = 24,
        color = 0xFFFFFF,
        bg_color = 0x2196F3, -- 蓝色背景
        radius = 15, -- 更大的圆角
        border_width = 2,
        border_color = 0x0D47A1, -- 深蓝色边框
        shadow_color = 0x2196F3, -- 蓝色阴影
        shadow_blur = 8, -- 阴影模糊
        shadow_offset_x = 0,
        shadow_offset_y = 4, -- 阴影偏移
        on_click = function()
            log.info("WATER_HOME_WIN", "Open detail page button clicked")
            -- 发布事件，打开详细页面窗口
            sys.publish("OPEN_WATER_DETAIL_WIN")
        end
    })
    
    -- 二维码
    airui.qrcode({
        parent = container,
        x = (screen_w - 130) / 2,
        y = 590,
        size = 130,
        data = "https://docs.openluat.com/air8101/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    return main_container
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xFFFFFF
    })
    main_container = create_home_page(main_container)
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_WATER_HOME_WIN", open_handler)
