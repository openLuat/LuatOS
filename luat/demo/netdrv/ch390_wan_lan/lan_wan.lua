-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

-- 引入DHCP服务器和DNS代理模块
dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

-- 网络配置参数
local WAN_SPI_ID = 1        -- WAN口使用SPI1
local WAN_CS_PIN = 12       -- WAN口片选引脚
local WAN_SPI_SPEED = 25600000  -- WAN口SPI速度

local LAN_SPI_ID = 0        -- LAN口使用SPI0  
local LAN_CS_PIN = 8        -- LAN口片选引脚
local LAN_SPI_SPEED = 51200000  -- LAN口SPI速度

local LAN_IP = "192.168.4.1"       -- LAN口IP地址
local LAN_MASK = "255.255.255.0"   -- LAN口子网掩码
local LAN_GW = "192.168.4.1"       -- LAN口网关

-- 网络适配器定义
local WAN_ADAPTER = socket.LWIP_USER1  -- WAN口适配器
local LAN_ADAPTER = socket.LWIP_USER0  -- LAN口适配器


-- 初始化WAN口（外网接口）
local function init_wan()
    log.info("WAN", "开始初始化WAN口")
    
    -- 配置WAN口SPI接口
    local result = spi.setup(
        WAN_SPI_ID,
        nil,
        0,      -- CPHA
        0,      -- CPOL
        8,      -- 数据宽度
        WAN_SPI_SPEED
    )
    
    if result ~= 0 then
        log.error("WAN", "SPI配置失败", result)
        return false
    end
    
    -- 初始化CH390网络驱动（WAN口）
    netdrv.setup(WAN_ADAPTER, netdrv.CH390, {
        spi = WAN_SPI_ID,
        cs = WAN_CS_PIN
    })
    
    -- 启用DHCP客户端，从外网获取IP地址
    netdrv.dhcp(WAN_ADAPTER, true)
    
    log.info("WAN", "WAN口初始化完成")
    return true
end

-- 初始化LAN口（内网接口）
local function init_lan()
    log.info("LAN", "开始初始化LAN口")
    
    -- 配置LAN口SPI接口
    local result = spi.setup(
        LAN_SPI_ID,
        nil,
        0,      -- CPHA
        0,      -- CPOL
        8,      -- 数据宽度
        LAN_SPI_SPEED
    )
    
    if result ~= 0 then
        log.error("LAN", "SPI配置失败", result)
        return false
    end

    -- 初始化CH390网络驱动（LAN口）
    netdrv.setup(LAN_ADAPTER, netdrv.CH390, {
        spi = LAN_SPI_ID,
        cs = LAN_CS_PIN
    })
    sys.wait(3000)
    
    -- 配置LAN网络IP地址
    local ipv4, mask, gw = netdrv.ipv4(LAN_ADAPTER, LAN_IP, LAN_MASK, LAN_GW)
    log.info("LAN", "IP配置", ipv4, mask, gw)
    
    -- 等待以太网连接建立
    while netdrv.link(LAN_ADAPTER) ~= true do
        sys.wait(100)
    end
    
    -- 等待移动网络连接建立
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    
    -- 启动DHCP服务器，为局域网设备分配IP地址
    dhcps.create({adapter = LAN_ADAPTER})
    
    -- 启动DNS代理服务，转发DNS查询请求
    dnsproxy.setup(LAN_ADAPTER, socket.LWIP_GP)
    
    -- 启用NAT转发功能，实现内网与外网的地址转换
    netdrv.napt(socket.LWIP_GP)
    
    -- 如果支持iperf，启动网络性能测试服务器
    if iperf then
        log.info("LAN", "启动iperf服务器端")
        iperf.server(LAN_ADAPTER)
    end
    
    log.info("LAN", "LAN口初始化完成")
    return true
end

-- 设置网络服务
local function setup_network_services()
    log.info("NET", "开始配置网络服务")
    
    -- 等待WAN口获取IP地址
    sys.waitUntil("IP_READY", WAN_ADAPTER)
    log.info("NET", "WAN口已获取IP地址")
    
    -- 等待4G网络连接建立
    while netdrv.link(socket.LWIP_GP) ~= true do
        log.info("NET", "等待4G网络连接...")
        sys.wait(100)
    end
    
    -- 启动DHCP服务器（为LAN口设备分配IP）
    dhcps.create({
        adapter = LAN_ADAPTER
    })
    log.info("NET", "DHCP服务器已启动")
    
    -- 启动DNS代理服务（LAN->4G DNS转发）
    dnsproxy.setup(LAN_ADAPTER, socket.LWIP_GP)
    log.info("NET", "DNS代理服务已启动")
    
    -- 启用NAT转发功能（LAN->4G地址转换）
    netdrv.napt(socket.LWIP_GP)
    log.info("NET", "NAT转发已启用")
    
    -- 启动网络性能测试服务器（可选）
    if iperf then
        iperf.server(LAN_ADAPTER)
        log.info("NET", "iPerf服务器已启动")
    end
    
    log.info("NET", "网络服务配置完成")
end

-- 网络状态监控
local function network_monitor()
    while true do
        sys.wait(10000)  -- 每10秒检查一次
        
        -- 检查WAN口状态
        local wan_link = netdrv.link(WAN_ADAPTER)
        local wan_ready = netdrv.ready(WAN_ADAPTER)
        
        -- 检查LAN口状态  
        local lan_link = netdrv.link(LAN_ADAPTER)
        local lan_ready = netdrv.ready(LAN_ADAPTER)
        
        -- 检查4G网络状态
        local gprs_link = netdrv.link(socket.LWIP_GP)
        local gprs_ready = netdrv.ready(socket.LWIP_GP)
        
        log.info("状态", string.format("WAN: link=%s ready=%s, LAN: link=%s ready=%s, 4G: link=%s ready=%s",
            tostring(wan_link), tostring(wan_ready),
            tostring(lan_link), tostring(lan_ready),
            tostring(gprs_link), tostring(gprs_ready)))
        
        -- 输出内存使用情况
        log.info("内存", "Lua:", rtos.meminfo())
        log.info("内存", "Sys:", rtos.meminfo("sys"))
    end
end

-- WAN口初始化任务
sys.taskInit(function()
    if init_wan() then
        log.info("INIT", "WAN口初始化成功")
    else
        log.error("INIT", "WAN口初始化失败")
    end
end)

-- LAN口初始化任务
sys.taskInit(function()
    sys.wait(2000)  -- 延迟启动，避免与WAN口冲突
    
    if init_lan() then
        log.info("INIT", "LAN口初始化成功")
        -- LAN口初始化成功后，启动网络服务
        setup_network_services()
    else
        log.error("INIT", "LAN口初始化失败")
    end
end)

-- 网络监控任务
sys.taskInit(network_monitor)

-- 事件处理
sys.subscribe("IP_READY", function(adapter)
    log.info("事件", "IP_READY", adapter)
    if adapter == WAN_ADAPTER then
        log.info("事件", "WAN口IP就绪")
    elseif adapter == LAN_ADAPTER then
        log.info("事件", "LAN口IP就绪")
    elseif adapter == socket.LWIP_GP then
        log.info("事件", "4G网络IP就绪")
    end
end)

sys.subscribe("IP_LOSE", function(adapter)
    log.info("事件", "IP_LOSE", adapter)
    if adapter == WAN_ADAPTER then
        log.warn("事件", "WAN口IP丢失")
    elseif adapter == LAN_ADAPTER then
        log.warn("事件", "LAN口IP丢失")
    elseif adapter == socket.LWIP_GP then
        log.warn("事件", "4G网络IP丢失")
    end
end)
