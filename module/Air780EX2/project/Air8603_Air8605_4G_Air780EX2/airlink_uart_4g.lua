--[[
@module  airlink_uart_4g
@summary AirLink UART 4G 网络桥接模块
@version 1.0
@date    2026.10.23
@usage
本模块实现 Air780EX2 通过 AirLink UART 把 4G 网络桥接给对端主控模组的功能。

主要功能：
1. AirLink UART 模式初始化（UART1，2Mbps）
2. 桥接网络设备创建与 IP 配置（192.168.111.2/24，网关 192.168.111.1）
3. NAPT 地址端口转换，使用 4G 网络作为出口
4. DNS 代理
5. AirLink SDATA 数据收发

硬件连接：Air780EX2 UART1 <-> 对端主控模组 UART

注意：GPIO27 在本工程中作为 CH390H 的 LAN_EN，
     因此不加载 AirLink 的 exairlinkwdt 看门狗。

使用示例：
require("airlink_uart_4g")
]]

--============================================================
-- 模块全局配置参数
--============================================================

-- AirLink UART 配置
local AIRLINK_UART_ID = 1              -- UART ID
local AIRLINK_BAUD = 2000000           -- 波特率：2M
local AIRLINK_DATA_BITS = 8            -- 数据位：8
local AIRLINK_STOP_BITS = 1            -- 停止位：1

-- 网络配置
local NET_LOCAL_IP = "192.168.111.2"   -- 本地IP
local NET_MASK = "255.255.255.0"       -- 子网掩码
local NET_GATEWAY = "192.168.111.1"    -- 网关IP

-- 超时配置
local NET_WAIT_TIMEOUT = 10000         -- 网络等待超时：10秒

--============================================================
-- 模块加载
--============================================================

local dnsproxy = require("dnsproxy")

--============================================================
-- 网络初始化
--============================================================

-- 初始化 AirLink UART，并把 4G 网络桥接给对端设备
local function init_airlink_net()
    -- 初始化UART
    uart.setup(
        AIRLINK_UART_ID,     -- 串口id
        AIRLINK_BAUD,        -- 波特率
        AIRLINK_DATA_BITS,   -- 数据位
        AIRLINK_STOP_BITS    -- 停止位
    )
    airlink.init()
    airlink.config(airlink.CONF_UART_ID, AIRLINK_UART_ID)
    sys.wait(100)
    airlink.start(airlink.MODE_UART)

    -- 创建桥接网络设备
    log.info("airlink_uart_4g", "创建桥接网络设备")
    netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)
    -- 配置IPv4地址
    log.info("airlink_uart_4g", "配置IPv4地址", NET_LOCAL_IP, NET_MASK, NET_GATEWAY)
    netdrv.ipv4(socket.LWIP_GP_GW, NET_LOCAL_IP, NET_MASK, NET_GATEWAY)
    sys.wait(100)
    -- 等待网络就绪，设置超时时间
    sys.waitUntil("IP_READY", NET_WAIT_TIMEOUT)
    -- 配置NAPT，使用4G网络作为主网关出口
    netdrv.napt(socket.LWIP_GP)
    -- 设置DNS代理
    dnsproxy.setup(socket.LWIP_GP_GW, socket.LWIP_GP)
    log.info("airlink_uart_4g", "网卡", netdrv.ready(socket.LWIP_GP_GW))
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

sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 初始化网络
sys.taskInit(init_airlink_net)
