--[[
@module  monitor_win
@summary 状态监控页面（内存/Flash/运行时间/告警）
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示系统内存、Flash使用率、运行时间和最近告警列表。
]]

local win_id = nil
local main_container, content
local mem_label, flash_label, runtime_label, alarm_count_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function format_bytes(bytes)
    if bytes >= 1024 then
        return string.format("%.1fKB", bytes / 1024)
    end
    return bytes .. "B"
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "系统监控", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 内存使用
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 10, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 15, y = 6, w = 100, h = 18, text = "Lua内存", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    mem_label = airui.label({ parent = c1, x = 15, y = 26, w = 400, h = 18, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- Flash使用
    local c2 = airui.container({ parent = content, x = T.MARGIN, y = 66, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c2, x = 15, y = 6, w = 100, h = 18, text = "Flash存储", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    flash_label = airui.label({ parent = c2, x = 15, y = 26, w = 400, h = 18, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 运行时间
    local c3 = airui.container({ parent = content, x = T.MARGIN, y = 122, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c3, x = 15, y = 6, w = 100, h = 18, text = "运行时间", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    runtime_label = airui.label({ parent = c3, x = 15, y = 26, w = 400, h = 18, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 告警
    local c4 = airui.container({ parent = content, x = T.MARGIN, y = 178, w = T.CARD_W, h = 40, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c4, x = 15, y = 10, w = 100, h = 20, text = "告警数量", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    alarm_count_label = airui.label({ parent = c4, x = 120, y = 10, w = 200, h = 20, text = "0", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
end

local function on_create()
    create_ui()
    sys.publish("monitor_query")
    sys.publish("ALARM_QUERY")
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    mem_label = nil; flash_label = nil; runtime_label = nil; alarm_count_label = nil; win_id = nil
end

local function on_get_focus()
    sys.publish("monitor_query")
    sys.publish("ALARM_QUERY")
end
local function on_lose_focus() end

-- 订阅内存更新
sys.subscribe("monitor_memory_update", function(data)
    if not mem_label then return end
    local used_kb = math.floor(data.used / 1024)
    local total_kb = math.floor(data.total / 1024)
    mem_label:set_text(string.format("%dKB / %dKB (%d%%)", used_kb, total_kb, data.usage_percent))
end)

-- 订阅Flash更新
sys.subscribe("monitor_flash_update", function(data)
    if not flash_label then return end
    flash_label:set_text(string.format("%s / %s (%d%%)", format_bytes(data.used), format_bytes(data.total), data.usage_percent))
end)

-- 订阅运行时间更新
sys.subscribe("monitor_runtime_update", function(data)
    if not runtime_label then return end
    runtime_label:set_text(data.runtime_full_str or data.runtime_str or "--")
end)

-- 订阅告警更新
sys.subscribe("ALARM_UPDATE", function(data)
    if not alarm_count_label then return end
    alarm_count_label:set_text(tostring(data.count or 0))
end)

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_MONITOR_WIN", open_handler)
