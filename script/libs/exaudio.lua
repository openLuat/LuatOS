--[[
@module exaudio
@summary exaudio扩展库
@version 1.9
@date    2026.7.1
@author  拓毅恒
@updates
    v1.9 2026.7.1
        1. 调整音频框架默认选择：780EXX系列、8000系列默认旧框架
        2. 新增audio_mode参数，支持在setup中强制切换音频框架（"new"/"old"）
        3. 默认使用新音频框架的型号：Air8101、Air1601、Air1602
    v1.8 2026.5.11
        1. 新增TM8211音频编解码器支持，支持"es8311"、"tm8211"(I2S+外部Codec)和"dac"(内置DAC)两种类型
    v1.7 2026.4.22
        1. 新增多文件播放时的音频参数一致性检查，连续播放多个音频时添加限制，避免格式不同导致播放异常
    v1.6 2026.4.16
        1. 新增DAC模式支持，适配Air8101等使用内置DAC的模组，支持"es8311"(I2S+外部Codec)和"dac"(内置DAC)两种类型
        2. 优化参数检查逻辑，根据model自动选择初始化方式
        3. 流式播放统一使用队列+回调机制，通过audio.MORE_DATA事件驱动数据写入
    v1.5 2026.3.10
        1. 修改录音缓冲区使用逻辑，每次写完数据都清空缓冲区数据，释放内存，避免最后一段录音数据异常
    v1.4 2026.2.14
        1. 重构初始化i2s的逻辑，将接口给出让有录音或流式播放等需求的客户来自定义。
        3. 增大流式录音到文件缓冲区大小至48000，防止录音不完整。
    v1.3 2026.2.5
        1. 新增exaudio.pm()函数，可以在逻辑层直接调用exaudio.pm()来修改audio休眠模式。
        2. 重构exaudio.play_start()函数处理播放优先级逻辑，目前插入不同优先级的音频文件，会自动按照从高到底的顺序播放打断或播放。
        3. 重构exaudio.play_stop()函数，目前可以使用本函数来停止流式播放。
    v1.2 2026.1.6
        1. 新增双声道播放支持，exaudio.setup增加一个声道的配置参数
        2. 录音时间设置成0,会一直录音是正常的,api库已说明，这里再增加log打印提示
        3. 使用exaudio.record_stop()停止录音时，会有一小部分结尾的数据因为没有进入audio.on中的audio.RECORD_DATA事件而丢失，解决方案：
            在调用exaudio.record_stop()后，检查两个PCM缓冲区，确保所有数据都被处理
        4. exaudio.play_stream_write(data),流式音频数据,单次写入的长度修改为根据每秒播放数据量来确定
        5. 低功耗自动控制，exaudio.setup默认SHUTDOWN模式,exaudio.play_start和exaudio.record_start会自动切换到RESUME模式,播放完成或录音完成，会自动切换到SHUTDOWN模式
@usage

-- 版本更新说明
-- 版本号：202607021200
-- 1、更新时间：2026-07-02 12:00
-- 2、更新内容
--    新增exaudio.version()接口
--    支持exaudio库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月dd日hh时mm分发布的版本
]]
local exaudio = {}

-- ==================== 模组检测 ====================
-- 获取当前模组型号
local function get_module_type()
    local model = hmeta and hmeta.model and hmeta.model()
    if model then
        local model_lower = model:lower()
        if model_lower:find("air1601") then
            return "air1601"
        elseif model_lower:find("air1602") then
            return "air1602"
        elseif model_lower:find("air8101") then
            return "air8101"
        elseif model_lower:find("air780e") then
            return "air780e"       -- 780EXX系列
        elseif model_lower:find("air8000") then
            return "air8000"      -- 8000系列
        end
    end
    return "other"
end

-- 当前模组型号
local MODULE_TYPE = get_module_type()

-- 判断使用audio_v2还是audio
-- 780EXX系列、8000系列默认用audio，其余（8101、160X等）默认用audio_v2
local USE_AUDIO_V2 = (MODULE_TYPE ~= "air780e" and MODULE_TYPE ~= "air8000")

-- ==================== 常量定义 ====================
local I2S_ID = 0
local MULTIMEDIA_ID = 0
local EX_MSG_PLAY_DONE = "playDone"
local ES8311_ADDR = 0x18    -- 7位地址
local CHIP_ID_REG = 0x00    -- 芯片ID寄存器地址
local PCM_BUFFER_DURATION_MS = 50  -- 每个缓冲区的时长（毫秒）

-- audio_v2相关常量
local AUDIO_V2_DRIVER_ID = nil  -- audio_v2驱动ID，初始化时设置

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

-- ==================== 版本自适应 ====================
-- 根据版本号自适应设置dac_delay
local set_dac_delay = 0
local version = rtos.version()
local version_num = 0
if version then
    -- 从版本号字符串中提取数字部分
    local num_str = version:match("V(%d+)")
    if num_str then
        version_num = tonumber(num_str)
    end
end

if version_num and version_num >= 2026 then
    -- 固件版本≥V2026，dac_delay单位为100ms
    set_dac_delay = 6
else
    -- 固件版本＜V2026，dac_delay单位为1ms
    set_dac_delay = 600
end

