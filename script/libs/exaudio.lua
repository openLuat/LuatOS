--[[
@module exaudio
@summary exaudio扩展库
@version 1.2
@date    2026.1.6
@author  wangshihao
@updates
    v1.2 2026.1.6
        1. 新增双声道播放支持，exaudio.setup增加一个声道的配置参数
        2. 录音时间设置成0,会一直录音是正常的,api库已说明，这里再增加log打印提示
        3. 使用exaudio.record_stop()停止录音时，会有一小部分结尾的数据因为没有进入audio.on中的audio.RECORD_DATA事件而丢失，解决方案：
            在调用exaudio.record_stop()后，检查两个PCM缓冲区，确保所有数据都被处理
        4. exaudio.play_stream_write(data),流式音频数据,单次写入的长度修改为根据每秒播放数据量来确定
        5. 低功耗自动控制，exaudio.setup默认POWEROFF模式,exaudio.play_start和exaudio.record_start会自动切换到RESUME模式,播放完成或录音完成，会自动切换到POWEROFF模式
@usage
]]
local exaudio = {}

-- 常量定义
local I2S_ID = 0
local I2S_MODE = 0          -- 0:主机 1:从机
local I2S_SAMPLE_RATE = 16000
local I2S_COMM_FORMAT = i2s.MODE_LSB   -- 可选MODE_I2S, MODE_LSB, MODE_MSB
local I2S_CHANNEL_BITS = 16
local MULTIMEDIA_ID = 0
local EX_MSG_PLAY_DONE = "playDone"
local ES8311_ADDR = 0x18    -- 7位地址
local CHIP_ID_REG = 0x00    -- 芯片ID寄存器地址
local PCM_BUFFER_DURATION_MS = 50  -- 每个缓冲区的时长（毫秒）

-- 模块常量
exaudio.PLAY_DONE = 1         --   音频播放完毕的事件之一
exaudio.RECORD_DONE = 1       --   音频录音完毕的事件之一  
exaudio.AMR_NB = 0
exaudio.AMR_WB = 1
exaudio.PCM_8000 = 2
exaudio.PCM_16000 = 3 
exaudio.PCM_24000 = 4
exaudio.PCM_32000 = 5
exaudio.PCM_48000 = 6


-- 默认配置参数
local audio_setup_param = {
    model = "es8311",         -- dac类型: "es8311"
    i2c_id = 0,               -- i2c_id: 0,1
    pa_ctrl = 0,              -- 音频放大器电源控制管脚
    dac_ctrl = 0,             -- 音频编解码芯片电源控制管脚
    dac_delay = 3,            -- DAC启动前冗余时间(100ms)
    pa_delay = 10,           -- DAC启动后延迟打开PA的时间(ms)
    dac_time_delay = 600,      -- 播放完毕后PA与DAC关闭间隔(ms)
    bits_per_sample = 16,     -- 采样位数
    pa_on_level = 1,          -- PA打开电平 1:高 0:低       
    channels = 1              -- 声道数: 1:单声道 2:双声道  
}

local audio_play_param = {
    type = 0,                  -- 0:文件 1:TTS 2:流式
    content = nil,             -- 播放内容
    cbfnc = nil,               -- 播放完毕回调
    priority = 0,              -- 优先级(数值越大越高)
    sampling_rate = 16000,     -- 采样率(仅流式)
    sampling_depth = 16,       -- 采样位深(仅流式)
    signed_or_unsigned = true, -- PCM是否有符号(仅流式)
    channels = 1,              -- 声道数 1:单声道 2:双声道（将使用setup中的配置）
    stream_buffer_size = 0,    -- 流式缓冲区大小(字节)
}

local audio_record_param = {
    format = 0,               -- 录制格式，支持exaudio.AMR_NB，exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000,exaudio.PCM_48000
    time = 5,                 -- 录制时间(秒)
    path = nil,               -- 文件路径或流式回调
    cbfnc = nil               -- 录音完毕回调
}

-- 内部变量
local pcm_buff0 = nil
local pcm_buff1 = nil
local voice_vol = 65
local mic_vol = 80

-- 定义全局队列表
local audio_play_queue = {
    data = {},       -- 存储字符串的数组
    sequenceIndex = 1  -- 用于跟踪插入顺序的索引
}

-- 向队列中添加字符串（按调用顺序插入）
local function audio_play_queue_push(str)
    if type(str) == "string" then
        -- 存储格式: {index = 顺序索引, value = 字符串值}
        table.insert(audio_play_queue.data, {
            index = audio_play_queue.sequenceIndex,
            value = str
        })
        audio_play_queue.sequenceIndex = audio_play_queue.sequenceIndex + 1
        return true
    end
    return false
