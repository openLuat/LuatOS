-- nconv: var2-4 fn2-5 tag-short
--[[
@module  netdrv_wifi
@summary "WIFI STA网卡"驱动模块
@version 1.0
@date    2025.07.01
@author  马梦阳
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、初始化WIFI网络；
2、连接WIFI路由器；
3、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]
local function irf(ip, ad)
    if ad and ad == socket.LWIP_STA then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(ad, 1, "223.5.5.5")
        socket.setDNS(ad, 2, "114.114.114.114")
        log.info("nwf.ip", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end

local function ilf(ad)
    if ad and ad == socket.LWIP_STA then
        log.warn("nwf.los", "IP_LOSE")
    end
end

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察WIFI的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", irf)
sys.subscribe("IP_LOSE", ilf)

local function wsf(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("sta", evt, data)
end

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", wsf)

-- 初始化防重入标识
local ad = false

local function nwtf()
    socket.dft(socket.LWIP_STA)
    if ad then return end
    ad = true
    -- 使用pcall保护，避免首次开机时airlink未就绪导致的死机
    local ok, err = pcall(function()
        -- 配置AirLink SPI参数
        airlink.config(airlink.CONF_SPI_ID, 1)
        airlink.config(airlink.CONF_SPI_CS, 8)
        airlink.config(airlink.CONF_SPI_RDY, 14)
        airlink.config(airlink.CONF_SPI_SPEED, 2 * 1000000)
        airlink.init()
        log.info("reg", "注册STA和AP设备")
        netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
        netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
        airlink.start(airlink.MODE_SPI_MASTER)
        sys.wait(1000)
        wlan.init()
        wlan.setMode(wlan.STATIONAP)
        sys.publish("WIFI_READY")
    end)
    if not ok then
        log.error("nwf", "airlink初始化异常", err)
    end
end

-- 启动一个task，task的处理函数为netdrv_wifi_task_func
-- 在处理函数中初始化airlink和wifi
-- 因为airlink和wlan初始化要求必须在task中被调用，所以此处启动一个task
sys.taskInit(nwtf)
