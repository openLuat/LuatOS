--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2025.10.15
@author  魏健强
@usage
本demo演示的核心功能为：
1. 初始化4G和WiFi网络连接。
2. Air8101与对端设备进行数据交互。
3. 自动切换网络连接模式。
4. 通过HTTP GET请求测试网络连接情况。
]]
exnetif = require "exnetif"

-- 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能。
local function init_airlink_net()
    exnetif.set_priority_order({
    -- {
    --     WIFI = { -- WiFi配置
    --         ssid = "test", -- WiFi名称(string)
    --         password = "HZ88888888" -- WiFi密码(string)
    --     }
    -- }, 
    { -- 开启4G虚拟网卡
        airlink_4G = {
            auto_socket_switch = false, -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
            airlink_type = airlink.MODE_SPI_MASTER, -- airlink工作模式
            -- airlink_spi_id = 0, -- airlink使用的SPI接口ID,选填参数
            -- airlink_cs_pin = 15,-- airlink使用的片选引脚gpio号,选填参数
            -- airlink_rdy_pin = 48-- airlink使用的rdy引脚gpio号,选填参数
        }
    }})
end

local function netdrv_multiple_notify_cbfunc(net_type,adapter)
    if type(net_type)=="string" then
        log.info("netdrv_multiple_notify_cbfunc", "use new adapter", net_type, adapter)
    elseif type(net_type)=="nil" then
        log.warn("netdrv_multiple_notify_cbfunc", "no available adapter", net_type, adapter)
    else
        log.warn("netdrv_multiple_notify_cbfunc", "unknown status", net_type, adapter)
    end
end

-- 设置网卡状态变化通知回调函数netdrv_multiple_notify_cbfunc
exnetif.notify_status(netdrv_multiple_notify_cbfunc)

-- Air8101发送数据信息给Air780EPM。
local function airlink_sdata_Air780EPM()
    -- 设置网络时间同步。
    socket.sntp()
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
-- 一个简单的HTTP GET请求测试程序，用于判断Air8101的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(10000)
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
            timeout = 3000
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
-- Air8101发送数据信息给Air780EPM。
sys.taskInit(airlink_sdata_Air780EPM)
sys.taskInit(http_get_test)
-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)