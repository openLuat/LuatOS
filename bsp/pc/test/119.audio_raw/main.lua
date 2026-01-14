-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio_raw"
VERSION = "1.0.0"

_G.sys = require("sys")

local function gen_pcm(path, seconds, rate, channels, bits, freq)
    local f = io.open(path, "wb")
    if not f then
        log.error("audio", "open fail", path)
        return false
    end
    local samples = seconds * rate
    local two_pi_f = 2 * math.pi * freq
    for n = 0, samples - 1 do
        local t = n / rate
        local v = math.sin(two_pi_f * t)
        local sample = math.floor(v * 32767)
        local lo = sample & 0xFF
        local hi = (sample >> 8) & 0xFF
        -- write interleaved channels (stereo)
        if channels == 2 then
            f:write(string.char(lo, hi, lo, hi))
        else
            f:write(string.char(lo, hi))
        end
    end
    f:close()
    return true
end

sys.taskInit(function()
    local pcm = "sample_44100_16bit_stereo.pcm"
    -- 生成2分钟 440Hz 立体声PCM
    if not io.exists(pcm) then
        gen_pcm(pcm, 120, 44100, 2, 16, 440)
    end

    -- 初始化I2S（确保底层已配置）
    local i2s_ok = i2s.setup(0, 0, 44100, 16, 2, 0, 16)
    log.info("audio", "i2s.setup", i2s_ok)

    -- 启动原始音频播放
    local ok = audio.start(0, audio.PCM, 2, 44100, 16)
    log.info("audio", "audio.start", ok)
    if not ok then
        log.error("audio", "start raw failed")
        return
    end

    local f = io.open(pcm, "rb")
    if not f then
        log.error("audio", "read fail", pcm)
        return
    end
    local chunk = 4096
    local sent_total = 0
    while true do
        local data = f:read(chunk)
        if not data or #data == 0 then break end
        local okw = audio.write(0, data)
        sent_total = sent_total + #data
        if not okw then
            log.error("audio", "write failed at", sent_total)
            break
        end
        -- 查询发送缓冲状态
        local maxb, remain = i2s.txStat(0)
        if maxb and remain then
            -- log.debug("audio", "txStat", maxb, remain)
        end
        sys.wait(1)
    end
    f:close()

    log.info("audio", "written bytes", sent_total)

    audio.stop(0)
    log.info("audio", "raw playback done")
end)

sys.run()