-- ==================== 配置参数 ====================
local audio_setup_param = {
    model = "es8311",    -- 编解码器类型: "es8311"、"tm8211" 或 "dac"(内置DAC)
    i2c_id = 0,               -- i2c_id: 0,1
    pa_ctrl = 0,              -- 音频放大器电源控制管脚
    dac_ctrl = 0,             -- 音频编解码芯片电源控制管脚
        
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_delay = 10,           -- DAC启动后延迟打开PA的时间(ms)
    dac_time_delay = 600,      -- 播放完毕后PA与DAC关闭间隔(ms)
    pa_on_level = 1,          -- PA打开电平 1:高 0:低       
    channels = 1,             -- 声道数: 1:单声道 2:双声道
    
    -- I2S硬件配置参数
    i2s_mode = 0,                -- I2S模式: 0:主机 1:从机
    i2s_sample = 16000,     -- I2S采样率
    bits_per_sample = 16,     -- I2S采样位深
    i2s_comm_format = i2s and i2s.MODE_LSB or 0, -- I2S通信格式: MODE_I2S, MODE_LSB, MODE_MSB
    i2s_framebit = 16,       -- I2S通道位宽
    
    -- DAC硬件配置参数
    dac_ch = 0,               -- DAC通道号
    dac_chl = 0               -- DAC通道选择: 0=AUD_LN, 1=AUD_LP, 2=双通道
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

-- ==================== 内部变量 ====================
local pcm_buff0 = nil
local pcm_buff1 = nil
local voice_vol = 65
local mic_vol = 80

-- 定义全局队列表
local audio_play_queue = {
    requests = {},       -- 存储播放请求的数组，按优先级从高到低排序
    current_priority = 0 -- 当前播放的优先级
}

-- 定义全局流式数据队列
local audio_stream_queue = {
    data = {},           -- 存储字符串的数组
    sequenceIndex = 1    -- 用于跟踪插入顺序的索引
}

-- audio_v2相关变量
local audio_v2_request_index = nil  -- 当前播放请求的索引
local audio_v2_record_request_index = nil  -- 当前录音请求的索引
local audio_v2_stream_file_fp = nil  -- 流式播放文件句柄(audio_v2模式)
local audio_v2_stream_codec_id = nil  -- 流式播放codec_id(audio_v2模式)
local audio_v2_stream_data_start = nil  -- 流式播放数据起始位置(audio_v2模式)
local audio_v2_record_zbuff = nil  -- 录音zbuff（audio_v2回调模式）
local audio_v2_stream_end_marked = false  -- 标记流式结束（队列模式）
local audio_v2_es8311_drv = nil  -- ES8311驱动引用（audio_v2模式）

-- ==================== 工具函数 ====================
-- 参数检查
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

-- ==================== 队列操作函数 ====================
-- 向播放请求队列中添加请求（按优先级排序）
local function audio_play_queue_push_request(request)
    if type(request) == "table" and request.priority then
        -- 按优先级从高到低插入队列
        local inserted = false
        for i, existing_request in ipairs(audio_play_queue.requests) do
            if request.priority > existing_request.priority then
                table.insert(audio_play_queue.requests, i, request)
                inserted = true
                break
            end
        end
        
        if not inserted then
            table.insert(audio_play_queue.requests, request)
        end
        return true
    end
    return false
end

-- 从播放请求队列中取出最高优先级的请求
local function audio_play_queue_pop_request()
    if #audio_play_queue.requests > 0 then
        -- 取出并移除最高优先级的请求（队列第一个元素）
        local request = table.remove(audio_play_queue.requests, 1)
        audio_play_queue.current_priority = request.priority
        return request
    end
    audio_play_queue.current_priority = 0
    return nil
end

-- 向流式数据队列中添加字符串（按调用顺序插入）
local function audio_stream_queue_push(str)
    if type(str) == "string" then
        -- 存储格式: {index = 顺序索引, value = 字符串值}
        table.insert(audio_stream_queue.data, {
            index = audio_stream_queue.sequenceIndex,
            value = str
        })
        audio_stream_queue.sequenceIndex = audio_stream_queue.sequenceIndex + 1
        return true
    end
    return false
end

-- 从流式数据队列中取出最早插入的字符串（按顺序取出）
local function audio_stream_queue_pop()
    if #audio_stream_queue.data > 0 then
        -- 取出并移除第一个元素
        local item = table.remove(audio_stream_queue.data, 1)
        return item.value  -- 返回值
    end
    return nil
end

-- 清空所有队列数据
local function audio_queue_clear()
    -- 清空播放请求队列
    audio_play_queue.requests = {}
    audio_play_queue.current_priority = 0
    
    -- 清空流式数据队列
    audio_stream_queue.data = {}
    audio_stream_queue.sequenceIndex = 1
    return true
end

-- ==================== audio_v2 回调处理 ====================
local function audio_v2_callback(request_index, event, param)
    if event == audio_v2.REQUEST_START then
        audio_v2_request_index = request_index
        log.info("exaudio", "播放开始", request_index)
    elseif event == audio_v2.REQUEST_NEED_NEW_DATA then
        -- 流式播放需要更多数据
        -- 先调用input()检查FIFO剩余空间
        -- 优先使用文件句柄方式
        if audio_v2_stream_file_fp and request_index == audio_v2_request_index then
            -- 文件流模式：先获取FIFO剩余空间，再循环写入
            local result, write_len, free_len = audio_v2.input(request_index)
            if result and free_len then
                while free_len > 0 do
                    local data = audio_v2_stream_file_fp:read(4096)
                    if data then
                        if #data < 4096 then
                            result, write_len, free_len = audio_v2.input(request_index, data, true)
                            break
                        else
                            result, write_len, free_len = audio_v2.input(request_index, data, false)
                            if not result then break end
                        end
                    else
                        audio_v2.input(request_index, nil, true)
                        break
                    end
                end
            end
        else
            -- 队列模式：用户通过play_stream_write写入数据，循环填充直到FIFO满或队列空
            local result, write_len, free_len = audio_v2.input(request_index)
            if result and free_len then
                while free_len > 0 do
                    local data = audio_stream_queue_pop()
                    if data then
                        result, write_len, free_len = audio_v2.input(request_index, data, false)
                        if not result then break end
                        -- 处理partial write：audio_v2.input()只写入free_len能容纳的部分，剩余放回队列
                        if write_len and write_len < #data then
                            local remaining = data:sub(write_len + 1)
                            table.insert(audio_stream_queue.data, 1, {index = 0, value = remaining})
                            break
                        end
                    else
                        break
                    end
                end
            end
            -- while循环可能因partial write/FIFO满等原因退出而不走else分支，
            -- 所以此处统一检查：只有队列真正空了才发结束标记
            if audio_v2_stream_end_marked and #audio_stream_queue.data == 0 then
                audio_v2.input(request_index, "", true)
                audio_v2_stream_end_marked = false
            end
        end
    elseif event == audio_v2.REQUEST_GET_NEW_DATA then
        -- 录音数据
        if type(audio_record_param.path) == "function" and audio_v2_record_zbuff then
            local total = audio_v2_record_zbuff:used()
            if total > 0 then
                audio_record_param.path(audio_v2_record_zbuff, total)
                audio_v2_record_zbuff:del()
            end
        end
    elseif event == audio_v2.REQUEST_END then
        log.info("exaudio", "播放完毕", request_index)
        
        -- 判断是录音结束还是播放结束
        if audio_v2_record_request_index == request_index then
            -- 录音结束
            audio_v2_record_request_index = nil
            audio_v2_record_zbuff = nil
            if type(audio_record_param.cbfnc) == "function" then
                audio_record_param.cbfnc(exaudio.RECORD_DONE)
            end
            -- 录音不发布EX_MSG_PLAY_DONE
        elseif audio_v2_request_index == request_index then
            -- 播放结束
            -- 关闭文件句柄
            if audio_v2_stream_file_fp then
                audio_v2_stream_file_fp:close()
                audio_v2_stream_file_fp = nil
            end
            
            if type(audio_play_param.cbfnc) == "function" then
                audio_play_param.cbfnc(exaudio.PLAY_DONE)
            end
            
            -- audio_v2 自带优先级管理，下一个请求会自动播放
            audio_v2_request_index = nil
            audio_v2_stream_codec_id = nil
            audio_v2_stream_data_start = nil
            audio_v2_stream_end_marked = false
            audio_play_queue.current_priority = 0
            
            sys.publish(EX_MSG_PLAY_DONE)
        end
    end
end

-- ==================== audio 回调处理 ====================
local function audio_callback(id, event, point)
    if event == audio.MORE_DATA then
        -- 从队列取出数据并写入
        local data = audio_stream_queue_pop()
        if data then
            audio.write(MULTIMEDIA_ID, data)
        end
    elseif event == audio.DONE then
        if type(audio_play_param.cbfnc) == "function" then
            audio_play_param.cbfnc(exaudio.PLAY_DONE)
        end
        
        -- 检查是否有下一个播放请求
        if #audio_play_queue.requests > 0 then
            -- 播放下一个请求
            start_next_play()
        else
            -- 没有更多请求，清空流式播放数据队列并进入休眠
            audio_stream_queue.data = {}
            audio_stream_queue.sequenceIndex = 1
            audio.pm(MULTIMEDIA_ID, audio.SHUTDOWN) -- audio.SHUTDOWN模式
            audio_play_queue.current_priority = 0
        end
        
        sys.publish(EX_MSG_PLAY_DONE)
        
    elseif event == audio.RECORD_DATA then
        if type(audio_record_param.path) == "function" then
            local buff, len = point == 0 and pcm_buff0 or pcm_buff1,
                             point == 0 and pcm_buff0:used() or pcm_buff1:used()
            audio_record_param.path(buff, len)
            -- 清空缓冲区数据，释放内存
            if buff and buff.del then
                buff:del()
            end
        end
        
    elseif event == audio.RECORD_DONE then
        if type(audio_record_param.cbfnc) == "function" then
            audio_record_param.cbfnc(exaudio.RECORD_DONE)
        end

        audio.pm(MULTIMEDIA_ID, audio.SHUTDOWN) -- audio.SHUTDOWN模式
    end
end

-- ==================== 硬件初始化 ====================
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

-- audio_v2模式初始化
local function audio_v2_setup()
    -- 根据model进行不同的初始化
    if audio_setup_param.model == "dac" then
        -- DAC模式（Air1601等使用内置DAC的模组）
        log.info("exaudio.setup", "audio_v2 DAC模式初始化")
    elseif audio_setup_param.model == "es8311" then
        -- ES8311 I2S模式（Air780EHM等使用ES8311的模组）
        log.info("exaudio.setup", "audio_v2 ES8311模式初始化")
        
        -- I2C配置
        if not i2c.setup(audio_setup_param.i2c_id) then
            log.error("I2C初始化失败")
            return false
        end
    else
        log.error("audio_v2不支持的model:", audio_setup_param.model)
        return false
    end
    
    -- 检查audio_v2驱动管理API是否可用
    if audio_v2.make_probe_id and audio_v2.set_default_driver then
        -- 使用驱动管理API设置驱动
        local driver_probe_id
        if audio_setup_param.model == "dac" then
            -- 合成DAC驱动ID: DAC0播放, 无录音
            driver_probe_id = audio_v2.make_probe_id(
                audio_v2.DRIVER_TYPE_DAC, 0,  -- 发送: DAC0
                audio_v2.DRIVER_TYPE_NONE, 0   -- 接收: 无
            )
        elseif audio_setup_param.model == "es8311" then
            -- 合成I2S驱动ID: I2S0全双工(播放+录音)
            driver_probe_id = audio_v2.make_probe_id(
                audio_v2.DRIVER_TYPE_I2S, 0,  -- 发送: I2S0
                audio_v2.DRIVER_TYPE_I2S, 0   -- 接收: I2S0
            )
        end
        
        -- 设置默认驱动
        local set_ok = audio_v2.set_default_driver(driver_probe_id)
        if set_ok then
            log.info("exaudio.setup", "默认驱动已设置, probe_id:", driver_probe_id)
        else
            -- 设置失败，可能是驱动未注册，尝试继续
            log.warn("exaudio.setup", "设置默认驱动失败，尝试使用系统默认驱动")
        end
    else
        -- 固件不支持驱动管理API，使用默认驱动
        log.info("exaudio.setup", "使用audio_v2默认驱动")
    end
    
    -- 注册audio_v2事件回调
    audio_v2.on(audio_v2_callback)
    
    -- 配置PA电源控制
    if audio_setup_param.pa_ctrl and audio_setup_param.pa_ctrl > 0 then
        audio_v2.config_pa_power_ctrl(
            true,  -- 使能PA电源控制
            audio_setup_param.pa_ctrl,  -- PA控制引脚
            audio_setup_param.pa_on_level,  -- PA使能电平
            audio_setup_param.pa_delay or 200  -- 延时
        )
    end
    
    -- ES8311模式下：Codec电源由手动GPIO控制，防止断电后ES8311寄存器丢失
    if audio_setup_param.model == "es8311" then
        -- 手动打开CODEC电源并保持常开
        if audio_setup_param.dac_ctrl and audio_setup_param.dac_ctrl > 0 then
            gpio.setup(audio_setup_param.dac_ctrl, 1)
        end
        
        -- 配置audio_v2 I2S参数
        audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
        audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, audio_setup_param.i2s_framebit or 16, audio_setup_param.i2s_framebit or 16)
        audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)
        
        -- 初始化ES8311编解码器
        local es8311_ok
        es8311_ok, audio_v2_es8311_drv = pcall(require, "es8311")
        if es8311_ok and audio_v2_es8311_drv then
            sys.wait(10)
            
            -- 检查ES8311芯片连接
            if not read_es8311_id() then
                log.error("ES8311通讯失败，请检查硬件")
                return false
            end
            
            if audio_v2_es8311_drv.init(audio_setup_param.i2c_id) then
                audio_v2_es8311_drv.set_sample_rate(audio_setup_param.i2c_id, audio_setup_param.i2s_sample or 16000, 256)
                audio_v2_es8311_drv.set_data_bits(audio_setup_param.i2c_id, audio_setup_param.bits_per_sample or 16)
                audio_v2_es8311_drv.set_format(audio_setup_param.i2c_id)
                audio_v2_es8311_drv.resume(audio_setup_param.i2c_id)
                audio_v2_es8311_drv.set_voice_vol(audio_setup_param.i2c_id, 60)
                audio_v2_es8311_drv.set_mic_vol(audio_setup_param.i2c_id, mic_vol)
                log.info("exaudio.setup", "ES8311初始化完成")
            else
                log.error("ES8311芯片初始化失败")
                return false
            end
        else
            log.warn("exaudio.setup", "未找到es8311驱动模块")
        end


        -- ES8311模式下初始化完成后进入低功耗休眠（只关PA，不关Codec电源，防止配置丢失）
        audio_v2.shutdown(false, false, true)
    else
        -- DAC等其他模式下初始化完成后进入低功耗休眠
        audio_v2.shutdown(false, true, true)
    end
    log.info("exaudio.setup", "audio_v2初始化完成")
    return true
