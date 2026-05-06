-- settings_storage_win.lua
--[[
@module  settings_storage_win
@summary 存储页面
@version 1.2
@date    2026.04.16
]]

require "settings_storage_app"
require "settings_memory_app"

local win_id = nil
local main_container

-- 存储相关UI
local total_label, used_label, free_label, progress_bar, percent_label

-- 内存相关UI
local sys_total_label, sys_used_label, sys_max_label, sys_percent_label, sys_progress_bar
local vm_total_label, vm_used_label, vm_max_label, vm_percent_label, vm_progress_bar
local psram_total_label, psram_used_label, psram_max_label, psram_percent_label, psram_progress_bar

local screen_w, screen_h = 480, 800
local margin = 20
local card_w = 440
local timer_id = nil

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_ACCENT         = 0xFF9800

local STORAGE_CARD_H
local MEMORY_CARD_H

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
    log.info("storage_win", "屏幕尺寸", screen_w, screen_h, "卡片宽度", card_w)
end

-- 存储信息更新
local function update_storage_info(info)
    if total_label then total_label:set_text(info.total or "--") end
    if used_label then used_label:set_text(info.used or "--") end
    if free_label then free_label:set_text(info.free or "--") end
    if info.used_percent and progress_bar then
        progress_bar:set_value(info.used_percent, true)
    end
    if info.used_percent and percent_label then
        percent_label:set_text("已使用 " .. info.used_percent .. "%")
    end
    log.info("storage_win", "存储信息已更新")
end

