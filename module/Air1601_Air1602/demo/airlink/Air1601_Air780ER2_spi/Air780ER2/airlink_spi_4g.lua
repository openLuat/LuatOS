--[[
@module  airlink_spi_4g
@summary AirLink SPI 4G网络模块
@version 1.0
@date    2026.05.26
@author  马梦阳
@usage
本模块实现Air780ER2作为外部4G模块外挂到Air1601的功能

主要功能：
1. AirLink SPI模式网络初始化
2. 桥接网络设备创建与配置
3. NAPT网络地址端口转换
4. DNS代理配置
5. AirLink数据收发
6. Ping/HTTP测试（可选）

硬件连接：Air780ER2 SPI <-> Air1601 SPI

使用示例：
require("airlink_spi_4g")
]]

--============================================================
-- 模块全局配置参数
--============================================================

-- 网络配置
local NET_LOCAL_IP = "192.168.111.2"  -- 本地IP
local NET_MASK = "255.255.255.0"      -- 子网掩码
local NET_GATEWAY = "192.168.111.1"   -- 网关IP

-- 超时配置
local NET_WAIT_TIMEOUT = 10000         -- 网络等待超时：10秒
local PING_INTERVAL = 3000             -- Ping间隔：3秒
local SDATA_INTERVAL = 1000            -- 数据发送间隔：1秒
local HTTP_INTERVAL = 5000             -- HTTP请求间隔：5秒
local HTTP_TIMEOUT = 3000             -- HTTP超时：3秒

-- HTTP 配置
local HTTP_URL = "https://httpbin.air32.cn/bytes/2048"

--============================================================
-- 模块加载
--============================================================

-- 加载需要用到的功能模块
local dnsproxy = require("dnsproxy")

--============================================================
-- 网络初始化
--============================================================

-- 初始化网络，使得 Air1601 可以外挂 Air780ER2 实现 4G 联网功能
local function init_airlink_net()
    -- 初始化airlink
    airlink.init()
    sys.wait(100)
    airlink.start(airlink.MODE_SPI_SLAVE)
    -- 创建桥接网络设备
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)
    -- 配置IPv4地址
    log.info("配置IPv4地址", NET_LOCAL_IP, NET_MASK, NET_GATEWAY)
    netdrv.ipv4(socket.LWIP_GP_GW, NET_LOCAL_IP, NET_MASK, NET_GATEWAY)
    sys.wait(100)
    -- 等待网络就绪，设置超时时间
    sys.waitUntil("IP_READY", NET_WAIT_TIMEOUT)
    -- 配置NAPT，使用4G网络作为主网关出口
    netdrv.napt(socket.LWIP_GP)
    -- 设置DNS代理
    dnsproxy.setup(socket.LWIP_GP_GW, socket.LWIP_GP)
    log.info("网卡", netdrv.ready(socket.LWIP_GP_GW))
end

--============================================================
-- AirLink数据收发
--============================================================

-- Air780ER2 发送数据信息给 Air1601
local function airlink_sdata_Air1601()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)

        -- 此处代码用于实现 Air780ER2 网络状态的持续检测，并持续给对端设备发送网络状态信息，方便对端设备作应对处理。
        -- 如果有需要，可以打开注释。
        -- local net_state = socket.adapter(socket.LWIP_GP)
        -- if net_state then
        --     airlink.sdata("Air780ER2_IP_READY!!")
        -- else
        --     airlink.sdata("Air780ER2_IP_LOSE!!")
        -- end

        sys.wait(SDATA_INTERVAL)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

--============================================================
-- 测试函数
--============================================================

-- Ping测试
local function ping_test()
    while true do
        -- 必须指定使用哪个网卡
        netdrv.ping(socket.LWIP_GP_GW, NET_GATEWAY)
        sys.wait(PING_INTERVAL)
    end
end

-- Ping响应结果回调
local function ping_res(id, time, dst)
    log.info("ping", id, time, dst)
end

-- HTTP GET请求测试，用于判断Air780EPM的网络访问外网是否正常
local function http_get_test()
    -- 循环发起HTTP GET请求，测试Air780EPM的网络访问外网是否正常
    while 1 do
        log.info("发起HTTP GET请求", HTTP_URL)
        local code, headers, body = http.request("GET", HTTP_URL, nil, nil, {
            timeout = HTTP_TIMEOUT
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
        else
            log.error("HTTP请求失败", "错误码", code)
        end
        sys.wait(HTTP_INTERVAL)
    end
end

--============================================================
-- 事件订阅
--============================================================

-- 订阅airlink的SDATA事件，打印收到的信息
local function airlink_sdata(data)
    log.info("收到AIRLINK_SDATA!!", data)
end

--============================================================
-- 启动入口
--============================================================

-- 订阅PING_RESULT事件
sys.subscribe("PING_RESULT", ping_res)

-- 订阅airlink的SDATA事件
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 初始化网络
sys.taskInit(init_airlink_net)

-- 启动Ping测试
-- sys.taskInit(ping_test)

-- 一个简单的HTTP GET请求测试程序，用于判断 Air780ER2 的网络访问外网是否正常。
-- sys.taskInit(http_get_test)

-- 发送数据给对端
sys.taskInit(airlink_sdata_Air1601)
