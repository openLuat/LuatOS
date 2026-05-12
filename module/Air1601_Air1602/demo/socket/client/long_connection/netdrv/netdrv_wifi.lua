--[[
@module  netdrv_wifi
@summary "WIFI STA网卡"驱动模块
@version 1.0
@date    2025.07.01
@author  马梦阳
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、通过exnetif.set_priority_order配置airlink_wifi网卡；
   exnetif内部自动完成WiFi硬件初始化和airlink桥接初始化；
2、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]

local exnetif = require "exnetif"

-- IP就绪回调
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_wifi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end

-- IP丢失回调
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_STA then
        log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
    end
end

-- WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- WIFI断网后，内核固件会产生一个"IP_LOSE"消息
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- WiFi STA状态事件回调
local function wifi_sta_func(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end
sys.subscribe("WLAN_STA_INC", wifi_sta_func)

-- 初始化WiFi网卡任务
local function netdrv_wifi_task_func()
    -- 配置airlink WiFi单网卡
    -- 实际测试时，根据自己要连接的WiFi热点信息修改ssid和password参数
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,
                airlink_type = airlink.MODE_UART,
                airlink_uart_id = 3,
                airlink_uart_baud = 2000000,
                ssid = "116",
                password = "hezhou666"
            }
        }
    })
end

-- 启动一个task，task的处理函数为netdrv_wifi_task_func
-- 因为exnetif.set_priority_order要求必须在task中被调用，所以此处启动一个task
sys.taskInit(netdrv_wifi_task_func)
