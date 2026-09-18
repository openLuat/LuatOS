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
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local window_id = nil
local main_container = nil
local apps_card = nil
local video_obj = nil           -- 视频播放组件（开机动画循环播放）
local video_is_playing = true   -- 播放状态
local video_is_loop = true      -- 循环状态
local video_ctrl_bar = nil      -- 控制栏容器
local video_ctrl_visible = true -- 控制栏可见性
local video_ctrl_timer = nil    -- 控制栏自动隐藏定时器（已停用，仅保留清理，防旧定时器残留）
local video_play_label = nil    -- 播放/暂停按钮文字
local video_loop_label = nil    -- 循环按钮文字
local video_file_label = nil    -- 当前文件名标签
local video_current_file = "/luatos_boot.hzv"  -- 当前播放文件（res/luatos_boot.hzv 打包后在 /luadb/ 下）
local _video_card_ref = nil   -- 视频卡片容器引用（供切换文件时使用）
local video_loop_timer = nil  -- MJPG 循环定时器（已停用：循环改由组件 loop 参数负责）
-- 配套音频播放（同名 MP3）
local audio_obj = nil         -- 当前音频文件路径（非 nil 表示有配套音频）
local audio_playing = false   -- 音频播放状态
local exaudio_inited = false  -- exaudio.pm RESUME 已调用
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

-- 方案A：左侧视频 + 右侧信息列
local col_gap = 10             -- 左右栏 / 右列卡片间距（设计稿 10）
local video_w = 480            -- 视频区域宽度
local video_h = 270            -- 视频区域高度（按 luatos_boot 素材帧高留的布局基准）
local video_x = 0              -- 视频左上角 X（相对 content_x）
local video_y = 0              -- 视频左上角 Y（相对内容区顶部）
local video_frame_h = 0        -- 视频画面高度（卡片高 - 控制栏高）
local right_x = 0              -- 右侧信息列起始 X
local right_w = 0              -- 右侧信息列宽度
local video_enabled = false    -- 是否启用视频布局（仅宽屏启用）

local clock_y = 0              -- 时钟卡 Y 坐标（video_enabled 时与 video_y 对齐）

local density_scale_val = _G.density_scale or 1.0

local status_cache = { time = "08:00", date = "1970-01-01", weekday = "星期四", mobile_level = -1, wifi_level = 0 }

-- 天气缓存：下面这组是**兜底初值**（联网拿到真数据前先显示，避免空格）。
-- 真实数据由 app/common/weather_app.lua 联网获取：
--   按出口 IP 自动定位城市 -> open-meteo 查天气 -> sys.publish("WEATHER_UPDATED", {...})
-- 本窗口创建时还会 sys.publish("WEATHER_REQUEST") 主动要一次，
--   因为天气数据可能先于窗口到达（订阅晚于发布就会丢首帧）
--
-- 缓存结构：
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
-- 网盘与「应用工厂 / AI 助手」同属可裁剪的大型内置应用：只渲染入口，窗口由 ui_main 按同一开关加载
local has_cloud_disk = _G.project_config and _G.project_config.features and _G.project_config.features.cloud_disk
    and _G.project_config.ui and _G.project_config.ui.show_cloud_disk

local chip_name = (_G.project_config and _G.project_config.chip) or ""
local model_suffix = chip_name:gsub("^Air", "")
local product_name = "合宙引擎主机" .. (model_suffix ~= "" and model_suffix or "")

-- 内置应用（同时出现在网格与底部 Dock）
local builtin_apps = {
    { name = "设置",     win = "SETTINGS",     icon = "settings",  dock = true },
    { name = "应用市场", win = "APP_STORE",    icon = "app_store", dock = true },
    { name = "文件管理", win = "FILE_MANAGER", icon = "file",      dock = true },
}
if has_app_factory then
    table.insert(builtin_apps, { name = "应用工厂", win = "APP_FACTORY", icon = "app_factory", dock = true })
end
if has_ai_chat then
    table.insert(builtin_apps, { name = "AI助手", win = "AI_CHAT", icon = "ai_chat", dock = true })
end
if has_cloud_disk then
    table.insert(builtin_apps, { name = "合宙网盘", win = "CLOUD_DISK", icon = "cloud_disk", dock = true })
end

-- 前向声明（网格点击依赖上下文菜单，后者定义在后面）
local show_app_context_menu
-- 前向声明（一级菜单切换依赖左栏高亮更新器，后者定义在 build_rail 之后）
local set_rail_active

--[[当前激活的一级菜单（内置应用的 win 名）
nil = 桌面态（没有内置应用页打开）。仅用于左栏高亮与日志排查。]]
local active_menu = nil

--[[左栏「桌面」项的哨兵 key
桌面不是内置应用（不发布 OPEN_xxx_WIN），但它是与各内置应用互斥的一级菜单之一，
同样要参与左栏高亮，所以用一个不可能与 win 名冲突的 key 登记进 rail_items。]]
local DESKTOP_KEY = "__desktop"

--[[左栏项控件引用表：{ [win] = { hl = 选中底块 } }
build_rail 填充，set_rail_active 就地切换显隐，避免重建 rail 造成整条栏闪烁。]]
local rail_items = {}

--[[左栏容器本身的引用

v1 只记 rail_items（子项），重建左栏时若只清子项会留下一条空底色的旧栏压在新栏下面，
所以换肤就地重建时必须连容器一起销毁。]]
local rail_container = nil

--[[换肤时「就地重建左栏」的兜底定时器

必须是文件级 local，且声明位置要早于 on_destroy —— 否则 on_destroy 里的同名引用
会落到词法作用域之外、解析成全局变量，两处操作的不是同一个变量，
『销毁时停掉待触发的重建定时器』这条清理会静默失效。]]
local rail_rebuild_timer = nil

