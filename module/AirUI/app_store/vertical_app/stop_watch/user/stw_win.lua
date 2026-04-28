--[[
@module  stw_win
@summary 秒表窗口模块 - 白色风格，支持圈速记录
@version 1.0
@date    2026.04.01
@author  许璐
@usage
本模块实现高精度秒表功能，包括：
1. 计时显示格式 MM:SS.xxx (分:秒.毫秒)
2. 开始/暂停/重置/圈速记录
3. 圈速列表展示（最新在上）
4. 清空记录功能
]]

local win_id = nil
local main_container, content

-- UI 组件
local timer_display
local start_btn, pause_btn, reset_btn, lap_btn
local records_container
local clear_records_btn
local empty_records_label

-- 秒表核心变量
local is_running = false
local elapsed_ms = 0        -- 累计毫秒数（总计时）
local start_ticks = 0       -- 开始/继续时刻的 ticks 值
local pause_elapsed_ms = 0  -- 暂停时已累计的毫秒数
local timer_task = nil

-- 圈速记录数据
local lap_records = {}
local next_lap_number = 1
local record_items = {}

-- 格式化时间: 毫秒 -> MM:SS.xxx
local function format_time(ms)
    if ms < 0 then ms = 0 end
    local total_ms = math.floor(ms)
    local total_seconds = math.floor(total_ms / 1000)
    local minutes = math.floor(total_seconds / 60)
    local seconds = total_seconds % 60
    local millis = total_ms % 1000
    return string.format("%02d:%02d.%03d", minutes, seconds, millis)
end

-- 更新计时显示
local function update_display()
    if timer_display then
        timer_display:set_text(format_time(elapsed_ms))
    end
end

-- 停止计时器（统一处理）
local function stop_timer()
    if timer_task then
        sys.timerStop(timer_task)
        timer_task = nil
    end
    is_running = false
end

-- 重置计时状态变量
local function reset_timer_state()
    elapsed_ms = 0
    start_ticks = 0
    pause_elapsed_ms = 0
    next_lap_number = 1
end

-- 按钮反馈动画（通用）
local function button_feedback(btn, highlight_style, original_style)
    if btn then
        btn:set_style(highlight_style)
        sys.timerStart(function()
            if btn then
                btn:set_style(original_style)
            end
        end, 100)
    end
end

-- 创建计时器任务
local function start_timer_task()
    timer_task = sys.timerLoopStart(function()
        if not is_running then return end
        local current_ticks = mcu.ticks()
        local diff_ticks = current_ticks - start_ticks
        local current_segment_ms = math.floor(diff_ticks)
        local new_elapsed_ms = pause_elapsed_ms + current_segment_ms
        if new_elapsed_ms ~= elapsed_ms then
            elapsed_ms = new_elapsed_ms
            update_display()
        end
    end, 10)
end

-- 恢复暂停按钮为"暂停"状态
local function reset_pause_button_text()
    if pause_btn then
        pause_btn:set_text("暂停")
    end
end

