--[[
@module  wifi_storage
@summary WiFi存储模块（fskv封装）
@version 1.0
@date    2026.04.05
@author  江访
@usage
-- 完全通过事件交互，不对外提供函数
-- 接收的事件：
--   WIFI_STORAGE_INIT_REQ: 初始化请求
--   WIFI_STORAGE_SAVE_REQ: {ssid, password, advanced_config}
--   WIFI_STORAGE_LOAD_REQ
--   WIFI_STORAGE_SET_ENABLED_REQ: {enabled}
--   WIFI_STORAGE_ADD_TO_SAVED_LIST_REQ: {ssid, password} - 添加到已保存网络列表
--   WIFI_STORAGE_GET_SAVED_LIST_REQ: 获取已保存网络列表
-- 发布的事件：
--   WIFI_STORAGE_INIT_RSP: {success}
--   WIFI_STORAGE_SAVE_RSP: {success}
--   WIFI_STORAGE_LOAD_RSP: {config}
--   WIFI_STORAGE_SET_ENABLED_RSP: {success}
--   WIFI_STORAGE_GET_SAVED_LIST_RSP: {list}
]]

local CONFIG_KEY = "wifi_app_config"
local SAVED_LIST_FILE = "/wifi_saved_list.json"

local config = {
    wifi_enabled = false,       -- WiFi功能是否启用
    ssid = "",                  -- WiFi名称
    password = "",              -- WiFi密码
    need_ping = true,           -- 是否需要通过ping来测试网络连通性
    local_network_mode = false, -- 是否为局域网模式（不连接外网）
    ping_ip = "",               -- ping目标IP地址
    ping_time = "10000",        -- ping间隔时间（毫秒）
    auto_socket_switch = true   -- 是否自动切换socket连接
}

local saved_list = {}

--[[
@function save_to_fskv
@summary 将config 保存配置到 fskv
@return boolean - 保存成功返回true，失败返回false
]]
local function save_to_fskv()
    local result = fskv.set(CONFIG_KEY, config)
    if result then
        log.info("wifi_storage", "配置保存成功")
    else
        log.error("wifi_storage", "配置保存失败")
    end
    return result
end

--[[
@function load_from_fskv
@summary 从 fskv 加载配置
]]
local function load_from_fskv()
    local loaded_config = fskv.get(CONFIG_KEY)
    if loaded_config then
        for k, v in pairs(loaded_config) do
            if config[k] ~= nil then
                config[k] = v
            end
        end
        log.info("wifi_storage", "配置加载成功:", config.ssid)
    else
        log.info("wifi_storage", "配置加载失败，使用默认配置")
    end
end

