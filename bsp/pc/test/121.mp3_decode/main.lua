
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2sdemo"
VERSION = "1.0.0"


sys.taskInit(function()
    sys.wait(500)

    

    -- mp3测试
    -- 推荐使用ffmpeg对mp3文件进行预处理, 必须转成单声道或者立体声格式, 采样率44100, 采样深度16bit的mp3文件
    local path = "/luadb/test.mp3"
    local decoder = codec.create(codec.MP3)
    log.info("decoder", decoder)
    local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.info(decoder, path)
    log.info("info", result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
    if result then
        -- 初始化I2S（确保底层已配置）
        local i2s_ok = i2s.setup(0, 0, sample_rate, bits_per_sample, 2, 0, 16)
        log.info("audio", "i2s.setup", i2s_ok)
        -- 按mp3实际情况切换采样率和采样深度
        audio.start(0, audio.PCM, num_channels, sample_rate, bits_per_sample) 
        -- 音频数据缓存区大小
        local buff = zbuff.create(8*1024)
        -- log.info("sys", rtos.meminfo("sys"))
        -- log.info("buff", buff)
        while 1 do
            -- log.info("尝试解码")
            local result = codec.data(decoder, buff, 4096)
            -- log.info("解析结果", result)
            if result then
                while 1 do
                    -- 判断底层缓冲区是否空闲, 不空闲就需要等待
                    local max, remain = i2s.txStat(0)
                    -- log.info("底层缓冲区状态", max, remain)
                    if max == 0 then
                        sys.wait(120)
                        break
                    end
                    if remain > (max / 2) then
                        sys.wait(10) -- sys.waitUntil("AUDIO_INC", 10)
                    else
                        break -- 已经足够空闲,写入数据就好
                    end
                end
                audio.write(0, buff)
                -- log.info("音频数据已写入", buff:used())
            else
                break
            end
        end
    end
    log.info("audio", "mp3 decode done")
    -- 释放解码器资源
    codec.release(decoder)
    audio.stop(0)
    log.info("audio", "mp3 playback done")
end)

-- sys.taskInit(function()
--     while 1 do
--         -- 打印内存状态, 调试用
--         sys.wait(1000)
--         log.info("lua", rtos.meminfo())
--         log.info("sys", rtos.meminfo("sys"))
--     end
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
