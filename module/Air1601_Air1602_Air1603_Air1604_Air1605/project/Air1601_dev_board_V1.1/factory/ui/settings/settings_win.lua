--[[
@module  settings_win
@summary 设置主页面（TabOS 深色玻璃态）——左侧导航 + 右侧设备信息
@version 2.1
@date    2026.09.23
@author  江访
@usage
订阅: OPEN_SETTINGS_WIN → 打开设置主页
发布: OPEN_IOT_WIN / OPEN_WIFI_WIN / OPEN_DISPLAY_WIN / OPEN_STORAGE_WIN /
      OPEN_STORAGE_PRI_WIN / OPEN_FOTA_WIN / OPEN_SOUND_WIN /
      OPEN_AUTOSTART_WIN / OPEN_RS485_WIN / OPEN_UVC_WIN / OPEN_GNSS_WIN /
      OPEN_BLE_WIN / OPEN_CAN_WIN / OPEN_ABOUT_WIN
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
require "settings_report_win"
require "settings_rs485_win"
require "settings_uvc_win"
require "settings_gnss_win"
require "settings_ble_win"
require "settings_can_win"
require "settings_channel_win"

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
    ["OPEN_WIFI_WIN"]        = "wifi",
    ["OPEN_DISPLAY_WIN"]     = "brightness",
    ["OPEN_THEME_WIN"]       = "theme",
    ["OPEN_STORAGE_WIN"]     = "storage",
    ["OPEN_STORAGE_PRI_WIN"] = "sort",
    ["OPEN_FOTA_WIN"]        = "update",
    ["OPEN_SOUND_WIN"]       = "sound",
    ["OPEN_AUTOSTART_WIN"]   = "autostart",
    ["OPEN_ABOUT_WIN"]       = "about",
    ["OPEN_AIRCLOUD_WIN"]    = "cloud",
    -- RS485 是有线串口总线，复用以太网（有线口）图标，不新增二进制资源
    ["OPEN_RS485_WIN"]       = "ethernet",
    -- 摄像头没有专用图标，复用 AI 助手图标（相机/识别语义最接近），不新增二进制资源
    ["OPEN_UVC_WIN"]         = "ai_chat",
    -- 定位没有专用图标，复用天气晴（户外/天空语义最接近），不新增二进制资源
    ["OPEN_GNSS_WIN"]        = "weather_sunny",
    -- 蓝牙没有专用图标，复用 WiFi（无线语义最接近），不新增二进制资源
    ["OPEN_BLE_WIN"]         = "wifi",
    -- CAN 与 RS485 同属有线现场总线，复用同一张以太网图标，不新增二进制资源
    ["OPEN_CAN_WIN"]         = "ethernet",
    -- UART3 口复用是「一路串口多模组选路」，同样复用有线口图标
    ["OPEN_CHANNEL_WIN"]     = "ethernet",
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

    add("IOT账号", "OPEN_IOT_WIN", "合宙 IoT 平台登录与设备绑定")
    -- UART3 口复用：4G / WiFi / GNSS / 蓝牙 只能有一路占用这条串口。
    -- 只要板上存在其中任一通道（network 段非空，或对应 features 打开）就显示入口。
    -- 注意 features.wifi / net_4g 已被 settings_channel_app 按通道收口，
    -- 通道选 gnss/ble 时两者都是 false，此时靠 network 段（以太网）兜住入口。
    if (type(cfg.network) == "table" and #cfg.network > 0)
        or fe.wifi or fe.net_4g or fe.gnss or fe.ble then
        add("UART3口复用", "OPEN_CHANNEL_WIN", "4G / WiFi / GNSS / 蓝牙 四选一")
    end
    if fe.wifi then add("WiFi设置", "OPEN_WIFI_WIN", "扫描、连接与已保存网络管理") end
    -- 背光为 GPIO 直控、不支持亮度调节，入口只保留媒体音量（hw.audio 存在时才有）
    if cfg.hw and cfg.hw.audio then add("音量调节", "OPEN_DISPLAY_WIN", "媒体音量调节") end
    add("主题风格", "OPEN_THEME_WIN", "外观配色与强调色")
    if ui.show_storage_settings then add("存储和内存", "OPEN_STORAGE_WIN", "文件系统容量与内存占用") end
    if fe.sd_card or fe.nand_flash then add("存储顺序", "OPEN_STORAGE_PRI_WIN", "外部应用安装位置优先级") end
    add("系统更新", "OPEN_FOTA_WIN", "检查并下载最新固件")
    if fe.buzzer and ui.show_buzzer_settings then add("触摸音效", "OPEN_SOUND_WIN", "触摸反馈音开关与音量") end
    -- 功能开关与 UI 入口分离：features.aircloud 控制是否上报，ui.show_aircloud 控制是否显示设置入口
    if fe.aircloud and ui.show_aircloud then add("数据上报", "OPEN_AIRCLOUD_WIN", "AirCloud 云端上报开关与周期") end
    add("后装APP自启", "OPEN_AUTOSTART_WIN", "开机自动启动指定应用")
    if fe.rs485 then add("RS485测试", "OPEN_RS485_WIN", "UART2 半双工收发自检") end
    if fe.uvc then add("USB摄像头", "OPEN_UVC_WIN", "UVC 摄像头画面预览") end
    if fe.gnss then add("GNSS定位", "OPEN_GNSS_WIN", "UART3 搜星与经纬度") end
    if fe.ble then add("蓝牙测试", "OPEN_BLE_WIN", "UART3 蓝牙连接与收发自检") end
    add("CAN测试", "OPEN_CAN_WIN", "UART2 CAN 总线收发自检")
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
        { "屏幕分辨率", string.format("%d × %d", scr_w, scr_h) },
    }

    local row_h = math.max(theme.dp(30), math.floor((h - pad * 2 - theme.dp(24)) / math.max(1, #rows)))
    local fs = theme.fs("caption")
    local lh = fs + 3
    local tx = theme.dp(10)
    local inner = w - 2 * pad
    for i, r in ipairs(rows) do
        local y0 = pad + theme.dp(24) + (i - 1) * row_h
        local key_w = theme.text_width(r[1], fs) + theme.dp(8)
        local val_w = inner - tx - theme.dp(12) - key_w
        -- 值列吃掉左标题之外的整行宽度，一行放不下就折行，折到行高装得下为止
        local lines = math.max(1, math.ceil(theme.text_width(r[2], fs) / math.max(1, val_w)))
        if lh * lines > row_h then lines = math.max(1, math.floor(row_h / lh)) end
        theme.label(card, {
            x = pad + tx, y = y0 + math.floor((row_h - lh) / 2), w = key_w, h = lh,
            text = r[1], px_size = fs, color = theme.C.t1,
        })
        theme.label(card, {
            x = pad + inner - val_w, y = y0 + math.floor((row_h - lh * lines) / 2),
            w = val_w, h = lh * lines,
            text = theme.fit_text(r[2], val_w, fs, lines), px_size = fs,
            color = theme.C.t1, align = airui.TEXT_ALIGN_RIGHT,
        })
        if i < #rows then
            theme.divider(card, { x = pad, y = y0 + row_h, w = inner })
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

        -- 行高按入口数量自适应：先按可用高度均分，再夹到 [36, 56]。
        -- 下限放到 36dp 是为了兜住「入口变多」的情况（RS485 / UVC / GNSS 逐个加进来），
        -- 之前下限 42dp 时 13 项会算出 546dp、超出版面，最后一项（关于设置）被裁掉半截。
        local row_h = math.max(theme.dp(36), math.floor((body_h - pad * 2) / math.max(1, #entries)))
        row_h = math.min(row_h, theme.dp(56))
        -- 兜底：万一夹完仍超出可用高度（入口继续增加），按可用高度硬压，宁可挤也不丢项
        local avail_h = body_h - pad * 2
        if row_h * #entries > avail_h then
            row_h = math.max(theme.dp(30), math.floor(avail_h / #entries))
        end
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
