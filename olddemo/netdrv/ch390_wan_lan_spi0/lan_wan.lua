--[[
=======================================================================
              CH390双网口SPI0复用演示程序核心逻辑
=======================================================================

功能概述：
本程序演示如何在单个SPI总线上同时连接两个CH390网络芯片，实现完整的
WAN+LAN双网口路由器功能。

SPI复用技术原理：
1. 【总线共享】两个CH390芯片共享SPI0的SCK、MOSI、MISO三条信号线
2. 【片选分离】通过不同的CS引脚(GPIO8/GPIO12)实现设备选择
3. 【时序互斥】使用SPI锁定机制确保同一时刻只有一个设备通信
4. 【驱动隔离】每个CH390有独立的网络适配器和协议栈

硬件连接：
  MCU (Air780EPM)        CH390-WAN          CH390-LAN
  ├─ SPI0_SCK     ─────┬─ SCK          ┌─ SCK
  ├─ SPI0_MOSI    ─────┼─ MOSI         ├─ MOSI  
  ├─ SPI0_MISO    ─────┼─ MISO         ├─ MISO
  ├─ GPIO12       ─────┘  CS           │
  ├─ GPIO8        ─────────────────────┘  CS
  ├─ GPIO29       ─────── 3.3V供电控制  │
  └─ GPIO20       ─────────────────────── 3.3V供电控制

网络拓扑：
  Internet ←→ [WAN口CH390] ←→ [Air780EPM] ←→ [LAN口CH390] ←→ 内网设备
              CS=GPIO12      4G/路由转发     CS=GPIO8      192.168.4.x

技术特点：
- ✅ 完全硬件SPI复用，无需软件SPI
- ✅ 25.6MHz高速SPI通信
- ✅ 自动SPI总线锁定/解锁机制
- ✅ 支持并发网络数据处理
- ✅ 独立的DHCP、DNS、NAT服务

关键点：
1. 两个网口使用相同的SPI总线（SPI0）
2. 每个网口使用不同的CS片选引脚（WAN=GPIO12，LAN=GPIO8）
3. SPI总线只需要配置一次，CS引脚需要单独初始化
4. 通过LuatOS的SPI锁定机制保证通信安全

=======================================================================
]]

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

-- 引入DHCP服务器和DNS代理模块
dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

-- 网络配置参数
local WAN_SPI_ID = 0        -- WAN口使用SPI0（复用）
local WAN_CS_PIN = 12        -- WAN口片选引脚
local WAN_SPI_SPEED = 25600000  -- WAN口SPI速度

local LAN_SPI_ID = 0        -- LAN口使用SPI0（复用）
local LAN_CS_PIN = 8       -- LAN口片选引脚（必须与WAN口不同）
local LAN_SPI_SPEED = 25600000  -- LAN口SPI速度

local BOTH_SPI_SPEED = 25600000  -- SPI速度

local LAN_IP = "192.168.4.1"       -- LAN口IP地址
local LAN_MASK = "255.255.255.0"   -- LAN口子网掩码
local LAN_GW = "192.168.4.1"       -- LAN口网关

-- 网络适配器定义
local WAN_ADAPTER = socket.LWIP_USER1  -- WAN口适配器
local LAN_ADAPTER = socket.LWIP_USER0  -- LAN口适配器

-- 网口初始化配置选项
-- "LAN" - 只初始化LAN口
-- "WAN" - 只初始化WAN口  
-- "BOTH" - 同时初始化WAN口和LAN口
local INIT_MODE = "BOTH"

-- 同时初始化WAN口和LAN口
local function init_wan_lan()
    log.info("INIT", "开始初始化网口，模式：" .. INIT_MODE)
    
    -- 根据模式选择SPI ID和速度
    local spi_id, spi_speed
    if INIT_MODE == "WAN" then
        spi_id = WAN_SPI_ID
        spi_speed = WAN_SPI_SPEED
    elseif INIT_MODE == "LAN" then
        spi_id = LAN_SPI_ID
        spi_speed = LAN_SPI_SPEED
    else -- INIT_MODE == "BOTH"
        spi_id = WAN_SPI_ID  -- 复用模式使用WAN口的SPI ID
        spi_speed = BOTH_SPI_SPEED
    end
    
    -- 配置SPI接口（只需要配置一次SPI总线）
    local result = spi.setup(
        spi_id,
        nil,        -- CS由netdrv管理，这里不设置
        0,          -- CPHA
        0,          -- CPOL
        8,          -- 数据宽度
        spi_speed
    )
    if result ~= 0 then
        log.error("INIT", "SPI配置失败", result)
        return false
    end
    
    -- 根据配置初始化对应的网口
    if INIT_MODE == "WAN" or INIT_MODE == "BOTH" then
        -- 初始化WAN口CS引脚
        gpio.setup(WAN_CS_PIN, 1)  -- 拉高CS引脚（空闲状态）
        gpio.setup(LAN_CS_PIN, 1)  -- 拉高CS引脚，防止干扰
        
        -- 初始化CH390网络驱动（WAN口）
        log.info("INIT", "初始化WAN口网络驱动")
        netdrv.setup(WAN_ADAPTER, netdrv.CH390, {
            spi = WAN_SPI_ID,
            cs = WAN_CS_PIN
        })
        
        -- 启用DHCP客户端，从外网获取IP地址
        netdrv.dhcp(WAN_ADAPTER, true)
        
        sys.wait(1000)  -- 等待WAN口初始化稳定
        log.info("INIT", "WAN口初始化完成，使用SPI", WAN_SPI_ID, "CS引脚", WAN_CS_PIN)
    end
    
    if INIT_MODE == "LAN" or INIT_MODE == "BOTH" then
        -- 初始化LAN口CS引脚
        gpio.setup(LAN_CS_PIN, 1)  -- 拉高CS引脚（空闲状态）
        gpio.setup(WAN_CS_PIN, 1)  -- 拉高CS引脚，防止干扰
        
        -- 初始化CH390网络驱动（LAN口）
        log.info("INIT", "初始化LAN口网络驱动")
        netdrv.setup(LAN_ADAPTER, netdrv.CH390, {
            spi = LAN_SPI_ID,
            cs = LAN_CS_PIN
        })
        
        sys.wait(2000)  -- 等待LAN口初始化稳定
        
        -- 配置LAN网络IP地址
        local ipv4, mask, gw = netdrv.ipv4(LAN_ADAPTER, LAN_IP, LAN_MASK, LAN_GW)
        log.info("LAN", "IP配置", ipv4, mask, gw)
        log.info("INIT", "LAN口初始化完成，使用SPI", LAN_SPI_ID, "CS引脚", LAN_CS_PIN)
    end
    
    log.info("INIT", "网口初始化完成，模式：" .. INIT_MODE)
    return true
