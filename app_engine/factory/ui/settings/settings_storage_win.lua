--[[
@module  settings_storage_win
@summary 存储页面（内存 + 多文件系统空间）
@version 1.3
@date    2026.05.15
]]

local window_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 20
local card_w = 440
local timer_id = nil

-- 内存卡控件
local sys_total, sys_used, sys_max, sys_percent, sys_bar
local vm_total, vm_used, vm_max, vm_percent, vm_bar
local psram_total, psram_used, psram_max, psram_percent, psram_bar

-- 文件系统卡控件（动态创建）
local fs_cards = {}
local fs_card_h = 0

local titlebar = require "settings_titlebar"

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_ACCENT         = 0xFF9800
local COLOR_DANGER         = 0xE63946

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

local function format_bytes(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    if bytes < 0 then bytes = -bytes end
    if bytes < 1024 then return string.format("%d B", bytes)
    elseif bytes < 1024*1024 then return string.format("%.2f KB", bytes/1024)
    elseif bytes < 1024*1024*1024 then return string.format("%.2f MB", bytes/1024/1024)
    else return string.format("%.2f GB", bytes/1024/1024/1024) end
end

local function format_kb(total_kb)
    if not total_kb or total_kb == 0 then return "0 KB" end
    if total_kb < 0 then total_kb = -total_kb end
    if total_kb < 1024 then return string.format("%d KB", total_kb)
    elseif total_kb < 1024*1024 then return string.format("%.2f MB", total_kb/1024)
    else return string.format("%.2f GB", total_kb/1024/1024) end
end

local function calc_percent(used, total)
    if not used or not total or total == 0 then return 0 end
    return math.min(100, math.max(0, (used / total) * 100))
end

-- ==================== 内存卡更新 ====================

local function update_memory_info(info)
    if info.sys and sys_total then
        local pct = calc_percent(info.sys.used, info.sys.total)
        sys_total:set_text(format_bytes(info.sys.total))
        sys_used:set_text(format_bytes(info.sys.used))
        sys_max:set_text(format_bytes(info.sys.max))
        sys_percent:set_text(string.format("%.1f%% 占用", pct))
        if sys_bar then sys_bar:set_value(math.floor(pct), false) end
    end
    if info.vm and vm_total then
        local pct = calc_percent(info.vm.used, info.vm.total)
        vm_total:set_text(format_bytes(info.vm.total))
        vm_used:set_text(format_bytes(info.vm.used))
        vm_max:set_text(format_bytes(info.vm.max))
        vm_percent:set_text(string.format("%.1f%% 占用", pct))
        if vm_bar then vm_bar:set_value(math.floor(pct), false) end
    end
    if info.psram and psram_total then
        local pct = calc_percent(info.psram.used, info.psram.total)
        psram_total:set_text(format_bytes(info.psram.total))
        psram_used:set_text(format_bytes(info.psram.used))
        psram_max:set_text(format_bytes(info.psram.max))
        psram_percent:set_text(string.format("%.1f%% 占用", pct))
        if psram_bar then psram_bar:set_value(math.floor(pct), false) end
    end
end

-- ==================== 文件系统卡 ====================

local function create_info_row(p, y, lt, row_height)
    local rh = row_height or math.floor(26 * (_G.density_scale or 1.0))
    local r = airui.container({
        parent = p, x = math.floor(16 * (_G.density_scale or 1.0)), y = y,
        w = card_w - math.floor(32 * (_G.density_scale or 1.0)),
        h = rh, color = COLOR_CARD
    })
    local text_pad = math.floor(math.max(2, rh * 0.12))
    local text_h = rh - text_pad * 2
    local text_sz = math.max(10, math.min(18, math.floor(rh * 0.6)))
    airui.label({
        parent = r, x = 0, y = text_pad,
        w = math.floor(90 * (_G.density_scale or 1.0)), h = text_h,
        text = lt, font_size = text_sz,
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT
    })
    local vl = airui.label({
        parent = r,
        x = math.floor(100 * (_G.density_scale or 1.0)), y = text_pad,
        w = card_w - math.floor(132 * (_G.density_scale or 1.0)), h = text_h,
        text = "--", font_size = text_sz,
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_RIGHT
    })
    return vl
end

local function create_memory_card(p, y, title, percent_color, card_height)
    local card = airui.container({ parent = p, x = margin, y = y, w = card_w, h = card_height, color = COLOR_WHITE, radius = 8 })
    local density = _G.density_scale or 1.0
    local pad = math.floor(card_height * 0.06)
    local th = math.floor(card_height * 0.20)
    local ih = math.floor(card_height * 0.15)
    local bh = math.floor(card_height * 0.08)
    local g = math.floor(card_height * 0.025)

    local yt = pad
    local yi1 = yt + th + g
    local yi2 = yi1 + ih + g
    local yi3 = yi2 + ih + g
    local yb = yi3 + ih + g

    local title_font = math.max(12, math.min(26, math.floor(th * 0.7)))
    local percent_font = math.max(10, math.min(20, math.floor(th * 0.55)))
    airui.label({ parent = card, x = math.floor(16 * density), y = yt, w = math.floor(200 * density), h = th,
        text = title, font_size = title_font, color = COLOR_TEXT })
    local lp = airui.label({ parent = card, x = card_w - math.floor(180 * density), y = yt, w = math.floor(160 * density), h = th,
        text = "0% 占用", font_size = percent_font, color = percent_color, align = airui.TEXT_ALIGN_RIGHT })

    local lt = create_info_row(card, yi1, "总内存", ih)
    local lu = create_info_row(card, yi2, "当前使用", ih)
    local lm = create_info_row(card, yi3, "历史峰值", ih)
    local lb = airui.bar({ parent = card, x = math.floor(16 * density), y = yb,
        w = card_w - math.floor(32 * density), h = bh, value = 0,
        bg_color = COLOR_DIVIDER, indicator_color = percent_color, radius = 7 })

    return { total = lt, used = lu, max = lm, percent = lp, progress = lb }
end

local function create_fs_card(p, y, title, card_height, is_internal)
    local card = airui.container({ parent = p, x = margin, y = y, w = card_w, h = card_height, color = COLOR_WHITE, radius = 8 })
    local density = _G.density_scale or 1.0
    local pad = math.floor(card_height * 0.05)
    local th = math.floor(card_height * 0.20)
    local rh = math.floor(card_height * 0.18)
    local bh = math.floor(card_height * 0.08)
    local g = math.floor(card_height * 0.020)
    local row_h = math.floor(card_height * 0.18)

    local yt = pad
    local yb = yt + th + g
    local yp = yb + bh + g
    local yu = yp + rh + g
    local yf = yu + row_h + g

    local title_font = math.max(12, math.min(26, math.floor(th * 0.7)))
    local status_font = math.max(10, math.min(20, math.floor(th * 0.55)))
    local pct_font = math.max(10, math.min(18, math.floor(rh * 0.6)))
    airui.label({ parent = card, x = math.floor(16 * density), y = yt, w = math.floor(200 * density), h = th,
        text = title, font_size = title_font, color = COLOR_TEXT })

    -- 内置先显示占位，外部显示"未挂载"
    local status_label = airui.label({ parent = card, x = card_w - math.floor(180 * density), y = yt,
        w = math.floor(160 * density), h = th,
        text = is_internal and "--" or "未挂载",
        font_size = status_font, color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_RIGHT })

    local bar = airui.bar({ parent = card, x = math.floor(16 * density), y = yb,
        w = card_w - math.floor(32 * density), h = bh, value = 0,
        bg_color = COLOR_DIVIDER, indicator_color = COLOR_PRIMARY, radius = 7 })

    local pct_label = airui.label({ parent = card, x = math.floor(16 * density), y = yp,
        w = card_w - math.floor(32 * density), h = rh,
        text = "已使用 --%", font_size = pct_font, color = COLOR_TEXT })

    local total_label = create_info_row(card, yu, "总容量", row_h)
    local free_label = create_info_row(card, yf, "可用空间", row_h)

    return {
        status = status_label, bar = bar, pct_label = pct_label,
        total = total_label, free = free_label,
        is_internal = is_internal,
    }
end

local function update_fs_card(card_widgets, info)
    if not info or not info.available then
        if card_widgets.is_internal then
            card_widgets.status:set_text("--")
        else
            card_widgets.status:set_text("未挂载")
        end
        card_widgets.bar:set_value(0, false)
        card_widgets.pct_label:set_text("--")
        card_widgets.total:set_text("--")
        card_widgets.free:set_text("--")
        return
    end
    local total = info.total_kb or 0
    local free = info.free_kb or 0
    local used = info.used_kb or (total - free)
    local pct = calc_percent(used, total)

    if card_widgets.is_internal then
        -- 内置文件系统：不显示"已挂载"，只显示总容量
        card_widgets.status:set_text(format_kb(total))
    else
        card_widgets.status:set_text(string.format("已挂载 (%s)", format_kb(total)))
    end
    card_widgets.bar:set_value(math.floor(pct), false)
    card_widgets.pct_label:set_text(string.format("已使用 %d%%  |  已用 %s", math.floor(pct), format_kb(used)))
    card_widgets.total:set_text(format_kb(total))
    card_widgets.free:set_text(format_bytes(free * 1024))
end

-- ==================== 构建 UI ====================

local function build_ui()
    update_screen_size()

    -- 6张卡片(3内存+3文件系统) + 间距 + 留白 = 可用高度
    local th_est = math.floor(60 * (_G.density_scale or 1.0))
    local margin_top = margin
    local gap_count = 5
    local card_gap_est = math.floor(margin * 0.7)
    local available_h = screen_h - th_est - margin_top * 2 - gap_count * card_gap_est
    local card_height_base = math.floor(available_h / 6)
    if card_height_base < 105 then card_height_base = 105 end
    if card_height_base > 200 then card_height_base = 200 end

    memory_card_h = card_height_base
    fs_card_h = math.floor(card_height_base * 0.85)

    main_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h, color = COLOR_BG
    })

    local _, th = titlebar.create(main_container, "存储和内存", screen_w, function() exwin.close(window_id) end)

    local content_area = airui.container({
        parent = main_container, x = 0, y = th, w = screen_w, h = screen_h - th,
        color = COLOR_BG, scrollable = true
    })

    local card_gap = math.floor(margin * 0.7)
    local current_y = margin

    -- 三个文件系统卡：内置 / SD / little_flash
    local fs_configs = {
        { title = "内置文件系统", internal = true },
        { title = "TF卡/SD卡",    internal = false },
        { title = "外挂Flash",    internal = false },
    }
    fs_cards = {}
    for _, cfg in ipairs(fs_configs) do
        local w = create_fs_card(content_area, current_y, cfg.title, fs_card_h, cfg.internal)
        table.insert(fs_cards, w)
        current_y = current_y + fs_card_h + card_gap
    end

    -- 三个内存卡
    local sys_result = create_memory_card(content_area, current_y, "系统内存", 0x4CAF50, memory_card_h)
    sys_total, sys_used, sys_max, sys_percent, sys_bar = sys_result.total, sys_result.used, sys_result.max, sys_result.percent, sys_result.progress
    current_y = current_y + memory_card_h + card_gap

    local vm_result = create_memory_card(content_area, current_y, "Lua 虚拟机内存", COLOR_ACCENT, memory_card_h)
    vm_total, vm_used, vm_max, vm_percent, vm_bar = vm_result.total, vm_result.used, vm_result.max, vm_result.percent, vm_result.progress
    current_y = current_y + memory_card_h + card_gap

    local psram_result = create_memory_card(content_area, current_y, "PSRAM 内存", 0x9C27B0, memory_card_h)
    psram_total, psram_used, psram_max, psram_percent, psram_bar = psram_result.total, psram_result.used, psram_result.max, psram_result.percent, psram_result.progress