end

-- 从队列中取出最早插入的字符串（按顺序取出）
local function audio_play_queue_pop()
    if #audio_play_queue.data > 0 then
        -- 取出并移除第一个元素
        local item = table.remove(audio_play_queue.data, 1)
        return item.value  -- 返回值
    end
    return nil
end

-- 清空队列中所有数据
function audio_queue_clear()
    -- 清空数组
    audio_play_queue.data = {}
    -- 重置顺序索引
    audio_play_queue.sequenceIndex = 1
    return true
end

-- 工具函数：参数检查
local function check_param(param, expected_type, name)
    if type(param) ~= expected_type then
        log.error(string.format("参数错误: %s 应为 %s 类型", name, expected_type))
        return false
    end
    return true
end

-- 计算缓冲区大小, 公式：采样率 * 声道数 * 采样位数/8 * 缓冲区时长(秒)
local function calculate_buffer_size(sampling_rate, sampling_depth, channels)
    local bytes_per_sample = sampling_depth / 8
    local bytes_per_channel_per_second = sampling_rate * bytes_per_sample
    local bytes_per_buffer = bytes_per_channel_per_second * channels * (PCM_BUFFER_DURATION_MS / 1000)
    return math.floor(bytes_per_buffer / 4) * 4  -- 对齐到4字节
end

-- 音频回调处理
local function audio_callback(id, event, point)
    -- log.info("audio_callback", "event:", event, 
    --         "MORE_DATA:", audio.MORE_DATA, 
    --         "DONE:", audio.DONE,
    --         "RECORD_DATA:", audio.RECORD_DATA,
    --         "RECORD_DONE:", audio.RECORD_DONE)

    if event == audio.MORE_DATA then
        audio.write(MULTIMEDIA_ID,audio_play_queue_pop())
    elseif event == audio.DONE then
        if type(audio_play_param.cbfnc) == "function" then
            audio_play_param.cbfnc(exaudio.PLAY_DONE)
        end
        audio_queue_clear()  -- 清空流式播放数据队列
        audio.pm(MULTIMEDIA_ID, audio.POWEROFF) -- audio.POWEROFF模式
        sys.publish(EX_MSG_PLAY_DONE)
        
    elseif event == audio.RECORD_DATA then
        if type(audio_record_param.path) == "function" then
            local buff, len = point == 0 and pcm_buff0 or pcm_buff1,
                             point == 0 and pcm_buff0:used() or pcm_buff1:used()
            audio_record_param.path(buff, len)
        end
        
    elseif event == audio.RECORD_DONE then
        if type(audio_record_param.cbfnc) == "function" then
            audio_record_param.cbfnc(exaudio.RECORD_DONE)
        end

        audio.pm(MULTIMEDIA_ID, audio.POWEROFF) -- audio.POWEROFF模式
    end
end

-- 读取ES8311芯片ID
local function read_es8311_id()
    -- 发送读取请求
    local send_ok = i2c.send(audio_setup_param.i2c_id, ES8311_ADDR, CHIP_ID_REG)
    if not send_ok then
        log.error("发送芯片ID读取请求失败")
        return false
    end

    -- 读取数据
    local data = i2c.recv(audio_setup_param.i2c_id, ES8311_ADDR, 1)
    if data and #data == 1 then
        return true
    end

    log.error("读取ES8311芯片ID失败")
    return false
end