--[[
@function save_saved_list_to_file
@summary 将已保存网络列表保存到文件
@return boolean - 保存成功返回true，失败返回false
]]
local function save_saved_list_to_file()
    local data = json.encode(saved_list)
    local f = io.open(SAVED_LIST_FILE, "w")
    if f then
        f:write(data)
        f:close()
        log.info("wifi_storage", "已保存网络列表保存成功，数量:", #saved_list)
        return true
    else
        log.error("wifi_storage", "已保存网络列表保存失败")
        return false
    end
end

--[[
@function load_saved_list_from_file
@summary 从文件加载已保存网络列表
]]
local function load_saved_list_from_file()
    local f = io.open(SAVED_LIST_FILE, "r")
    log.info("wifi_storage", "尝试从已保存网络列表文件加载:", SAVED_LIST_FILE)
    if f then
        log.info("wifi_storage", "已保存网络列表文件打开成功")
        local data = f:read("*a")
        f:close()
        if data then
            local ok, list = pcall(json.decode, data)
            if ok and type(list) == "table" then
                saved_list = list
                log.info("wifi_storage", "已保存网络列表加载成功，数量:", #saved_list)
                return
            end
        end
    end
    saved_list = {}
    log.info("wifi_storage", "已保存网络列表文件加载失败，使用默认值")
end

--[[
@function add_to_saved_list
@summary 添加网络到已保存网络列表
@param string ssid - WiFi SSID
@param string password - WiFi密码
@param table advanced_config - 高级配置（可选）
]]
local function add_to_saved_list(ssid, password, advanced_config)
    if not ssid or ssid == "" then
        log.error("wifi_storage", "添加已保存网络时，SSID不能为空")
        return
    end

    for i, item in ipairs(saved_list) do
        if item.ssid == ssid then
            saved_list[i].password = password
            if advanced_config then
                saved_list[i].need_ping = advanced_config.need_ping
                saved_list[i].local_network_mode = advanced_config.local_network_mode
                saved_list[i].ping_ip = advanced_config.ping_ip
                saved_list[i].ping_time = advanced_config.ping_time
                saved_list[i].auto_socket_switch = advanced_config.auto_socket_switch
            end
            save_saved_list_to_file()
            log.info("wifi_storage", "更新已保存网络:", ssid)
            return
        end
    end

    local item = {ssid = ssid, password = password}
    if advanced_config then
        item.need_ping = advanced_config.need_ping
        item.local_network_mode = advanced_config.local_network_mode
        item.ping_ip = advanced_config.ping_ip
        item.ping_time = advanced_config.ping_time
        item.auto_socket_switch = advanced_config.auto_socket_switch
    end
    table.insert(saved_list, item)
    save_saved_list_to_file()
    log.info("wifi_storage", "添加已保存网络:", ssid)
end

--[[
@function on_init_req
@summary 处理 WIFI_STORAGE_INIT_REQ 事件处理
]]
local function on_init_req()
    log.info("wifi_storage", "收到初始化请求")
    local success = fskv.init()
    if success then
        log.info("wifi_storage", "fskv 初始化成功")
        load_from_fskv()
        load_saved_list_from_file()

        sys.subscribe("WIFI_STORAGE_SAVE_REQ", function(data)
            log.info("wifi_storage", "收到保存请求，ssid:", data.ssid)
            if data.ssid ~= nil then
                config.ssid = data.ssid
            end
            if data.password ~= nil then
                config.password = data.password
            end
            if data.advanced_config and type(data.advanced_config) == "table" then
                if data.advanced_config.need_ping ~= nil then
                    config.need_ping = data.advanced_config.need_ping
                end
                if data.advanced_config.local_network_mode ~= nil then
                    config.local_network_mode = data.advanced_config.local_network_mode
                end
                if data.advanced_config.ping_ip ~= nil then
                    config.ping_ip = data.advanced_config.ping_ip
                end
                if data.advanced_config.ping_time ~= nil then
                    config.ping_time = data.advanced_config.ping_time
                end
                if data.advanced_config.auto_socket_switch ~= nil then
                    config.auto_socket_switch = data.advanced_config.auto_socket_switch
                end
            end

            if data.ssid and data.ssid ~= "" and data.password then
                add_to_saved_list(data.ssid, data.password, data.advanced_config)
            end

            local save_result = save_to_fskv()
            log.info("wifi_storage", "保存结果:", save_result, "当前ssid:", config.ssid)
        end)

        sys.subscribe("WIFI_STORAGE_LOAD_REQ", function()
            sys.publish("WIFI_STORAGE_LOAD_RSP", {config = config})
        end)

        sys.subscribe("WIFI_STORAGE_SET_ENABLED_REQ", function(data)
            config.wifi_enabled = data.enabled
            local save_result = save_to_fskv()
            sys.publish("WIFI_STORAGE_SET_ENABLED_RSP", {success = save_result, enabled = config.wifi_enabled})
        end)

        sys.subscribe("WIFI_STORAGE_ADD_TO_SAVED_LIST_REQ", function(data)
            add_to_saved_list(data.ssid, data.password)
        end)

        sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_REQ", function()
            sys.publish("WIFI_STORAGE_GET_SAVED_LIST_RSP", {list = saved_list})
        end)
    else
        log.error("wifi_storage", "fskv 初始化失败")
    end

    sys.publish("WIFI_STORAGE_INIT_RSP", {success = success})
    log.info("wifi_storage", "初始化完成，success:", success)
end

log.info("wifi_storage", "等待初始化请求...")
sys.subscribe("WIFI_STORAGE_INIT_REQ", on_init_req)
