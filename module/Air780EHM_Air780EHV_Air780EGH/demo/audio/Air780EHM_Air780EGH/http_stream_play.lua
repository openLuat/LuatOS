--[[
@module  http_stream_play
@summary HTTP音频流式播放（边下边播）
@version 1.0
@date    2026.07.03
@author  拓毅恒
@usage
使用httpplus进行HTTP下载，边下边播

注意：
1. 如果搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音
2. 使用 AirAUDIO_1020 时，仅需在`audio_setup_param`修改 `model="tm8211"` 并移除 `i2c_id` 配置即可支持播放功能
3. 支持PCM/AMR/MP3/WAV格式的HTTP边下边播
4. 依赖exaudio扩展库自动初始化音频硬件和ES8311编解码器，使用新音频框架
5. 本demo使用新音频框架，固件需要V2046及以上的13/113号固件才能播放
6. PCM格式默认16kHz、16位、有符号、单声道
7. AMR/MP3/WAV格式会自动解析文件头获取真实采样率
]]

local exaudio = require "exaudio"
local httpplus = require("httpplus")

-- HTTP音频文件URL（可替换为AMR/MP3/WAV/PCM的URL）
local AUDIO_URL = "https://appstoreoss.luatos.com/iot-apps/res/100617/sample-6s.mp3"

-- 音频初始化设置参数
local audio_setup_param = {
    model = "es8311",          -- 编解码器类型: "es8311"、"tm8211"、"dac"
    i2c_id = 1,                -- I2C接口编号
    
    dac_delay = 6, -- DAC启动前冗余时间
    
    pa_ctrl = 26,              -- 音频放大器电源控制管脚
    dac_ctrl = 2,              -- 音频编解码芯片电源控制管脚

    audio_mode = "new"  -- 此demo只能用最新音频框架版本
}

-- ========== 统计用变量 ==========
local TICK_HZ = mcu.hz()
local STATS_PRINT_INTERVAL = 5

-- 时间转换函数
local function ticks_to_ms(elapsed_ticks)
    return math.floor(elapsed_ticks * 1000 / TICK_HZ)
end

-- ========== 音频格式检测 ==========

-- 根据URL扩展名获取音频编码格式
local function get_audio_codec(url)
    local ext = url:match("%.([^%.]+)$")
    if not ext then return nil end
    ext = ext:lower()
    local map = {
        amr = { cid = 2, sr = 8000,  bits = 16, sig = true, ch = 1, n = "AMR_NB" },
        pcm = { cid = 0, sr = 16000, bits = 16, sig = true, ch = 1, n = "PCM" },
        wav = { cid = 1, sr = 16000, bits = 16, sig = true, ch = 1, n = "WAV" },
        mp3 = { cid = 5, sr = 44100, bits = 16, sig = true, ch = 1, n = "MP3" },
    }
    return map[ext]
end

-- ========== 播放完成回调 ==========

local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
        sys.publish("PLAYBACK_DONE")
    end
end

-- ========== 等待4G网络就绪 ==========

local function wait_network_ready()
    log.info("network", "等待4G网络就绪...")
    while not socket.adapter(socket.dft()) do
        sys.wait(1000)
    end
    log.info("network", "4G网络已就绪")
end

-- ========== HTTP下载回调 ==========
-- 该回调由httpplus.request在下载数据时触发
-- 负责解析文件头、启动流式播放、写入音频数据到流式队列

local stats_http_total = 0
local stats_http_chunks = 0
local stats_http_start_tick = 0
local stream_started = false
local need_header_parse = nil
local warm_buf = {}
local parse_pos = 0
local play_sr = 0
local play_bits = 16
local play_ch = 1
local play_sig = true

