--[[
@module  prod_audio
@summary 产测项 AUDIO_TEST#：播放测试音（内置 DAC + PA）
@usage
  AUDIO_TEST#                      播放默认测试音：/luadb/test_sound.wav 或 /sd/test_sound.wav
  AUDIO_TEST,/luadb/歌名.mp3#       播放指定文件（把自己的歌放进工程根目录即可随固件烧入）
@return  string —— "OK" / "ERROR"
说明
1. exaudio 用 DAC 模式，pa_ctrl 取配置里的 PA_EN(GPIO27)；
2. 收到播放完成回调即通过，10 秒内没收到则失败；
3. 有没有真实声音需人工听；测试音频需随脚本烧进 luadb。
]]

local DEFAULT_FILES = { "/luadb/test_sound.wav", "/sd/test_sound.wav" }
local TIMEOUT_MS   = 10000

return function(arg)
    local exaudio = require "exaudio"
    local c = _G.project_config.hw.audio

    local file = (type(arg) == "string" and #arg > 0) and arg or nil
    if not file then
        for _, f in ipairs(DEFAULT_FILES) do
            if io.exists(f) then file = f break end
        end
    end
    if not file or not io.exists(file) then
        log.error("prod_audio", "测试音频不存在：", table.concat(DEFAULT_FILES, " / "),
            "（放 SD 卡 /test_sound.wav 或随脚本烧进 luadb）")
        return "ERROR"
    end

    log.info("prod_audio", "播放测试音:", file)

    local a = {
        model       = "dac",
        pa_ctrl     = c.pa_en,
        pa_on_level = c.pa_on_level or 1,
    }
    if c.dac_chl then a.dac_chl = c.dac_chl end     -- 0=AUD_LN(默认) / 1=AUD_LP / 2=双通道

    if not exaudio.setup(a) then
        log.error("prod_audio", "exaudio.setup 失败（model=dac, pa_ctrl=", tostring(c.pa_en), "）")
        return "ERROR"
    end
    log.info("prod_audio", "exaudio.setup ok, pa_ctrl", tostring(c.pa_en),
        "pa_on_level", tostring(a.pa_on_level))

    exaudio.vol(70)

    local finished = false
    local ok_start = exaudio.play_start({
        type    = 0,
        content = file,
        cbfnc   = function(event)
            if event == exaudio.PLAY_DONE then
                finished = true
                sys.publish("AUDIO_DONE")
            end
        end,
    })

    log.info("prod_audio", "play_start 返回:", tostring(ok_start))

    sys.waitUntil("AUDIO_DONE", TIMEOUT_MS)

    if not finished then
        log.error("prod_audio", "未收到播放完成事件（查 VBAT_AUDIO/喇叭/PA_EN）")
        return "ERROR"
    end
    log.info("prod_audio", "播放完成，请人工确认喇叭有声音")
    return "OK"
end
