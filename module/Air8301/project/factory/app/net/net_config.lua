--[[
@module  net_config
@summary 网络配置管理 — fskv 持久化存储（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
]]

local M = {}

local DEFAULTS = {
    device_name = "Air8301",
    ntp_server = "ntp.aliyun.com",
    timezone = "UTC+8",
    wifi_ssid = "116",
    wifi_pwd = "wangshuai123",
    wifi_ip = "192.168.1.200",
    wifi_mask = "255.255.255.0",
    wifi_gw = "192.168.1.1",
    ap_ssid = "Air8301",
    ap_pwd = "12345678",
    ap_ip = "192.168.4.1",
    ap_mask = "255.255.255.0",
    ap_gw = "192.168.4.1",
    eth1_ip = "192.168.1.183",
    eth1_mask = "255.255.255.0",
    eth1_gw = "192.168.1.1",
    eth2_ip = "192.168.1.185",
    eth2_mask = "255.255.255.0",
    eth2_gw = "192.168.1.1",
    priority = { "wifi", "eth1", "eth2", "4g" },
    power_mode = "normal",       -- normal / lowpower / psm
    psm_interval = 300,          -- 低功耗/PSM 唤醒间隔(秒)
}

local cfg = nil

--[[
加载网络配置（无保存则使用默认值）

@return table 网络配置表
]]
function M.load()
    if cfg then return cfg end
    fskv.init()
    local saved = fskv.get("NET_CFG")
    if type(saved) == "table" then
        for k, v in pairs(DEFAULTS) do
            if saved[k] == nil then saved[k] = v end
        end
        cfg = saved
        log.info("net_config", "已加载 fskv 配置")
    else
        cfg = DEFAULTS
        log.info("net_config", "无保存配置，使用默认值")
    end
    return cfg
end

--[[
保存网络配置并广播 NET_CONFIG_UPDATED

@param tbl table 需要保存的配置项
@return boolean 是否成功
]]
function M.save(tbl)
    if not tbl then return false end
    for k, v in pairs(tbl) do cfg[k] = v end
    fskv.set("NET_CFG", cfg)
    log.info("net_config", "配置已保存")
    sys.publish("NET_CONFIG_UPDATED", cfg)
    return true
end

--[[
获取配置（密码打码），用于 UI 展示

@return table 打码后的配置表
]]
function M.get_masked()
    local c = M.load()
    local m = {}
    for k, v in pairs(c) do
        m[k] = (k == "wifi_pwd") and "****" or v
    end
    return m
end

--[[
恢复默认配置

@return table 默认配置表
]]
function M.reset()
    cfg = DEFAULTS
    fskv.del("NET_CFG")
    log.info("net_config", "已恢复默认配置")
    sys.publish("NET_CONFIG_UPDATED", cfg)
    return cfg
end

M.load()
return M
