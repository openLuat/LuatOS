local airtts = {}

local i2c_id = 0            -- i2c_id 0


local play_string =  "支持 4G,卫星定位,WiFi,蓝牙，5秒极速联网，"
local play_string1 =  "51个可编程IO/4个UART/4个通用ADC/1个CAN接口，"
local play_string2 =  "支持LuatOS二次开发，源码开放例程丰富，"
local play_string3 =  "支持485/232/充电/以太网驱动/多网融合/VoLTE通话，"
local airaudio  = require "airaudio"
local taskName = "airtts"
local run_state = 0

local function audio_play()
    local result    
    -- 本例子是按行播放 "千字文", 文本来源自wiki百科
    local fd = nil
    local line = nil
    log.info("开始播放")
    line = play_string .. play_string1 .. play_string2 .. play_string3
    line = line:trim()
    log.info("播放内容", line)
    result = audio.tts(0, line)
    if result then
    --等待音频通道的回调消息，或者切换歌曲的消息
        while true do
            msg = sysplus.waitMsg(taskName, nil)
            if type(msg) == 'table' then
                if msg[1] == MSG_PD then
                    log.info("播放结束")
                    break
                end
            else
                log.error(type(msg), msg)
            end
        end
    else
        log.debug("解码失败!")
        sys.wait(1000)
    end
    if not audio.isEnd(0) then
        log.info("手动关闭")
        audio.playStop(0)
    end
    if audio.pm then
        audio.pm(0,audio.STANDBY)
    end
    
    -- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
    log.info("mem", "sys", rtos.meminfo("sys"))
    log.info("mem", "lua", rtos.meminfo("lua"))
    -- sys.wait(1000)
    sysplus.taskDel(taskName)
    run_state = 0
    sysplus.sendMsg(taskName, "PALY END")
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


function airtts.run()       -- TTS 播放主程序
    if run_state == 0 then
        lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
        sysplus.taskInitEx(audio_task, taskName)
        run_state = 1
    end
    lcd.drawStr(0,80,play_string)
    lcd.drawStr(0,130,play_string1)
    lcd.drawStr(0,180,play_string2)
    lcd.drawStr(0,230,play_string3)
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


function airtts.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 120 and  x < 200 and y > 300  and  y < 380 then
        audio_stop()
    end
end

return airtts