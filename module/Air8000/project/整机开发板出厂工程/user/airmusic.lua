local airmusic = {}


function airmusic.play(path)

    -- 配置好audio外设

    local taskName = "task_audio"


    local MSG_PD = "playDone"   -- 播放完成所有数据

    local function audio_task()
        local result    
        sys.waitUntil("AUDIO_READY")
        log.info("开始播放")
        result = audio.play(0,path)
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
            audio.pm(0,audio.STANDBY)       --PM模式 待机模式，PA断电，codec待机状态，系统不能进低功耗状态，如果PA不可控，codec进入静音模式
        end
        -- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        log.info("mem", "sys", rtos.meminfo("sys"))
        log.info("mem", "lua", rtos.meminfo("lua"))
        sys.wait(1000)
        
    end

    sys.timerLoopStart(function()
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))
    end, 3000)

    sysplus.taskInitEx(audio_task, taskName)
end

return airmusic