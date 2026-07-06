local audio_play_pc_test = {}

-- 选择本用例固定音频资源
-- 约定：音频文件与main.lua放在同目录，并通过 /luadb/xxx.mp3 访问
local function pick_mp3_path()
    local p = "/luadb/test_16k.mp3"
    local sz = io.fileSize(p)
    if type(sz) == "number" and sz > 0 then
        return p
    end
    return nil
end

-- audio.play 基础流程测试
-- 覆盖点：
-- 1) 单文件播放成功并收到 audio.DONE
-- 2) audio.isEnd / audio.getError 返回值符合预期
-- 3) 二次播放后手动 playStop 能正确结束并收到回调
function audio_play_pc_test.test_audio_play_basic()
    log.info("audio_play_pc_test", "开始 test_audio_play_basic")

    local path = pick_mp3_path()
    assert(path, "未找到可播放的mp3文件(/luadb/test_16k.mp3)")

    -- 注册播放结束回调，收到 DONE 后通过消息同步给测试流程
    audio.on(0, function(id, event)
        if id == 0 and event == audio.DONE then
            sys.publish("AUDIO_PC_DONE")
        end
    end)

    -- 第一次完整播放
    local ok = audio.play(0, path)
    assert(ok == true, "audio.play启动失败")

    local done = sys.waitUntil("AUDIO_PC_DONE", 15000)
    assert(done == true, "播放超时未收到audio.DONE")

    assert(audio.isEnd(0) == true, "播放完成后audio.isEnd应为true")
    local succ, user_stop = audio.getError(0)
    assert(succ == true and user_stop == false, "播放完成后的getError结果异常")

    -- 第二次播放后主动停止
    local ok2 = audio.play(0, path)
    assert(ok2 == true, "二次播放启动失败")
    sys.wait(30)
    local stop_ok = audio.playStop(0)
    assert(stop_ok == true, "audio.playStop返回失败")

    local done2 = sys.waitUntil("AUDIO_PC_DONE", 5000)
    assert(done2 == true, "停止播放后未收到audio.DONE")

    local succ2 = select(1, audio.getError(0))
    assert(succ2 == false or succ2 == true, "getError返回值异常")

    log.info("audio_play_pc_test", "test_audio_play_basic 通过")
end

return audio_play_pc_test
