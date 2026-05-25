--[[
@module  app_main
@summary 应用主入口模块，负责按顺序加载所有业务功能模块
@version 1.2
@date    2026.05.06
@author  江访

=== 执行流程 ===

require 即执行，main.lua 调用 require "app_main" 时以下模块按顺序加载：

  1. net_init       → 统一网络事件订阅（DNS配置、IP_READY/IP_LOSE/WLAN_STA 日志、多网状态）
  2. wifi_app       → WiFi 业务层（自动连接、扫描、配置管理），内部根据平台分发到 wifi_app_real
  3. status_provider_app → 状态栏数据源（时间/信号/电量定时更新，发布 STATUS_UPDATE）
  4. ntp_app        → NTP 时间同步（订阅 IP_READY，联网后自动校时）
  5. speedtest_app  → Cloudflare 测速（订阅 SPEEDTEST_START，延迟→下载→上传三阶段）
  6. settings_iot_app → IOT 平台账号登录/登出（订阅 LOGIN_REQUEST/LOGOUT_REQUEST）
  7. settings_app   → 设置主框架（加载所有设置子模块，fskv 持久化配置）
  8. fota_app       → 固件 OTA 升级（订阅 IP_READY，定时检查云端新版本）

=== 关键设计决策 ===

1. require 顺序即初始化顺序：Lua 单线程，每个模块 require 时注册事件订阅、启动定时器，
   互不阻塞。顺序考虑：网络基础设施 → 依赖网络的服务 → 独立设置 → OTA

2. 不做条件 require：app_main 对所有平台加载相同模块列表，模块内部根据 project_config
   自行判断是否激活。例如 wifi_app 对仅 4G 平台（Air780E）走 exnetif 纯 4G 路径

3. 事件驱动解耦：模块之间不直接调用，通过 sys.publish/subscribe 通信。
   例如 ntp_app 和 fota_app 都订阅 IP_READY，但互不知晓对方存在
]]

-- 加载统一网络初始化模块（DNS/IP/WLAN事件管理，基于 exnetif 多网融合）
-- 必须在 wifi_app 之前加载，提供网卡状态日志和 DNS 配置基础设施
require "net_init"

-- 加载 wifi_app 主模块（分发器：WiFi 平台 → wifi_app_real，仅4G平台 → exnetif 4G初始化）
require "wifi_app"

-- 加载状态提供 app 模块（系统时间/4G信号/WiFi信号 定时更新，发布 STATUS_UPDATE 给状态栏）
require "status_provider_app"

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
