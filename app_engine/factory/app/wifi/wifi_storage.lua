--[[
@module  wifi_storage
@summary WiFi存储模块（fskv封装）
@version 1.1
@date    2026.05.29
@author  江访
@usage
-- 完全通过事件交互，不对外提供函数
-- 接收的事件：
--   WIFI_STORAGE_INIT_REQ: 初始化请求
--   WIFI_STORAGE_SAVE_REQ: {ssid, password, advanced_config, bssid}
--   WIFI_STORAGE_LOAD_REQ
--   WIFI_STORAGE_SET_ENABLED_REQ: {enabled}
--   WIFI_STORAGE_ADD_TO_SAVED_LIST_REQ: {ssid, password} - 添加到已保存网络列表
--   WIFI_STORAGE_GET_SAVED_LIST_REQ: 获取已保存网络列表
--   WIFI_STORAGE_MARK_CONNECTED_REQ: {ssid, bssid} - 标记连接成功，更新bssid和连接状态
--   WIFI_STORAGE_MARK_FAILED_REQ: {ssid} - 标记连接失败（仅对从未成功过的记录生效）
-- 发布的事件：
--   WIFI_STORAGE_INIT_RSP: {success}
--   WIFI_STORAGE_SAVE_RSP: {success}
--   WIFI_STORAGE_LOAD_RSP: {config}
--   WIFI_STORAGE_SET_ENABLED_RSP: {success}
--   WIFI_STORAGE_GET_SAVED_LIST_RSP: {list}
--   WIFI_STORAGE_MARK_CONNECTED_RSP: {success, count}
--   WIFI_STORAGE_MARK_FAILED_RSP: {success, count}
]]

local CONFIG_KEY = "wifi_app_config"
local SAVED_LIST_FILE = "/wifi_saved_list.json"

