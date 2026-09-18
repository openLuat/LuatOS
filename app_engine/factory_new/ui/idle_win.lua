--[[
@module  idle_win
@summary 桌面首页（TabOS 深色玻璃态）——状态栏 + 时钟卡 + 应用网格 + 底部 Dock
@version 2.3
@date    2026.09.18
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
订阅: VIDEO_FILE_CHANGED(path)                 → 全屏播放页里换了文件，同步「当前文件」
发布: REQUEST_STATUS_REFRESH / OPEN_xxx_WIN / OPEN_VIDEO_WIN / APP_STORE_UNINSTALL
      AUTOSTART_* / FOTA_*

=== 视觉说明 ===
采用 tablet-smart-home 设计语言：
  宽屏（≥560dp）左侧 104dp 玻璃导航栏，窄屏省略
  顶部状态栏 + 问候行 + 大时钟玻璃卡（右侧资料中心二维码）
  天气玻璃卡：左侧「天气图标 + 温度 + （地点|状况）单串」，右侧 3 天预报等宽三列
  中部应用网格玻璃卡（含分页器）+ 底部玻璃 Dock
  竖屏播放器布局（配置项 ui.show_video_area）：状态栏 → 时钟 → 播放器（画面 + 独立控制栏）→ 已安装应用 → Dock

=== 排版注意（改天气卡前必读）===
theme.label 内部有一行 `if fs < 16 then fs = 16 end`，而 density_scale 在
10.1" 1024x600 上算得 0.64 → 被 max(1.0, ...) 抬回 1.0，因此 theme.F.tiny/small/body
这三个令牌在本工程实机上全部退化为 16px（仅 h2=17 略大）。
=> 想要可靠的字号层级必须走 px_size；且行高 h 必须 >= 字号，否则字被裁切。
]]

local exnetif = require "exnetif"
local theme = require "ui_theme"
-- 播放器两块共用的底层：素材工具（帧尺寸口径 / 音轨初始化）与文件选择弹窗。
-- 全屏播放页（ui/video_win.lua）用的是同一套，改口径只改模块。
local video_picker = require "video_picker"
local video_util = require "video_util"

local window_id = nil
local main_container = nil
local apps_card = nil
--[[播放器区域（画面 + 控制栏 + 文件选择器）的全部状态与函数

为什么挂到一张表上：Lua 每个函数内「同时活跃」的局部变量上限是 200 个
（LUAI_MAXVARS），而主块本身就是一个函数 —— 顶层每多一个 local 就永久占一个名额，
本文件已经顶到 201 个、直接编译不过。播放器这一组是完整的功能子系统，收进一张
局部表只占 1 个名额，也让「哪些东西属于播放器」一眼可见。
字段沿用原先的后缀命名（去掉前面的前缀），例如：
  VP.ctrl_h / VP.frame_h / VP.current_file / VP.start_play / VP.open_picker
跨窗口调用请走本文件已有的导出接口，别在别的窗口里直接碰这张表。]]
local VP = {}
VP.obj = nil                    -- 视频播放组件（开机动画循环播放）
VP.is_playing = true            -- 播放状态
VP.is_loop = true               -- 循环状态
VP.ctrl_bar = nil               -- 控制栏容器
VP.ctrl_visible = true          -- 控制栏可见性
VP.ctrl_timer = nil             -- 控制栏自动隐藏定时器（已停用，仅保留清理，防旧定时器残留）
VP.play_label = nil             -- 播放/暂停按钮文字
VP.loop_label = nil             -- 循环按钮文字
VP.file_label = nil             -- 当前文件名标签
VP.current_file = "/luatos_boot.hzv"           -- 当前播放文件（res/luatos_boot.hzv 打包后在 /luadb/ 下）
VP.card_ref = nil             -- 视频卡片容器引用（供切换文件时使用）
VP.loop_timer = nil           -- MJPG 循环定时器（已停用：循环改由组件 loop 参数负责）
-- 配套音频（同名 MP3）的播放状态已收进 video_util：桌面播放器与全屏播放页
-- 共用一份，避免「两边同时出声」，也避免各自记一份状态后互相打架。
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

