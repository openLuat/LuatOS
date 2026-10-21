--[[
@module  app_config
@summary 出厂固件运行配置（fskv 持久化）
@version 1.0
@date    2026.10.20

约定：
1. 只有"出厂默认值"写在本文件；运行中修改的值存 fskv 的 APP_CFG 键，重刷脚本不丢。
2. Web 页面、AirCloud 下行命令改配置时统一走 app_config.save()，改完发布 APP_CONFIG_UPDATED。
3. 与硬件相关的引脚不在这里，统一在 board.lua。
]]

local M = {}

local DEFAULTS = {
    -- 配置结构版本：需要强制刷新旧设备上的默认值时 +1
    cfg_ver = 2,

    -- 设备标识
    device_name = "Air8380",

    -- 网络优先级：网口 > WiFi > 4G（工业现场优先有线，其次现场 WiFi，4G 兜底）
    priority = { "eth", "wifi", "4g" },

    -- 以太网（默认静态，方便现场固定 IP 访问内置网页）
    eth_mode = "static",              -- static / dhcp
    eth_ip = "192.168.1.183",
    eth_mask = "255.255.255.0",
    eth_gw = "192.168.1.1",

    -- WiFi STA（出厂不预置，现场配网；留空表示不连）
    wifi_ssid = "",
    wifi_pwd = "",

    -- 时间
    timezone = "UTC+8",
    ntp_server = "ntp.aliyun.com",

    -- AirCloud：excloud 用 use_getip 自动认证，**不需要 project_key**
    cloud_enabled = true,
    project_key = "IV78QcZViBxtD9G71CD8X5qPVfW2NC9B",  -- 仅 FOTA 使用（iot 项目密钥）
    report_interval = 60,             -- 上报间隔（秒）

    -- 定位（airlbs 收费服务，项目在 iot.openluat.com/lbs/bs 创建）
    lbs_enabled = true,
    lbs_project_id = "lblKo3",        -- 合宙测试项目，量产建议换成客户自己的
    lbs_project_key = "DKqM6sHJkHV23WCzgzTbk7QW7HYGCJxp",
    lbs_interval = 600,               -- 定位间隔（秒），过密会被服务端限流
    lbs_wifi_scan = true,             -- 是否带 WiFi 扫描（更准，但会短暂影响 WiFi STA）

    -- FOTA
    fota_auto = true,
    fota_first_delay = 60,            -- 开机后首次检测延迟（秒）
    fota_interval = 14400,            -- 自动检测间隔（秒），4 小时

    -- 网络看门狗
    net_watchdog_enable = true,
    net_watchdog_timeout = 900,       -- 无 IP/无成功上报超过该秒数则重启
}

-- 配置版本升级时，用新默认值覆盖这些字段（旧设备 fskv 里存过的旧值会被刷新）
local CFG_FORCE_ON_MIGRATE = { "fota_interval", "fota_first_delay" }

local cfg

function M.load()
    if cfg then return cfg end
    fskv.init()
    local saved = fskv.get("APP_CFG")
    if type(saved) == "table" then
        for k, v in pairs(DEFAULTS) do
            if saved[k] == nil then saved[k] = v end
        end
        -- 配置版本迁移：旧设备 fskv 里存的是旧默认值，这里强制刷成新默认
        if saved.cfg_ver ~= DEFAULTS.cfg_ver then
            for _, k in ipairs(CFG_FORCE_ON_MIGRATE) do
                saved[k] = DEFAULTS[k]
            end
            saved.cfg_ver = DEFAULTS.cfg_ver
            fskv.set("APP_CFG", saved)
            log.info("app_config", "配置已迁移到版本", tostring(DEFAULTS.cfg_ver))
        end
        cfg = saved
        log.info("app_config", "已加载 fskv 配置")
    else
        cfg = {}
        for k, v in pairs(DEFAULTS) do cfg[k] = v end
        log.info("app_config", "无保存配置，使用出厂默认值")
    end
    return cfg
end

-- 合并保存（只覆盖传入的字段）
function M.save(tbl)
    if type(tbl) ~= "table" then return false end
    cfg = M.load()
    for k, v in pairs(tbl) do
        if type(v) == "string" then v = v:gsub("^%s+", ""):gsub("%s+$", "") end
        cfg[k] = v
    end
    fskv.set("APP_CFG", cfg)
    log.info("app_config", "配置已保存")
    sys.publish("APP_CONFIG_UPDATED", cfg)
    return true
end

-- 供 Web/云端回读，密码打码
function M.get_masked()
    local c = M.load()
    local m = {}
    for k, v in pairs(c) do
        if k == "wifi_pwd" or k == "project_key" then
            m[k] = (v and #tostring(v) > 0) and "****" or ""
        else
            m[k] = v
        end
    end
    return m
end

function M.reset()
    fskv.del("APP_CFG")
    cfg = nil
    local c = M.load()
    log.info("app_config", "已恢复出厂默认配置")
    sys.publish("APP_CONFIG_UPDATED", c)
    return c
end

-- 时区字符串 -> rtc.timezone 的 15 分钟偏移
function M.tz_offset(tz)
    local h = tonumber(string.match(tostring(tz or ""), "([+-]?%d+)")) or 8
    return h * 4
end

return M
