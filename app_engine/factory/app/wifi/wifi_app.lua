--[[
@module  wifi_app
@summary 网络管理分发器（基于项目配置驱动，统一走 exnetif 多网融合）
@version 2.0
@date    2026.05.22
@author  江访
@usage
根据 project_config.features 决定加载路径：
  有 WiFi → 加载 wifi_app_real（全平台统一 WiFi 业务逻辑）
  仅 4G  → 通过 exnetif 启用 4G（原生4G 或 airlink 4G）
]]
local config = _G.project_config or {}
local features = config.features or {}

-- 4G-only 平台：仅通过 exnetif 启用 4G 网卡，不加载 WiFi 相关逻辑
if features.net_4g and not features.wifi then
    local exnetif = require "exnetif"
    local net_cfg = features.net_4g_config or {}
    local priority
    if net_cfg.type == "airlink" then
        -- airlink 4G（Air8101 + Air780EPM 等外挂模组，无 WiFi）
        local acfg = {
            airlink_type = net_cfg.airlink_type,
            auto_socket_switch = (net_cfg.auto_socket_switch ~= false),
        }
        if net_cfg.airlink_spi_id then acfg.airlink_spi_id = net_cfg.airlink_spi_id end
        if net_cfg.airlink_cs_pin then acfg.airlink_cs_pin = net_cfg.airlink_cs_pin end
        if net_cfg.airlink_rdy_pin then acfg.airlink_rdy_pin = net_cfg.airlink_rdy_pin end
        if net_cfg.airlink_uart_id then acfg.airlink_uart_id = net_cfg.airlink_uart_id end
        if net_cfg.airlink_uart_baud then acfg.airlink_uart_baud = net_cfg.airlink_uart_baud end
        priority = { { airlink_4G = acfg } }
    else
        -- 原生 4G（Air780EGG/EHV/EHU/EHM 等）
        priority = { { LWIP_GP = true } }
    end
    sys.taskInit(function()
        local ok = exnetif.set_priority_order(priority)
        if ok then
            log.info("wifi_app", "4G-only 平台，exnetif 4G 已初始化")
        else
            log.error("wifi_app", "4G-only 平台，exnetif 4G 初始化失败")
        end
    end)
    return
end

-- 有 WiFi 的平台：加载统一 WiFi 应用（Air1601/Air1602/Air8000W/Air8000A/Air8101 等）
return require "wifi_app_real"
