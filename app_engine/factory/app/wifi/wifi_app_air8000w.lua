-- Shortened names: ws=wifi_status sc=saved_config stmr=scan_timer utmr=update_timer
--   lcs=last_connect_status dcr=disconnect_reason uidc=user_initiated_disconnect
--   uico=user_initiated_connect SCTO=SCAN_TIMEOUT UPIT=UPDATE_INTERVAL wa=wifi_app(logtag)
--   upst=update_status refni=refresh_network_info hwse=handle_wifi_sta_event
--   hipr=handle_ip_ready hipl=handle_ip_lose hscd=handle_scan_done hsct=handle_scan_timeout
--   asv=auto_scan_and_verify ract=run_auto_connect_task
--   oslr/ossr/oenr/oscr/ocnr/odcr/ogsr/ogcr/ogsl/osgs/osir=on_* handlers

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

local SCTO = 10000   -- WiFi扫描超时时间（毫秒）
local UPIT = 5000 -- 网络信息更新间隔（毫秒）

local ws = {        -- WiFi当前状态
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

local sc = {          -- 保存的WiFi配置（从storage加载）
    wifi_enabled = false,       -- WiFi功能是否启用
    ssid = "",                  -- WiFi名称
    password = "",              -- WiFi密码
    need_ping = true,           -- 是否需要通过ping来测试网络连通性
    local_network_mode = false, -- 是否为局域网模式（不连接外网）
    ping_ip = "",               -- ping目标IP地址
    ping_time = "10000",        -- ping间隔时间（毫秒）
    auto_socket_switch = true   -- 是否自动切换socket连接
}

local stmr = nil                  -- 扫描超时定时器
local utmr = nil                -- 网络信息更新定时器
local lcs = nil         -- 上次连接状态
local dcr = nil           -- 断开连接原因
local uidc = false -- 是否用户主动断开连接
local uico = false    -- 是否用户主动发起连接

--[[
@function update_status
@summary 更新WiFi状态并发布事件
@param table status - 包含状态字段的对象
]]
local function upst(status)
    if not status then
        log.error("wa", "更新WiFi状态时，状态对象为空")
        return
    end

    for k, v in pairs(status) do
        ws[k] = v
    end
    common.update_status(ws, sc)
end

--[[
@function refresh_network_info
@summary 刷新并更新网络信息（IP、网关、子网掩码等）
]]
local function refni()
    common.refresh_network_info(ws)
end

--[[
@function handle_wifi_sta_event
@summary 处理WiFi STA事件（连接/断开等）
@param string evt - 事件类型
@param any data - 事件数据
]]
local function hwse(evt, data)
    log.info("wa", "WiFi STA事件:", evt, data)

    if evt == "CONNECTED" then
        ws.connected = true
        ws.ready = false
        ws.current_ssid = data

        sys.publish("WIFI_CONNECTED", data)
        lcs = "CONNECTED"
        uico = false

        if utmr then
            sys.timerStop(utmr)
            utmr = nil
        end
        utmr = sys.timerLoopStart(refni, UPIT)

    elseif evt == "DISCONNECTED" then
        if uico then
            log.info("wa", "用户发起的连接失败，重置状态以允许再次弹窗")
            lcs = nil
        elseif lcs == "DISCONNECTED" then
            log.info("wa", "已断开状态，跳过重复事件")
            return
        end

        if dcr == "config" then
            log.info("wa", "配置前断开，跳过事件处理")
            dcr = nil
            return
        end

        ws.connected = false
        ws.ready = false
        ws.current_ssid = ""
        ws.rssi = "--"
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        ws.bssid = "--"

        if utmr then
            sys.timerStop(utmr)
            utmr = nil
        end

        local rsn = common.resolve_disconnect_reason(data)
        sys.publish("WIFI_DISCONNECTED", rsn, data)
        lcs = "DISCONNECTED"
        uico = false

        if uidc then
            log.info("wa", "用户主动断开，只进行扫描")
            uidc = false
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
local function hipr(ip, adapter)
    common.handle_ip_ready(ip, adapter, ws, refni)
end

--[[
@function handle_ip_lose
@summary 处理IP丢失事件
@param number adapter - 网卡适配器
]]
local function hipl(adapter)
    common.handle_ip_lose(adapter, ws)
end

--[[
@function handle_scan_done
@summary 处理WiFi扫描完成事件
]]
local function hscd()
    local str = {}
    str[1] = stmr
    common.handle_scan_done(ws, str)
    stmr = str[1]
end

--[[
@function handle_scan_timeout
@summary 处理WiFi扫描超时事件
]]
local function hsct()
    stmr = nil
    sys.unsubscribe("WLAN_SCAN_DONE", hscd)
    common.handle_scan_timeout({})
end

--[[
@function auto_scan_and_verify
@summary 自动扫描并验证保存的SSID是否在附近
@return table {verified, ssid, signal} - 验证结果
]]
local function asv()
    return common.auto_scan_and_verify(sc)
end

--[[
@function run_auto_connect_task
@summary 运行自动连接任务
]]
local function ract()
    if not sc.wifi_enabled then
        log.info("wa", "WiFi开关已关闭，跳过自动连接")
        return
    end

    if ws.connected then
        log.info("wa", "已连接WiFi，刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    log.info("wa", "开始执行开机自动连接（选择信号最强的已保存网络）")
    local vr = asv()

    if vr.verified then
        log.info("wa", "自动连接到最佳网络:", vr.ssid, "信号:", vr.signal)
        sys.publish("WIFI_CONNECT_REQ", { ssid = vr.ssid, password = vr.password, advanced_config = vr.config and { need_ping = vr.config.need_ping, local_network_mode = vr.config.local_network_mode, ping_ip = vr.config.ping_ip, ping_time = vr.config.ping_time, auto_socket_switch = vr.config.auto_socket_switch } })
        log.info("wa", "自动连接请求发送成功")
    else
        log.info("wa", "附近没有已保存网络，等待手动连接")
    end
end

--[[
@function on_storage_load_rsp
@summary 处理WIFI_STORAGE_LOAD_RSP事件
@param table data - 包含config字段的响应数据
]]
local function oslr(data)
    sc = data.config
    log.info("wa", "加载配置完成:", sc.ssid, "enabled:", sc.wifi_enabled)
    sys.taskInit(ract)
end

local function osser(data)
    common.on_storage_set_enabled_rsp(data, sc)
end

--[[
@function on_enable_req
@summary 处理WIFI_ENABLE_REQ事件（WiFi开关切换）
@param table data - 包含enabled字段的数据
]]
local function oenr(data)
    local en = data.enabled
    log.info("wa", "收到开关请求:", en)

    if sc then
        sc.wifi_enabled = en
    end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", {enabled = en})

    if _G.model_str:find("PC") then
        if not en then
            ws.connected = false
            ws.ready = false
            ws.current_ssid = ""
            ws.rssi = "--"
            ws.ip = "--"
            ws.netmask = "--"
            ws.gateway = "--"
            ws.bssid = "--"
            upst(ws)
        else
            log.info("wa", "正在开启WiFi网卡")
            if sc and sc.ssid and sc.ssid ~= "" then
                if ws.connected then
                    log.info("wa", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wa", "检测到保存的SSID，执行自动连接")
                    sys.taskInit(ract)
                end
            end
        end
        return
    end

    if not en then
        log.info("wa", "正在关闭WiFi网卡")
        exnetif.close(nil, socket.LWIP_STA)
        ws.connected = false
        ws.ready = false
        ws.current_ssid = ""
        ws.rssi = "--"
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        ws.bssid = "--"
        ws.scan_results = {}
        upst(ws)
    else
        log.info("wa", "正在开启WiFi网卡")
        if sc and sc.ssid and sc.ssid ~= "" then
            if ws.connected then
                log.info("wa", "已连接WiFi，只进行扫描")
                sys.publish("WIFI_SCAN_REQ")
            else
                log.info("wa", "检测到保存的SSID，执行自动连接")
                sys.taskInit(ract)
            end
        end
    end
end

--[[
@function on_scan_req
@summary 处理WIFI_SCAN_REQ事件（开始扫描）
]]
local function oscr()
    log.info("wa", "收到扫描请求")

    if _G.model_str:find("PC") then
        sys.publish("WIFI_SCAN_STARTED")
        sys.taskInit(function()
            sys.wait(1500)
            local mkr = { { ssid = "ChinaNet-5G", rssi = -45, channel = 149 }, { ssid = "TP-LINK_ABC", rssi = -62, channel = 6 }, { ssid = "CMCC-8888", rssi = -58, channel = 11 }, { ssid = "HUAWEI-1234", rssi = -70, channel = 1 } }
            ws.scan_results = mkr
            sys.publish("WIFI_SCAN_DONE", mkr)
        end)
        return
    end

    wlan.init()
    wlan.scan()

    if stmr then
        sys.timerStop(stmr)
    end
    stmr = sys.timerStart(hsct, SCTO)

    sys.publish("WIFI_SCAN_STARTED")
end

--[[
@function on_connect_req
@summary 处理WIFI_CONNECT_REQ事件（连接WiFi）
@param table data - 包含ssid, password, advanced_config字段的数据
]]
local function ocnr(data)
    local sd = data.ssid
    local pw = data.password
    local advc = data.advanced_config

    log.info("wa", "收到连接请求:", sd)
    uico = true

    if not sd or sd == "" then
        sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
        return
    end
    if not pw or pw == "" then
        sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
        return
    end

    if sc and not sc.wifi_enabled then
        log.warn("wa", "WiFi已关闭，无法连接")
        return
    end

    sys.publish("WIFI_STORAGE_SAVE_REQ", { ssid = sd, password = pw, advanced_config = advc })

    if _G.model_str:find("PC") then
        sys.publish("WIFI_CONNECTING", sd)
        sys.taskInit(function()
            sys.wait(2000)
            local success = math.random(100) > 20
            if success then
                ws.connected = true
                ws.current_ssid = sd
                ws.rssi = tostring(-50 - math.random(20))
                ws.bssid = string.format("A0:B1:C2:D3:E4:%02X", math.random(255))
                ws.ip = string.format("192.168.1.%d", math.random(2, 254))
                ws.netmask = "255.255.255.0"
                ws.gateway = "192.168.1.1"
                ws.ready = true
                sys.publish("WIFI_CONNECTED", sd)
                sys.wait(500)
                upst(ws)
            else
                ws.connected = false
                ws.current_ssid = ""
                ws.ready = false
                ws.ip = "--"
                ws.netmask = "--"
                ws.gateway = "--"
                ws.bssid = "--"
                ws.rssi = "--"
                upst(ws)
                sys.publish("WIFI_DISCONNECTED", "密码错误或连接超时", -1)
            end
        end)
        return
    end

    sys.publish("WIFI_CONNECTING", sd)
    dcr = "config"
    exnetif.close(nil, socket.LWIP_STA)

    local wcfg = { ssid = sd, password = pw }

    if sc then
        if sc.need_ping ~= nil then
            wcfg.need_ping = sc.need_ping
        end
        if sc.local_network_mode ~= nil then
            wcfg.local_network_mode = sc.local_network_mode
        end
        if sc.ping_ip ~= nil and sc.ping_ip ~= "" then
            wcfg.ping_ip = sc.ping_ip
        end
        if sc.ping_time ~= nil and sc.ping_time ~= "" then
            wcfg.ping_time = tonumber(sc.ping_time) or 10000
        end
        if sc.auto_socket_switch ~= nil then
            wcfg.auto_socket_switch = sc.auto_socket_switch
        end
    end

    local res = exnetif.set_priority_order({ { WIFI = wcfg } })

    if res then
        log.info("wa", "WiFi连接参数配置成功")
    else
        log.error("wa", "WiFi连接参数配置失败")
        sys.publish("WIFI_DISCONNECTED", "连接参数配置失败", -5)
    end
end

--[[
@function on_disconnect_req
@summary 处理WIFI_DISCONNECT_REQ事件（断开连接）
]]
local function odcr()
    log.info("wa", "收到断开请求")
    uidc = true

    if _G.model_str:find("PC") then
        ws.connected = false
        ws.current_ssid = ""
        ws.ready = false
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        ws.bssid = "--"
        ws.rssi = "--"
        upst(ws)
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    dcr = "user"
    exnetif.close(nil, socket.LWIP_STA)
    dcr = nil
end

--[[
@function on_get_status_req
@summary 处理WIFI_GET_STATUS_REQ事件（获取当前状态）
]]
local function ogsr()
    common.on_get_status_req(ws, sc)
end

--[[
@function on_get_config_req
@summary 处理WIFI_GET_CONFIG_REQ事件（获取配置）
]]
local function ogcr()
    common.on_get_config_req(sc)
end

--[[
@function on_get_saved_list_req
@summary 处理WIFI_GET_SAVED_LIST_REQ事件（获取已保存网络列表）
]]
local function ogsl()
    common.on_get_saved_list_req(sc)
end

local function osgs(data)
    common.on_storage_get_saved_list_rsp(data)
end

--[[
@function on_storage_init_rsp
@summary 处理WIFI_STORAGE_INIT_RSP事件，storage初始化完成后继续app初始化
@param table data - 包含success字段的响应数据
]]
local function osir(data)
    common.on_storage_init_rsp(data)
end

--[[
@function init
@summary 初始化应用模块，先初始化storage，再继续app初始化
]]
local function init()
    log.info("wa", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", osir)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

-- 订阅所有事件（放在文件末尾，确保所有函数都已定义）
sys.subscribe("WLAN_STA_INC", hwse)
sys.subscribe("WLAN_SCAN_DONE", hscd)
sys.subscribe("IP_READY", hipr)
sys.subscribe("IP_LOSE", hipl)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", oslr)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", osser)
sys.subscribe("WIFI_ENABLE_REQ", oenr)
sys.subscribe("WIFI_SCAN_REQ", oscr)
sys.subscribe("WIFI_CONNECT_REQ", ocnr)
sys.subscribe("WIFI_DISCONNECT_REQ", odcr)
sys.subscribe("WIFI_GET_STATUS_REQ", ogsr)
sys.subscribe("WIFI_GET_CONFIG_REQ", ogcr)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", ogsl)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", osgs)

sys.taskInit(init)
