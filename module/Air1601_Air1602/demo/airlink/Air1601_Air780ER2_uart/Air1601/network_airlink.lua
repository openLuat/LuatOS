--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2026.05.27
@author  马梦阳
@usage
本demo演示的核心功能为：
1. 初始化4G和WiFi网络连接。
2. Air1601与对端设备进行数据交互。
3. 自动切换网络连接模式。
4. 通过HTTP GET请求测试网络连接情况。

使用示例：
require("network_airlink")
]]

--============================================================
-- 全局配置参数
--============================================================

-- AirLink UART 配置
local AIRLINK_UART_ID = 3    -- UART ID
local AIRLINK_BAUD = 2000000 -- 波特率：2M

-- 网络配置
local NET_PEER_IP = "192.168.111.2" -- 对端IP

-- 测试配置
local HTTP_URL = "https://httpbin.air32.cn/bytes/2048"
local HTTP_INTERVAL = 10000 -- HTTP请求间隔：10秒
local HTTP_TIMEOUT = 9000   -- HTTP超时：9秒
local SDATA_INTERVAL = 1000 -- 数据发送间隔：1秒

--============================================================
-- 模块加载
--============================================================

local exnetif = require "exnetif"

--============================================================
-- 网络初始化
--============================================================

-- 初始化网络，使得Air1601可以外挂Air780ER2模块实现4G联网功能。
local function init_airlink_net()
    exnetif.set_priority_order({
        {                                           -- 开启4G虚拟网卡
            airlink_4G = {
                auto_socket_switch = false,         -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART,   -- airlink工作模式：UART模式
                airlink_uart_id = AIRLINK_UART_ID,  -- airlink使用的UART接口ID
                airlink_uart_baud = AIRLINK_BAUD,   -- airlink使用的UART波特率
                airlink_adapter = socket.LWIP_GP_GW -- Air1601使用socket.LWIP_GP_GW网卡标识
            }
        }
    })
end

--============================================================
-- 数据收发
--============================================================

-- Air1601发送数据信息给Air780ER2模块。
local function airlink_sdata_Air780ER2()
    -- 设置网络时间同步。
    -- socket.sntp()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(SDATA_INTERVAL)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

--============================================================
-- 获取并打印 airlink 从机的网络信息
--============================================================

local function log_mobile_sync_info()
    while true do
        sys.wait(15000)
        if mobile then
            log.info("存在 mobile 底层库")
        else
            log.info("不存在 mobile 底层库，跳过获取 airlink 从机端网络信息")
            return
        end
        local imei = "unknown"
        local imsi = "unknown"
        local iccid = "unknown"
        local csq = -1
        local status = -1
        local rsrp = 0
        local rsrq = 0
        local snr = 0
        local rssi = 0
        if mobile and mobile.imei then
            local ok, val = pcall(mobile.imei)
            if ok and val then imei = val end
        end
        if mobile and mobile.imsi then
            local ok, val = pcall(mobile.imsi)
            if ok and val then imsi = val end
        end
        if mobile and mobile.iccid then
            local ok, val = pcall(mobile.iccid)
            if ok and val then iccid = val end
        end
        if mobile and mobile.csq then
            local ok, val = pcall(mobile.csq)
            if ok and val then csq = val end
        end
        log.info("airlink 从机网络信息", "imei", imei, "imsi", imsi, "iccid", iccid, "csq", csq, "airlink_ready", airlink.ready())

        -- 以下网络信息暂时不打印
        -- if mobile and mobile.status then
        --     local ok, val = pcall(mobile.status)
        --     if ok and val then status = val end
        -- end
        -- if mobile and mobile.rsrp then
        --     local ok, val = pcall(mobile.rsrp)
        --     if ok and val then rsrp = val end
        -- end
        -- if mobile and mobile.rsrq then
        --     local ok, val = pcall(mobile.rsrq)
        --     if ok and val then rsrq = val end
        -- end
        -- if mobile and mobile.snr then
        --     local ok, val = pcall(mobile.snr)
        --     if ok and val then snr = val end
        -- end
        -- if mobile and mobile.rssi then
        --     local ok, val = pcall(mobile.rssi)
        --     if ok and val then rssi = val end
        -- end
        -- log.info("mobile-rpc-sync", "imei", imei, "imsi", imsi, "iccid", iccid, "csq", csq, "status", status, "rsrp", rsrp, "rsrq", rsrq, "snr", snr, "rssi", rssi, "airlink_ready", airlink.ready())
    end
end

--============================================================
-- 测试函数
--============================================================

-- Ping测试（调试用）
local function ping_test()
    while true do
        -- 必须指定使用哪个网卡
        netdrv.ping(socket.LWIP_GP_GW, NET_PEER_IP)
        -- local res = sys.waitUntil("PING_RESULT", 3000)
        -- if not res then
        --     log.info("ping超时")
        -- end
        sys.wait(3000)
    end
end

-- Ping响应结果回调
local function ping_res(id, time, dst)
    log.info("ping", id, time, dst) --获取到响应结果，id为网卡id，也就是调用netdrv.ping时填写的网卡的常量值，time为请求到响应的时间，dst为目标IP也就是调用netdrv.ping时填写的ip
end


-- HTTP GET请求测试，用于判断Air1601的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(HTTP_INTERVAL)
        -- 本功能在2025.9.3
        log.info("网卡状态", netdrv.ready(socket.LWIP_GP_GW))
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", HTTP_URL)
        local code, headers, body = http.request("GET", HTTP_URL, nil, nil, {
            timeout = HTTP_TIMEOUT,
            adapter = socket.LWIP_GP_GW
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
            sys.publish("打印网卡信息", "succeeded")
        else
            log.error("HTTP请求失败", "错误码", code)
            sys.publish("打印网卡信息", "failed")
        end
    end
end

--============================================================
-- 事件订阅
--============================================================

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

--============================================================
-- 启动入口
--============================================================

-- 订阅PING_RESULT事件
sys.subscribe("PING_RESULT", ping_res)

-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 开启airlink
sys.taskInit(init_airlink_net)

-- 启动Ping测试
-- sys.taskInit(ping_test)

-- HTTP GET请求测试
sys.taskInit(http_get_test)

-- Air1601发送数据信息给Air780ER2模块。
sys.taskInit(airlink_sdata_Air780ER2)

-- 获取并打印 airlink 从机的网络信息
sys.taskInit(log_mobile_sync_info)
