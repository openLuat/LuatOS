--[[
@module  airlink_wifi_ap
@summary Airlink WiFi AP模块 - 通过SPI或UART连接Air6205创建WiFi热点
@version 1.0
@date    2026.09.14
@author  江访
@usage
本模块封装了Airlink初始化和WiFi AP创建的完整流程，支持SPI和UART两种接口。

使用示例：
local airlink_wifi_ap = require "airlink_wifi_ap"
airlink_wifi_ap.open({
    mode     = "spi",
    ssid     = "luatos_1234",
    password = "",
    spi_id   = 0,
    spi_cs   = 8,
    spi_rdy  = 33,
    spi_irq  = 24,
    spi_speed = 8*1000000,
    wifi_rst = 32,
})

参考文档：
- Airlink协议：docs/root/docs/osapi/core/airlink.md
- exremotefile扩展库：script/libs/exremotefile.lua
--]]

local dnsproxy = require("dnsproxy")
local dhcpsrv  = require("dhcpsrv")

local M = {}

-- 默认配置参数
local default_opts = {
    -- 通用参数
    mode        = "spi",         -- 通信模式："spi" 或 "uart"
    ssid        = "luatos_wifi", -- WiFi热点名称
    password    = "",            -- WiFi密码（留空=无密码）
    server_addr = "192.168.4.1", -- AP网关IP地址
    -- SPI参数（mode="spi"时使用）
    spi_id      = 0,             -- SPI接口ID
    spi_cs      = 8,             -- SPI片选引脚GPIO号
    spi_rdy     = 33,            -- SPI就绪信号引脚GPIO号
    spi_irq     = 24,            -- SPI中断信号引脚GPIO号
    spi_speed   = 8*1000000,     -- SPI时钟频率（Hz）
    wifi_rst    = 32,            -- WiFi模块复位引脚GPIO号
    -- UART参数（mode="uart"时使用）
    uart_id     = 2,             -- UART接口ID
    uart_baud   = 2000000,       -- UART波特率
    uart_tx     = 12,            -- UART TX引脚GPIO号
    uart_rx     = 13,            -- UART RX引脚GPIO号
}

local opts = nil

--============================================================
-- SPI模式：初始化Airlink SPI通信通道
-- 流程：复位WiFi模块 → 配置SPI参数 → 初始化airlink → 注册网络设备 → 启动SPI主机
--============================================================
local function init_airlink_spi()
    log.info("airlink_wifi_ap", "初始化Airlink SPI通道")
    log.info("airlink_wifi_ap", "SPI_ID=" .. opts.spi_id ..
        " CS=" .. opts.spi_cs ..
        " RDY=" .. opts.spi_rdy ..
        " IRQ=" .. opts.spi_irq ..
        " SPEED=" .. opts.spi_speed)

    -- 复位WiFi模块（拉低RST引脚100ms后再拉高）
    if gpio and opts.wifi_rst then
        gpio.setup(opts.wifi_rst, 0)
        sys.wait(100)
        gpio.setup(opts.wifi_rst, 1)
        sys.wait(500)
        log.info("airlink_wifi_ap", "WiFi模块已复位")
    end

    -- 等待WiFi芯片上电稳定
    sys.wait(2000)

    -- 配置Airlink SPI参数
    airlink.config(airlink.CONF_SPI_ID, opts.spi_id)
    airlink.config(airlink.CONF_SPI_CS, opts.spi_cs)
    airlink.config(airlink.CONF_SPI_RDY, opts.spi_rdy)
    airlink.config(airlink.CONF_SPI_IRQ, opts.spi_irq)
    airlink.config(airlink.CONF_SPI_SPEED, opts.spi_speed)

    -- 初始化airlink并注册STA和AP网络设备
    -- STA：用于airlink内部通信
    -- AP：用于WiFi热点的网络接口
    airlink.init()
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP,  netdrv.WHALE)

    -- 启动Airlink SPI主机模式
    airlink.start(airlink.MODE_SPI_MASTER)

    sys.wait(2000)
    log.info("airlink_wifi_ap", "Airlink SPI通道已建立")
end