-- 内存工具函数
local function format_memory(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    if bytes < 1024 then return string.format("%d B", bytes)
    elseif bytes < 1024*1024 then return string.format("%.2f KB", bytes/1024)
    elseif bytes < 1024*1024*1024 then return string.format("%.2f MB", bytes/1024/1024)
    else return string.format("%.2f GB", bytes/1024/1024/1024) end
end

local function format_memory_full(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    local converted = format_memory(bytes)
    if bytes >= 1024 then
        return string.format("%d B (≈%s)", bytes, converted)
    else
        return string.format("%d B", bytes)
    end
end

local function calc_percent(used, total)
    if not used or not total or total == 0 then return 0 end
    return math.min(100, math.max(0, (used / total) * 100))
end

-- 内存信息更新
local function update_memory_info(info)
    if info.sys and sys_total_label then
        local pct = calc_percent(info.sys.used, info.sys.total)
        sys_total_label:set_text(format_memory(info.sys.total))
        sys_used_label:set_text(format_memory(info.sys.used))
        sys_max_label:set_text(format_memory(info.sys.max))
        sys_percent_label:set_text(string.format("%.1f%% 占用", pct))
        if sys_progress_bar then sys_progress_bar:set_value(math.floor(pct), false) end
    end
    if info.vm and vm_total_label then
        local pct = calc_percent(info.vm.used, info.vm.total)
        vm_total_label:set_text(format_memory(info.vm.total))
        vm_used_label:set_text(format_memory(info.vm.used))
        vm_max_label:set_text(format_memory(info.vm.max))
        vm_percent_label:set_text(string.format("%.1f%% 占用", pct))
        if vm_progress_bar then vm_progress_bar:set_value(math.floor(pct), false) end
    end
    if info.psram and psram_total_label then
        local pct = calc_percent(info.psram.used, info.psram.total)
        psram_total_label:set_text(format_memory(info.psram.total))
        psram_used_label:set_text(format_memory(info.psram.used))
        psram_max_label:set_text(format_memory(info.psram.max))
        psram_percent_label:set_text(string.format("%.1f%% 占用", pct))
        if psram_progress_bar then psram_progress_bar:set_value(math.floor(pct), false) end
    end
    log.info("storage_win", "内存信息已更新")
end

-- 创建信息行（辅助）
local function create_info_row(parent, y, label_text)
    local row = airui.container({
        parent = parent,
        x = math.floor(20 * _G.density_scale), y = y,
        w = card_w - math.floor(40 * _G.density_scale),
        h = math.floor(35 * _G.density_scale),
        color = COLOR_CARD
    })
    airui.label({
        parent = row,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = label_text,
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    local value_label = airui.label({
        parent = row,
        x = math.floor(110 * _G.density_scale), y = math.floor(5 * _G.density_scale),
        w = (card_w - math.floor(40 * _G.density_scale)) - math.floor(110 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "--",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })
    return value_label
end

-- 创建内存卡片（高度可调）
local function create_memory_card(parent, y, title, progress_color, card_height)
    local card = airui.container({
        parent = parent,
        x = margin, y = y,
        w = card_w, h = card_height,
        color = COLOR_WHITE,
        radius = 8
    })
    local m_pad = math.floor(12 * _G.density_scale)
    local m_title_h = math.floor(30 * _G.density_scale)
    local m_info_h = math.floor(35 * _G.density_scale)
    local m_bar_h = math.floor(18 * _G.density_scale)
    local m_gap = math.floor(4 * _G.density_scale)

    local y_title = m_pad
    local y_row1 = y_title + m_title_h + m_gap
    local y_row2 = y_row1 + m_info_h + m_gap
    local y_row3 = y_row2 + m_info_h + m_gap
    local y_bar = y_row3 + m_info_h + m_gap

    airui.label({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = y_title,
        w = math.floor(200 * _G.density_scale), h = m_title_h,
        text = title,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    local percent_label = airui.label({
        parent = card,
        x = card_w - math.floor(180 * _G.density_scale), y = y_title,
        w = math.floor(160 * _G.density_scale), h = m_title_h,
        text = "0% 占用",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local total_label = create_info_row(card, y_row1, "总内存")
    local used_label = create_info_row(card, y_row2, "当前使用")
    local max_label = create_info_row(card, y_row3, "历史峰值")
    local progress_bar = airui.bar({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = y_bar,
        w = card_w - math.floor(40 * _G.density_scale),
        h = m_bar_h,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = progress_color,
        radius = 8
    })
    return {
        total = total_label,
        used = used_label,
        max = max_label,
        percent = percent_label,
        progress = progress_bar
    }
end

local function create_ui()
    update_screen_size()

    local card_h = math.floor(screen_h * 0.20)
    if card_h < 140 then card_h = 140 end
    if card_h > 260 then card_h = 260 end

    local s_pad = math.floor(10 * _G.density_scale)
    local s_row_h = math.floor(28 * _G.density_scale)
    local s_bar_h = math.floor(18 * _G.density_scale)
    local s_small_h = math.floor(22 * _G.density_scale)
    local s_gap = math.floor(6 * _G.density_scale)
    local y_free = s_pad + s_row_h + s_gap + s_bar_h + math.floor(2 * _G.density_scale) + s_small_h + s_gap + s_small_h + s_gap
    local s_total = y_free + s_small_h + s_pad
    STORAGE_CARD_H = math.max(card_h, s_total)

    local m_pad = math.floor(12 * _G.density_scale)
    local m_title_h = math.floor(30 * _G.density_scale)
    local m_info_h = math.floor(35 * _G.density_scale)
    local m_bar_h = math.floor(18 * _G.density_scale)
    local m_gap = math.floor(4 * _G.density_scale)
    local y_bar = m_pad + m_title_h + m_gap + m_info_h + m_gap + m_info_h + m_gap + m_info_h + m_gap
    local m_total = y_bar + m_bar_h + m_pad + math.floor(8 * _G.density_scale)
    MEMORY_CARD_H = math.max(card_h, m_total)

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG
    })

    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY
    })

    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "存储",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 内容容器（支持滚动，防止高密度屏下内容溢出）
    local title_h = math.floor(60 * _G.density_scale)
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h,
        color = COLOR_BG,
        scrollable = true
    })

    local card_gap = math.floor(margin * 0.7)
    local current_y = margin

    -- 存储卡片内部相对布局（变量已在上方预计算）
    local y_title = s_pad
    local y_bar = y_title + s_row_h + s_gap
    local y_percent = y_bar + s_bar_h + math.floor(2 * _G.density_scale)
    local y_used = y_percent + s_small_h + s_gap
    local y_free = y_used + s_small_h + s_gap

    -- 存储卡片
    local card_storage = airui.container({
        parent = content,
        x = margin, y = current_y,
        w = card_w, h = STORAGE_CARD_H,
        color = COLOR_WHITE,
        radius = 8
    })
    current_y = current_y + STORAGE_CARD_H + card_gap

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = y_title,
        w = math.floor(100 * _G.density_scale), h = s_row_h,
        text = "总容量",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    total_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = y_title,
        w = math.floor(200 * _G.density_scale), h = s_row_h,
        text = "--",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    progress_bar = airui.bar({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = y_bar,
        w = card_w - math.floor(40 * _G.density_scale),
        h = s_bar_h,
        min = 0, max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 8
    })

    percent_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = y_percent,
        w = math.floor(200 * _G.density_scale), h = s_small_h,
        text = "已使用 --%",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = y_used,
        w = math.floor(100 * _G.density_scale), h = s_small_h,
        text = "已使用",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    used_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = y_used,
        w = math.floor(200 * _G.density_scale), h = s_small_h,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = y_free,
        w = math.floor(100 * _G.density_scale), h = s_small_h,
        text = "可用空间",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    free_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = y_free,
        w = math.floor(200 * _G.density_scale), h = s_small_h,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 内存卡片（使用高度 MEMORY_CARD_H = 180）
    local sys = create_memory_card(content, current_y, "系统内存", 0x4CAF50, MEMORY_CARD_H)
    sys_total_label, sys_used_label, sys_max_label, sys_percent_label, sys_progress_bar = sys.total, sys.used, sys.max, sys.percent, sys.progress
    current_y = current_y + MEMORY_CARD_H + card_gap

    local vm = create_memory_card(content, current_y, "Lua 虚拟机内存", COLOR_ACCENT, MEMORY_CARD_H)
    vm_total_label, vm_used_label, vm_max_label, vm_percent_label, vm_progress_bar = vm.total, vm.used, vm.max, vm.percent, vm.progress
    current_y = current_y + MEMORY_CARD_H + card_gap

    local psram = create_memory_card(content, current_y, "PSRAM 内存", 0x9C27B0, MEMORY_CARD_H)
    psram_total_label, psram_used_label, psram_max_label, psram_percent_label, psram_progress_bar = psram.total, psram.used, psram.max, psram.percent, psram.progress

    log.info("storage_win", "UI创建完成，总内容高度", current_y + MEMORY_CARD_H)
end

local function on_create()
    log.info("storage_win", "窗口创建")
    create_ui()
    sys.publish("STORAGE_GET_INFO")
    sys.publish("MEMORY_INFO_GET")
    if timer_id then sys.timerStop(timer_id) end
    timer_id = sys.timerLoopStart(function()
        sys.publish("MEMORY_INFO_GET")
    end, 1000)
    log.info("storage_win", "数据请求已发送，定时器启动")
end

local function on_destroy()
    if timer_id then sys.timerStop(timer_id); timer_id = nil end
    if main_container then main_container:destroy(); main_container = nil end
    total_label = nil; used_label = nil; free_label = nil; progress_bar = nil; percent_label = nil
    sys_total_label = nil; sys_used_label = nil; sys_max_label = nil; sys_percent_label = nil; sys_progress_bar = nil
    vm_total_label = nil; vm_used_label = nil; vm_max_label = nil; vm_percent_label = nil; vm_progress_bar = nil
    psram_total_label = nil; psram_used_label = nil; psram_max_label = nil; psram_percent_label = nil; psram_progress_bar = nil
    log.info("storage_win", "窗口销毁")
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
    log.info("storage_win", "窗口已打开, win_id=", win_id)
end

sys.subscribe("STORAGE_INFO", update_storage_info)
sys.subscribe("MEMORY_INFO", update_memory_info)
sys.subscribe("OPEN_STORAGE_WIN", open_handler)