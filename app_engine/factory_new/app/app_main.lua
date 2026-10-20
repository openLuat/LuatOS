--[[
@module  app_main
@summary 业务模块聚合入口：core() 核心批 + optional() 可选批（boot_ui 分批调用）
@version 2.0
@date    2026.10.16
@author  江访

=== 执行流程 ===

boot_ui 在 logo 展示期间分批调用本模块的两个函数：

  core()     核心批（进桌面前必须完成）：
    1. status_provider_app → 状态栏数据源（时间/信号/电量定时更新，发布 STATUS_*)
    2. settings_iot_app    → IOT 平台账号登录/登出
    3. settings_app        → 设置主框架（fskv 持久化，级联 8 个 settings_*_app 子模块）
    4. fota_app            → 固件 OTA 升级
    5. file_manager_app    → 文件管理业务层（file_manager_win 同批加载）

  optional() 可选批（独立协程与桌面并行，功能开关门控）：
    1. net_manager    → 统一网络管理器（task 中 init，读取 config.network 构建 exnetif 优先级）
    2. net_init       → 统一网络事件订阅（DNS配置、IP_READY/IP_LOSE/WLAN_STA 日志）
    3. wifi_app_real  → WiFi 业务层（自动连接、扫描、UI交互），不做4G/以太网初始化
    4. weather_app    → 天气服务（按出口 IP 自动定位城市，发布 WEATHER_UPDATED）
    5. battery_app    → 电池管理（features.battery）
    6. nes_key_app    → NES 游戏按键（features.nes，模块加载即注册）
    7. ntp_app        → NTP 时间同步（订阅 IP_READY）
    （1~4、7 为网络族，has_net 门控：无网络板不加载，见下方 optional() 内注释）
    8. factory_app    → 应用工厂（features.app_factory，级联 factory_rec）
    9. usb_hid_app    → USB HID 键鼠（features.usb_hid）
   10. llm_chat       → AI 助手（features.ai_chat）
   11. cloud_disk_app → 合宙网盘（features.cloud_disk）
   12. tts_app        → TTS 播报（hw.audio）
   13. aircloud_app   → AirCloud 数据上报（features.aircloud）
   14. file_transfer_app → hzadb 文件传输（features.file_transfer）
   15. periph_loader  → 外设预留框架（config.peripherals，未实现 type 记日志跳过）

=== 关键约束 ===

1. UI 窗口与业务层必须成对、同批加载（见 ui_main 同款注释）：只加载 UI 会
   「窗口能开、按钮没反应」，只加载业务会白占内存
2. 门控条件必须与 ui_main 对应窗口的门控完全一致
3. require 只用文件名不带路径；函数体内静态 require 由编译系统文本扫描打包，
   不需要登记 platform_loader 编译清单（清单已包进永不调用的函数，不参与运行时）
]]

local M = {}

-- ==================== 核心批：进桌面前必须完成 ====================
function M.core()
    -- 状态提供 app 模块（系统时间/4G信号/WiFi信号 定时更新，发布 STATUS_* 给状态栏）
    require "status_provider_app"
    -- IOT 账号模块（合宙 IoT 平台登录/登出，需联网，订阅 LOGIN_REQUEST/LOGOUT_REQUEST）
    require "settings_iot_app"
    -- 设置主模块（级联 require 所有 settings_*_app 子模块，fskv 初始化和配置加载）
    require "settings_app"
    -- FOTA 固件升级模块（订阅 IP_READY，定时向 iot.openluat.com 检查固件更新）
    require "fota_app"
    -- 文件管理业务层（file_manager_win 也会 require，这里保证启动即注册）
    require "file_manager_app"
end

-- ==================== 可选批：与桌面并行加载，功能开关门控 ====================
function M.optional()
    local cfg = _G.project_config or {}
    local feat = cfg.features or {}

    -- 网络族：无网络板（features 无 wifi/net_4g/ethernet 且未配 network 段，如 8607）
    -- 不加载网络栈（net_manager 会拖出 exnetif/httpplus 等整条库链）
    local has_net = (type(cfg.network) == "table" and #cfg.network > 0)
        or feat.wifi or feat.net_4g or feat.ethernet
    if has_net then
        -- 统一网络管理器（require 时不初始化，只注册接口）
        -- 替代旧的 require "wifi_app" + require "netdrv_eth_spi"
        -- 必须在 net_init 之前加载，使 exnetif IP 事件能被 net_init 正常订阅
        local net_manager = require "net_manager"
        -- 传入 project_config，在 task 中初始化 net_manager 并启动所有网络
        -- exnetif.set_priority_order 内部使用 sys.wait()，必须在 task 中调用
        sys.taskInit(function()
            local ok, err = pcall(net_manager.init, cfg)
            if not ok then
                log.error("app_main", "net_manager.init 失败，桌面继续运行", err)
            end
        end)

        -- 统一网络事件订阅（DNS配置、IP_READY/IP_LOSE/WLAN_STA 日志）
        require "net_init"
        -- WiFi 业务层（仅 WiFi 扫描/连接/配置管理，不含4G/以太网初始化）
        require "wifi_app_real"
        -- 天气服务模块（订阅 IP_READY，联网后按出口 IP 自动定位城市并查询天气，
        -- 发布 WEATHER_UPDATED 给桌面天气卡；数据源全部免 key）
        require "weather_app"
    end

    -- 电池管理（ADC 电压检测 + USB 充电检测）
    if feat.battery then
        require "battery_app"
    end

    -- NES 游戏按键（需配 nes_keys；模块加载即注册幂等，见 nes_key_app 头部说明）
    if feat.nes then
        require "nes_key_app"
    end

    -- NTP 时间同步（订阅 IP_READY，首次联网自动向 ntp.aliyun.com 校时；无网络板不加载）
    if has_net then
        require "ntp_app"
    end

    -- 应用工厂（录音 → 生成 → 安装链路，级联 require factory_rec）
    if feat.app_factory then
        require "factory_app"
    end

    -- USB HID 键盘鼠标管理
    if feat.usb_hid then
        require "usb_hid_app"
    end

    -- AI 助手（WebSocket 会话 + STT/TTS，订阅 AI_CHAT_*）
    if feat.ai_chat then
        require "llm_chat"
    end

    -- 合宙网盘（IoT 登录取 space_key → device_space/list_files → 下载到最高优先级存储）
    if feat.cloud_disk then
        require "cloud_disk_app"
    end

    -- TTS 播报服务（云端 tts 下行命令/本地共用播放路径）；仅 hw.audio 配置存在的板子加载
    if cfg.hw and cfg.hw.audio then
        require "tts_app"
    end

    -- AirCloud 数据上报（能力探测：有接口就采，没有就跳过，不绑定型号）
    if feat.aircloud then
        require "aircloud_app"
    end

    -- 文件传输（hzadb 服务管理/共享清单/传输记录，PC↔设备经日志口互传文件）
    if feat.file_transfer then
        require "file_transfer_app"
    end

    -- 外设预留框架：按 config.peripherals 逐个初始化，未实现 type 记日志跳过
    pcall(function() require("periph_loader").init_all(cfg.peripherals) end)
end

return M
