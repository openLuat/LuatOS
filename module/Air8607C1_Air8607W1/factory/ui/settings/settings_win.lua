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
      OPEN_AUTOSTART_WIN / OPEN_ABOUT_WIN / OPEN_USB_MODE_WIN
]]

require "settings_display_win"
require "settings_time_win"
require "settings_storage_win"
require "storage_pri_win"
require "settings_about_win"
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

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

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
    ["OPEN_ABOUT_WIN"]       = "about",
    ["OPEN_AIRCLOUD_WIN"]    = "cloud",
    ["OPEN_USB_MODE_WIN"]    = "mouse",
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
    -- UVC 摄像头与 USB 键鼠共用 USB Host，两者都配了才需要二选一（见 usb_mode）
    if require("usb_mode").available(cfg) then
        add("外设模式", "OPEN_USB_MODE_WIN", "UVC 摄像头与 USB 键鼠二选一")
    end
    -- 系统更新：固件设置页是无条件显示的入口（不跟 features.fota 走），这里照搬
    add("系统更新", "OPEN_FOTA_WIN", "检查并下载最新固件")
    if fe.buzzer and ui.show_buzzer_settings then add("触摸音效", "OPEN_SOUND_WIN", "触摸反馈音开关与音量") end
    if fe.aircloud and ui.show_aircloud then add("数据上报", "OPEN_AIRCLOUD_WIN", "AirCloud 云端上报开关与周期") end
    if ui.show_autostart then add("后装APP自启", "OPEN_AUTOSTART_WIN", "开机自动启动指定应用") end
    -- 固件设置页没有「关于设置」入口，这里同步去掉（页面本身仍保留，可由别处发布 OPEN_ABOUT_WIN 打开）
    return entries
end

--[[设备信息卡的字段，与固件「关于」页保持同一套、同一顺序]]
local INFO_ROWS = {
    { key = "设备名称",   field = "device_name" },
    { key = "设备型号",   field = "model" },
    { key = "设备ID",     field = "unique_id" },
    { key = "固件版本",   field = "version" },
    { key = "内核版本",   field = "kernel" },
    { key = "主控芯片",   field = "chip" },
    { key = "屏幕分辨率", field = "screen" },
}

-- 字段 -> 值标签的更新函数（卡片每次重建都会重新登记）
local info_setters = {}

--[[设备信息回填：值由 settings_about_app 上报（型号 / ID / 版本 / 内核 / 芯片 / 分辨率），
设备名称另走 config 的持久化读取。]]
local function apply_info(info)
    if type(info) ~= "table" then return end
    for _, it in ipairs(INFO_ROWS) do
        local v = info[it.field]
        local set = info_setters[it.field]
        if set and v ~= nil and v ~= "" then set(tostring(v)) end
    end
end

local function apply_device_name(name)
    local set = info_setters.device_name
    if not set then return end
    if name == nil or name == "" then
        -- 未保存过名称时按芯片型号兜底，与固件默认名一致
        local suffix = tostring((_G.project_config and _G.project_config.chip) or ""):gsub("^Air", "")
        if suffix == "PC" then suffix = "" end   -- 模拟器不拼芯片名
        name = "合宙引擎主机" .. suffix
    end
    set(tostring(name))
end

--[[右侧设备信息卡]]
local function build_info_card(parent, x, y, w, h)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })

    theme.section(card, { x = pad, y = pad, w = w - 2 * pad,
        text = "设备信息", px_size = theme.fs("label"), color = theme.C.t2 })

    local cfg = _G.project_config or {}
    -- 本地就能确定的先填上，其余等业务层上报（避免先闪一行 "--"）
    local seed = {
        model   = cfg.name or "--",
        version = VERSION or "--",
        chip    = cfg.chip or "--",
        screen  = string.format("%d × %d", scr_w, scr_h),
    }
    local rows = {}
    for _, it in ipairs(INFO_ROWS) do
        rows[#rows + 1] = { it.key, it.field, seed[it.field] or "--" }
    end
    info_setters = {}

    -- 行高把卡片剩余高度均分，键值同一行；键列宽度按最长键固定，值统一左对齐起点（前面对齐）
    local row_h = math.max(theme.dp(34), math.floor((h - pad * 2 - theme.dp(24)) / math.max(1, #rows)))
    local fs = theme.fs("body")
    local lh = fs + 4
    local inset = theme.dp(12)            -- 行内容到卡片内边的距离
    local inner = w - 2 * pad
    local key_w = 0
    for _, r in ipairs(rows) do
        local w0 = theme.text_width(r[1], fs)
        if w0 > key_w then key_w = w0 end
    end
    key_w = key_w + theme.dp(16)          -- 最长键 + 间距，所有值都从这一列开始
    local val_w = inner - inset * 2 - key_w
    for i, r in ipairs(rows) do
        local y0 = pad + theme.dp(24) + (i - 1) * row_h
        -- 一行放不下就折行，折到行高装得下为止
        local lines = math.max(1, math.ceil(theme.text_width(r[3], fs) / math.max(1, val_w)))
        if lh * lines > row_h then lines = math.max(1, math.floor(row_h / lh)) end
        theme.label(card, {
            x = pad + inset, y = y0 + math.floor((row_h - lh) / 2), w = key_w, h = lh,
            text = r[1], px_size = fs, color = theme.C.t1,
        })
        local val = theme.label(card, {
            x = pad + inset + key_w, y = y0 + math.floor((row_h - lh * lines) / 2),
            w = val_w, h = lh * lines,
            text = theme.fit_text(r[3], val_w, fs, lines), px_size = fs,
            color = theme.C.t1,
        })
        local field, vw = r[2], val_w
        info_setters[field] = function(text)
            if val and not val:is_destroyed() then
                val:set_text(theme.fit_text(text, vw, fs, lines))
            end
        end
        if i < #rows then
            theme.divider(card, { x = pad + inset, y = y0 + row_h, w = inner - inset * 2 })
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

local function on_create()
    build_ui()
    -- 设备信息卡的值由业务层上报（与「关于设备」页同一条消息链路）
    sys.subscribe("ABOUT_DEVICE_INFO", apply_info)
    sys.subscribe("CONFIG_DEVICE_NAME_VALUE", apply_device_name)
    sys.publish("ABOUT_DEVICE_GET_INFO")
    sys.publish("CONFIG_GET_DEVICE_NAME")
end

local function on_destroy()
    sys.unsubscribe("ABOUT_DEVICE_INFO", apply_info)
    sys.unsubscribe("CONFIG_DEVICE_NAME_VALUE", apply_device_name)
    info_setters = {}
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
