--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2025.10.15
@author  魏健强
@usage
本demo演示的核心功能为：
1. 初始化网络，使得Air1601可以外挂Air780EPM实现4G联网功能
2. Air780EPM与对端设备进行数据交互。
3. 通过HTTP GET请求测试Air780EPM的网络访问外网是否正常。
]] -- 加载需要用到的功能模块。
dnsproxy = require("dnsproxy")

-- 初始化网络，使得Air1601可以外挂Air780EPM实现4G联网功能。
local function init_airlink_net()
    local uartid = 2 -- 根据实际设备选取不同的uartid
    -- 初始化
    uart.setup(uartid, -- 串口id
    2000000, -- 波特率
    8, -- 数据位
    1 -- 停止位
    )
    airlink.init()
    airlink.config(airlink.CONF_UART_ID, uartid)
    -- 延时100毫秒。
    sys.wait(100)
    airlink.start(airlink.MODE_UART)
    -- 创建桥接网络设备。
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)
    -- 配置IPv4地址。
    log.info("配置IPv4地址", "192.168.111.2", "255.255.255.0", "192.168.111.1")
    netdrv.ipv4(socket.LWIP_GP_GW, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    -- 延时100毫秒。
    sys.wait(100)
    -- 等待网络就绪，默认事件主题为IP_READY，设置超时时间为10秒。
    sys.waitUntil("IP_READY", 10000)
    -- 配置网络地址端口转换（NAPT），此处使用4G网络作为主网关出口。
    netdrv.napt(socket.LWIP_GP)
    -- 设置DNS代理。
    dnsproxy.setup(socket.LWIP_GP_GW, socket.LWIP_GP)
    log.info("网卡", netdrv.ready(socket.LWIP_GP_GW))
end

local function ping_test()
    while true do
        -- 必须指定使用哪个网卡
        netdrv.ping(socket.LWIP_GP_GW, "192.168.111.1")
        -- local res = sys.waitUntil("PING_RESULT", 3000)
        -- if not res then
        --     log.info("ping超时")
        -- end
        sys.wait(3000)
    end
end
local function ping_res(id, time, dst)
    log.info("ping", id, time, dst); -- 获取到响应结果，id为网卡id，也就是调用netdrv.ping时填写的网卡的常量值，time为请求到响应的时间，dst为目标IP也就是调用netdrv.ping时填写的ip
end
-- sys.taskInit(ping_test)
sys.subscribe("PING_RESULT", ping_res)

-- Air780EPM发送数据信息给Air1601。
local function airlink_sdata_Air1601()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos.bsp() .. " " .. os.date()

        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)

        -- 此处代码用于实现Air780EPM网络状态的持续检测，并持续给对端设备发送网络状态信息，方便对端设备作应对处理。
        -- 如果有需要，可以打开注释。
        -- local net_state = socket.adapter(socket.LWIP_GP)
        -- if net_state then
        --     airlink.sdata("Air780EPM_IP_READY!!")
        -- else
        --     airlink.sdata("Air780EPM_IP_LOSE!!")
        -- end

        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

-- 一个简单的HTTP GET请求测试程序，用于判断Air780EPM的网络访问外网是否正常。
local function http_get_test()
    -- 循环发起HTTP GET请求，测试Air780EPM的网络访问外网是否正常。
    while 1 do
        log.info("发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
            timeout = 3000
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
        else
            log.error("HTTP请求失败", "错误码", code)
        end

        -- 加点延时，避免请求过快。
        sys.wait(5000)
    end
end

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    log.info("收到AIRLINK_SDATA!!", data)
end

-- 初始化网络，使得Air1601可以外挂Air780EPM实现4G联网功能。
sys.taskInit(init_airlink_net)

-- 一个简单的HTTP GET请求测试程序，用于判断Air780EPM的网络访问外网是否正常。
-- sys.taskInit(http_get_test)

-- Air780EPM发送数据信息给Air1601。
sys.taskInit(airlink_sdata_Air1601)

-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)
