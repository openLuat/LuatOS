--[[
@module  idle_win
@summary 桌面首页（TabOS 深色玻璃态）——状态栏 + 时钟卡 + 应用网格 + 底部 Dock
@version 2.2
@date    2026.09.16
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_IDLE_WIN                             → 创建桌面窗口
订阅: STATUS_TIME_UPDATED(time,date,weekday)    → 刷新时钟
订阅: STATUS_SIGNAL_UPDATED(level)              → 刷新 4G 信号图标
订阅: STATUS_WIFI_SIGNAL_UPDATED(level)         → 刷新 WiFi 信号图标
订阅: APP_STORE_INSTALLED_UPDATED               → 应用列表变更，重建网格并刷新表头计数
订阅: BATTERY_STATUS({present,level,charging})  → 刷新电量条
订阅: AUTOSTART_SETTINGS_VALUE / AUTOSTART_CONFIG_CHANGED / AUTOSTART_PASSWORD_RESULT
订阅: FOTA_PROMPT_REBOOT / FOTA_PROMPT_DOWNLOAD
订阅: WEATHER_UPDATED({city,condition,temp,daily}) → 刷新天气卡（未接 API 前用占位数据）
发布: REQUEST_STATUS_REFRESH / OPEN_xxx_WIN / APP_STORE_UNINSTALL / AUTOSTART_* / FOTA_*

=== 视觉说明 ===
采用 tablet-smart-home 设计语言：
  宽屏（≥560dp）左侧 104dp 玻璃导航栏，窄屏省略
  顶部状态栏 + 问候行 + 大时钟玻璃卡（右侧资料中心二维码）
  天气玻璃卡：左侧「天气图标 + 温度 + （地点|状况）单串」，右侧 3 天预报等宽三列
  中部应用网格玻璃卡（含分页器）+ 底部玻璃 Dock

=== 排版注意（改天气卡前必读）===
theme.label 内部有一行 `if fs < 16 then fs = 16 end`，而 density_scale 在
10.1" 1024x600 上算得 0.64 → 被 max(1.0, ...) 抬回 1.0，因此 theme.F.tiny/small/body
这三个令牌在本工程实机上全部退化为 16px（仅 h2=17 略大）。
=> 想要可靠的字号层级必须走 px_size；且行高 h 必须 >= 字号，否则字被裁切。
]]

local exnetif = require "exnetif"
local theme = require "ui_theme"

local window_id = nil
local main_container = nil
local apps_card = nil
-- 应用卡片表头计数标签（"已安装应用 | N"）。
-- 原来只在 build_apps_card 里把它造出来就丢掉了返回值，谁也拿不到，
-- 于是安装/卸载后这个数字永远停在开机那一刻 —— 必须持有引用才能刷新。
local apps_head_label = nil
-- 翻页按钮引用：空列表时要能整组隐藏（见 update_pager 的注释）
local pager_prev_btn, pager_next_btn = nil, nil

-- 关键控件
local status_time_label, big_time_label, date_label, greet_label
local wifi_icon, mobile_icon, ethernet_icon
local battery_bar, battery_label, battery_container
local grid_container, page_idx_label

-- ==================== 布局参数（calc_layout 计算） ====================
local use_rail = false
local rail_w = 0
local pad = 12
local status_h = 28
local header_h = 0
local clock_h = 90
local dock_h = 60
local content_x = 0
local content_w = 0
local apps_y, apps_h = 0, 0
local weather_y, weather_h = 0, 0
local apps_pad_y = 12
local apps_head_h = 26
local grid_cols = 4
local grid_gap = 10
local tile_w, tile_h = 96, 84
local tile_icon = 46
local apps_per_page = 12
local grid_rows = 2
local apps_page_count = 1
local apps_page_index = 1

local density_scale_val = _G.density_scale or 1.0

local status_cache = { time = "08:00", date = "1970-01-01", weekday = "星期四", mobile_level = -1, wifi_level = 0 }

-- 天气缓存（占位数据，接入天气 API 后发 WEATHER_UPDATED 消息即可整卡刷新）
--   city/condition/temp        → 当前天气
--   daily[1..3]                → 未来三天预报，{ day = 标题, high = 最高温, low = 最低温 }
-- 天气图标放在 res/ 下（打包进 /luadb/），文件名见 WEATHER_STYLES 的 icon 字段：
--   weather_sunny.png / weather_cloudy.png / weather_overcast.png
--   weather_rain.png / weather_snow.png
-- 文件不在时不会留白：降级为自绘图标（晴天画光晕 + 四向光芒 + 日面）。
local weather_cache = {
    city = "上海",
    condition = "晴",
    temp = "26℃",   -- 用 ℃(U+2103) 而非 "°C"：固件内置字库不含 °(U+00B0)，℃ 确认可用
    daily = {
        { day = "明天",   high = 28, low = 21 },
        { day = "后天",   high = 25, low = 19 },
        { day = "大后天", high = 27, low = 20 },
    },
}

-- 自启应用状态（与 settings_auto_app 共享 fskv 数据源）
local auto_start_enabled = false
local auto_start_target = ""
local auto_start_has_password = false

local app_cards = {}
local all_apps = {}

local has_4g = _G.project_config and _G.project_config.features and _G.project_config.features.net_4g
local has_wifi = _G.project_config and _G.project_config.features and _G.project_config.features.wifi
local has_battery = _G.project_config and _G.project_config.features and _G.project_config.features.battery
    and _G.project_config.ui and _G.project_config.ui.show_battery_icon

local has_eth = false
if _G.project_config then
    local cf = _G.project_config.network or {}
    for _, nc in ipairs(cf) do
        if nc.type and nc.type:find("eth", 1, true) then has_eth = true break end
    end
    if not has_eth then
        has_eth = _G.project_config.features and _G.project_config.features.ethernet
    end
end

local has_app_factory = _G.project_config and _G.project_config.features and _G.project_config.features.app_factory
    and _G.project_config.ui and _G.project_config.ui.show_app_factory
local has_ai_chat = _G.project_config and _G.project_config.features and _G.project_config.features.ai_chat
    and _G.project_config.ui and _G.project_config.ui.show_ai_chat

local chip_name = (_G.project_config and _G.project_config.chip) or ""
local model_suffix = chip_name:gsub("^Air", "")
local product_name = "合宙引擎主机" .. (model_suffix ~= "" and model_suffix or "")

-- 内置应用（同时出现在网格与底部 Dock）
local builtin_apps = {
    { name = "设置",     win = "SETTINGS",     icon = "settings",  dock = true },
    { name = "应用市场", win = "APP_STORE",    icon = "app_store", dock = true },
    { name = "文件管理", win = "FILE_MANAGER", icon = "file",      dock = true },
    { name = "网络测速", win = "SPEEDTEST",    icon = "speedtest", dock = true },
}
if has_app_factory then
    table.insert(builtin_apps, { name = "应用工厂", win = "APP_FACTORY", icon = "app_factory", dock = true })
end
if has_ai_chat then
    table.insert(builtin_apps, { name = "AI助手", win = "AI_CHAT", icon = "ai_chat", dock = true })
end

-- 侧栏导航项（宽屏使用）—— 改为内置应用快捷入口
local rail_items = {}  -- 在 build_rail 中由 builtin_apps 动态填充

-- 前向声明（网格点击依赖上下文菜单，后者定义在后面）
local show_app_context_menu

