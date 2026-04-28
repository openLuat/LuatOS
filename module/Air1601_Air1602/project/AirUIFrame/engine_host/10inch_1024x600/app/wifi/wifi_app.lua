--[[
@module  wifi_app
@summary WiFi应用模块（业务逻辑层，事件驱动）
@version 1.0
@date    2026.04.05
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

local SCAN_TIMEOUT = 20000   -- WiFi扫描超时时间（毫秒），airlink SPI速度慢，给足时间
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

local wifi_initialized = false          -- airlink+wlan硬件是否已初始化
local wifi_init_in_progress = false     -- 硬件初始化是否正在进行中
local scan_in_progress = false          -- 扫描是否正在进行中

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
    
    local log_status = {
        connected = wifi_status.connected,
        ready = wifi_status.ready,
        current_ssid = wifi_status.current_ssid,
        rssi = wifi_status.rssi,
        ip = wifi_status.ip,
        netmask = wifi_status.netmask,
        gateway = wifi_status.gateway,
        bssid = wifi_status.bssid
    }
    log.info("wifi_app", "WiFi状态更新:", json.encode(log_status))
    
    if saved_config then
        log_status.wifi_enabled = saved_config.wifi_enabled
    end
    sys.publish("WIFI_STATUS_UPDATED", log_status)
end

--[[
@function refresh_network_info
@summary 刷新并更新网络信息（IP、网关、子网掩码等）
]]
local function refresh_network_info()
    if not socket.adapter(socket.LWIP_STA) then
        log.warn("wifi_app", "WiFi网卡未就绪")
        return
    end
    
    local wlan_info = wlan.getInfo()
    if wlan_info then
        if wlan_info.rssi then
            wifi_status.rssi = wlan_info.rssi
        end
        if wlan_info.bssid then
            wifi_status.bssid = wlan_info.bssid
        end
        if wlan_info.gw then
            wifi_status.gateway = wlan_info.gw
        end
    end
    
    local ip, netmask, gateway = socket.localIP(socket.LWIP_STA)
    if ip then
        wifi_status.ip = ip
        wifi_status.netmask = netmask
        wifi_status.gateway = gateway
        wifi_status.ready = true
    else
        wifi_status.ready = false
    end
    
    update_status(wifi_status)
end

--[[
@function init_wifi_hardware_task
@summary 初始化airlink+wlan硬件（必须在task中运行，因为使用了sys.wait）
]]
local function init_wifi_hardware_task()
    if wifi_initialized then return end

    log.info("wifi_app", "初始化airlink+wlan硬件")

    airlink.config(airlink.CONF_SPI_ID, 1)
    airlink.config(airlink.CONF_SPI_CS, 8)
    airlink.config(airlink.CONF_SPI_RDY, 14)
    airlink.config(airlink.CONF_SPI_SPEED, 2 * 1000000)
    airlink.init()

    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

    airlink.start(airlink.MODE_SPI_MASTER)

    gpio.setup(55, 0)
    log.info("wifi_app", "拉低复位引脚，等待500ms")
    sys.wait(500)
    gpio.setup(55, 1)
    log.info("wifi_app", "拉高复位引脚")

    while not airlink.ready() do
        log.info("wifi_app", "等待airlink就绪...")
        sys.wait(100)
    end
    log.info("wifi_app", "airlink就绪")

    wlan.init()
    wlan.setMode(wlan.STATIONAP)

    wifi_initialized = true
    wifi_init_in_progress = false
    log.info("wifi_app", "airlink+wlan硬件初始化完成")
    sys.publish("WIFI_HW_READY")
end

--[[
@function ensure_wifi_init
@summary 确保WiFi硬件已初始化，未初始化则启动初始化task
]]
local function ensure_wifi_init()
    if wifi_initialized then return true end
    if not wifi_init_in_progress then
        wifi_init_in_progress = true
        sys.taskInit(init_wifi_hardware_task)
    end
    return false
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
        
        local reason = "未知错误"
        if data == 260 then reason = "DHCP超时"
        elseif data == 259 then reason = "程序主动断开"
        elseif data == 258 then reason = "密码错误"
        elseif data == 257 then reason = "找不到对应SSID"
        elseif data == 256 then reason = "信号丢失"
        elseif data == 3 then reason = "软件主动断开"
        end
        
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
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP就绪:", ip)
        refresh_network_info()
    end
end

--[[
@function handle_ip_lose
@summary 处理IP丢失事件
@param number adapter - 网卡适配器
]]
local function handle_ip_lose(adapter)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP断开")
        wifi_status.ready = false
        wifi_status.ip = "--"
        wifi_status.netmask = "--"
        wifi_status.gateway = "--"
        update_status(wifi_status)
    end
end

--[[
@function handle_scan_done
@summary 处理WiFi扫描完成事件
]]
local function handle_scan_done()
    if scan_timer then
        sys.timerStop(scan_timer)
        scan_timer = nil
    end
    scan_in_progress = false
    
    local results = wlan.scanResult() or {}
    
    local filtered_results = {}
    for _, wifi in ipairs(results) do
        if wifi.ssid and wifi.ssid ~= "" then
            table.insert(filtered_results, wifi)
        end
    end
    
    wifi_status.scan_results = filtered_results
    sys.publish("WIFI_SCAN_DONE", wifi_status.scan_results)
    sys.publish("WIFI_DONE",results)
    log.info("wifi_app", "扫描完成，找到", #wifi_status.scan_results, "个热点")
end

--[[
@function handle_scan_timeout
@summary 处理WiFi扫描超时事件
]]
local function handle_scan_timeout()
    scan_timer = nil
    scan_in_progress = false
    sys.publish("WIFI_SCAN_TIMEOUT")
    log.warn("wifi_app", "扫描超时")
end

--[[
@function auto_scan_and_verify
@summary 自动扫描并验证保存的SSID是否在附近
@return table {verified, ssid, signal} - 验证结果
]]
local function auto_scan_and_verify()
    log.info("wifi_app", "开始自动扫描并验证SSID")
    
    -- 执行扫描
    sys.publish("WIFI_SCAN_REQ")
    
    -- 等待扫描完成事件，超时与SCAN_TIMEOUT一致
    local scan_done, results = sys.waitUntil("WIFI_SCAN_DONE", SCAN_TIMEOUT + 5000)
    
    if not scan_done then
        log.error("wifi_app", "自动扫描超时")
        return { verified = false, ssid = saved_config.ssid, signal = 0 }
    end
    
    -- 验证保存的SSID是否在扫描结果中
    local saved_ssid = saved_config.ssid
    local found = false
    local signal = 0
    
    for _, wifi in ipairs(results or {}) do
        if wifi.ssid == saved_ssid then
            found = true
            signal = wifi.rssi or 0
            log.info("wifi_app", "找到保存的SSID:", saved_ssid, "信号:", signal)
            break
        end
    end
    
    if not found then
        log.info("wifi_app", "未找到保存的SSID:", saved_ssid)
    end
    
    return { verified = found, ssid = saved_ssid, signal = signal }
end

--[[
@function run_auto_connect_task
@summary 运行自动连接任务
]]
local function run_auto_connect_task()
    if rtos.bsp() == "PC" then
        -- PC模拟器直接跳过后面的硬件初始化
    else
        -- 检查WiFi开关状态
        if not saved_config.wifi_enabled then
            log.info("wifi_app", "WiFi开关已关闭，跳过自动连接")
            return
        end

        -- 确保airlink+wlan硬件已初始化
        ensure_wifi_init()
        if not wifi_initialized then
            sys.waitUntil("WIFI_HW_READY", 15000)
        end
        if not wifi_initialized then
            log.error("wifi_app", "airlink+wlan硬件初始化超时")
            return
        end
    end

    log.info("wifi_app", "WiFi开关已打开，执行自动连接操作")

    -- 检查是否已连接WiFi
    if wifi_status.connected then
        log.info("wifi_app", "已连接WiFi，只进行扫描刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    -- 检查是否有保存的SSID
    if not saved_config.ssid or saved_config.ssid == "" then
        log.info("wifi_app", "没有保存的SSID，跳过自动连接")
        return
    end

    log.info("wifi_app", "开始执行开机自动连接")

    -- 执行自动扫描并验证SSID
    local verify_result = auto_scan_and_verify()

    if verify_result.verified then
        log.info("wifi_app", "找到保存的SSID，开始自动连接")

        -- 自动连接
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = saved_config.ssid,
            password = saved_config.password
        })
        log.info("wifi_app", "自动连接请求发送成功")
    else
        log.info("wifi_app", "未找到保存的SSID，等待用户手动连接")
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

--[[
@function on_storage_set_enabled_rsp
@summary 处理WIFI_STORAGE_SET_ENABLED_RSP事件
@param table data - 包含success和enabled字段的响应数据
]]
local function on_storage_set_enabled_rsp(data)
    log.info("wifi_app", "设置开关响应:", data.success, data.enabled)
    if saved_config then
        saved_config.wifi_enabled = data.enabled
    end
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
    
    if rtos.bsp() == "PC" then
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
        if wifi_initialized then
            wlan.disconnect()
        end
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
        -- 确保硬件已初始化后再进行扫描/自动连接
        sys.taskInit(function()
            ensure_wifi_init()
            if not wifi_initialized then
                sys.waitUntil("WIFI_HW_READY", 15000)
            end
            if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
                if wifi_status.connected then
                    log.info("wifi_app", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                    run_auto_connect_task()
                end
            end
        end)
    end
end

--[[
@function on_scan_req
@summary 处理WIFI_SCAN_REQ事件（开始扫描）
]]
local function on_scan_req()
    log.info("wifi_app", "收到扫描请求")
    
    if rtos.bsp() == "PC" then
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
    
    -- 确保airlink+wlan硬件已初始化
    if not wifi_initialized then
        ensure_wifi_init()
        log.info("wifi_app", "等待WiFi硬件初始化完成后再扫描")
        sys.taskInit(function()
            sys.waitUntil("WIFI_HW_READY", 15000)
            if wifi_initialized and not scan_in_progress then
                scan_in_progress = true
                wlan.scan()
                if scan_timer then sys.timerStop(scan_timer) end
                scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
                sys.publish("WIFI_SCAN_STARTED")
            end
        end)
        return
    end

    if scan_in_progress then
        log.info("wifi_app", "扫描已在进行中，跳过重复请求")
        return
    end

    scan_in_progress = true
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
    
    if rtos.bsp() == "PC" then
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

    -- 确保airlink+wlan硬件已初始化（在task中执行，因为初始化用到sys.wait）
    sys.taskInit(function()
        if not wifi_initialized then
            ensure_wifi_init()
            if not wifi_initialized then
                local ok = sys.waitUntil("WIFI_HW_READY", 15000)
                if not ok then
                    log.error("wifi_app", "WiFi硬件初始化超时，无法连接")
                    sys.publish("WIFI_DISCONNECTED", "硬件初始化超时", -6)
                    return
                end
            end
        end

        -- 断开已有连接，设置标识屏蔽由此触发的DISCONNECTED事件
        -- 注意：不立即清除disconnect_reason，由handle_wifi_sta_event处理完DISCONNECTED后清除
        disconnect_reason = "config"
        wlan.disconnect()

        -- 通过wlan API直接连接WiFi
        local result = wlan.connect(ssid, password)

        if result then
            log.info("wifi_app", "WiFi连接已发起:", ssid)
        else
            log.error("wifi_app", "WiFi连接发起失败")
            sys.publish("WIFI_DISCONNECTED", "连接发起失败", -5)
        end
    end)
end

--[[
@function on_disconnect_req
@summary 处理WIFI_DISCONNECT_REQ事件（断开连接）
]]
local function on_disconnect_req()
    log.info("wifi_app", "收到断开请求")
    user_initiated_disconnect = true
    
    if rtos.bsp() == "PC" then
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
    wlan.disconnect()
    disconnect_reason = nil
end

--[[
@function on_get_status_req
@summary 处理WIFI_GET_STATUS_REQ事件（获取当前状态）
]]
local function on_get_status_req()
    log.info("wifi_app", "收到获取状态请求")
    local status = {}
    for k, v in pairs(wifi_status) do
        status[k] = v
    end
    if saved_config then
        status.wifi_enabled = saved_config.wifi_enabled
    end
    sys.publish("WIFI_STATUS_UPDATED", status)
end

--[[
@function on_get_config_req
@summary 处理WIFI_GET_CONFIG_REQ事件（获取配置）
]]
local function on_get_config_req()
    log.info("wifi_app", "收到获取配置请求")
    sys.publish("WIFI_CONFIG_RSP", {config = saved_config})
end

--[[
@function on_get_saved_list_req
@summary 处理WIFI_GET_SAVED_LIST_REQ事件（获取已保存网络列表）
]]
local function on_get_saved_list_req()
    log.info("wifi_app", "收到获取已保存网络列表请求")
    
    if rtos.bsp() == "PC" then
        local list = {
            {ssid = "TP-LINK_ABC", password = "12345678", need_ping = true, local_network_mode = false, ping_ip = "8.8.8.8", ping_time = "10000", auto_socket_switch = true},
            {ssid = "ChinaNet-5G", password = "abcdefgh", need_ping = true, local_network_mode = true, ping_ip = "192.168.1.1", ping_time = "5000", auto_socket_switch = false},
            {ssid = "CMCC-8888", password = "88888888", need_ping = false, local_network_mode = false, ping_ip = "", ping_time = "20000", auto_socket_switch = true},
            {ssid = "HUAWEI-123", password = "huawei123", need_ping = true, local_network_mode = true, ping_ip = "114.114.114.114", ping_time = "15000", auto_socket_switch = true},
            {ssid = "NETGEAR_5GHz", password = "netgear5g", need_ping = true, local_network_mode = false, ping_ip = "8.8.4.4", ping_time = "10000", auto_socket_switch = false},
        }
        sys.publish("WIFI_SAVED_LIST_RSP", {list = list})
    else
        sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    end
end

local function on_storage_get_saved_list_rsp(data)
    log.info("wifi_app", "收到已保存网络列表，数量:", #data.list)
    sys.publish("WIFI_SAVED_LIST_RSP", {list = data.list})
end

--[[
@function on_storage_init_rsp
@summary 处理WIFI_STORAGE_INIT_RSP事件，storage初始化完成后继续app初始化
@param table data - 包含success字段的响应数据
]]
local function on_storage_init_rsp(data)
    log.info("wifi_app", "storage初始化响应:", data.success)
    
    if not data.success then
        log.error("wifi_app", "storage初始化失败")
        return
    end
    
    sys.publish("WIFI_STORAGE_LOAD_REQ")
    log.info("wifi_app", "初始化完成")
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