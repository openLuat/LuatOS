PROJECT = "air780ehm_air1103_tts"
VERSION = "1.0.0"
sys = require "sys"
local exaudio = require "exaudio"

-- 配套 Air780EHM 13/113 固件；UART1 连接 Air1103，TX/RX 交叉并共地，2M。
-- 同时下载 script/libs/exaudio.lua 和 script/libs/air1103.lua。
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 1000)
end

sys.taskInit(function()
    assert(exaudio.setup({model = "air1103", uart_id = 1, audio_mode = "new"}), "Air1103 初始化失败")
    exaudio.vol(70)
    local ok, reason = exaudio.play_start({
        type = 1,
        content = "你好，这是离线语音播报。当前数值是一二三四五。",
        cbfnc = function(event, result)
            if event == exaudio.PLAY_DONE then
                log.info("air1103.tts", "播放结束", result, "空闲", exaudio.is_end())
            end
        end
    })
    log.info("air1103.tts", "请求受理", ok, reason)
    -- 中途停止：exaudio.play_stop({type = 1})。
    -- 在完成回调中，或等待 exaudio.is_end() 为 true 后，才能启动下一句/通话。
end)

sys.run()
