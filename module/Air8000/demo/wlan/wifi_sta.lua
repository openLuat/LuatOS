--[[
@module  wifi_sta
@summary wifi_sta模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage 本文为wifi_sta功能模块,核心逻辑为
1、模块连接wifi；
2、发送http请求,测试网络；
本文件没有对外接口，直接在其他功能模块中require "wifi_sta"就可以加载运行；
]] 
-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end)


function test_sta()
    log.info("执行STA连接操作")
    wlan.connect("test", "HZ88888888")
    -- 等待wifi_sta网络连接成功
    while not socket.adapter(socket.LWIP_STA) do
        -- 在此处阻塞等待wifi连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    while true do
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
        log.info("http执行结果", code, headers, body and #body)
        sys.wait(2000)
    end
end

function ip_ready_handle(ip, adapter)
    log.info("ip_ready_handle",ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("wifi sta 链接成功")
    end
end

sys.taskInit(test_sta)
sys.subscribe("IP_READY", ip_ready_handle)