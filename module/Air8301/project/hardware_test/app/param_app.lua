--[[
@module  param_app
@summary 参数管理应用模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
管理设备配置（device_config.json）的加载、保存、恢复出厂设置。
1、启动时从 /device_config.json 加载配置，不存在则用 param_default 创建
2、订阅 CONFIG_UPDATE_TRIGGER(module_name, module_data) 事件，合并更新并保存
3、订阅 FACTORY_RESET_UI 事件，恢复出厂设置（重启后生效）
4、订阅 BACKUP_RESTORE 事件，备份恢复（重启后生效）
5、NTP 对时管理
]]

local param_app = {}

local TASK_NAME = "param_app"

-- 设备配置引用
local _device_config = nil

-- 配置文件路径
local CONFIG_PATH = "/device_config.json"
local RESTORE_FLAG_PATH = "/restore_pending.json"
local FACTORY_DEFAULT_PATH = "/device_config_default.json"

--[[
@function load_config
@summary 加载配置文件（优先恢复标记 > 出厂默认 > 正常加载 > param_default 兜底）
@return table 配置数据
]]
local function load_config()
    -- 检查是否有待恢复的配置（来自备份恢复）
    local f = io.open(RESTORE_FLAG_PATH, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, restore_data = pcall(json.decode, content)
        if ok and restore_data then
            log.info(TASK_NAME, "restoring config from backup")
            os.remove(RESTORE_FLAG_PATH)
            local wf = io.open(CONFIG_PATH, "w")
            if wf then
                wf:write(json.encode(restore_data))
                wf:close()
                log.info(TASK_NAME, "config restored and saved")
                return restore_data
            end
        end
    end

    -- 检查是否有恢复出厂设置标记
    f = io.open(FACTORY_DEFAULT_PATH, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, default_data = pcall(json.decode, content)
        if ok and default_data then
            log.info(TASK_NAME, "factory reset detected, applying defaults")
            local wf = io.open(CONFIG_PATH, "w")
            if wf then
                wf:write(content)
                wf:close()
            end
            os.remove(FACTORY_DEFAULT_PATH)
            return default_data
        end
    end

    -- 正常加载配置
    f = io.open(CONFIG_PATH, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and data then
            log.info(TASK_NAME, "config loaded from", CONFIG_PATH)
            return data
        end
    end

    -- 兜底：用 param_default 创建
    log.warn(TASK_NAME, "no config file found, creating from param_default")
    local param_default = require "param_default"
    local wf = io.open(CONFIG_PATH, "w")
    if wf then
        wf:write(json.encode(param_default))
        wf:close()
        log.info(TASK_NAME, "config file created from param_default")
    end
    return param_default
end

--[[
@function save_config
@summary 保存配置到文件
@param config table 配置数据
]]
local function save_config(config)
    local f = io.open(CONFIG_PATH, "w")
    if f then
        f:write(json.encode(config))
        f:close()
        log.info(TASK_NAME, "config saved")
    else
        log.error(TASK_NAME, "config save failed")
    end
end

--[[
@function factory_reset_to_defaults
@summary 恢复出厂设置 - 将默认配置写入标记文件，重启后生效
@return boolean 是否成功
]]
local function factory_reset_to_defaults()
    local param_default = require "param_default"
    local wf = io.open(FACTORY_DEFAULT_PATH, "w")
    if wf then
        wf:write(json.encode(param_default))
        wf:close()
        log.info(TASK_NAME, "factory_reset: defaults saved to", FACTORY_DEFAULT_PATH)
        return true
    end
    log.error(TASK_NAME, "factory_reset: failed to write")
    return false
end

--[[
@function save_pending_restore
@summary 保存待恢复的配置（重启后自动应用）
@param config table 要恢复的配置
@return boolean 是否成功
]]
local function save_pending_restore(config)
    local f = io.open(RESTORE_FLAG_PATH, "w")
    if f then
        f:write(json.encode(config))
        f:close()
        return true
    end
    return false
end

-- ==================== NTP 对时 ====================

--[[
@function sync_ntp
@summary 执行 NTP 对时
@param ntp_config table NTP 配置 {server, tz, interval_h}
]]
local function sync_ntp(ntp_config)
    if not ntp_config then return end
    local server = ntp_config.server or "ntp.aliyun.com"
    local tz = ntp_config.tz or "UTC+8"

    log.info(TASK_NAME, "NTP sync", "server:", server, "tz:", tz)
    sys.publish("NTP_REQ", server)
end

-- ==================== 事件订阅 ====================

local function subscribe_events()
    -- 配置更新事件：合并更新指定模块的配置
    sys.subscribe("CONFIG_UPDATE_TRIGGER", function(module_name, module_data)
        log.info(TASK_NAME, "CONFIG_UPDATE_TRIGGER", module_name)
        if not module_name or not module_data then return end
        if not _device_config[module_name] then
            _device_config[module_name] = {}
        end
        for k, v in pairs(module_data) do
            _device_config[module_name][k] = v
        end
        save_config(_device_config)
        -- 通知所有模块配置已更新
        sys.publish("CONFIG_UPDATED", _device_config)
    end)

    -- 恢复出厂设置
    sys.subscribe("FACTORY_RESET_UI", function()
        log.info(TASK_NAME, "FACTORY_RESET_UI received")
        local ok = factory_reset_to_defaults()
        sys.publish("FACTORY_RESET_RESULT", ok, nil)
    end)

    -- 备份恢复
    sys.subscribe("BACKUP_RESTORE", function(config)
        log.info(TASK_NAME, "BACKUP_RESTORE received")
        if save_pending_restore(config) then
            log.info(TASK_NAME, "pending restore saved, will apply after reboot")
        end
    end)
end

-- ==================== 对外接口 ====================

--[[
@function param_app.init
@summary 初始化参数管理模块
@param device_config table 设备配置引用（由 app_main 传入）
]]
function param_app.init(device_config)
    _device_config = device_config
    subscribe_events()

    -- NTP 对时
    local ntp_cfg = device_config.system
    if ntp_cfg and ntp_cfg.ntp_enabled then
        -- 启动后延迟执行 NTP 对时（等网络就绪）
        sys.taskInit(function()
            sys.wait(5000)
            sync_ntp(ntp_cfg)
            -- 定期对时
            local interval_h = ntp_cfg.ntp_interval_h or 6
            while true do
                sys.wait(interval_h * 3600 * 1000)
                sync_ntp(ntp_cfg)
            end
        end)
    end

    log.info(TASK_NAME, "init done")
end

--[[
@function param_app.get_config
@summary 获取当前配置引用
@return table 设备配置
]]
function param_app.get_config()
    return _device_config
end

--[[
@function param_app.save_config
@summary 外部调用保存配置
@param config table 要保存的完整配置
]]
function param_app.save_config(config)
    _device_config = config
    save_config(config)
end

return param_app
