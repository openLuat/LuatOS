--[[
@module  settings_storage_win
@summary 存储页面
@version 1.2
@date    2026.04.16
@author  江访
]]

local window_id = nil
local main_container
local total_label, used_label, free_label, progress_bar, percent_label
local sys_total, sys_used, sys_max, sys_percent, sys_bar
local vm_total, vm_used, vm_max, vm_percent, vm_bar
local psram_total, psram_used, psram_max, psram_percent, psram_bar
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

local storage_card_h
local memory_card_h

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
end

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
end

local function format_bytes(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    if bytes < 1024 then return string.format("%d B", bytes)
    elseif bytes < 1024*1024 then return string.format("%.2f KB", bytes/1024)
    elseif bytes < 1024*1024*1024 then return string.format("%.2f MB", bytes/1024/1024)
    else return string.format("%.2f GB", bytes/1024/1024/1024) end
end

local function format_bytes_full(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    local converted = format_bytes(bytes)
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

local function update_memory_info(info)
    if info.sys and sys_total then
        local percent = calc_percent(info.sys.used, info.sys.total)
        sys_total:set_text(format_bytes(info.sys.total))
        sys_used:set_text(format_bytes(info.sys.used))
        sys_max:set_text(format_bytes(info.sys.max))
        sys_percent:set_text(string.format("%.1f%% 占用", percent))
        if sys_bar then sys_bar:set_value(math.floor(percent), false) end
    end
    if info.vm_result and vm_total then
        local percent = calc_percent(info.vm_result.used, info.vm_result.total)
        vm_total:set_text(format_bytes(info.vm_result.total))
        vm_used:set_text(format_bytes(info.vm_result.used))
        vm_max:set_text(format_bytes(info.vm_result.max))
        vm_percent:set_text(string.format("%.1f%% 占用", percent))
        if vm_bar then vm_bar:set_value(math.floor(percent), false) end
    end
    if info.psram and psram_total then
        local percent = calc_percent(info.psram.used, info.psram.total)
        psram_total:set_text(format_bytes(info.psram.total))
        psram_used:set_text(format_bytes(info.psram.used))
        psram_max:set_text(format_bytes(info.psram.max))
        psram_percent:set_text(string.format("%.1f%% 占用", percent))
        if psram_bar then psram_bar:set_value(math.floor(percent), false) end
    end
end

local function create_info_row(p, y, lt)
    local r = airui.container({
        parent = p,
        x = math.floor(20 * _G.density_scale), y = y,
        w = card_w - math.floor(40 * _G.density_scale),
        h = math.floor(35 * _G.density_scale),
        color = COLOR_CARD
    })
    airui.label({
        parent = r,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = lt,
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    local vl = airui.label({
        parent = r,
        x = math.floor(110 * _G.density_scale), y = math.floor(5 * _G.density_scale),
        w = (card_w - math.floor(40 * _G.density_scale)) - math.floor(110 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "--",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })
    return vl
end

local function create_memory_card(p, y, title, percent_color, card_height)
    local card = airui.container({
        parent = p,
        x = margin, y = y,
        w = card_w, h = card_height,
        color = COLOR_WHITE,
        radius = 8
    })
    local mem_pad = math.floor(12 * _G.density_scale)
    local mem_title_h = math.floor(30 * _G.density_scale)
    local mem_item_h = math.floor(35 * _G.density_scale)
    local mem_bar_h = math.floor(18 * _G.density_scale)
    local mg = math.floor(4 * _G.density_scale)

    local y_title = mem_pad
    local y_item1 = y_title + mem_title_h + mg
    local y_item2 = y_item1 + mem_item_h + mg
    local y_item3 = y_item2 + mem_item_h + mg
    local y_bar = y_item3 + mem_item_h + mg

    airui.label({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = y_title,
        w = math.floor(200 * _G.density_scale), h = mem_title_h,
        text = title,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    local local_pct = airui.label({
        parent = card,
        x = card_w - math.floor(180 * _G.density_scale), y = y_title,
        w = math.floor(160 * _G.density_scale), h = mem_title_h,
        text = "0% 占用",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local local_total = create_info_row(card, y_item1, "总内存")
    local local_used = create_info_row(card, y_item2, "当前使用")
    local local_max = create_info_row(card, y_item3, "历史峰值")
    local local_bar = airui.bar({
        parent = card,
        x = math.floor(20 * _G.density_scale), y = y_bar,
        w = card_w - math.floor(40 * _G.density_scale),
        h = mem_bar_h,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = percent_color,
        radius = 8
    })
    return {
        total = local_total,
        used = local_used,
        max = local_max,
        percent = local_pct,
        progress = local_bar
    }
end

local function build_ui()
    update_screen_size()

    local card_h2 = math.floor(screen_h * 0.20)
    if card_h2 < 140 then card_h2 = 140 end
    if card_h2 > 260 then card_h2 = 260 end

    local storage_pad = math.floor(10 * _G.density_scale)
    local storage_row_h = math.floor(28 * _G.density_scale)
    local storage_bar_h = math.floor(18 * _G.density_scale)
    local storage_small_h = math.floor(22 * _G.density_scale)
    local storage_gap = math.floor(6 * _G.density_scale)
    local y_free = storage_pad + storage_row_h + storage_gap + storage_bar_h + math.floor(2 * _G.density_scale) + storage_small_h + storage_gap + storage_small_h + storage_gap
    local storage_total_h = y_free + storage_small_h + storage_pad
    storage_card_h = math.max(card_h2, storage_total_h)

    local mem_pad = math.floor(12 * _G.density_scale)
    local mem_title_h = math.floor(30 * _G.density_scale)
    local mem_item_h = math.floor(35 * _G.density_scale)
    local mem_bar_h = math.floor(18 * _G.density_scale)
    local mg = math.floor(4 * _G.density_scale)
    local y_bar2 = mem_pad + mem_title_h + mg + mem_item_h + mg + mem_item_h + mg + mem_item_h + mg
    local mem_total_h = y_bar2 + mem_bar_h + mem_pad + math.floor(8 * _G.density_scale)
    memory_card_h = math.max(card_h2, mem_total_h)

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

    local back_btn = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(window_id) end
    })
    airui.label({
        parent = back_btn,
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

    local title_h2 = math.floor(60 * _G.density_scale)
    local content_area = airui.container({
        parent = main_container,
        x = 0, y = title_h2,
        w = screen_w, h = screen_h - title_h2,
        color = COLOR_BG,
        scrollable = true
    })

    local card_gap = math.floor(margin * 0.7)
    local current_y = margin

    local y_title = storage_pad
    local yb3 = y_title + storage_row_h + storage_gap
    local yp = yb3 + storage_bar_h + math.floor(2 * _G.density_scale)
    local yu = yp + storage_small_h + storage_gap
    local yf2 = yu + storage_small_h + storage_gap

    local storage_card = airui.container({
        parent = content_area,
        x = margin, y = current_y,
        w = card_w, h = storage_card_h,
        color = COLOR_WHITE,
        radius = 8
    })
    current_y = current_y + storage_card_h + card_gap

    airui.label({
        parent = storage_card,
        x = math.floor(20 * _G.density_scale), y = y_title,
        w = math.floor(100 * _G.density_scale), h = storage_row_h,
        text = "总容量",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    total_label = airui.label({
        parent = storage_card,
        x = card_w - math.floor(220 * _G.density_scale), y = y_title,
        w = math.floor(200 * _G.density_scale), h = storage_row_h,
        text = "--",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    progress_bar = airui.bar({
        parent = storage_card,
        x = math.floor(20 * _G.density_scale), y = yb3,
        w = card_w - math.floor(40 * _G.density_scale),
        h = storage_bar_h,
        min = 0, max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 8
    })

    percent_label = airui.label({
        parent = storage_card,
        x = card_w - math.floor(220 * _G.density_scale), y = yp,
        w = math.floor(200 * _G.density_scale), h = storage_small_h,
        text = "已使用 --%",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = storage_card,
        x = math.floor(20 * _G.density_scale), y = yu,
        w = math.floor(100 * _G.density_scale), h = storage_small_h,
        text = "已使用",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    used_label = airui.label({
        parent = storage_card,
        x = card_w - math.floor(220 * _G.density_scale), y = yu,
        w = math.floor(200 * _G.density_scale), h = storage_small_h,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = storage_card,
        x = math.floor(20 * _G.density_scale), y = yf2,
        w = math.floor(100 * _G.density_scale), h = storage_small_h,
        text = "可用空间",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    free_label = airui.label({
        parent = storage_card,
        x = card_w - math.floor(220 * _G.density_scale), y = yf2,
        w = math.floor(200 * _G.density_scale), h = storage_small_h,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local sys_result = create_memory_card(content_area, current_y, "系统内存", 0x4CAF50, memory_card_h)
    sys_total, sys_used, sys_max, sys_percent, sys_bar = sys_result.total, sys_result.used, sys_result.max, sys_result.percent, sys_result.progress
    current_y = current_y + memory_card_h + card_gap

    local vm_result = create_memory_card(content_area, current_y, "Lua 虚拟机内存", COLOR_ACCENT, memory_card_h)
    vm_total, vm_used, vm_max, vm_percent, vm_bar = vm_result.total, vm_result.used, vm_result.max, vm_result.percent, vm_result.progress
    current_y = current_y + memory_card_h + card_gap

    local psram_result = create_memory_card(content_area, current_y, "PSRAM 内存", 0x9C27B0, memory_card_h)
    psram_total, psram_used, psram_max, psram_percent, psram_bar = psram_result.total, psram_result.used, psram_result.max, psram_result.percent, psram_result.progress

end

local function on_create()
    build_ui()
    sys.publish("STORAGE_GET_INFO")
    sys.publish("MEMORY_INFO_GET")
    sys.subscribe("STORAGE_INFO", update_storage_info)
    sys.subscribe("MEMORY_INFO", update_memory_info)
    if timer_id then sys.timerStop(timer_id) end
    timer_id = sys.timerLoopStart(function()
        sys.publish("MEMORY_INFO_GET")
    end, 1000)
end

local function on_destroy()
    sys.unsubscribe("STORAGE_INFO", update_storage_info)
    sys.unsubscribe("MEMORY_INFO", update_memory_info)
    if timer_id then sys.timerStop(timer_id); timer_id = nil end
    if main_container then main_container:destroy(); main_container = nil end
    total_label = nil; used_label = nil; free_label = nil; progress_bar = nil; percent_label = nil
    sys_total = nil; sys_used = nil; sys_max = nil; sys_percent = nil; sys_bar = nil
    vm_total = nil; vm_used = nil; vm_max = nil; vm_percent = nil; vm_bar = nil
    psram_total = nil; psram_used = nil; psram_max = nil; psram_percent = nil; psram_bar = nil
end

local function on_get_focus()
    if timer_id then sys.timerStop(timer_id) end
    timer_id = sys.timerLoopStart(function()
        sys.publish("MEMORY_INFO_GET")
    end, 1000)
end

local function on_lose_focus()
    if timer_id then sys.timerStop(timer_id); timer_id = nil end
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_STORAGE_WIN", open_handler)
