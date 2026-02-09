--[[
@module codec_g711_pcm
@summary G711编解码演示
@version 13.3
@date 2025.11.16
@author 陈媛媛
@usage

注意：
如果搭配AirAUDIO_1000 音频板测试，需将AirAUDIO_1000 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

本文件为G711编解码演示功能模块，核心业务逻辑为：
1、使用exaudio流式播放原始PCM文件
2、对PCM文件进行G711编码并保存
3、对编码后的G711文件进行解码
4、使用exaudio流式播放解码后的PCM数据

本文件没有对外接口，直接在main.lua中require "codec_g711"就可以加载运行；
]]

-- 使用exaudio库
local exaudio = require "exaudio"

-- 音频配置参数
local audio_setup_param = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = gpio.AUDIOPA_EN,
    dac_ctrl = 20,
    pa_delay = 20,
    bits_per_sample = 16
}

-- 定义播放完成消息
local PLAY_COMPLETE_MSG = "AUDIO_PLAY_COMPLETE"

-- 定义播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成", "回调触发")
        -- 发布播放完成消息
        sys.publish(PLAY_COMPLETE_MSG)
    end
end

-- 等待播放完成的函数
local function wait_play_complete(timeout_ms)
    local result, data = sys.waitUntil(PLAY_COMPLETE_MSG, timeout_ms)

    if result then
        log.info("播放正常完成")
        return true
    else
        log.warn("等待播放完成超时", timeout_ms, "ms")
        return false
    end
end

