--[[
@module  airui_checkbox
@summary 复选框组件演示页面
@version 1.0.0
@date    2026.05.20
@author  江访
@usage
本文件是复选框组件的演示页面，展示复选框的创建、状态切换和样式设置。
]]

local airui_checkbox = {}

local main_container = nil

function airui_checkbox.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = 1024, h = 600,
        color = 0xF5F5F5,
    })

    -- 标题
    airui.label({
        parent = main_container,
        text = "复选框组件演示",
        x = 20, y = 20, w = 300, h = 30, size = 20,
    })

    -- 基础 Checkbox
    airui.label({
        parent = main_container,
        text = "示例1: 基础复选框",
        x = 20, y = 70, w = 400, h = 30, size = 16,
    })

    local cb1 = airui.checkbox({
        parent = main_container,
        x = 40, y = 110, w = 300, h = 40,
        text = "基础选项",
        on_change = function(self)
            log.info("cb1", "state ->", self:get_checked())
        end
    })

    -- 默认勾选
    local cb2 = airui.checkbox({
        parent = main_container,
        x = 40, y = 160, w = 300, h = 40,
        text = "默认勾选",
        checked = true,
        on_change = function(self)
            log.info("cb2", "state ->", self:get_checked())
        end
    })

    -- 自定义样式
    airui.label({
        parent = main_container,
        text = "示例2: 自定义样式",
        x = 20, y = 220, w = 400, h = 30, size = 16,
    })

    local cb3 = airui.checkbox({
        parent = main_container,
        x = 40, y = 260, w = 400, h = 40,
        text = "自定义文字颜色和字号",
        checked = true,
        style = {
            text_color = 0x174EA6,
            checked_text_color = 0xD93025,
            text_font_size = 28,
        },
        on_change = function(self)
            log.info("cb3", "state ->", self:get_checked())
        end
    })
end

function airui_checkbox.init(params)
    airui_checkbox.create_ui()
end

function airui_checkbox.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_checkbox