-- 音频硬件初始化
local function audio_setup()
    -- I2C配置
    if not i2c.setup(audio_setup_param.i2c_id, i2c.FAST) then
        log.error("I2C初始化失败")
        return false
    end
    -- 初始化I2S
    local I2S_CHANNEL_FORMAT = audio_setup_param.channels == 2 and i2s.STEREO or i2s.MONO_R
    local result, data = i2s.setup(
        I2S_ID, 
        I2S_MODE, 
        I2S_SAMPLE_RATE, 
        audio_setup_param.bits_per_sample, 
        I2S_CHANNEL_FORMAT, 
        I2S_COMM_FORMAT,
        I2S_CHANNEL_BITS
    )

    if not result then
        log.error("I2S设置失败")
        return false
    end
    -- 配置音频通道
    audio.config(
        MULTIMEDIA_ID, 
        audio_setup_param.pa_ctrl, 
        audio_setup_param.pa_on_level, 
        audio_setup_param.dac_delay, 
        audio_setup_param.pa_delay, 
        audio_setup_param.dac_ctrl, 
        1,  -- power_on_level
        audio_setup_param.dac_time_delay
    )
    -- 设置总线
    audio.setBus(
        MULTIMEDIA_ID, 
        audio.BUS_I2S,
        {
            chip = audio_setup_param.model,
            i2cid = audio_setup_param.i2c_id,
            i2sid = I2S_ID
            -- voltage = audio.VOLTAGE_1800
        }
    )


    -- 设置音量
    audio.vol(MULTIMEDIA_ID, voice_vol)
    audio.micVol(MULTIMEDIA_ID, mic_vol)
    
    -- 检查芯片连接
    if audio_setup_param.model == "es8311" and not read_es8311_id() then
        log.error("ES8311通讯失败，请检查硬件")
        return false
    end

    -- 注册回调
    audio.on(MULTIMEDIA_ID, audio_callback)
    
    audio.pm(MULTIMEDIA_ID, audio.POWEROFF) -- audio.POWEROFF模式
    log.info("exaudio.setup", "声道数已设置为:"..audio_setup_param.channels.."(1=单声道,2=双声道)")
    return true
end

-- 模块接口：获取推荐的流式缓冲区大小
function exaudio.get_stream_buffer_size()
    if audio_play_param.stream_buffer_size > 0 then
        return audio_play_param.stream_buffer_size
    end

    -- 如果没有开始流式播放，返回一个基于默认参数的推荐值 
    local default_channels = audio_setup_param.channels or 1 
    local default_rate = I2S_SAMPLE_RATE 
    local default_depth = audio_setup_param.bits_per_sample 
    return calculate_buffer_size(default_rate, default_depth, default_channels)
end


