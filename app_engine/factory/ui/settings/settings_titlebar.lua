--[[
@module  settings_titlebar
@summary 设置页面标题栏共享组件（支持低分辨率横屏紧凑模式）
@version 1.1
@date    2026.08.14
@usage
local titlebar = require "settings_titlebar"
local _, th = titlebar.create(main_container, "设置", screen_w, function() exwin.close(window_id) end)
]]
local M = {}

local COLOR_PRIMARY = 0x007AFF
local COLOR_WHITE   = 0xFFFFFF

function M.create(parent, title, screen_w, on_back)
    local density = _G.density_scale or 1.0
    local gh = _G.screen_h or 800
    -- 低分辨率横屏（如 480x272）压缩标题栏，留更多空间给内容
    local compact = (gh > 0 and gh < 320)
    local bar_height = math.floor((compact and 48 or 60) * density)
    local in_pad = math.floor((compact and 4 or 10) * density)
    local in_h = bar_height - 2 * in_pad

    local title_bar = airui.container({
        parent = parent,
        x = 0, y = 0,
        w = screen_w, h = bar_height,
        color = COLOR_PRIMARY
    })

    local back_btn = airui.container({
        parent = title_bar,
        x = in_pad, y = in_pad,
        w = math.floor((compact and 42 or 50) * density), h = in_h,
        color = COLOR_PRIMARY,
        on_click = on_back
    })
    airui.label({
        parent = back_btn,
        x = 0, y = 0,
        w = math.floor((compact and 42 or 50) * density), h = in_h,
        text = "<",
        font_size = math.floor((compact and 26 or 28) * density),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题宽度自适应：根据字符数计算，取屏幕剩余宽度的较大值防止换行
    local title_char_count = 0
    for _ in string.gmatch(title, "[%z\1-\127\194-\244][\128-\191]*") do
        title_char_count = title_char_count + 1
    end
    local back_area = math.floor((compact and 60 or 70) * density)
    local title_max_w = screen_w - back_area - math.floor(10 * density)
    local title_calc_w = math.floor(title_char_count * (compact and 30 or 40) * density)
    local title_width = math.min(title_max_w, math.max(math.floor(100 * density), title_calc_w))

    airui.label({
        parent = title_bar,
        x = back_area, y = in_pad,
        w = title_width, h = in_h,
        text = title,
        font_size = math.floor((compact and 26 or 32) * density),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    return title_bar, bar_height
end

return M
