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
-- 
-- [Short names] local fn: us=update_status, rni=refresh_network_info,
--  iwh=init_wifi_hardware_task, ewi=ensure_wifi_init, hse=handle_wifi_sta_event,
--  hir=handle_ip_ready, hil=handle_ip_lose, hsd=handle_scan_done,
--  hst=handle_scan_timeout, asv=auto_scan_and_verify, rac=run_auto_connect_task,
--  osl=on_storage_load_rsp, ose=on_storage_set_enabled_rsp, oer=on_enable_req,
--  osr=on_scan_req, ocr=on_connect_req, odr=on_disconnect_req,
--  ogs=on_get_status_req, ogc=on_get_config_req, ogl=on_get_saved_list_req,
--  osg=on_storage_get_saved_list_rsp, osi=on_storage_init_rsp, fi=init,
--  uws=update_wifi_signal(nested)
--  local var: ws=wifi_status, sv=saved_config, st=scan_timer, ut=update_timer,
--  lc=last_connect_status, dr=disconnect_reason, uid=user_initiated_disconnect,
--  uic=user_initiated_connect, wi=wifi_initialized, wp=wifi_init_in_progress,
--  sp=scan_in_progress, cm=common; log tag: wa=wifi_app
]]

require "wifi_storage"
local cm = require "wifi_app_common"

local SCAN_TIMEOUT = 15000
local UPDATE_INTERVAL = 5000

local ws = { connected = false, ready = false, current_ssid = "", rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--", scan_results = {} }

local sv = { wifi_enabled = false, ssid = "", password = "", need_ping = true, local_network_mode = false, ping_ip = "", ping_time = "10000", auto_socket_switch = true }

local st = nil
local ut = nil
local lc = nil
local dr = nil
local uid = false
local uic = false

local wi = false
local wp = false
local sp = false

--[[
@function update_status
@summary 更新WiFi状态并发布事件
@param table status - 包含状态字段的对象
]]
local function us(s)
    if not s then
        log.error("wa", "更新WiFi状态时，状态对象为空")
        return
    end

    for k, v in pairs(s) do
        ws[k] = v
    end
    cm.update_status(ws, sv)
end

--[[
@function refresh_network_info
@summary 刷新并更新网络信息（IP、网关、子网掩码等）
]]
local function rni()
    local function uws()
        if wlan_info then
            local rs = wlan_info.rssi
            local lv = 0
            if rs > -60 then lv = 4
            elseif rs > -70 then lv = 3
            elseif rs > -80 then lv = 2
            else lv = 1 end
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", lv)
        end
    end
    cm.refresh_network_info(ws, uws)
end

--[[
@function init_wifi_hardware_task
@summary 初始化airlink+wlan硬件（必须在task中运行，因为使用了sys.wait）
]]
local function iwh()
    if wi then return end

    log.info("wa", "初始化airlink+wlan硬件")

    airlink.config(airlink.CONF_SPI_ID, 1)
    airlink.config(airlink.CONF_SPI_CS, 8)
    airlink.config(airlink.CONF_SPI_RDY, 14)
    airlink.config(airlink.CONF_SPI_SPEED, 2 * 1000000)
    airlink.init()

    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

    airlink.start(airlink.MODE_SPI_MASTER)

    gpio.setup(55, 0)
    log.info("wa", "拉低复位引脚，等待500ms")
    sys.wait(500)
    gpio.setup(55, 1)
    log.info("wa", "拉高复位引脚")

    while not airlink.ready() do
        log.info("wa", "等待airlink就绪...")
        sys.wait(100)
    end
    log.info("wa", "airlink就绪")

    wlan.init()
    wlan.setMode(wlan.STATIONAP)

    wi = true
    wp = false
    log.info("wa", "airlink+wlan硬件初始化完成")
    sys.publish("WIFI_HW_READY")
end

--[[
@function ensure_wifi_init
@summary 确保WiFi硬件已初始化，未初始化则启动初始化task
]]
local function ewi()
    if wi then return true end
    if not wp then
        wp = true
        sys.taskInit(iwh)
    end
    return false
end

--[[
@function handle_wifi_sta_event
@summary 处理WiFi STA事件（连接/断开等）
@param string evt - 事件类型
@param any data - 事件数据
]]
local function hse(e, d)
    log.info("wa", "WiFi STA事件:", e, d)

    if e == "CONNECTED" then
        ws.connected = true
        ws.ready = false
        ws.current_ssid = d

        sys.publish("WIFI_CONNECTED", d)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 3)
        lc = "CONNECTED"
        uic = false

        if ut then
            sys.timerStop(ut)
            ut = nil
        end
        ut = sys.timerLoopStart(rni, UPDATE_INTERVAL)

    elseif e == "DISCONNECTED" then
        if uic then
            log.info("wa", "用户发起的连接失败，重置状态以允许再次弹窗")
            lc = nil
        elseif lc == "DISCONNECTED" then
            log.info("wa", "已断开状态，跳过重复事件")
            return
        end

        if dr == "config" then
            log.info("wa", "配置前断开，跳过事件处理")
            dr = nil
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

        if ut then
            sys.timerStop(ut)
            ut = nil
        end

        local r = cm.resolve_disconnect_reason(d)
        sys.publish("WIFI_DISCONNECTED", r, d)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        lc = "DISCONNECTED"
        uic = false

        if uid then
            log.info("wa", "用户主动断开，只进行扫描")
            uid = false
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
local function hir(ip, ad)
    if ad == socket.LWIP_STA then
        socket.setDNS(ad, 1, "223.5.5.5")
        socket.setDNS(ad, 2, "114.114.114.114")
        log.info("wa", "WiFi IP就绪，DNS已设置:", ip)
    end
    cm.handle_ip_ready(ip, ad, ws, rni)