-- 渲染圈速列表
local function render_records()
    if not records_container then return end

    -- 清空现有记录项
    for _, item in ipairs(record_items) do
        if item.container then
            item.container:destroy()
        end
    end
    record_items = {}

    -- 处理空记录状态
    if #lap_records == 0 then
        if empty_records_label then
            empty_records_label:set_text("暂无记录，点击「记录」添加圈速")
        end
        return
    else
        if empty_records_label then
            empty_records_label:set_text("")
        end
    end
    
    -- 从最新到最旧遍历显示（最新在上）
    local scroll_y = 8
    local item_height = 50
    local item_spacing = 6
    local max_records = math.min(#lap_records, 30)

    for i = #lap_records, #lap_records - max_records + 1, -1 do
        if i < 1 then break end
        local rec = lap_records[i]

        local item_container = airui.container({
            parent = records_container,
            x = 12,
            y = scroll_y,
            w = 432,
            h = item_height,
            color = 0xF8FAFC,
            radius = 22,
        })

        -- 左侧蓝色装饰条
        airui.container({
            parent = item_container,
            x = 0,
            y = 7,
            w = 4,
            h = 36,
            color = 0x3B82F6,
            radius = 2
        })

        -- 圈速编号
        airui.label({
            parent = item_container,
            x = 16,
            y = 10,
            w = 60,
            h = 30,
            text = string.format("#%d", rec.lap_number),
            font_size = 18,
            color = 0x2563EB,
            align = airui.TEXT_ALIGN_LEFT
        })

        -- 圈速时间（增大字体和宽度）
        airui.label({
            parent = item_container,
            x = 85,
            y = 10,
            w = 340,
            h = 30,
            text = rec.time_str,
            font_size = 26,
            color = 0x1A1A1A,
            align = airui.TEXT_ALIGN_RIGHT
        })

        table.insert(record_items, { container = item_container })
        scroll_y = scroll_y + item_height + item_spacing
    end
end

-- 添加新圈速
local function add_lap()
    if not is_running then
        -- 未运行时点击记录，通过短暂改变文字提示用户
        if timer_display then
            local original_text = timer_display:get_text()
            timer_display:set_text("请先开始计时")
            sys.timerStart(function()
                if timer_display then
                    timer_display:set_text(original_text)
                end
            end, 200)
        end
        return
    end
    
    local current_ms = elapsed_ms
    local formatted = format_time(current_ms)
    table.insert(lap_records, {
        lap_number = next_lap_number,
        time_str = formatted,
        raw_ms = current_ms
    })
    next_lap_number = next_lap_number + 1
    
    -- 限制最多100条记录
    if #lap_records > 100 then
        table.remove(lap_records, 1)
    end

    render_records()
end

-- 清空所有圈速记录
local function clear_records()
    if #lap_records == 0 then return end
    lap_records = {}
    next_lap_number = 1
    render_records()

    -- 按钮反馈
    button_feedback(
        clear_records_btn,
        {
            bg_color = 0xE6EDF4,
            pressed_bg_color = 0xE6EDF4,
            text_color = 0xEF4444,
            pressed_text_color = 0xDC2626,
            radius = 40,
        },
        {
            bg_color = 0xF1F5F9,
            pressed_bg_color = 0xE6EDF4,
            text_color = 0xEF4444,
            pressed_text_color = 0xDC2626,
            radius = 40,
        }
    )
end

-- 重置秒表（清零计时，重置编号但保留圈速记录）
local function reset_stopwatch()
    stop_timer()
    reset_timer_state()
    update_display()
    reset_pause_button_text()

    -- 按钮反馈
    button_feedback(
        reset_btn,
        {
            bg_color = 0x8B9DC0,
            pressed_bg_color = 0x8B9DC0,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        {
            bg_color = 0x94A3B8,
            pressed_bg_color = 0x64748B,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        }
    )
end

-- 开始/重置计时（清零并开始新的一轮）
local function start_timer()
    stop_timer()
    reset_timer_state()
    is_running = true
    start_ticks = mcu.ticks()
    start_timer_task()
    reset_pause_button_text()

    -- 按钮反馈
    button_feedback(
        start_btn,
        {
            bg_color = 0x16A34A,
            pressed_bg_color = 0x16A34A,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        {
            bg_color = 0x22C55E,
            pressed_bg_color = 0x16A34A,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        }
    )
end

-- 暂停/继续计时（根据当前状态切换）
local function toggle_pause()
    if is_running then
        -- 暂停计时：保存当前累计时间
        pause_elapsed_ms = elapsed_ms
        stop_timer()
        if pause_btn then
            pause_btn:set_text("继续")
        end
    else
        -- 检查是否有累计时间，如果没有则不继续（避免在00:00.000时点击开始计时）
        if pause_elapsed_ms == 0 and elapsed_ms == 0 then
            return
        end
        -- 继续计时：从新的 ticks 开始，但保留之前累计的时间
        is_running = true
        start_ticks = mcu.ticks()
        start_timer_task()
        if pause_btn then
            pause_btn:set_text("暂停")
        end
    end

    -- 按钮反馈
    button_feedback(
        pause_btn,
        {
            bg_color = 0xEA580C,
            pressed_bg_color = 0xEA580C,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        {
            bg_color = 0xF97316,
            pressed_bg_color = 0xEA580C,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        }
    )
end

-- 创建UI界面
local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xF8F9FA
    })
    
    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 60,
        color = 0x3F51B5
    })
    
    -- 返回按钮
    local back_btn = airui.container({
        parent = title_bar,
        x = 390,
        y = 15,
        w = 80,
        h = 40,
        color = 0x2195F6,
        radius = 5,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({
        parent = back_btn,
        x = 10,
        y = 10,
        w = 60,
        h = 24,
        text = "返回",
        font_size = 20,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 标题文字
    airui.label({
        parent = title_bar,
        x = 10,
        y = 12,
        w = 460,
        h = 40,
        text = "秒表",
        font_size = 32,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 480,
        h = 740,
        color = 0xF8F9FA
    })
    
    -- 计时面板（浅蓝色）
    local timer_panel = airui.container({
        parent = content,
        x = 20,
        y = 20,
        w = 440,
        h = 160,
        color = 0xBFDBEE,
        radius = 48,
    })

    timer_display = airui.label({
        parent = timer_panel,
        x = 0,
        y = 30,
        w = 440,
        h = 100,
        text = "00:00.000",
        font_size = 58,
        color = 0x1A1A1A,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = timer_panel,
        x = 0,
        y = 120,
        w = 440,
        h = 30,
        text = "当前计时 | 精确到毫秒",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 按钮区域 (4个按钮一行)
    local btn_y = 200
    local btn_w = 100
    local btn_h = 50
    local btn_spacing = 10
    local start_x = (480 - (btn_w * 4 + btn_spacing * 3)) / 2

    -- 开始按钮（清零并开始）
    start_btn = airui.button({
        parent = content,
        x = start_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "开始",
        font_size = 20,
        style = {
            bg_color = 0x22C55E,
            pressed_bg_color = 0x16A34A,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        on_click = function()
            start_timer()
        end
    })

    -- 暂停/继续按钮
    pause_btn = airui.button({
        parent = content,
        x = start_x + btn_w + btn_spacing,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "暂停",
        font_size = 20,
        style = {
            bg_color = 0xF97316,
            pressed_bg_color = 0xEA580C,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        on_click = function()
            toggle_pause()
        end
    })

    -- 重置按钮
    reset_btn = airui.button({
        parent = content,
        x = start_x + (btn_w + btn_spacing) * 2,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "重置",
        font_size = 20,
        style = {
            bg_color = 0x94A3B8,
            pressed_bg_color = 0x64748B,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        on_click = function()
            reset_stopwatch()
        end
    })

    -- 记录按钮
    lap_btn = airui.button({
        parent = content,
        x = start_x + (btn_w + btn_spacing) * 3,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "记录",
        font_size = 20,
        style = {
            bg_color = 0x3B82F6,
            pressed_bg_color = 0x2563EB,
            text_color = 0xFFFFFF,
            radius = 60,
            border_width = 0
        },
        on_click = function()
            add_lap()
        end
    })
    
    -- 圈速记录面板
    local records_panel = airui.container({
        parent = content,
        x = 12,
        y = 270,
        w = 456,
        h = 340,
        color = 0xFEFEFE,
        radius = 32,
    })
    
    -- 面板标题
    airui.label({
        parent = records_panel,
        x = 16,
        y = 12,
        w = 200,
        h = 30,
        text = "圈速记录 (最新在上)",
        font_size = 16,
        color = 0x334155,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = records_panel,
        x = 360,
        y = 12,
        w = 80,
        h = 30,
        text = "MM:SS.xxx",
        font_size = 12,
        color = 0x94A3B8,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 分隔线
    airui.container({
        parent = records_panel,
        x = 12,
        y = 45,
        w = 432,
        h = 2,
        color = 0xEEF2F8
    })
    
    -- 记录列表容器
    records_container = airui.container({
        parent = records_panel,
        x = 0,
        y = 50,
        w = 456,
        h = 280,
        color = 0xFEFEFE
    })
    
    -- 空记录提示
    empty_records_label = airui.label({
        parent = records_container,
        x = 0,
        y = 100,
        w = 456,
        h = 60,
        text = "暂无记录，点击「记录」添加圈速",
        font_size = 16,
        color = 0x64748B,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 清空记录按钮（独立放置，在面板下方）
    clear_records_btn = airui.button({
        parent = content,
        x = 120,
        y = 620,
        w = 240,
        h = 44,
        text = "清空所有记录",
        font_size = 18,
        style = {
            bg_color = 0xF1F5F9,
            pressed_bg_color = 0xE6EDF4,
            text_color = 0xEF4444,
            pressed_text_color = 0xDC2626,
            radius = 40,
        },
        on_click = function()
            clear_records()
        end
    })
    
    -- 初始化显示
    update_display()
    render_records()
end

-- 窗口生命周期回调
local function on_create()
    create_ui()
end

local function on_destroy()
    if is_running and timer_task then
        sys.timerStop(timer_task)
        timer_task = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    timer_display = nil
    start_btn, pause_btn, reset_btn, lap_btn = nil, nil, nil, nil
    records_container = nil
    clear_records_btn = nil
    empty_records_label = nil
    record_items = {}
    win_id = nil
end

local function on_get_focus()
    update_display()
    render_records()
end

local function on_lose_focus()
    -- 失去焦点时不操作
end

-- 窗口打开处理函数
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

-- 订阅窗口打开事件
sys.subscribe("OPEN_STW_WIN", open_handler)

return {
    start_timer = start_timer,
    toggle_pause = toggle_pause,
    reset_stopwatch = reset_stopwatch,
    add_lap = add_lap,
    clear_records = clear_records
}