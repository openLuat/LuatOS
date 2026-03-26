--[[
@module  codec_pcm_to_amr
@summary PCM编码为AMR并播放
@version 2.3
@date    2025.11.18
@author  陈媛媛
@usage

注意：
如果搭配AirAUDIO_1000 音频板测试，需将AirAUDIO_1000 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

本文件为PCM编码为AMR功能模块，支持AMR-NB(8kHz)和AMR-WB(16kHz)两种模式，核心业务逻辑为：
1、使用exaudio播放原始PCM文件
2、对PCM文件进行AMR编码并保存（AMR-NB或AMR-WB，由TEST_AMR_NB开关控制）
3、播放编码后的AMR文件
4、等待播放完成并释放所有资源

测试开关 TEST_AMR_NB：
  - true:  AMR-NB模式，使用8kHz PCM文件，输出文件头 #!AMR\n
  - false: AMR-WB模式，使用16kHz PCM文件，输出文件头 #!AMR-WB\n

本文件没有对外接口，直接在main.lua中require "codec_pcm_to_amr"就可以加载运行；
]]

local exaudio = require "exaudio"

-- 测试开关：true = AMR-NB (8kHz), false = AMR-WB (16kHz)
local TEST_AMR_NB = false

-- 音频初始化设置参数
local audio_setup_param = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = gpio.AUDIOPA_EN,
    dac_ctrl = 20,
    pa_delay = 20,
    bits_per_sample = 16,
    pa_on_level = 1
}

-- 文件路径定义（根据测试模式选择）
local PCM_FILE = TEST_AMR_NB and "/luadb/test_8k.pcm" or "/luadb/test.pcm"
local AMR_OUTPUT_FILE = TEST_AMR_NB and "/encoded_amr_nb.amr" or "/encoded_amr_wb.amr"

-- AMR文件头
local AMR_HEADER = TEST_AMR_NB and "#!AMR\n" or "#!AMR-WB\n"

-- 定义播放完成消息
local PLAY_COMPLETE_MSG = "AMR_PLAY_COMPLETE"

-- 播放完成回调
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("AMR播放完成", "回调触发")
        sys.publish(PLAY_COMPLETE_MSG)
    end
end

-- 等待播放完成的函数
local function wait_play_complete(timeout_ms)
    local result, data = sys.waitUntil(PLAY_COMPLETE_MSG, timeout_ms)

    if result then
        log.info("AMR播放正常完成")
        return true
    else
        log.warn("等待AMR播放完成超时", timeout_ms, "ms")
        return false
    end
end

-- PCM转AMR编码并播放演示主函数
function demo()
    local mode_name = TEST_AMR_NB and "AMR-NB(8kHz)" or "AMR-WB(16kHz)"
    log.info("开始PCM转AMR编码并播放演示", "模式:", mode_name)

    -- 提前声明所有需要跨goto使用的变量
    local encoder, in_buffer, out_buffer, pcm_file, pcm_data, encode_result
    local encoded_size, encoded_data, play_success, file_check, pcm_size, amr_size
    local audio_play_param

    -- 初始化音频设备
    log.info("初始化音频设备")
    if not exaudio.setup(audio_setup_param) then
        log.error("音频设备初始化失败")
        goto FINAL_CLEANUP
    end

    -- 设置音量
    exaudio.vol(60)
    log.info("音量设置为60")

    -- 检查PCM文件是否存在
    file_check = io.open(PCM_FILE, "r")
    if not file_check then
        log.error("PCM文件不存在:", PCM_FILE)
        goto FINAL_CLEANUP
    end
    file_check:close()

    pcm_size = fs.fsize(PCM_FILE)
    log.info("原始PCM文件大小:", pcm_size, "字节")

    -- 创建AMR编码器（根据测试模式选择AMR-NB或AMR-WB）
    encoder = codec.create(TEST_AMR_NB and codec.AMR or codec.AMR_WB, false, 4)
    if not encoder then
        log.error("AMR编码器创建失败", mode_name)
        goto FINAL_CLEANUP
    end
    log.info("AMR编码器创建成功", mode_name)

    -- 读取PCM文件
    pcm_file = io.open(PCM_FILE, "rb")
    if not pcm_file then
        log.error("无法打开PCM文件:", PCM_FILE)
        goto FINAL_CLEANUP
    end

    pcm_data = pcm_file:read("*a")
    pcm_file:close()
    log.info("实际读取的PCM数据大小:", #pcm_data, "字节")

    -- 创建输入和输出缓冲区
    in_buffer = zbuff.create(#pcm_data)
    out_buffer = zbuff.create(#pcm_data)

    if not in_buffer or not out_buffer then
        log.error("创建缓冲区失败")
        goto FINAL_CLEANUP
    end

    -- 将PCM数据写入输入缓冲区
    in_buffer:write(pcm_data)

    -- 执行AMR编码
    log.info("开始AMR编码", mode_name)
    encode_result = codec.encode(encoder, in_buffer, out_buffer, 4)

    if not encode_result then
        log.error("AMR编码失败", mode_name)
        goto FINAL_CLEANUP
    end

    encoded_size = out_buffer:used()
    log.info("AMR编码成功", mode_name, "编码后数据大小:", encoded_size, "字节")

    -- 保存编码后的AMR数据到文件
    encoded_data = out_buffer:toStr(0, encoded_size)

    -- 添加AMR文件头（根据模式选择）
    encoded_data = AMR_HEADER .. encoded_data

    -- 写入文件
    if not io.writeFile(AMR_OUTPUT_FILE, encoded_data) then
        log.error("保存AMR文件失败", mode_name)
        goto FINAL_CLEANUP
    end

    amr_size = fs.fsize(AMR_OUTPUT_FILE)
    log.info("AMR文件保存成功:", AMR_OUTPUT_FILE, "大小:", amr_size, "字节")

    -- 配置音频播放参数
    audio_play_param = {
        type = 0,  -- 文件播放
        content = AMR_OUTPUT_FILE,
        cbfnc = play_end_callback
    }

    -- 开始播放
    log.info("开始播放AMR文件", mode_name)
    if not exaudio.play_start(audio_play_param) then
        log.error("AMR文件播放失败", mode_name)
        goto FINAL_CLEANUP
    end

    log.info("AMR文件开始播放", mode_name)

    -- 等待播放完成
    play_success = wait_play_complete(30000)

    -- 正常完成路径
    log.info("PCM转AMR编码并播放演示完成", mode_name)

    -- 最终资源清理
    ::FINAL_CLEANUP::
    if encoder then
        codec.release(encoder)
        encoder = nil
        log.debug("资源清理", "AMR编码器已释放")
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
    exaudio.play_stop(audio_play_param)
    log.debug("资源清理", "播放器已停止")

    return play_success or false
end

-- 启动AMR演示任务函数
local function start_pcm_to_amr_demo()
    demo()
end

-- 启动AMR演示任务
sys.taskInit(start_pcm_to_amr_demo)
