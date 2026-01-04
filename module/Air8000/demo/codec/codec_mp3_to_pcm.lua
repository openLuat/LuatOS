--[[
@module codec_mp3_to_pcm
@summary MP3解码为PCM并流式播放演示
@version 2.4
@date 2025.11.18
@author 陈媛媛

本文件为GMP3解码为PCM并流式播放演示功能模块，核心业务逻辑为：
1、 使用exaudio流式播放原始MP3文件
2、对MP3文件进行解码得到PCM数据
3、将解码后的PCM数据通过exaudio流式播放
4、等待播放完成并释放所有资源
本文件没有对外接口，直接在main.lua中require " codec_mp3_to_pcm"就可以加载运行；
]]

-- 使用exaudio库
local exaudio = require("exaudio")

-- 初始化exaudio音频设备
local audio_configs = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = 162,
    dac_ctrl = 164,
    pa_delay = 20,
    bits_per_sample = 16,
    channels =2
}

-- 文件路径定义
 local MP3_FILE = "/luadb/sample-6s.mp3"
-- 定义播放完成消息
local PLAY_COMPLETE_MSG = "MP3_PLAY_COMPLETE"

-- 播放状态标志
local is_playing = false

-- 播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("MP3播放完成", "回调触发")
        is_playing = false
        -- 发布播放完成消息
        sys.publish(PLAY_COMPLETE_MSG)
    end
end

-- 等待播放完成的函数
local function wait_play_complete(timeout_ms)
    local result, data = sys.waitUntil(PLAY_COMPLETE_MSG, timeout_ms)

    if result then
        log.info("MP3播放正常完成")
        return true
    else
        log.warn("等待MP3播放完成超时", timeout_ms, "ms")
        return false
    end
end

