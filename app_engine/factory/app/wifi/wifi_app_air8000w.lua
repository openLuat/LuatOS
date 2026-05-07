--[[
@module  wifi_app
@summary WiFi应用模块（业务逻辑层，事件驱动）
@version 1.0
@date    2026.04.05
@author  江访
@usage
-- 接收的事件（来自UI层）：
--   WIFI_ENABLE_REQ: {enabled}
--   WIFI_SCAN_REQ
--   WIFI_CONNECT_REQ: {ssid, password, advanced_config}
--   WIFI_DISCONNECT_REQ
--   WIFI_GET_STATUS_REQ
--   WIFI_GET_CONFIG_REQ
--   WIFI_GET_SAVED_LIST_REQ: 获取已保存网络列表
-- 发布的事件（给UI层）：
--   WIFI_SCAN_STARTED, WIFI_SCAN_DONE, WIFI_SCAN_TIMEOUT
--   WIFI_CONNECTING, WIFI_CONNECTED, WIFI_DISCONNECTED
--   WIFI_STATUS_UPDATED: {status}
--   WIFI_CONFIG_RSP: {config}
--   WIFI_SAVED_LIST_RSP: {list}
-- 与storage层交互的事件：
--   WIFI_STORAGE_INIT_REQ (发送)
--   WIFI_STORAGE_INIT_RSP (接收)
--   WIFI_STORAGE_LOAD_REQ, WIFI_STORAGE_LOAD_RSP
--   WIFI_STORAGE_SAVE_REQ (发送，不等待响应)
--   WIFI_STORAGE_SET_ENABLED_REQ, WIFI_STORAGE_SET_ENABLED_RSP
]]

require "wifi_storage"
local common = require "wifi_app_common"
local exnetif = require "exnetif"

local SCAN_TIMEOUT = 10000   -- WiFi扫描超时时间（毫秒）
local UPDATE_INTERVAL = 5000 -- 网络信息更新间隔（毫秒）

local wifi_status = {        -- WiFi当前状态
    connected = false,       -- 是否已连接
    ready = false,           -- 网络是否就绪（获取到IP）
    current_ssid = "",       -- 当前连接的SSID
    rssi = "--",             -- 信号强度
    ip = "--",               -- IP地址
    netmask = "--",          -- 子网掩码
    gateway = "--",          -- 网关
    bssid = "--",            -- AP的MAC地址
    scan_results = {}        -- 扫描结果列表
}

local saved_config = {          -- 保存的WiFi配置（从storage加载）
    wifi_enabled = false,       -- WiFi功能是否启用
    ssid = "",                  -- WiFi名称
    password = "",              -- WiFi密码
    need_ping = true,           -- 是否需要通过ping来测试网络连通性
    local_network_mode = false, -- 是否为局域网模式（不连接外网）
    ping_ip = "",               -- ping目标IP地址
    ping_time = "10000",        -- ping间隔时间（毫秒）
    auto_socket_switch = true   -- 是否自动切换socket连接
}

local scan_timer = nil                  -- 扫描超时定时器
local update_timer = nil                -- 网络信息更新定时器
local last_connect_status = nil         -- 上次连接状态
local disconnect_reason = nil           -- 断开连接原因
local user_initiated_disconnect = false -- 是否用户主动断开连接
local user_initiated_connect = false    -- 是否用户主动发起连接

--[[
@function update_status
@summary 更新WiFi状态并发布事件
@param table status - 包含状态字段的对象
]]
local function update_status(status)
    if not status then
        log.error("wifi_app", "更新WiFi状态时，状态对象为空")
        return
    end
    
    for k, v in pairs(status) do
        wifi_status[k] = v
    end
    common.update_status(wifi_status, saved_config)
end

--[[
@function refresh_network_info
@summary 刷新并更新网络信息（IP、网关、子网掩码等）
]]
local function refresh_network_info()
    common.refresh_network_info(wifi_status)
end

