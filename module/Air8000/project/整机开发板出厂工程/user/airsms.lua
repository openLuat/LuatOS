local airsms = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行


local function start_send_sms()

end



function airsms.run()       
    log.info("airsms.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"短信测试：需要代码内修改发送短信的号码" )

        --[
        -- 此处可填写短信demo ui
        --]


        lcd.showImage(20,360,"/luadb/back.jpg")
        if ap_state then
            lcd.showImage(130,370,"/luadb/stop.jpg")
        else
            lcd.showImage(130,370,"/luadb/start.jpg")
        end
        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function airsms.tp_handal(x,y,event)          -- 此处处理UI 的发送短信按钮
    if x > 20 and  x < 100 and y > 360  and  y < 440 then   -- 返回主界面
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        sysplus.taskInitEx(start_send_sms, "start_send_sms")
    end
end

return airsms