--[[失焦前正在播放的视频文件路径
桌面失焦时会销毁视频组件以释放硬解资源，回到桌面按此路径恢复播放。]]
local video_resume_file = nil

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
    header_h = 0
    dock_h = compact and 46 or clamp(math.floor(sh * 0.105), 48, 72)

    content_x = rail_w
    content_w = sw - rail_w

    -- 方案A：宽屏（≥900dp）启用左侧视频 + 右侧信息列布局
    video_enabled = (sw >= 900) and (sh >= 400)

    if video_enabled then
        --[[ 方案A（设计稿 1024x600）：
             左列 = 视频 480 x 全高（576）；右列 406，从上到下：
             状态栏 36 -> 时钟 110 -> 天气 68 -> 应用网格（剩余高度）。
             左右栏间距 10，内容区四周 padding 12。]]
        local inner_w = content_w - 2 * pad

        -- 左列：视频铺满内容区高度，顶部与右列状态栏齐平
        video_x = 0
        video_y = 0
        video_w = clamp(math.floor(inner_w * 0.535), 320, math.floor(inner_w * 0.60))
        video_h = sh - 2 * pad

        -- 右列
        right_x = video_w + col_gap
        right_w = inner_w - video_w - col_gap
        if right_w < 200 then right_w = 200 end

        -- 右列纵向：状态栏只在信息列内（不再横跨整屏）
        status_h = clamp(math.floor(sh * 0.060), 28, 40)     -- 设计稿 36
        clock_h = clamp(math.floor(sh * 0.183), 84, 120)     -- 设计稿 110
        weather_h = clamp(math.floor(sh * 0.113), 52, 80)    -- 设计稿 68

        local ry = pad + status_h + col_gap
        ry = ry + clock_h + col_gap
        weather_y = ry
        ry = ry + weather_h + col_gap
        apps_y = ry
        apps_h = sh - ry - pad        if apps_h < 84 then apps_h = 84 end    else        -- 原始布局（窄屏 / 竖屏）
        clock_h = compact and clamp(math.floor(sh * 0.22), 50, 66)
            or clamp(math.floor(sh * 0.26), 110, 150)
        weather_h = compact and 0 or clamp(math.floor(sh * 0.125), 58, 78)

        local y = pad + status_h + pad
        y = y + clock_h + pad
        weather_y = y
        y = y + weather_h + pad
        apps_y = y
        if use_rail then
            apps_h = sh - y - pad
        else
            apps_h = sh - y - dock_h - pad
        end
        if apps_h < 84 then apps_h = 84 end
    end

    -- 网格参数
    local grid_w = video_enabled and right_w or (content_w - 2 * pad - 2 * apps_pad_y)
    local inner_w = grid_w - 2 * apps_pad_y
    tile_icon = clamp(math.floor(sh * 0.060 * density_scale_val), 26, 48)   -- 设计稿 36
    tile_h = tile_icon + math.floor(30 * density_scale_val)
    apps_head_h = clamp(math.floor(sh * 0.045), 24, 30)
    grid_gap = clamp(math.floor(sw * 0.010), 6, 12)

    local min_tile_w = math.floor(math.max(72, tile_icon * 2.1))
    grid_cols = clamp(math.floor((inner_w + grid_gap) / (min_tile_w + grid_gap)), 2, 6)
    tile_w = math.floor((inner_w - (grid_cols - 1) * grid_gap) / grid_cols)

    local grid_avail = apps_h - apps_head_h - apps_pad_y * 2 - 4
    grid_rows = math.floor((grid_avail + grid_gap) / (tile_h + grid_gap))
    if grid_rows < 1 then grid_rows = 1 end
    apps_per_page = math.max(1, grid_cols * grid_rows)

    --[[把左栏几何暴露给 ui_theme：其余页面据此把自己渲染到右侧内容区，左栏因此始终可见。
    窄屏 rail_w = 0 → shell.enabled = false → 所有页面回到整屏铺满的既有行为，
    窄屏表现与改造前完全一致。]]
    theme.shell.enabled = use_rail
    theme.shell.rail_w  = rail_w
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

--[[一级菜单（内置应用）统一切换入口

所有进入内置应用的入口（应用网格、左栏 rail、底部 dock）都必须走这里，
不要各自直接 sys.publish —— 否则会漏掉「回收旧菜单」这一步，窗口栈会随切换次数持续堆积。

切换是「先开新页、再回收旧页」，但回收**不在本函数里做**，而是交给
exwin.begin_menu_switch 登记事务、由 exwin 在新页面创建完成后收尾。原因：
sys.publish 只是把消息压入全局队列（script/corelib/sys.lua:524），真正的分发在
sys.run() 的下一轮 dispatch，而本轮结束时会先渲染一帧。若在本函数内先清后开，
那一帧渲染的就是被清空后裸露的桌面 —— 表现为切页时先闪一下 idle_win 再进新页面。
登记事务后，回收发生在「新页已挂在屏幕最上层」之后，旧菜单被完全遮挡，无闪烁。

设置 → iot 这类「同一个一级菜单内部的跳转」不走这里，它们仍用各自的 sys.publish，
因此不会被回收；只有点左栏/网格/dock 切换到另一个一级菜单时才会连带销毁。]]
local function open_builtin(win)
    local host = theme.shell.host_id
    local leaf = exwin.children_of(host)[1]   -- 一级菜单互斥，宿主至多有一个直接子窗口

    --[[已经停在目标一级菜单里：只需退回该菜单的根（回收它的后代），菜单页本身不重建。
    这样既不会闪烁，也保住了页面内的滚动位置与已填写的内容。]]
    if active_menu == win and leaf then
        if exwin.has_children(leaf) then
            exwin.close_children_of(leaf)
        end
        return
    end

    exwin.begin_menu_switch(host)   -- 登记切换事务：新页归属 host，旧页由 exwin 在新页创建后回收
    set_rail_active(win)
    sys.publish("OPEN_" .. win .. "_WIN")
end

--[[回到桌面态（左栏底部「桌面」入口）

与 open_builtin 对称，但不开新页面：只清掉当前一级菜单的整棵子树。
close_children_of 末尾会结算一次焦点，idle 的 on_get_focus 随即把高亮切回「桌面」，
所以这里不必再手动调 set_rail_active。已在桌面态时直接返回，省掉一次无谓的焦点结算。]]
local function go_desktop()
    if active_menu == nil then return end
    exwin.close_children_of(theme.shell.host_id)
end

local function tile_bind_click(app)
    if app.is_builtin then
        open_builtin(app.win)
    else
        exapp.open(app.path)
    end
end