--============================================================
-- UART模式：初始化Airlink UART通信通道
-- 流程：配置UART引脚 → 配置UART参数 → 初始化airlink → 注册网络设备 → 启动UART
--============================================================
local function init_airlink_uart()
    log.info("airlink_wifi_ap", "初始化Airlink UART通道")
    log.info("airlink_wifi_ap", "UART_ID=" .. opts.uart_id ..
        " BAUD=" .. opts.uart_baud ..
        " TX=" .. opts.uart_tx ..
        " RX=" .. opts.uart_rx)

    -- 配置UART引脚（先下拉再释放，确保初始状态正确）
    gpio.setup(opts.uart_tx, nil, gpio.PULLDOWN)
    gpio.setup(opts.uart_rx, nil, gpio.PULLDOWN)
    sys.wait(2000)
    gpio.close(opts.uart_tx)
    gpio.close(opts.uart_rx)

    -- 配置UART参数
    uart.setup(opts.uart_id, opts.uart_baud, 8, 1)
    sys.wait(100)

    -- 配置Airlink使用UART通道
    airlink.config(airlink.CONF_UART_ID, opts.uart_id)
    airlink.init()
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    airlink.start(airlink.MODE_UART)

    sys.wait(2000)
    log.info("airlink_wifi_ap", "Airlink UART通道已建立")
end

--============================================================
-- 创建WiFi AP热点
-- 流程：初始化WiFi → 创建AP → 配置IP → 等待就绪 → 启动DHCP → 等待稳定
-- 参考：exremotefile.lua 的 create_ap 函数
--============================================================
local function create_ap()
    log.info("airlink_wifi_ap", "创建AP热点: " .. opts.ssid)

    -- 初始化WiFi（通过airlink RPC发送到Air6205）
    wlan.init()
    sys.wait(100)

    -- 创建WiFi AP热点
    wlan.createAP(opts.ssid, opts.password)

    -- 配置AP网络IP地址
    netdrv.ipv4(socket.LWIP_AP, opts.server_addr, "255.255.255.0", "0.0.0.0")

    -- 等待AP网络适配器就绪
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end

    -- 启动DNS代理（WiFi客户端的DNS请求转发到上游网络）
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)

    -- 启动DHCP服务器（为WiFi客户端自动分配IP地址）
    dhcpsrv.create({adapter = socket.LWIP_AP})

    -- 等待AP网卡完全稳定（Air6205需要额外时间完成AP初始化）
    sys.wait(2000)

    -- 发布AP创建完成事件
    sys.publish("AP_CREATE_OK")
    log.info("airlink_wifi_ap", "AP热点创建成功")
end

--============================================================
-- 对外接口
--============================================================

--[[
启动WiFi AP热点
@param table config 配置参数表
    mode        : 通信模式，"spi"或"uart"（默认"spi"）
    ssid        : WiFi热点名称（默认"luatos_wifi"）
    password    : WiFi密码，留空表示无密码（默认""）
    server_addr : AP网关IP（默认"192.168.4.1"）
    -- SPI参数（mode="spi"时使用）
    spi_id      : SPI接口ID（默认0）
    spi_cs      : SPI片选引脚GPIO号（默认8）
    spi_rdy     : SPI就绪引脚GPIO号（默认33）
    spi_irq     : SPI中断引脚GPIO号（默认24）
    spi_speed   : SPI时钟频率Hz（默认8000000）
    wifi_rst    : WiFi复位引脚GPIO号（默认32）
    -- UART参数（mode="uart"时使用）
    uart_id     : UART接口ID（默认2）
    uart_baud   : UART波特率（默认2000000）
    uart_tx     : UART TX引脚GPIO号（默认12）
    uart_rx     : UART RX引脚GPIO号（默认13）
@return boolean 是否成功
]]
function M.open(config)
    -- 合并默认配置和用户配置
    opts = {}
    for k, v in pairs(default_opts) do
        opts[k] = v
    end
    if config then
        for k, v in pairs(config) do
            opts[k] = v
        end
    end

    -- 步骤1：初始化airlink通信通道
    if opts.mode == "spi" then
        init_airlink_spi()
    else
        init_airlink_uart()
    end

    -- 步骤2：创建WiFi AP热点
    create_ap()

    return true
end

--[[
关闭WiFi AP
]]
function M.close()
    if airlink then
        airlink.pause(1)
    end
    log.info("airlink_wifi_ap", "已关闭")
end

return M
