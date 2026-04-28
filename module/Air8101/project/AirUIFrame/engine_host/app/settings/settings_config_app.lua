--[[
@module  settings_config_app
@summary 设置配置管理模块
@version 1.0
@date    2026.04.02
@author  LuatOS
@usage
本模块管理应用配置参数，使用fskv进行持久化存储。
功能：
1. 开机自动初始化fskv
2. 管理设备名称等配置参数
3. 提供配置参数的读取和保存接口
]]

local settings_config_app = {}

-- ==================== 配置常量 ====================

-- 配置项键名
local CONFIG_KEYS = {
    DEVICE_NAME = "device_name"  -- 设备名称
}

-- 设备名称后缀常量（拼接在模组型号后面）
local DEVICE_NAME_SUFFIX = "_UI_畅玩板"

-- 默认值（不在此处定义，动态生成）
-- 注意：默认值通过 get_default_device_name() 函数动态获取

-- ==================== 局部变量 ====================

-- fskv初始化状态
local fskv_initialized = false

-- ==================== 私有函数 ====================

--[[
获取默认设备名称（动态拼接模组型号 + 后缀）
@return string 默认设备名称，格式：模组型号_UI_畅玩板
]]
local function get_default_device_name()
    local model = "Air8101"
    local ret, result = pcall(hmeta.model)
    if ret and result and result ~= "" then
        model = result
    end
    return model .. DEVICE_NAME_SUFFIX
end

--[[
初始化fskv
@return boolean 初始化是否成功
]]
local function init_fskv()
    if fskv_initialized then
        return true
    end

    local result = fskv.init()
    if result then
        fskv_initialized = true
        log.info("settings_config_app", "fskv初始化成功")

        -- 初始化默认值（如果不存在）
        local default_device_name = get_default_device_name()
        local value = fskv.get(CONFIG_KEYS.DEVICE_NAME)
        if value == nil then
            fskv.set(CONFIG_KEYS.DEVICE_NAME, default_device_name)
            log.info("settings_config_app", "设置默认值", CONFIG_KEYS.DEVICE_NAME, default_device_name)
        end

        return true
    else
        log.error("settings_config_app", "fskv初始化失败")
        return false
    end
end

--[[
获取配置值
@param key 配置键名
@param default_value 默认值（可选）
@return any 配置值
]]
local function get_config(key, default_value)
    if not fskv_initialized then
        log.warn("settings_config_app", "fskv未初始化，尝试初始化")
        if not init_fskv() then
            return default_value or ""
        end
    end

    local value = fskv.get(key)
    if value == nil then
        value = default_value or ""
    end
    return value
end

--[[
设置配置值
@param key 配置键名
@param value 配置值
@return boolean 是否设置成功
]]
local function set_config(key, value)
    if not fskv_initialized then
        log.warn("settings_config_app", "fskv未初始化，尝试初始化")
        if not init_fskv() then
            return false
        end
    end
    
    local result = fskv.set(key, value)
    if result then
        log.info("settings_config_app", "配置已保存", key, value)
        -- 发布配置变更事件
        sys.publish("CONFIG_CHANGED", key, value)
    else
        log.error("settings_config_app", "配置保存失败", key)
    end
    return result
end

-- ==================== 设备名称相关接口 ====================

--[[
获取设备名称
@return string 设备名称
]]
local function get_device_name()
    return get_config(CONFIG_KEYS.DEVICE_NAME)
end

--[[
设置设备名称
@param name 设备名称
@return boolean 是否设置成功
]]
local function set_device_name(name)
    return set_config(CONFIG_KEYS.DEVICE_NAME, name)
end

-- ==================== 事件处理 ====================

-- 订阅获取设备名称事件
sys.subscribe("CONFIG_GET_DEVICE_NAME", function()
    local device_name = get_device_name()
    sys.publish("CONFIG_DEVICE_NAME_VALUE", device_name)
    log.info("settings_config_app", "上报设备名称", device_name)
end)

-- 订阅设置设备名称事件
sys.subscribe("CONFIG_SET_DEVICE_NAME", function(name)
    if name and #name > 0 then
        set_device_name(name)
    else
        log.warn("settings_config_app", "设置设备名称失败，名称无效")
    end
end)

-- ==================== 事件订阅 ====================
-- 订阅 settings_app 初始化通知
sys.subscribe("SETTINGS_APP_INIT", function()
    log.info("settings_config_app", "收到初始化通知")
    init_fskv()
end)

log.info("settings_config_app", "模块加载完成")

return settings_config_app
