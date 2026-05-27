--[[
@module  settings_storage_priority_win
@summary 存储优先级配置窗口
@version 1.0
@date    2026.05.13
@author  江访
@usage
用户可以在此页面调整 app 安装存储位置的优先级（上移/下移）。
默认优先级：外挂TF卡 > 外挂Flash > 内置文件系统
]]

local window_id = nil
local main_container = nil
local titlebar = require "settings_titlebar"

local screen_w, screen_h = 480, 800
local margin = 10
local card_w = 460
local card_h = 80
local card_gap = 12

-- 当前显示的优先级列表（含 UI 组件引用）
local priority_items = {}
local content_area = nil
local titlebar_height = 0
local title_bar = nil  -- 标题栏引用，重建时需销毁旧实例

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.04)
    card_w = screen_w - 2 * margin
    card_h = math.max(48, math.floor(screen_h * 0.12))
    card_gap = math.floor(screen_h * 0.015)
end

-- 将当前 UI 上的优先级顺序编码为 type_key 数组并保存
local function save_current_priority()
    local priority_list = {}
    for _, item in ipairs(priority_items) do
        if item.type_key then
            table.insert(priority_list, item.type_key)
        end
    end
    if #priority_list > 0 then
        sys.publish("STORAGE_PRIORITY_SET", priority_list)
    end
end

-- 交换相邻两项并重建 UI
local function swap_and_rebuild(index_a, index_b)
    local item_a = priority_items[index_a]
    local item_b = priority_items[index_b]
    if not item_a or not item_b then return end
    priority_items[index_a] = item_b
    priority_items[index_b] = item_a
    rebuild_priority_list()
    save_current_priority()
end

