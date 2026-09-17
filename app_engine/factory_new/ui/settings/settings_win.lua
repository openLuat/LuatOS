--[[
@module  settings_win
@summary 设置主页面（TabOS 深色玻璃态）——左侧导航 + 右侧设备信息
@version 2.0
@date    2026.09.15
@author  江访
@usage
订阅: OPEN_SETTINGS_WIN → 打开设置主页
发布: OPEN_IOT_WIN / OPEN_WIFI_WIN / OPEN_DISPLAY_WIN / OPEN_STORAGE_WIN /
      OPEN_STORAGE_PRI_WIN / OPEN_FOTA_WIN / OPEN_SOUND_WIN /
      OPEN_AUTOSTART_WIN / OPEN_ABOUT_WIN
]]

require "settings_display_win"
require "settings_storage_win"
require "storage_pri_win"
require "settings_about_win"
require "settings_sound_win"
require "wifi_list_win"
require "settings_iot_win"
require "settings_fota_win"
require "settings_auto_win"
require "settings_theme_win"

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 12
local bar_h = 56

-- 设置项定义（icon 为语义图标名，缺失时仅显示文字）
local ENTRY_ICONS = {
    ["OPEN_IOT_WIN"]         = "cloud",
    ["OPEN_WIFI_WIN"]        = "wifi",
    ["OPEN_DISPLAY_WIN"]     = "brightness",
    ["OPEN_THEME_WIN"]       = "theme",
    ["OPEN_STORAGE_WIN"]     = "storage",
    ["OPEN_STORAGE_PRI_WIN"] = "sort",
    ["OPEN_FOTA_WIN"]        = "update",
    ["OPEN_SOUND_WIN"]       = "sound",
    ["OPEN_AUTOSTART_WIN"]   = "autostart",
    ["OPEN_ABOUT_WIN"]       = "about",
}

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    pad = theme.page_margin()
    bar_h = theme.dp(56)
end

--[[收集当前硬件支持的设置入口]]
local function collect_entries()
    local cfg = _G.project_config or {}
    local fe = cfg.features or {}
    local ui = cfg.ui or {}
    local entries = {}

    local function add(label, event, desc)
        entries[#entries + 1] = { label = label, event = event, desc = desc, icon = ENTRY_ICONS[event] }
    end

    add("IOT账号", "OPEN_IOT_WIN", "合宙 IoT 平台登录与设备绑定")
    if fe.wifi then add("WiFi设置", "OPEN_WIFI_WIN", "扫描、连接与已保存网络管理") end
    add("显示亮度", "OPEN_DISPLAY_WIN", "屏幕背光强度调节")
    add("主题风格", "OPEN_THEME_WIN", "外观配色与强调色")
    if ui.show_storage_settings then add("存储和内存", "OPEN_STORAGE_WIN", "文件系统容量与内存占用") end
    if fe.sd_card or fe.nand_flash then add("存储顺序", "OPEN_STORAGE_PRI_WIN", "外部应用安装位置优先级") end
    add("系统更新", "OPEN_FOTA_WIN", "检查并下载最新固件")
    if fe.buzzer and ui.show_buzzer_settings then add("触摸音效", "OPEN_SOUND_WIN", "触摸反馈音开关与音量") end
    add("后装APP自启", "OPEN_AUTOSTART_WIN", "开机自动启动指定应用")
    add("关于设置", "OPEN_ABOUT_WIN", "设备型号、唯一ID与版本信息")
    return entries
end

--[[右侧设备信息卡]]
local function build_info_card(parent, x, y, w, h)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })

    theme.section(card, { x = pad, y = pad, w = w - 2 * pad,
        text = "设备信息", px_size = theme.fs("micro"), color = theme.C.t3 })

    local cfg = _G.project_config or {}
    local rows = {
        { "设备型号", cfg.name or "--" },
        { "主控芯片", cfg.chip or "--" },
        { "固件版本", VERSION or "--" },
        { "底板型号", cfg.baseboard or "--" },
        { "屏幕分辨率", string.format("%d × %d", sw, sh) },
    }

    local row_h = math.max(theme.dp(30), math.floor((h - pad * 2 - theme.dp(24)) / math.max(1, #rows)))
    for i, r in ipairs(rows) do
        theme.row(card, {
            x = pad, y = pad + theme.dp(24) + (i - 1) * row_h, w = w - 2 * pad, h = row_h,
            text = r[1], sub = nil, right = r[2], right_w = math.floor(w * 0.52),
            px_size = theme.fs("caption"), right_px = theme.fs("caption"),
            right_color = theme.C.t1,
        })
        if i < #rows then
            theme.divider(card, { x = pad, y = pad + theme.dp(24) + i * row_h, w = w - 2 * pad })
        end
    end
    return card
end

local function build_ui()
    update_screen_size()
    -- 统一骨架：背景 + 页边距 + 标题栏一次算清，不再各页自己拼
    local ctx = theme.page({
        title = "设置",
        sub = "设备偏好、网络、显示与系统",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    pad = ctx.pad

    local y = ctx.y
    local body_h = ctx.h
    local entries = collect_entries()
    local wide = sw >= 560

    if wide then
        local nav_w = math.max(theme.dp(180), math.min(theme.dp(240), math.floor(sw * 0.26)))
        local nav = theme.card(main_container, { x = pad, y = y, w = nav_w, h = body_h })

        local row_h = math.max(theme.dp(42), math.floor((body_h - pad * 2) / math.max(1, #entries)))
        row_h = math.min(row_h, theme.dp(56))
        for i, e in ipairs(entries) do
            local event = e.event
            theme.row(nav, {
                x = pad - theme.dp(2), y = pad + (i - 1) * row_h, w = nav_w - 2 * pad + theme.dp(4),
                h = row_h - theme.dp(2),
                icon = e.icon, icon_size = theme.dp(28), tint = theme.C.amber,
                text = e.label, px_size = theme.fs("body"),
                on_click = function() sys.publish(event) end,
            })
        end

        build_info_card(main_container, pad + nav_w + pad, y, sw - nav_w - 3 * pad, body_h)
    else
        -- 窄屏：两列入口卡片
        local cols = (sw >= 420) and 2 or 1
        local gap = pad
        local cw = math.floor((sw - 2 * pad - (cols - 1) * gap) / cols)
        local ch = theme.dp(62)
        for i, e in ipairs(entries) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = pad + col * (cw + gap)
            local cy = y + row * (ch + gap)
            if cy + ch > screen_h - pad then break end
            local event = e.event
            -- 窄屏下这些行直接落在页面底色上，必须自带卡面（否则只剩孤立文字）
            theme.row(main_container, {
                x = x, y = cy, w = cw, h = ch,
                icon = e.icon, icon_size = theme.dp(28),
                px_size = theme.fs("body"), sub_px = theme.fs("micro"),
                bg = theme.C.surface, opa = theme.OPA.glass, border = theme.C.stroke,
                text = e.label, sub = e.desc,
                on_click = function() sys.publish(event) end,
            })
        end
    end
end

local function on_create() build_ui() end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
end

--[[主题切换后标记脏，等本页重新获得焦点时再重建
（换肤发生在主题页，此时本页在下层；直接重建会打乱窗口栈顺序）]]
local theme_dirty = false
local function on_theme_changed() theme_dirty = true end
sys.subscribe("UI_THEME_CHANGED", on_theme_changed)

local function on_get_focus()
    if theme_dirty then
        theme_dirty = false
        if main_container then main_container:destroy(); main_container = nil end
        build_ui()
    end
end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)