local config = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
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
@function save_saved_list
@summary 将已保存网络列表保存到文件
@return boolean - 保存成功返回true，失败返回false
]]
local function save_saved_list()
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
@function load_saved_list
@summary 从文件加载已保存网络列表
]]
local function load_saved_list()
    local f = io.open(SAVED_LIST_FILE, "r")
    log.info("wifi_storage", "尝试从已保存网络列表文件加载:", SAVED_LIST_FILE)
    if f then
        log.info("wifi_storage", "已保存网络列表文件打开成功")
        local data = f:read("*a")
        f:close()
        if data then
            local ok_decoded, decoded_list = pcall(json.decode, data)
            if ok_decoded and type(decoded_list) == "table" then
                saved_list = decoded_list
                log.info("wifi_storage", "已保存网络列表加载成功，数量:", #saved_list)
                return
            end
        end
    end
    saved_list = {}
    log.info("wifi_storage", "已保存网络列表文件加载失败，使用默认值")
end

--[[
@function add_saved_network
@summary 添加网络到已保存网络列表
@param string ssid - WiFi SSID
@param string password - WiFi密码
@param table adv_config - 高级配置（可选）
@param string bssid - 热点BSSID（可选，用于同SSID多AP场景区分）
@note 新添加的记录 last_connect_ok 初始为 nil（未验证状态）
      更新已有记录时保留 bssid 和 last_connect_ok（仅由 MARK 事件修改）
]]
local function add_saved_network(ssid, password, adv_config, bssid)
    if not ssid or ssid == "" then
        log.error("wifi_storage", "添加已保存网络时，SSID不能为空")
        return
    end
    -- 归一化BSSID：去除分隔符、转小写，便于比对
    local norm_bssid = nil
    if bssid and bssid ~= "" then
        norm_bssid = bssid:lower():gsub("[^0-9a-f]", "")
        if #norm_bssid < 12 then norm_bssid = nil end
    end
    for i, entry in ipairs(saved_list) do
        if entry.ssid == ssid then
            -- 更新密码和高级配置
            saved_list[i].password = password
            if adv_config then
                saved_list[i].need_ping = adv_config.need_ping
                saved_list[i].local_network_mode = adv_config.local_network_mode
                saved_list[i].ping_ip = adv_config.ping_ip
                saved_list[i].ping_time = adv_config.ping_time
                saved_list[i].auto_socket_switch = adv_config.auto_socket_switch
            end
            -- 如果传了新的bssid值则更新bssid
            if bssid and norm_bssid then
                saved_list[i].bssid = bssid
            end
            -- 更新条目时，如果上次连接失败过，重置为nil，给新密码一次机会
            -- 保留 last_connect_ok = true 的条目不变
            if saved_list[i].last_connect_ok == false then
                saved_list[i].last_connect_ok = nil
            end
            save_saved_list()
            log.info("wifi_storage", "更新已保存网络:", ssid)
            return
        end
    end
    -- 新增条目：last_connect_ok = nil（未验证），需连接成功后由 MARK_CONNECTED 设为 true
    local entry = {ssid = ssid, password = password, last_connect_ok = nil}
    if bssid and norm_bssid then
        entry.bssid = bssid
    end
    if adv_config then
        entry.need_ping = adv_config.need_ping
        entry.local_network_mode = adv_config.local_network_mode
        entry.ping_ip = adv_config.ping_ip
        entry.ping_time = adv_config.ping_time
        entry.auto_socket_switch = adv_config.auto_socket_switch
    end
    table.insert(saved_list, entry)
    save_saved_list()
    log.info("wifi_storage", "添加已保存网络:", ssid, "last_connect_ok: nil（未验证）")
end

--[[
@function mark_connected
@summary 标记网络连接成功，更新BSSID和连接状态
@param string ssid - WiFi SSID
@param string bssid - 连接成功的BSSID（可选）
@return number - 更新的条目数量
]]
local function mark_connected(ssid, bssid)
    if not ssid or ssid == "" then return 0 end
    local count = 0
    local norm_bssid = nil
    if bssid and bssid ~= "" then
        norm_bssid = bssid:lower():gsub("[^0-9a-f]", "")
        if #norm_bssid < 12 then norm_bssid = nil end
    end
    for i, entry in ipairs(saved_list) do
        if entry.ssid == ssid then
            saved_list[i].last_connect_ok = true
            if bssid and norm_bssid then
                saved_list[i].bssid = bssid
            end
            count = count + 1
        end
    end
    if count > 0 then
        save_saved_list()
        log.info("wifi_storage", "标记连接成功:", ssid, "bssid:", bssid, "更新条目:", count)
    end
    return count
end

--[[
@function mark_failed
@summary 标记网络连接失败（仅对从未成功连接过的记录生效）
@param string ssid - WiFi SSID
@return number - 更新的条目数量
@note 如果该SSID曾成功连接过（last_connect_ok == true），不覆盖
      这是为了防止信号波动导致的误标记
]]
local function mark_failed(ssid)
    if not ssid or ssid == "" then return 0 end
    local count = 0
    for i, entry in ipairs(saved_list) do
        if entry.ssid == ssid then
            -- 只有从未成功连接过的记录才标记失败
            -- 曾经成功过的保留 true（可能是临时信号问题）
            if entry.last_connect_ok ~= true then
                saved_list[i].last_connect_ok = false
                count = count + 1
            end
        end
    end
    if count > 0 then
        save_saved_list()
        log.info("wifi_storage", "标记连接失败:", ssid, "更新条目:", count)
    end
    return count
end

--[[
@function on_init_req
@summary 处理 WIFI_STORAGE_INIT_REQ 事件处理
]]
local function on_init_request()
    log.info("wifi_storage", "收到初始化请求")
    local ok = fskv.init()
    if ok then
        log.info("wifi_storage", "fskv 初始化成功")
        load_from_fskv()
        load_saved_list()

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
            if data.ssid and data.ssid ~= "" and data.password ~= nil then
                add_saved_network(data.ssid, data.password, data.advanced_config, data.bssid)
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
            add_saved_network(data.ssid, data.password, data.advanced_config, data.bssid)
        end)

        sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_REQ", function()
            sys.publish("WIFI_STORAGE_GET_SAVED_LIST_RSP", {list = saved_list})
        end)

        -- 新事件：标记连接成功
        sys.subscribe("WIFI_STORAGE_MARK_CONNECTED_REQ", function(data)
            local count = mark_connected(data.ssid, data.bssid)
            sys.publish("WIFI_STORAGE_MARK_CONNECTED_RSP", {success = count > 0, count = count})
        end)

        -- 新事件：标记连接失败（仅标记从未成功过的）
        sys.subscribe("WIFI_STORAGE_MARK_FAILED_REQ", function(data)
            local count = mark_failed(data.ssid)
            sys.publish("WIFI_STORAGE_MARK_FAILED_RSP", {success = count > 0, count = count})
        end)
    else
        log.error("wifi_storage", "fskv 初始化失败，使用默认配置继续运行")
        -- 初始化失败时，仍然注册事件处理器并发布加载响应
        -- 使用默认配置，确保 wifi_app 不会进入僵尸状态
        sys.subscribe("WIFI_STORAGE_SAVE_REQ", function(data)
            log.warn("wifi_storage", "fskv 不可用，跳过保存:", data.ssid)
        end)

        sys.subscribe("WIFI_STORAGE_LOAD_REQ", function()
            sys.publish("WIFI_STORAGE_LOAD_RSP", {config = config})
        end)

        sys.subscribe("WIFI_STORAGE_SET_ENABLED_REQ", function(data)
            config.wifi_enabled = data.enabled
            sys.publish("WIFI_STORAGE_SET_ENABLED_RSP", {success = false, enabled = config.wifi_enabled})
        end)

        sys.subscribe("WIFI_STORAGE_ADD_TO_SAVED_LIST_REQ", function(data)
            log.warn("wifi_storage", "存储不可用，跳过添加已保存网络:", data.ssid)
        end)

        sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_REQ", function()
            sys.publish("WIFI_STORAGE_GET_SAVED_LIST_RSP", {list = {}})
        end)

        sys.subscribe("WIFI_STORAGE_MARK_CONNECTED_REQ", function(data)
            log.warn("wifi_storage", "存储不可用，跳过标记连接成功:", data.ssid)
            sys.publish("WIFI_STORAGE_MARK_CONNECTED_RSP", {success = false, count = 0})
        end)

        sys.subscribe("WIFI_STORAGE_MARK_FAILED_REQ", function(data)
            log.warn("wifi_storage", "存储不可用，跳过标记连接失败:", data.ssid)
            sys.publish("WIFI_STORAGE_MARK_FAILED_RSP", {success = false, count = 0})
        end)
    end

    sys.publish("WIFI_STORAGE_INIT_RSP", {success = ok})
    log.info("wifi_storage", "初始化完成，success:", ok)
end

log.info("wifi_storage", "等待初始化请求...")
sys.subscribe("WIFI_STORAGE_INIT_REQ", on_init_request)