--[[
@function handle_wifi_sta_event
@summary 处理WiFi STA事件（连接/断开等）
@param string evt - 事件类型
@param any data - 事件数据
]]
local function handle_wifi_sta_event(evt, data)
    log.info("wifi_app", "WiFi STA事件:", evt, data)
    
    if evt == "CONNECTED" then
        wifi_status.connected = true
        wifi_status.ready = false
        wifi_status.current_ssid = data
        
        sys.publish("WIFI_CONNECTED", data)
        last_connect_status = "CONNECTED"
        user_initiated_connect = false
        
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        update_timer = sys.timerLoopStart(refresh_network_info, UPDATE_INTERVAL)
        
    elseif evt == "DISCONNECTED" then
        if user_initiated_connect then
            log.info("wifi_app", "用户发起的连接失败，重置状态以允许再次弹窗")
            last_connect_status = nil
        elseif last_connect_status == "DISCONNECTED" then
            log.info("wifi_app", "已断开状态，跳过重复事件")
            return
        end
        
        if disconnect_reason == "config" then
            log.info("wifi_app", "配置前断开，跳过事件处理")
            disconnect_reason = nil
            return
        end
        
        wifi_status.connected = false
        wifi_status.ready = false
        wifi_status.current_ssid = ""
        wifi_status.rssi = "--"
        wifi_status.ip = "--"
        wifi_status.netmask = "--"
        wifi_status.gateway = "--"
        wifi_status.bssid = "--"
        
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        
        local reason = common.resolve_disconnect_reason(data)
        sys.publish("WIFI_DISCONNECTED", reason, data)
        last_connect_status = "DISCONNECTED"
        user_initiated_connect = false
        
        if user_initiated_disconnect then
            log.info("wifi_app", "用户主动断开，只进行扫描")
            user_initiated_disconnect = false
            sys.publish("WIFI_SCAN_REQ")
        end
    end
end

--[[
@function handle_ip_ready
@summary 处理IP就绪事件
@param string ip - IP地址
@param number adapter - 网卡适配器
]]
local function handle_ip_ready(ip, adapter)
    common.handle_ip_ready(ip, adapter, wifi_status, refresh_network_info)
end

--[[
@function handle_ip_lose
@summary 处理IP丢失事件
@param number adapter - 网卡适配器
]]
local function handle_ip_lose(adapter)
    common.handle_ip_lose(adapter, wifi_status)
end

--[[
@function handle_scan_done
@summary 处理WiFi扫描完成事件
]]
local function handle_scan_done()
    local st_ref = {}
    st_ref[1] = scan_timer
    common.handle_scan_done(wifi_status, st_ref)
    scan_timer = st_ref[1]
end

--[[
@function handle_scan_timeout
@summary 处理WiFi扫描超时事件
]]
local function handle_scan_timeout()
    scan_timer = nil
    sys.unsubscribe("WLAN_SCAN_DONE", handle_scan_done)
    common.handle_scan_timeout({})
end

--[[
@function auto_scan_and_verify
@summary 自动扫描并验证保存的SSID是否在附近
@return table {verified, ssid, signal} - 验证结果
]]
local function auto_scan_and_verify()
    return common.auto_scan_and_verify(saved_config)
end

--[[
@function run_auto_connect_task
@summary 运行自动连接任务
]]
local function run_auto_connect_task()
    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi开关已关闭，跳过自动连接")
        return
    end

    if wifi_status.connected then
        log.info("wifi_app", "已连接WiFi，刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    log.info("wifi_app", "开始执行开机自动连接（选择信号最强的已保存网络）")
    local verify_result = auto_scan_and_verify()

    if verify_result.verified then
        log.info("wifi_app", "自动连接到最佳网络:", verify_result.ssid, "信号:", verify_result.signal)
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = verify_result.ssid,
            password = verify_result.password,
            advanced_config = verify_result.config and {
                need_ping = verify_result.config.need_ping,
                local_network_mode = verify_result.config.local_network_mode,
                ping_ip = verify_result.config.ping_ip,
                ping_time = verify_result.config.ping_time,
                auto_socket_switch = verify_result.config.auto_socket_switch,
            }
        })
        log.info("wifi_app", "自动连接请求发送成功")
    else
        log.info("wifi_app", "附近没有已保存网络，等待手动连接")
    end
end