end

-- 等待网络连接并设置服务
local function setup_network_services()
    log.info("NET", "开始配置网络服务")
    
    -- 根据初始化模式等待对应网口连接
    if INIT_MODE == "LAN" or INIT_MODE == "BOTH" then
        -- 等待LAN口以太网连接建立
        while netdrv.link(LAN_ADAPTER) ~= true do
            log.info("NET", "等待LAN口以太网连接...")
            sys.wait(100)
        end
        log.info("NET", "LAN口以太网连接已建立")
    end
    
    -- 等待4G网络连接建立（用于NAT转发）
    if INIT_MODE == "LAN" or INIT_MODE == "BOTH" then
        while netdrv.link(socket.LWIP_GP) ~= true do
            log.info("NET", "等待4G网络连接...")
            sys.wait(100)
        end
        log.info("NET", "4G网络连接已建立")
        
        -- 启动DHCP服务器，为局域网设备分配IP地址
        dhcps.create({adapter = LAN_ADAPTER})
        log.info("NET", "DHCP服务器已启动")
        
        -- 启动DNS代理服务，转发DNS查询请求
        dnsproxy.setup(LAN_ADAPTER, socket.LWIP_GP)
        log.info("NET", "DNS代理服务已启动")
        
        -- 启用NAT转发功能，实现内网与外网的地址转换
        netdrv.napt(socket.LWIP_GP)
        log.info("NET", "NAT转发已启用")
        
        -- 如果支持iperf，启动网络性能测试服务器
        if iperf then
            log.info("NET", "启动iperf服务器端")
            iperf.server(LAN_ADAPTER)
        end
    end
    
    log.info("NET", "网络服务配置完成")
end

-- 网络状态监控
local function network_monitor()
    while true do
        sys.wait(10000)  -- 每10秒检查一次
        
        local status_info = {}
        
        -- 根据初始化模式检查对应网口状态
        if INIT_MODE == "WAN" or INIT_MODE == "BOTH" then
            local wan_link = netdrv.link(WAN_ADAPTER)
            local wan_ready = netdrv.ready(WAN_ADAPTER)
            table.insert(status_info, string.format("WAN: link=%s ready=%s", tostring(wan_link), tostring(wan_ready)))
        end
        
        if INIT_MODE == "LAN" or INIT_MODE == "BOTH" then
            local lan_link = netdrv.link(LAN_ADAPTER)
            local lan_ready = netdrv.ready(LAN_ADAPTER)
            table.insert(status_info, string.format("LAN: link=%s ready=%s", tostring(lan_link), tostring(lan_ready)))
        end
        
        -- 检查4G网络状态
        local gprs_link = netdrv.link(socket.LWIP_GP)
        local gprs_ready = netdrv.ready(socket.LWIP_GP)
        table.insert(status_info, string.format("4G: link=%s ready=%s", tostring(gprs_link), tostring(gprs_ready)))
        
        log.info("状态", table.concat(status_info, ", "))
        
        -- 输出内存使用情况
        log.info("内存", "Lua:", rtos.meminfo())
        log.info("内存", "Sys:", rtos.meminfo("sys"))
    end
end

-- 主初始化任务
sys.taskInit(function()
    if init_wan_lan() then
        log.info("INIT", "网口初始化成功")
        -- 初始化成功后，启动网络服务
        setup_network_services()
    else
        log.error("INIT", "网口初始化失败")
    end
end)

-- 网络监控任务
sys.taskInit(network_monitor)

-- 事件处理
sys.subscribe("IP_READY", function(adapter)
    log.info("事件", "IP_READY", adapter)
    if adapter == WAN_ADAPTER and (INIT_MODE == "WAN" or INIT_MODE == "BOTH") then
        log.info("事件", "WAN口IP就绪")
    elseif adapter == LAN_ADAPTER and (INIT_MODE == "LAN" or INIT_MODE == "BOTH") then
        log.info("事件", "LAN口IP就绪")
    elseif adapter == socket.LWIP_GP then
        log.info("事件", "4G网络IP就绪")
    end
end)

sys.subscribe("IP_LOSE", function(adapter)
    log.info("事件", "IP_LOSE", adapter)
    if adapter == WAN_ADAPTER and (INIT_MODE == "WAN" or INIT_MODE == "BOTH") then
        log.warn("事件", "WAN口IP丢失")
    elseif adapter == LAN_ADAPTER and (INIT_MODE == "LAN" or INIT_MODE == "BOTH") then
        log.warn("事件", "LAN口IP丢失")
    elseif adapter == socket.LWIP_GP then
        log.warn("事件", "4G网络IP丢失")
    end
end)
