local airsta = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false
local sta_state = false
local wifi_net_state = "未打开"
local ssid = "Air8000_"
local password = "12345678"
local number = 0
local event = ""

local LEDA = gpio.setup(146, 0, gpio.PULLUP)

local function test_sta_http()
    local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
    --  注意使用不同的网络出口，可以设置不同的适配器，比如你想通过sta 方式上网就填入adapter=socket.LWIP_STA，如果使用4G 则填入adapter=socket.LWIP_GP
    log.info("http执行结果", code, headers, body and #body)
    if code == 200 then
        wifi_net_state = "STA 连接成功,http 通过STA 上网测试成功"
    end

end

function handle_http_request(fd, method, uri, headers, body)
    log.info("httpsrv", method, uri, json.encode(headers), body)
    if uri == "/led/1" then
        LEDA(1)
        event = "绿灯已打开"
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        LEDA(0)
        event = "绿灯已关闭"
        return 200, {}, "ok"
    elseif uri == "/scan/go" then
        event = "开始搜索WiFi"
        wlan.scan()
        return 200, {}, "ok"
    elseif uri == "/scan/list" then
        return 200, {["Content-Type"]="application/json"}, (json.encode({data=_G.scan_result, ok=true}))
    elseif uri == "/connect" then
        if method == "POST" and body and #body > 2 then
            local jdata = json.decode(body)
            if jdata and jdata.ssid then
                event = "开始链接目标WiFi 路由器"
                sys.timerStart(wlan.connect, 500, jdata.ssid, jdata.passwd)
                return 200, {}, "ok"
            end
        end
        return 400, {}, "ok"
    elseif uri == "/connok" then
        log.info("connok", json.encode({ip=socket.localIP(2)}))
        
        return 200, {["Content-Type"]="application/json"}, json.encode({ip=socket.localIP(2)})
    end
    return 404, {}, "Not Found" .. uri
end
function wifi_networking()
    sys.wait(3000)
    httpsrv.start(80, handle_http_request, socket.LWIP_AP)
    log.info("web", "pls open url http://192.168.4.1/")
end

function scan_done_handle()
    local result = wlan.scanResult()
    _G.scan_result = {}
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(_G.scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(_G.scan_result))
    event = "搜索热点完成,共搜到" ..  #_G.scan_result .. "个,请选择热点,并输入密码后连接"
end


local function start_ap()
    wifi_net_state = "创建AP 热点中,通过AP 热点配置 STA 网络"
    wifi_networking()  --  创建网页服务,可以根据此服务进行配网
    log.info("start_sta")
    ssid = ssid .. wlan.getMac()
    wlan.createAP(ssid, password)

    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
     while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    -- sys.wait(5000)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    wifi_net_state = "创建AP 热点完成"
    event = "请连接热点后,打开192.168.4.1网页"
end
local function start_sta()
    wlan.init()
    sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)
    sys.subscribe("IP_READY", ip_ready_handle)
    start_ap()
    
end
local function stop_sta()
    wlan.stopAP()
end

sys.subscribe("WLAN_AP_INC", function(evt, data)
    
    if evt == "CONNECTED" then
        event = "配置工具连接成功,请打开192.168.4.1"
    elseif evt == "DISCONNECTED" then
        event = "配置工具断开"
    end
    log.info("收到AP事件", evt, data and data:toHex())
end)

sys.subscribe("WLAN_STA_INC", function(evt, data)
    if evt == "CONNECTED" then
        event = "连接成功,连接的SSID 是：" .. data
        wifi_net_state = "STA 连接成功"
        sysplus.taskInitEx(test_sta_http,"test_sta_http")
    elseif evt == "DISCONNECTED" then
        event = "断开了,断开的原因是：" .. data
    end
    log.info("收到STA事件", evt, data )
end)



function airsta.run()       
    log.info("airsta.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"WIFI STA状态:"..wifi_net_state )
        if sta_state then
            lcd.drawStr(0,100,"WIFI ssid:" .. ssid )
            lcd.drawStr(0,120,"WIFI password:" .. password )

            lcd.drawStr(0,150, event)
        end

        lcd.showImage(20,360,"/luadb/back.jpg")
        if sta_state then
            lcd.showImage(130,370,"/luadb/stop.jpg")
        else
            lcd.showImage(130,370,"/luadb/start.jpg")
        end
        

        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束
            return true
        end
    end
end

local function start_sta_task()
    sta_state = true
    start_sta()
end


local function stop_sta_task()
    wlan.disconnect()
    sta_state = false
end
function airsta.start_sta() 
    start_sta()
end

function airsta.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if sta_state then
            sysplus.taskInitEx(stop_sta_task, "stop_sta_task")
        else
            sysplus.taskInitEx(start_sta_task , "start_sta_task")
        end
    end
end

return airsta