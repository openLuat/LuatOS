--[[
@module  network_airlink
@summary 780EXX + Air6205 WiFi联网驱动模块（UART模式）
@version 1.0
@date    2026.07.20
@usage
本模块负责通过airlink UART协议驱动Air6205连接WiFi，并提供网络状态监控和HTTP测试功能。

模块功能说明：
1. airlink WiFi STA网卡初始化：通过exnetif配置airlink UART参数，连接指定WiFi热点，验证STA模式联网功能
2. AP热点功能测试：STA连接成功后开启AP热点（名称: test, 密码: 12345678），验证Air6205的AP模式功能
3. HTTP GET请求测试：联网成功后每30秒发送HTTP GET请求验证网络连通性
4. airlink状态监控：实时监控airlink连接状态，支持ping测试
5. SDATA数据收发：支持与Air6205之间的自定义数据收发

初始化参数说明：
- airlink_type = airlink.MODE_UART：使用UART模式通信
- airlink_uart_id = 2：使用UART2（默认pin28/pin29）
- airlink_uart_baud = 2000000：波特率2Mbps
- ssid/password：要连接的WiFi热点名称和密码

注意事项：
1. 本模块使用UART2作为airlink通信串口，与readme.md中的接线表一致
2. 如需修改连接的WiFi热点，请修改下方的ssid和password参数
3. Air6205仅支持2.4G WiFi，不支持5G WiFi
]]

local exnetif = require "exnetif"
local dnsproxy = require("dnsproxy")
local dhcpsrv = require("dhcpsrv")

airlink.config(airlink.CONF_HEARTBEAT_MAX, 20000)  -- 手动设 20s

-- 初始化网络，使得Air780Exx可以通过airlink外挂Air6205实现WiFi联网功能。
local function init_airlink_net()
    -- 配置airlink WiFi STA网卡
    -- 实际测试时，根据自己要连接的WiFi热点信息修改ssid和password参数
    -- Air6205仅支持2.4G WiFi，不支持5G WiFi
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,       -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
                airlink_uart_id = 2,              -- airlink使用的UART接口ID（Air780Exx UART2）
                airlink_uart_baud = 2000000,      -- airlink使用的UART波特率，默认2000000
                ssid = "luatos1234",              -- WiFi名称
                password = "12341234"             -- WiFi密码
            }
        }
    })
    -- 注意：airlink_wifi使用socket.LWIP_STA作为网卡标识（由exnetif内部硬编码），
    -- 不支持airlink_adapter自定义网卡标识

    -- 等待STA网卡IP就绪
    sys.waitUntil("IP_READY")

    -- STA连接成功后，开启AP热点
    log.info("开始测试AP功能...")
    local res = exnetif.setproxy(socket.LWIP_AP, socket.LWIP_STA, {
        ssid = "test",           -- AP热点名称
        password = "12345678",   -- AP热点密码
        -- ap_opts = {                      -- AP模式下配置项(选填参数)
        --     hidden = false,              -- 是否隐藏SSID, 默认false,不隐藏
        --     max_conn = 4 },              -- 最大客户端数量, 默认4
        -- channel = 6,                     -- AP建立的通道, 默认6
        main_adapter = {
            ssid = "luatos1234", -- STA连接的WiFi名称（与上方保持一致）
            password = "12341234"
        }
    })
    log.info("AP热点开启结果:", res, "名称: test 密码: 12345678")
end

-- AP连接事件回调
local function ap_event(evt, data)
    -- evt: "CONNECTED"或"DISCONNECTED"
    -- data: 连接/断开AP的STA的MAC地址
    log.info("AP事件", evt, data and data:toHex())
end
sys.subscribe("WLAN_AP_INC", ap_event)

-- Air780Exx发送数据信息给Air6205。
local function airlink_sdata_Air6205()
    while 1 do
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(10000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

-- 一个简单的HTTP GET请求测试程序，用于判断Air780Exx的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(30000)
        log.info("网卡状态", netdrv.ready(socket.LWIP_STA))
        log.info("发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
            timeout = 9000,
            adapter = socket.LWIP_STA
        }).wait()

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
sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
    if ok then
        log.info("ping", "成功", "rtt=" .. v1 .. "ms", "echo=" .. v2)
    else
        log.info("ping", "失败", tostring(v1))
    end
end)

-- airlink ping函数
local function airlink_ping()
    sys.waitUntil("IP_READY")
    while true do
        local ping_id = airlink.ping("hello_airlink", 2000)
        log.info("Ping已发送", "id=" .. ping_id)
        sys.wait(20000)
    end
end

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    log.info("收到AIRLINK_SDATA!!", data)
end


-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 开启airlink
sys.taskInit(init_airlink_net)

-- Air780Exx http get测试
sys.taskInit(http_get_test)

-- Air780Exx发送数据信息给Air6205。
-- sys.taskInit(airlink_sdata_Air6205)

-- Air780Exx airlink ping测试
-- sys.taskInit(airlink_ping)