end

--[[
@function handle_ip_lose
@summary 处理IP丢失事件
@param number adapter - 网卡适配器
]]
local function hil(ad)
    cm.handle_ip_lose(ad, ws)
end

--[[
@function handle_scan_done
@summary 处理WiFi扫描完成事件
]]
local function hsd()
    local sr = {}
    sr[1] = st
    cm.handle_scan_done(ws, sr, function() sp = false end)
    st = sr[1]
end

--[[
@function handle_scan_timeout
@summary 处理WiFi扫描超时事件
]]
local function hst()
    st = nil
    sp = false
    cm.handle_scan_timeout({})
end

--[[
@function auto_scan_and_verify
@summary 自动扫描并从所有已保存网络中选信号最强的
@return table {verified, ssid, password, signal, config} - 验证结果
]]
local function asv()
    return cm.auto_scan_and_verify(sv, SCAN_TIMEOUT + 5000)
end

--[[
@function run_auto_connect_task
@summary 运行自动连接任务
]]
local function rac()
    if _G.model_str:find("PC") then
    else
        if not sv.wifi_enabled then
            log.info("wa", "WiFi开关已关闭，跳过自动连接")
            return
        end

        ewi()
        if not wi then
            sys.waitUntil("WIFI_HW_READY", 15000)
        end
        if not wi then
            log.error("wa", "airlink+wlan硬件初始化超时")
            return
        end
    end

    log.info("wa", "开始执行开机自动连接（选择信号最强的已保存网络）")

    if ws.connected then
        log.info("wa", "已连接WiFi，只进行扫描刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    local vr = asv()

    if vr.verified then
        log.info("wa", "自动连接到最佳网络:", vr.ssid, "信号:", vr.signal)
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = vr.ssid,
            password = vr.password,
            advanced_config = vr.config and { need_ping = vr.config.need_ping, local_network_mode = vr.config.local_network_mode, ping_ip = vr.config.ping_ip, ping_time = vr.config.ping_time, auto_socket_switch = vr.config.auto_socket_switch }
        })
        log.info("wa", "自动连接请求发送成功")
    else
        log.info("wa", "附近没有已保存网络，等待用户手动连接")
    end
