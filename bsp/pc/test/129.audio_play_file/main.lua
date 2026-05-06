PROJECT = "pc_audio_play_file"
VERSION = "1.0.0"

-- 固定测试资源：与本脚本同目录，挂载后通过 /luadb/ 路径访问
local function pick_mp3_path()
    local p = "/luadb/test_16k.mp3"
    local sz = io.fileSize(p)
    if type(sz) == "number" and sz > 0 then
        return p
    end
    return nil
end

sys.taskInit(function()
    local ok, err = pcall(function()
        log.info("pc_audio_play_file", "开始回归测试")

        local path = pick_mp3_path()
        assert(path, "未找到MP3文件")

        -- 接收 audio.DONE 事件，作为播放阶段结束信号
        audio.on(0, function(id, event)
            if id == 0 and event == audio.DONE then
                sys.publish("AUDIO_DONE")
            end
        end)

        -- 场景1：完整播放并结束
        assert(audio.play(0, path) == true, "audio.play失败")
        assert(sys.waitUntil("AUDIO_DONE", 15000) == true, "未收到DONE回调")
        assert(audio.isEnd(0) == true, "播放结束状态异常")

        -- 场景2：播放中主动停止
        assert(audio.play(0, path) == true, "再次播放失败")
        sys.wait(30)
        assert(audio.playStop(0) == true, "playStop失败")
        assert(sys.waitUntil("AUDIO_DONE", 5000) == true, "停止后未收到DONE")

        log.info("pc_audio_play_file", "回归测试通过")
    end)

    if ok then
        log.info("pc_audio_play_file", "PASS")
        os.exit(0)
    else
        log.error("pc_audio_play_file", "FAIL", err)
        os.exit(1)
    end
end)

sys.run()