-- 方案A：左侧视频 + 右侧信息列（横屏）
local col_gap = 10             -- 左右栏 / 右列卡片间距（设计稿 10）
VP.w = 480                     -- 视频区域宽度
VP.h = 270                     -- 视频区域高度（按 luatos_boot 素材帧高留的布局基准）
VP.x = 0                       -- 视频卡左上角 X（绝对坐标，从内容区左缘算起）
VP.y = 0                       -- 视频卡左上角 Y（绝对坐标，从屏幕顶缘算起）
VP.frame_h = 0                 -- 视频画面高度（卡片高 - 控制栏高）
VP.ctrl_h = 36                 -- 视频控制栏高度（画面下方独立一行，不叠画面；calc_layout 按密度重算）
local right_x = 0              -- 右侧信息列起始 X
local right_w = 0              -- 右侧信息列宽度
VP.enabled = false             -- 是否启用横屏双列布局（左视频 + 右信息列）

--[[方案B：竖屏播放器布局

纵向堆叠：状态栏 → 时钟 → 播放器（画面 + 独立控制栏）→ 已安装应用 → 底部 Dock。
**该布局不带天气卡**：天气卡那点高度让给了播放器的控制栏。
控制栏必须独占一行、不能压在画面上 —— 硬解视频是独立图层，压在它底下的控件在真机上
会被画面盖住（用户报的「视频播放缺少控制按钮」）。
与方案A互斥，由配置项 ui.show_video_area 显式打开（原因见下方开关注释）。]]
VP.portrait = false

--[[播放器卡基准高度 = luatos_boot.hzv 的原生帧高（480×320）

airui 播放器控件**不支持缩放**：请求尺寸与素材帧尺寸不一致时，控件会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c:
 "scaling is not supported yet ... force reset widget size"）。
所以布局基准必须按素材原生高度留；卡片比素材矮不会「缩小画面」，只会把画面上下缘裁掉。]]
VP.BASE_H = 320

--[[竖屏播放器布局开关（配置项 ui.show_video_area）

横屏双列布局按屏幕尺寸自动启用；竖屏上下堆叠会显著压缩已安装应用区域，
属于机型级取舍，必须由配置显式打开 —— 不能让所有竖屏机型默认继承。]]
local cfg_show_video_area = _G.project_config and _G.project_config.ui
    and _G.project_config.ui.show_video_area

local clock_y = 0              -- 时钟卡 Y 坐标（VP.enabled 时与 VP.y 对齐）

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
VP.resume_file = nil