end

--[[
@function on_storage_load_rsp
@summary 处理WIFI_STORAGE_LOAD_RSP事件
@param table data - 包含config字段的响应数据
]]
local function osl(d)
    sv = d.config
    log.info("wa", "加载配置完成:", sv.ssid, "enabled:", sv.wifi_enabled)
    sys.taskInit(rac)
end

local function ose(d)
    cm.on_storage_set_enabled_rsp(d, sv)
end

--[[
@function on_storage_set_enabled_rsp
@summary 处理WIFI_STORAGE_SET_ENABLED_RSP事件
@param table data - 包含success和enabled字段的响应数据
]]

--[[
@function on_enable_req
@summary 处理WIFI_ENABLE_REQ事件（WiFi开关切换）
@param table data - 包含enabled字段的数据
]]
local function oer(d)
    local en = d.enabled
    log.info("wa", "收到开关请求:", en)

    if sv then
        sv.wifi_enabled = en
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
            us(ws)
        else
            log.info("wa", "正在开启WiFi网卡")
            if sv and sv.ssid and sv.ssid ~= "" then
                if ws.connected then
                    log.info("wa", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wa", "检测到保存的SSID，执行自动连接")
                    sys.taskInit(rac)
                end
            end
        end
        return
    end

    if not en then
        log.info("wa", "正在关闭WiFi网卡")
        if wi then
            wlan.disconnect()
        end
        ws.connected = false
        ws.ready = false
        ws.current_ssid = ""
        ws.rssi = "--"
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        ws.bssid = "--"
        ws.scan_results = {}
        us(ws)
    else
        log.info("wa", "正在开启WiFi网卡")
        sys.taskInit(function()
            ewi()
            if not wi then
                sys.waitUntil("WIFI_HW_READY", 15000)
            end
            if sv and sv.ssid and sv.ssid ~= "" then
                if ws.connected then
                    log.info("wa", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wa", "检测到保存的SSID，执行自动连接")
                    rac()
                end
            end
        end)
    end
end

--[[
@function on_scan_req
@summary 处理WIFI_SCAN_REQ事件（开始扫描）
]]
local function osr()
    log.info("wa", "收到扫描请求")

    if _G.model_str:find("PC") then
        sys.publish("WIFI_SCAN_STARTED")
        sys.taskInit(function()
            sys.wait(1500)
            local mr = { { ssid = "ChinaNet-5G", rssi = -45, channel = 149 }, { ssid = "TP-LINK_ABC", rssi = -62, channel = 6 }, { ssid = "CMCC-8888", rssi = -58, channel = 11 }, { ssid = "HUAWEI-1234", rssi = -70, channel = 1 } }
            ws.scan_results = mr
            sys.publish("WIFI_SCAN_DONE", mr)
        end)
        return
    end

    if not wi then
        ewi()
        log.info("wa", "等待WiFi硬件初始化完成后再扫描")
        sys.taskInit(function()
            sys.waitUntil("WIFI_HW_READY", 15000)
            if wi and not sp then
                sp = true
                wlan.scan()
                if st then sys.timerStop(st) end
                st = sys.timerStart(hst, SCAN_TIMEOUT)
                sys.publish("WIFI_SCAN_STARTED")
            end
        end)
        return
    end

    if sp then
        log.info("wa", "扫描已在进行中，跳过重复请求")
        return
    end

    sp = true
    wlan.scan()

    if st then
        sys.timerStop(st)
    end
    st = sys.timerStart(hst, SCAN_TIMEOUT)

    sys.publish("WIFI_SCAN_STARTED")
end

--[[
@function on_connect_req
@summary 处理WIFI_CONNECT_REQ事件（连接WiFi）
@param table data - 包含ssid, password, advanced_config字段的数据
]]
local function ocr(d)
    local sd = d.ssid
    local pw = d.password
    local ac = d.advanced_config

    log.info("wa", "收到连接请求:", sd)
    uic = true

    if not sd or sd == "" then
        sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
        return
    end
    if not pw or pw == "" then
        sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
        return
    end

    if sv and not sv.wifi_enabled then
        log.warn("wa", "WiFi已关闭，无法连接")
        return
    end

    sys.publish("WIFI_STORAGE_SAVE_REQ", { ssid = sd, password = pw, advanced_config = ac })

    if _G.model_str:find("PC") then
        sys.publish("WIFI_CONNECTING", sd)
        sys.taskInit(function()
            sys.wait(2000)
            local scs = math.random(100) > 20
            if scs then
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
                us(ws)
            else
                ws.connected = false
                ws.current_ssid = ""
                ws.ready = false
                ws.ip = "--"
                ws.netmask = "--"
                ws.gateway = "--"
                ws.bssid = "--"
                ws.rssi = "--"
                us(ws)
                sys.publish("WIFI_DISCONNECTED", "密码错误或连接超时", -1)
            end
        end)
        return
    end

    sys.publish("WIFI_CONNECTING", sd)
    dr = "config"

    sys.taskInit(function()
        if not wi then
            ewi()
            if not wi then
                local ok = sys.waitUntil("WIFI_HW_READY", 15000)
                if not ok then
                    log.error("wa", "WiFi硬件初始化超时，无法连接")
                    sys.publish("WIFI_DISCONNECTED", "硬件初始化超时", -6)
                    return
                end
            end
        end

        dr = "config"
        wlan.disconnect()

        local res = wlan.connect(sd, pw)

        if res then
            log.info("wa", "WiFi连接已发起:", sd)
        else
            log.error("wa", "WiFi连接发起失败")
            sys.publish("WIFI_DISCONNECTED", "连接发起失败", -5)
        end
    end)
end

--[[
@function on_disconnect_req
@summary 处理WIFI_DISCONNECT_REQ事件（断开连接）
]]
local function odr()
    log.info("wa", "收到断开请求")
    uid = true

    if _G.model_str:find("PC") then
        ws.connected = false
        ws.current_ssid = ""
        ws.ready = false
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        ws.bssid = "--"
        ws.rssi = "--"
        us(ws)
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    dr = "user"
    wlan.disconnect()
    dr = nil
end

--[[
@function on_get_status_req
@summary 处理WIFI_GET_STATUS_REQ事件（获取当前状态）
]]
local function ogs()
    cm.on_get_status_req(ws, sv)
end

--[[
@function on_get_config_req
@summary 处理WIFI_GET_CONFIG_REQ事件（获取配置）
]]
local function ogc()
    cm.on_get_config_req(sv)
end

--[[
@function on_get_saved_list_req
@summary 处理WIFI_GET_SAVED_LIST_REQ事件（获取已保存网络列表）
]]
local function ogl()
    cm.on_get_saved_list_req(sv)
end

local function osg(d)
    cm.on_storage_get_saved_list_rsp(d)
end

--[[
@function on_storage_init_rsp
@summary 处理WIFI_STORAGE_INIT_RSP事件，storage初始化完成后继续app初始化
@param table data - 包含success字段的响应数据
]]
local function osi(d)
    cm.on_storage_init_rsp(d)
end

--[[
@function init
@summary 初始化应用模块，先初始化storage，再继续app初始化
]]
local function fi()
    log.info("wa", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", osi)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

sys.subscribe("WLAN_STA_INC", hse)
sys.subscribe("WLAN_SCAN_DONE", hsd)
sys.subscribe("IP_READY", hir)
sys.subscribe("IP_LOSE", hil)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", osl)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", ose)
sys.subscribe("WIFI_ENABLE_REQ", oer)
sys.subscribe("WIFI_SCAN_REQ", osr)
sys.subscribe("WIFI_CONNECT_REQ", ocr)
sys.subscribe("WIFI_DISCONNECT_REQ", odr)
sys.subscribe("WIFI_GET_STATUS_REQ", ogs)
sys.subscribe("WIFI_GET_CONFIG_REQ", ogc)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", ogl)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", osg)

sys.taskInit(fi)