-- 模块接口：初始化
function exaudio.setup(audioConfigs)
    -- 检查必要参数
    if not  audio  then
        log.error("不支持audio 库,请选择支持audio 的core")
        return false
    end
    if not audioConfigs or type(audioConfigs) ~= "table" then
        log.error("配置参数必须为table类型")
        return false
    end
    -- 检查codec型号
    if not audioConfigs.model or (audioConfigs.model ~= "es8311") then
        log.error("请指定正确的codec型号(es8311)")
        return false
    end
    audio_setup_param.model = audioConfigs.model
    -- 针对ES8311的特殊检查
    if audioConfigs.model == "es8311" then
        if not check_param(audioConfigs.i2c_id, "number", "i2c_id") then
            return false
        end
        audio_setup_param.i2c_id = audioConfigs.i2c_id
    end

    -- 检查功率放大器控制管脚
    if audioConfigs.pa_ctrl == nil then
        log.warn("pa_ctrl(功率放大器控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
    end
    audio_setup_param.pa_ctrl = audioConfigs.pa_ctrl

    -- 检查功率放大器控制管脚
    if audioConfigs.dac_ctrl == nil then
        log.warn("dac_ctrl(音频编解码控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
    end
    audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl


    -- 处理可选参数
    local optional_params = {
        {name = "dac_delay", type = "number"},
        {name = "pa_delay", type = "number"},
        {name = "dac_time_delay", type = "number"},
        {name = "bits_per_sample", type = "number"},
        {name = "pa_on_level", type = "number"},
        {name = "channels", type = "number"}
    }

    for _, param in ipairs(optional_params) do
        if audioConfigs[param.name] ~= nil then
            if check_param(audioConfigs[param.name], param.type, param.name) then
                -- 对channels参数进行验证，确保只能是1或2
                if param.name == "channels" then
                    if audioConfigs[param.name] == 1 or audioConfigs[param.name] == 2 then
                        audio_setup_param[param.name] = audioConfigs[param.name]
                    else
                        log.error("声道数必须为1(单声道)或2(双声道)")
                        return false
                    end
                else
                    audio_setup_param[param.name] = audioConfigs[param.name]
                end
            else
                return false
            end
        end
    end

    -- 确保采样位数和声道数有默认值
    audio_setup_param.bits_per_sample = audio_setup_param.bits_per_sample or 16
    audio_setup_param.channels = audio_setup_param.channels or 1
    return audio_setup()
end

-- 模块接口：开始播放
function exaudio.play_start(playConfigs)
    -- 恢复audio.RESUME工作模式
    audio.pm(MULTIMEDIA_ID, audio.RESUME)
    if not playConfigs or type(playConfigs) ~= "table" then
        log.error("播放配置必须为table类型")
        return false
    end

    -- 检查播放类型
    if not check_param(playConfigs.type, "number", "type") then
        log.error("type必须为数值(0:文件,1:TTS,2:流式)")
        return false
    end
    audio_play_param.type = playConfigs.type

    -- 处理优先级
    if playConfigs.priority ~= nil then
        if check_param(playConfigs.priority, "number", "priority") then
            if playConfigs.priority > audio_play_param.priority then
                log.error("是否完成播放",audio.isEnd(MULTIMEDIA_ID))
                if not audio.isEnd(MULTIMEDIA_ID) then
                    if audio.play(MULTIMEDIA_ID) ~= true then
                        return false
                    end
                    sys.waitUntil(EX_MSG_PLAY_DONE)
                end
                audio_play_param.priority = playConfigs.priority
            end
        else
            return false
        end
    end

    -- 处理不同播放类型
    local play_type = audio_play_param.type
    if play_type == 0 then  -- 文件播放
        if not playConfigs.content then
            log.error("文件播放需要指定content(文件路径或路径表)")
            return false
        end

        local content_type = type(playConfigs.content)
        if content_type == "table" then
            for _, path in ipairs(playConfigs.content) do
                if type(path) ~= "string" then
                    log.error("播放列表元素必须为字符串路径")
                    return false
                end
            end
        elseif content_type ~= "string" then
            log.error("文件播放content必须为字符串或路径表")
            return false
        end

        audio_play_param.content = playConfigs.content
        if audio.play(MULTIMEDIA_ID, audio_play_param.content) ~= true then
            return false
        end

    elseif play_type == 1 then  -- TTS播放
        if not audio.tts then
            log.error("本固件不支持TTS,请更换支持TTS 的固件")
            return false
        end
        if not check_param(playConfigs.content, "string", "content") then
            log.error("TTS播放content必须为字符串")
            return false
        end
        audio_play_param.content = playConfigs.content
        if audio.tts(MULTIMEDIA_ID, audio_play_param.content)  ~= true  then
            return false
        end

    elseif play_type == 2 then  -- 流式播放
        if not check_param(playConfigs.sampling_rate, "number", "sampling_rate") then
            return false
        end
        if not check_param(playConfigs.sampling_depth, "number", "sampling_depth") then
            return false
        end

        audio_play_param.content = playConfigs.content
        audio_play_param.sampling_rate = playConfigs.sampling_rate
        audio_play_param.sampling_depth = playConfigs.sampling_depth
        audio_play_param.channels = audio_setup_param.channels or 1

        -- 计算每个缓冲区的大小（字节数）
        audio_play_param.stream_buffer_size = calculate_buffer_size(
            audio_play_param.sampling_rate,
            audio_play_param.sampling_depth,
            audio_play_param.channels
        )

        if playConfigs.signed_or_unsigned ~= nil then
            audio_play_param.signed_or_unsigned = playConfigs.signed_or_unsigned
        end

        audio.start(
            MULTIMEDIA_ID, 
            audio.PCM, 
            audio_play_param.channels, 
            playConfigs.sampling_rate, 
            playConfigs.sampling_depth, 
            audio_play_param.signed_or_unsigned
        )

        -- 发送初始数据（使用计算出的缓冲区大小）
        if audio.write(MULTIMEDIA_ID, string.rep("\0", audio_play_param.stream_buffer_size)) ~= true then
            return false
        end
    end                        

    -- 处理回调函数
    if playConfigs.cbfnc ~= nil then
        if check_param(playConfigs.cbfnc, "function", "cbfnc") then
            audio_play_param.cbfnc = playConfigs.cbfnc
        else
            return false
        end
    else
        audio_play_param.cbfnc = nil
    end
    return true
end

-- 模块接口：流式播放数据写入
function exaudio.play_stream_write(data)
    audio_play_queue_push(data)
    return true
end

-- 模块接口：停止播放
function exaudio.play_stop()
    return audio.play(MULTIMEDIA_ID)
end

-- 模块接口：检查播放是否结束
function exaudio.is_end()
    return audio.isEnd(MULTIMEDIA_ID)
end

-- 模块接口：获取错误信息
function exaudio.get_error()
    return audio.getError(MULTIMEDIA_ID)
end

-- 模块接口：开始录音
function exaudio.record_start(recodConfigs)
    -- 恢复audio.RESUME工作模式
    audio.pm(MULTIMEDIA_ID, audio.RESUME)
    if not recodConfigs or type(recodConfigs) ~= "table" then
        log.error("录音配置必须为table类型")
        return false
    end
    -- 检查录音格式
    if recodConfigs.format == nil or type(recodConfigs.format) ~= "number" or recodConfigs.format > 6 then
        log.error("请指定正确的录音格式")
        return false
    end
    audio_record_param.format = recodConfigs.format

    -- 处理录音时间
    if recodConfigs.time ~= nil then
        if check_param(recodConfigs.time, "number", "time") then
            if recodConfigs.time == 0 then
                audio_record_param.time = 0
                log.warn("exaudio.record_start", "录音时间设置为0，将无限录音")
                log.warn("exaudio.record_start", "提示：请调用exaudio.record_stop()手动停止录音")
            elseif recodConfigs.time < 0 then
                log.error("录音时间不能为负数")
                return false
            else
                audio_record_param.time = recodConfigs.time
                log.info("exaudio.record_start", string.format("将录音%d秒", audio_record_param.time))
            end
        else
            return false
        end
    else
        audio_record_param.time = 0
        log.warn("exaudio.record_start", "未指定录音时间，将无限录音")
        log.warn("exaudio.record_start", "提示：请调用exaudio.record_stop()手动停止录音")
    end

    -- 处理存储路径/回调
    if not recodConfigs.path then
        log.error("必须指定录音路径或流式回调函数")
        return false
    end
    audio_record_param.path = recodConfigs.path

    -- 转换录音格式
    local recod_format, amr_quailty
    if audio_record_param.format == exaudio.AMR_NB then
        recod_format = audio.AMR_NB
        amr_quailty = 7
    elseif audio_record_param.format == exaudio.AMR_WB then
        recod_format = audio.AMR_WB
        amr_quailty = 8
    elseif audio_record_param.format == exaudio.PCM_8000 then
        recod_format = 8000
    elseif audio_record_param.format == exaudio.PCM_16000 then
        recod_format = 16000
    elseif audio_record_param.format == exaudio.PCM_24000 then
        recod_format = 24000
    elseif audio_record_param.format == exaudio.PCM_32000 then
        recod_format = 32000
    elseif audio_record_param.format == exaudio.PCM_48000 then
        recod_format = 48000
    end

    -- 处理回调函数
    if recodConfigs.cbfnc ~= nil then
        if check_param(recodConfigs.cbfnc, "function", "cbfnc") then
            audio_record_param.cbfnc = recodConfigs.cbfnc
        else
            return false
        end
    else
        audio_record_param.cbfnc = nil
    end
    -- 开始录音
    local path_type = type(audio_record_param.path)
    if path_type == "string" then
        return audio.record(
            MULTIMEDIA_ID, 
            recod_format, 
            audio_record_param.time, 
            amr_quailty, 
            audio_record_param.path
        )
    elseif path_type == "function" then
        -- 初始化缓冲区
        if not pcm_buff0 or not pcm_buff1 then
            pcm_buff0 = zbuff.create(16000)
            pcm_buff1 = zbuff.create(16000)
        end
        return audio.record(
            MULTIMEDIA_ID, 
            recod_format, 
            audio_record_param.time, 
            amr_quailty, 
            nil, 
            3,
            pcm_buff0,
            pcm_buff1
        )
    end
    log.error("录音路径必须为字符串或函数")
    return false
end

-- 模块接口：停止录音
function exaudio.record_stop()
    local result = audio.recordStop(MULTIMEDIA_ID)
    -- 处理剩余的录音数据
    if type(audio_record_param.path) == "function" then
        -- 检查两个PCM缓冲区
        local buffers = {pcm_buff0, pcm_buff1}
        for i, buff in ipairs(buffers) do
            if buff and buff:used() > 0 then
                log.info("exaudio.record_stop", string.format("处理缓冲区%d的剩余数据: %d字节", i, buff:used()))
                audio_record_param.path(buff, buff:used())
            end
        end
    end
    return result
end

-- 模块接口：设置音量
function exaudio.vol(play_volume)
    if check_param(play_volume, "number", "音量值") then
        return audio.vol(MULTIMEDIA_ID, play_volume)
    end
    return false
end

-- 模块接口：设置麦克风音量
function exaudio.mic_vol(record_volume)
    if check_param(record_volume, "number", "麦克风音量值") then
        return audio.micVol(MULTIMEDIA_ID, record_volume)  
    end
    return false
end

-- 获取当前声道数
function exaudio.get_channels()
    return audio_setup_param.channels
end

-- 模块接口：写入最后一块数据后，通知多媒体通道已经没有更多数据需要播放了
function exaudio.finish()
    if audio.finish then
        return audio.finish(MULTIMEDIA_ID)
    end
    return false
end

return exaudio
