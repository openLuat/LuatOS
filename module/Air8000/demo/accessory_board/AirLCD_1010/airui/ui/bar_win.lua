--[[
@module  bar_win
@summary 进度条组件演示窗口
@version 1.1.0
@date    2026.03.18
@author  江访
@usage
本文件是进度条组件的演示窗口，展示进度条的各种用法，支持动画和颜色自定义。
]]


local win_id = nil
local main_container = nil
local scroll_container = nil
local animated_bar = nil
local value_label = nil
local update_timer = nil
local start_btn = nil

local SCREEN_W, SCREEN_H = 320, 480
local MARGIN = 15
local COMPONENT_H = 36
local SPACING = 10

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 50,
        color = 0x9C27B0,
    })
    airui.label({
        parent = title_bar,
        text = "进度条组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })
    airui.button({
        parent = title_bar,
        x = SCREEN_W - 70,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function() exwin.close(win_id) end,
    })

    -- 滚动容器
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = SCREEN_W,
        h = SCREEN_H - 100,
        color = 0xF5F5F5,
    })

    local y_pos = MARGIN

    -- 示例1：基本进度条
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本进度条",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })
    y_pos = y_pos + 25
    airui.bar({
        parent = scroll_container,
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        value = 30,
        min = 0,
        max = 100,
        radius = 10,
        indicator_color = 0x4CAF50,
    })
    y_pos = y_pos + 30

    -- 示例2：带边框进度条
    airui.label({
        parent = scroll_container,
        text = "示例2: 带边框进度条",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })
    y_pos = y_pos + 25
    airui.bar({
        parent = scroll_container,
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 25,
        value = 50,
        min = 0,
        max = 100,
        radius = 12,
        border_width = 2,
        border_color = 0x9C27B0,
        indicator_color = 0x9C27B0,
        bg_color = 0xF3E5F5,
    })
    y_pos = y_pos + 35

    -- 示例3：动画进度条
    airui.label({
        parent = scroll_container,
        text = "示例3: 动画进度条",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })
    y_pos = y_pos + 25

    animated_bar = airui.bar({
        parent = scroll_container,
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 25,
        value = 0,
        min = 0,
        max = 100,
        radius = 12,
        indicator_color = 0x2196F3,
        show_progress_text = true,
        progress_text_format = "%d%%",
    })
    y_pos = y_pos + 35

    value_label = airui.label({
        parent = scroll_container,
        text = "当前值: 0%",
        x = SCREEN_W - 100,
        y = y_pos - 30,
        w = 90,
        h = 25,
        font_size = 14,
        align = "right",
    })

    start_btn = airui.button({
        parent = scroll_container,
        x = MARGIN,
        y = y_pos,
        w = 80,
        h = 35,
        text = "开始",
        on_click = function(self)
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                self:set_text("开始")
            else
                self:set_text("停止")
                update_timer = sys.timerLoopStart(function()
                    local current = animated_bar:get_value()
                    if current >= 100 then
                        current = 0
                    else
                        current = current + 5
                    end
                    animated_bar:set_value(current, true)
                    value_label:set_text("当前值: " .. current .. "%")
                    if current >= 100 then
                        sys.timerStop(update_timer)
                        update_timer = nil
                        start_btn:set_text("开始")
                    end
                end, 200)
            end
        end,
    })

    airui.button({
        parent = scroll_container,
        x = MARGIN + 90,
        y = y_pos,
        w = 80,
        h = 35,
        text = "重置",
        on_click = function()
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                start_btn:set_text("开始")
            end
            animated_bar:set_value(0, true)
        end,
    })
    y_pos = y_pos + 45

    -- 示例4：不同颜色进度条
    airui.label({
        parent = scroll_container,
        text = "示例4: 不同颜色进度条",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
        color = 0x333333,
    })
    y_pos = y_pos + 25

    local color_bar = airui.bar({
        parent = scroll_container,
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        value = 75,
        min = 0,
        max = 100,
        radius = 10,
        indicator_color = 0xFF5722,
    })
    y_pos = y_pos + 30

    local colors = { { "红色", 0xF44336 }, { "绿色", 0x4CAF50 }, { "蓝色", 0x2196F3 }, { "紫色", 0x9C27B0 } }
    for i, c in ipairs(colors) do
        airui.button({
            parent = scroll_container,
            x = MARGIN + (i - 1) * 75,
            y = y_pos,
            w = 65,
            h = 30,
            text = c[1],
            on_click = function() color_bar:set_indicator_color(c[2]) end,
        })
    end
    y_pos = y_pos + 40

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示: 进度条支持动画和颜色自定义",
        x = MARGIN,
        y = SCREEN_H - 30,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
        color = 0x666666,
    })
end

local function on_create()
    math.randomseed(os.time())
    create_ui()
end

local function on_destroy()
    if update_timer then
        sys.timerStop(update_timer)
        update_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
        scroll_container = nil
    end
    win_id = nil
    log.info("bar_win", "窗口销毁")
end

local function on_get_focus()
    log.info("bar_win", "窗口获得焦点")
end

local function on_lose_focus()
    log.info("bar_win", "窗口失去焦点")
end

sys.subscribe("OPEN_BAR_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("bar_win", "窗口打开，ID:", win_id)
    end
end)