local airrecord = {}



local airaudio  = require "airaudio"
local taskName = "airrecord"
local run_state = 0

local function audio_play()

end

function audio_stop()
    sysplus.sendMsg(taskName, MSG_PD)
end

local function audio_task()
    airaudio.init()
    if fonts.list then
        log.info("fonts", "u8g2", json.encode(fonts.list("u8g2")))
    end
    audio_play()
end


function airrecord.run()       -- TTS 播放主程序
    if run_state == 0 then
        lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
        sysplus.taskInitEx(audio_task, taskName)
        run_state = 1
    end
    lcd.showImage(120,300,"/luadb/back.jpg")
    lcd.showImage(0,448,"/luadb/Lbottom.jpg")
    lcd.flush()
    while true do
        sys.wait(30)
        if run_state == 0 then    -- 等待结束
            return true
        end
    end
end


function airrecord.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 120 and  x < 200 and y > 300  and  y < 380 then
        audio_stop()
    end
end

return airrecord