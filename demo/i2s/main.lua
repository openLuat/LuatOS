
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2sdemo"
VERSION = "1.0.0"

--[[
本demo暂时只在air101/103/601测试过
对于EC618系列的模块,例如Air780E/Air700E,请使用audio库进行快捷播放

本demo需要外挂ES8311 codec芯片, 可使用海凌科的w800音频开发板进行测试

https://detail.tmall.com/item.htm?abbucket=2&id=670202333872
]]

-- sys库是标配
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(500)
    local multimedia_id = 0
    local i2c_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 44100
    local i2s_bits_per_sample = 16
    local i2s_channel_format = 0
    local i2s_communication_format = 0
    local i2s_channel_bits = 32

    local pa_pin = 20
    local pa_on_level = 1
    local pa_delay = 20
    local power_pin = 255
    local power_delay = 0

    local voice_vol = 70

    i2c.setup(i2c_id,i2c.FAST)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S

    -- 播放参数设置
    audio.start(multimedia_id, audio.PCM, 1, 16000, 16)
    -- 音量设置
    audio.vol(multimedia_id, 50)
    audio.pm(multimedia_id,audio.RESUME)
    -- PCM播放演示, 16k采样率, 16bit采样深度
    local file_size = fs.fsize("/luadb/test.pcm")
    -- print("/luadb/test.pcm size",file_size)   
    local f = io.open("/luadb/test.pcm", "rb")
    if f then 
        while 1 do
            local data = f:read(4096)
            -- print("-------------")
            if not data or #data == 0 then
                break
            end
            audio.write(0, data)
            sys.wait(100)
        end
        f:close()
    end

    -- mp3测试
    -- 推荐使用ffmpeg对mp3文件进行预处理, 必须转成单声道
    --  ffmpeg -i abc.mp3 -ac 1 -map_metadata -1 -y out.mp3
    -- Air101/Air103/Air601支持采样率 8~44.1k, 深度8-16bit, 以下是转成16k采样率
    --  ffmpeg -i abc.mp3 -ac 1 -map_metadata -1 -ar 16000 -y out.mp3
    local path = "/luadb/out.mp3"
    local decoder = codec.create(codec.MP3)
    log.info("decoder", decoder)
    local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.info(decoder, path)
    log.info("info", result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
    if result then
        -- 按mp3实际情况切换采样率和采样深度
        audio.start(0, audio.PCM, 1, sample_rate, bits_per_sample) 
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
    -- 释放解码器资源
    codec.release(decoder)
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