end

-- audio模式初始化
local function audio_setup()
    -- 根据model选择初始化方式
    if audio_setup_param.model == "dac" then
        -- DAC模式初始化
        log.info("exaudio.setup", "使用DAC模式初始化")
        
        -- 配置音频通道
        audio.config(
            MULTIMEDIA_ID, 
            audio_setup_param.pa_ctrl,      -- PA控制引脚
            audio_setup_param.pa_on_level,  -- PA打开电平
            0,                              -- dac_delay: 固定为0
            audio_setup_param.pa_delay      -- PA延时
        )
        
        -- 设置总线为DAC模式
        audio.setBus(
            MULTIMEDIA_ID, 
            audio.BUS_DAC,
            {
                dacid = audio_setup_param.dac_ch
            }
        )
        
        log.info("exaudio.setup", "DAC通道已设置为:"..audio_setup_param.dac_ch)
    elseif audio_setup_param.model == "tm8211" then
        -- TM8211模式初始化 (I2S，无需I2C)
        log.info("exaudio.setup", "使用TM8211模式初始化")
        
        -- 初始化I2S
        local I2S_channel_format = audio_setup_param.channels == 2 and i2s.STEREO or i2s.MONO_R

        local result, data = i2s.setup(
            I2S_ID,  -- I2S的通道号
            audio_setup_param.i2s_mode,  -- I2S主从模式
            audio_setup_param.i2s_sample,  -- I2S采样率
            audio_setup_param.bits_per_sample,  -- I2S采样位深
            I2S_channel_format, -- 声道
            audio_setup_param.i2s_comm_format, -- I2S通讯格式
            audio_setup_param.i2s_framebit  -- I2S通道位宽
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
                i2sid = I2S_ID
                -- voltage = audio.VOLTAGE_1800
            }
        )
        -- TM8211无需I2C芯片ID检查
    else
        -- ES8311 I2S模式初始化
        log.info("exaudio.setup", "使用ES8311 I2S模式初始化")
        
        -- I2C配置
        if not i2c.setup(audio_setup_param.i2c_id, i2c.FAST) then
            log.error("I2C初始化失败")
            return false
        end
        -- 初始化I2S
        local I2S_channel_format = audio_setup_param.channels == 2 and i2s.STEREO or i2s.MONO_R

        local result, data = i2s.setup(
            I2S_ID,  -- I2S的通道号
            audio_setup_param.i2s_mode,  -- I2S主从模式
            audio_setup_param.i2s_sample,  -- I2S采样率
            audio_setup_param.bits_per_sample,  -- I2S采样位深
            I2S_channel_format, -- 声道
            audio_setup_param.i2s_comm_format, -- I2S通讯格式
            audio_setup_param.i2s_framebit  -- I2S通道位宽
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

        -- 检查芯片连接
        if audio_setup_param.model == "es8311" and not read_es8311_id() then
            log.error("ES8311通讯失败，请检查硬件")
            return false
        end
    end

    -- 设置音量
    audio.vol(MULTIMEDIA_ID, voice_vol)
    if audio.micVol then
        audio.micVol(MULTIMEDIA_ID, mic_vol)
    end

    -- 注册回调
    audio.on(MULTIMEDIA_ID, audio_callback)
    
    audio.pm(MULTIMEDIA_ID, audio.SHUTDOWN) -- audio.SHUTDOWN模式
    log.info("exaudio.setup", "声道数已设置为:"..audio_setup_param.channels.."(1=单声道,2=双声道)")
    return true
end

-- ==================== 播放控制 ====================
-- audio模式开始播放
local function audio_legacy_start_next_play()
    local request = audio_play_queue_pop_request()
    if not request then
        return false
    end
    
    local playConfigs = request.configs
    audio_play_param.priority = request.priority
    
    -- 处理不同播放类型
    local play_type = playConfigs.type
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
            -- 多文件播放时检查音频参数一致性
            if #playConfigs.content > 1 then
                -- 根据文件扩展名获取codec类型
                local function get_codec_type(file_path)
                    local ext = file_path:match("%.([^.]+)$")
                    if ext then
                        ext = ext:lower()
                        if ext == "mp3" then
                            return codec.MP3
                        elseif ext == "amr" then
                            return codec.AMR
                        end
                    end
                    return nil
                end
                
                local codec_type = get_codec_type(playConfigs.content[1])
                if not codec_type then
                    log.error("无法识别第一个音频文件格式:", playConfigs.content[1])
                    return false
                end
                
                -- 创建临时decoder用于获取音频信息
                local coder = codec.create(codec_type, true)
                if not coder then
                    log.error("无法创建codec decoder, 类型:", codec_type)
                    return false
                end
                local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed = codec.info(coder, playConfigs.content[1])
                if not result then
                    log.error("无法获取第一个音频文件信息:", playConfigs.content[1])
                    codec.release(coder)
                    return false
                end
                for i = 2, #playConfigs.content do
                    local codec_type2 = get_codec_type(playConfigs.content[i])
                    if codec_type2 ~= codec_type then
                        log.error("多文件播放要求格式一致，文件", playConfigs.content[i], 
                            "格式与第一个文件格式不同")
                        codec.release(coder)
                        return false
                    end
                    local result2, audio_format2, num_channels2, sample_rate2, bits_per_sample2, is_signed2 = codec.info(coder, playConfigs.content[i])
                    if not result2 then
                        log.error("无法获取音频文件信息:", playConfigs.content[i])
                        codec.release(coder)
                        return false
                    end
                    if sample_rate2 ~= sample_rate then
                        log.error("多文件播放要求采样率一致，文件", playConfigs.content[i], 
                            "采样率", sample_rate2, "与第一个文件采样率", sample_rate, "不同")
                        codec.release(coder)
                        return false
                    end
                    if num_channels2 ~= num_channels then
                        log.error("多文件播放要求声道数一致，文件", playConfigs.content[i],
                            "声道数", num_channels2, "与第一个文件声道数", num_channels, "不同")
                        codec.release(coder)
                        return false
                    end
                    if bits_per_sample2 ~= bits_per_sample then
                        log.error("多文件播放要求采样位深一致，文件", playConfigs.content[i],
                            "位深", bits_per_sample2, "与第一个文件位深", bits_per_sample, "不同")
                        codec.release(coder)
                        return false
                    end
                end
                codec.release(coder)
                log.info("多文件播放参数检查通过，采样率:", sample_rate,
                    "声道数:", num_channels, "位深:", bits_per_sample)
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

-- ==================== 模块接口 ====================
-- 获取推荐的流式缓冲区大小
function exaudio.get_stream_buffer_size()
    if USE_AUDIO_V2 then
        -- audio_v2模式下返回推荐值
        local default_channels = audio_setup_param.channels or 1 
        local default_rate = audio_setup_param.i2s_sample 
        local default_depth = audio_setup_param.bits_per_sample 
        return calculate_buffer_size(default_rate, default_depth, default_channels)
    end
    
    if audio_play_param.stream_buffer_size > 0 then
        return audio_play_param.stream_buffer_size
    end

    -- 如果没有开始流式播放，返回一个基于默认参数的推荐值 
    local default_channels = audio_setup_param.channels or 1 
    local default_rate = audio_setup_param.i2s_sample 
    local default_depth = audio_setup_param.bits_per_sample 
    return calculate_buffer_size(default_rate, default_depth, default_channels)
end

-- 初始化
function exaudio.setup(audioConfigs)
    if not audioConfigs or type(audioConfigs) ~= "table" then
        log.error("配置参数必须为table类型")
        return false
    end

    -- audio_mode参数处理
    -- 780EXX系列、8000系列可通过audio_mode="new"切换到新音频框架
    -- 8101、160X系列只能用新框架，audio_mode参数无效
    if audioConfigs.audio_mode == "new" and not USE_AUDIO_V2 then
        USE_AUDIO_V2 = true
        log.info("exaudio.setup", "audio_mode=new，切换到新音频框架")
    end
    if audioConfigs.audio_mode == "old" and USE_AUDIO_V2 then
        log.warn("exaudio.setup", "当前模组仅支持新音频框架， audio_mode = old 不生效")
    end

    log.info("exaudio.setup", "当前使用" .. (USE_AUDIO_V2 and "新" or "旧") .. "音频框架")

    -- 检查必要参数
    if USE_AUDIO_V2 then
        if not audio_v2 then
            log.error("不支持audio_v2 库,请选择支持audio_v2 的core")
            return false
        end
    else
        if not audio then
            log.error("不支持audio 库,请选择支持audio 的core")
            return false
        end
    end

    -- 检查编解码器型号
    if audioConfigs.model then
        if audioConfigs.model ~= "es8311" and audioConfigs.model ~= "dac" and audioConfigs.model ~= "tm8211" then
            log.error("请指定正确的model: es8311、tm8211 或 dac")
            return false
        end
        audio_setup_param.model = audioConfigs.model
    end
    
    -- 根据model进行参数检查
    if audio_setup_param.model == "dac" then
        -- DAC模式
        if audioConfigs.dac_ch ~= nil then
            audio_setup_param.dac_ch = audioConfigs.dac_ch
        end
        if audioConfigs.dac_chl ~= nil then
            audio_setup_param.dac_chl = audioConfigs.dac_chl
        end
        log.info("exaudio.setup", "DAC模式 - 通道:"..audio_setup_param.dac_ch..", 声道:"..audio_setup_param.channels)
    elseif audio_setup_param.model == "tm8211" then
        -- TM8211模式 (I2S，无需I2C)
        log.info("exaudio.setup", "TM8211模式 - 声道:"..audio_setup_param.channels)
        
        -- TM8211 默认使用 MODE_MSB 格式
        if audioConfigs.i2s_comm_format == nil then
            audio_setup_param.i2s_comm_format = i2s and i2s.MODE_MSB or 0
            log.info("exaudio.setup", "TM8211使用默认MODE_MSB格式")
        end
        
        -- 检查功率放大器控制管脚
        if audioConfigs.dac_ctrl == nil then
            log.warn("dac_ctrl(音频编解码控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
        end
        audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl
    else
        -- ES8311 I2S模式
        if not audio_setup_param.model or (audio_setup_param.model ~= "es8311") then
            log.error("请指定正确的model(es8311)")
            return false
        end
        -- 针对ES8311的特殊检查
        if not check_param(audioConfigs.i2c_id, "number", "i2c_id") then
            return false
        end
        audio_setup_param.i2c_id = audioConfigs.i2c_id

        -- 检查功率放大器控制管脚
        if audioConfigs.dac_ctrl == nil then
            log.warn("dac_ctrl(音频编解码控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
        end
        audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl
    end

    -- 检查功率放大器控制管脚
    if audioConfigs.pa_ctrl == nil then
        log.warn("pa_ctrl(功率放大器控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
    end
    audio_setup_param.pa_ctrl = audioConfigs.pa_ctrl

    -- 处理可选参数
    local optional_params = {
        {name = "dac_delay", type = "number"},
        {name = "pa_delay", type = "number"},
        {name = "dac_time_delay", type = "number"},
        {name = "bits_per_sample", type = "number"},
        {name = "pa_on_level", type = "number"},
        {name = "channels", type = "number"},
        {name = "i2s_sample", type = "number"},      -- I2S采样率
        {name = "i2s_framebit", type = "number"},     -- I2S通道位宽
        {name = "i2s_mode", type = "number"},         -- I2S模式
        {name = "i2s_comm_format", type = "number"},  -- I2S通信格式
        {name = "dac_ch", type = "number"},           -- DAC通道
        {name = "dac_chl", type = "number"}           -- DAC通道选择
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
    
    -- 根据模式选择初始化方式
    if USE_AUDIO_V2 then
        return audio_v2_setup()
    else
        return audio_setup()
    end
end

-- 开始播放
function exaudio.play_start(playConfigs)
    if USE_AUDIO_V2 then
        -- audio_v2模式播放
        if not playConfigs or type(playConfigs) ~= "table" then
            log.error("播放配置必须为table类型")
            return false
        end

        -- 检查播放类型
        if not check_param(playConfigs.type, "number", "type") then
            log.error("type必须为数值(0:文件,1:TTS,2:流式)")
            return false
        end

        -- 设置默认优先级
        playConfigs.priority = playConfigs.priority or 0
        
        -- audio_v2播放
        local play_type = playConfigs.type
        local ok, req_id = false, nil
        
        if play_type == 0 then  -- 文件播放
            if not playConfigs.content then
                log.error("文件播放需要指定content(文件路径或路径表)")
                return false
            end
            
            -- 使用audio_v2.play播放文件
            ok, req_id = audio_v2.play(
                playConfigs.content, 
                playConfigs.err_stop ~= false,  -- 默认true
                playConfigs.priority,
                playConfigs.driver_probe_id,
                playConfigs.codec_id
            )
            if ok then
                audio_v2_request_index = req_id
                audio_play_param.cbfnc = playConfigs.cbfnc
            end
            return ok
            
        elseif play_type == 1 then  -- TTS播放
            if not check_param(playConfigs.content, "string", "content") then
                log.error("TTS播放content必须为字符串")
                return false
            end
            
            ok, req_id = audio_v2.tts(
                playConfigs.content, 
                playConfigs.priority,
                playConfigs.driver_probe_id
            )
            if ok then
                audio_v2_request_index = req_id
                audio_play_param.cbfnc = playConfigs.cbfnc
            end
            return ok
            
        elseif play_type == 2 then  -- 流式播放
            -- audio_v2流式播放
            -- 未指定codec_id时默认0(RAW/PCM)
            if not playConfigs.codec_id then
                --流式播放未指定codec_id时默认RAW/PCM
                playConfigs.codec_id = 0
            end
            
            -- 兼容旧版参数名
            local sample_rate = playConfigs.sample_rate or playConfigs.sampling_rate
            local data_bits = playConfigs.data_bits or playConfigs.sampling_depth or 16
            local is_signed
            if playConfigs.is_signed ~= nil then
                is_signed = playConfigs.is_signed  -- 保持boolean不变，直接传给stream
            elseif playConfigs.signed_or_unsigned ~= nil then
                is_signed = playConfigs.signed_or_unsigned
            else
                is_signed = true  -- 默认有符号
            end
            local channel_nums = playConfigs.channel_nums or playConfigs.channels or 1
            local priority = playConfigs.priority or 0
            local driver_probe_id = playConfigs.driver_probe_id or AUDIO_V2_DRIVER_ID
            
            -- 对于MP3/AMR/WAV格式，从文件解析真实采样率
            local file_path = playConfigs.file_path
            if file_path and (playConfigs.codec_id == 5 or playConfigs.codec_id == 2 or playConfigs.codec_id == 3 or playConfigs.codec_id == 1) then
                local fp = io.open(file_path, "rb")
                if fp then
                    local file_data = fp:read(12)
                    if file_data and #file_data > 0 then
                        local no_error, next_pos, need_len, parsed_sample_rate, parsed_data_bits, parsed_channel_nums, parsed_is_signed = 
                            audio_v2.get_play_info(file_data, playConfigs.codec_id, 0)
                        if no_error then
                            if parsed_sample_rate and parsed_sample_rate > 0 then
                                sample_rate = parsed_sample_rate
                                data_bits = parsed_data_bits or data_bits
                                channel_nums = parsed_channel_nums or channel_nums
                                if parsed_is_signed ~= nil then
                                    is_signed = parsed_is_signed  -- 保持boolean
                                end
                                log.info("exaudio", "从文件解析到采样率:", sample_rate, "bits:", data_bits, 
                                         "ch:", channel_nums, "signed:", is_signed)
                            else
                                -- sample_rate为0，重试
                                local retry_count = 0
                                while retry_count < 6 and no_error and (not parsed_sample_rate or parsed_sample_rate == 0) do
                                    log.info("exaudio", "seek", next_pos, "need", need_len)
                                    fp:seek("set", next_pos)
                                    file_data = fp:read(need_len)
                                    if file_data then
                                        no_error, next_pos, need_len, parsed_sample_rate, parsed_data_bits, parsed_channel_nums, parsed_is_signed = 
                                            audio_v2.get_play_info(file_data, playConfigs.codec_id, next_pos)
                                        retry_count = retry_count + 1
                                    else
                                        break
                                    end
                                end
                                if no_error and parsed_sample_rate and parsed_sample_rate > 0 then
                                    sample_rate = parsed_sample_rate
                                    data_bits = parsed_data_bits or data_bits
                                    channel_nums = parsed_channel_nums or channel_nums
                                    if parsed_is_signed ~= nil then
                                        is_signed = parsed_is_signed  -- 保持boolean
                                    end
                                    log.info("exaudio", "从文件解析到采样率:", sample_rate, "bits:", data_bits, 
                                             "ch:", channel_nums, "signed:", is_signed, "retries:", retry_count)
                                else
                                    log.warn("exaudio", "无法从文件解析采样率，使用默认值", "retries:", retry_count)
                                end
                            end
                        else
                            log.warn("exaudio", "get_play_info解析失败，使用默认值")
                        end
                    end
                    fp:close()
                end
            end
            
            -- 默认采样率
            if not sample_rate or sample_rate <= 0 then
                if playConfigs.codec_id == 0 then
                    sample_rate = 16000
                elseif playConfigs.codec_id == 1 then
                    sample_rate = 44100
                elseif playConfigs.codec_id == 2 then
                    sample_rate = 8000
                elseif playConfigs.codec_id == 3 then
                    sample_rate = 16000
                elseif playConfigs.codec_id == 5 then
                    sample_rate = 44100
                else
                    sample_rate = 16000
                end
                log.info("exaudio", "codec_id", playConfigs.codec_id, "使用默认采样率:", sample_rate)
            end
            
            log.info("exaudio", "调用stream: cid=", playConfigs.codec_id, "sr=", sample_rate, 
                     "bits=", data_bits, "ch=", channel_nums, "sig=", is_signed, "pri=", priority)
            ok, req_id = audio_v2.stream(
                playConfigs.codec_id,
                sample_rate,
                data_bits,
                channel_nums,
                is_signed,
                priority
            )
            log.info("exaudio", "stream返回: ok=", ok, "req_id=", req_id)
            
            if ok then
                audio_v2_request_index = req_id
                audio_v2_stream_codec_id = playConfigs.codec_id
                audio_play_param.cbfnc = playConfigs.cbfnc
                
                -- 如果有file_path，打开文件用于回调中循环读取
                if file_path then
                    local fp = io.open(file_path, "rb")
                    if fp then
                        -- 跳转到数据起始位置
                        local data_start = playConfigs.data_start or 0
                        if data_start > 0 then
                            fp:seek("set", data_start)
                        end
                        audio_v2_stream_file_fp = fp
                        audio_v2_stream_data_start = data_start
                        log.info("exaudio", "流式播放文件已打开:", file_path, "data_start:", data_start)
                    else
                        log.warn("exaudio", "无法打开流式播放文件:", file_path)
                    end
                end
                
                log.info("exaudio", "流式播放启动成功, request_index:", req_id, 
                         "采样率:", sample_rate, "codec_id:", playConfigs.codec_id)
            else
                log.error("exaudio", "流式播放启动失败")
            end
            return ok
        end
        
        return false
    else
        -- audio模式播放
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

        -- 设置默认优先级
        playConfigs.priority = playConfigs.priority or 0
        
        -- 创建播放请求
        local request = {
            priority = playConfigs.priority,
            configs = playConfigs
        }
        
        -- 检查是否正在播放
        if not audio.isEnd(MULTIMEDIA_ID) then
            -- 如果新请求的优先级更高，则打断当前播放
            if playConfigs.priority > audio_play_queue.current_priority then
                -- 停止当前播放
                if audio.play(MULTIMEDIA_ID) ~= true then
                    return false
                end
                sys.waitUntil(EX_MSG_PLAY_DONE)
                
                -- 将新请求加入队列并立即播放
                audio_play_queue_push_request(request)
                return audio_legacy_start_next_play()
            else
                -- 优先级不够高，将请求加入队列等待
                audio_play_queue_push_request(request)
                return true
            end
        else
            -- 没有正在播放，将请求加入队列并立即播放
            audio_play_queue_push_request(request)
            return audio_legacy_start_next_play()
        end
    end
end

-- 流式播放数据写入
-- @param data 音频数据(string/zbuff)
-- @param is_end 是否为最后一帧数据，true表示播放结束(仅audio_v2模式支持)
-- @return ok 是否成功
-- @return written 实际写入的字节数(audio_v2)
-- @return free_len FIFO剩余空间(audio_v2)
function exaudio.play_stream_write(data, is_end)
    if USE_AUDIO_V2 then
        -- audio_v2模式：入队列，由NEED_NEW_DATA回调批量写入FIFO
        if not audio_v2_request_index then
            log.error("audio_v2流式播放未启动")
            return false
        end
        
        -- 如果有文件句柄，由回调自动处理，忽略用户的手动写入
        if audio_v2_stream_file_fp then
            log.info("exaudio", "文件流模式，忽略手动写入")
            return true
        end
        
        -- 数据入队列
        audio_stream_queue_push(data)
        if is_end then
            -- is_end=true标记在队列数据被回调消耗完后生效
            audio_v2_stream_end_marked = true
        end
        
        -- 立即尝试刷新队列：入队后马上尝试写入audio_v2 FIFO，
        -- 避免等NEED_NEW_DATA 250ms后才轮到写入导致FIFO欠载/噪音。
        -- 数据安全留在队列等NEED_NEW_DATA写入。
        local flush_ok, flush_free = audio_v2.input(audio_v2_request_index)
        if flush_ok and flush_free and flush_free > 0 then
            while flush_free > 0 do
                local qdata = audio_stream_queue_pop()
                if qdata then
                    local _, flush_written, flush_free = audio_v2.input(audio_v2_request_index, qdata, false)
                    if flush_written and flush_written < #qdata then
                        -- partial write: 剩余放回队列头部
                        local remain = qdata:sub(flush_written + 1)
                        table.insert(audio_stream_queue.data, 1, {index = 0, value = remain})
                        break
                    end
                else
                    break
                end
            end
        end
        
        return true
    end
    
    -- audio模式：插入队列，由audio.MORE_DATA回调处理
    audio_stream_queue_push(data)
    return true
end

-- 停止播放
function exaudio.play_stop(stopConfigs)
    if USE_AUDIO_V2 then
        -- audio_v2停止播放
        if audio_v2_request_index then
            -- 关闭文件句柄
            if audio_v2_stream_file_fp then
                audio_v2_stream_file_fp:close()
                audio_v2_stream_file_fp = nil
            end
            
            audio_v2.stop(audio_v2_request_index)
            audio_v2_request_index = nil
            audio_v2_stream_codec_id = nil
            audio_v2_stream_data_start = nil
            audio_play_queue.current_priority = 0
            audio_v2.shutdown(false, true, true)
            return true
        end
        return false
    end

    -- 强制要求传入配置表参数
    if not stopConfigs or type(stopConfigs) ~= "table" then
        log.error("停止播放必须传入配置表参数，格式: {type = 0|1|2}")
        log.error("type参数说明: 0=文件播放, 1=TTS播放, 2=流式播放")
        return false
    end

    -- 检查播放类型参数
    if not check_param(stopConfigs.type, "number", "type") then
        log.error("停止播放需要指定type参数(0:文件,1:TTS,2:流式)")
        return false
    end
    
    -- 检查播放类型参数
    if not check_param(stopConfigs.type, "number", "type") then
        log.error("停止播放需要指定type参数(0:文件,1:TTS,2:流式)")
        return false
    end
    
    local stop_type = stopConfigs.type
    
    -- 根据播放类型使用不同的停止方法
    if stop_type == 2 then  -- 流式播放
        -- 流式播放使用audio.stop()停止
        local result = audio.stop(MULTIMEDIA_ID)
        if result then
            -- 清空流式数据队列
            audio_stream_queue.data = {}
            audio_stream_queue.sequenceIndex = 1
            audio_play_queue.current_priority = 0
            audio.pm(MULTIMEDIA_ID, audio.SHUTDOWN)
        end
        return result
    else  -- 文件播放或TTS播放
        -- 文件播放和TTS播放使用audio.play()停止
        local result = audio.play(MULTIMEDIA_ID)
        if result then
            -- 只有当停止的是当前播放类型时才清空状态
            audio_play_queue.current_priority = 0
            audio.pm(MULTIMEDIA_ID, audio.SHUTDOWN)
        end
        return result
    end
end

-- 检查播放是否结束
function exaudio.is_end()
    if USE_AUDIO_V2 then
        -- audio_v2使用is_all_done判断是否所有请求结束
        return audio_v2.is_all_done()
    end
    return audio.isEnd(MULTIMEDIA_ID)
end

-- 获取错误信息
function exaudio.get_error()
    if USE_AUDIO_V2 then
        -- audio_v2暂无错误获取接口
        return nil
    end
    return audio.getError(MULTIMEDIA_ID)
end

-- audio_v2录音格式转码表
local audio_v2_record_codec_map = {
    [exaudio.AMR_NB]   = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_AMR_NB or 2, sr = 8000,  bits = 16 },
    [exaudio.AMR_WB]   = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_AMR_WB or 3, sr = 16000, bits = 16 },
    [exaudio.PCM_8000]  = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 8000,  bits = 16 },
    [exaudio.PCM_16000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 16000, bits = 16 },
    [exaudio.PCM_24000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 24000, bits = 16 },
    [exaudio.PCM_32000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 32000, bits = 16 },
    [exaudio.PCM_48000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 48000, bits = 16 },
}

-- 开始录音
function exaudio.record_start(recodConfigs)
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

    -- 处理回调函数
    if recodConfigs.cbfnc ~= nil then
        if type(recodConfigs.cbfnc) ~= "function" then
            log.error("cbfnc必须为函数类型")
            return false
        end
        audio_record_param.cbfnc = recodConfigs.cbfnc
    else
        audio_record_param.cbfnc = nil
    end

    if USE_AUDIO_V2 then
        local fmt = audio_v2_record_codec_map[audio_record_param.format]
        if not fmt then
            log.error("不支持的录音格式")
            return false
        end
        
        local path_type = type(audio_record_param.path)
        local ok, req_id
        
        if path_type == "string" then
            ok, req_id = audio_v2.record(
                audio_record_param.path,  -- 文件路径
                audio_record_param.time,  -- 录制时长（秒）
                fmt.codec_id,             -- 编解码器ID
                0,                        -- priority
                fmt.sr,                   -- 采样率
                fmt.bits,                 -- 位深
                audio_setup_param.channels or 1  -- 声道数
            )
        elseif path_type == "function" then
            -- 创建录音zbuff
            audio_v2_record_zbuff = zbuff.create(48000)
            ok, req_id = audio_v2.record(
                audio_v2_record_zbuff,    -- zbuff缓冲区
                audio_record_param.time,  -- 录制时长（秒）
                fmt.codec_id,             -- 编解码器ID
                0,                        -- priority
                fmt.sr,                   -- 采样率
                fmt.bits,                 -- 位深
                audio_setup_param.channels or 1  -- 声道数
            )
        else
            log.error("录音路径必须为字符串或函数")
            return false
        end
        
        if ok then
            audio_v2_record_request_index = req_id
            log.info("exaudio", "录音已开始, req_id:", req_id)
        else
            audio_v2_record_zbuff = nil
            log.error("exaudio", "录音启动失败")
        end
        return ok
    end
    
    -- ========== audio模式录音 ==========
    -- 恢复audio.RESUME工作模式
    audio.pm(MULTIMEDIA_ID, audio.RESUME)

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
            pcm_buff0 = zbuff.create(48000)
            pcm_buff1 = zbuff.create(48000)
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

-- 停止录音
function exaudio.record_stop()
    if USE_AUDIO_V2 then
        if audio_v2_record_request_index then
            -- 停止录音前，如果有回调模式，处理zbuff中剩余数据
            if type(audio_record_param.path) == "function" and audio_v2_record_zbuff then
                local left = audio_v2_record_zbuff:used()
                if left > 0 then
                    audio_record_param.path(audio_v2_record_zbuff, left)
                    audio_v2_record_zbuff:del()
                end
                -- zbuff模式必须调stop让C层停止
                audio_v2.stop(audio_v2_record_request_index)
                audio_v2_record_request_index = nil
                audio_v2_record_zbuff = nil
                return true
            end
            -- 文件录音：不调stop，让C层自然结束（timeout到期后自动回收REQUEST_END）。
            -- 不清空audio_v2_record_request_index，等待REQUEST_END回调来清空。
            -- 调stop会导致文件未保存/REQUEST_END不触发，只轮询is_all_done从不主动stop录音。
            return true
        end
        return false
    end
    
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

-- 设置音量
-- @param play_volume 音量值
-- @param driver_probe_id 驱动ID(可选,audio_v2模式支持)
-- @return 是否成功
function exaudio.vol(play_volume, driver_probe_id)
    if USE_AUDIO_V2 then
        -- audio_v2音量设置使用soft_volume
        if check_param(play_volume, "number", "音量值") then
            return audio_v2.soft_volume(play_volume, driver_probe_id)
        end
        return false
    end
    
    if check_param(play_volume, "number", "音量值") then
        return audio.vol(MULTIMEDIA_ID, play_volume)
    end
    return false
end

-- 设置麦克风音量
function exaudio.mic_vol(record_volume)
    if USE_AUDIO_V2 then
        if not audio_v2_es8311_drv then
            local ok
            ok, audio_v2_es8311_drv = pcall(require, "es8311")
        end
        if audio_v2_es8311_drv then
            audio_v2_es8311_drv.set_mic_vol(audio_setup_param.i2c_id or 0, record_volume)
            mic_vol = record_volume
            return true
        end
        return false
    end
    
    if check_param(record_volume, "number", "麦克风音量值") then
        return audio.micVol(MULTIMEDIA_ID, record_volume)  
    end
    return false
end

-- 获取当前声道数
function exaudio.get_channels()
    return audio_setup_param.channels
end

-- 写入最后一块数据后，通知多媒体通道已经没有更多数据需要播放了
-- audio_v2模式下，此函数用于标记流式播放结束
-- @param data 最后一帧数据(可选,audio_v2流式播放)
-- @return 是否成功
function exaudio.finish(data)
    if USE_AUDIO_V2 then
        -- audio_v2流式播放结束
        if audio_v2_request_index then
            -- 如果有文件句柄，由回调自动处理结束，这里不干预
            if audio_v2_stream_file_fp then
                log.info("exaudio", "文件流模式，等待回调自动处理结束")
                return true
            end
            
            -- 队列模式：入队列后标记结束，由NEED_NEW_DATA回调在队列清空后发结束信号
            if data then
                audio_stream_queue_push(data)
            end
            audio_v2_stream_end_marked = true
            return true
        end
        return false
    end
    
    if audio.finish then
        return audio.finish(MULTIMEDIA_ID)
    end
    return false
end

-- 休眠控制(audio模式)
-- @param pm_mode 休眠模式: audio.SHUTDOWN/audio.RESUME
-- @return 是否成功
function exaudio.pm(pm_mode)
    if USE_AUDIO_V2 then
        log.warn("audio_v2模式请使用exaudio.shutdown()进行电源管理")
        return false
    end
    
    if audio.pm then
        return audio.pm(MULTIMEDIA_ID, pm_mode)
    end
    return false
end

-- 休眠控制(audio_v2模式)
-- @api exaudio.shutdown(driver_power_off, codec_power_off, pa_power_off, driver_probe_id)
-- @param driver_power_off boolean 是否关闭驱动。true会调用stop+deactivate停止驱动并释放资源
-- @param codec_power_off boolean 是否关闭外部CODEC电源（需事先通过setup配置引脚）
-- @param pa_power_off boolean 是否关闭PA功放电源（需事先通过setup配置引脚）
-- @param driver_probe_id int 可选。驱动ID，不使用默认驱动时填写
-- @return boolean 是否成功
-- @usage
-- -- 完整下电：关闭PA → 关闭CODEC → 停止驱动
-- exaudio.shutdown(true, true, true)
-- -- 仅关闭PA，保持驱动和CODEC运行
-- exaudio.shutdown(false, false, true)
-- -- 对指定驱动执行下电
-- local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0, audio_v2.DRIVER_TYPE_I2S, 0)
-- exaudio.shutdown(true, true, true, pid)
function exaudio.shutdown(driver_power_off, codec_power_off, pa_power_off, driver_probe_id)
    if not USE_AUDIO_V2 then
        log.warn("audio模式请使用exaudio.pm()进行休眠控制")
        return false
    end
    
    if not audio_v2 then
        log.error("audio_v2模块未加载")
        return false
    end
    
    -- 如果所有参数都为nil，则执行完整下电
    local do_driver = driver_power_off ~= false
    local do_codec = codec_power_off ~= false
    local do_pa = pa_power_off ~= false
    
    audio_v2.shutdown(do_driver, do_codec, do_pa, driver_probe_id)
    return true
end

-- 获取当前使用的音频模式
function exaudio.get_audio_mode()
    return USE_AUDIO_V2 and "audio_v2" or "audio"
end

-- ==================== 流式播放辅助函数（仅audio_v2模式支持） ====================

--[[
@description 从音频文件解析播放信息（采样率、位宽、声道数等）
@api exaudio.parse_audio_info(file_path, codec_id)
@string file_path 音频文件路径
@number codec_id 编解码器ID (0=PCM, 1=WAV, 2=AMR_NB, 3=AMR_WB, 5=MP3)
@return table 成功返回包含音频信息的table，失败返回nil
@usage
local info = exaudio.parse_audio_info("/luadb/test.mp3", 5)
if info then
    log.info("采样率:", info.sample_rate)
    log.info("位宽:", info.data_bits)
    log.info("声道数:", info.channel_nums)
end
注意：此函数仅在audio_v2模式下可用
]]
function exaudio.parse_audio_info(file_path, codec_id)
    if not file_path or type(file_path) ~= "string" then
        log.error("parse_audio_info: file_path must be string")
        return nil
    end
    
    if not codec_id or type(codec_id) ~= "number" then
        log.error("parse_audio_info: codec_id must be number")
        return nil
    end
    
    -- PCM格式是原始音频数据，没有文件头，直接返回默认值
    if codec_id == 0 then
        log.info("parse_audio_info: PCM format, use default values")
        return {sample_rate = 16000, data_bits = 16, channel_nums = 1, is_signed = true, data_start = 0}
    end
    
    local fp = io.open(file_path, "rb")
    if not fp then
        log.error("parse_audio_info: cannot open file", file_path)
        return nil
    end
    
    -- 先读取12字节进行初始解析
    local file_data = fp:read(12)
    if not file_data or #file_data == 0 then
        log.error("parse_audio_info: file read failed", file_path)
        fp:close()
        return nil
    end
    
    -- 使用audio_v2.get_play_info解析文件头
    local no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = 
        audio_v2.get_play_info(file_data, codec_id, 0)
    
    log.info("parse_audio_info", "get_play_info result:", no_error, "sample_rate:", sample_rate, "next_pos:", next_pos, "need_len:", need_len)
    
    if no_error then
        if sample_rate and sample_rate > 0 then
            -- 解析成功，跳转到数据起始位置
            log.info("exaudio.parse_audio_info", file_path, "sample_rate:", sample_rate, 
                     "bits:", data_bits, "channels:", channel_nums)
            fp:close()
            return {
                sample_rate = sample_rate,
                data_bits = data_bits or 16,
                channel_nums = channel_nums or 1,
                is_signed = (is_signed ~= false),
                data_start = next_pos
            }
        else
            -- sample_rate为0或nil，需要读取更多数据重试
            log.info("parse_audio_info", "sample_rate is", sample_rate, "need retry")
            local retry_count = 0
            while retry_count < 6 and no_error and (not sample_rate or sample_rate == 0) do
                log.info("parse_audio_info", "seek", next_pos, "need", need_len)
                fp:seek("set", next_pos)
                file_data = fp:read(need_len)
                if file_data then
                    log.info("parse_audio_info", "read", #file_data)
                    no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = 
                        audio_v2.get_play_info(file_data, codec_id, next_pos)
                    retry_count = retry_count + 1
                else
                    break
                end
            end
            
            if no_error and sample_rate and sample_rate > 0 then
                log.info("exaudio.parse_audio_info", file_path, "sample_rate:", sample_rate, 
                         "bits:", data_bits, "channels:", channel_nums, "retries:", retry_count)
                fp:close()
                return {
                    sample_rate = sample_rate,
                    data_bits = data_bits or 16,
                    channel_nums = channel_nums or 1,
                    is_signed = is_signed ~= false,
                    data_start = next_pos
                }
            else
                log.warn("parse_audio_info: retry failed, use default values", file_path, "retries:", retry_count)
            end
        end
    else
        log.warn("parse_audio_info: get_play_info error", file_path)
    end
    
    -- 解析失败，返回false
    log.info("parse_audio_info: parse failed, return nil for", file_path)
    fp:close()
    return false
end

--[[
@description 获取推荐流式播放缓冲区大小
@api exaudio.get_stream_buffer_size_by_codec(codec_id)
@number codec_id 编解码器ID (0=PCM, 1=WAV, 2=AMR_NB, 3=AMR_WB, 5=MP3)
@return number 推荐的缓冲区大小（字节）
@usage
local buffer_size = exaudio.get_stream_buffer_size_by_codec(5)  -- MP3推荐大小
注意：此函数仅在audio_v2模式下可用
]]
function exaudio.get_stream_buffer_size_by_codec(codec_id)
    local buffer_sizes = {
        [0] = 4096,   -- PCM: 4KB
        [1] = 4096,   -- WAV: 4KB
        [2] = 640,    -- AMR_NB: 640字节（帧较小）
        [3] = 640,    -- AMR_WB: 640字节
        [5] = 1792,   -- MP3: 1792字节（帧大小）
    }
    return buffer_sizes[codec_id] or 4096
end

--[[
@description 获取流式播放推荐等待时间
@api exaudio.get_stream_wait_ms(codec_id)
@number codec_id 编解码器ID (0=PCM, 1=WAV, 2=AMR_NB, 3=AMR_WB, 5=MP3)
@return number 推荐的等待时间（毫秒）
@usage
local wait_ms = exaudio.get_stream_wait_ms(5)  -- MP3推荐等待时间
注意：此函数仅在audio_v2模式下可用
]]
function exaudio.get_stream_wait_ms(codec_id)
    local wait_times = {
        [0] = 20,     -- PCM: 20ms
        [1] = 20,     -- WAV: 20ms
        [2] = 80,     -- AMR_NB: 80ms
        [3] = 80,     -- AMR_WB: 80ms
        [5] = 100,    -- MP3: 100ms
    }
    return wait_times[codec_id] or 20
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202606300102"
@usage
exaudio.version()
]]
function exaudio.version()
    return "202607021200"
end

log.debug("exaudio", "version -> " .. exaudio.version())

return exaudio
