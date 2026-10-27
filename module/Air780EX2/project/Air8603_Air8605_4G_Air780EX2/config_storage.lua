--[[
@module  config_storage
@summary 通用配置持久化存储模块
@version 1.0
@date    2026.06.02
@usage
本模块基于fskv实现通用配置的持久化存储

主要功能：
1. 初始化fskv数据库
2. 通用键值对读写接口
3. 支持多种数据类型（字符串、数值、布尔值、table）

使用示例：
local config_storage = require("config_storage")

-- 保存配置
config_storage.set("fota_auto", 1)
config_storage.set("device_name", "Air780EX2")

-- 读取配置
local fota_auto = config_storage.get("fota_auto")
local device_name = config_storage.get("device_name")
]]

--============================================================
-- 模块全局变量
--============================================================

-- fskv初始化状态标志
local g_fskv_inited = false

--============================================================
-- 内部函数声明
--============================================================

-- 初始化fskv数据库
-- @return boolean: 初始化成功返回true，失败返回false
local function fskv_init()
    -- 已初始化则跳过
    if g_fskv_inited then
        return true
    end
    -- 初始化fskv
    local result = fskv.init()
    if result then
        g_fskv_inited = true
        log.info("config_storage", "fskv初始化成功")
        return true
    else
        log.error("config_storage", "fskv初始化失败")
        return false
    end
end

--============================================================
-- 公开接口函数
--============================================================

-- 保存配置到fskv
-- @param key string: 配置键名
-- @param value any: 配置值，支持string/number/boolean/table类型
-- @return boolean: 保存成功返回true，失败返回false
local function set(key, value)
    -- 参数校验
    if key == nil or key == "" then
        log.error("config_storage", "键名不能为空")
        return false
    end

    -- 确保fskv已初始化
    if not fskv_init() then
        return false
    end

    -- 保存配置到fskv
    local result = fskv.set(key, value)
    if result then
        log.info("config_storage", "配置已保存:", key, "=", value)
        return true
    else
        log.error("config_storage", "配置保存失败:", key)
        return false
    end
end

-- 从fskv读取配置
-- @param key string: 配置键名
-- @param default any: 默认值，当键不存在时返回
-- @return any: 配置值，读取失败或键不存在时返回默认值
local function get(key, default)
    -- 参数校验
    if key == nil or key == "" then
        log.error("config_storage", "键名不能为空")
        return default
    end

    -- 确保fskv已初始化
    if not fskv_init() then
        return default
    end

    -- 从fskv读取配置
    local value = fskv.get(key)
    if value ~= nil then
        -- table类型序列化显示
        if type(value) == "table" then
            log.info("config_storage", "读取配置:", key, "=", json.encode(value))
        else
            log.info("config_storage", "读取配置:", key, "=", value)
        end
        return value
    else
        log.info("config_storage", "配置不存在:", key, "，返回默认值:", default)
        return default
    end
end

-- 删除fskv中的配置
-- @param key string: 配置键名
-- @return boolean: 删除成功返回true，失败返回false
local function del(key)
    -- 参数校验
    if key == nil or key == "" then
        log.error("config_storage", "键名不能为空")
        return false
    end

    -- 确保fskv已初始化
    if not fskv_init() then
        return false
    end

    -- 删除配置
    local result = fskv.del(key)
    if result then
        log.info("config_storage", "配置已删除:", key)
        return true
    else
        log.error("config_storage", "配置删除失败:", key)
        return false
    end
end

-- 检查fskv中是否存在指定配置
-- @param key string: 配置键名
-- @return boolean: 存在返回true，不存在返回false
local function has(key)
    -- 参数校验
    if key == nil or key == "" then
        log.error("config_storage", "键名不能为空")
        return false
    end

    -- 确保fskv已初始化
    if not fskv_init() then
        return false
    end

    -- 检查配置是否存在
    local value = fskv.get(key)
    return value ~= nil
end

--============================================================
-- 模块导出
--============================================================

-- 返回模块接口
return {
    set = set,
    get = get,
    del = del,
    has = has
}