-- ==================== 布局计算 ====================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[网格几何（由可用宽度驱动）

竖屏播放器布局要在纵向分支里先算出「已安装应用卡至少要多高」，才能把上面剩下的
空间全部让给播放器，所以这段必须能提前独立调用，不能只写在 calc_layout 末尾。]]
local function calc_grid_metrics(gw)
    local inner_w = gw - 2 * apps_pad_y
    tile_icon = clamp(math.floor(screen_h * 0.060 * density_scale_val), 26, 48)   -- 设计稿 36
    --[[瓦片内容高度：图标 y=dp(6) + 图标 + 文字 y 偏移 dp(4) + 文字高 dp(18) = dp(28) + 图标，
    而容器还要减掉上下各 1px 描边 —— 原来的 dp(30) 让内容**正好顶到容器边缘**（余量 0），
    真机上再有一两个像素的取整/行高差，LVGL 就会给瓦片画出滚动条
    （用户报的「已安装应用里挤出滑块」）。这里把余量提到 dp(34)，文字下方固定留 4px。]]
    tile_h = tile_icon + math.floor(34 * density_scale_val)
    apps_head_h = clamp(math.floor(screen_h * 0.045), 24, 30)
    grid_gap = clamp(math.floor(screen_w * 0.010), 6, 12)

    local min_tile_w = math.floor(math.max(72, tile_icon * 2.1))
    grid_cols = clamp(math.floor((inner_w + grid_gap) / (min_tile_w + grid_gap)), 2, 6)
    tile_w = math.floor((inner_w - (grid_cols - 1) * grid_gap) / grid_cols)
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

    -- 播放器控制栏高度（两种布局共用；竖屏时它独占画面下方的一行，不压画面）
    VP.ctrl_h = clamp(math.floor(sh * 0.060), 32, 44)

    -- 方案A：宽屏（≥900dp）启用左侧视频 + 右侧信息列布局
    VP.enabled = (sw >= 900) and (sh >= 400)
    -- 方案B：竖屏播放器布局（与 A 互斥，由配置 ui.show_video_area 打开）
    VP.portrait = (not VP.enabled) and cfg_show_video_area and (sh > sw) and (sh >= 700)

    if VP.enabled then
        --[[ 方案A（设计稿 1024x600）：
             左列 = 视频 480 x 全高（576）；右列 406，从上到下：
             状态栏 36 -> 时钟 110 -> 天气 68 -> 应用网格（剩余高度）。
             左右栏间距 10，内容区四周 padding 12。]]
        local inner_w = content_w - 2 * pad

        -- 左列：视频铺满内容区高度，顶部与右列状态栏齐平
        -- 坐标改存绝对值（此前是「相对 pad 的偏移」，由 build_video_area 再加 pad）
        VP.x = pad
        VP.y = pad
        VP.w = clamp(math.floor(inner_w * 0.535), 320, math.floor(inner_w * 0.60))
        VP.h = sh - 2 * pad

        -- 右列
        right_x = VP.w + col_gap
        right_w = inner_w - VP.w - col_gap
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
        apps_h = sh - ry - pad
        if apps_h < 84 then apps_h = 84 end
    else
        -- 原始布局（窄屏 / 竖屏）
        clock_h = compact and clamp(math.floor(sh * 0.22), 50, 66)
            or clamp(math.floor(sh * 0.26), 110, 150)
        weather_h = compact and 0 or clamp(math.floor(sh * 0.125), 58, 78)
        -- 竖屏播放器布局不带天气卡：这块高度让给播放器的独立控制栏（见下方方案B）
        if VP.portrait then weather_h = 0 end

        local y = pad + status_h + pad
        y = y + clock_h + pad
        weather_y = y
        -- weather_h = 0（紧凑屏或竖屏播放器布局）时不要再占一格「卡片 + 间距」，
        -- 否则时钟与下面那张卡之间会平白多出 pad —— 竖屏播放器布局那 10px 要留给应用卡。
        if weather_h > 0 then y = y + weather_h + pad end
        apps_y = y
        if use_rail then
            apps_h = sh - y - pad
        else
            apps_h = sh - y - dock_h - pad
        end
        if apps_h < 84 then apps_h = 84 end

        --[[方案B（竖屏）：时钟下方插入通栏播放器（画面 + 独立控制栏）

        纵向预算（480×854 实测，density 1.05）：
        状态栏 36 + 时钟 150 + 播放器 364（画面 320 + 控制栏 44）+ 应用卡 158 + Dock 96。
        播放器与应用卡各拿刚需（应用卡刚需 = 表头 30 + 内边距 24 + 1 行 89 + 分页器余量 4 = 147），
        **剩下的纵向空间全部给 Dock（内置应用栏）** —— 以前反过来：应用卡当「剩余空间池」，
        Dock 被通用公式的 clamp 卡死在 72，于是应用卡白留 40+ px、Dock 又偏矮。
        行数由 apps_h 反推，屏幕更高会自动多一行（2 行 ≈ 240 高）。]]
        if VP.portrait then
            calc_grid_metrics(content_w - 2 * pad)

            --[[高度预算

            player_h     = 画面原生高 + 控制栏高：播放器卡的理想高度（再多也不能超，否则
                           画面与控制栏之间会露出黑边）
            apps_need_h  = 表头 + 上下内边距 + 分页器余量 + 1 行（含行间距）：应用卡舒适高度
            apps_floor_h = 去掉行间距那 6px 的下限：实际渲染 1 行只要这么多，
                           播放器不够高时可以借到这里]]
            local player_h = VP.BASE_H + VP.ctrl_h
            local apps_need_h  = apps_head_h + apps_pad_y * 2 + 4 + (tile_h + grid_gap)
            local apps_floor_h = apps_need_h - grid_gap

            local video_top = apps_y            -- 时钟卡下方（该布局没有天气卡）

            --[[Dock（内置应用栏）反向驱动

            刚需先摆好：播放器拿 player_h、应用卡拿 apps_need_h，中间各留一个 pad。
            由此推出来的「Dock 上沿」以上的部分就是 Dock 能用的全部高度，再夹进
            [dock_base, dock_max]：
              · 下限 = 通用公式算出的值 —— 别的竖屏机型只会更松，不会因这次改动变挤
              · 上限 = 96 —— 再高就只是个空横条（icon_size 到 42 已封顶，不会再变大）]]
            local dock_base = dock_h
            local dock_top = video_top + player_h + pad + apps_need_h + pad
            dock_h = (sh - pad) - dock_top
            local dock_max = clamp(math.floor(sh * 0.115), 64, 96)
            if dock_max < dock_base then dock_max = dock_base end
            if dock_h > dock_max then dock_h = dock_max end
            if dock_h < dock_base then dock_h = dock_base end

            local bottom = sh - dock_h - pad    -- 应用卡下沿 = Dock 上沿
            local room = bottom - video_top - pad   -- 播放器 + 应用卡 能用的总高（已扣中间间距）

            -- 应用卡先拿舒适高度，剩下的给播放器（播放器吃完 player_h 就不再要）
            VP.h = room - apps_need_h
            if VP.h > player_h then VP.h = player_h end

            -- 播放器不够理想高度时，从应用卡的舒适余量里借，最多借到 1 行下限
            if VP.h < player_h then
                local spare = room - apps_floor_h
                if spare > VP.h then
                    VP.h = player_h < spare and player_h or spare
                end
            end
            -- 极端小屏兜底：宁可裁掉一些画面，也别让按钮消失
            if VP.h < VP.ctrl_h + 96 then VP.h = VP.ctrl_h + 96 end

            VP.w = content_w                 -- 通栏：素材原生宽 480，两边留 pad 会各裁掉 10px
            VP.x = 0
            VP.y = video_top

            apps_y = video_top + VP.h + pad
            apps_h = bottom - apps_y
            if apps_h < apps_floor_h then apps_h = apps_floor_h end
        end
    end

    -- 网格参数（宽度驱动的部分统一走 calc_grid_metrics，竖屏分支里已提前算过一次）
    -- 注意：calc_grid_metrics 内部会再减掉左右内边距，这里要传「卡片宽度」。
    -- 以前多减了一次 2*apps_pad_y，瓦片行比卡片窄 24px、右侧白留一条（老 bug）。
    local grid_w = VP.enabled and right_w or (content_w - 2 * pad)
    calc_grid_metrics(grid_w)

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

    local gw = VP.enabled and right_w or (content_w - 2 * pad)
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
    local bar_x = VP.enabled and (content_x + pad + right_x) or (content_x + pad)
    local bar_w = VP.enabled and right_w or (content_w - 2 * pad)
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
    local cx = VP.enabled and (content_x + pad + right_x) or (content_x + pad)
    local cw = VP.enabled and right_w or (content_w - 2 * pad)
    local y = VP.enabled and (pad + status_h + col_gap) or (pad + status_h + pad)
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
    local ax = VP.enabled and (content_x + pad + right_x) or (content_x + pad)
    local aw = VP.enabled and right_w or (content_w - 2 * pad)
    apps_card = theme.card(parent, {
        x = ax, y = apps_y, w = aw, h = apps_h,
        -- 子元素按卡片圆角裁剪（airui.container 没有 clip 参数，以前写 clip=true 是无效的）
        clip_corner = true,
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

    --[[Dock 瓦片几何

    theme.tile 的内容高 = 图标 y 偏移 dp(6) + 图标 + 文字 y 偏移 dp(4) + 文字高 dp(18)
    = 图标 + dp(28)，容器还要再减掉上下各 1px 描边。原来写死 icon_size + 26 —— 连 dp(28)
    都不到，内容比容器高 3px，而 LVGL 容器默认 scrollbar_mode = AUTO，于是 Dock 里每个
    图标下面都挂一条滑块（用户报的「内置应用挤出了滑块」）。这里按网格瓦片同样的口径留 dp(34)；
    Dock 不够高时先缩图标（下限 28），保证「内容 + 描边」放得下、瓦片绝不超出卡片。
    （Dock 自身矮于 60 的 tiny 屏 —— 320×480 / 480×272 / 800×480 这一档 —— 图标已到下限，
    文字区仍会顶满瓦片；那是 Dock 高度公式本身偏矮，不属于本次改动范围。）]]
    local label_reserve = math.floor(6 * density_scale_val + 0.5) + math.floor(4 * density_scale_val + 0.5) + math.floor(18 * density_scale_val + 0.5)
    local icon_fit = dock_h - 2 - label_reserve - 2      -- 上下各 1px 描边 + 2px 余量
    if icon_size > icon_fit and icon_fit >= 28 then icon_size = icon_fit end

    local dock_tile_h = icon_size + math.floor(34 * density_scale_val)
    local dock_inner_h = math.max(dock_h - 2, icon_size)
    if dock_tile_h > dock_inner_h then dock_tile_h = dock_inner_h end

    for i, it in ipairs(items) do
        local win = it.win
        theme.tile(dock, {
            x = sx + (i - 1) * iw, y = math.floor((dock_h - dock_tile_h) / 2),
            w = iw, h = dock_tile_h,
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
    local wx = VP.enabled and (content_x + pad + right_x) or (content_x + pad)
    local card_w = VP.enabled and right_w or (content_w - 2 * pad)
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
function VP.show_ctrl()
    if not VP.ctrl_bar then return end
    VP.ctrl_bar:set_hidden(false)
    VP.ctrl_visible = true
end

--[[隐藏控制栏

原本挂在控制栏最右侧的 X 按钮上。那个按钮已改成「进入全屏播放」（见 build_video_area），
所以现在没有入口会调到这里 —— 保留函数是为了让「点画面唤出控制栏」那条路径仍有
配对的显隐状态（show_ctrl / hide_ctrl 是同一套状态的两个方向），
删掉反而容易让后来者以为控制栏本来就不可隐藏。]]
function VP.hide_ctrl()
    if not VP.ctrl_bar then return end
    VP.ctrl_bar:set_hidden(true)
    VP.ctrl_visible = false
end

-- 视频控制：停止并重建视频组件（切换文件或循环模式时用）
function VP.stop()
    if VP.loop_timer then sys.timerStop(VP.loop_timer); VP.loop_timer = nil end
    video_util.audio_stop()
    if VP.obj then
        pcall(function() VP.obj:stop() end)
        pcall(function() VP.obj:destroy() end)
        VP.obj = nil
    end
end

--[[媒体素材工具已下沉到 ui/video_util.lua

这份口径（容器魔数嗅探 / 帧尺寸读取 / HZV 音轨初始化）桌面播放器与全屏播放页都要用，
而 airui 播放器**不支持缩放** —— 帧尺寸读错不会「拉伸画面」，只会让控件溢出容器、
把画面裁掉一块。同一份口径只能有一处实现，否则两个页面的裁切行为会不一致。

配套音频（同名 MP3）也跟着下沉了：播放状态跨页面共用一份，避免两边同时出声。]]

--- 读素材帧尺寸；读不到时按布局形态回退
--- 竖屏播放器布局用 luatos_boot.hzv 的原生尺寸（480×320），横屏沿用旧默认（480×270）。
--- 回退值必须与布局基准一致：给错不会「拉伸画面」，只会让控件溢出卡片、把画面切掉一块。
local function media_frame_size(path)
    return video_util.frame_size(path, 480, VP.portrait and VP.BASE_H or 270)
end

function VP.start_play(file_path)
    log.info("idle_win", "video_start_play", file_path)
    VP.stop()

    VP.current_file = file_path

    local video_card = VP.card_ref
    if not video_card then
        log.warn("idle_win", "video_start_play: no video card ref")
        return
    end

    -- 从容器头读取实际帧尺寸，widget 必须严格匹配否则 airui 报缩放错误
    local vw, vh = media_frame_size(file_path)
    if vh > VP.frame_h then vh = VP.frame_h end
    local vx_off = math.floor((VP.w - vw) / 2)
    local vy_off = math.floor((VP.frame_h - vh) / 2)

    -- 循环交回组件（loop 参数）。旧版是「每 3 秒 stop+play」手动重播，
    -- 会把正在解码的视频硬重启，画面就停在半路 —— 用户报的「播放卡住」。
    video_util.audio_ensure()

    local fmt = video_util.guess_format(file_path)
    local vcfg = {
        parent = video_card,
        x = vx_off, y = vy_off, w = vw, h = vh,
        src = file_path,
        format = fmt,
        decode_mode = "hw",
        loop = VP.is_loop,
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
    VP.obj = airui.video(vcfg)

    VP.is_playing = (VP.obj ~= nil)
    if VP.play_label then
        VP.play_label:set_text(VP.is_playing and "||" or ">")
    end
    if VP.file_label then
        local name = file_path:match("([^/]+)$") or file_path
        VP.file_label:set_text(name)
    end
    VP.show_ctrl()

    -- 同名 MP3 配套播放：只有 MJPG 素材需要。HZV 的音轨已在容器内、由 videoplayer
    -- 统一驱动，而 find_companion_mp3 只认 .mjpg 后缀，对 .hzv 天然返回 nil。
    local mp3 = video_util.find_companion_mp3(file_path)
    if mp3 then
        video_util.audio_play(mp3, function() return VP.is_loop and VP.is_playing end)
    end

    log.info("idle_win", "video play", file_path, "ok=", VP.obj ~= nil, "loop=", VP.is_loop)
end

-- 视频控制：播放/暂停切换
function VP.toggle_play()
    if not VP.obj then return end
    if VP.is_playing then
        pcall(function() VP.obj:pause() end)
        VP.is_playing = false
        if VP.play_label then VP.play_label:set_text(">") end
        video_util.audio_toggle(function() return VP.is_loop and VP.is_playing end)
    else
        pcall(function() VP.obj:play() end)
        VP.is_playing = true
        if VP.play_label then VP.play_label:set_text("||") end
        video_util.audio_toggle(function() return VP.is_loop and VP.is_playing end)
        VP.show_ctrl()
    end
end

-- 视频控制：重播
function VP.restart()
    if VP.current_file then
        VP.start_play(VP.current_file)
    end
end

-- 视频控制：切换循环
-- loop 只在创建组件时生效，所以切完标志位重建一次组件
function VP.toggle_loop()
    VP.is_loop = not VP.is_loop
    if VP.loop_label then
        VP.loop_label:set_text(VP.is_loop and "R" or "1")
    end
    if VP.current_file and VP.obj then
        VP.start_play(VP.current_file)
    end
end

-- ==================== 文件选择器 / 全屏入口 ====================

--[[弹窗本体已下沉到 ui/video_picker.lua

桌面播放器与全屏播放页（ui/video_win.lua）共用同一套弹窗：存储设备快捷行（当前设备
点亮）、返回上一级、文件列表。复制两份意味着修一个 bug 要改两遍。
这里只保留「选中之后怎么办」以及桌面特有的两个动作：换文件、进全屏。]]

--- 打开文件选择器（默认从当前文件所在目录开始，省得每次从根目录点进去）
--- @param string|nil start_path 指定起始目录；不传则取当前文件所在目录
function VP.open_picker(start_path)
    local start = start_path
    if not start then
        start = (VP.current_file and VP.current_file:match("^(.+/)")) or "/"
    end
    video_picker.open({
        start_path = start,
        sw = screen_w, sh = screen_h,
        on_pick = function(path) VP.start_play(path) end,
    })
end

--- 关闭文件选择器（窗口销毁时兜底：弹窗可能还开着）
function VP.close_picker()
    video_picker.close()
end

--- 进入全屏播放页
--- 把当前文件带过去，全屏页从同一个素材接着播；退出后桌面按 VIDEO_FILE_CHANGED 同步
function VP.open_fullscreen()
    log.info("idle_win", "video btn: fullscreen", VP.current_file)
    sys.publish("OPEN_VIDEO_WIN", VP.current_file)
end

--[[全屏播放页里换了文件 → 同步「当前文件」

桌面此刻已失焦（on_lose_focus 已经把自己的播放器停掉并销毁了），所以这里只更新记录、
不起播；等退出全屏、桌面重新拿到焦点时，由 on_get_focus 按 resume_file 起播。

把选择结果提前记下来（而不是等退出时再补一次），是为了避免「先按旧文件起了播、
再销毁重建一次」的二次解码 —— BK72xx 的硬解链路是单实例资源，白重启一次代价不小。]]
local function on_video_file_changed(path)
    if type(path) ~= "string" or path == "" then return end
    if VP.current_file == path then return end
    VP.current_file = path
    VP.resume_file = path
    -- 桌面在前台时（理论上不会走到这里，因为只有全屏页会发这条消息）立即切过去
    if VP.obj then VP.start_play(path) end
end

-- 方案A：左列视频卡片（铺满内容区高度）+ 卡片底部常驻控制栏
local function build_video_area(parent)
    if not VP.enabled and not VP.portrait then return end

    -- 资源落点随烧录方式而变（/luadb/ 或根目录），先挑实际存在的那个
    if not io.exists(VP.current_file) then
        -- .hzv 优先（真机硬解）；素材还没换成 hzv 时回落同名 .mjpg，避免视频卡片空掉
        for _, p in ipairs({
            "/luadb/luatos_boot.hzv", "/luatos_boot.hzv",
            "/luadb/luatos_boot.mjpg", "/luatos_boot.mjpg",
        }) do
            if io.exists(p) then
                VP.current_file = p
                break
            end
        end
    end

    -- 方案A（横屏）：左列 = 视频卡片铺满内容区高度，控制栏占卡片底部一行（设计稿 .ctrl-bar）
    -- 方案B（竖屏）：时钟下方的通栏播放器，控制栏同样独占底部一行，不压画面
    -- VP.x / VP.y 是绝对坐标，不要再叠 pad（横屏分支已把 pad 算进 VP.x/VP.y）
    local vx = content_x + VP.x
    local vy = VP.y
    local ctrl_h = VP.ctrl_h      -- calc_layout 按屏幕高算好：1024x600 横屏 36，480x854 竖屏 44
    if ctrl_h < 28 then ctrl_h = 28 end

    -- 视频卡片（直接放 parent，不套 wrapper，避免 LVGL 渲染异常）
    local video_card = theme.card(parent, {
        x = vx, y = vy, w = VP.w, h = VP.h,
        color = theme.C.black, opa = 255, radius = theme.R.md, border_w = 0,
        --[[子组件按卡片圆角裁剪

        控制栏是贴底、等宽的方形子容器，它的两个直角会盖住卡片的圆角，
        卡片下方就冒出两个方角（用户报「播放器下面的按钮容器外部有两个白色的方角」）。
        打开 clip_corner 让控制栏被卡片圆角裁掉，等价于设计稿里父容器的 overflow:hidden。]]
        clip_corner = true,
        on_click = function() VP.show_ctrl() end,   -- 控制栏被 X 收起后，点画面可再唤出
    })
    VP.card_ref = video_card

    --[[画面高度：两种布局都是「卡片高 - 控制栏高」，控制栏独占卡片底部一行、不压画面。
    竖屏下卡片 = 画面原生 320 + 控制栏，画面正好占满上半部分、控制栏紧贴其下。
    控制栏绝不能叠在画面上：硬解视频是独立图层，压在画面上的控件真机上看不见。]]
    VP.frame_h = VP.h - ctrl_h
    if VP.frame_h < 60 then VP.frame_h = 60 end

    -- 从容器头读取实际帧尺寸，widget 必须严格匹配否则 airui 报缩放错误
    local vw, vh = media_frame_size(VP.current_file)
    if vh > VP.frame_h then vh = VP.frame_h end
    local vx_off = math.floor((VP.w - vw) / 2)
    local vy_off = math.floor((VP.frame_h - vh) / 2)

    -- 循环交给组件的 loop 参数。旧版是「每 3 秒 stop+play」手动重播，
    -- 会把正在解码的视频硬重启，画面停在半路（用户报的「播放卡住」）。
    video_util.audio_ensure()

    local fmt = video_util.guess_format(VP.current_file)
    local vcfg = {
        parent = video_card,
        x = vx_off, y = vy_off, w = vw, h = vh,
        src = VP.current_file,
        format = fmt,
        decode_mode = "hw",
        loop = VP.is_loop,
        auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 容器自带逐帧时长与 MP3 音轨
        vcfg.backend = "videoplayer"
    else
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    end
    VP.obj = airui.video(vcfg)
    VP.is_playing = (VP.obj ~= nil)

    -- 无视频：按设计稿显示空态（三角 + 文案，居中）
    if not VP.is_playing then
        theme.label(video_card, {
            x = 0, y = math.floor(VP.frame_h / 2) - math.floor(26 * density_scale_val),
            w = VP.w, h = math.floor(34 * density_scale_val),
            text = ">", px_size = math.floor(32 * density_scale_val),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        theme.label(video_card, {
            x = 0, y = math.floor(VP.frame_h / 2) + math.floor(10 * density_scale_val),
            w = VP.w, h = math.floor(22 * density_scale_val),
            text = "点击选择视频文件", px_size = math.floor(13 * density_scale_val),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 控制栏（视频卡片底部，半透明深底）
    VP.ctrl_bar = theme.card(video_card, {
        x = 0, y = VP.frame_h, w = VP.w, h = ctrl_h,
        -- 控制栏与画面不重叠，用接近实色的面板底，按钮看得清（横竖屏同款）
        color = theme.C.panel, opa = 235, radius = 0,
        border_w = 0,
    })

    local btn_size = clamp(math.floor(ctrl_h * 0.78), 24, 32)    -- 设计稿 28
    local btn_gap = clamp(math.floor(6 * density_scale_val), 4, 8)
    local btn_y = math.floor((ctrl_h - btn_size) / 2)
    local pad_in = math.floor(10 * density_scale_val)

    -- 按钮工厂：用 airui.button 替代 theme.card，获得真实按压反馈
    -- 从右往左摆位
    local rx = VP.w - pad_in
    local function place_btn(text, tint, on_click)
        rx = rx - btn_size
        -- 颜色策略：主按钮（play）用实色突出，其余用 bg_opa 20% 半透明保持玻璃感
        local is_primary = (on_click == VP.toggle_play)
        local btn = airui.button({
            parent = VP.ctrl_bar, x = rx, y = btn_y, w = btn_size, h = btn_size,
            text = text, font_size = math.floor(btn_size * 0.5),
            style = { bg_color = tint, text_color = theme.C.t1, border_width = 0,
                      radius = theme.R.xs, bg_opa = is_primary and 255 or 51 },
            on_click = on_click,
        })
        return btn, btn
    end

    -- 文件名标签（左侧，宽度让开右侧 4 个按钮）
    local fname = VP.current_file:match("([^/]+)$") or ""
    local btns_w = (btn_size + btn_gap) * 4 - btn_gap
    VP.file_label = theme.label(VP.ctrl_bar, {
        x = pad_in, y = btn_y, w = math.max(40, VP.w - pad_in * 2 - btns_w - btn_gap),
        h = btn_size, text = fname, px_size = math.floor(11 * density_scale_val),
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    --[[从右往左：全屏 / 选择文件 / 循环 / 重播 / 播放

    最右那个按钮原来是把控制栏收起来的 X。现在改成「进入全屏播放」：
    收控制栏这个动作本身就是个死胡同（收掉之后唯一的入口是再点一下画面，
    而画面没有提示），换成全屏的收益明显更大。按钮文字用 ASCII 的 "[]"
    —— 工程里所有按钮都只用 ASCII（<  >  ||  R  1  ...），字形资源缺失时才不会空白。]]
    place_btn("[]", theme.C.violet, VP.open_fullscreen)
    rx = rx - btn_gap
    place_btn("...", theme.C.cyan, function()
        log.info("idle_win", "video btn: open file picker")
        VP.open_picker()
    end)
    rx = rx - btn_gap
    local _, loop_lbl = place_btn(VP.is_loop and "R" or "1", theme.C.amber, VP.toggle_loop)
    VP.loop_label = loop_lbl
    rx = rx - btn_gap
    place_btn("|<", theme.C.cyan_light, function()
        log.info("idle_win", "video btn: restart", VP.current_file, "obj=", VP.obj ~= nil)
        VP.restart()
    end)
    rx = rx - btn_gap - 5  -- 播放按钮向左移动 5 像素
    local _, play_lbl = place_btn(VP.is_playing and "||" or ">", theme.C.green, VP.toggle_play)
    VP.play_label = play_lbl

    VP.show_ctrl()
    log.info("idle_win", "video area built", VP.w, "x", VP.h, "frame", VP.frame_h)
end

-- ==================== 窗口生命周期 ====================

local timer_handler = nil

local function on_create()
    log.info("idle_win", "on_create begin")
    calc_layout()
    -- 重建时 build_video_area 会自行起播，不需要 on_get_focus 再恢复一次
    VP.resume_file = nil

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
    sys.subscribe("VIDEO_FILE_CHANGED", on_video_file_changed)
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

    log.info("idle_win", string.format("桌面构建完成 %dx%d rail=%d cols=%d rows=%d apps=%d video=%s",
        screen_w, screen_h, rail_w, grid_cols, grid_rows, #all_apps,
        VP.enabled and "two-col" or (VP.portrait and "portrait" or "off")))
end

local function on_destroy()
    log.info("idle_win", "on_destroy")
    if timer_handler then sys.timerStop(timer_handler); timer_handler = nil end
    stop_charge_anim()
    -- 停止视频控制栏定时器
    if VP.ctrl_timer then sys.timerStop(VP.ctrl_timer); VP.ctrl_timer = nil end
    if VP.loop_timer then sys.timerStop(VP.loop_timer); VP.loop_timer = nil end
    -- 停止并释放视频播放组件
    if VP.obj then
        pcall(function() VP.obj:stop() end)
        pcall(function() VP.obj:destroy() end)
        VP.obj = nil
    end
    video_util.audio_stop()
    sys.unsubscribe("STATUS_TIME_UPDATED", update_time_date)
    if has_4g then sys.unsubscribe("STATUS_SIGNAL_UPDATED", update_mobile_icon) end
    if has_wifi then sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", update_wifi_icon) end
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    sys.unsubscribe("WEATHER_UPDATED", on_weather_updated)
    if has_battery then sys.unsubscribe("BATTERY_STATUS", on_status_battery) end
    sys.unsubscribe("AUTOSTART_SETTINGS_VALUE", on_auto_start_settings)
    sys.unsubscribe("AUTOSTART_CONFIG_CHANGED", request_auto_start_state)
    sys.unsubscribe("AUTOSTART_PASSWORD_RESULT", on_auto_start_password_result)
    sys.unsubscribe("VIDEO_FILE_CHANGED", on_video_file_changed)
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
    VP.obj = nil
    VP.card_ref = nil
    VP.ctrl_bar = nil
    VP.play_label = nil
    VP.loop_label = nil
    VP.file_label = nil
    VP.close_picker()
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
    if VP.resume_file and not VP.obj and VP.is_playing then
        local f = VP.resume_file
        VP.resume_file = nil
        pcall(VP.start_play, f)
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
    if VP.obj then
        if VP.current_file and VP.is_playing then
            VP.resume_file = VP.current_file
        end
        pcall(function() VP.obj:stop() end)
        pcall(function() VP.obj:destroy() end)
        VP.obj = nil
    end
    video_util.audio_stop()
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
