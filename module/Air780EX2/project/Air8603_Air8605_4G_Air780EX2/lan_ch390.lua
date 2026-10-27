--[[
@module  lan_ch390
@summary CH390H 以太网 LAN 口模块
@version 1.0
@date    2026.10.23
@usage
本模块实现外挂 CH390H 以太网芯片的 LAN 口功能。

功能说明：
1. CH390H 供电与 SPI 总线初始化
2. 以太网 LAN 口网络配置（静态 IP 192.168.4.1）
3. DHCP 服务器、DNS 代理、NAPT 转发，下挂设备通过 4G 上网
4. 网络状态监控

硬件连接：Air780EX2 SPI0 <-> CH390H
- SPI0：SCK/MOSI/MISO
- CS片选：GPIO8
- LAN_EN供电控制：GPIO27
- INT中断：GPIO22

注意：GPIO27 在本工程中被复用为 LAN_EN，
      因此 airlink_uart_4g 中不再启用 exairlinkwdt 看门狗。

使用示例：
require("lan_ch390")
]]

--============================================================
-- 模块全局配置参数
--============================================================

-- CH390H 硬件配置
local LAN_SPI_ID = 0              -- SPI ID
local LAN_CS_PIN = 8              -- 片选引脚
local LAN_EN_PIN = 27             -- 供电控制引脚
local LAN_INT_PIN = 22            -- 中断引脚
local LAN_SPI_SPEED = 25600000    -- SPI速度

-- 网络配置
local LAN_IP = "192.168.4.1"      -- LAN口IP地址
local LAN_MASK = "255.255.255.0"  -- 子网掩码
local LAN_GW = "192.168.4.1"      -- 网关IP

-- 网络适配器
local LAN_ADAPTER = socket.LWIP_ETH -- 以太网适配器

-- 超时配置
local POWER_WAIT_TIME = 200       -- 供电稳定等待时间：200ms
local LINK_WAIT_TIMEOUT = 30000   -- 链路等待超时：30秒
local NET_WAIT_TIMEOUT = 60000    -- 网络等待超时：60秒
local MONITOR_INTERVAL = 10000    -- 状态监控间隔：10秒

--============================================================
-- 模块加载
--============================================================

-- 加载需要用到的功能模块
local dhcps = require("dhcpsrv")
local dnsproxy = require("dnsproxy")

--============================================================
-- 内部函数声明
--============================================================

-- CH390H供电与SPI总线初始化
local function init_lan_hw()
    -- 打开CH390H供电
    log.info("lan_ch390", "打开CH390H供电 GPIO" .. LAN_EN_PIN)
    gpio.setup(LAN_EN_PIN, 1)
    sys.wait(POWER_WAIT_TIME)

    -- 初始化SPI总线
    local result = spi.setup(LAN_SPI_ID, nil, 0, 0, 8, LAN_SPI_SPEED)
    if result ~= 0 then
        log.error("lan_ch390", "SPI配置失败", result)
        return false
    end

    -- 拉高CS引脚，保持空闲状态
    gpio.setup(LAN_CS_PIN, 1)
    return true
end

-- 等待指定网卡的网络连接建立
-- @param adapter 网络适配器编号
-- @param name 网卡名称，用于日志显示
-- @param timeout 等待超时时间(ms)
-- @return boolean 网络连接是否建立
local function wait_link(adapter, name, timeout)
    local waited = 0
    while netdrv.link(adapter) ~= true do
        sys.wait(100)
        waited = waited + 100
        if waited >= timeout then
            log.warn("lan_ch390", "等待" .. name .. "网络连接超时")
            return false
        end
    end
    log.info("lan_ch390", name .. "网络连接已建立")
    return true
end

-- CH390H网络驱动初始化
local function init_lan_net()
    log.info("lan_ch390", "初始化CH390H网络驱动")
    local result = netdrv.setup(LAN_ADAPTER, netdrv.CH390, {
        spi = LAN_SPI_ID,
        cs = LAN_CS_PIN,
        irq = LAN_INT_PIN
    })
    if result ~= true then
        log.error("lan_ch390", "网络驱动初始化失败")
        return false
    end

    -- 配置LAN口静态IP地址
    local ipv4, mask, gw = netdrv.ipv4(LAN_ADAPTER, LAN_IP, LAN_MASK, LAN_GW)
    log.info("lan_ch390", "IP配置", ipv4, mask, gw)
    return true
end

-- 启动网络服务
local function start_lan_services()
    -- 启动DHCP服务器，为局域网设备分配IP地址
    dhcps.create({adapter = LAN_ADAPTER})
    log.info("lan_ch390", "DHCP服务器已启动")

    -- 启动DNS代理服务，转发DNS查询请求
    dnsproxy.setup(LAN_ADAPTER, socket.LWIP_GP)
    log.info("lan_ch390", "DNS代理服务已启动")

    -- 启用NAPT转发，使用4G网络作为主网关出口
    netdrv.napt(socket.LWIP_GP)
    log.info("lan_ch390", "NAPT转发已启用")
end

-- 网络状态监控
local function lan_monitor()
    while true do
        sys.wait(MONITOR_INTERVAL)
        log.info("lan_ch390", "状态",
            "LAN link", netdrv.link(LAN_ADAPTER),
            "LAN ready", netdrv.ready(LAN_ADAPTER),
            "4G link", netdrv.link(socket.LWIP_GP))
    end
end

-- 主初始化任务
local function init_lan_task()
    if not init_lan_hw() then
        return
    end
    if not init_lan_net() then
        return
    end

    -- 等待以太网链路建立
    wait_link(LAN_ADAPTER, "以太网", LINK_WAIT_TIMEOUT)

    -- 等待4G网络连接建立
    wait_link(socket.LWIP_GP, "4G", NET_WAIT_TIMEOUT)

    -- 启动网络服务
    start_lan_services()
    log.info("lan_ch390", "以太网LAN口初始化完成")
end

--============================================================
-- 启动入口
--============================================================

-- 初始化以太网LAN口
sys.taskInit(init_lan_task)

-- 启动网络状态监控
sys.taskInit(lan_monitor)
