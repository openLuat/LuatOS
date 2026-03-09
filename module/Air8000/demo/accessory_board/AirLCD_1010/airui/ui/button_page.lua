--[[
@module  button_page
@summary 按钮组件演示页面
@version 1.1
@date    2026.03.09
@author  江访
@usage
本文件展示按钮组件 V1.1.0 的新特性：样式表、动态样式、切换文本、点击计数等。
]]

local button_page = {}

-- 页面UI元素
local main_container = nil


-- 辅助函数：创建带标题的容器

local function create_section(parent, title, x, y, width, height)
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

function button_page.create_ui()
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
        color = 0xF44336,
    })
    airui.label({
        parent = title_bar,
        text = "按钮组件演示 V1.1.0",
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
        on_click = function() go_back() end,
    })

    -- 滚动容器
    local scroll = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 370,
        color = 0xF5F5F5,
    })

    local y_offset = 10
    local section_w = 300
    local section_h = 90

    ----
    -- 1. 基础按钮（默认样式）
    ----
    local sec1 = create_section(scroll, "1. 基础按钮", 10, y_offset, section_w, section_h)
    airui.button({
        parent = sec1,
        x = 20,
        y = 30,
        w = 120,
        h = 40,
        text = "点击我",
        on_click = function(self)
            log.info("button", "基础按钮被点击")
        end,
    })
    y_offset = y_offset + section_h + 10

    ----
    -- 2. 自定义样式按钮（V1.1.0 样式表）
    ----
    local sec2 = create_section(scroll, "2. 自定义样式（圆角、边框、按下色）", 10, y_offset, section_w, 130)
    local style_btn = airui.button({
        parent = sec2,
        x = 20,
        y = 30,
        w = 150,
        h = 50,
        text = "样式按钮",
        style = {
            bg_color = 0x1A73E8,           -- 默认背景
            border_color = 0x0B57D0,        -- 边框颜色
            border_width = 2,                -- 边框宽度
            radius = 25,                     -- 圆角半径
            text_color = 0xFFFFFF,           -- 文字颜色
            pressed_bg_color = 0x0B57D0,     -- 按下背景
            focus_outline_color = 0xFFB300,  -- 焦点描边
            focus_outline_width = 3,         -- 焦点描边宽度
        },
        on_click = function(self)
            log.info("button", "样式按钮被点击")
        end,
    })
    -- 动态修改样式按钮
    airui.button({
        parent = sec2,
        x = 180,
        y = 30,
        w = 100,
        h = 40,
        text = "随机样式",
        on_click = function()
            local r = math.random(0, 0xFF)
            local g = math.random(0, 0xFF)
            local b = math.random(0, 0xFF)
            local color = (r << 16) | (g << 8) | b
            style_btn:set_stype({
                bg_color = color,
                pressed_bg_color = color & 0x7F7F7F,
            })
        end,
    })
    y_offset = y_offset + section_h + 10

    ----
    -- 3. 切换文本按钮（播放/停止）
    ----
    local sec3 = create_section(scroll, "3. 切换文本（播放/停止）", 10, y_offset, section_w, 90)
    local is_play = false
    local toggle_btn = airui.button({
        parent = sec3,
        x = 20,
        y = 30,
        w = 120,
        h = 40,
        text = "播放",
        on_click = function(self)
            if is_play then
                self:set_text("播放")
                is_play = false
            else
                self:set_text("停止")
                is_play = true
            end
            log.info("button", "切换状态:", is_play and "停止" or "播放")
        end,
    })
    y_offset = y_offset + section_h + 10

    ----
    -- 4. 点击计数按钮
    ----
    local sec4 = create_section(scroll, "4. 点击计数", 10, y_offset, section_w, 90)
    local count = 0
    local count_btn = airui.button({
        parent = sec4,
        x = 20,
        y = 30,
        w = 150,
        h = 40,
        text = "点击 0 次",
        on_click = function(self)
            count = count + 1
            self:set_text("点击 " .. count .. " 次")
        end,
    })
    y_offset = y_offset + section_h + 10

    ----
    -- 5. 按钮组（水平排列）
    ----
    local sec5 = create_section(scroll, "5. 按钮组", 10, y_offset, section_w, 90)
    local group_container = airui.container({
        parent = sec5,
        x = 10,
        y = 30,
        w = 280,
        h = 50,
        color = 0xEEEEEE,
        radius = 5,
    })
    for i = 1, 3 do
        airui.button({
            parent = group_container,
            x = 10 + (i-1)*90,
            y = 5,
            w = 80,
            h = 40,
            text = "选项" .. i,
            on_click = function(self)
                log.info("button", "选项", i, "被点击")
            end,
        })
    end
    y_offset = y_offset + section_h + 10

    ----
    -- 6. 动态销毁按钮
    ----
    local sec6 = create_section(scroll, "6. 动态销毁", 10, y_offset, section_w, 90)
    local destroy_target = airui.button({
        parent = sec6,
        x = 20,
        y = 30,
        w = 120,
        h = 40,
        text = "可被销毁",
        on_click = function(self)
            log.info("button", "可销毁按钮被点击")
        end,
    })
    airui.button({
        parent = sec6,
        x = 150,
        y = 30,
        w = 120,
        h = 40,
        text = "销毁左边",
        on_click = function()
            if destroy_target then
                destroy_target:destroy()
                destroy_target = nil
                log.info("button", "已销毁可销毁按钮")
            end
        end,
    })
    y_offset = y_offset + section_h + 10

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示: 按钮支持样式表、动态文本、销毁等",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

function button_page.init(params)
    math.randomseed(os.time())
    button_page.create_ui()
end

function button_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return button_page