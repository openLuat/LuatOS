local airpower = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行




function airpower.run()       
    log.info("airpower.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"电源管理测试" )

        --[
        -- 此处可填写demo ui
        --]

        lcd.showImage(100,360,"/luadb/back.jpg")
        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function airpower.tp_handal(x,y,event)       
    if x > 100 and  x < 180 and y > 360  and  y < 440 then   -- 返回主界面
        run_state = false
    end
end

return airpower