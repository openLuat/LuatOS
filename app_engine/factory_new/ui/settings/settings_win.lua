--[[
@module  settings_win
@summary 设置主页面（TabOS 深色玻璃态）——左侧导航 + 右侧设备信息
@version 2.1
@date    2026.09.23
@author  江访
@usage
订阅: OPEN_SETTINGS_WIN → 打开设置主页
发布: OPEN_IOT_WIN / OPEN_NET_WIN / OPEN_DISPLAY_WIN / OPEN_TIME_WIN /
      OPEN_STORAGE_WIN / OPEN_STORAGE_PRI_WIN / OPEN_FOTA_WIN / OPEN_SOUND_WIN /
      OPEN_AUTOSTART_WIN / OPEN_USB_MODE_WIN
]]

require "settings_display_win"
require "settings_time_win"
require "settings_storage_win"
require "storage_pri_win"
local device_info = require "settings_about_win"
require "settings_sound_win"
require "wifi_list_win"
require "net_settings_win"
require "net_detail_win"
require "settings_iot_win"
require "settings_fota_win"
require "settings_auto_win"
require "settings_theme_win"
require "settings_report_win"
require "settings_usb_win"
require "settings_mux_win"      -- Air8606 接口复用页（订阅 OPEN_AIR8606_MUX_WIN；非 8606 机型无入口）

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
-- scr_w/scr_h 是「整屏」尺寸，sw/sh 会被 content_fit 收窄成内容区宽度（全屏 − 左栏），
-- 展示「屏幕分辨率」必须用前者，否则宽屏下会少写一条左栏宽度。
local scr_w, scr_h = 480, 800
local pad = 12
local bar_h = 56

-- 设置项定义（icon 为语义图标名，缺失时仅显示文字）
local ENTRY_ICONS = {
    ["OPEN_IOT_WIN"]         = "cloud",
    ["OPEN_NET_WIN"]         = "wifi",
    ["OPEN_DISPLAY_WIN"]     = "brightness",
    ["OPEN_TIME_WIN"]        = "about",
    ["OPEN_THEME_WIN"]       = "theme",
    ["OPEN_STORAGE_WIN"]     = "storage",
    ["OPEN_STORAGE_PRI_WIN"] = "sort",
    ["OPEN_FOTA_WIN"]        = "update",
    ["OPEN_SOUND_WIN"]       = "sound",
    ["OPEN_AUTOSTART_WIN"]   = "autostart",
    ["OPEN_AIRCLOUD_WIN"]    = "cloud",
    ["OPEN_USB_MODE_WIN"]    = "mouse",
    ["OPEN_AIR8606_MUX_WIN"] = "mouse",
}

local function update_screen_size()
    scr_w, scr_h = screen_w or 480, screen_h or 800
    sw, sh = scr_w, scr_h
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）；收窄后 wide 判定与内部几何自动自适应
    sw, sh = theme.content_fit(sw, sh)
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

    -- 界面暴露统一由 ui.show_* 决定（不写即不显示）：IOT账号 / 系统更新 / 后装APP自启 是
    -- 联网相关入口，无联网能力的型号按能力就不写这几个键（见 config/template.lua）
    if ui.show_iot then add("IOT账号", "OPEN_IOT_WIN", "合宙 IoT 平台登录与设备绑定") end
    local nets = cfg.network
    local has_eth = fe.ethernet
    if type(nets) == "table" then
        for _, nc in ipairs(nets) do
            if nc and type(nc.type) == "string" and nc.type:find("eth", 1, true) then has_eth = true break end
        end
    end
    if (fe.wifi and ui.show_wifi_icon) or (fe.net_4g and ui.show_4g_icon)
        or (has_eth and ui.show_ethernet_settings) then
        add("网络设置", "OPEN_NET_WIN", "网络开关、连接状态与 WiFi 管理")
    end
    add("亮度和声音", "OPEN_DISPLAY_WIN", "屏幕背光与媒体音量调节")
    add("设置当前时间", "OPEN_TIME_WIN", "手动校准系统时钟")
    add("主题风格", "OPEN_THEME_WIN", "外观配色与强调色")
    if ui.show_storage_settings then add("存储和内存", "OPEN_STORAGE_WIN", "文件系统容量与内存占用") end
    if fe.sd_card or fe.nand_flash then add("存储顺序", "OPEN_STORAGE_PRI_WIN", "外部应用安装位置优先级") end
    -- UVC 摄像头与 USB 键鼠共用 USB Host，两者都配了才需要二选一（见 usb_mode）。
    -- Air8606 机型（cfg.radio 存在）由「接口复用」页统一管 USB Host 等六组装配，
    -- 不再单出「外设模式」行（与参考库一致）
    if cfg.radio then
        add("接口复用", "OPEN_AIR8606_MUX_WIN", "SPI2、UART 和 USB Host 用途选择")
    elseif require("usb_mode").available(cfg) then
        add("外设模式", "OPEN_USB_MODE_WIN", "UVC 摄像头与 USB 键鼠二选一")
    end
    if ui.show_fota then add("系统更新", "OPEN_FOTA_WIN", "检查并下载最新固件") end
    if fe.buzzer and ui.show_buzzer_settings then add("触摸音效", "OPEN_SOUND_WIN", "触摸反馈音开关与音量") end
    if fe.aircloud and ui.show_aircloud then add("数据上报", "OPEN_AIRCLOUD_WIN", "AirCloud 云端上报开关与周期") end
    if ui.show_autostart then add("后装APP自启", "OPEN_AUTOSTART_WIN", "开机自动启动指定应用") end
    return entries
end

-- 横屏左右分栏；窄屏信息卡与设置入口上下排列。
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
        local nav = theme.card(main_container, { x = pad, y = y, w = nav_w, h = body_h, scrollable = true })

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

        device_info.mount(main_container, pad + nav_w + pad, y, sw - nav_w - 3 * pad, body_h)
    else
        -- 窄屏：信息位于入口上方，内容滚动以保留所有设置入口。
        local body = theme.box(main_container, {
            x = ctx.x, y = y, w = ctx.w, h = body_h,
            color = theme.C.black, opa = 0, scrollable = true,
        })
        local info_h = device_info.mount(main_container, 0, 0, ctx.w, body_h, body)
        local entries_y = info_h + pad
        local cols = (sw >= 420) and 2 or 1
        local gap = pad
        local cw = math.floor((sw - 2 * pad - (cols - 1) * gap) / cols)
        local ch = theme.dp(62)
        for i, e in ipairs(entries) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = col * (cw + gap)
            local cy = entries_y + row * (ch + gap)
            local event = e.event
            -- 窄屏下这些行直接落在页面底色上，必须自带卡面（否则只剩孤立文字）
            theme.row(body, {
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
    device_info.unmount()
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
        device_info.unmount()
        if main_container then main_container:destroy(); main_container = nil end
        build_ui()
    end
end
local function on_lose_focus() device_info.close_editor() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)
