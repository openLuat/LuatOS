
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8101_sta_httpsrv"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end)

function test_sta()
    log.info("执行STA连接操作")
    wlan.connect("luatos8888", "12345678")
    sys.wait(8000)
    iperf.server(socket.LWIP_STA)


    sys.wait(5000)
    sys.wait(200)
    wifi_networking()
    
    while 1 do
        log.info("wlan", "info", json.encode(wlan.getInfo()))
           
        sys.wait(30*1000)
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
        log.info("http执行结果", code, headers, body and #body)
 
    end
end

function wifi_networking()
   sys.wait(3000)
    -- AP的ssid和password
    wlan.scan()
    -- sys.wait(500)
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
    end, socket.LWIP_STA)
end

sys.taskInit(function()
    wlan.init()
   
    -- 连接STA测试
    log.info("STA_httpsrv测试启动...")
    test_sta()

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