-- 流式播放PCM文件的通用函数
local function stream_play_pcm_file(file_path, sampling_rate, sampling_depth, description)
    log.info("开始流式播放:", description)
    log.info("文件路径:", file_path)

    local stream_play_param = {
        type = 2,
        cbfnc = play_end_callback,
        sampling_rate = sampling_rate,
        sampling_depth = sampling_depth,
        signed_or_unsigned = true
    }

    -- 提前声明所有需要跨goto使用的变量
    local file_handle, total_written, chunk_count, play_success

    -- 启动播放
    if not exaudio.play_start(stream_play_param) then
        log.error("流式播放", "开始流式播放失败")
        return false
    end

    log.info("流式播放", "开始流式播放")

    local file_size = fs.fsize(file_path)
    log.info("文件大小", file_size, "字节")

    -- 打开文件 - 修改变量名
    file_handle = io.open(file_path, "rb")
    if not file_handle then
        log.error("流式播放", "无法打开文件:", file_path)
        goto CLEANUP_EXIT
    end

    -- 初始化变量（在goto标签之前）
    total_written = 0
    chunk_count = 0

    -- 文件读取和播放循环
    while true do
        local data = file_handle:read(4096)
        if not data or #data == 0 then
            break
        end

        if not exaudio.play_stream_write(data) then
            log.error("流式播放", "写入音频数据失败")
            goto CLEANUP_EXIT
        end

        chunk_count = chunk_count + 1
        total_written = total_written + #data

        if chunk_count % 10 == 0 then
            log.debug("流式播放", "写入音频数据块", chunk_count, "大小:", #data, "字节")
        end
        --写数据时不要死循环，每写一次，需要留出时间给其他task运行代码
        sys.wait(10)
    end

    -- 正常完成路径
    log.info("流式播放", "文件数据写入完成，总共", chunk_count, "块，", total_written, "字节")

    play_success = wait_play_complete(15000)

    -- 清理资源
    if file_handle then
        file_handle:close()
        file_handle = nil
        log.debug("资源清理", "文件句柄已关闭")
    end

    exaudio.play_stop(stream_play_param)
    log.debug("资源清理", "播放器已停止")

    if play_success then
        log.info("流式播放", "文件播放完成:", description)
        return true
    else
        log.warn("流式播放", "文件播放未在预期时间内完成:", description)
        return false
    end

    -- 错误路径清理（放在函数末尾，避免作用域问题）
    ::CLEANUP_EXIT::
    if file_handle then
        file_handle:close()
        file_handle = nil
        log.debug("资源清理", "文件句柄已关闭")
    end

    exaudio.play_stop(stream_play_param)
    log.debug("资源清理", "播放器已停止")

    return false
end

-- 解码G711文件到内存缓冲区
local function decode_g711_to_buffer(g711_file_path)
    log.info("开始完全解码G711文件:", g711_file_path)

    -- 提前声明所有需要跨goto使用的变量
    local decoder, decode_buffer, all_decoded_data, decode_count, total_decoded

    -- 创建解码器
    decoder = codec.create(codec.ALAW)
    if not decoder then
        log.error("解码", "创建G711解码器失败")
        goto CLEANUP_EXIT
    end

    result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed = codec.info(decoder, g711_file_path)
    if not result then
        log.error("解码", "无法获取G711文件信息")
        goto CLEANUP_EXIT
    end

    log.info("G711文件信息", "采样率:", sample_rate, "声道数:", num_channels, "位深度:", bits_per_sample)

    -- 创建解码缓冲区
    decode_buffer = zbuff.create(16384)
    if not decode_buffer then
        log.error("解码", "创建解码缓冲区失败")
        goto CLEANUP_EXIT
    end

    -- 获取文件信息
    -- 初始化变量（在goto标签之前）
    all_decoded_data = ""
    decode_count = 0
    total_decoded = 0

    log.info("开始解码过程...")

    -- 解码循环
    while true do
        local decode_result = codec.data(decoder, decode_buffer)
        if decode_result then
            local data_size = decode_buffer:used()
            if data_size > 0 then
                decode_count = decode_count + 1
                total_decoded = total_decoded + data_size

                -- 将解码数据添加到总缓冲区
                local chunk_data = decode_buffer:toStr(0, data_size)
                all_decoded_data = all_decoded_data .. chunk_data

                if decode_count % 20 == 0 then
                    log.debug("解码", "解码数据块", decode_count, "大小:", data_size, "字节")
                    --让出CPU时间片，避免任务占用过多系统资源
                    sys.wait(1)
                end
            else
                log.info("解码", "解码完成，没有更多数据")
                break
            end
        else
            log.info("解码", "G711解码完成")
            break
        end
    end

    -- 检查是否有有效数据
    if #all_decoded_data == 0 then
        log.error("解码", "解码完成但无数据")
        goto CLEANUP_EXIT
    end

    log.info("解码完成", "总解码数据大小:", #all_decoded_data, "字节")
    log.info("解码完成", "总共解码块数:", decode_count)


    -- 资源清理（放在函数末尾）
    ::CLEANUP_EXIT::
    if decoder then
        codec.release(decoder)
        decoder = nil
        log.debug("资源清理", "解码器已释放")
    end

    if decode_buffer then
        decode_buffer:free()
        decode_buffer = nil
        log.debug("资源清理", "解码缓冲区已释放")
    end

    if #all_decoded_data > 0 then
          return all_decoded_data
    else
        log.error("解码","解码失败")
    end

end

-- 流式播放内存中的PCM数据（不使用goto避免作用域问题）
local function stream_play_pcm_data(pcm_data, sampling_rate, sampling_depth, description)
    log.info("开始流式播放内存数据:", description)
    log.info("数据大小:", #pcm_data, "字节")

    local stream_play_param = {
        type = 2,
        cbfnc = play_end_callback,
        sampling_rate = sampling_rate,
        sampling_depth = sampling_depth,
        signed_or_unsigned = true
    }

    -- 启动播放
    if not exaudio.play_start(stream_play_param) then
        log.error("流式播放", "开始流式播放失败")
        return false
    end

    log.info("流式播放", "开始流式播放内存数据")

    local total_written = 0
    local chunk_count = 0
    local chunk_size = 4096
    local success = true

    -- 内存数据播放循环
    while success and total_written < #pcm_data do
        local remaining = #pcm_data - total_written
        local current_chunk_size = math.min(chunk_size, remaining)

        local chunk_data = pcm_data:sub(total_written + 1, total_written + current_chunk_size)

        if not exaudio.play_stream_write(chunk_data) then
            log.error("内存播放", "写入音频数据失败")
            success = false
            break
        end

        chunk_count = chunk_count + 1
        total_written = total_written + current_chunk_size

        if chunk_count % 10 == 0 then
            log.debug("内存播放", "写入音频数据块", chunk_count, "大小:", #chunk_data, "字节")
        end

        ----写数据时不要死循环，每写一次，需要留出时间给其他task运行代码
        sys.wait(10)
    end

    -- 正常完成路径
    if success then
        log.info("内存播放", "数据写入完成，总共", chunk_count, "块，", total_written, "字节")

        local play_success = wait_play_complete(15000)

        -- 清理资源
        exaudio.play_stop(stream_play_param)
        log.debug("资源清理", "播放器已停止")

        if play_success then
            log.info("内存播放", "数据播放完成:", description)
            return true
        else
            log.warn("内存播放", "数据播放未在预期时间内完成:", description)
            return false
        end
    else
        -- 资源清理
        exaudio.play_stop(stream_play_param)
        log.debug("资源清理", "播放器已停止")
        return false
    end
end

local encoder, in_buffer, out_buffer, pcm_data, decoded_data, play_success
local pcm_file_handle = io.open("/luadb/test.pcm", "rb")  -- 修改变量名

-- G711编解码演示主函数
function demo()
    log.info("开始G711编解码测试")

    -- 提前声明所有需要跨goto使用的变量

    -- 初始化音频设备
    log.info("exaudio", "开始配置音频设备")
    if not exaudio.setup(audio_setup_param) then
        log.error("exaudio", "音频设备配置失败")
        goto FINAL_CLEANUP
    end

    log.info("exaudio", "音频设备配置成功")

    -- 设置音量
    exaudio.vol(50)

    -- 第一步：使用流式播放原始PCM文件
    log.info("第一步：流式播放原始PCM文件")
    if not stream_play_pcm_file("/luadb/test.pcm", 16000, 16, "原始PCM文件") then
        log.error("演示", "原始PCM文件播放失败，跳过后续步骤")
        goto FINAL_CLEANUP
    end

    -- 第二步：对/luadb/test.pcm进行G711编码
    log.info("第二步：对/luadb/test.pcm进行G711编码")

    encoder = codec.create(codec.ALAW, false)
    if not encoder then
        log.error("G711编码", "创建编码器失败")
        goto FINAL_CLEANUP
    end
    log.info("G711编码器创建成功")

    -- 文件操作使用局部作用域，确保及时关闭
    do

        if not pcm_file_handle then
            log.error("G711编码", "无法打开PCM文件")
            goto FINAL_CLEANUP
        end
        pcm_data = pcm_file_handle:read("*a")
        pcm_file_handle:close()
    end

    pcm_size = #pcm_data
    log.info("PCM文件大小:", pcm_size, "字节")

    in_buffer = zbuff.create(pcm_size)
    out_buffer = zbuff.create(pcm_size)

    if not in_buffer or not out_buffer then
        log.error("G711编码", "创建缓冲区失败")
        goto FINAL_CLEANUP
    end

    in_buffer:write(pcm_data)

    log.info("开始G711编码，PCM数据大小:", pcm_size, "字节")
    encode_result = codec.encode(encoder, in_buffer, out_buffer, 0)
    if not encode_result then
        log.error("G711编码失败")
        goto FINAL_CLEANUP
    end

    log.info("G711编码结果:", encode_result)

    encoded_size = out_buffer:used()
    log.info("编码成功，编码后数据大小:", encoded_size, "字节")

    encoded_data = out_buffer:toStr(0, encoded_size)
    if not io.writeFile("/aaa.g711", encoded_data) then
        log.error("保存编码文件失败")
        goto FINAL_CLEANUP
    end

    log.info("编码数据已保存到 /aaa.g711")

    -- 第三步：先完全解码，再播放
    log.info("第三步：先完全解码G711文件，再播放")

    -- 先完全解码到内存缓冲区
    decoded_data = decode_g711_to_buffer("/aaa.g711")
    if not decoded_data then
        log.error("解码", "G711文件解码失败")
        goto FINAL_CLEANUP
    end

    log.info("解码完成", "准备播放解码后的数据，大小:", #decoded_data, "字节")

    -- 使用内存数据播放
    play_success = stream_play_pcm_data(decoded_data, 16000, 16, "G711解码数据")

    if play_success then
        log.info("播放", "G711解码数据播放成功")
    else
        log.error("播放", "G711解码数据播放失败")
    end

    -- 正常完成路径
    log.info("G711编解码测试完成")

    -- 最终资源清理
    ::FINAL_CLEANUP::
    if encoder then
        codec.release(encoder)
        encoder = nil
        log.debug("资源清理", "编码器已释放")
    end

    if in_buffer then
        in_buffer:free()
        in_buffer = nil
        log.debug("资源清理", "输入缓冲区已释放")
    end

    if out_buffer then
        out_buffer:free()
        out_buffer = nil
        log.debug("资源清理", "输出缓冲区已释放")
    end

    -- 确保音频设备停止
    exaudio.play_stop(stream_play_param)
    log.debug("资源清理", "播放器已停止")
end

-- 启动G711演示任务函数
local function start_g711_demo()
    demo()
end

-- 启动G711演示任务
sys.taskInit(start_g711_demo)