local function http_callback(total_len, recv_len, recv_data)
    if not recv_data or #recv_data == 0 then return end

    local chunk_size = #recv_data
    stats_http_total = stats_http_total + chunk_size
    stats_http_chunks = stats_http_chunks + 1
    if stats_http_start_tick == 0 then stats_http_start_tick = mcu.ticks2() end

    -- 未启动stream时：先解析文件头，如果是PCM，则直接启动
    if not stream_started then
        if need_header_parse ~= nil then
            -- AMR/MP3/WAV：先缓冲数据，解析文件头获取真实采样率/声道数
            table.insert(warm_buf, recv_data)
            local combined = table.concat(warm_buf)
            local info = exaudio.parse_audio_info(combined, need_header_parse, parse_pos)
            if info and info.sample_rate and info.sample_rate > 0 then
                play_sr = info.sample_rate
                play_bits = info.data_bits or play_bits
                play_ch = info.channel_nums or play_ch
                play_sig = info.is_signed

                -- 用解析后的正确参数启动流式播放
                if exaudio.play_start({
                    type = 2,
                    cbfnc = play_end_callback,
                    priority = 0,
                    codec_id = need_header_parse,
                    sample_rate = play_sr,
                    data_bits = play_bits,
                    channel_nums = play_ch,
                    is_signed = play_sig,
                }) then
                    stream_started = true
                    log.info("stream", "流启动成功, 采样率:", play_sr, "声道:", play_ch)

                    -- 写入已经缓冲的纯音频数据
                    local all_data = table.concat(warm_buf)
                    warm_buf = nil
                    if info.data_start and info.data_start > 0 and info.data_start < #all_data then
                        all_data = all_data:sub(info.data_start + 1)
                    end
                    exaudio.play_stream_write(all_data)
                    log.info("stream", "写入首块纯音频:", #all_data, "字节")
                end
            elseif info and info.sample_rate == 0 then
                parse_pos = info.data_start or (parse_pos + chunk_size)
                log.info("stream", "头解析需继续缓冲")
            else
                log.error("stream", "文件头解析失败")
            end
        else
            -- PCM：直接用默认参数启动流式播放
            if exaudio.play_start({
                type = 2,
                cbfnc = play_end_callback,
                priority = 0,
                codec_id = 0,
                sample_rate = 16000,
                data_bits = 16,
                channel_nums = 1,
                is_signed = true,
            }) then
                stream_started = true
                exaudio.play_stream_write(recv_data)
                log.info("stream", "PCM流启动成功, 首块:", chunk_size, "字节")
            end
        end

        -- 下载速度统计
        if stats_http_chunks % STATS_PRINT_INTERVAL == 0 then
            local now = mcu.ticks2()
            local elapsed = now - stats_http_start_tick
            local elapsed_ms = ticks_to_ms(elapsed)
            local speed = (elapsed_ms > 0) and math.floor(stats_http_total * 1000 / elapsed_ms) or 0
            log.info("stat_http", "chunks:", stats_http_chunks,
                "downloaded:", stats_http_total,
                "elapsed_ms:", elapsed_ms,
                "speed:", speed, "B/s")
        end
        return
    end

    -- stream已启动，写入音频数据到流式队列
    exaudio.play_stream_write(recv_data)

    -- 下载速度统计
    if stats_http_chunks % STATS_PRINT_INTERVAL == 0 then
        local now = mcu.ticks2()
        local elapsed = now - stats_http_start_tick
        local elapsed_ms = ticks_to_ms(elapsed)
        local speed = (elapsed_ms > 0) and math.floor(stats_http_total * 1000 / elapsed_ms) or 0
        log.info("stat_http", "chunks:", stats_http_chunks,
            "downloaded:", stats_http_total,
            "elapsed_ms:", elapsed_ms,
            "speed:", speed, "B/s")
    end
end

-- ========== 主播放任务 ==========

local function play_task()
    -- 等待网络就绪
    wait_network_ready()

    local codec = get_audio_codec(AUDIO_URL)
    if not codec then
        log.error("audio", "不支持的音频格式")
        return
    end

    -- 初始化音频硬件
    if not exaudio.setup(audio_setup_param) then
        log.error("音频硬件初始化失败")
        return
    end
    exaudio.vol(60)

    log.info("stream", "========== 开始HTTP下载+播放 ==========")
    log.info("stream", "URL:", AUDIO_URL)

    stats_http_total = 0
    stats_http_chunks = 0
    stats_http_start_tick = 0
    stream_started = false
    need_header_parse = (codec.cid ~= 0) and codec.cid or nil
    warm_buf = {}
    parse_pos = 0
    play_sr = codec.sr
    play_bits = codec.bits
    play_ch = codec.ch
    play_sig = codec.sig

    -- 下载音频数据，边下边播
    httpplus.request({
        url = AUDIO_URL, timeout = 90,
        is_big_file = true,
        callback = http_callback,
    })

    -- HTTP下载完成
    log.info("stream", "HTTP下载完成，总字节:", stats_http_total)

    local http_elapsed = mcu.ticks2() - stats_http_start_tick
    local http_elapsed_ms = ticks_to_ms(http_elapsed)
    log.info("stat_summary",
        "http_total:", stats_http_total,
        "http_chunks:", stats_http_chunks,
        "http_time_ms:", http_elapsed_ms,
        "http_speed:", math.floor(stats_http_total * 1000 / http_elapsed_ms), "B/s")

    -- 通知流式数据已全部写入，可以结束
    exaudio.finish()

    -- 等待播放完成
    sys.waitUntil("PLAYBACK_DONE")

    log.info("stat_summary", "========== 播放完全结束 ==========")
end

-- 启动播放任务
sys.taskInit(play_task)
