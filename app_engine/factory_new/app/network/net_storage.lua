--[[
@module  net_storage
@summary 网络开关存储模块（fskv封装）
@version 1.0
@date    2026.10.29
@author  江访
@usage
net_storage.init()                          初始化 fskv 并读取网络开关
net_storage.load(type_list)                 按 config.network 的网络列表补齐默认开关
net_storage.get_enabled(type_name)          查询单个网络开关
net_storage.get_all()                       查询全部网络开关
net_storage.set_enabled(type_name, enable)  设置单个网络开关并落盘
net_storage.set_enabled_batch(tbl)          批量设置网络开关，一次落盘
net_storage.reset()                         清除网络开关记录，恢复默认全开

存储键 CONFIG_KEY = "net_app_config"，结构：
    net_app_config = {
        version = 1,
        enabled = { ["eth_spi"] = true, ["wifi_airlink_spi"] = false },
    }
键或字段缺失时按 true 处理。

type 属 wifi 组时同步 wifi_app_config.wifi_enabled，两个开关保持同值。
wifi_app_config 由 wifi_storage 统一维护，这里只改 wifi_enabled 字段并通知。

发布的事件：
    NET_CONFIG_CHANGED: { changed = { type_name, ... } }
]]

local CONFIG_KEY = "net_app_config"
local WIFI_CONFIG_KEY = "wifi_app_config"
local CONFIG_VERSION = 1

local net_storage = {}

local config = {
    version = CONFIG_VERSION,
    enabled = {},
}

local inited = false

--[[
@function is_wifi_type
@summary 判断网络类型是否属 wifi 组
@param string type_name - 网络类型名
@return boolean - 属 wifi 组返回true
]]
local function is_wifi_type(type_name)
    return type(type_name) == "string" and type_name:find("wifi", 1, true) ~= nil
end

--[[
@function save_to_fskv
@summary 将网络开关保存到 fskv
@return boolean - 保存成功返回true，失败返回false
]]
local function save_to_fskv()
    local result = fskv.set(CONFIG_KEY, config)
    if result then
        log.info("net_storage", "网络开关保存成功")
    else
        log.error("net_storage", "网络开关保存失败")
    end
    return result
end

--[[
@function sync_wifi_enabled
@summary 同步 wifi_app_config.wifi_enabled
@param boolean enable - WiFi 开关值
]]
local function sync_wifi_enabled(enable)
    local value = (enable == true)
    local ok, saved = pcall(fskv.get, WIFI_CONFIG_KEY)
    local wifi_cfg = (ok and type(saved) == "table") and saved or {}
    wifi_cfg.wifi_enabled = value
    fskv.set(WIFI_CONFIG_KEY, wifi_cfg)
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", { enabled = value })
end

--[[
@function load_from_fskv
@summary 从 fskv 加载网络开关
]]
local function load_from_fskv()
    local ok, saved = pcall(fskv.get, CONFIG_KEY)
    if ok and type(saved) == "table" then
        config.version = tonumber(saved.version) or CONFIG_VERSION
        if type(saved.enabled) == "table" then
            for type_name, enable in pairs(saved.enabled) do
                if type(type_name) == "string" then
                    config.enabled[type_name] = (enable == true)
                end
            end
        end
        log.info("net_storage", "网络开关加载成功")
    else
        log.info("net_storage", "无网络开关记录，使用默认全开")
    end
end

--[[
初始化网络开关存储
@return boolean - 初始化完成返回true
]]
function net_storage.init()
    if inited then return true end
    pcall(fskv.init)
    load_from_fskv()
    inited = true
    log.info("net_storage", "初始化完成")
    return true
end

--[[
按网络列表补齐默认开关，已存在的开关不覆盖
@param table type_list - 网络类型名列表，元素为 string 或 { type = "eth_spi" }
]]
function net_storage.load(type_list)
    if type(type_list) ~= "table" then return end
    local wifi_default = nil
    local ok_cfg, wifi_cfg = pcall(fskv.get, WIFI_CONFIG_KEY)
    if ok_cfg and type(wifi_cfg) == "table" and wifi_cfg.wifi_enabled ~= nil then
        wifi_default = (wifi_cfg.wifi_enabled == true)
    end
    local changed = false
    for _, item in ipairs(type_list) do
        local type_name = (type(item) == "table") and item.type or item
        if type(type_name) == "string" and type_name ~= ""
            and config.enabled[type_name] == nil then
            if is_wifi_type(type_name) and wifi_default ~= nil then
                config.enabled[type_name] = wifi_default
            else
                config.enabled[type_name] = true
            end
            changed = true
        end
    end
    if changed then save_to_fskv() end
end

--[[
查询单个网络开关
@param string type_name - 网络类型名
@return boolean - 开启返回true，关闭返回false，无记录时返回true
]]
function net_storage.get_enabled(type_name)
    if type(type_name) ~= "string" or type_name == "" then return false end
    local enable = config.enabled[type_name]
    if enable == nil then return true end
    return enable == true
end

--[[
查询全部网络开关
@return table - { [type_name] = boolean }
]]
function net_storage.get_all()
    local all = {}
    for type_name, enable in pairs(config.enabled) do
        all[type_name] = (enable == true)
    end
    return all
end

--[[
设置单个网络开关并落盘
@param string type_name - 网络类型名
@param boolean enable - 开关值
@return boolean - 保存成功返回true，失败返回false
]]
function net_storage.set_enabled(type_name, enable)
    if type(type_name) ~= "string" or type_name == "" then
        log.error("net_storage", "网络类型名为空")
        return false
    end
    local value = (enable == true)
    config.enabled[type_name] = value
    log.info("net_storage", "设置网络开关:", type_name, value)
    if is_wifi_type(type_name) then sync_wifi_enabled(value) end
    local result = save_to_fskv()
    sys.publish("NET_CONFIG_CHANGED", { changed = { type_name } })
    return result
end

--[[
批量设置网络开关，一次落盘
@param table tbl - { [type_name] = boolean }
@return boolean - 保存成功返回true，失败返回false
]]
function net_storage.set_enabled_batch(tbl)
    if type(tbl) ~= "table" then
        log.error("net_storage", "批量设置网络开关参数错误")
        return false
    end
    local changed = {}
    local wifi_value = nil
    for type_name, enable in pairs(tbl) do
        if type(type_name) == "string" and type_name ~= "" then
            local value = (enable == true)
            if config.enabled[type_name] ~= value then
                config.enabled[type_name] = value
                changed[#changed + 1] = type_name
            end
            if is_wifi_type(type_name) then wifi_value = value end
        end
    end
    if wifi_value ~= nil then sync_wifi_enabled(wifi_value) end
    local result = save_to_fskv()
    log.info("net_storage", "批量设置网络开关:", #changed)
    if #changed > 0 then
        sys.publish("NET_CONFIG_CHANGED", { changed = changed })
    end
    return result
end

--[[
清除网络开关记录，恢复默认全开
@return boolean - 保存成功返回true，失败返回false
]]
function net_storage.reset()
    config.version = CONFIG_VERSION
    config.enabled = {}
    log.info("net_storage", "网络开关已重置")
    return save_to_fskv()
end

return net_storage
