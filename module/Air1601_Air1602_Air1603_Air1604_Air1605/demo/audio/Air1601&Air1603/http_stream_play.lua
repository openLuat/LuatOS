--[[
@module  http_stream_play
@summary HTTP音频流式播放（边下边播）
@version 1.0
@date    2026.07.21
@author  拓毅恒
@usage
使用httpplus进行HTTP下载，边下边播

注意：
1. Air1601使用内置DAC输出音频，无需外部音频编解码芯片
2. 支持PCM/AMR/MP3/WAV格式的HTTP边下边播
3. 依赖exaudio扩展库自动初始化音频硬件，使用新音频框架
4. 固件需要V1026及以上的版本才能播放
5. PCM格式默认16kHz、16位、有符号、单声道
6. AMR/MP3/WAV格式会自动解析文件头获取真实采样率
]]

local exaudio = require "exaudio"
local exnetif = require "exnetif"
local httpplus = require "httpplus"

-- 硬件环境配置说明
-- 本Demo支持以下硬件环境，请根据实际使用情况修改HARDWARE_ENV变量：
--   "AIR1601_V1_1"  - Air1601 V1.1开发板：PA_EN = IO12
--   "AIR1601_V1_2"  - Air1601 V1.2开发板：PA_EN = IO73
-- 详细说明请参考本目录下的readme.md文件
HARDWARE_ENV = "AIR1601_V1_2"  -- 使用"AIR1601_V1_2"开发板

-- PA脚映射：不同板型/版本的功放使能脚不同
local pa_pin_map = {
    AIR1601_V1_1 = 12,
    AIR1601_V1_2 = 73,
}
local pa_pin = pa_pin_map[HARDWARE_ENV] or 73

-- WiFi配置
local WIFI_SSID = "luatos1234"
local WIFI_PASS = "12341234"

-- HTTP音频文件URL（可替换为AMR/MP3/WAV/PCM的URL）
local AUDIO_URL = "https://appstoreoss.luatos.com/iot-apps/res/100617/sample-6s.mp3"

-- 音频初始化设置参数
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = pa_pin,         -- 音频放大器电源控制管脚，按HARDWARE_ENV自动选择(见上方映射)
    pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
    dac_delay = 6,            -- DAC启动前冗余时间，单位为100ms
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

-- ========== 网络连接 ==========

local function wait_network_ready()
    log.info("wifi", "开始连接WiFi", WIFI_SSID)
    sys.subscribe("WLAN_STA_INC", function(evt, data) log.info("wifi", "STA事件:", evt, data) end)
    sys.subscribe("IP_READY", function(ip, adapter)
        if adapter == socket.LWIP_STA then
            socket.setDNS(adapter, 1, "223.5.5.5")
            socket.setDNS(adapter, 2, "114.114.114.114")
            log.info("wifi", "IP_READY", socket.localIP(socket.LWIP_STA))
        end
    end)
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,
                airlink_type = airlink.MODE_UART,
                airlink_uart_id = 3,
                airlink_uart_baud = 2000000,
                ssid = WIFI_SSID,
                password = WIFI_PASS
            }
        }
    })
    log.info("wifi", "等待IP获取...")
    local r = sys.waitUntil("IP_READY", 30000)
    if r then
        log.info("wifi", "WiFi连接成功"); return true
    else
        log.error("wifi", "WiFi连接超时"); return false
    end
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
            -- 缓冲数据模式下 parse_audio_info 不会自动重试：返回 sample_rate:0 + data_start 表示需推进位置继续解析。
            -- 服务端常以单个 chunk 一次性返回全部数据，不会再触发“下一包回调”，
            -- 若只等下一包会永远卡死在 sys.waitUntil("PLAYBACK_DONE")；故必须就地在已缓冲数据上按 data_start 推进重试。
            -- 头部若带 ID3v2 标签（"ID3" 开头），先按标签长度跳过，使首包即定位到 MP3 帧，避免重复解析/重复打印 ID3 日志
            -- ID3v2 头：3字节"ID3" + 2字节版本 + 1字节flags + 4字节syncsafe长度（每字节高位置0）。
            if combined:sub(1, 3) == "ID3" then
                local c7, c8, c9, c10 = combined:byte(7, 10)
                if c7 and c8 and c9 and c10 then
                    local tag_len = (c7 % 128) * 0x200000 + (c8 % 128) * 0x4000 + (c9 % 128) * 0x80 + (c10 % 128)
                    parse_pos = 10 + tag_len
                end
            end
            -- 单点调用 parse_audio_info 并就地按 data_start 推进重试，
            -- 数据一次性到达时也不会死等“下一包”；guard 上限 + 位置不前进即退出，防止异常死循环。
            local info
            local guard = 0
            while guard < 32 do
                info = exaudio.parse_audio_info(combined, need_header_parse, parse_pos)
                guard = guard + 1
                if not (info and info.sample_rate == 0) then break end
                local next_pos = info.data_start or (parse_pos + chunk_size)
                if next_pos <= parse_pos or next_pos >= #combined then break end
                parse_pos = next_pos
            end
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
    -- 下载可能在 1 个 tick(<1ms)内完成导致 http_elapsed_ms 为 0，除零会得到 inf，这里加保护
    local http_speed = (http_elapsed_ms and http_elapsed_ms > 0)
        and math.floor(stats_http_total * 1000 / http_elapsed_ms) or 0
    log.info("stat_summary",
        "http_total:", stats_http_total,
        "http_chunks:", stats_http_chunks,
        "http_time_ms:", http_elapsed_ms,
        "http_speed:", http_speed, "B/s")

    -- 通知流式数据已全部写入，可以结束
    exaudio.finish()

    -- 等待播放完成
    sys.waitUntil("PLAYBACK_DONE")

    log.info("stat_summary", "========== 播放完全结束 ==========")
end

-- 启动播放任务
sys.taskInit(play_task)
