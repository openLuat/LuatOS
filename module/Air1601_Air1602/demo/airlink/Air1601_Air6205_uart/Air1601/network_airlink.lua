--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2025.10.15
@author  魏健强
@usage
本demo演示的核心功能为：
1. 初始化Air6205外挂WiFi网络连接。
2. Air1601与对端设备进行数据交互。
3. 通过HTTP GET请求测试网络连接情况。
]]

local exnetif = require "exnetif"

-- 初始化网络，使得Air1601可以通过airlink外挂Air6205实现WiFi联网功能。
local function init_airlink_net()
    -- 配置airlink WiFi单网卡
    -- 实际测试时，根据自己要连接的WiFi热点信息修改ssid和password参数
    -- Air6205仅支持2.4G WiFi，不支持5G WiFi
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,       -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
                airlink_uart_id = 3,              -- airlink使用的UART接口ID
                airlink_uart_baud = 2000000,      -- airlink使用的UART波特率，默认2000000
                ssid = "116",                     -- WiFi名称
                password = "wangshuai123"         -- WiFi密码
            }
        }
    })
    -- 注意：airlink_wifi使用socket.LWIP_STA作为网卡标识（由exnetif内部硬编码），
    -- 不支持airlink_adapter自定义网卡标识
end

-- Air1601发送数据信息给Air6205。
local function airlink_sdata_Air6205()
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


-- 一个简单的HTTP GET请求测试程序，用于判断Air1601的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(10000)
        -- 检查WiFi网卡是否就绪
        log.info("网卡状态", netdrv.ready(socket.LWIP_STA))
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", "https://httpbin.luatos.com/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.luatos.com/bytes/2048", nil, nil, {
            timeout = 9000,
            adapter = socket.LWIP_STA
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

-- airlink ping回调
-- sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
--     if ok then
--         log.info("ping", "成功", "rtt=" .. v1 .. "ms", "echo=" .. v2)
--     else
--         log.info("ping", "失败", tostring(v1)) -- v1 = "timeout" 或错误码
--     end
-- end)

-- airlink ping函数
-- local function airlink_ping()
--     sys.waitUntil("IP_READY")
--     while true do
--         local ping_id = airlink.ping("hello_airlink", 2000)
--         log.info("Ping已发送", "id=" .. ping_id)
--         sys.wait(20000) -- 每20s ping一次
--     end
-- end

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

-- 开启airlink
sys.taskInit(init_airlink_net)
-- Air1601发送数据信息给Air6205。
sys.taskInit(airlink_sdata_Air6205)
-- Air1601 http get测试
sys.taskInit(http_get_test)
-- Air1601 airlink ping测试
-- sys.taskInit(airlink_ping)
-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)
