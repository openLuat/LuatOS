--[[
@module  di_win
@summary DI状态页面，显示DI1/DI2输入状态及历史记录
@version 1.0.0
@date    2026.07.30
@author  合宙 Air8301
@usage
本页面以圆形指示器和文字显示DI1和DI2的当前状态（ON/OFF），
下方显示状态变更历史记录。
监听 DI_STATUS_CHANGED 消息更新。
]]

local win_id = nil
local main_container, content
local di1_circle, di1_label, di2_circle, di2_label
local history_text_list = {}
local history_label

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x4CAF50
local COLOR_GRAY = 0x000000

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
DI状态变更消息回调

@local
@function on_di_status_changed
@param di1 boolean DI1状态（true=ON, false=OFF）
@param di2 boolean DI2状态（true=ON, false=OFF）
]]
local function on_di_status_changed(di1, di2)
    if not exwin.is_active(win_id) then return end
    if di1_circle and di1_label then
        if di1 then
            di1_circle:set_color(COLOR_GREEN)
            di1_label:set_text("ON")
            di1_label:set_color(COLOR_GREEN)
        else
            di1_circle:set_color(COLOR_GRAY)
            di1_label:set_text("OFF")
            di1_label:set_color(COLOR_SECONDARY)
        end
    end
    if di2_circle and di2_label then
        if di2 then
            di2_circle:set_color(COLOR_GREEN)
            di2_label:set_text("ON")
            di2_label:set_color(COLOR_GREEN)
        else
            di2_circle:set_color(COLOR_GRAY)
            di2_label:set_text("OFF")
            di2_label:set_color(COLOR_SECONDARY)
        end
    end

    -- 记录历史
    local time_str = os.date("%H:%M:%S")
    local status_str = "DI1:" .. (di1 and "ON" or "OFF") .. " DI2:" .. (di2 and "ON" or "OFF")
    table.insert(history_text_list, time_str .. " " .. status_str)
    if #history_text_list > 20 then
        table.remove(history_text_list, 1)
    end
    if history_label then
        history_label:set_text(table.concat(history_text_list, "\n"))
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 0,
        y = 0,
        w = 60,
        h = 44,
        on_click = on_back_click
    })
    airui.label({
        parent = back_btn,
        x = 5,
        y = 10,
        w = 50,
        h = 24,
        text = "< 返回",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = header,
        x = 60,
        y = 8,
        w = 360,
        h = 28,
        text = "DI输入",
        font_size = 20,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 44,
        w = 480,
        h = 228,
        color = COLOR_BG
    })

    -- DI1 和 DI2 卡片
    local di_card = airui.container({
        parent = content,
        x = 10,
        y = 10,
        w = 460,
        h = 80,
        color = COLOR_CARD,
        radius = 6
    })

    -- DI1
    airui.label({
        parent = di_card,
        x = 20,
        y = 6,
        w = 60,
        h = 20,
        text = "DI1",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    -- DI1圆形指示器（用container模拟圆形）
    di1_circle = airui.container({
        parent = di_card,
        x = 30,
        y = 34,
        w = 24,
        h = 24,
        color = COLOR_GRAY,
        radius = 12
    })
    di1_label = airui.label({
        parent = di_card,
        x = 60,
        y = 32,
        w = 60,
        h = 24,
        text = "OFF",
        font_size = 18,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- DI2
    airui.label({
        parent = di_card,
        x = 250,
        y = 6,
        w = 60,
        h = 20,
        text = "DI2",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    -- DI2圆形指示器
    di2_circle = airui.container({
        parent = di_card,
        x = 260,
        y = 34,
        w = 24,
        h = 24,
        color = COLOR_GRAY,
        radius = 12
    })
    di2_label = airui.label({
        parent = di_card,
        x = 290,
        y = 32,
        w = 60,
        h = 24,
        text = "OFF",
        font_size = 18,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 历史记录卡片
    local history_card = airui.container({
        parent = content,
        x = 10,
        y = 100,
        w = 460,
        h = 118,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = history_card,
        x = 10,
        y = 4,
        w = 120,
        h = 18,
        text = "历史记录",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    history_label = airui.label({
        parent = history_card,
        x = 10,
        y = 24,
        w = 440,
        h = 90,
        text = "暂无记录",
        font_size = 12,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("DI_STATUS_CHANGED", on_di_status_changed)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    di1_circle = nil
    di1_label = nil
    di2_circle = nil
    di2_label = nil
    history_label = nil
    history_text_list = {}
    sys.unsubscribe("DI_STATUS_CHANGED", on_di_status_changed)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 不需要特殊处理
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus()
    -- 不需要特殊处理
end

--[[
OPEN_DI_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_DI_WIN", open_handler)