--[[
@function on_storage_load_rsp
@summary 处理WIFI_STORAGE_LOAD_RSP事件
@param table data - 包含config字段的响应数据
]]
local function on_storage_load_rsp(data)
    saved_config = data.config
    log.info("wifi_app", "加载配置完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)
    sys.taskInit(run_auto_connect_task)
end

local function on_storage_set_enabled_rsp(data)
    common.on_storage_set_enabled_rsp(data, saved_config)
end

--[[
@function on_enable_req
@summary 处理WIFI_ENABLE_REQ事件（WiFi开关切换）
@param table data - 包含enabled字段的数据
]]
local function on_enable_req(data)
    local enabled = data.enabled
    log.info("wifi_app", "收到开关请求:", enabled)
    
    if saved_config then
        saved_config.wifi_enabled = enabled
    end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", {enabled = enabled})
    
    if _G.model_str:find("PC") then
        if not enabled then
            wifi_status.connected = false
            wifi_status.ready = false
            wifi_status.current_ssid = ""
            wifi_status.rssi = "--"
            wifi_status.ip = "--"
            wifi_status.netmask = "--"
            wifi_status.gateway = "--"
            wifi_status.bssid = "--"
            update_status(wifi_status)
        else
            log.info("wifi_app", "正在开启WiFi网卡")
            if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
                if wifi_status.connected then
                    log.info("wifi_app", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                    sys.taskInit(run_auto_connect_task)
                end
            end
        end
        return
    end
    
    if not enabled then
        log.info("wifi_app", "正在关闭WiFi网卡")
        exnetif.close(nil, socket.LWIP_STA)
        wifi_status.connected = false
        wifi_status.ready = false
        wifi_status.current_ssid = ""
        wifi_status.rssi = "--"
        wifi_status.ip = "--"
        wifi_status.netmask = "--"
        wifi_status.gateway = "--"
        wifi_status.bssid = "--"
        wifi_status.scan_results = {}
        update_status(wifi_status)
    else
        log.info("wifi_app", "正在开启WiFi网卡")
        if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
            if wifi_status.connected then
                log.info("wifi_app", "已连接WiFi，只进行扫描")
                sys.publish("WIFI_SCAN_REQ")
            else
                log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                sys.taskInit(run_auto_connect_task)
            end
        end
    end
end

--[[
@function on_scan_req
@summary 处理WIFI_SCAN_REQ事件（开始扫描）
]]
local function on_scan_req()
    log.info("wifi_app", "收到扫描请求")
    
    if _G.model_str:find("PC") then
        sys.publish("WIFI_SCAN_STARTED")
        sys.taskInit(function()
            sys.wait(1500)
            local mock_results = {
                { ssid = "ChinaNet-5G", rssi = -45, channel = 149 },
                { ssid = "TP-LINK_ABC", rssi = -62, channel = 6 },
                { ssid = "CMCC-8888", rssi = -58, channel = 11 },
                { ssid = "HUAWEI-1234", rssi = -70, channel = 1 },
            }
            wifi_status.scan_results = mock_results
            sys.publish("WIFI_SCAN_DONE", mock_results)
        end)
        return
    end
    
    wlan.init()
    wlan.scan()
    
    if scan_timer then
        sys.timerStop(scan_timer)
    end
    scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
    
    sys.publish("WIFI_SCAN_STARTED")
end

--[[
@function on_connect_req
@summary 处理WIFI_CONNECT_REQ事件（连接WiFi）
@param table data - 包含ssid, password, advanced_config字段的数据
]]
local function on_connect_req(data)
    local ssid = data.ssid
    local password = data.password
    local advanced_config = data.advanced_config
    
    log.info("wifi_app", "收到连接请求:", ssid)
    user_initiated_connect = true
    
    if not ssid or ssid == "" then
        sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
        return
    end
    if not password or password == "" then
        sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
        return
    end
    
    if saved_config and not saved_config.wifi_enabled then
        log.warn("wifi_app", "WiFi已关闭，无法连接")
        return
    end
    
    sys.publish("WIFI_STORAGE_SAVE_REQ", {
        ssid = ssid,
        password = password,
        advanced_config = advanced_config
    })
    
    if _G.model_str:find("PC") then
        sys.publish("WIFI_CONNECTING", ssid)
        sys.taskInit(function()
            sys.wait(2000)
            local success = math.random(100) > 20
            if success then
                wifi_status.connected = true
                wifi_status.current_ssid = ssid
                wifi_status.rssi = tostring(-50 - math.random(20))
                wifi_status.bssid = string.format("A0:B1:C2:D3:E4:%02X", math.random(255))
                wifi_status.ip = string.format("192.168.1.%d", math.random(2, 254))
                wifi_status.netmask = "255.255.255.0"
                wifi_status.gateway = "192.168.1.1"
                wifi_status.ready = true
                sys.publish("WIFI_CONNECTED", ssid)
                sys.wait(500)
                update_status(wifi_status)
            else
                wifi_status.connected = false
                wifi_status.current_ssid = ""
                wifi_status.ready = false
                wifi_status.ip = "--"
                wifi_status.netmask = "--"
                wifi_status.gateway = "--"
                wifi_status.bssid = "--"
                wifi_status.rssi = "--"
                update_status(wifi_status)
                sys.publish("WIFI_DISCONNECTED", "密码错误或连接超时", -1)
            end
        end)
        return
    end
    
    sys.publish("WIFI_CONNECTING", ssid)
    disconnect_reason = "config"
    exnetif.close(nil, socket.LWIP_STA)
    
    local wifi_config = {
        ssid = ssid,
        password = password
    }
    
    if saved_config then
        if saved_config.need_ping ~= nil then
            wifi_config.need_ping = saved_config.need_ping
        end
        if saved_config.local_network_mode ~= nil then
            wifi_config.local_network_mode = saved_config.local_network_mode
        end
        if saved_config.ping_ip ~= nil and saved_config.ping_ip ~= "" then
            wifi_config.ping_ip = saved_config.ping_ip
        end
        if saved_config.ping_time ~= nil and saved_config.ping_time ~= "" then
            wifi_config.ping_time = tonumber(saved_config.ping_time) or 10000
        end
        if saved_config.auto_socket_switch ~= nil then
            wifi_config.auto_socket_switch = saved_config.auto_socket_switch
        end
    end
    
    local result = exnetif.set_priority_order({
        {
            WIFI = wifi_config
        }
    })
    
    if result then
        log.info("wifi_app", "WiFi连接参数配置成功")
    else
        log.error("wifi_app", "WiFi连接参数配置失败")
        sys.publish("WIFI_DISCONNECTED", "连接参数配置失败", -5)
    end
end

--[[
@function on_disconnect_req
@summary 处理WIFI_DISCONNECT_REQ事件（断开连接）
]]
local function on_disconnect_req()
    log.info("wifi_app", "收到断开请求")
    user_initiated_disconnect = true
    
    if _G.model_str:find("PC") then
        wifi_status.connected = false
        wifi_status.current_ssid = ""
        wifi_status.ready = false
        wifi_status.ip = "--"
        wifi_status.netmask = "--"
        wifi_status.gateway = "--"
        wifi_status.bssid = "--"
        wifi_status.rssi = "--"
        update_status(wifi_status)
        sys.publish("WIFI_SCAN_REQ")
        return
    end
    
    disconnect_reason = "user"
    exnetif.close(nil, socket.LWIP_STA)
    disconnect_reason = nil
end

--[[
@function on_get_status_req
@summary 处理WIFI_GET_STATUS_REQ事件（获取当前状态）
]]
local function on_get_status_req()
    common.on_get_status_req(wifi_status, saved_config)
end

--[[
@function on_get_config_req
@summary 处理WIFI_GET_CONFIG_REQ事件（获取配置）
]]
local function on_get_config_req()
    common.on_get_config_req(saved_config)
end

--[[
@function on_get_saved_list_req
@summary 处理WIFI_GET_SAVED_LIST_REQ事件（获取已保存网络列表）
]]
local function on_get_saved_list_req()
    common.on_get_saved_list_req(saved_config)
end

local function on_storage_get_saved_list_rsp(data)
    common.on_storage_get_saved_list_rsp(data)
end

--[[
@function on_storage_init_rsp
@summary 处理WIFI_STORAGE_INIT_RSP事件，storage初始化完成后继续app初始化
@param table data - 包含success字段的响应数据
]]
local function on_storage_init_rsp(data)
    common.on_storage_init_rsp(data)
end

--[[
@function init
@summary 初始化应用模块，先初始化storage，再继续app初始化
]]
local function init()
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_init_rsp)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

-- 订阅所有事件（放在文件末尾，确保所有函数都已定义）
sys.subscribe("WLAN_STA_INC", handle_wifi_sta_event)
sys.subscribe("WLAN_SCAN_DONE", handle_scan_done)
sys.subscribe("IP_READY", handle_ip_ready)
sys.subscribe("IP_LOSE", handle_ip_lose)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", on_storage_load_rsp)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", on_storage_set_enabled_rsp)
sys.subscribe("WIFI_ENABLE_REQ", on_enable_req)
sys.subscribe("WIFI_SCAN_REQ", on_scan_req)
sys.subscribe("WIFI_CONNECT_REQ", on_connect_req)
sys.subscribe("WIFI_DISCONNECT_REQ", on_disconnect_req)
sys.subscribe("WIFI_GET_STATUS_REQ", on_get_status_req)
sys.subscribe("WIFI_GET_CONFIG_REQ", on_get_config_req)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", on_get_saved_list_req)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", on_storage_get_saved_list_rsp)

sys.taskInit(init)