-- ==================== 布局计算 ====================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function calc_layout()
    local sw, sh = screen_w, screen_h
    local compact = (sh < 340 and sw > sh)

    use_rail = (sw >= 560) and not compact
    rail_w = use_rail and clamp(math.floor(104 * density_scale_val), 60, math.floor(sw * 0.18)) or 0

    pad = clamp(math.floor(math.min(sw, sh) * 0.021), 6, 18)
    status_h = compact and 22 or clamp(math.floor(sh * 0.05), 28, 36)
    header_h = 0  -- 问候语已移入状态栏，不再占用独立区域
    dock_h = compact and 46 or clamp(math.floor(sh * 0.105), 48, 72)
    clock_h = compact and clamp(math.floor(sh * 0.22), 50, 66)
        or clamp(math.floor(sh * 0.26), 110, 150)
    -- 天气卡高度下限 58：内部「温度两行」与「预报两行」按 16px 字号下限计算
    -- 至少需要 42px 内容高度，加上下内边距 8*2，低于 58 必然裁字
    weather_h = compact and 0 or clamp(math.floor(sh * 0.125), 58, 78)

    content_x = rail_w
    content_w = sw - rail_w

    local y = pad + status_h + pad
    y = y + clock_h + pad
    weather_y = y
    y = y + weather_h + pad
    apps_y = y
    if use_rail then
        -- 无 Dock，应用区域延伸到底部，与左侧 rail 下边距对齐
        apps_h = sh - y - pad
    else
        apps_h = sh - y - dock_h - pad
    end
    if apps_h < 84 then apps_h = 84 end

    -- 网格参数
    local inner_w = content_w - 2 * pad - 2 * apps_pad_y
    tile_icon = clamp(math.floor(sh * 0.075 * density_scale_val), 26, 48)
    tile_h = tile_icon + math.floor(30 * density_scale_val)
    apps_head_h = clamp(math.floor(sh * 0.045), 24, 30)
    grid_gap = clamp(math.floor(sw * 0.010), 6, 12)

    local min_tile_w = math.floor(math.max(72, tile_icon * 2.1))
    grid_cols = clamp(math.floor((inner_w + grid_gap) / (min_tile_w + grid_gap)), 3, 6)
    tile_w = math.floor((inner_w - (grid_cols - 1) * grid_gap) / grid_cols)

    local grid_avail = apps_h - apps_head_h - apps_pad_y * 2 - 4  -- 减4px安全余量防溢出
    grid_rows = math.floor((grid_avail + grid_gap) / (tile_h + grid_gap))
    if grid_rows < 1 then grid_rows = 1 end
    apps_per_page = math.max(1, grid_cols * grid_rows)
end

-- ==================== 工具函数 ====================

local function greeting_text(time_str)
    local hour = tonumber(string.sub(time_str or "08:00", 1, 2)) or 8
    if hour < 6 then return "凌晨好" end
    if hour < 12 then return "上午好" end
    if hour < 14 then return "中午好" end
    if hour < 18 then return "下午好" end
    return "晚上好"
end

local function dialog_style()
    return {
        bg_color = theme.C.dialog, header_bg_color = theme.C.dialog, content_bg_color = theme.C.dialog,
        title_text_color = theme.C.t1, radius = theme.r("lg"),
        title_align = airui.TEXT_ALIGN_CENTER,
        header_height = math.floor(46 * density_scale_val), content_pad = 0,
    }
end

-- ==================== 上下文 UI 管理 ====================

local context_keyboard = nil
local context_verify_win = nil
local context_password_win = nil
local context_menu_win = nil
local action_confirm_box = nil

local function destroy_context_ui()
    if context_keyboard then pcall(context_keyboard.destroy, context_keyboard); context_keyboard = nil end
    if context_verify_win then pcall(context_verify_win.destroy, context_verify_win); context_verify_win = nil end
    if context_password_win then pcall(context_password_win.destroy, context_password_win); context_password_win = nil end
    if context_menu_win then pcall(context_menu_win.destroy, context_menu_win); context_menu_win = nil end
    if action_confirm_box then pcall(action_confirm_box.destroy, action_confirm_box); action_confirm_box = nil end
end

local function show_info_box(title, text, buttons, on_action)
    local box = airui.msgbox({
        w = math.min(math.floor(screen_w * 0.82), 460),
        h = math.floor(screen_h * 0.26),
        style = { text_font_size = math.max(16, math.floor(16 * density_scale_val)) },
        title = title, text = text, buttons = buttons,
        on_action = on_action,
    })
    box:show()
    return box
end

-- ==================== 应用网格 ====================

local function tile_bind_click(app)
    if app.is_builtin then
        sys.publish("OPEN_" .. app.win .. "_WIN")
    else
        exapp.open(app.path)
    end
end

local function render_grid_page()
    if not apps_card then return end
    if grid_container then grid_container:destroy(); grid_container = nil end
    app_cards = {}

    local inner_w = content_w - 2 * pad - 2 * apps_pad_y
    grid_container = theme.box(apps_card, {
        x = apps_pad_y, y = apps_head_h + apps_pad_y,
        w = inner_w, h = grid_rows * (tile_h + grid_gap), color = theme.C.black, opa = 0,
    })

    local start_idx = (apps_page_index - 1) * apps_per_page + 1
    for i = 1, apps_per_page do
        local idx = start_idx + i - 1
        if idx > #all_apps then break end
        local app = all_apps[idx]
        local col = (i - 1) % grid_cols
        local row = math.floor((i - 1) / grid_cols)
        local x = col * (tile_w + grid_gap)
        local y = row * (tile_h + grid_gap)

        local long_handler = nil
        if not app.is_builtin then
            long_handler = function() show_app_context_menu(app) end
        end

        local tile = theme.tile(grid_container, {
            x = x, y = y, w = tile_w, h = tile_h,
            icon = app.icon, icon_size = tile_icon, text = app.name, opa = 0,
            on_click = function() tile_bind_click(app) end,
            on_long_press = long_handler,
        })
        if not app.is_builtin then
            app_cards[app.path] = { container = tile, name = app.name }
            if auto_start_enabled and auto_start_target == app.path then
                tile:set_color(theme.C.amber, 40)
            end
        end
    end
end

