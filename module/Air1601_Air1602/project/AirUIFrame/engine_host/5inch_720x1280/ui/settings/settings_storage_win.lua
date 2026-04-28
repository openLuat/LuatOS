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

-- 存储卡片高度（原200改为180）
local STORAGE_CARD_H = math.floor(180 * _G.density_scale)
-- 内存卡片高度（原220改为180）
local MEMORY_CARD_H = math.floor(180 * _G.density_scale)

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
        sys_total_label:set_text(format_memory_full(info.sys.total))
        sys_used_label:set_text(format_memory_full(info.sys.used))
        sys_max_label:set_text(format_memory_full(info.sys.max))
        sys_percent_label:set_text(string.format("%.1f%% 占用", pct))
        if sys_progress_bar then sys_progress_bar:set_value(math.floor(pct), false) end
    end
    if info.vm and vm_total_label then
        local pct = calc_percent(info.vm.used, info.vm.total)
        vm_total_label:set_text(format_memory_full(info.vm.total))
        vm_used_label:set_text(format_memory_full(info.vm.used))
        vm_max_label:set_text(format_memory_full(info.vm.max))
        vm_percent_label:set_text(string.format("%.1f%% 占用", pct))
        if vm_progress_bar then vm_progress_bar:set_value(math.floor(pct), false) end
    end
    if info.psram and psram_total_label then
        local pct = calc_percent(info.psram.used, info.psram.total)
        psram_total_label:set_text(format_memory_full(info.psram.total))
        psram_used_label:set_text(format_memory_full(info.psram.used))
        psram_max_label:set_text(format_memory_full(info.psram.max))
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
        color = 0xFFFFFF
    })
    airui.label({
        parent = row,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = label_text,
        font_size = math.floor(16 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })
    local value_label = airui.label({
        parent = row,
        x = math.floor(110 * _G.density_scale), y = math.floor(5 * _G.density_scale),
        w = (card_w - math.floor(40 * _G.density_scale)) - math.floor(110 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "--",
        font_size = math.floor(16 * _G.density_scale),
        color = 0x333333,
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
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = title,
        font_size = math.floor(22 * _G.density_scale),
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    local percent_label = airui.label({
        parent = card,
        x = card_w - math.floor(180 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = math.floor(160 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "0% 占用",
        font_size = math.floor(16 * _G.density_scale),
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_RIGHT
    })
    -- 根据卡片高度调整内部行位置
    local row_y1 = math.floor(55 * _G.density_scale)
    local row_y2 = math.floor(90 * _G.density_scale)
    local row_y3 = math.floor(125 * _G.density_scale)
    local bar_y = card_height - math.floor(25 * _G.density_scale)
    if card_height == MEMORY_CARD_H then
        row_y1 = math.floor(50 * _G.density_scale)
        row_y2 = math.floor(80 * _G.density_scale)
        row_y3 = math.floor(110 * _G.density_scale)
        bar_y = math.floor(150 * _G.density_scale)
    end
    local total_label = create_info_row(card, row_y1, "总内存")
    local used_label = create_info_row(card, row_y2, "当前使用")
    local max_label = create_info_row(card, row_y3, "历史峰值")
    local progress_bar = airui.bar({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = bar_y,
        w = card_w - math.floor(40 * _G.density_scale),
        h = math.floor(20 * _G.density_scale),
        value = 0,
        bg_color = 0xE0E0E0,
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
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(60 * _G.density_scale),
        color = 0x3F51B5
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = 0x3F51B5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = math.floor(60 * _G.density_scale), y = math.floor(14 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "存储",
        font_size = math.floor(32 * _G.density_scale),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 内容容器（不使用滚动，直接放置所有卡片）
    local title_h = math.floor(60 * _G.density_scale)
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h,
        color = 0xF5F5F5
    })

    local current_y = margin

    -- 存储卡片（高度180）
    local card_storage = airui.container({
        parent = content,
        x = margin, y = current_y,
        w = card_w, h = STORAGE_CARD_H,
        color = 0xFFFFFF,
        radius = 8
    })
    current_y = current_y + STORAGE_CARD_H + margin

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = math.floor(20 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "总容量",
        font_size = math.floor(20 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })
    total_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = math.floor(20 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "--",
        font_size = math.floor(22 * _G.density_scale),
        color = 0x333333,
        align = airui.TEXT_ALIGN_RIGHT
    })

    progress_bar = airui.bar({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = math.floor(60 * _G.density_scale),
        w = card_w - math.floor(40 * _G.density_scale),
        h = math.floor(20 * _G.density_scale),
        min = 0, max = 100,
        value = 0,
        bg_color = 0xE8E8E8,
        indicator_color = 0x3366FF,
        radius = 8
    })

    percent_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = math.floor(80 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        text = "已使用 --%",
        font_size = math.floor(18 * _G.density_scale),
        color = 0x3366FF,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = math.floor(105 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        text = "已使用",
        font_size = math.floor(18 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })
    used_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = math.floor(105 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = 0x333333,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = card_storage,
        x = math.floor(20 * _G.density_scale), y = math.floor(145 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        text = "可用空间",
        font_size = math.floor(18 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })
    free_label = airui.label({
        parent = card_storage,
        x = card_w - math.floor(220 * _G.density_scale), y = math.floor(145 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = 0x333333,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 内存卡片（使用高度 MEMORY_CARD_H = 180）
    local sys = create_memory_card(content, current_y, "系统内存", 0x4CAF50, MEMORY_CARD_H)
    sys_total_label, sys_used_label, sys_max_label, sys_percent_label, sys_progress_bar = sys.total, sys.used, sys.max, sys.percent, sys.progress
    current_y = current_y + MEMORY_CARD_H + margin

    local vm = create_memory_card(content, current_y, "Lua 虚拟机内存", 0xFF9800, MEMORY_CARD_H)
    vm_total_label, vm_used_label, vm_max_label, vm_percent_label, vm_progress_bar = vm.total, vm.used, vm.max, vm.percent, vm.progress
    current_y = current_y + MEMORY_CARD_H + margin

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