end

-- ==================== 多存储信息更新 ====================

local function update_fs_info_list(list)
    -- list: { { mount_point="/", label="内置文件系统", available=true, total_kb, free_kb, used_kb }, ... }
    if type(list) ~= "table" then return end
    for _, entry in ipairs(list) do
        if entry.mount_point == "/" and fs_cards[1] then
            update_fs_card(fs_cards[1], entry)
        elseif entry.mount_point == "/sd/" and fs_cards[2] then
            update_fs_card(fs_cards[2], entry)
        elseif entry.mount_point == "/little_flash/" and fs_cards[3] then
            update_fs_card(fs_cards[3], entry)
        end
    end
end

-- ==================== 生命周期 ====================

local function on_create()
    build_ui()
    sys.subscribe("STORAGE_INFO_LIST", update_fs_info_list)
    sys.subscribe("MEMORY_INFO", update_memory_info)
    -- 异步查询，让 UI 先渲染完成再填充数据，避免 io.fsstat 阻塞首帧
    sys.taskInit(function()
        sys.publish("STORAGE_GET_INFO_LIST")
        sys.publish("MEMORY_INFO_GET")
    end)
end

local function on_destroy()
    sys.unsubscribe("STORAGE_INFO_LIST", update_fs_info_list)
    sys.unsubscribe("MEMORY_INFO", update_memory_info)
    if main_container then main_container:destroy(); main_container = nil end
    fs_cards = {}
    sys_total = nil; sys_used = nil; sys_max = nil; sys_percent = nil; sys_bar = nil
    vm_total = nil; vm_used = nil; vm_max = nil; vm_percent = nil; vm_bar = nil
    psram_total = nil; psram_used = nil; psram_max = nil; psram_percent = nil; psram_bar = nil
end

local function on_get_focus()
    sys.taskInit(function()
        sys.publish("MEMORY_INFO_GET")
        sys.publish("STORAGE_GET_INFO_LIST")
    end)
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