-- MP3转PCM流式播放演示主函数
function demo()
    log.info("开始MP3解码为PCM并使用exaudio流式播放")

    -- 提前声明所有需要跨goto使用的变量
    local decoder, decode_buffer, play_success
    local sample_rate, bits_per_sample, num_channels, result, audio_format, channels, rate, bits, is_signed
    local audio_play_param, pre_decode_count, pre_decoded_data
    local decode_count, total_decoded  -- 将这两个变量也提前声明

    -- 使用exaudio.setup初始化音频设备
    log.info("使用exaudio.setup初始化音频设备")
    if exaudio.setup(audio_configs) then
        log.info("exaudio.setup初始化成功")
    else
        log.error("exaudio.setup初始化失败")
        goto FINAL_CLEANUP
    end

    -- 设置音量
    exaudio.vol(50)
    log.info("初始音量设置为50")

    -- 创建MP3解码器
    decoder = codec.create(codec.MP3, true)
    if not decoder then
        log.error("MP3解码器创建失败")
        goto FINAL_CLEANUP
    end

    -- 解析MP3文件信息
    result, audio_format, channels, rate, bits, is_signed = codec.info(decoder, MP3_FILE)
    if not result then
        log.error("解析MP3文件信息失败")
        goto FINAL_CLEANUP
    end

    -- 使用MP3文件的原始采样率
    sample_rate = rate
    bits_per_sample = bits
    num_channels = channels  

    log.info("MP3文件原始信息:")
    log.info("原始声道数:", channels)
    log.info("采样率:", sample_rate)
    log.info("位深度:", bits_per_sample)
    log.info("播放声道数:", num_channels)

    -- 创建解码缓冲区
    decode_buffer = zbuff.create(16384)
    if not decode_buffer then
        log.error("创建解码缓冲区失败")
        goto FINAL_CLEANUP
    end

    -- 预先解码一些数据，确保播放启动时有数据可播
    log.info("预先解码数据准备...")
    pre_decode_count = 0
    pre_decoded_data = ""
    
    -- 预先解码循环
    while pre_decode_count < 5 do  -- 预先解码5个块
        local decode_result = codec.data(decoder, decode_buffer, 4096)
        if decode_result then
            local data_size = decode_buffer:used()
            if data_size > 0 then
                local pcm_data = decode_buffer:toStr(0, data_size)
                pre_decoded_data = pre_decoded_data .. pcm_data
                decode_buffer:del(0, data_size)
                pre_decode_count = pre_decode_count + 1
                log.info("预先解码块", pre_decode_count, "大小:", data_size, "字节")
            else
                log.warn("预先解码数据大小为0")
                break
            end
        else
            log.warn("预先解码失败")
            break
        end
    end

    if #pre_decoded_data == 0 then
        log.error("预先解码失败，没有获得数据")
        goto FINAL_CLEANUP
    end

    -- 确保预先解码的数据是1024的倍数
    if #pre_decoded_data % 1024 ~= 0 then
        local remainder = 1024 - (#pre_decoded_data % 1024)
        pre_decoded_data = pre_decoded_data .. string.rep("\0", remainder)
    end

    log.info("预先解码完成，总数据大小:", #pre_decoded_data, "字节")

    -- 配置流式播放参数
    audio_play_param = {
        type = 2,  -- 流式播放
        cbfnc = play_end_callback,
        sampling_rate = sample_rate,
        sampling_depth = bits_per_sample,
        signed_or_unsigned = true
    }

    -- 启动流式播放
    if exaudio.play_start(audio_play_param) then
        log.info("exaudio流式播放启动成功")
        is_playing = true
    else
        log.error("exaudio流式播放启动失败")
        goto FINAL_CLEANUP
    end

    -- 立即写入预先解码的数据
    if not exaudio.play_stream_write(pre_decoded_data) then
        log.error("流式写入预先解码数据失败")
        goto FINAL_CLEANUP
    end
    log.info("预先解码数据已写入，大小:", #pre_decoded_data, "字节")

    -- 继续解码剩余数据
    log.info("开始持续解码剩余数据...")
    
    -- 初始化解码计数和总数据大小变量
    decode_count = pre_decode_count
    total_decoded = #pre_decoded_data
    
    while is_playing do
        -- 解码数据
        local decode_result = codec.data(decoder, decode_buffer, 4096)
        
        if decode_result then
            local data_size = decode_buffer:used()
            if data_size > 0 then
                decode_count = decode_count + 1
                total_decoded = total_decoded + data_size
                
                -- 将解码后的PCM数据转换为字符串
                local pcm_data = decode_buffer:toStr(0, data_size)
                
                -- 确保数据长度是1024的倍数（exaudio要求）
                if #pcm_data % 1024 ~= 0 then
                    local remainder = 1024 - (#pcm_data % 1024)
                    pcm_data = pcm_data .. string.rep("\0", remainder)
                end
                
                -- 使用exaudio流式写入音频数据
                if exaudio.play_stream_write(pcm_data) then
                    if decode_count % 10 == 0 then
                        log.info("解码并写入数据块", decode_count, "大小:", #pcm_data, "字节", "累计:", total_decoded, "字节")
                    end
                else
                    log.error("流式写入音频数据失败")
                    goto FINAL_CLEANUP
                end
                
                -- 清空缓冲区以便下次使用
                decode_buffer:del(0, data_size)
                
                -- 这个等待是必须的，用于让出CPU时间片，避免任务占用过多系统资源
                sys.wait(3)
            else
                log.info("解码完成，没有更多数据")
                break
            end
        else
            log.info("MP3解码完成")
            break
        end
    end

    log.info("MP3解码完成，总解码数据:", total_decoded, "字节")

    -- 等待播放完成
    if is_playing then
        play_success = wait_play_complete(15000)
    else
        log.warn("播放已提前结束")
        play_success = false
    end

    -- 正常完成路径
    log.info("MP3转PCM流式播放演示完成")

    -- 最终资源清理
    ::FINAL_CLEANUP::
    is_playing = false
    
    if decoder then
        codec.release(decoder)
        decoder = nil
        log.debug("资源清理", "MP3解码器已释放")
    end

    if decode_buffer then
        decode_buffer:free()
        decode_buffer = nil
        log.debug("资源清理", "解码缓冲区已释放")
    end

    -- 确保音频设备停止
    exaudio.play_stop()
    log.debug("资源清理", "播放器已停止")

    return play_success or false
end

-- 启动MP3演示任务函数
local function start_mp3_to_pcm_demo()
    demo()
end

-- 启动MP3演示任务
sys.taskInit(start_mp3_to_pcm_demo)
