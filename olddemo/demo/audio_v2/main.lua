PROJECT = "audio_v2_test"
VERSION = "1.0.1"
log.style(1)
local taskName = "task_audio"
local es8311 = require "es8311"
local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

local buff0 = zbuff.create(16000)
local buff1 = zbuff.create(16000)

local i2c_id = 1
local stream_file_fp = nil
local stream_request_index = nil
local function audio_cb(request_index, event, param)
    log.info("audio_cb", request_index, event, param)
    if stream_file_fp and request_index == stream_request_index then
        if event == audio_v2.REQUEST_NEED_NEW_DATA then
            local result, write_len, free_len = audio_v2.input(stream_request_index)
            log.info("stream fifo", result, free_len)
            if result then
                local file_end = false
                while free_len > 4096 and not file_end do
                    local data = stream_file_fp:read(4096)
                    if data then
                        if #data < 4096 then
                            result, write_len, free_len = audio_v2.input(stream_request_index, data, true)
                            file_end = true
                        else
                            result, write_len, free_len = audio_v2.input(stream_request_index, data, false)
                        end
                    else
                        result, write_len, free_len = audio_v2.input(stream_request_index, nil, true)
                        file_end = true
                    end
                    log.info("stream fifo write", result, write_len, free_len, file_end)
                end
            end
        end
    end
end
audio_v2.debug(true)
audio_v2.on(audio_cb)


function audio_setup_1601_evb()
    audio_v2.config_pa_power_ctrl(true, 12, 0, 100)  --PA能控制
    audio_v2.config_codec_power_ctrl(false, nil, nil, 200, 10) --codec电源不控制，只控制播放前的空白音时长
    audio_v2.soft_volume(80)
end

function audio_setup_air780ehm_evb()
    local all_nums, default_driver_index = audio_v2.get_driver_info()
    for i = 0, all_nums - 1 do
        log.info("驱动序号", i, "id", audio_v2.print_probe_id(audio_v2.get_driver_id(i), true))
    end
    log.info("默认驱动序号", default_driver_index, "id", audio_v2.print_probe_id(audio_v2.get_driver_id(default_driver_index), true))
    audio_v2.config_pa_power_ctrl(true, 1, 1, 200)  --PA能控制
    audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0) --codec电源不控制，只控制播放前的空白音时长

    audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)

    i2c.setup(i2c_id)
    gpio.setup(2, 1) --全程都打开codec电源
    es8311.init(i2c_id)
    es8311.set_sample_rate(i2c_id,16000,256)
    es8311.set_data_bits(i2c_id,16)
    es8311.set_format(i2c_id)
    es8311.resume(i2c_id)
    es8311.set_voice_vol(i2c_id,60)
    es8311.set_mic_vol(i2c_id,80)
    --es8311.standby(i2c_id)
end

local function play_task()
    local i2c_id = 1
    local amrs = {"/luadb/alipay.amr", "/luadb/2.amr", "/luadb/10.amr", "/luadb/yuan.amr"}
    local file_data, no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed, result
    while true do
        audio_v2.play(amrs)
        audio_v2.play("/luadb/test_16k.mp3")
        --audio_v2.play("/luadb/test_32k.mp3")
        --audio_v2.play("/luadb/test_44k.mp3")
        while not audio_v2.is_all_done() do --简单的看看有没有都播放完，实际需要在回调里判断+消息通知task
            sys.wait(1000)
        end
        log.info(rtos.meminfo("sys"))
        log.info(rtos.meminfo("lua"))
        -- 演示流模式播放
        stream_file_fp = io.open("/luadb/test_44k.mp3", "rb")
        sample_rate = 0
        if stream_file_fp then
            file_data  = stream_file_fp:read(12)
            no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = audio_v2.get_play_info(file_data, audio_v2.DATA_CODEC_TYPE_MP3, 0)
            if no_error then
                if sample_rate ~= 0 then
                    log.info("mp3 file info", sample_rate, data_bits, channel_nums, is_signed)
                    stream_file_fp:seek("set", next_pos)
                    log.info("data start", next_pos)
                else
                    local retry_count = 0
                    while retry_count < 6 and no_error and sample_rate == 0 do
                        log.info("seek", next_pos, "get", need_len)
                        stream_file_fp:seek("set", next_pos)
                        file_data  = stream_file_fp:read(need_len)
                        log.info("read", #file_data)
                        no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = audio_v2.get_play_info(file_data, audio_v2.DATA_CODEC_TYPE_MP3, next_pos)
                        retry_count = retry_count + 1
                    end
                    if no_error and sample_rate ~= 0 then
                        log.info("mp3 file info", sample_rate, data_bits, channel_nums, is_signed)
                        stream_file_fp:seek("set", next_pos)
                        log.info("data start", next_pos)
                    else
                        log.warn("get mp3 file info failed", retry_count, no_error, sample_rate)
                    end
                end
            end
            if sample_rate ~= 0 then
                result, stream_request_index = audio_v2.stream(audio_v2.DATA_CODEC_TYPE_MP3, sample_rate, data_bits, channel_nums, is_signed, 0)
                while not audio_v2.is_all_done() do --简单的看看有没有都播放完，实际需要在回调里判断+消息通知task
                    sys.wait(1000)
                end
            end
            stream_file_fp:close()
            stream_file_fp = nil
        else
            log.warn("mp3 file not found")
        end
        file_data = nil
    end
end
--audio_setup_1601_evb()
audio_setup_air780ehm_evb()
sys.taskInit(play_task)
sys.run()
