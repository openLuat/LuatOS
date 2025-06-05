local airgps = {}

local gps_state = "未定位"
local gps_is_run  = false
local lat = ""
local lng = ""
local total_sats = 0
local speed = 0
local degrees = ""
local location = ""
local move = "静止"
local time = ""

local function setup_gps()
    gps_is_run = true
    gps_state = "定位中"
    local gnss = require("agps_icoe")
    log.debug("提醒", "室内无GNSS信号,定位不会成功, 要到空旷的室外,起码要看得到天空")
    pm.power(pm.GPS, true)
    gnss.setup({
        uart_id=2,
        uart_forward = uart.VUART_0, -- 转发到虚拟串口,方便对接GnssToolKit3
        debug=true,
        sys=1
    })
    gnss.start() --初始化gnss
    gnss.agps() --使用agps辅助定位
    --循环打印解析后的数据，可以根据需要打开对应注释

end
local function gps_state_get()
    local gsv =  libgnss.getGsv()
    if gsv and  gsv.total_sats then
        total_sats = gsv.total_sats
    end
    local vtg =  libgnss.getVtg()
    if vtg and  gsv.speed_kph then
        speed = gsv.speed_kph
    end
    if vtg and  gsv.true_track_degrees then
        degrees = gsv.true_track_degrees
    end
    if vtg and  gsv.speed_kph then
        speed = gsv.speed_kph
    end
    if gps_state == "定位成功" then
        rmc = libgnss.getRmc(2)
        log.info("nmea", "rmc", json.encode(libgnss.getRmc(2)))
        lat = rmc.lat
        lng = rmc.lng
        variation = rmc.variation
        
        time = rmc.year .. "年" .. rmc.month .. "月" .. rmc.day .. "日" .. rmc.hour .. "时" .. (rmc.min + 8) .. "分"  ..   rmc.sec .. "秒" 
        -- speed = libgnss.getIntLocation(2)
    end
end


-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "locStr", locStr)
        gps_state = "定位成功"
        -- if locStr then
        --     -- 存入文件,方便下次AGNSS快速定位
        --     io.writeFile("/gnssloc", locStr)
        -- end
    elseif event == "LOSE" then
        gps_state = "定位失败"
    end
end)

function airgps.run()       -- TTS 播放主程序
    log.info("airgps.run")
    run_state = 1
    
    lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
    while true do
        lcd.clear(_G.bkcolor) 
        sys.wait(100)
        
        gps_state_get()
        -- log.info("airgps.run 11 ")
        
        lcd.drawStr(0,80,"GPS 状态:" .. gps_state)
        lcd.drawStr(0,110,"经度:" .. lng  .. " 纬度:".. lat)
        lcd.drawStr(0,140,"卫星数:" .. total_sats)
        lcd.drawStr(0,170,"速度:" .. speed .. "千米/小时")
        lcd.drawStr(0,200,"方向:" .. degrees)
        lcd.drawStr(0,230,"位置:" .. location)
        lcd.drawStr(0,260,"时间:" .. time)
        lcd.drawStr(0,290,"运动状态:" .. move)


        lcd.showImage(20,360,"/luadb/back.jpg")
        if gps_is_run then
            lcd.showImage(130,370,"/luadb/stop_gps.jpg")
        else
            lcd.showImage(130,370,"/luadb/start_gps.jpg")
        end
        

        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if run_state == 0 then    -- 等待结束
            return true
        end
    end
end

local function stop_gps()
    gnss.stop()
end

function airgps.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = 0
    elseif x > 130 and  x < 241 and y > 370  and  y < 417 then
        if  gps_is_run then
            sys.taskInit(stop_gps, "stop_gps")   
        else
            sys.taskInit(setup_gps, "setup_gps")   
        end
         
    end
end

return airgps