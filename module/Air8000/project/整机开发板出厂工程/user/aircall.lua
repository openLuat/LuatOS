local aircall = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行


local function stop_call()

end

local function recv_call()

end

local function start_call()

end



function aircall.run()       
    log.info("aircall.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"需要代码内修改拨打的号码" )

        --[
        -- 此处可填写demo ui
        --]


        lcd.showImage(20,360,"/luadb/back.jpg")
        lcd.showImage(130,303,"/luadb/stop.jpg")    -- 挂断&拒接电话
        lcd.showImage(130,350,"/luadb/start.jpg")   -- 接电话
        lcd.showImage(130,397,"/luadb/start.jpg")   -- 拨打电话

        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function aircall.tp_handal(x,y,event)       
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 230 and y > 303  and  y < 350 then
        sysplus.taskInitEx(stop_call, "stop_call")
    elseif x > 130 and  x < 230 and y > 350  and  y < 397 then
        sysplus.taskInitEx(recv_call, "recv_call")
    elseif x > 130 and  x < 230 and y > 397  and  y < 444 then
        sysplus.taskInitEx(start_call, "start_call")
    end
end

return aircall