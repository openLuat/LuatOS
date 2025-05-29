local airtts = {}

local i2c_id = 0            -- i2c_id 0


local play_string = "降功耗，找合宙"
local taskName = "airtts"


local function audio_play()
    local result    
    -- 本例子是按行播放 "千字文", 文本来源自wiki百科
    local fd = nil
    local line = nil
    log.info("开始播放")
    line = play_string
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
    sys.wait(1000)
    sysplus.taskDel(taskName)
end


local function audio_task()
    audio_play()
end


function airtts.play(string)
    play_string = string
    sysplus.taskInitEx(audio_task, taskName)
end

return airtts