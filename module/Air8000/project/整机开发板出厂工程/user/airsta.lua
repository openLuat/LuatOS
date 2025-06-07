local airsta = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false
local ap_state = false
local wifi_net_state = "未打开"
local ssid = "Air8000_"
local password = "12345678"
local number = 0
local event = ""


local function start_sta()
    wifi_net_state = "已打开，创建路由中"
    wlan.init()
    log.info("start_sta")
    ssid = ssid .. wlan.getMac()
    wlan.createAP(ssid, password)

    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
     while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    -- sys.wait(5000)
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            wifi_net_state = "已打开，热点可用"
            log.info("start_sta ok")
            break
        end
        sys.wait(500)
    end
end

local function stop_ap()
    wlan.stopAP()
end

sys.subscribe("WLAN_AP_INC", function(evt, data)
    event = evt.. ",对方的MAC为：" .. data:toHex()
    if evt == "CONNECTED" then
        number = number + 1
    elseif evt == "DISCONNECTED" then
        number = number - 1
    end
    log.info("收到AP事件", evt, data and data:toHex())
end)
sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
    event = "ping" .. id .. time .. dst
end)


function airsta.run()       
    log.info("airsta.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"WIFI AP状态:"..wifi_net_state )
        if ap_state then
            lcd.drawStr(0,120,"WIFI ssid:" .. ssid )
            lcd.drawStr(0,140,"WIFI password:" .. password )
            lcd.drawStr(0,160,"WIFI MAC:" .. wlan.getMac() )
            lcd.drawStr(0,180,"链接WIFI 数量:" .. number)
            lcd.drawStr(0,200, event)
        end

        lcd.showImage(20,360,"/luadb/back.jpg")
        if ap_state then
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
    ap_state = true
    start_sta()
end


local function stop_ap_task()
    stop_ap()
    ap_state = false
end
function airsta.start_sta() 
    start_sta()
end

function airsta.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if ap_state then
            sysplus.taskInitEx(stop_ap_task, "stop_ap_task")
        else
            sysplus.taskInitEx(start_sta_task , "start_sta_task")
        end
    end
end

return airsta