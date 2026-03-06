--[[
@module  chart_page
@summary 图表组件演示页面
@version 1.0
@date    2026.03.02
@author  自动生成
@usage
本文件是图表组件的演示页面，展示图表的各种用法。
注意：需要确保 airui.chart 组件可用。
]]

local chart_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container   = nil
local scroll_container = nil
local chart_timer      = nil          -- 数据推送定时器ID
local page_active      = false        -- 页面是否活跃，用于定时器安全

local value_text       = nil          -- 显示当前数值
local point_text       = nil          -- 显示按下的点索引
local chart            = nil          -- 图表对象

----------------------------------------------------------------
-- 辅助函数：创建带标题的容器
----------------------------------------------------------------
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

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function chart_page.create_ui()
    main_container = airui.container({
        parent = airui.screen,
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
        color = 0x9C27B0,          -- 紫色，与其他页面区分
    })

    airui.label({
        parent = title_bar,
        text = "图表组件演示",
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
            go_back()
        end
    })

    -- 滚动容器（确保所有内容可滚动）
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 420,                    -- 留出底部空间
        color = 0xF5F5F5,
    })

    local current_y = 10

    --------------------------------------------------------------------
    -- 示例说明
    --------------------------------------------------------------------
    airui.label({
        parent = scroll_container,
        text = "图表组件演示 (10Hz 模拟数据)",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })
    current_y = current_y + 25

    --------------------------------------------------------------------
    -- 数值显示区域
    --------------------------------------------------------------------
    local info_container = airui.container({
        parent = scroll_container,
        x = 10,
        y = current_y,
        w = 300,
        h = 40,
        color = 0xEEEEEE,
        radius = 4,
    })
    current_y = current_y + 45

    value_text = airui.label({
        parent = info_container,
        text = "当前值: 50",
        x = 10,
        y = 10,
        w = 140,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })

    point_text = airui.label({
        parent = info_container,
        text = "按下点: -1",
        x = 160,
        y = 10,
        w = 130,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })

    --------------------------------------------------------------------
    -- 图表组件
    --------------------------------------------------------------------
    local chart_container = create_demo_container(scroll_container, "实时曲线", 10, current_y, 300, 200)
    current_y = current_y + 200 + 10

    chart = airui.chart({
        parent = chart_container,
        x = 10,
        y = 30,
        w = 280,
        h = 150,
        y_min = 0,
        y_max = 100,
        point_count = 30,               -- 减少点数以适应窄屏
        update_mode = "shift",           -- 滚动模式
        line_color = 0x00b4ff,
        line_width = 2,
        hdiv = 5,
        vdiv = 4,
        on_point = function(self)
            if point_text then
                local idx = self:get_pressed_point()
                point_text:set_text("按下点: " .. tostring(idx))
                log.info("chart", "pressed index", idx)
            end
        end
    })

    -- 预置一组初始值（平滑过渡）
    chart:set_values({50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 68, 66, 64, 62, 60, 58, 56, 54, 52, 50})

    --------------------------------------------------------------------
    -- 控制按钮区域
    --------------------------------------------------------------------
    local control_container = create_demo_container(scroll_container, "控制面板", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    local mode = "shift"
    local btn_mode = airui.button({
        parent = control_container,
        text = "模式: shift",
        x = 20,
        y = 30,
        w = 120,
        h = 35,
        on_click = function(self)
            if mode == "shift" then
                mode = "circular"
                chart:set_update_mode("circular")
                self:set_text("模式: circular")
            else
                mode = "shift"
                chart:set_update_mode("shift")
                self:set_text("模式: shift")
            end
            log.info("chart", "update_mode ->", mode)
        end
    })

    local btn_clear = airui.button({
        parent = control_container,
        text = "清除",
        x = 160,
        y = 30,
        w = 120,
        h = 35,
        on_click = function(self)
            chart:clear(50)
            if value_text then
                value_text:set_text("当前值: 50")
            end
            log.info("chart", "clear to 50")
        end
    })

    local btn_color = airui.button({
        parent = control_container,
        text = "随机颜色",
        x = 20,
        y = 70,
        w = 120,
        h = 35,
        on_click = function(self)
            local color = math.random(0, 0xFFFFFF)
            chart:set_line_color(color)
            log.info("chart", "set line color", string.format("%06X", color))
        end
    })

    --------------------------------------------------------------------
    -- 底部提示
    --------------------------------------------------------------------
    airui.label({
        parent = main_container,
        text = "提示: 点击曲线可查看数据点索引",
        x = 10,
        y = 450,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

----------------------------------------------------------------
-- 定时器回调：模拟10Hz数据推送
----------------------------------------------------------------
local function chart_timer_cb()
    if not page_active then
        return      -- 页面已销毁，不再更新
    end

    -- 简单的三角波模拟
    local tick = _G.__chart_tick or 0
    tick = tick + 1
    _G.__chart_tick = tick

    local base = 50 + 30 * math.sin(tick * 0.1)
    local noise = math.random(-3, 3)
    local value = math.floor(base + noise + 0.5)
    -- 限制范围
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end

    if chart and value_text then
        chart:push(value)
        value_text:set_text("当前值: " .. tostring(value))
    end

    if tick % 50 == 0 then
        log.info("chart", "running 10Hz, sample=", value)
    end
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function chart_page.init(params)
    chart_page.create_ui()
    page_active = true

    -- 启动定时器（100ms = 10Hz）
    if chart_timer then
        sys.timerStop(chart_timer)
    end
    chart_timer = sys.timerLoopStart(chart_timer_cb, 100)
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function chart_page.cleanup()
    page_active = false
    if chart_timer then
        sys.timerStop(chart_timer)
        chart_timer = nil
    end

    if main_container then
        main_container:destroy()
        main_container = nil
        scroll_container = nil
        value_text = nil
        point_text = nil
        chart = nil
    end
end

return chart_page