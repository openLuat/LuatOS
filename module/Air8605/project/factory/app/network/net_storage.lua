--[[
@module  net_storage
@summary 网络开关存储模块（fskv封装）
@version 1.1
@date    2026.11.09
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
        version = 2,
        enabled = { ["eth_spi"] = true, ["wifi_airlink_spi"] = false },
    }
键或字段缺失时按 true 处理（WiFi 组同样默认开启）。
v1 → v2 迁移：v1 曾把 wifi_app_config.wifi_enabled 这个旧镜像当 WiFi 默认值落盘，
迁移时把 WiFi 组开关一次性恢复开启，避免仅 WiFi 机型首启即「已关闭」还得重启才能用。

type 属 wifi 组时同步 wifi_app_config.wifi_enabled，两个开关保持同值。
wifi_app_config 由 wifi_storage 统一维护，这里只改 wifi_enabled 字段并通知。
开关真源是本模块；wifi_app_real 开机按 NET_APP_CONFIG 对齐后再决定是否自动连接。

发布的事件：
    NET_CONFIG_CHANGED: { changed = { type_name, ... } }
]]

local CONFIG_KEY = "net_app_config"
local WIFI_CONFIG_KEY = "wifi_app_config"
-- v2：WiFi 组默认开启，并修正 v1 把旧镜像值写成「已关闭」的记录
local CONFIG_VERSION = 2

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
@summary 从 fskv 加载网络开关，并把 v1 记录迁移到 v2
@note v1 曾把 wifi_app_config.wifi_enabled（旧固件默认 false 的镜像）当成 WiFi 默认值并落盘，
      结果仅 WiFi 机型首次开机就被记成「已关闭」，用户只能进网络设置打开再重启。
      v1→v2 迁移把 WiFi 组开关一次性恢复成开启，之后的用户操作不再被覆盖。
]]
local function load_from_fskv()
    local ok, saved = pcall(fskv.get, CONFIG_KEY)
    if ok and type(saved) == "table" then
        local saved_version = tonumber(saved.version) or 1
        config.version = saved_version
        if type(saved.enabled) == "table" then
            for type_name, enable in pairs(saved.enabled) do
                if type(type_name) == "string" then
                    config.enabled[type_name] = (enable == true)
                end
            end
        end
        log.info("net_storage", "网络开关加载成功, version:", saved_version)
        if saved_version < CONFIG_VERSION then
            for type_name in pairs(config.enabled) do
                if is_wifi_type(type_name) then
                    config.enabled[type_name] = true
                end
            end
            config.version = CONFIG_VERSION
            save_to_fskv()
            log.info("net_storage", "网络开关已迁移到 v" .. CONFIG_VERSION, "WiFi 组恢复开启")
        end
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
@note 缺失记录一律默认开启（含 WiFi），与 WiFi 业务层默认值保持一致：
      仅 WiFi / 仅 4G 机型首次开机就能直接联网，不需要先开开关再重启。
      这里不再从 wifi_app_config.wifi_enabled 迁移取值——那只是本模块写出的镜像，
      老固件残留的 false 会让网络设置页开关、WiFi 连接管理两处状态互相打架。
]]
function net_storage.load(type_list)
    if type(type_list) ~= "table" then return end
    local changed = false
    for _, item in ipairs(type_list) do
        local type_name = (type(item) == "table") and item.type or item
        if type(type_name) == "string" and type_name ~= ""
            and config.enabled[type_name] == nil then
            config.enabled[type_name] = true
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
