

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

pins.setup(58, "I2C0_SDA")
pins.setup(57, "I2C0_SCL")
log.info("i2c", "复用" )

sys.taskInit(function()
    sys.wait(1000)
    log.info("开始G711编解码测试")

    -- 初始化audio
    local multimedia_id = 0
    local i2c_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 44100
    local i2s_bits_per_sample = 16
    local i2s_channel_format = 0
    local i2s_communication_format = 0
    local i2s_channel_bits = 32

    local pa_pin = 22
    local pa_on_level = 1
    local pa_delay = 20
    local power_pin = 20
    local power_delay = 0

    i2c.setup(i2c_id,i2c.FAST)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})


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



    -- 第一步：对/luadb/test.pcm进行G711编码
    log.info("第一步：对/luadb/test.pcm进行G711编码")

    -- 创建G711编码器
    local encoder = codec.create(codec.ALAW, false)
    log.info("G711编码器创建成功:", encoder)

    -- 创建输入和输出缓冲区
    local in_buffer = zbuff.create(54594)
    local out_buffer = zbuff.create(54594)

    -- 读取PCM文件数据
    local f = io.open("/luadb/test.pcm", "rb")

    local pcm_data = f:read("*a")  -- 读取全部数据
    f:close()
    log.info("PCM文件大小:", #pcm_data, "字节")

    -- 将PCM数据写入输入缓冲区
    in_buffer:write(pcm_data)

    -- 执行G711编码
    log.info("开始G711编码，PCM数据大小:", #pcm_data, "字节")
    local encode_result = codec.encode(encoder, in_buffer, out_buffer, 0)  -- 使用默认编码等级0
    log.info("G711编码结果:", encode_result)

    if encode_result then
        local encoded_size = out_buffer:used()
        log.info("编码成功，编码后数据大小:", encoded_size, "字节")

        -- 保存编码后的G711数据到文件
        local encoded_data = out_buffer:toStr(0, encoded_size)
        io.writeFile("/aaa.g711", encoded_data)
        log.info("编码数据已保存到 /aaa.g711")

        -- 第二步：对编码后的文件进行解码
        log.info("第二步：对编码后的文件进行解码")

        -- 创建G711解码器
        local decoder = codec.create(codec.ALAW)
        if not decoder then
            log.error("创建G711解码器失败")
            codec.release(encoder)
            return
        end
        log.info("G711解码器创建成功:", decoder)

        -- 获取编码后文件的信息
        local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed = codec.info(decoder, "/aaa.g711")
        log.info("编码后文件信息 - 采样率:", sample_rate, "声道数:", num_channels, "位深度:", bits_per_sample)

        -- 解码G711文件
        log.info("开始解码G711文件")
        local decoded_data = ""
        local decode_count = 0
        local total_decoded = 0

        -- 创建解码缓冲区
        local decode_buffer = zbuff.create(54594)

        while 1 do
            local decode_result = codec.data(decoder, decode_buffer)
            if decode_result then
                local data_size = decode_buffer:used()
                if data_size > 0 then
                    decode_count = decode_count + 1
                    total_decoded = total_decoded + data_size
                    decoded_data = decoded_data .. decode_buffer:toStr(0, data_size)
                    log.info("解码数据块", decode_count, "大小:", data_size, "字节")
                else
                    log.info("解码完成，没有更多数据")
                    break
                end
            else
                log.info("G711解码完成或失败")
                break
            end
        end
        log.info("解码完成，总解码数据大小:", #decoded_data, "字节")


        -- 第三步：播放解码后的音频
        log.info("第三步：播放解码后的音频")

        -- 播放参数设置
        audio.start(multimedia_id, audio.PCM, 1, 16000, 16)
        -- 音量设置
        audio.vol(multimedia_id, 50)
        audio.pm(multimedia_id,audio.RESUME)

        -- 播放解码后的PCM数据
        log.info("开始播放解码后的PCM数据")
        local play_buffer = zbuff.create(54594)
        play_buffer:write(decoded_data)
        play_buffer:seek(0)

        -- 分块播放音频数据
        local offset = 0
        while offset < #decoded_data do
            local chunk = play_buffer:read(math.min(4096, #decoded_data - offset))
            if chunk and #chunk > 0 then
                audio.write(multimedia_id, chunk)
                log.info("播放音频块，大小:", #chunk, "字节")
                sys.wait(50)  -- 等待一小段时间
            end
            offset = offset + 4096
        end

        log.info("音频播放完成")

        -- 清理解码器资源
        codec.release(decoder)
        decode_buffer:free()
        play_buffer:free()
    else
        log.error("G711编码失败")
    end

    -- 清理资源
    codec.release(encoder)
    in_buffer:free()
    out_buffer:free()

    log.info("G711编解码测试完成")
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
