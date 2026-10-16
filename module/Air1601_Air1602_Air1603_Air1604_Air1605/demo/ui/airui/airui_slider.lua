--[[
@module  airui_slider
@summary 滑块组件演示页面
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件是滑块组件的演示页面，演示airui.slider组件的用法，包括创建、值设置、
取值范围修改、样式设置和销毁。
]]

local airui_slider = {}

-- 页面UI元素
local main_container = nil
local slider1 = nil
local value_label = nil
local value_timer = nil

-- 创建UI
function airui_slider.create_ui()
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
        color = 0x2196F3,
    })

    airui.label({
        parent = title_bar,
        text = "滑块组件演示",
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

    -- ========== 示例1: 基本滑块（左列） ==========
    local card1 = airui.container({
        parent = main_container,
        x = 20,
        y = 80,
        w = 480,
        h = 300,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card1,
        text = "示例1: 基本滑块",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    slider1 = airui.slider({
        parent = card1,
        x = 40, y = 70, w = 400, h = 28,
        min = 0,
        max = 100,
        value = 35,
        on_change = function(self)
            log.info("slider1", "value changed", self:get_value())
        end
    })
    log.info("airui", "slider1 created", slider1 ~= nil, "init value", slider1:get_value())

    -- 显示当前值的 Label
    value_label = airui.label({
        parent = card1,
        x = 40, y = 115, w = 400, h = 28,
        text = "当前值: 35",
        size = 16,
    })

    -- 设置 slider1 值为 75
    airui.button({
        parent = card1,
        text = "设置值 75",
        x = 40, y = 175, w = 180, h = 50,
        size = 16,
        on_click = function()
            if slider1 and not slider1:is_destroyed() then
                slider1:set_value(75, true)
                log.info("slider1", "set value to 75")
            end
        end
    })

    -- 切换 slider1 样式（随机颜色）
    airui.button({
        parent = card1,
        text = "切换样式",
        x = 250, y = 175, w = 180, h = 50,
        size = 16,
        on_click = function()
            if slider1 and not slider1:is_destroyed() then
                slider1:set_style({
                    indicator_color = math.random(0, 0xFFFFFF),
                    knob_border_color = math.random(0, 0xFFFFFF),
                })
                log.info("slider1", "style changed")
            end
        end
    })

    -- ========== 示例2: 自定义样式的滑块（右列） ==========
    local card2 = airui.container({
        parent = main_container,
        x = 522,
        y = 80,
        w = 480,
        h = 300,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card2,
        text = "示例2: 自定义样式的滑块",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    local slider2 = airui.slider({
        parent = card2,
        x = 40, y = 70, w = 400, h = 28,
        min = 0,
        max = 100,
        value = 60,
        style = {
            bg_color = 0xEDF6F9,
            bg_opa = 255,
            border_color = 0x5AA9E6,
            border_width = 2,
            radius = 12,
            pad = 2,
            indicator_color = 0x2CA58D,
            indicator_opa = 255,
            knob_color = 0xFFFFFF,
            knob_opa = 255,
            knob_border_color = 0x2CA58D,
            knob_border_width = 2,
        },
        on_change = function(self)
            log.info("slider2", "value changed", self:get_value())
        end
    })
    log.info("airui", "slider2 created", slider2 ~= nil)

    -- 修改 slider2 取值范围
    airui.button({
        parent = card2,
        text = "范围 0-200",
        x = 40, y = 175, w = 180, h = 50,
        size = 16,
        on_click = function()
            if slider2 and not slider2:is_destroyed() then
                slider2:set_range(0, 200)
                log.info("slider2", "range set to 0-200")
            end
        end
    })

    -- 销毁 slider1
    airui.button({
        parent = card2,
        text = "销毁 S1",
        x = 250, y = 175, w = 180, h = 50,
        size = 16,
        on_click = function()
            if slider1 and not slider1:is_destroyed() then
                slider1:destroy()
                log.info("slider1", "destroyed")
            else
                log.info("slider1", "already destroyed")
            end
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 滑块支持取值范围设置、动态取值、样式设置和范围修改",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        size = 14,
    })

    -- 定时更新值显示
    value_timer = sys.timerLoopStart(function()
        if slider1 and not slider1:is_destroyed() then
            value_label:set_text("当前值: " .. slider1:get_value())
        end
    end, 500)
end

-- 初始化页面
function airui_slider.init(params)
    airui_slider.create_ui()
end

-- 清理页面
function airui_slider.cleanup()
    if value_timer then
        sys.timerStop(value_timer)
        value_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    slider1 = nil
    value_label = nil
end

return airui_slider
