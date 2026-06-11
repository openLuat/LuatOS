--[[
@module  slider_page
@summary 滑块组件演示
@version 1.0
@date    2026.06.11
@author  江访
@usage
本文件演示airui.slider组件的用法，包括创建、值设置、取值范围修改、样式设置和销毁。
]]

local function ui_main()
    -- ========== 基础 Slider ==========
    local slider1 = airui.slider({
        x = 20, y = 40, w = 280, h = 24,
        min = 0,
        max = 100,
        value = 35,
        on_change = function(self)
            log.info("slider1", "value changed", self:get_value())
        end
    })
    log.info("airui", "slider1 created", slider1 ~= nil, "init value", slider1:get_value())

    -- ========== 自定义样式的 Slider ==========
    local slider2 = airui.slider({
        x = 20, y = 90, w = 280, h = 24,
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

    -- ========== 显示当前值的 Label ==========
    local value_label = airui.label({
        x = 20, y = 130, w = 100, h = 28,
        text = "val: 35",
        font_size = 16,
    })

    -- ========== 控制按钮 ==========
    -- 设置 slider1 值为 75
    airui.button({
        text = "Set 75",
        x = 20, y = 180, w = 130, h = 44,
        on_click = function()
            if slider1 and not slider1:is_destroyed() then
                slider1:set_value(75, true)
                log.info("slider1", "set value to 75")
            end
        end
    })

    -- 切换 slider1 样式
    airui.button({
        text = "Style",
        x = 170, y = 180, w = 130, h = 44,
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

    -- 修改 slider2 取值范围
    airui.button({
        text = "Range 200",
        x = 20, y = 240, w = 130, h = 44,
        on_click = function()
            if slider2 and not slider2:is_destroyed() then
                slider2:set_range(0, 200)
                log.info("slider2", "range set to 0-200")
            end
        end
    })

    -- 销毁 slider1
    airui.button({
        text = "Destroy",
        x = 170, y = 240, w = 130, h = 44,
        on_click = function()
            if slider1 and not slider1:is_destroyed() then
                slider1:destroy()
                log.info("slider1", "destroyed")
            else
                log.info("slider1", "already destroyed")
            end
        end
    })

    -- 定时更新值显示
    sys.timerLoopStart(function()
        if slider1 and not slider1:is_destroyed() then
            value_label:set_text("val: " .. slider1:get_value())
        end
    end, 500)
end

sys.taskInit(ui_main)
