--[[
@module  app_main
@summary 应用主入口模块，负责按顺序加载所有业务功能模块
@version 1.3
@date    2026.06.26
@author  江访

=== 执行流程 ===

require 即执行，main.lua 调用 require "app_main" 时以下模块按顺序加载：

  1. net_manager    → 统一网络管理器（读取 config.network，构建 exnetif 优先级列表）
                     替代旧的 wifi_app + netdrv_eth_spi，初始化所有非WiFi兜底网络
  2. net_init       → 统一网络事件订阅（DNS配置、IP_READY/IP_LOSE/WLAN_STA 日志）
  3. wifi_app_real  → WiFi 业务层（自动连接、扫描、UI交互），不再做4G/以太网初始化
  4. status_provider_app → 状态栏数据源（时间/信号/电量定时更新，发布 STATUS_UPDATE）
  5. ntp_app        → NTP 时间同步（订阅 IP_READY，联网后自动校时）
  6. speedtest_app  → Cloudflare 测速（订阅 SPEEDTEST_START）
  7. settings_iot_app → IOT 平台账号登录/登出
  8. settings_app   → 设置主框架（fskv 持久化配置）
  9. fota_app       → 固件 OTA 升级

=== 网络架构变化 ===

旧: wifi_app (分发) → wifi_app_real (混合4G/WiFi/以太网) + netdrv_eth_spi
新: net_manager (统一读 config → exnetif.set_priority_order)
    wifi_app_real (仅 WiFi 扫描/连接/UI 交互)
]]

-- 加载统一网络管理器（require 时不初始化，只注册接口）
-- 替代旧的 require "wifi_app" + require "netdrv_eth_spi"
-- 必须在 net_init 之前加载，使 exnetif IP 事件能被 net_init 正常订阅
local net_manager = require "net_manager"

-- 传入 project_config，在 task 中初始化 net_manager 并启动所有网络
-- exnetif.set_priority_order 内部使用 sys.wait()，必须在 task 中调用
sys.taskInit(function()
    net_manager.init(_G.project_config)
end)

-- 加载统一网络事件订阅模块（DNS配置、IP_READY/IP_LOSE/WLAN_STA 日志）
require "net_init"

-- 加载 WiFi 业务层（仅 WiFi 扫描/连接/配置管理，不含4G/以太网初始化）
-- net_manager 已处理所有非WiFi网络的初始化兜底
require "wifi_app_real"

-- 加载状态提供 app 模块（系统时间/4G信号/WiFi信号 定时更新，发布 STATUS_UPDATE 给状态栏）
require "status_provider_app"

-- 加载电池管理模块（按 features.battery 配置开关，ADC 电压检测 + USB 充电检测）
if _G.project_config and _G.project_config.features and _G.project_config.features.battery then
    require "battery_app"
end

-- 加载 NTP 时间同步应用模块（订阅 IP_READY，首次联网自动向 ntp.aliyun.com 校时）
require "ntp_app"

-- 加载网络测速应用模块（订阅 SPEEDTEST_START，执行 Cloudflare 延迟/下载/上传测速）
require "speedtest_app"

-- 加载 IOT 账号模块（合宙 IoT 平台登录/登出，需联网，订阅 LOGIN_REQUEST/LOGOUT_REQUEST）
require "settings_iot_app"

-- 加载设置主模块（会级联 require 所有 settings_*_app 子模块，fskv 初始化和配置加载）
require "settings_app"

-- 加载 FOTA 固件升级模块（订阅 IP_READY，定时向 iot.openluat.com 检查固件更新）
require "fota_app"

-- NES游戏按键模块（按 features.nes 配置开关）
if _G.project_config and _G.project_config.features and _G.project_config.features.nes then
    require "nes_key_app"
end

-- 文件管理模块（浏览各挂载点 /app_store 目录，支持展开/折叠、新建/删除）
require "file_manager_app"