local function render_grid_page()
    if not apps_card then return end
    if grid_container then grid_container:destroy(); grid_container = nil end
    app_cards = {}

    local gw = video_enabled and right_w or (content_w - 2 * pad)
    local inner_w = gw - 2 * apps_pad_y
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
            icon = app.icon, icon_size = tile_icon, text = app.name, opa = 6,
            px_size = clamp(math.floor(screen_h * 0.02), 11, 14), text_color = theme.C.t2,
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
    return theme.keyboard({
        --[[键盘统一规范（与 wifi 密码键盘一致）：
            parent 必须是「宽 = 内容区宽」的本页根容器 —— 拼音候选栏与输入预览框
            都由 C 侧建在键盘的父对象上、宽度取父宽的 100%（整屏宽就会左右超出键盘）；
            挂在屏幕根上还会变成「整屏底部居中」，与内容区错开且不随页面销毁。
            y 固定 0（相对父容器底部居中），高度统一 dp(200)，全部带 preview 输入预览条。]]
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density_scale_val),
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
    -- 每次重建都重置引用表：旧控件随 main_container 一并销毁，留着就是悬空引用
    rail_items = {}
    if not use_rail then return end
    --[[左栏底色读 theme.C.rail_bg，不再借用 theme.C.white
    （借用 white 的后果见 ui_theme.lua 的 M.C.rail_bg 注释）]]
    rail_container = theme.box(parent, { x = 0, y = 0, w = rail_w, h = screen_h,
        color = theme.C.rail_bg, opa = theme.OPA.rail })
    local rail = rail_container

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
    local ih = clamp(math.floor(screen_h * 0.087), 46, 56)   -- 设计稿 52
    local gap = math.floor(6 * density_scale_val)            -- 设计稿 6
    local y = pad + bs + pad

    for _, b in ipairs(builtin_apps) do
        local item = theme.card(rail, {
            x = math.floor((rail_w - iw) / 2), y = y, w = iw, h = ih,
            radius = theme.R.md,
            color = theme.C.surface, opa = 0,
            on_click = function() open_builtin(b.win) end,
        })
        --[[选中态底块：必须**先于**图标与文字创建，才能落在 z 序最底层、不遮挡它们。
        默认隐藏，由 set_rail_active 切换显隐（就地改属性，不重建 rail）。
        底块自身不挂 on_click，点击会冒泡到 item 上。]]
        local hl = theme.box(item, {
            x = 0, y = 0, w = iw, h = ih,
            color = theme.C.amber, opa = theme.OPA.rail_active, radius = theme.R.md,
        })
        pcall(function() hl:set_hidden(true) end)
        rail_items[b.win] = { hl = hl }
        -- 重建后按当前激活项恢复高亮（换肤重建 / 从内置应用返回时都需要）
        if active_menu == b.win then
            pcall(function() hl:set_hidden(false) end)
        end

        local isz = math.floor(ih * 0.36)
        theme.image(item, { icon = b.icon, placeholder = true, x = math.floor((iw - isz) / 2),
            y = math.floor(ih * 0.18), w = isz, h = isz })
        theme.label(item, {
            x = 2, y = math.floor(ih * 0.56), w = iw - 4, h = math.floor(ih * 0.38),
            text = b.name, px_size = clamp(math.floor(screen_h * 0.018), 10, 13),
            --[[左栏标签读 t2 而不是 t3

            左栏底色是「rail_bg 叠在主题 bg 上」的合成色，比纯 bg 亮一档；
            t3 是弱文字档，在两套玻璃主题的合成左栏上只有 2.3 / 2.9:1（低于 3:1 下限）。
            t2 在全部 9 套主题的左栏上都 ≥ 4.6:1，而且左栏标签本就是主导航文案，
            语义上对应「次级文字」而非「弱文字」。]]
            color = theme.C.t2, align = airui.TEXT_ALIGN_CENTER,
        })
        y = y + ih + gap
    end

    --[[底部「桌面」入口（设计稿里这个位置是用户头像，换成导航项更实用）：
    它不发布 OPEN_xxx_WIN，只负责把当前一级菜单的整棵子树清掉、回桌面态。

    固定在栏底，与内置应用之间留出空白做视觉分隔。放不下就跳过 —— 内置应用数量由
    配置驱动（最多 6 个），溢出的控件会顶出父容器，而 LVGL 容器天生带 SCROLLABLE，
    一溢出整条左栏就会长出滑动条。]]
    local home_y = screen_h - pad - ih
    if y <= home_y then
        local item = theme.card(rail, {
            x = math.floor((rail_w - iw) / 2), y = home_y, w = iw, h = ih,
            radius = theme.R.md,
            color = theme.C.surface, opa = 0,
            on_click = go_desktop,
        })
        -- 选中底块必须先于图标/文字创建，才落在 z 序最底层（与内置应用项同一套约定）
        local hl = theme.box(item, {
            x = 0, y = 0, w = iw, h = ih,
            color = theme.C.amber, opa = theme.OPA.rail_active, radius = theme.R.md,
        })
        pcall(function() hl:set_hidden(true) end)
        rail_items[DESKTOP_KEY] = { hl = hl }
        if active_menu == nil then
            pcall(function() hl:set_hidden(false) end)
        end

        local isz = math.floor(ih * 0.36)
        -- desktop.png 尚未提供时按占位块绘制（与品牌块、应用项同一套兜底）
        theme.image(item, { icon = "desktop", placeholder = true, x = math.floor((iw - isz) / 2),
            y = math.floor(ih * 0.18), w = isz, h = isz })
        theme.label(item, {
            x = 2, y = math.floor(ih * 0.56), w = iw - 4, h = math.floor(ih * 0.38),
            text = "桌面", px_size = clamp(math.floor(screen_h * 0.018), 10, 13),
            color = theme.C.t2, align = airui.TEXT_ALIGN_CENTER,
        })
    else
        log.warn("idle_win", "左栏放不下「桌面」入口（内置应用过多），已跳过")
    end

end

--[[更新左栏一级菜单高亮

@param win string|nil 当前激活的内置应用 win 名；nil = 桌面态

桌面态不是「没有任何高亮」，而是高亮栏底的「桌面」项 —— 一级菜单里始终恰好有一项
处于选中态，用户才能一眼看出自己停在哪一层。
只切换选中底块的显隐，不重建 rail —— 重建会让整条左栏闪一下，
而且 rail 重建时机应由 idle 重新获得焦点（换肤）决定，不该由一次点击触发。]]
set_rail_active = function(win)
    active_menu = win
    local target = win or DESKTOP_KEY
    for k, ref in pairs(rail_items) do
        if ref.hl then
            pcall(function() ref.hl:set_hidden(k ~= target) end)
        end
    end
end

local function build_status_bar(parent)
    -- 方案A：宽屏时状态栏只落在右侧信息列内（与左侧视频同高起点），不再横跨整屏
    local bar_x = video_enabled and (content_x + pad + right_x) or (content_x + pad)
    local bar_w = video_enabled and right_w or (content_w - 2 * pad)
    local isz = math.floor(status_h * 0.62)
    local icon_y = math.floor((status_h - isz) / 2)
    local gap = clamp(math.floor(8 * density_scale_val), 6, 12)
    local fs = clamp(math.floor(screen_h * 0.0217), 13, 16)   -- 设计稿问候语/时间 13px
    local text_h = fs + 4
    local text_y = pad + math.floor((status_h - text_h) / 2)

    -- 左侧：问候语
    greet_label = theme.label(parent, {
        x = bar_x, y = text_y, w = math.floor(bar_w * 0.55), h = text_h,
        text = greeting_text(status_cache.time) .. "，合宙用户!",
        px_size = fs, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧从右往左：时间 / 电量 / 以太网 / 4G / WiFi
    local rx = bar_w

    local time_w = clamp(math.floor(50 * density_scale_val), 44, 64)
    rx = rx - time_w
    status_time_label = theme.label(parent, {
        x = bar_x + rx, y = text_y, w = time_w, h = text_h,
        text = status_cache.time, px_size = fs, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    if has_battery then
        local bw = math.floor(54 * density_scale_val)
        local bh = math.floor(status_h * 0.58)
        rx = rx - bw - gap
        battery_container = theme.box(parent, {
            x = bar_x + rx, y = pad + math.floor((status_h - bh) / 2), w = bw, h = bh,
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
            src = "/luadb/ethernet_link_down.png", x = bar_x + rx,
            y = pad + icon_y, w = isz, h = isz,
        })
    end
    if has_4g then
        rx = rx - isz - gap
        mobile_icon = theme.image(parent, {
            src = "/luadb/4Gxinhao6.png", x = bar_x + rx,
            y = pad + icon_y, w = isz, h = isz,
        })
    end
    if has_wifi then
        rx = rx - isz - gap
        wifi_icon = theme.image(parent, {
            src = "/luadb/wifixinhao0.png", x = bar_x + rx,
            y = pad + icon_y, w = isz, h = isz,
        })
    end
end

local function build_clock_card(parent)
    -- 方案A：时钟卡是右列第 2 块（状态栏下方），不再与视频同高起点
    local cx = video_enabled and (content_x + pad + right_x) or (content_x + pad)
    local cw = video_enabled and right_w or (content_w - 2 * pad)
    local y = video_enabled and (pad + status_h + col_gap) or (pad + status_h + pad)
    local card = theme.card(parent, {
        x = cx, y = y, w = cw, h = clock_h,
    })

    -- 内部度量：全部由卡片高度推导，保证「英雄字 + 日期」与右侧二维码都不被裁切
    local pad_in = clamp(math.floor(clock_h * 0.11), 10, 24)
    local hero = clamp(math.floor(clock_h * 0.50), 40, 64)
    local fs_date = clamp(math.floor(clock_h * 0.128), 13, 16)
    local date_h = fs_date + 4
    local gap = math.floor(4 * density_scale_val)
    local date_y = pad_in + hero + gap

    big_time_label = theme.label(card, {
        x = pad_in, y = pad_in, w = math.floor(cw * 0.52), h = hero + 2,
        text = status_cache.time, px_size = hero, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    date_label = theme.label(card, {
        x = pad_in, y = date_y, w = math.floor(cw * 0.52), h = date_h,
        text = status_cache.weekday .. " | " .. status_cache.date,
        px_size = fs_date, color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧资料中心（文字 + 二维码），整体在卡片内垂直居中
    local qs = clamp(math.floor(clock_h * 0.62), 40, 80)
    local qlabel_h = clamp(math.floor(clock_h * 0.11), 12, 16)
    local qlabel_w = qs + math.floor(16 * density_scale_val)
    local qr_gap = math.floor(3 * density_scale_val)
    local total_qr_h = qlabel_h + qr_gap + qs
    local qx = cw - pad_in - qs
    local qr_y_start = pad_in + math.floor((clock_h - pad_in * 2 - total_qr_h) / 2)
    if qr_y_start < pad_in then qr_y_start = pad_in end

    theme.label(card, {
        x = qx-10, y = qr_y_start, w = qlabel_w, h = qlabel_h,
        text = "资料中心", px_size = qlabel_h - 1, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.qrcode({
        parent = card, x = qx-3, y = qr_y_start + qlabel_h + qr_gap,
        size = qs,
        data = "https://docs.openluat.com/",
        dark_color = theme.C.qr_dark, light_color = theme.C.qr_light, quiet_zone = true,
    })
end

local function build_apps_card(parent)
    local ax = video_enabled and (content_x + pad + right_x) or (content_x + pad)
    local aw = video_enabled and right_w or (content_w - 2 * pad)
    apps_card = theme.card(parent, {
        x = ax, y = apps_y, w = aw, h = apps_h,
        clip = true,
    })

    -- 接住返回值：安装/卸载后靠它刷新计数（见 update_pager）
    apps_head_label = theme.section(apps_card, {
        x = apps_pad_y + 4, y = math.floor(apps_pad_y * 0.6),
        w = math.floor(aw * 0.45), h = apps_head_h,
        text = "已安装应用 | " .. tostring(#all_apps), px_size = clamp(math.floor(screen_h * 0.02), 12, 16),
        color = theme.C.t3,
    })

    -- 注意：这里不能按 "#all_apps == 0 就 return" 提前退出。
    -- 首次开机外部应用为 0，提前退出就不会创建分页器，之后装了应用也补不回来。
    -- 空列表下的隐藏交给 update_pager() 统一处理。

    -- 分页器（右上角）—— 缩小按钮宽度防重叠
    local pw = clamp(math.floor(36 * density_scale_val), 24, 40)
    local pager_gap = math.floor(4 * density_scale_val)
    local pager_y = math.floor(apps_pad_y * 0.4)
    local pager_x = aw - apps_pad_y

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
        text = "1/1", px_size = clamp(math.floor(screen_h * 0.018), 11, 14), color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    grid_container = theme.box(apps_card, {
        x = apps_pad_y, y = apps_head_h + apps_pad_y,
        w = aw - 2 * apps_pad_y, h = grid_rows * (tile_h + grid_gap),
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
            on_click = function() open_builtin(win) end,
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
    local wx = video_enabled and (content_x + pad + right_x) or (content_x + pad)
    local card_w = video_enabled and right_w or (content_w - 2 * pad)
    local card = theme.card(parent, {
        x = wx, y = weather_y, w = card_w, h = weather_h,
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
    local fs_info = clamp(math.floor(content_h * 0.26), 12, 18)             -- 地点|状况（设计稿 12px）
    local fs_fc = math.min(clamp(math.floor(content_h * 0.26), 12, 16), fs_info)  -- 预报（次级，设计稿 11~12px）
    local fs_temp = clamp(math.floor(content_h * 0.60), 20, 34)             -- 当前温度（英雄字，设计稿 30px）
    -- 必要时压缩温度字号，确保「温度 + 地点|状况」两行加间距不超出内容高度
    local max_temp_fs = content_h - fs_info - line_gap - 4
    if fs_temp > max_temp_fs then fs_temp = math.max(16, max_temp_fs) end

    local temp_h = fs_temp + 2
    local info_h = fs_info + 2
    local fc_h = fs_fc + 2

    -- ========== 左侧：天气图标 + 温度 + 地点|状况 ==========
    local icon_sz = clamp(math.floor(content_h * 0.85), 24, 40)
    local icon_x = pad_in
    local icon_y = pad_in + math.floor((content_h - icon_sz) / 2)

    -- 设计稿 .weather-icon：图标带琥珀半透明底块（图标资源缺失时色块也保留）
    theme.card(card, {
        x = icon_x, y = icon_y, w = icon_sz, h = icon_sz,
        radius = theme.R.sm, color = theme.C.amber, opa = 46, border_w = 0,
    })

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

-- ==================== 视频区域（方案A：左侧视频 + 右侧信息列） ====================

-- 视频控制：显示/隐藏控制栏
-- 旧版在播放时起 3 秒定时器把控制栏藏起来，用户看到的是「播放一会儿按钮就没了」；
-- 设计稿 .ctrl-bar 是常驻的，所以这里只做显隐，不再自动隐藏。
local function video_show_ctrl()
    if not video_ctrl_bar then return end
    video_ctrl_bar:set_hidden(false)
    video_ctrl_visible = true
end

local function video_hide_ctrl()
    if not video_ctrl_bar then return end
    video_ctrl_bar:set_hidden(true)
    video_ctrl_visible = false
end

-- 视频控制：停止并重建视频组件（切换文件或循环模式时用）
local function video_stop()
    if video_loop_timer then sys.timerStop(video_loop_timer); video_loop_timer = nil end
    audio_stop()
    if video_obj then
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
end

--- 判断素材用哪种容器解析：优先看魔数，其次看扩展名
--- @return "hzv" | "mjpg" | "mp4"
local function media_guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(4)
        f:close()
        if magic == "HZV1" then return "hzv" end
    end
    local ext = path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" then return "mp4" end
    end
    return "mjpg"
end

--- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
--- 音频框架没起来时既不响、也不会走帧，所以这里做一次幂等初始化。
--- 首次真 setup，之后只 RESUME；失败不阻断画面创建。
local function hzv_audio_ensure()
    if not exaudio then return false end
    if not (_G.project_config and _G.project_config.hw and _G.project_config.hw.audio) then
        return false
    end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end
    local ac = _G.project_config.hw.audio
    local ok = pcall(exaudio.setup, {
        model       = ac.model or "dac",
        pa_ctrl     = ac.pa_ctrl,
        pa_on_level = ac.pa_on_level or 0,
        dac_delay   = ac.dac_delay,
    })
    if ok then
        pcall(exaudio.vol, ac.play_vol or 100)
        _G.__hzv_audio_ready = true
        return true
    end
    log.warn("idle_win", "hzv: exaudio.setup 失败，音轨与播放时钟可能不可用")
    return false
end

--- 读媒体容器头拿回 (width, height)
--- HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
--- 其它  : 按 MJPG/JPEG 扫 SOF0/SOF2 标记
--- @return width, height 或 nil（调用方回退默认值）
local function media_read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)  -- HZV 头部 0x48 以内 / JPEG 的 SOF 标记一般在 512 字节内
    f:close()
    if not data or #data < 8 then return nil end

    -- HZV 容器：帧尺寸直接写在头里（Lua 下标从 1 起，0x44 → 69）
    if data:sub(1, 4) == "HZV1" then
        local hw = data:byte(69) + data:byte(70) * 256
        local hh = data:byte(71) + data:byte(72) * 256
        if hw > 0 and hh > 0 then return hw, hh end
        return nil
    end

    -- 扫描 SOI (FF D8) 之后的标记，找 SOF0 (FF C0)
    local i = 1
    while i <= #data - 1 do
        if data:byte(i) == 0xFF then
            local marker = data:byte(i + 1)
            if marker == 0xC0 or marker == 0xC2 then  -- SOF0 / SOF2
                if i + 9 <= #data then
                    local h = data:byte(i + 5) * 256 + data:byte(i + 6)
                    local w = data:byte(i + 7) * 256 + data:byte(i + 8)
                    return w, h
                end
                return nil
            end
            -- 跳过非 SOF 标记（读取段长度并跳过）
            if marker ~= 0xD8 and marker ~= 0xD9 and (marker < 0xD0 or marker > 0xD7) then
                if i + 3 <= #data then
                    local seg_len = data:byte(i + 2) * 256 + data:byte(i + 3)
                    i = i + 2 + seg_len
                else
                    break
                end
            else
                i = i + 2
            end
        else
            i = i + 1
        end
    end
    return nil
end

-- ==================== 配套音频（同名 MP3） ====================
local has_audio = exaudio and project_config and project_config.hw and project_config.hw.audio

--- 在同目录下搜索与 mjpg 同名的 .mp3 文件
local function find_audio_for_video(mjpg_path)
    if not has_audio then return nil end
    local dir = mjpg_path:match("^(.+/)") or "/"
    local base = mjpg_path:match("([^/]+)%.mjpg$") or mjpg_path:match("([^/]+)%.MJPG$")
    if not base then return nil end
    local mp3_path = dir .. base .. ".mp3"
    if io.exists(mp3_path) then return mp3_path end
    mp3_path = dir .. base .. ".MP3"
    if io.exists(mp3_path) then return mp3_path end
    return nil
end

local function audio_start(mp3_path)
    if not has_audio or not mp3_path then return end
    if not exaudio_inited then
        pcall(exaudio.pm, exaudio.RESUME)
        exaudio_inited = true
    end
    audio_stop()
    audio_obj = mp3_path
    local function play_audio_loop(path)
        local r = pcall(exaudio.play_start, {
            type = 0, content = path,
            cbfnc = function(event)
                if event == exaudio.PLAY_DONE then
                    if video_is_loop and video_is_playing and audio_obj then
                        play_audio_loop(path)
                    else
                        audio_playing = false
                    end
                end
            end
        })
        return r
    end
    audio_playing = play_audio_loop(mp3_path)
    log.info("idle_win", "audio start", mp3_path, "ok=", audio_playing)
end

function audio_stop()
    if not has_audio then return end
    if audio_obj then
        pcall(exaudio.play_stop, { type = 0 })
        audio_obj = nil
        audio_playing = false
    end
end

local function audio_toggle()
    if not has_audio or not audio_obj then return end
    if audio_playing then
        pcall(exaudio.play_stop, { type = 0 })
        audio_playing = false
    else
        audio_start(audio_obj)
    end
end

local function video_start_play(file_path)
    log.info("idle_win", "video_start_play", file_path)
    video_stop()

    video_current_file = file_path

    local video_card = _video_card_ref
    if not video_card then
        log.warn("idle_win", "video_start_play: no video card ref")
        return
    end

    -- 从容器头读取实际帧尺寸，widget 必须严格匹配否则 airui 报缩放错误
    local vw, vh = media_read_dimensions(file_path)
    if not vw or not vh then vw, vh = 480, 270 end  -- 兜底默认值
    if vh > video_frame_h then vh = video_frame_h end
    local vx_off = math.floor((video_w - vw) / 2)
    local vy_off = math.floor((video_frame_h - vh) / 2)

    -- 循环交回组件（loop 参数）。旧版是「每 3 秒 stop+play」手动重播，
    -- 会把正在解码的视频硬重启，画面就停在半路 —— 用户报的「播放卡住」。
    hzv_audio_ensure()

    local fmt = media_guess_format(file_path)
    local vcfg = {
        parent = video_card,
        x = vx_off, y = vy_off, w = vw, h = vh,
        src = file_path,
        format = fmt,
        decode_mode = "hw",
        loop = video_is_loop,
        auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 自带逐帧时长与 MP3 音轨，Lua 不填 interval
        vcfg.backend = "videoplayer"
    else
        -- 30fps，与能正常播的 welcome_win 开机动画保持一致；
        -- 调大等于慢放（每帧间隔变大），看着就像卡住
        vcfg.interval = 33
    end
    video_obj = airui.video(vcfg)

    video_is_playing = (video_obj ~= nil)
    if video_play_label then
        video_play_label:set_text(video_is_playing and "||" or ">")
    end
    if video_file_label then
        local name = file_path:match("([^/]+)$") or file_path
        video_file_label:set_text(name)
    end
    video_show_ctrl()

    -- 同名 MP3 配套播放：只有 MJPG 素材需要。HZV 的音轨已在容器内、由 videoplayer
    -- 统一驱动，而 find_audio_for_video 只认 .mjpg 后缀，对 .hzv 天然返回 nil。
    local mp3 = find_audio_for_video(file_path)
    if mp3 then audio_start(mp3) end

    log.info("idle_win", "video play", file_path, "ok=", video_obj ~= nil, "loop=", video_is_loop)
end

-- 视频控制：播放/暂停切换
local function video_toggle_play()
    if not video_obj then return end
    if video_is_playing then
        pcall(function() video_obj:pause() end)
        video_is_playing = false
        if video_play_label then video_play_label:set_text(">") end
        audio_toggle()
    else
        pcall(function() video_obj:play() end)
        video_is_playing = true
        if video_play_label then video_play_label:set_text("||") end
        audio_toggle()
        video_show_ctrl()
    end
end

-- 视频控制：重播
local function video_restart()
    if video_current_file then
        video_start_play(video_current_file)
    end
end

-- 视频控制：切换循环
-- loop 只在创建组件时生效，所以切完标志位重建一次组件
local function video_toggle_loop()
    video_is_loop = not video_is_loop
    if video_loop_label then
        video_loop_label:set_text(video_is_loop and "R" or "1")
    end
    if video_current_file and video_obj then
        video_start_play(video_current_file)
    end
end

-- 视频控制：简单文件选择（列出内置/SD/Flash 根目录的 .hzv/.mjpg/.mp4 文件）
local video_picker_overlay = nil
local video_picker_scroll = nil

local function video_close_picker()
    if video_picker_overlay then
        pcall(function() video_picker_overlay:destroy() end)
        video_picker_overlay = nil
    end
    video_picker_scroll = nil
end

local function video_render_picker(dir_path, scroll_container)
    if not scroll_container then return end
    local items = {}
    local ret, files = io.lsdir(dir_path, 200, 0)
    if ret and files then
        for _, f in ipairs(files) do
            if f.type == 1 then
                items[#items + 1] = { name = f.name, is_dir = true, path = dir_path .. f.name .. "/" }
            elseif f.type == 0 then
                local ext = f.name:match("%.([^%.]+)$")
                if ext then ext = ext:lower() end
                if ext == "hzv" or ext == "mjpg" or ext == "mp4" then
                    items[#items + 1] = { name = f.name, is_dir = false, path = dir_path .. f.name }
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)

    local row_h = math.floor(32 * density_scale_val)
    local px = math.floor(8 * density_scale_val)
    local y = 0
    for _, item in ipairs(items) do
        local row = theme.card(scroll_container, {
            x = px, y = y, w = right_w - 2 * px, h = row_h,
            radius = theme.R.sm, opa = 0,
            on_click = function()
                if item.is_dir then
                    video_close_picker()
                    -- 进入子目录：重建选择器
                    video_open_file_picker(item.path)
                else
                    video_close_picker()
                    video_start_play(item.path)
                end
            end,
        })
        local icon_c = item.is_dir and theme.C.amber or theme.C.cyan
        theme.label(row, {
            x = px, y = 0, w = math.floor(18 * density_scale_val), h = row_h,
            text = item.is_dir and ">" or ">", px_size = math.floor(13 * density_scale_val),
            color = icon_c, align = airui.TEXT_ALIGN_CENTER,
        })
        theme.label(row, {
            x = px + math.floor(20 * density_scale_val), y = 0,
            w = right_w - 2 * px - math.floor(24 * density_scale_val), h = row_h,
            text = item.name, px_size = math.floor(12 * density_scale_val),
            color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
        })
        y = y + row_h + math.floor(2 * density_scale_val)
    end
    if #items == 0 then
        theme.label(scroll_container, {
            x = 0, y = math.floor(20 * density_scale_val), w = right_w, h = row_h,
            text = "无视频文件", px_size = math.floor(12 * density_scale_val),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

function video_open_file_picker(start_path)
    video_close_picker()
    start_path = start_path or "/"

    local picker_w = math.min(math.floor(screen_w * 0.50), 460)
    local picker_h = math.floor(screen_h * 0.70)
    local pad_in = math.floor(12 * density_scale_val)

    -- 使用 airui.win 创建独立弹窗，不影响底层布局
    video_picker_overlay = airui.win({
        parent = airui.screen, title = "选择视频文件",
        w = picker_w, h = picker_h, close_btn = true, auto_center = true,
        style = {
            bg_color = theme.C.dialog, header_bg_color = theme.C.dialog,
            content_bg_color = theme.C.dialog,
            title_text_color = theme.C.t1, radius = theme.R.lg,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = math.floor(40 * density_scale_val), content_pad = 0,
        },
        on_close = function() video_picker_overlay = nil end,
    })

    -- 快捷跳转行
    local quick_h = math.floor(28 * density_scale_val)
    local quick_w = math.floor((picker_w - pad_in * 2 - math.floor(8 * density_scale_val)) / 3)
    local quick_gap = math.floor(4 * density_scale_val)
    local quick_items = {
        { text = "内置存储", path = "/" },
        { text = "SD卡", path = "/sd/" },
        { text = "Flash", path = "/little_flash/" },
    }
    for qi, q in ipairs(quick_items) do
        theme.ghost_button(video_picker_overlay, {
            x = pad_in + (qi - 1) * (quick_w + quick_gap), y = pad_in,
            w = quick_w, h = quick_h,
            text = q.text, size = theme.F.tiny, fg = theme.C.cyan,
            on_click = function()
                video_close_picker()
                video_open_file_picker(q.path)
            end,
        })
    end

    -- 文件列表滚动区域
    local list_y = pad_in + quick_h + pad_in
    video_picker_scroll = airui.container({
        parent = video_picker_overlay,
        x = 0, y = list_y, w = picker_w, h = picker_h - list_y - pad_in,
        color = theme.C.bg, color_opacity = 0, scrollable = true,
    })
    video_render_picker(start_path, video_picker_scroll)
end

-- 方案A：左列视频卡片（铺满内容区高度）+ 卡片底部常驻控制栏
local function build_video_area(parent)
    if not video_enabled then return end

    -- 资源落点随烧录方式而变（/luadb/ 或根目录），先挑实际存在的那个
    if not io.exists(video_current_file) then
        -- .hzv 优先（真机硬解）；素材还没换成 hzv 时回落同名 .mjpg，避免视频卡片空掉
        for _, p in ipairs({
            "/luadb/luatos_boot.hzv", "/luatos_boot.hzv",
            "/luadb/luatos_boot.mjpg", "/luatos_boot.mjpg",
        }) do
            if io.exists(p) then
                video_current_file = p
                break
            end
        end
    end

    -- 方案A：左列 = 视频卡片铺满内容区高度，控制栏叠在卡片底部（设计稿 .ctrl-bar）
    local vx = content_x + pad + video_x
    local vy = pad + video_y
    local ctrl_h = clamp(math.floor(screen_h * 0.060), 32, 44)   -- 设计稿 36

    -- 视频卡片（直接放 parent，不套 wrapper，避免 LVGL 渲染异常）
    local video_card = theme.card(parent, {
        x = vx, y = vy, w = video_w, h = video_h,
        color = theme.C.black, opa = 255, radius = theme.R.md, border_w = 0,
        --[[子组件按卡片圆角裁剪

        控制栏是贴底、等宽的方形子容器，它的两个直角会盖住卡片的圆角，
        卡片下方就冒出两个方角（用户报「播放器下面的按钮容器外部有两个白色的方角」）。
        打开 clip_corner 让控制栏被卡片圆角裁掉，等价于设计稿里父容器的 overflow:hidden。]]
        clip_corner = true,
        on_click = function() video_show_ctrl() end,   -- 控制栏被 X 收起后，点画面可再唤出
    })
    _video_card_ref = video_card

    -- 画面高度 = 卡片高度 - 控制栏高度（控制栏浮在卡片底部）
    video_frame_h = video_h - ctrl_h
    if video_frame_h < 60 then video_frame_h = 60 end

    -- 从容器头读取实际帧尺寸，widget 必须严格匹配否则 airui 报缩放错误
    local vw, vh = media_read_dimensions(video_current_file)
    if not vw or not vh then vw, vh = 480, 270 end  -- 兜底默认值
    if vh > video_frame_h then vh = video_frame_h end
    local vx_off = math.floor((video_w - vw) / 2)
    local vy_off = math.floor((video_frame_h - vh) / 2)

    -- 循环交给组件的 loop 参数。旧版是「每 3 秒 stop+play」手动重播，
    -- 会把正在解码的视频硬重启，画面停在半路（用户报的「播放卡住」）。
    hzv_audio_ensure()

    local fmt = media_guess_format(video_current_file)
    local vcfg = {
        parent = video_card,
        x = vx_off, y = vy_off, w = vw, h = vh,
        src = video_current_file,
        format = fmt,
        decode_mode = "hw",
        loop = video_is_loop,
        auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 容器自带逐帧时长与 MP3 音轨
        vcfg.backend = "videoplayer"
    else
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    end
    video_obj = airui.video(vcfg)
    video_is_playing = (video_obj ~= nil)

    -- 无视频：按设计稿显示空态（三角 + 文案，居中）
    if not video_is_playing then
        theme.label(video_card, {
            x = 0, y = math.floor(video_frame_h / 2) - math.floor(26 * density_scale_val),
            w = video_w, h = math.floor(34 * density_scale_val),
            text = ">", px_size = math.floor(32 * density_scale_val),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        theme.label(video_card, {
            x = 0, y = math.floor(video_frame_h / 2) + math.floor(10 * density_scale_val),
            w = video_w, h = math.floor(22 * density_scale_val),
            text = "点击选择视频文件", px_size = math.floor(13 * density_scale_val),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 控制栏（视频卡片底部，半透明深底）
    video_ctrl_bar = theme.card(video_card, {
        x = 0, y = video_h - ctrl_h, w = video_w, h = ctrl_h,
        color = theme.C.panel, opa = 235, radius = 0,
        border_w = 0,
    })

    local btn_size = clamp(math.floor(ctrl_h * 0.78), 24, 32)    -- 设计稿 28
    local btn_gap = clamp(math.floor(6 * density_scale_val), 4, 8)
    local btn_y = math.floor((ctrl_h - btn_size) / 2)
    local pad_in = math.floor(10 * density_scale_val)

    -- 按钮工厂：用 airui.button 替代 theme.card，获得真实按压反馈
    -- 从右往左摆位
    local rx = video_w - pad_in
    local function place_btn(text, tint, on_click)
        rx = rx - btn_size
        -- 颜色策略：主按钮（play）用实色突出，其余用 bg_opa 20% 半透明保持玻璃感
        local is_primary = (on_click == video_toggle_play)
        local btn = airui.button({
            parent = video_ctrl_bar, x = rx, y = btn_y, w = btn_size, h = btn_size,
            text = text, font_size = math.floor(btn_size * 0.5),
            style = { bg_color = tint, text_color = theme.C.t1, border_width = 0,
                      radius = theme.R.xs, bg_opa = is_primary and 255 or 51 },
            on_click = on_click,
        })
        return btn, btn
    end

    -- 文件名标签（左侧，宽度让开右侧 5 个按钮）
    local fname = video_current_file:match("([^/]+)$") or ""
    local btns_w = (btn_size + btn_gap) * 5 - btn_gap
    video_file_label = theme.label(video_ctrl_bar, {
        x = pad_in, y = btn_y, w = math.max(40, video_w - pad_in * 2 - btns_w - btn_gap),
        h = btn_size, text = fname, px_size = math.floor(11 * density_scale_val),
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 从右往左：关闭 / 选择文件 / 循环 / 重播 / 播放
    place_btn("X", theme.C.rose, function()
        log.info("idle_win", "video btn: hide ctrl")
        video_hide_ctrl()
    end)
    rx = rx - btn_gap
    place_btn("...", theme.C.cyan, function()
        log.info("idle_win", "video btn: open file picker")
        video_open_file_picker()
    end)
    rx = rx - btn_gap
    local _, loop_lbl = place_btn(video_is_loop and "R" or "1", theme.C.amber, video_toggle_loop)
    video_loop_label = loop_lbl
    rx = rx - btn_gap
    place_btn("|<", theme.C.cyan_light, function()
        log.info("idle_win", "video btn: restart", video_current_file, "obj=", video_obj ~= nil)
        video_restart()
    end)
    rx = rx - btn_gap - 5  -- 播放按钮向左移动 5 像素
    local _, play_lbl = place_btn(video_is_playing and "||" or ">", theme.C.green, video_toggle_play)
    video_play_label = play_lbl

    video_show_ctrl()
    log.info("idle_win", "video area built", video_w, "x", video_h, "frame", video_frame_h)
end

-- ==================== 窗口生命周期 ====================

local timer_handler = nil

local function on_create()
    log.info("idle_win", "on_create begin")
    calc_layout()
    -- 重建时 build_video_area 会自行起播，不需要 on_get_focus 再恢复一次
    video_resume_file = nil

    main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    build_rail(main_container)
    build_status_bar(main_container)
    build_clock_card(main_container)
    pcall(build_weather_card, main_container)  -- pcall 防止天气卡片报错阻断后续构建
    pcall(build_video_area, main_container)    -- 方案A：左侧视频区域

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
    -- 请求天气：天气数据可能先于本窗口到达（订阅晚于发布就会丢首帧），
    -- 用请求-应答让天气服务把当前数据立即回发一次
    sys.publish("WEATHER_REQUEST")
    sys.timerStart(check_duplicates, 1200)

    log.info("idle_win", string.format("桌面构建完成 %dx%d rail=%d cols=%d rows=%d apps=%d",
        screen_w, screen_h, rail_w, grid_cols, grid_rows, #all_apps))
end

local function on_destroy()
    log.info("idle_win", "on_destroy")
    if timer_handler then sys.timerStop(timer_handler); timer_handler = nil end
    stop_charge_anim()
    -- 停止视频控制栏定时器
    if video_ctrl_timer then sys.timerStop(video_ctrl_timer); video_ctrl_timer = nil end
    if video_loop_timer then sys.timerStop(video_loop_timer); video_loop_timer = nil end
    -- 停止并释放视频播放组件
    if video_obj then
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
    audio_stop()
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
    video_obj = nil
    _video_card_ref = nil
    video_ctrl_bar = nil
    video_play_label = nil
    video_loop_label = nil
    video_file_label = nil
    video_close_picker()
    app_cards = {}
    all_apps = {}
    -- 左栏随 main_container 一起被销毁，引用必须跟着清掉：
    -- 换肤重建的兜底定时器可能晚于 on_destroy 触发，悬空引用会去 destroy 已销毁的控件
    rail_container = nil
    if rail_rebuild_timer then sys.timerStop(rail_rebuild_timer); rail_rebuild_timer = nil end
    window_id = nil
end

--[[换肤要做两件事

1) 打脏标记：等桌面重新回到前台时整屏重建。
   换肤在设置页发起，此刻桌面在窗口栈下层，整屏重建会打乱焦点顺序。

2) 立即就地重建左栏。
   改造后左栏是**常驻可见**的 —— 上层页面只占右侧内容区，用户在主题页点一下
   就正盯着左栏看。只做 (1) 的话左栏要等用户回到桌面才会换色，当下看起来就是
   「主题改不动左侧内置应用区域」。所以这里不等焦点，直接重建 rail。

只重建 rail 而不是整屏：桌面右区此刻被上层页面完全遮住，重建它纯属浪费，
而且整屏重建会顺带重启视频解码（见 on_lose_focus）。]]
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()

local function rebuild_rail_now()
    rail_rebuild_timer = nil
    -- 桌面已销毁，或处于窄屏（本就没有左栏）时什么都不做
    if not main_container or not window_id or not use_rail then return end
    if rail_container then
        pcall(function() rail_container:destroy() end)
        rail_container = nil
    end
    -- rail_items 由 build_rail 内部重置，active_menu 的选中态也在其中恢复
    pcall(build_rail, main_container)
end

local function on_theme_changed()
    mark_theme_dirty()
    -- 延迟到本轮事件派发结束再动控件：换肤是在主题卡片的点击回调里发起的，
    -- 在回调栈上销毁容器不安全。40ms 远小于人眼可辨的延迟，观感上就是「立刻」。
    if not rail_rebuild_timer then
        rail_rebuild_timer = sys.timerStart(rebuild_rail_now, 40)
    end
end
sys.subscribe("UI_THEME_CHANGED", on_theme_changed)

local function on_get_focus()
    if take_theme_dirty() then
        -- on_destroy 会注销全部订阅与定时器并清空控件引用，on_create 重新建立，
        -- 二者成对调用即可完整重绘（桌面窗口本身不关闭，window_id 需保留）
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
        -- on_destroy 会把 window_id 置 nil，重建后必须重新登记宿主 id，
        -- 否则下一次切一级菜单时 close_children_of 拿不到 id、清场会静默失效
        theme.shell.host_id = window_id
    end
    -- 桌面重新获得焦点 = 压在它上面的窗口都已被关闭 → 清除左栏一级菜单高亮
    set_rail_active(nil)
    -- 失焦时释放掉的视频在这里恢复（音视频一起从头播，避免音画错位）
    if video_resume_file and not video_obj and video_is_playing then
        local f = video_resume_file
        video_resume_file = nil
        pcall(video_start_play, f)
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
    --[[失焦即释放视频解码资源

    桌面被内置应用页盖住之后，视频若继续播放会一直占着硬件解码器与帧缓冲
    （480x270 单帧约 253KB，双缓冲近 506KB —— 很可能是全应用最大的一笔单体分配）。
    AirUI 视频组件只认自己的 playing 状态、没有任何「被遮挡」判断，必须在这里显式处理。

    这里选择销毁而不是 pause()：exaudio 没有可靠的续播接口，只暂停画面而音乐继续会音画错位；
    整组销毁、回到桌面时按记录的文件重新起播（见 on_get_focus），音视频一起从头开始、观感一致。
    代价是回到桌面要重新解码起播，换来的是失焦期间不占解码资源。]]
    if video_obj then
        if video_current_file and video_is_playing then
            video_resume_file = video_current_file
        end
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
    audio_stop()
end

local function open_handler()
    window_id = exwin.open({
        -- 桌面是最底层的一级菜单宿主，显式声明为顶层窗口（owner = nil），
        -- 不随开窗瞬间的栈顶变化而归属于别的窗口
        owner = false,
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
    -- 暴露宿主 id：切一级菜单时 close_children_of 需要它来清场
    theme.shell.host_id = window_id
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
