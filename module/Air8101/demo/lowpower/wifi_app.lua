--[[
本文件为WIFI网络连接管理应用功能模块，核心业务逻辑为：
1、初始化WIFI网络；
2、连接WIFI路由器；
3、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；

本文件没有对外接口；
]] ----填写WIFI账号密码，选择是否使用DTIM10--------------------------------------
local ssid = "茶室-降功耗,找合宙!" -- WIFI名称
local password = "Air123456" -- WIFI密码
local DTIM10_mode = false -- 是否开启DTIM10模式。--true 需要      --false 不需要
--------------------------------------------------------------------------------

local function ip_ready_func()
    log.info("wlan_connect.ip_ready_func", "IP_READY")
    if DTIM10_mode then
        pm.power(pm.WIFI_STA_DTIM, 10)
        log.info("DRIM10设置完成")
    end
end

local function ip_lose_func()
    log.warn("wlan_connect.ip_lose_func", "IP_LOSE")
end

-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察WIFI的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
wlan.init()
-- 连接WIFI热点，连接结果会通过"IP_READY"或者"IP_LOSE"消息通知
-- Air8101仅支持2.4G的WIFI，不支持5G的WIFI
-- 此处前两个参数表示WIFI热点名称以及密码，更换为自己测试时的真实参数即可
-- 第三个参数1表示WIFI连接异常时，内核固件会自动重连

-- 判断是否开启DTIM10模式，默认DTIM1。
-- 低功耗模式下，网络在线，随时响应服务器命令，CPU 降频运行，外设功能部分可用:3.3v供电，
-- DTIM10的平均电流为480uA，DTIM1的平均电流为1.2mA;
-- DTIM1 和 DTIM10 的核心区别有：
--      DTIM1不会丢失WIFI AP路由器发送给wiFi station的广播帧和组播帧，DTIM10会丢失，
--      一般来说，对于iot应用，丢失广播帧和组播帧对产品应用没有什么影响，只要单播帧不丢失就行;
--      一般来说，WiFiAP路由器发送Beacon帧的间隔是100毫秒，DTIM1最长延迟100毫秒可以收到WIFI AP路由器发送过来的数据，
--      DTIM10最长演示1000毫秒可以收到WIFI AP路由器发送过来的数据。可以根据自己项目对功耗以及数据收发时延的要求选择合适的DTIM配置:xq
wlan.connect(ssid, password, 1)

-- WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

-- WIFI断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功