--[[刷新应用卡片头部：表头计数 + 分页器。
安装/卸载后 on_installed_updated -> load_external_apps 会走到这里，
表头 "已安装应用 | N" 必须跟着变（以前这里只更新了分页器数字，
计数永远停在开机那一刻，就是「应用总数安装后不会自动更新」）。

分页器的显隐用 set_hidden，而不是在 build_apps_card 里 "#all_apps == 0 就 return"：
设备首次开机时外部应用为 0，那时若直接退出，分页器控件根本不会被创建，
之后从应用商店装上第一个应用时卡片不会重建 —— 分页器就永远不出现，翻不到第二页。
airui.label 没有 set_hidden（只有 set_text/set_color/set_font_size/set_align），
所以页码标签用「置空文本」代替隐藏，按钮用容器的 set_hidden。]]
local function update_pager()
    apps_page_count = math.max(1, math.ceil(#all_apps / apps_per_page))
    if apps_page_index > apps_page_count then apps_page_index = apps_page_count end
    if apps_page_index < 1 then apps_page_index = 1 end

    -- 表头计数（安装/卸载后必须跟着变）
    if apps_head_label then
        apps_head_label:set_text("已安装应用 | " .. tostring(#all_apps))
    end

    -- 分页器：无外部应用时整组隐藏
    local has_apps = (#all_apps > 0)
    if pager_prev_btn then pager_prev_btn:set_hidden(not has_apps) end
    if pager_next_btn then pager_next_btn:set_hidden(not has_apps) end
    if page_idx_label then
        page_idx_label:set_text(has_apps
            and string.format("%d/%d", apps_page_index, apps_page_count) or "")
    end
end

local function on_page_prev()
    if apps_page_index > 1 then
        apps_page_index = apps_page_index - 1
        update_pager()
        render_grid_page()
    end
end

local function on_page_next()
    if apps_page_index < apps_page_count then
        apps_page_index = apps_page_index + 1
        update_pager()
        render_grid_page()
    end
end

-- ==================== 加载外部应用 ====================

local function load_external_apps()
    local installed = {}
    local installed_apps = exapp.list_installed()
    for app_dir, info in pairs(installed_apps or {}) do
        local is_builtin_flag = false
        for _, b in ipairs(builtin_apps) do
            if info.cn_name == b.name then is_builtin_flag = true break end
        end
        if not is_builtin_flag then
            installed[#installed + 1] = {
                name = info.cn_name or app_dir,
                icon = info.icon_path or "/luadb/img.png",
                is_builtin = false,
                path = info.path,
                install_time = info.install_time,
            }
        end
    end
    table.sort(installed, function(a, b)
        if a.install_time == b.install_time then return a.name < b.name end
        if a.install_time == nil then return false end
        if b.install_time == nil then return true end
        return a.install_time < b.install_time
    end)

    all_apps = {}
    -- 网格只显示外部应用（内置应用已在左侧 rail 和底部 Dock）
    for _, a in ipairs(installed) do
        all_apps[#all_apps + 1] = a
    end
    update_pager()
    render_grid_page()
end

-- ==================== 自启状态 ====================

local function request_auto_start_state()
    sys.publish("AUTOSTART_SETTINGS_GET")
end

local function on_auto_start_settings(data)
    if not data then return end
    auto_start_enabled = data.enabled
    auto_start_target = data.target or ""
    auto_start_has_password = data.has_password
    for app_path, card in pairs(app_cards) do
        if card.container then
            if auto_start_enabled and app_path == auto_start_target then
                card.container:set_color(theme.C.amber, 40)
            else
                card.container:set_color(theme.C.surface, 0)
            end
        end
    end
end

-- ==================== 卸载应用 ====================

local function handle_uninstall_app(app)
    local app_name = app.name or "未知"
    action_confirm_box = airui.msgbox({
        w = math.min(math.floor(screen_w * 0.80), 400),
        h = math.floor(screen_h * 0.25),
        style = { text_font_size = math.max(16, math.floor(16 * density_scale_val)) },
        title = "确认卸载", text = "确定要卸载 " .. app_name .. " 吗？",
        buttons = { "确定", "取消" },
        on_action = function(self, btn_label)
            self:destroy()
            action_confirm_box = nil
            if btn_label == "确定" then
                local app_dir = app.path:match("/([^/]+)/?$") or ""
                if app_dir ~= "" then
                    if auto_start_target == app.path then
                        sys.publish("AUTOSTART_SET_ENABLED", false, "")
                    end
                    sys.publish("APP_STORE_UNINSTALL", app_dir, "", "")
                end
            end
        end
    })
    action_confirm_box:show()
end

-- ==================== 密码验证 / 设置弹窗 ====================

local function make_dark_keyboard()
    return airui.keyboard({
        x = 0, y = -math.floor(20 * density_scale_val),
        w = screen_w, h = math.floor(220 * density_scale_val),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })
end

local function show_password_verify_popup(title_str, on_confirm, on_cancel)
    destroy_context_ui()
    local d = density_scale_val
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(46 * d)
    local pad_in = math.floor(16 * d)
    local input_h = math.floor(44 * d)
    local btn_h = math.floor(40 * d)
    local label_h = math.floor(22 * d)
    local gap = math.floor(12 * d)
    local win_h = header_h + pad_in * 2 + label_h + gap + input_h + gap + btn_h

    context_keyboard = make_dark_keyboard()

    local win = airui.win({
        parent = airui.screen, title = title_str,
        w = win_w, h = win_h, close_btn = false, auto_center = true,
        style = dialog_style(),
        on_close = function()
            destroy_context_ui()
            if on_cancel then on_cancel() end
        end,
    })
    context_verify_win = win

    theme.label(win, { x = pad_in, y = pad_in, w = win_w - 2 * pad_in, h = label_h,
        text = "请输入密码", size = theme.F.body, color = theme.C.t2, align = airui.TEXT_ALIGN_CENTER })

    local pwd_input = theme.input({
        parent = win, x = pad_in, y = pad_in + label_h + gap,
        w = win_w - 2 * pad_in, h = input_h,
        text = "", placeholder = "请输入密码", max_len = 16,
        font_size = math.max(16, math.floor(18 * d)), keyboard = context_keyboard,
    })

    local by = pad_in + label_h + gap + input_h + gap
    local btn_w = math.floor((win_w - 2 * pad_in - gap) / 2)
    theme.ghost_button(win, { x = pad_in, y = by, w = btn_w, h = btn_h, text = "取消",
        on_click = function() destroy_context_ui(); if on_cancel then on_cancel() end end })
    theme.button(win, { x = pad_in + btn_w + gap, y = by, w = btn_w, h = btn_h, text = "确定",
        on_click = function()
            local pwd = pwd_input:get_text() or ""
            destroy_context_ui()
            if on_confirm then on_confirm(pwd) end
        end })
end

local function show_password_set_popup(on_confirm, on_cancel)
    destroy_context_ui()
    local d = density_scale_val
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(46 * d)
    local pad_in = math.floor(16 * d)
    local input_h = math.floor(44 * d)
    local btn_h = math.floor(40 * d)
    local label_h = math.floor(22 * d)
    local gap = math.floor(10 * d)
    local win_h = header_h + pad_in * 2 + label_h + gap + input_h + gap + btn_h

    context_keyboard = make_dark_keyboard()

    local win = airui.win({
        parent = airui.screen, title = "设置自启密码",
        w = win_w, h = win_h, close_btn = false, auto_center = true,
        style = dialog_style(),
        on_close = function()
            destroy_context_ui()
            if on_cancel then on_cancel() end
        end,
    })
    context_password_win = win

    theme.label(win, { x = pad_in, y = pad_in, w = win_w - 2 * pad_in, h = label_h,
        text = "新密码（留空则清除密码）", size = theme.F.body, color = theme.C.t2 })

    local new_pwd_input = theme.input({
        parent = win, x = pad_in, y = pad_in + label_h + gap,
        w = win_w - 2 * pad_in, h = input_h,
        text = "", placeholder = "请输入新密码或留空", max_len = 16,
        font_size = math.max(16, math.floor(18 * d)), keyboard = context_keyboard,
    })

    local by = pad_in + label_h + gap + input_h + gap
    local btn_w = math.floor((win_w - 2 * pad_in - gap) / 2)
    theme.ghost_button(win, { x = pad_in, y = by, w = btn_w, h = btn_h, text = "取消",
        on_click = function() destroy_context_ui(); if on_cancel then on_cancel() end end })
    theme.button(win, { x = pad_in + btn_w + gap, y = by, w = btn_w, h = btn_h, text = "保存",
        on_click = function()
            local new_pwd = new_pwd_input:get_text() or ""
            destroy_context_ui()
            if on_confirm then on_confirm(new_pwd) end
        end })
end

-- ==================== 自启流程 ====================

local function handle_set_auto_start(app)
    if auto_start_has_password then
        show_password_verify_popup("验证密码以设置自启", function(pwd)
            sys.publish("AUTOSTART_SET_TARGET_AND_ENABLE", app.path, pwd)
        end)
    else
        action_confirm_box = airui.msgbox({
            w = math.min(math.floor(screen_w * 0.80), 420),
            h = math.floor(screen_h * 0.28),
            style = { text_font_size = math.max(16, math.floor(16 * density_scale_val)) },
            title = "设为自启应用",
            text = "确认将 " .. (app.name or "未知") .. " 设为开机自启吗？\n\n无密码保护的应用可被任意取消自启。",
            buttons = { "直接开启", "设置密码", "取消" },
            on_action = function(self, btn_label)
                self:destroy()
                action_confirm_box = nil
                if btn_label == "直接开启" then
                    sys.publish("AUTOSTART_SET_TARGET_AND_ENABLE", app.path, "")
                elseif btn_label == "设置密码" then
                    show_password_set_popup(function(new_password)
                        sys.publish("AUTOSTART_SET_PASSWORD", "", new_password or "")
                        sys.publish("AUTOSTART_SET_TARGET_AND_ENABLE", app.path, new_password or "")
                    end)
                end
            end
        })
        action_confirm_box:show()
    end
end

local function handle_cancel_auto_start(app)
    if auto_start_has_password then
        show_password_verify_popup("验证密码以取消自启", function(pwd)
            sys.publish("AUTOSTART_SET_ENABLED", false, pwd)
        end)
    else
        sys.publish("AUTOSTART_SET_ENABLED", false, "")
    end
end

-- ==================== 长按上下文菜单 ====================

show_app_context_menu = function(app)
    destroy_context_ui()
    local d = density_scale_val
    local is_auto = auto_start_enabled and (auto_start_target == app.path)
    local win_w = math.floor(screen_w * 0.62)
    local header_h = math.floor(46 * d)
    local pad_in = math.floor(16 * d)
    local item_h = math.floor(42 * d)
    local item_gap = math.floor(8 * d)
    local icon_size = math.floor(44 * d)
    local gap = math.floor(10 * d)
    local cancel_h = math.floor(40 * d)

    local items = {}
    if is_auto then
        items = { { text = "取消自启动", color = theme.C.amber, action = "cancel_auto" },
                  { text = "卸载应用",   color = theme.C.rose,  action = "uninstall" } }
    else
        items = { { text = "设为自启",   color = theme.C.amber, action = "set_auto" },
                  { text = "卸载应用",   color = theme.C.rose,  action = "uninstall" } }
    end

    local auto_label_h = is_auto and (math.floor(20 * d) + gap) or 0
    local win_h = header_h + pad_in * 2 + icon_size + gap + auto_label_h
        + #items * (item_h + item_gap) + gap + cancel_h

    local win = airui.win({
        parent = airui.screen, title = app.name or "未知",
        w = win_w, h = win_h, close_btn = true, auto_center = true,
        style = dialog_style(),
        on_close = function() context_menu_win = nil end,
    })
    context_menu_win = win

    local y = pad_in
    theme.image(win, { src = app.icon, x = math.floor((win_w - icon_size) / 2), y = y,
        w = icon_size, h = icon_size })
    y = y + icon_size + gap

    if is_auto then
        -- 原文本 "● 已设为开机自启" 里的 "●"(U+25CF) 内置字库不含该字形，去掉该字符；
        -- 状态语义改由琥珀色承担（弹窗内居中的单行提示，加圆点会导致定位依赖文字实测宽度）
        local auto_h = math.floor(20 * d)
        theme.label(win, { x = pad_in, y = y, w = win_w - 2 * pad_in, h = auto_h,
            text = "已设为开机自启", size = theme.F.body, color = theme.C.amber,
            align = airui.TEXT_ALIGN_CENTER })
        y = y + auto_h + gap
    end

    for _, item in ipairs(items) do
        theme.ghost_button(win, {
            x = pad_in, y = y, w = win_w - 2 * pad_in, h = item_h,
            text = item.text, fg = item.color,
            on_click = function()
                destroy_context_ui()
                if item.action == "set_auto" then handle_set_auto_start(app)
                elseif item.action == "cancel_auto" then handle_cancel_auto_start(app)
                elseif item.action == "uninstall" then handle_uninstall_app(app) end
            end,
        })
        y = y + item_h + item_gap
    end

    y = y + gap
    theme.ghost_button(win, { x = pad_in, y = y, w = win_w - 2 * pad_in, h = cancel_h,
        text = "取消", on_click = function() destroy_context_ui() end })
end

local function on_auto_start_password_result(success, msg)
    if not success then
        action_confirm_box = show_info_box("提示", msg or "操作失败", { "确定" },
            function(self) self:destroy(); action_confirm_box = nil end)
    end
end

-- ==================== 重复应用检测 ====================

local STORAGE_LABELS = {
    internal = "内置文件系统", sd_tf = "SD/TF卡",
    little_flash = "外挂Flash", nand_flash = "外挂Flash",
}

local function check_duplicates()
    local dup, dup_count = exapp.list_duplicates()
    if dup_count == 0 then return end
    local idx = 0
    local app_list = {}
    for app_name, entries in pairs(dup) do
        idx = idx + 1
        app_list[idx] = { app_name = app_name, entries = entries }
    end
    log.warn("idle_win", "duplicate apps detected:", dup_count)

    local function format_size(kb)
        if not kb or kb == 0 then return "未知" end
        if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
        return math.floor(kb) .. " KB"
    end

    local current = 0
    local function process_next()
        current = current + 1
        if current > #app_list then load_external_apps() return end
        local item = app_list[current]
        local entries = item.entries
        local cn_name = entries[1].cn_name or item.app_name
        local lines = {}
        local buttons = {}
        for _, entry in ipairs(entries) do
            local label = STORAGE_LABELS[entry.storage_type] or entry.storage_type
            lines[#lines + 1] = label .. "：" .. format_size(entry.origin_size_kb)
            buttons[#buttons + 1] = "保留" .. label
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "未保留的副本将被自动删除。"
        local box = airui.msgbox({
            w = math.min(math.floor(screen_w * 0.85), 480),
            h = math.floor(screen_h * 0.40),
            style = { text_font_size = math.max(16, math.floor(16 * density_scale_val)) },
            title = "重复应用",
            text = "应用：" .. cn_name .. "\n\n" .. table.concat(lines, "\n"),
            buttons = buttons,
            on_action = function(self, btn_label)
                self:destroy()
                for _, entry in ipairs(entries) do
                    local label = STORAGE_LABELS[entry.storage_type] or entry.storage_type
                    if btn_label == "保留" .. label then
                        local ok, err = exapp.resolve_duplicate(item.app_name, entry.storage_type)
                        if not ok then
                            log.warn("idle_win", "resolve_duplicate failed:", item.app_name, err)
                            show_info_box("操作失败", err or "未知错误", { "确定" },
                                function(b) b:destroy(); process_next() end)
                            return
                        end
                        process_next()
                        return
                    end
                end
                process_next()
            end
        })
        box:show()
    end
    process_next()
end

-- ==================== 安装更新 ====================

local app_rebuild_pending = false
local app_cache_dirty = false

local function on_installed_updated()
    app_cache_dirty = true
    if not app_rebuild_pending then
        app_rebuild_pending = true
        sys.timerStart(function()
            app_rebuild_pending = false
            if app_cache_dirty then
                app_cache_dirty = false
                load_external_apps()
            end
        end, 500)
    end
end

-- ==================== FOTA 升级弹窗 ====================

local function fota_msgbox(title, text, buttons, on_ok_label, ok_event)
    local box = airui.msgbox({
        w = math.min(math.floor(screen_w * 0.80), 420),
        h = math.floor(screen_h * 0.25),
        style = { text_font_size = math.max(16, math.min(20, math.floor(screen_h * 0.026))) },
        title = title, text = text, buttons = buttons,
        on_action = function(self, btn_label)
            self:destroy()
            if btn_label == on_ok_label then sys.publish(ok_event) end
        end
    })
    box:show()
end

local function show_fota_reboot_prompt(message)
    if _G._fota_settings_open then return end
    fota_msgbox("固件更新", message or "升级包已下载完成，是否重启设备进行升级？",
        { "稍后重启", "立即重启" }, "立即重启", "FOTA_CONFIRM_REBOOT")
end

local function show_fota_download_prompt(message)
    if _G._fota_settings_open then return end
    fota_msgbox("固件更新", message or "检测到新版本，是否下载升级？",
        { "取消", "开始下载" }, "开始下载", "FOTA_DOWNLOAD_START")
end

-- ==================== 状态刷新 ====================

local function update_time_date(time_str, date_str, weekday_str)
    if time_str then status_cache.time = time_str end
    if date_str then status_cache.date = date_str end
    if weekday_str then status_cache.weekday = weekday_str end
    if status_time_label then status_time_label:set_text(status_cache.time) end
    if big_time_label then big_time_label:set_text(status_cache.time) end
    if date_label then date_label:set_text(status_cache.weekday .. " | " .. status_cache.date) end
    if greet_label then greet_label:set_text(greeting_text(status_cache.time) .. "，合宙用户!") end
end

local function update_wifi_icon(level)
    if level == nil then return end
    status_cache.wifi_level = level
    if wifi_icon then wifi_icon:set_src("/luadb/wifixinhao" .. level .. ".png") end
end

local function update_mobile_icon(level)
    if level == nil then return end
    status_cache.mobile_level = level
    if mobile_icon then
        local ii
        if level == -1 then ii = 6 elseif level == 1 then ii = 5 else ii = level - 1 end
        mobile_icon:set_src("/luadb/4Gxinhao" .. ii .. ".png")
    end
end

local function update_ethernet_icon(state)
    if not ethernet_icon then return end
    if state == 1 then ethernet_icon:set_src("/luadb/ethernet.png")
    elseif state == 2 then ethernet_icon:set_src("/luadb/ethernet_link_down.png")
    else ethernet_icon:set_src("/luadb/ethernet_fault.png") end
end

-- ==================== 电池充电动画 ====================

local charge_anim_timer = nil
local charge_anim_value = 0
local charge_anim_active = false

local function stop_charge_anim()
    if charge_anim_timer then sys.timerStop(charge_anim_timer); charge_anim_timer = nil end
    charge_anim_active = false
end

local function start_charge_anim()
    stop_charge_anim()
    charge_anim_value = 0
    charge_anim_active = true
    charge_anim_timer = sys.timerLoopStart(function()
        if not battery_bar then stop_charge_anim() return end
        charge_anim_value = charge_anim_value + 4
        if charge_anim_value > 100 then charge_anim_value = 0 end
        battery_bar:set_value(charge_anim_value)
    end, 100)
end

local function on_status_battery(data)
    if not data or not battery_bar or not battery_label then return end
    local level = data.level or 0
    if not data.present then
        stop_charge_anim()
        battery_bar:set_value(0)
        battery_label:set_text("--")
        return
    end
    battery_label:set_text(level .. "%")
    if data.charging then
        battery_bar:set_indicator_color(theme.C.green)
        if not charge_anim_active then start_charge_anim() end
    else
        stop_charge_anim()
        battery_bar:set_value(level)
        if level < 20 then battery_bar:set_indicator_color(theme.C.rose)
        elseif level < 50 then battery_bar:set_indicator_color(theme.C.amber)
        else battery_bar:set_indicator_color(theme.C.green) end
    end
end

-- ==================== 页面构建 ====================

local function build_rail(parent)
    if not use_rail then return end
    local rail = theme.box(parent, { x = 0, y = 0, w = rail_w, h = screen_h,
        color = theme.C.white, opa = theme.OPA.rail })

    -- 品牌块
    local bs = clamp(math.floor(rail_w * 0.42), 32, 44)
    local brand = theme.card(rail, {
        x = math.floor((rail_w - bs) / 2), y = pad, w = bs, h = bs,
        radius = theme.R.md, color = theme.C.amber, opa = 255, border_w = 0,
    })
    theme.image(brand, { icon = "brand", placeholder = true,
        x = bs * 0.24, y = bs * 0.24, w = bs * 0.52, h = bs * 0.52 })

    -- 内置应用快捷入口（替代原导航项）
    local iw = math.floor(rail_w * 0.80)
    local ih = clamp(math.floor(screen_h * 0.10), 46, 60)
    local gap = math.floor(4 * density_scale_val)
    local y = pad + bs + pad

    for _, b in ipairs(builtin_apps) do
        local item = theme.card(rail, {
            x = math.floor((rail_w - iw) / 2), y = y, w = iw, h = ih,
            radius = theme.R.md,
            color = theme.C.surface, opa = 0,
            on_click = function() sys.publish("OPEN_" .. b.win .. "_WIN") end,
        })
        local isz = math.floor(ih * 0.36)
        theme.image(item, { icon = b.icon, placeholder = true, x = math.floor((iw - isz) / 2),
            y = math.floor(ih * 0.18), w = isz, h = isz })
        theme.label(item, {
            x = 2, y = math.floor(ih * 0.56), w = iw - 4, h = math.floor(ih * 0.38),
            text = b.name, size = theme.F.tiny,
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        y = y + ih + gap
    end

end

local function build_status_bar(parent)
    -- 不用容器包装，直接在 parent 上放元素，避免不可见容器产生横线
    local isz = math.floor(status_h * 0.62)
    local icon_y = math.floor((status_h - isz) / 2)
    local gap = math.floor(8 * density_scale_val)
    local bx = content_x + pad   -- 状态栏内容区左偏移
    local by = pad               -- 状态栏内容区上偏移

    -- 左侧：问候语
    greet_label = theme.label(parent, {
        x = bx, y = by + icon_y, w = math.floor(content_w * 0.5), h = isz,
        text = greeting_text(status_cache.time) .. "，合宙用户!",
        size = theme.F.small, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧从右往左：时间 / 电量 / 以太网 / 4G / WiFi
    local rx = content_w - 2 * pad

    local time_w = math.floor(50 * density_scale_val)
    rx = rx - time_w
    status_time_label = theme.label(parent, {
        x = bx + rx, y = by + icon_y, w = time_w, h = isz,
        text = status_cache.time, size = theme.F.small, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    if has_battery then
        local bw = math.floor(54 * density_scale_val)
        local bh = math.floor(status_h * 0.58)
        rx = rx - bw - gap
        battery_container = theme.box(parent, {
            x = bx + rx, y = by + math.floor((status_h - bh) / 2), w = bw, h = bh,
            color = theme.C.black, opa = 0, radius = bh,
        })
        battery_bar = airui.bar({
            parent = battery_container, x = 0, y = 0, w = bw, h = bh,
            min = 0, max = 100, value = 0,
            indicator_color = theme.C.green, bg_color = theme.C.stroke_soft, radius = bh,
        })
        battery_label = theme.label(battery_container, {
            x = 0, y = 0, w = bw, h = bh, text = "--",
            px_size = math.max(16, math.floor(11 * density_scale_val)),
            color = theme.C.t1, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    if has_eth then
        rx = rx - isz - gap
        ethernet_icon = theme.image(parent, {
            src = "/luadb/ethernet_link_down.png", x = bx + rx,
            y = by + icon_y, w = isz, h = isz,
        })
    end
    if has_4g then
        rx = rx - isz - gap
        mobile_icon = theme.image(parent, {
            src = "/luadb/4Gxinhao6.png", x = bx + rx,
            y = by + icon_y, w = isz, h = isz,
        })
    end
    if has_wifi then
        rx = rx - isz - gap
        wifi_icon = theme.image(parent, {
            src = "/luadb/wifixinhao0.png", x = bx + rx,
            y = by + icon_y, w = isz, h = isz,
        })
    end
end

local function build_clock_card(parent)
    local y = pad + status_h + pad
    local card = theme.card(parent, {
        x = content_x + pad, y = y, w = content_w - 2 * pad, h = clock_h,
    })

    local inner_pad = math.floor(clock_h * 0.14)
    local hero = clamp(math.floor(screen_h * 0.13), 48, 80)
    local date_h = clamp(math.floor(hero * 0.32), 14, 22)
    local date_y = inner_pad + hero + math.floor(6 * density_scale_val)

    big_time_label = theme.label(card, {
        x = inner_pad, y = inner_pad, w = math.floor(content_w * 0.50), h = hero + 4,
        text = status_cache.time, px_size = hero, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    date_label = theme.label(card, {
        x = inner_pad, y = date_y, w = math.floor(content_w * 0.50), h = date_h,
        text = status_cache.weekday .. " | " .. status_cache.date,
        size = theme.F.body, color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧资料中心（上下结构：文字在上，二维码在下）
    local card_w = content_w - 2 * pad  -- 卡片自身宽度
    local qlabel_h = clamp(math.floor(clock_h * 0.12), 12, 18)
    local qs = clamp(math.floor(clock_h * 0.48), 40, 72)
    local qr_gap = math.floor(3 * density_scale_val)
    local total_qr_h = qlabel_h + qr_gap + qs
    local qr_y_start = inner_pad + math.floor((clock_h - inner_pad * 2 - total_qr_h) / 2)
    local qx = card_w - inner_pad - qs  -- 相对于卡片左边缘

    theme.label(card, {
        x = qx, y = qr_y_start, w = qs, h = qlabel_h,
        text = "资料中心", size = theme.F.small, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.qrcode({
        parent = card, x = qx, y = qr_y_start + qlabel_h + qr_gap,
        size = qs,
        data = "https://docs.openluat.com/",
        -- 走二维码专用令牌：dark / light 要保持绝对明暗对比，不能跟着 t1 / scrim 走
        -- （浅色主题下 t1 本身就是深色，拿它当 light_color 会让整张码糊成一块）。
        dark_color = theme.C.qr_dark, light_color = theme.C.qr_light, quiet_zone = true,
    })
end

local function build_apps_card(parent)
    apps_card = theme.card(parent, {
        x = content_x + pad, y = apps_y, w = content_w - 2 * pad, h = apps_h,
        clip = true,
    })

    -- 接住返回值：安装/卸载后靠它刷新计数（见 update_pager）
    apps_head_label = theme.section(apps_card, {
        x = apps_pad_y + 4, y = math.floor(apps_pad_y * 0.6),
        w = math.floor(content_w * 0.4), h = apps_head_h,
        text = "已安装应用 | " .. tostring(#all_apps), size = theme.F.small,
        color = theme.C.t3,
    })

    -- 注意：这里不能按 "#all_apps == 0 就 return" 提前退出。
    -- 首次开机外部应用为 0，提前退出就不会创建分页器，之后装了应用也补不回来。
    -- 空列表下的隐藏交给 update_pager() 统一处理。

    -- 分页器（右上角）—— 缩小按钮宽度防重叠
    local pw = clamp(math.floor(36 * density_scale_val), 24, 40)
    local pager_gap = math.floor(4 * density_scale_val)
    local pager_y = math.floor(apps_pad_y * 0.4)
    local pager_x = content_w - 2 * pad - apps_pad_y

    -- 翻页按钮必须显式给描边：iconbtn 默认是「白底 + 低透明度」，深色主题上够看，
    -- 但浅色主题的卡片本身就是白的，按钮会整块消失，只剩一个孤零零的 ">"。
    pager_prev_btn = theme.iconbtn(apps_card, {
        x = pager_x - pw * 2 - pager_gap, y = pager_y, w = pw, h = apps_head_h,
        radius = theme.R.xs, icon = "chevron_left", text = "<",
        border = theme.C.stroke, text_color = theme.C.primary_light,
        on_click = on_page_prev,
    })
    pager_next_btn = theme.iconbtn(apps_card, {
        x = pager_x - pw, y = pager_y, w = pw, h = apps_head_h,
        radius = theme.R.xs, icon = "chevron_right", text = ">",
        border = theme.C.stroke, text_color = theme.C.primary_light,
        on_click = on_page_next,
    })
    page_idx_label = theme.label(apps_card, {
        x = pager_x - pw * 2 - pager_gap - math.floor(36 * density_scale_val), y = pager_y,
        w = math.floor(36 * density_scale_val), h = apps_head_h,
        text = "1/1", size = theme.F.small, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    grid_container = theme.box(apps_card, {
        x = apps_pad_y, y = apps_head_h + apps_pad_y,
        w = content_w - 2 * pad - 2 * apps_pad_y, h = grid_rows * (tile_h + grid_gap),
        color = theme.C.black, opa = 0,
    })

    -- 首建也要走一遍：把计数写进表头，并按 #all_apps 决定分页器显隐
    update_pager()
end

local function build_dock(parent)
    local dock_y = screen_h - pad - dock_h
    local dock = theme.card(parent, {
        x = content_x + pad, y = dock_y, w = content_w - 2 * pad, h = dock_h,
        radius = theme.R.xl, opa = theme.OPA.dock, border = theme.C.stroke,
    })

    local items = {}
    for _, b in ipairs(builtin_apps) do
        if b.dock then items[#items + 1] = b end
    end
    local n = #items
    if n == 0 then return end

    local inner_w = content_w - 2 * pad
    local iw = clamp(math.floor(inner_w / (n + 1)), 56, 86)
    local total = n * iw
    local sx = math.floor((inner_w - total) / 2)
    local icon_size = clamp(math.floor(dock_h * 0.52), 28, 42)

    for i, it in ipairs(items) do
        local win = it.win
        theme.tile(dock, {
            x = sx + (i - 1) * iw, y = math.floor((dock_h - (icon_size + 26)) / 2),
            w = iw, h = icon_size + 26,
            icon = it.icon, icon_size = icon_size, text = it.name,
            size = theme.F.tiny, text_color = theme.C.t2,
            on_click = function() sys.publish("OPEN_" .. win .. "_WIN") end,
        })
    end
end

-- ==================== 网络事件（以太网图标） ====================

local function on_netdrv_status(net_type)
    if net_type == "Ethernet" or net_type == "8101SPIETH" or net_type == "ETHUSER1" then
        update_ethernet_icon(1)
    end
end

local function on_ip_ready(ip, adapter)
    if adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1 then
        update_ethernet_icon(1)
    end
end

local function on_ip_lose(adapter)
    if adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1 then
        update_ethernet_icon(2)
    end
end

-- ==================== 天气卡片 ====================

-- 天气卡控件引用（WEATHER_UPDATED 到达时整卡重建，避免文本变长后撑破固定宽度）
local weather_card = nil
local weather_ui = { days = {}, temps = {} }

-- 状况 → 图标资源名 + 强调色（缺图时用该色做兜底色块，与 theme.tile 的兜底约定一致）
local WEATHER_STYLES = {
    ["晴"]   = { icon = "weather_sunny",    tint = theme.C.amber },
    ["多云"] = { icon = "weather_cloudy",   tint = theme.C.cyan_light },
    ["阴"]   = { icon = "weather_overcast", tint = theme.C.t2 },
    ["雨"]   = { icon = "weather_rain",     tint = theme.C.cyan },
    ["雪"]   = { icon = "weather_snow",     tint = theme.C.t1 },
}
local WEATHER_STYLE_DEFAULT = { icon = "weather_cloudy", tint = theme.C.amber }

--[[解析天气图标资源：存在才返回路径（theme.image 传 src 时不做存在性校验，
--   直接给不存在的路径会得到一片空白），否则返回 nil + 兜底色。
--   走 theme.icon() 而不是自己拼 "/luadb/..png"：图标目录由 ui_theme.ICON_DIR 统一
--   决定，自己拼路径在目录约定变化时会静默失联（还会绕过它的存在性缓存）。]]
local function weather_icon_path(condition)
    local st = WEATHER_STYLES[condition] or WEATHER_STYLE_DEFAULT
    local path, exists = theme.icon(st.icon)
    if exists and path then return path, st.tint end
    return nil, st.tint
end

--[[单日预报 → 展示文本，如 28/21
不带度数符号：列宽在 480×854 上只有 76px，且符号依赖字体支持；
当前温度已用 ℃ 标明量纲，预报列头有日名，语义不丢。]]
local function fmt_daily_temp(fc)
    if not fc or fc.high == nil or fc.low == nil then return "--" end
    return fc.high .. "/" .. fc.low
end

--[[地点|状况 → 单串文本
用 ASCII 的 "|" 而不是 "·"(U+00B7)：内置字库不含 U+00B7。
整串交给一个 label 渲染，两个词的间距只取决于 "|" 自身宽度；
后续接真实天气数据时同样走这里拼接，不会再各摆各的坐标。]]
local function weather_info_text()
    local city = weather_cache.city or ""
    local cond = weather_cache.condition or ""
    if city == "" then return cond end
    if cond == "" then return city end
    return city .. "|" .. cond
end

--[[天气图标资源缺失时的自绘兜底
晴天：光晕 + 四向光芒 + 日面。LVGL 的容器不能旋转，斜向光芒画不出来，只取上下左右。
其余状况：色调圆角块 + 状况首字（string.sub 取 1..3 字节即首个汉字）。
不用「实色方块」兜底：浅色主题下那会变成一块看不出语义的色斑。
（theme.box 会把 radius 按密度放大，但 LVGL 会把半径夹到短边的一半，
  所以给一个超过 size/2 的值等价于画整圆。）]]
local function draw_weather_fallback(parent, x, y, size, condition, tint)
    if condition ~= "晴" then
        local ph = theme.card(parent, {
            x = x, y = y, w = size, h = size,
            radius = theme.R.md, color = tint, opa = 40, border = tint, border_w = 1,
        })
        theme.label(ph, {
            x = 0, y = 0, w = size, h = size,
            text = string.sub(condition or "", 1, 3),
            px_size = clamp(math.floor(size * 0.50), 16, 22),
            color = tint, align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    theme.box(parent, {
        x = x, y = y, w = size, h = size,
        radius = math.floor(size / 2), color = tint, opa = 32,
    })
    local rw = math.max(2, math.floor(size * 0.08))
    local rl = math.max(3, math.floor(size * 0.16))
    local rr = math.floor(rw / 2)
    local cx = x + math.floor(size / 2)
    local cy = y + math.floor(size / 2)
    theme.box(parent, { x = cx - rr, y = y, w = rw, h = rl, radius = rr, color = tint, opa = 255 })
    theme.box(parent, { x = cx - rr, y = y + size - rl, w = rw, h = rl, radius = rr, color = tint, opa = 255 })
    theme.box(parent, { x = x, y = cy - rr, w = rl, h = rw, radius = rr, color = tint, opa = 255 })
    theme.box(parent, { x = x + size - rl, y = cy - rr, w = rl, h = rw, radius = rr, color = tint, opa = 255 })
    local core = math.floor(size * 0.50)
    theme.box(parent, {
        x = x + math.floor((size - core) / 2), y = y + math.floor((size - core) / 2),
        w = core, h = core, radius = math.floor(core / 2), color = tint, opa = 255,
    })
end

local function build_weather_card(parent)
    if weather_h <= 0 then return end
    local card_w = content_w - 2 * pad
    local card = theme.card(parent, {
        x = content_x + pad, y = weather_y, w = card_w, h = weather_h,
    })
    weather_card = card
    weather_ui.icon_img = nil
    weather_ui.icon_text = nil
    weather_ui.days = {}
    weather_ui.temps = {}

    -- ========== 内部度量：全部由卡片高度推导，保证文字不被裁切 ==========
    -- 字号走 px_size 显式给像素值（绕开 theme 的 16px 字号下限歧义），
    -- 行高统一取「字号 + 2」，修掉旧版「11~14px 行高装 16px 文字」的裁字问题。
    local pad_in = clamp(math.floor(weather_h * 0.15), 8, 12)
    local content_h = weather_h - 2 * pad_in
    local line_gap = clamp(math.floor(weather_h * 0.04), 2, 4)
    local fs_info = clamp(math.floor(content_h * 0.34), 16, 20)              -- 地点|状况
    local fs_fc = math.min(clamp(math.floor(content_h * 0.30), 16, 18), fs_info)  -- 预报（次级）
    local fs_temp = clamp(math.floor(content_h * 0.50), 20, 34)              -- 当前温度（英雄字）
    -- 必要时压缩温度字号，确保「温度 + 地点|状况」两行加间距不超出内容高度
    local max_temp_fs = content_h - fs_info - line_gap - 4
    if fs_temp > max_temp_fs then fs_temp = math.max(16, max_temp_fs) end

    local temp_h = fs_temp + 2
    local info_h = fs_info + 2
    local fc_h = fs_fc + 2

    -- ========== 左侧：天气图标 + 温度 + 地点|状况 ==========
    local icon_sz = clamp(math.floor(content_h * 0.72), 24, 40)
    local icon_x = pad_in
    local icon_y = pad_in + math.floor((content_h - icon_sz) / 2)

    -- 图标优先：/luadb/weather_*.png（文件名见 WEATHER_STYLES 的 icon 字段）
    local wicon_path, wtint = weather_icon_path(weather_cache.condition)
    if wicon_path then
        weather_ui.icon_img = theme.image(card, {
            src = wicon_path, x = icon_x, y = icon_y, w = icon_sz, h = icon_sz,
        })
    else
        draw_weather_fallback(card, icon_x, icon_y, icon_sz, weather_cache.condition, wtint)
    end

    -- 温度（英雄字）在上、「地点|状况」在下，整块在内容区垂直居中
    local gap = clamp(math.floor(weather_h * 0.10), 8, 14)
    local text_x = icon_x + icon_sz + gap
    local temp_w = clamp(math.floor(card_w * 0.13), 76, 140)
    local info_w = clamp(math.floor(card_w * 0.24), 128, 240)
    local block_w = math.max(temp_w, info_w)
    local block_h = temp_h + line_gap + info_h
    local block_y = pad_in + math.floor((content_h - block_h) / 2)

    weather_ui.temp = theme.label(card, {
        x = text_x, y = block_y, w = block_w, h = temp_h,
        text = weather_cache.temp or "--", px_size = fs_temp,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 「地点|状况」整串由一个 label 渲染。
    -- 旧写法是「城市 label + 1px 竖线 + 状况 label」三个控件按算出来的坐标摆位，
    -- 城市名一长两个词之间就被撑得很开；拼成单串后间距只由 "|" 自身宽度决定。
    local info_y = block_y + temp_h + line_gap
    weather_ui.info = theme.label(card, {
        x = text_x, y = info_y, w = block_w, h = info_h,
        text = weather_info_text(), px_size = fs_info,
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    local left_w = text_x + block_w

    -- ========== 右侧：未来几天预报（等宽列 + 列间细分隔线） ==========
    -- 先按剩余宽度均分列宽，再夹到 72~200；若放不下 day_count 列就逐列递减，
    -- 这样 320 宽的 4 寸竖屏也不会溢出卡片（退化到只显示 1 天，甚至只留当前天气）。
    local gap_fc = clamp(math.floor(card_w * 0.012), 8, 18)
    local right_edge = card_w - pad_in
    local fc_zone_x = left_w + gap_fc * 2 + 1
    local min_col = 72
    local day_count = 3
    while day_count > 0 and (right_edge - fc_zone_x - (day_count - 1) * gap_fc) < day_count * min_col do
        day_count = day_count - 1
    end

    if day_count > 0 then
        local day_col = math.floor((right_edge - fc_zone_x - (day_count - 1) * gap_fc) / day_count)
        if day_col > 200 then day_col = 200 end
        local fc_total = day_count * day_col + (day_count - 1) * gap_fc
        local fc_x = right_edge - fc_total
        if fc_x < fc_zone_x then fc_x = fc_zone_x end

        -- 分区竖线：把「当前天气」与「未来预报」两块在视觉上分开。
        -- 走 theme.divider（令牌色 + 令牌不透明度）—— 原来写死「白 + 固定透明度」，
        -- 浅色主题的卡片本身就是白的，这条线会整根消失。
        local div_h = clamp(math.floor(content_h * 0.72), 20, 44)
        theme.divider(card, {
            x = fc_x - gap_fc, y = pad_in + math.floor((content_h - div_h) / 2),
            w = 1, h = div_h,
        })

        local fc_block_h = fc_h * 2 + line_gap
        local fc_y = pad_in + math.floor((content_h - fc_block_h) / 2)
        for i = 1, day_count do
            local col_x = fc_x + (i - 1) * (day_col + gap_fc)
            local fc = weather_cache.daily and weather_cache.daily[i]
            weather_ui.days[i] = theme.label(card, {
                x = col_x, y = fc_y, w = day_col, h = fc_h,
                text = (fc and fc.day) or "--", px_size = fs_fc, color = theme.C.t3,
                align = airui.TEXT_ALIGN_CENTER,
            })
            weather_ui.temps[i] = theme.label(card, {
                x = col_x, y = fc_y + fc_h + line_gap, w = day_col, h = fc_h,
                text = fmt_daily_temp(fc), px_size = fs_fc, color = theme.C.t1,
                align = airui.TEXT_ALIGN_CENTER,
            })
            if i < day_count then
                theme.divider(card, {
                    x = col_x + day_col + math.floor(gap_fc / 2), y = fc_y + 2,
                    w = 1, h = fc_block_h - 4,
                })
            end
        end
    end
end

--[[天气数据更新（WEATHER_UPDATED）：写入缓存后整卡重建
    ——温度/状况文本长度、图标资源都可能变化，重建比逐控件 set_text 更稳]]
local function on_weather_updated(data)
    if type(data) ~= "table" then return end
    if data.city then weather_cache.city = data.city end
    if data.condition then weather_cache.condition = data.condition end
    if data.temp ~= nil then
        -- 数值温度补 ℃ 单位；字符串则原样透传（由数据源决定格式）
        weather_cache.temp = (type(data.temp) == "number") and (data.temp .. "℃") or tostring(data.temp)
    end
    if type(data.daily) == "table" then weather_cache.daily = data.daily end
    if not main_container then return end
    if weather_card then pcall(weather_card.destroy, weather_card); weather_card = nil end
    pcall(build_weather_card, main_container)
end

-- ==================== 窗口生命周期 ====================

local timer_handler = nil

local function on_create()
    log.info("idle_win", "on_create begin")
    calc_layout()

    main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    build_rail(main_container)
    build_status_bar(main_container)
    build_clock_card(main_container)
    pcall(build_weather_card, main_container)  -- pcall 防止天气卡片报错阻断后续构建

    -- 先收集应用列表（此时 apps_card 为空，render_grid_page 会直接返回），
    -- 再创建应用卡片与网格，保证卡片标题中的应用数量准确
    load_external_apps()
    build_apps_card(main_container)
    render_grid_page()
    update_pager()
    if not use_rail then build_dock(main_container) end

    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    update_wifi_icon(status_cache.wifi_level)
    update_mobile_icon(status_cache.mobile_level)

    timer_handler = sys.timerLoopStart(function()
        update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    end, 1000)

    sys.subscribe("STATUS_TIME_UPDATED", update_time_date)
    if has_4g then sys.subscribe("STATUS_SIGNAL_UPDATED", update_mobile_icon) end
    if has_wifi then sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", update_wifi_icon) end
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    sys.subscribe("WEATHER_UPDATED", on_weather_updated)
    if has_battery then sys.subscribe("BATTERY_STATUS", on_status_battery) end
    sys.subscribe("AUTOSTART_SETTINGS_VALUE", on_auto_start_settings)
    sys.subscribe("AUTOSTART_CONFIG_CHANGED", request_auto_start_state)
    sys.subscribe("AUTOSTART_PASSWORD_RESULT", on_auto_start_password_result)
    sys.subscribe("FOTA_PROMPT_REBOOT", show_fota_reboot_prompt)
    sys.subscribe("FOTA_PROMPT_DOWNLOAD", show_fota_download_prompt)

    if has_eth then
        sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", on_netdrv_status)
        sys.subscribe("IP_READY", on_ip_ready)
        sys.subscribe("IP_LOSE", on_ip_lose)
    end

    request_auto_start_state()
    sys.publish("REQUEST_STATUS_REFRESH")
    sys.timerStart(check_duplicates, 1200)

    log.info("idle_win", string.format("桌面构建完成 %dx%d rail=%d cols=%d rows=%d apps=%d",
        screen_w, screen_h, rail_w, grid_cols, grid_rows, #all_apps))
end

local function on_destroy()
    log.info("idle_win", "on_destroy")
    if timer_handler then sys.timerStop(timer_handler); timer_handler = nil end
    stop_charge_anim()
    sys.unsubscribe("STATUS_TIME_UPDATED", update_time_date)
    if has_4g then sys.unsubscribe("STATUS_SIGNAL_UPDATED", update_mobile_icon) end
    if has_wifi then sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", update_wifi_icon) end
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    sys.unsubscribe("WEATHER_UPDATED", on_weather_updated)
    if has_battery then sys.unsubscribe("BATTERY_STATUS", on_status_battery) end
    sys.unsubscribe("AUTOSTART_SETTINGS_VALUE", on_auto_start_settings)
    sys.unsubscribe("AUTOSTART_CONFIG_CHANGED", request_auto_start_state)
    sys.unsubscribe("AUTOSTART_PASSWORD_RESULT", on_auto_start_password_result)
    sys.unsubscribe("FOTA_PROMPT_REBOOT", show_fota_reboot_prompt)
    sys.unsubscribe("FOTA_PROMPT_DOWNLOAD", show_fota_download_prompt)
    if has_eth then
        sys.unsubscribe("EXLIB_NETDRV_NETWORK_STATUS", on_netdrv_status)
        sys.unsubscribe("IP_READY", on_ip_ready)
        sys.unsubscribe("IP_LOSE", on_ip_lose)
    end
    destroy_context_ui()

    if main_container then main_container:destroy(); main_container = nil end
    status_time_label = nil; big_time_label = nil; date_label = nil; greet_label = nil
    wifi_icon = nil; mobile_icon = nil; ethernet_icon = nil
    battery_bar = nil; battery_label = nil; battery_container = nil
    grid_container = nil; page_idx_label = nil
    apps_card = nil
    -- 必须与上面同一约定：去抖定时器可能晚于 on_destroy 触发，
    -- 悬空引用会让 update_pager 在已销毁的控件上调方法
    apps_head_label = nil
    pager_prev_btn = nil; pager_next_btn = nil
    weather_card = nil
    weather_ui = { days = {}, temps = {} }
    app_cards = {}
    all_apps = {}
    window_id = nil
end

-- 换肤：打脏标记，等桌面重新回到前台时整屏重建
-- （换肤在设置页发起，此刻桌面在窗口栈下层，直接重建会打乱焦点顺序）
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()
sys.subscribe("UI_THEME_CHANGED", mark_theme_dirty)

local function on_get_focus()
    if take_theme_dirty() then
        -- on_destroy 会注销全部订阅与定时器并清空控件引用，on_create 重新建立，
        -- 二者成对调用即可完整重绘（桌面窗口本身不关闭，window_id 需保留）
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
    end
    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    load_external_apps()
    request_auto_start_state()
    if not timer_handler then
        timer_handler = sys.timerLoopStart(function()
            update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
        end, 1000)
    end
end

local function on_lose_focus()
    if timer_handler then sys.timerStop(timer_handler); timer_handler = nil end
    stop_charge_anim()
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
