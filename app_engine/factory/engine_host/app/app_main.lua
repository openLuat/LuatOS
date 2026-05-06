--[[
@module  app_main
@summary 应用主入口模块，负责加载所有功能模块
@version 1.2
@date    2026.05.06
@author  江访
@usage
本文件为系统应用的主入口，依次加载各个功能模块。
所有模块在加载时自动执行初始化，无需额外调用。
]]

-- 平台检测
local function get_model()
    local ok, m = pcall(hmeta.model)
    if ok and m then return tostring(m) end
    return rtos.bsp() or ""
end
local model = get_model()
local is_air1601 = model:find("Air1601") or model:find("Air1602")

-- Air1601/Air1602: GPIO55供电给Air780EPM WiFi模块
if is_air1601 then
    gpio.setup(55, 1)
end

-- 加载网络驱动设备功能模块
-- Air1601/Air1602通过netdrv_device注册WiFi网卡驱动
-- Air8000/Air8101由exnetif自行管理网络适配器
if is_air1601 then
    require "netdrv_device"
end

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
