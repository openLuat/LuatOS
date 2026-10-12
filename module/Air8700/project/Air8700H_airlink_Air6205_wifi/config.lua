--[[
@module  config
@summary 配置管理模块 - WiFi热点参数和串口波特率的持久化存储
@version 1.0
@date    2026.09.14
@author  江访
@usage
本模块负责配置参数的读写和持久化存储，核心功能为：
1、从flash读取/写入JSON格式的配置数据（WiFi名称、密码、串口波特率）
2、根据设备IMEI自动生成默认WiFi热点名称
3、配置修改后立即写入flash，重启后自动加载

使用示例：
local config = require "config"
config.load()
local ssid = config.get("ssid", "")
config.set("ssid", "new_ssid")
local imei = config.get_imei()
--]]

local CONFIG_FILE = "/airlink_cfg.json" -- 配置文件存储路径（根目录可读写）

-- 配置数据（运行时缓存）
local cfg = {
    ssid     = "",      -- WiFi热点名称
    password = "",      -- WiFi密码
    baudrate = 115200,  -- 串口波特率
}

local M = {}

local imei_cache = nil -- IMEI缓存，避免重复查询

-- 保存配置到flash
local function config_save()
    local f = io.open(CONFIG_FILE, "w")
    if not f then
        log.info("config", "无法写入配置文件")
        return false
    end
    f:write(json.encode(cfg))
    f:close()
    log.info("config", "配置已保存")
    return true
end

-- 应用串口波特率设置到硬件
local function config_apply_baudrate()
    if uart then
        uart.setup(1, cfg.baudrate, 8, 1, uart.NONE)
        log.info("config", "串口波特率已设置为", cfg.baudrate)
    end
end

--[[
从flash加载配置并应用到硬件
@return boolean 加载是否成功（false表示使用默认值）
]]
function M.load()
    local f = io.open(CONFIG_FILE, "r")
    if not f then
        log.info("config", "无已保存配置，使用默认值")
        return false
    end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then
        return false
    end
    local ok, loaded = pcall(json.decode, data)
    if not ok or not loaded then
        log.info("config", "配置解析失败")
        return false
    end
    cfg.ssid     = loaded.ssid     or ""
    cfg.password = loaded.password or ""
    cfg.baudrate = loaded.baudrate or 115200
    config_apply_baudrate()
    log.info("config", "配置已加载")
    return true
end

--[[
获取配置项
@param string key 配置键名（"ssid"/"password"/"baudrate"）
@param any default 默认值（配置不存在时返回）
@return any 配置值
]]
function M.get(key, default)
    local v = cfg[key]
    if v == nil then return default end
    return v
end

--[[
设置配置项并持久化到flash
@param string key 配置键名
@param any value 配置值
]]
function M.set(key, value)
    cfg[key] = value
    config_save()
    -- 波特率修改后立即应用到硬件
    if key == "baudrate" then
        config_apply_baudrate()
    end
end

--[[
获取设备IMEI字符串（首次调用会查询硬件，后续返回缓存值）
@return string IMEI号码
]]
function M.get_imei()
    if imei_cache then return imei_cache end
    if mobile then
        local imei = mobile.imei()
        if imei and imei ~= "" then
            imei_cache = tostring(imei)
            return imei_cache
        end
    end
    imei_cache = "00000000"
    return imei_cache
end

--[[
生成默认WiFi SSID（格式：luatos_ + IMEI后4位）
@return string 默认SSID
]]
function M.default_ssid()
    local imei = M.get_imei()
    local tail4 = string.sub(imei, -4)
    return "luatos_" .. tail4
end

return M
