
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
接线要求:

SPI 使用常规4线解法
Air105开发板         TF模块
PC9                  CS
PB12(SPI0_CLK)       CLK
PB14(SPI0_MISO)      MOSI
PB15(SPI0_MISO)      MISO
5V                   VCC
GND                  GND
]]


audio.on(0, function(id, event_id)
    if event_id == audio.MORE_DATA then
        sys.publish("moredata")
    else
        sys.publish("playover")
    end
end)

sys.taskInit(function()
    --sys.wait(1000) -- 启动延时
    local spiId = 0
    local result = spi.setup(
        spiId,--串口id
        255, -- 不使用默认CS脚
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*1000  -- 初始化时使用较低的频率
    )
    local TF_CS = pin.PB13
    gpio.setup(TF_CS, 1)
    --fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", 0, TF_CS, 24000000)
    local data, err = fatfs.getfree("SD")
    local buff = zbuff.create(1024)
    local in_buff = zbuff.create(8 * 1024 + 512)
    if data then
        log.info("fatfs", "getfree", json.encode(data))
        f = io.open("/sd/music/test1.mp3", "rb")
        if f then
            log.debug("find mp3")
            data = f:read(8192)
            codecr = codec.create(codec.MP3)
            local result, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed = codec.get_audio_info(codecr, data)
            if result then
                buff:resize(SampleRate * 2)
                in_buff:copy(nil, data)
                result = codec.get_audio_data(codecr, in_buff, buff)
                log.debug("start", audio.start(0, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed))
                audio.write(0, buff)
                data = f:read(8192)
                in_buff:copy(nil, data) 
                result = codec.get_audio_data(codecr, in_buff, buff)
                audio.write(0, buff)
                data = f:read(8192)
                while data and #data > 0 do
                    sys.waitUntil("moredata", 2000)
                    in_buff:copy(nil, data) 
                    result = codec.get_audio_data(codecr, in_buff, buff)
                    audio.write(0, buff)
                    data = f:read(8192)
                end
                sys.waitUntil("playover", 2000)    
                codec.release(codecr)
                audio.stop(0)
            else
                log.debug("mp3无法解码")
            end
            f:close()
        end
        data = nil
        f = io.open("/sd/music/test.wav", "rb")
        if f then
            buff:seek(0, zbuff.SEEK_SET)
            buff:copy(0, f:read(12))
            if buff:query(0, 4) == 'RIFF' and buff:query(8, 4) == 'WAVE' then             
                local total = buff:query(4, 4, false)
                buff:copy(0, f:read(8))
                if buff:query(0, 4) == 'fmt ' then      
                    buff:copy(0, f:read(16))
                    buff:seek(0, zbuff.SEEK_SET)
                    local _, AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample = buff:unpack("<HHIIHH")
                    log.debug("find fmt info", AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample)
                    buff:copy(0, f:read(8))
                    if buff:query(0, 4) ~= 'data' then
                        buff:copy(0, buff:query(4, 4, false))
                        buff:copy(0, f:read(8))
                    end
                    log.debug("start", audio.start(0, AudioFormat, NumChannels, SampleRate, BitsPerSample))
                    ByteRate = SampleRate * BlockAlign
                    data = f:read(ByteRate)
                    audio.write(0, data)
                    data = f:read(ByteRate)
                    audio.write(0, data)
                    data = f:read(ByteRate)
                    while data and #data > 0 do
                        sys.waitUntil("moredata", 2000)
                        audio.write(0, data)
                        data = f:read(ByteRate)
                    end
                    sys.waitUntil("playover", 2000)
                    audio.stop(0)
                end
            else
                log.debug(buff:query(0, 4), buff:query(8, 4))
            end
            f:close()
        end
    else
        log.info("fatfs", "err", err)
    end



    -- #################################################

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
