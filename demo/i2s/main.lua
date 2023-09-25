
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2sdemo"
VERSION = "1.0.0"

--[[
本demo暂时只在air101/103/601测试过
对于EC618系列的模块,例如Air780E/Air700E,请使用audio库进行快捷播放
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
    audio.config(0, 20, 1, 0, 20)
    audio.setBus(0, audio.BUS_I2S)
    audio.start(0, audio.PCM, 1, 16000, 16)
    audio.vol(0, 10)

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
            sys.wait(50)
        end
        f:close()
    end

    -- mp3测试
    local decoder = codec.create(codec.MP3)
    log.info("decoder", decoder)
    local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.info(decoder, "/luadb/test_16k.mp3")
    log.info("info", result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
    
    local buff = zbuff.create(8*1024)
    log.info("sys", rtos.meminfo("sys"))
    log.info("buff", buff)
    while 1 do
        -- log.info("尝试解码")
        local result = codec.data(decoder, buff, 4096)
        -- log.info("解析结果", result)
        if result then
            while 1 do
                local max, remain = i2s.txStat(0)
                if max == 0 then
                    sys.wait(120)
                    break
                end
                if remain > (max / 2) then
                    sys.wait(10)
                else
                    break
                end
            end
            audio.write(0, buff)
            -- log.info("音频数据已写入", buff:used())
        else
            break
        end
    end
    codec.release(decoder)
end)

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
