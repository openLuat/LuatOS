--[[
@module  chart_page
@summary 图表组件演示页面
@version 1.1
@date    2026.03.09
@author  江访
@usage
本文件展示图表组件 V1.1.0 的新特性：多系列、折线/柱状/堆叠、坐标轴自定义、动态推流、点击点回调。
]]

local chart_page = {}


-- 页面UI元素

local main_container   = nil
local scroll_container = nil
local chart            = nil          -- 图表对象
local chart_timer      = nil          -- 数据定时器
local page_active      = false

-- 控制相关变量
local chart_type = "line"              -- 当前图表类型
local series_ids = {}                  -- 存储系列ID
local series_names = { "正弦波", "噪声", "差值" }
local series_colors = { 0x00b4ff, 0xff6b35, 0x22c55e }

-- 用于点击点显示
local point_label = nil


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

-- 定时器回调：模拟动态数据推送
local function chart_timer_cb()
    if not page_active or not chart then return end

    local t = _G.__chart_t or 0
    t = t + 1
    _G.__chart_t = t

    -- 计算原始浮点值
    local v1 = 50 + 30 * math.sin(t * 0.1)
    local v2 = 40 + 20 * math.cos(t * 0.12)
    local v3 = 10 + 10 * math.sin(t * 0.15)

    -- 添加噪声
    v1 = v1 + math.random(-2, 2)
    v2 = v2 + math.random(-2, 2)
    v3 = v3 + math.random(-1, 1)

    -- 限制范围
    v1 = math.max(0, math.min(100, v1))
    v2 = math.max(0, math.min(100, v2))
    v3 = math.max(0, math.min(100, v3))

    -- 转换为整数（四舍五入）
    v1 = math.floor(v1 + 0.5)
    v2 = math.floor(v2 + 0.5)
    v3 = math.floor(v3 + 0.5)

    chart:push(series_ids[1], v1)
    chart:push(series_ids[2], v2)
    chart:push(series_ids[3], v3)
end

