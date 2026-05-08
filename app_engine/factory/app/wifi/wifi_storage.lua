-- Naming convention: local fns ≤5 chars, local vars ≤4 chars
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

local cfg = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
}

local sl = {}

--[[
@function save_to_fskv
@summary 将config 保存配置到 fskv
@return boolean - 保存成功返回true，失败返回false
]]
local function stf()
    local rt = fskv.set(CONFIG_KEY, cfg)
    if rt then
        log.info("wfst", "配置保存成功")
    else
        log.error("wfst", "配置保存失败")
    end
    return rt
end

--[[
@function load_from_fskv
@summary 从 fskv 加载配置
]]
local function lff()
    local lc = fskv.get(CONFIG_KEY)
    if lc then
        for k, v in pairs(lc) do
            if cfg[k] ~= nil then
                cfg[k] = v
            end
        end
        log.info("wfst", "配置加载成功:", cfg.ssid)
    else
        log.info("wfst", "配置加载失败，使用默认配置")
    end
end

--[[
@function save_saved_list_to_file
@summary 将已保存网络列表保存到文件
@return boolean - 保存成功返回true，失败返回false
]]
local function sslf()
    local dt = json.encode(sl)
    local f = io.open(SAVED_LIST_FILE, "w")
    if f then
        f:write(dt)
        f:close()
        log.info("wfst", "已保存网络列表保存成功，数量:", #sl)
        return true
    else
        log.error("wfst", "已保存网络列表保存失败")
        return false
    end
end

--[[
@function load_saved_list_from_file
@summary 从文件加载已保存网络列表
]]
local function lslf()
    local f = io.open(SAVED_LIST_FILE, "r")
    log.info("wfst", "尝试从已保存网络列表文件加载:", SAVED_LIST_FILE)
    if f then
        log.info("wfst", "已保存网络列表文件打开成功")
        local dt = f:read("*a")
        f:close()
        if dt then
            local od, ls = pcall(json.decode, dt)
            if od and type(ls) == "table" then
                sl = ls
                log.info("wfst", "已保存网络列表加载成功，数量:", #sl)
                return
            end
        end
    end
    sl = {}
    log.info("wfst", "已保存网络列表文件加载失败，使用默认值")
end

--[[
@function add_to_saved_list
@summary 添加网络到已保存网络列表
@param string ssid - WiFi SSID
@param string password - WiFi密码
@param table advanced_config - 高级配置（可选）
]]
local function asl(sd, pw, ac)
    if not sd or sd == "" then
        log.error("wfst", "添加已保存网络时，SSID不能为空")
        return
    end
    for i, it in ipairs(sl) do
        if it.ssid == sd then
            sl[i].password = pw
            if ac then
                sl[i].need_ping = ac.need_ping
                sl[i].local_network_mode = ac.local_network_mode
                sl[i].ping_ip = ac.ping_ip
                sl[i].ping_time = ac.ping_time
                sl[i].auto_socket_switch = ac.auto_socket_switch
            end
            sslf()
            log.info("wfst", "更新已保存网络:", sd)
            return
        end
    end
    local it = {ssid = sd, password = pw}
    if ac then
        it.need_ping = ac.need_ping
        it.local_network_mode = ac.local_network_mode
        it.ping_ip = ac.ping_ip
        it.ping_time = ac.ping_time
        it.auto_socket_switch = ac.auto_socket_switch
    end
    table.insert(sl, it)
    sslf()
    log.info("wfst", "添加已保存网络:", sd)
end

--[[
@function on_init_req
@summary 处理 WIFI_STORAGE_INIT_REQ 事件处理
]]
local function oinr()
    log.info("wfst", "收到初始化请求")
    local ok = fskv.init()
    if ok then
        log.info("wfst", "fskv 初始化成功")
        lff()
        lslf()

        sys.subscribe("WIFI_STORAGE_SAVE_REQ", function(dt)
            log.info("wfst", "收到保存请求，ssid:", dt.ssid)
            if dt.ssid ~= nil then
                cfg.ssid = dt.ssid
            end
            if dt.password ~= nil then
                cfg.password = dt.password
            end
            if dt.advanced_config and type(dt.advanced_config) == "table" then
                if dt.advanced_config.need_ping ~= nil then
                    cfg.need_ping = dt.advanced_config.need_ping
                end
                if dt.advanced_config.local_network_mode ~= nil then
                    cfg.local_network_mode = dt.advanced_config.local_network_mode
                end
                if dt.advanced_config.ping_ip ~= nil then
                    cfg.ping_ip = dt.advanced_config.ping_ip
                end
                if dt.advanced_config.ping_time ~= nil then
                    cfg.ping_time = dt.advanced_config.ping_time
                end
                if dt.advanced_config.auto_socket_switch ~= nil then
                    cfg.auto_socket_switch = dt.advanced_config.auto_socket_switch
                end
            end
            if dt.ssid and dt.ssid ~= "" and dt.password then
                asl(dt.ssid, dt.password, dt.advanced_config)
            end
            local sr = stf()
            log.info("wfst", "保存结果:", sr, "当前ssid:", cfg.ssid)
        end)

        sys.subscribe("WIFI_STORAGE_LOAD_REQ", function()
            sys.publish("WIFI_STORAGE_LOAD_RSP", {config = cfg})
        end)

        sys.subscribe("WIFI_STORAGE_SET_ENABLED_REQ", function(dt)
            cfg.wifi_enabled = dt.enabled
            local sr = stf()
            sys.publish("WIFI_STORAGE_SET_ENABLED_RSP", {success = sr, enabled = cfg.wifi_enabled})
        end)

        sys.subscribe("WIFI_STORAGE_ADD_TO_SAVED_LIST_REQ", function(dt)
            asl(dt.ssid, dt.password)
        end)

        sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_REQ", function()
            sys.publish("WIFI_STORAGE_GET_SAVED_LIST_RSP", {list = sl})
        end)
    else
        log.error("wfst", "fskv 初始化失败")
    end

    sys.publish("WIFI_STORAGE_INIT_RSP", {success = ok})
    log.info("wfst", "初始化完成，success:", ok)
end

log.info("wfst", "等待初始化请求...")
sys.subscribe("WIFI_STORAGE_INIT_REQ", oinr)
