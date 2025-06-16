local airtf = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行

local function start_write_file()
    interrupt_state = true

    write_file_state = false
end


function airtf.run()       
    log.info("airtf.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"tf 卡测试" )

        --[
        -- 此处可填写demo ui
        --]

        lcd.showImage(20,360,"/luadb/back.jpg")
        if interrupt_state then
            lcd.showImage(130,370,"/luadb/stop.jpg")      --  开启中断模式
        else
            lcd.showImage(130,370,"/luadb/start.jpg")     --  关闭中断模式
        end
        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function airtf.tp_handal(x,y,event)       
    if x > 20 and  x < 100 and y > 360  and  y < 440 then   -- 返回主界面
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if not write_file_state then
            sysplus.taskInitEx(start_write_file, "start_write_file")
        end
    end
end

return airtf