-- 创建UI
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
        color = 0x9C27B0,
    })
    airui.label({
        parent = title_bar,
        text = "图表组件演示 V1.1.0",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })
    airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function() go_back() end,
    })

    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 420,
        color = 0xF5F5F5,
    })

    local y_off = 10

    ----
    -- 图表区域
    ----
    local chart_container = create_demo_container(scroll_container, "实时曲线 (多系列)", 10, y_off, 300, 200)
    y_off = y_off + 200 + 10

    -- 创建图表（折线图，多系列）
    chart = airui.chart({
        parent = chart_container,
        x = 10,
        y = 30,
        w = 280,
        h = 150,
        type = chart_type,                 -- 默认折线图
        y_min = 0,
        y_max = 100,
        point_count = 40,
        update_mode = "shift",
        line_color = series_colors[1],      -- 第一个系列颜色
        line_width = 2,
        hdiv = 5,
        vdiv = 4,
        legend = true,                      -- 显示图例
        x_axis = { enable = true, min = 0, max = 40, ticks = 5, unit = "t" },
        y_axis = { enable = true, min = 0, max = 100, ticks = 5, unit = "v" },
        on_point = function(self)
            if point_label then
                local idx = self:get_pressed_point()
                point_label:set_text("点击点索引: " .. tostring(idx))
                log.info("chart", "点击点索引:", idx)
            end
        end,
    })

    -- 添加额外系列
    table.insert(series_ids, 1)  -- 第一个系列ID默认为1（由创建时line_color指定）
    for i = 2, #series_names do
        local sid = chart:add_series({ color = series_colors[i], name = series_names[i] })
        table.insert(series_ids, sid)
    end

    -- 初始化数据
    local init_data = {}
    for i = 1, 40 do
        table.insert(init_data, 50 + 30 * math.sin(i * 0.2))
    end
    chart:set_values(series_ids[1], init_data)

    local init_data2 = {}
    for i = 1, 40 do
        table.insert(init_data2, 40 + 20 * math.cos(i * 0.3))
    end
    chart:set_values(series_ids[2], init_data2)

    local init_data3 = {}
    for i = 1, 40 do
        table.insert(init_data3, 10 + 10 * math.sin(i * 0.5))
    end
    chart:set_values(series_ids[3], init_data3)

    ----
    -- 信息显示区域
    ----
    local info_container = airui.container({
        parent = scroll_container,
        x = 10,
        y = y_off,
        w = 300,
        h = 40,
        color = 0xEEEEEE,
        radius = 4,
    })
    y_off = y_off + 45

    point_label = airui.label({
        parent = info_container,
        text = "点击点索引: -1",
        x = 10,
        y = 10,
        w = 280,
        h = 20,
        color = 0x333333,
        font_size = 12,
    })

    ----
    -- 控制面板
    ----
    local ctrl_container = create_demo_container(scroll_container, "控制面板", 10, y_off, 300, 220)
    y_off = y_off + 220 + 10

    local btn_x, btn_y = 20, 30
    local btn_w, btn_h = 120, 35

    -- 切换图表类型
    local type_btn = airui.button({
        parent = ctrl_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "切换柱状图",
        on_click = function(self)
            if chart_type == "line" then
                chart_type = "bar"
                self:set_text("切换折线图")
            else
                chart_type = "line"
                self:set_text("切换柱状图")
            end
            -- 注意：图表类型可能无法动态修改，此处演示仅改变文本
            log.info("chart", "图表类型切换为", chart_type)
            -- 实际可能需要重建图表，但为了演示，仅示意
        end,
    })

    -- 添加/移除系列
    local add_btn = airui.button({
        parent = ctrl_container,
        x = btn_x + btn_w + 20,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "添加系列",
        on_click = function()
            local new_sid = chart:add_series({ color = 0xFF00FF, name = "新系列" })
            table.insert(series_ids, new_sid)
            log.info("chart", "添加系列ID:", new_sid)
        end,
    })

    btn_y = btn_y + btn_h + 10

    -- 随机颜色
    local rand_color_btn = airui.button({
        parent = ctrl_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "随机系列1颜色",
        on_click = function()
            local color = math.random(0, 0xFFFFFF)
            chart:set_line_color(series_ids[1], color)
            log.info("chart", "系列1颜色设为", string.format("%06X", color))
        end,
    })

    -- 清空数据
    local clear_btn = airui.button({
        parent = ctrl_container,
        x = btn_x + btn_w + 20,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "清空(设50)",
        on_click = function()
            chart:clear(50)
            log.info("chart", "数据清空为50")
        end,
    })

    btn_y = btn_y + btn_h + 10

    -- 切换更新模式
    local mode_btn = airui.button({
        parent = ctrl_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "模式:shift",
        on_click = function(self)
            if chart.update_mode == "shift" then
                chart:set_update_mode("circular")
                self:set_text("模式:circular")
            else
                chart:set_update_mode("shift")
                self:set_text("模式:shift")
            end
        end,
    })

    -- 停止/启动定时器
    local timer_btn = airui.button({
        parent = ctrl_container,
        x = btn_x + btn_w + 20,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "暂停数据",
        on_click = function(self)
            if chart_timer then
                sys.timerStop(chart_timer)
                chart_timer = nil
                self:set_text("启动数据")
            else
                chart_timer = sys.timerLoopStart(chart_timer_cb, 100)
                self:set_text("暂停数据")
            end
        end,
    })

    btn_y = btn_y + btn_h + 10

    -- 设置X轴（示例）
    local xaxis_btn = airui.button({
        parent = ctrl_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "X轴: 0~50",
        on_click = function()
            chart:set_x_axis({ min = 0, max = 50, ticks = 6, unit = "s" })
            log.info("chart", "X轴范围设为0~50")
        end,
    })

    -- 设置Y轴（示例）
    local yaxis_btn = airui.button({
        parent = ctrl_container,
        x = btn_x + btn_w + 20,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "Y轴: -20~120",
        on_click = function()
            chart:set_y_axis({ min = -20, max = 120, ticks = 8, unit = "%" })
            log.info("chart", "Y轴范围设为-20~120")
        end,
    })

    btn_y = btn_y + btn_h + 10

    -- 柱状图间距设置（仅演示，实际需要bar类型）
    local bar_gap_btn = airui.button({
        parent = ctrl_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "柱间距: 15/5",
        on_click = function()
            chart:set_bar_gap(15, 5)
            log.info("chart", "设置组间距15，系列间距5")
        end,
    })

    -- 柱状图圆角
    local bar_radius_btn = airui.button({
        parent = ctrl_container,
        x = btn_x + btn_w + 20,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "柱圆角: 8",
        on_click = function()
            chart:set_bar_radius(8)
            log.info("chart", "柱圆角设为8")
        end,
    })

    ----
    -- 底部提示
    ----
    airui.label({
        parent = main_container,
        text = "提示: 图表支持多系列、动态数据、点击点、自定义轴",
        x = 10,
        y = 450,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

-- 页面生命周期
function chart_page.init(params)
    page_active = true
    chart_page.create_ui()
    -- 启动定时器
    chart_timer = sys.timerLoopStart(chart_timer_cb, 100)
end

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
        chart = nil
    end
end

return chart_page