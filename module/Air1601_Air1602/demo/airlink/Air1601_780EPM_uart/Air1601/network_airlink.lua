--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2025.10.15
@author  魏健强
@usage
本demo演示的核心功能为：
1. 初始化4G和WiFi网络连接。
2. Air1601与对端设备进行数据交互。
3. 自动切换网络连接模式。
4. 通过HTTP GET请求测试网络连接情况。
]]

local exnetif = require "exnetif"

-- 初始化网络，使得Air1601可以外挂Air780EPM实现4G联网功能。
local function init_airlink_net()
    exnetif.set_priority_order({
        { -- 开启4G虚拟网卡
            airlink_4G = {
                auto_socket_switch = false, -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
                airlink_uart_id = 3, -- airlink使用的UART接口ID
                airlink_uart_baud = 2000000, -- airlink使用的UART波特率，默认2000000
                airlink_adapter = socket.LWIP_GP_GW -- Air1601使用socket.LWIP_GP_GW网卡标识
            }
        }
    })
end

-- Air1601发送数据信息给Air780EPM。
local function airlink_sdata_Air780EPM()
    -- 设置网络时间同步。
    -- socket.sntp()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

-- local function ping_test()
--  while true do
--         -- 必须指定使用哪个网卡
--         netdrv.ping(socket.LWIP_GP_GW, "192.168.111.2")
--         -- local res = sys.waitUntil("PING_RESULT", 3000)
--         -- if not res then
--         --     log.info("ping超时")
--         -- end
--         sys.wait(3000)
--     end
-- end
-- local function ping_res(id, time, dst)
--     log.info("ping", id, time, dst); --获取到响应结果，id为网卡id，也就是调用netdrv.ping时填写的网卡的常量值，time为请求到响应的时间，dst为目标IP也就是调用netdrv.ping时填写的ip
-- end
-- sys.taskInit(ping_test)
-- sys.subscribe("PING_RESULT", ping_res)

-- 一个简单的HTTP GET请求测试程序，用于判断Air1601的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(10000)
        -- 本功能在2025.9.3
        log.info("网卡状态", netdrv.ready(socket.LWIP_GP_GW))
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
            timeout = 9000,
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

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

-- 开启airlink
sys.taskInit(init_airlink_net)
-- Air1601发送数据信息给Air780EPM。
sys.taskInit(airlink_sdata_Air780EPM)
sys.taskInit(http_get_test)
-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)
