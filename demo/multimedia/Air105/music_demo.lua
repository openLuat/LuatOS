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
-- music文件夾，可以換成你自己的目录，不用加/sd/，demo里固定用TF卡目录，如果要本地目录，自行修改
local music_dir = "/music/"

function music_demo_start()
    sys.wait(1000) -- 启动延时
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
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", 0, TF_CS, 12000000)
    local data, err = fatfs.getfree("SD")
    -- usbapp.udisk_attach_sdhc(0)
    -- usbapp.start(0)
    -- sys.wait(600000)
    local buff = zbuff.create(1024)
    local in_buff = zbuff.create(8 * 1024 + 512)
    local play_list = {}
    if data then
        log.info("fatfs", "getfree", json.encode(data))
        local dir_nums, dir_info = fatfs.lsdir(music_dir)
        for k,v in pairs(dir_info) do
            log.info(v.size, k)
            play_list[v.size] = "/sd".. music_dir .. k
        end
        while true do
            for k,v in pairs(play_list) do
                log.info(v)
                if v:find(".mp3") or v:find(".MP3") then
                    f = io.open(v, "rb")               
                    if f then
                        -- log.debug("find mp3")
                        in_buff:del()
                        data = f:read(10)
                        if data:sub(1, 3) == 'ID3' then
                            in_buff:copy(nil, data)
                            log.info("jump head", in_buff:query(6, 4, true))
                            f:seek(SEEK_SET, in_buff:query(6, 4, true))

                        end
                        in_buff:del()
                        data = f:read(2048)
                        codecr = codec.create(codec.MP3)
                        local result, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed = codec.get_audio_info(codecr, data)
                        if result then
                            log.info("mp3 info", NumChannels, SampleRate, BitsPerSample)
                            buff:resize(65536)
                            in_buff:copy(nil, data)
                            result = codec.get_audio_data(codecr, in_buff, buff)
                            while buff:used() == 0 do
                                log.info("need more data to decode", in_buff:used())
                                data = f:read(2048)
                                in_buff:copy(nil, data)
                                result = codec.get_audio_data(codecr, in_buff, buff)
                            end
                            log.debug("start", audio.start(0, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed))
                            audio.write(0, buff)
                            --local tick1,_ = mcu.tick64()
                            data = f:read(2048)
                            in_buff:copy(nil, data) 
                            result = codec.get_audio_data(codecr, in_buff, buff)
                            --local tick2,_ = mcu.tick64()
                            --log.debug(mcu.dtick64(tick2, tick1)/_)
                            audio.write(0, buff)
                            data = f:read(2048)
                            while data and #data > 0 and not decode_error do
                                sys.waitUntil("moredata", 2000)
                                in_buff:copy(nil, data) 
                                result = codec.get_audio_data(codecr, in_buff, buff)
                                while buff:used() == 0 and data and #data > 0 do
                                    log.info("need more data to decode", in_buff:used())
                                    data = f:read(2048)
                                    in_buff:copy(nil, data)
                                    result = codec.get_audio_data(codecr, in_buff, buff)
                                end
                                audio.write(0, buff)
                                data = f:read(2048)
                            end
                            sys.waitUntil("playover", 2000)           
                            
                            f:close()
                            audio.stop(0)
                        else
                            log.debug("mp3 decode fail!")
                            f:close()
                        end
                        codec.release(codecr)
                    end
                end
                if v:find(".wav") or v:find(".WAV") then
                    data = nil
                    f = io.open(v, "rb")
                    if f then
                        buff:del()
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
                                SampleRate = (SampleRate * BlockAlign / 8) & ~(3)
                                log.info("size", SampleRate)
                                data = f:read(SampleRate)
                                audio.write(0, data)
                                data = f:read(SampleRate)
                                audio.write(0, data)
                                data = f:read(SampleRate)
                                while data and #data > 0 do
                                    sys.waitUntil("moredata", 2000)
                                    audio.write(0, data)
                                    data = f:read(SampleRate)
                                end
                                sys.waitUntil("playover", 2000)
                                audio.stop(0)
                            end
                        else
                            log.debug(buff:query(0, 4), buff:query(8, 4))
                        end
                        f:close()
                    end
                end
            end
        end
    else
        log.info("fatfs", "err", err)
    end
end