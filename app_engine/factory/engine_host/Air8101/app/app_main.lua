--[[
@module  app_main
@summary 应用主入口模块，负责加载所有功能模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本文件为系统应用的主入口，依次加载各个功能模块：
- netdrv_device：网络驱动设备
- aircloud_app：云平台应用
- status_provider_app：状态提供器应用

所有模块在加载时自动执行初始化，无需额外调用。
]]
-- 加载网络驱动设备功能模块
-- require "netdrv_device"

-- 加载 wifi_app 主模块
require "wifi_app"

-- 加载状态提供app模块
require "status_provider_app"

-- 加载ntp时间同步应用模块
require "ntp_app"

-- 加载网络测速应用模块
require "speedtest_app"

-- 加载设置主模块（会通知settings_config_app进行初始化）
require "settings_app"