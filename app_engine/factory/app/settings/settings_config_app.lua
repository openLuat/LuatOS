--[[
@module  settings_config_app
@summary 设置配置管理模块
@version 1.0
@date    2026.04.02
@author  江访
@usage
本模块管理应用配置参数，使用fskv进行持久化存储。
功能：
1. 开机自动初始化fskv
2. 管理设备名称等配置参数
3. 提供配置参数的读取和保存接口
]]
-- naming: fn(2-5char), var(2-4char)

-- ==================== 配置常量 ====================

-- 配置项键名
local CK = {
    DEVICE_NAME     = "device_name",
    IOT_ACCOUNT     = "iot_account",
    IOT_PASSWORD    = "iot_password",
    IOT_NICKNAME    = "iot_nickname",
    IOT_LOGIN_TIME  = "iot_login_time"
}

-- 默认值（不在此处定义，动态生成）
-- 注意：默认值通过 get_default_device_name() 函数动态获取

-- ==================== 局部变量 ====================

-- fskv初始化状态
local finit = false

-- ==================== 私有函数 ====================

--[[
@function get_default_device_name
@summary 获取默认设备名称（动态拼接模组型号 + 后缀）
@return string 默认设备名称
]]
local function gdn()
    local sfx = _G.model_str:gsub("^Air", "")
    if sfx ~= "" then
        return "合宙引擎主机" .. sfx
    end
    return "合宙引擎主机"
end

--[[
@function init_fskv
@summary 初始化 fskv，如未初始化则设置默认值
@return boolean 初始化是否成功
]]
local function ifk()
    if finit then
        return true
    end

    local result = fskv.init()
    if result then
        finit = true
        log.info("scfg", "fskv初始化成功")

        -- 初始化默认值（如果不存在）
        local defn = gdn()
        local val = fskv.get(CK.DEVICE_NAME)
        if val == nil then
            fskv.set(CK.DEVICE_NAME, defn)
            log.info("scfg", "设置默认值", CK.DEVICE_NAME, defn)
        end

        return true
    else
        log.error("scfg", "fskv初始化失败")
        return false
    end
end

--[[
@function get_config
@summary 获取配置值
@param key 配置键名
@param default_value 默认值（可选）
@return any 配置值
]]
local function gc(key, def)
    if not finit then
        log.warn("scfg", "fskv未初始化，尝试初始化")
        if not ifk() then
            return def or ""
        end
    end

    local val = fskv.get(key)
    if val == nil then
        val = def or ""
    end
    return val
end

--[[
@function set_config
@summary 设置配置值并发布变更事件
@param key 配置键名
@param value 配置值
@return boolean 是否设置成功
]]
local function sc(key, val)
    if not finit then
        log.warn("scfg", "fskv未初始化，尝试初始化")
        if not ifk() then
            return false
        end
    end

    local result = fskv.set(key, val)
    if result then
        log.info("scfg", "配置已保存", key, val)
        -- 发布配置变更事件
        sys.publish("CONFIG_CHANGED", key, val)
    else
        log.error("scfg", "配置保存失败", key)
    end
    return result
end

-- ==================== 设备名称相关接口 ====================

--[[
@function get_device_name
@summary 获取设备名称
@return string 设备名称
]]
local function gdv()
    return gc(CK.DEVICE_NAME)
end

--[[
@function set_device_name
@summary 设置设备名称
@param name 设备名称
@return boolean 是否设置成功
]]
local function sdv(name)
    return sc(CK.DEVICE_NAME, name)
end

-- ==================== 事件处理 ====================

-- 订阅获取设备名称事件
sys.subscribe("CONFIG_GET_DEVICE_NAME", function()
    local dn = gdv()
    sys.publish("CONFIG_DEVICE_NAME_VALUE", dn)
    log.info("scfg", "上报设备名称", dn)
end)

-- 订阅设置设备名称事件
sys.subscribe("CONFIG_SET_DEVICE_NAME", function(name)
    if name and #name > 0 then
        sdv(name)
    else
        log.warn("scfg", "设置设备名称失败，名称无效")
    end
end)

ifk()
