--[[
@module  net_config
@summary 网络配置管理 — fskv 持久化存储
@version 1.1
@date    2026.09.18
@usage
本文件为网络配置管理模块，负责读取/保存网络相关配置（以太网、WiFi STA、时区、网络优先级等）。
配置通过 fskv 持久化存储，首次运行使用默认值，之后可通过 M.save() 覆盖保存并广播 NET_CONFIG_UPDATED。


对外接口：
1、net_config.load()    → 读取配置（含默认值合并）
2、net_config.save(t)   → 保存配置并广播 NET_CONFIG_UPDATED
3、net_config.reset()   → 恢复默认配置
]]

local M = {}

-- 配置版本（结构变更时递增，用于自动淘汰 fskv 中的旧配置，避免旧字段残留）
local CFG_VERSION = 2

-- 默认配置
local DEFAULTS = {
    config_version = CFG_VERSION,
    device_name = "Air8300",
    ntp_server = "ntp.aliyun.com",
    timezone = "UTC+8",

    -- ============ 以太网（单网口供网）============
    eth_enable = "eth1",             -- 启用的网口："eth1"(网口1,cs=21) / "eth2"(网口2,cs=20) / "none"(禁用)
    eth_mode   = "dhcp",             -- IP 获取方式："dhcp"(推荐,插上路由器即可上网) / "static"
    eth1_ip    = "192.168.10.183",   -- 仅 eth_mode="static" 时生效（独立网段，避免与 WiFi 冲突）
    eth1_mask  = "255.255.255.0",
    eth1_gw    = "192.168.10.1",
    eth2_ip    = "192.168.20.185",   -- 仅 eth_mode="static" 时生效（独立网段）
    eth2_mask  = "255.255.255.0",
    eth2_gw    = "192.168.20.1",
    net_need_ping = false,           -- 网卡连通性检测：false=仅依据 IP_READY 判断（就绪快，推荐）；true=ping 外网判定

    -- ============ WiFi（仅 STA 上网）============
    wifi_ssid = "116",
    wifi_pwd = "wangshuai123",

    -- ============ 网络优先级（高 → 低）============
    priority = { "eth1", "wifi", "4g" },
    power_mode = "normal",
}

-- 深拷贝（配置中含嵌套表 priority，必须深拷贝；否则运行期修改会污染出厂默认值 DEFAULTS）
local function deep_copy(t)
    if type(t) ~= "table" then
        return t
    end
    local r = {}
    for k, v in pairs(t) do
        r[k] = deep_copy(v)
    end
    return r
end

local cfg = nil

-- 读取配置（若未加载先加载，并合并默认值）
function M.load()
    if cfg then return cfg end
    fskv.init()
    local saved = fskv.get("NET_CFG")
    -- 配置版本不一致（结构已变更）时，直接启用新默认值，避免旧字段残留
    if type(saved) == "table" and saved.config_version ~= CFG_VERSION then
        log.info("net_config", "配置版本已更新，使用新默认值")
        cfg = deep_copy(DEFAULTS)      -- 深拷贝，避免后续 save 污染 DEFAULTS
        fskv.set("NET_CFG", cfg)
        return cfg
    end
    if type(saved) == "table" then
        for k, v in pairs(DEFAULTS) do
            if saved[k] == nil then saved[k] = v end
        end
        cfg = saved
        log.info("net_config", "已加载 fskv 配置")
    else
        cfg = deep_copy(DEFAULTS)      -- 深拷贝，避免后续 save 污染 DEFAULTS
        log.info("net_config", "无保存配置，使用默认值")
    end
    return cfg
end

-- 保存配置（合并到现有配置并持久化，广播 NET_CONFIG_UPDATED）
function M.save(tbl)
    if not tbl then return false end
    for k, v in pairs(tbl) do cfg[k] = v end
    fskv.set("NET_CFG", cfg)
    log.info("net_config", "配置已保存")
    sys.publish("NET_CONFIG_UPDATED", cfg)
    return true
end

-- 获取脱敏后的配置（隐藏 WiFi 密码）
function M.get_masked()
    local c = M.load()
    local m = {}
    for k, v in pairs(c) do
        m[k] = (k == "wifi_pwd") and "****" or v
    end
    return m
end

-- 恢复默认配置
function M.reset()
    cfg = deep_copy(DEFAULTS)          -- 深拷贝，保证恢复出厂默认后不被运行期修改污染
    fskv.del("NET_CFG")
    log.info("net_config", "已恢复默认配置")
    sys.publish("NET_CONFIG_UPDATED", cfg)
    return cfg
end

M.load()
return M