-- 重建优先级列表 UI
function rebuild_priority_list()
    -- 销毁旧卡片
    for _, item in ipairs(priority_items) do
        if item.container then
            item.container:destroy()
        end
    end

    -- 保留数据，清空引用
    local saved_list = {}
    for _, item in ipairs(priority_items) do
        table.insert(saved_list, {
            type_key    = item.type_key,
            label       = item.label,
            description = item.description,
        })
    end
    priority_items = {}

    -- 清理内容区并重建
    if content_area then
        content_area:destroy()
    end
    content_area = airui.container({
        parent = main_container,
        x = 0,
        y = titlebar_height,
        w = screen_w,
        h = screen_h - titlebar_height,
        color = COLOR_BG,
        scrollable = true,
    })

    -- 重建标题栏，保持在内容区上层以接收触摸事件
    if title_bar then
        title_bar:destroy()
    end
    title_bar = titlebar.create(main_container, "存储顺序", screen_w, function()
        exwin.close(window_id)
    end)

    local current_y = margin + math.floor(10 * _G.density_scale)

    -- 提示文字
    airui.label({
        parent = content_area,
        x = margin + math.floor(12 * _G.density_scale),
        y = current_y,
        w = card_w - math.floor(24 * _G.density_scale),
        h = math.floor(40 * _G.density_scale),
        text = "安装 app 时将按从上到下的顺序尝试存储位置",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    current_y = current_y + math.floor(50 * _G.density_scale)

    for i, item_data in ipairs(saved_list) do
        local rank_label_text
        if i == 1 then
            rank_label_text = "第一优先级"
        elseif i == 2 then
            rank_label_text = "第二优先级"
        elseif i == 3 then
            rank_label_text = "第三优先级"
        else
            rank_label_text = "第" .. i .. "优先级"
        end

        local card = airui.container({
            parent = content_area,
            x = margin,
            y = current_y,
            w = card_w,
            h = card_h,
            color = COLOR_CARD,
            radius = 12,
            border_width = 1,
            border_color = (i == 1) and COLOR_PRIMARY or COLOR_DIVIDER,
        })

        -- 序号标签
        airui.label({
            parent = card,
            x = math.floor(16 * _G.density_scale),
            y = math.floor(10 * _G.density_scale),
            w = math.floor(100 * _G.density_scale),
            h = math.floor(22 * _G.density_scale),
            text = rank_label_text,
            font_size = math.floor(14 * _G.density_scale),
            color = (i == 1) and COLOR_PRIMARY or COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT,
        })

        -- 存储名称
        airui.label({
            parent = card,
            x = math.floor(16 * _G.density_scale),
            y = math.floor(34 * _G.density_scale),
            w = card_w - math.floor(150 * _G.density_scale),
            h = math.floor(26 * _G.density_scale),
            text = item_data.label or item_data.type_key,
            font_size = math.floor(20 * _G.density_scale),
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT,
        })

        -- 上移按钮（第一项不显示）
        if i > 1 then
            airui.button({
                parent = card,
                x = card_w - math.floor(140 * _G.density_scale),
                y = math.floor((card_h - 36 * _G.density_scale) / 2),
                w = math.floor(60 * _G.density_scale),
                h = math.floor(36 * _G.density_scale),
                text = "上移",
                font_size = math.floor(16 * _G.density_scale),
                style = {
                    bg_color = COLOR_PRIMARY,
                    pressed_bg_color = COLOR_PRIMARY_DARK,
                    text_color = COLOR_WHITE,
                    radius = 8,
                    border_width = 0,
                },
                on_click = function()
                    swap_and_rebuild(i, i - 1)
                end,
            })
        end

        -- 下移按钮（最后一项不显示）
        if i < #saved_list then
            airui.button({
                parent = card,
                x = card_w - math.floor(72 * _G.density_scale),
                y = math.floor((card_h - 36 * _G.density_scale) / 2),
                w = math.floor(60 * _G.density_scale),
                h = math.floor(36 * _G.density_scale),
                text = "下移",
                font_size = math.floor(16 * _G.density_scale),
                style = {
                    bg_color = COLOR_TEXT_SECONDARY,
                    pressed_bg_color = COLOR_TEXT,
                    text_color = COLOR_WHITE,
                    radius = 8,
                    border_width = 0,
                },
                on_click = function()
                    swap_and_rebuild(i, i + 1)
                end,
            })
        end

        priority_items[i] = {
            type_key    = item_data.type_key,
            label       = item_data.label,
            description = item_data.description,
            container   = card,
        }

        current_y = current_y + card_h + card_gap
    end
end

local STORAGE_LABELS = {
    sd_tf = "外挂TF卡", little_flash = "外挂Flash", internal = "内置文件系统",
}

local function on_priority_value(priority_list)
    priority_items = {}
    for i, type_key in ipairs(priority_list) do
        table.insert(priority_items, {
            type_key    = type_key,
            label       = STORAGE_LABELS[type_key] or type_key,
            description = "",
            rank        = i,
        })
    end
    rebuild_priority_list()
end

local function build_ui()
    update_screen_size()

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = COLOR_BG,
    })

    -- 标题栏高度（与 titlebar.create 内部计算一致）
    local density = _G.density_scale or 1.0
    titlebar_height = math.floor(60 * density)

    -- 先创建可滚动内容区（在下层），再创建标题栏（在上层接收触摸）
    content_area = airui.container({
        parent = main_container,
        x = 0, y = titlebar_height,
        w = screen_w, h = screen_h - titlebar_height,
        color = COLOR_BG, scrollable = true,
    })

    title_bar = titlebar.create(main_container, "存储顺序", screen_w, function()
        exwin.close(window_id)
    end)
end

local function on_create()
    build_ui()
    sys.subscribe("STORAGE_PRIORITY_VALUE", on_priority_value)
    -- 请求当前配置
    sys.publish("STORAGE_PRIORITY_GET")
end

local function on_destroy()
    sys.unsubscribe("STORAGE_PRIORITY_VALUE", on_priority_value)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    priority_items = {}
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create    = on_create,
        on_destroy   = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_STORAGE_PRI_WIN", open_handler)
